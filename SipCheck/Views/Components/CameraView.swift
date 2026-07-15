import SwiftUI
import AVFoundation
import PhotosUI

struct CameraView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.capturedImage = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Camera button that handles permission and shows camera
struct CameraCaptureButton: View {
    @Binding var capturedImage: UIImage?
    @State private var showingCamera = false
    @State private var showingPermissionAlert = false

    var body: some View {
        VStack(spacing: SipSpacing.s) {
            // Sits inside AddBeerView's Form (opaque row), not over a live feed.
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    checkCameraPermission()
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                }
                .buttonStyle(SipPrimaryButtonStyle())
            }

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                PhotoLibraryButton(title: "Choose from Library", capturedImage: $capturedImage)
                    .buttonStyle(SipSecondaryButtonStyle())
            } else {
                PhotoLibraryButton(title: "Choose Beer Photo", capturedImage: $capturedImage)
                    .buttonStyle(SipPrimaryButtonStyle())
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraView(capturedImage: $capturedImage)
        }
        .alert("Camera Access Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable camera access in Settings to scan beer labels.")
        }
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showingCamera = true
                    } else {
                        // Surface the alert instead of silently doing nothing
                        // (intended behavior change, ordered by spec §3 WO-7).
                        showingPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showingPermissionAlert = true
        @unknown default:
            break
        }
    }
}

/// Shared photo-library input for simulator testing and existing label/menu
/// photos. Both camera and library paths write the same `capturedImage` binding,
/// so downstream OCR and persistence behavior stays identical.
struct PhotoLibraryButton: View {
    let title: String
    @Binding var capturedImage: UIImage?
    @State private var selection: PhotosPickerItem?
    @State private var isLoading = false

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            HStack(spacing: SipSpacing.s) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "photo.on.rectangle")
                }
                Text(isLoading ? "Loading Photo..." : title)
            }
        }
        .disabled(isLoading)
        .accessibilityIdentifier("chooseBeerPhoto")
        .onChange(of: selection) { _, item in
            guard let item else { return }
            isLoading = true
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                let image = data.flatMap(UIImage.init(data:))
                await MainActor.run {
                    if let image { capturedImage = image }
                    selection = nil
                    isLoading = false
                }
            }
        }
    }
}
