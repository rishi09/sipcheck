import SwiftUI
import AVFoundation
import PhotosUI
import VisionKit

struct LiveScanCapture {
    let text: String
    let image: UIImage?
}

/// Full-screen, shutterless label/menu scanner. VisionKit continuously tracks
/// visible text; once the transcript has held steady briefly we capture the
/// current frame and hand both signals to the normal resolver.
struct LiveScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (LiveScanCapture) -> Void
    @State private var status = "Looking for text..."
    @State private var errorMessage: String?

    static var isSupported: Bool {
        DataScannerViewController.isSupported
    }

    static var isAvailable: Bool {
        DataScannerViewController.isAvailable
    }

    var body: some View {
        ZStack {
            if Self.isSupported {
                LiveScannerController(status: $status) { capture in
                    onCapture(capture)
                    dismiss()
                } onError: { message in
                    errorMessage = message
                }
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            GeometryReader { proxy in
                let region = LiveScanLayout.region(in: proxy.size)
                RoundedRectangle(cornerRadius: SipRadius.card, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.75), lineWidth: 2)
                    .frame(width: region.width, height: region.height)
                    .position(x: region.midX, y: region.midY)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.62)))
                    }
                    .accessibilityLabel("Close scanner")

                    Spacer()

                    Text("Scan")
                        .font(SipTypography.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, SipSpacing.l)
                .padding(.top, SipSpacing.s)

                Spacer()

                Text(errorMessage ?? status)
                    .font(SipTypography.subhead)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, SipSpacing.l)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(Color.black.opacity(0.68)))
                    .padding(.horizontal, SipSpacing.xl)
                    .padding(.bottom, SipSpacing.xxl)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("liveScanner")
        .onAppear {
            if !Self.isSupported {
                status = "Scanner preview"
            }
        }
    }
}

/// Pure transcript cleanup kept separate from VisionKit's delegate so ordering
/// and acceptance rules can be regression-tested without a camera.
enum LiveScanText {
    static func transcript(from lines: [(text: String, bounds: CGRect)]) -> String {
        let cleaned = lines.compactMap { line -> (String, CGRect)? in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return (text, line.bounds)
        }
        .sorted { lhs, rhs in
            if abs(lhs.1.midY - rhs.1.midY) > 8 {
                return lhs.1.midY < rhs.1.midY
            }
            return lhs.1.midX < rhs.1.midX
        }
        return cleaned.map(\.0).joined(separator: "\n")
    }

    static func isUsable(_ text: String) -> Bool {
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        let generic: Set<String> = [
            "abv", "alc", "ale", "ales", "beer", "beers", "bottle", "can",
            "draft", "ipa", "lager", "menu", "oz", "porter", "stout", "tap"
        ]
        return words.contains { $0.count >= 4 && !generic.contains($0) }
    }
}

enum LiveScanLayout {
    static func region(in size: CGSize) -> CGRect {
        let width = max(160, min(330, size.width - 48))
        let height = max(220, min(430, size.height * 0.48))
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }
}

private struct LiveScannerController: UIViewControllerRepresentable {
    @Binding var status: String
    let onCapture: (LiveScanCapture) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["en-US"])],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner

        DispatchQueue.main.async {
            if scanner.view.bounds.width > 0, scanner.view.bounds.height > 0 {
                scanner.regionOfInterest = LiveScanLayout.region(in: scanner.view.bounds.size)
            }
            do {
                try scanner.startScanning()
            } catch {
                onError("Camera scanner unavailable. Close and try again.")
            }
        }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        guard scanner.view.bounds.width > 0, scanner.view.bounds.height > 0 else { return }
        let region = LiveScanLayout.region(in: scanner.view.bounds.size)
        if scanner.regionOfInterest != region {
            scanner.regionOfInterest = region
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        coordinator.cancelPendingCapture()
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: LiveScannerController
        weak var scanner: DataScannerViewController?
        private var pendingCapture: Task<Void, Never>?
        private var candidateText = ""
        private var delivered = false

        init(parent: LiveScannerController) {
            self.parent = parent
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            consider(allItems, in: dataScanner)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didUpdate updatedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            consider(allItems, in: dataScanner)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didRemove removedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            consider(allItems, in: dataScanner)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            cancelPendingCapture()
            parent.onError("Camera scanner unavailable. Close and try again.")
        }

        func cancelPendingCapture() {
            pendingCapture?.cancel()
            pendingCapture = nil
        }

        private func consider(_ items: [RecognizedItem], in scanner: DataScannerViewController) {
            guard !delivered else { return }
            let lines: [(text: String, bounds: CGRect)] = items.compactMap { item in
                guard case .text(let recognized) = item else { return nil }
                let bounds = recognized.bounds
                let corners = [bounds.topLeft, bounds.topRight, bounds.bottomLeft, bounds.bottomRight]
                let minX = corners.map(\.x).min() ?? 0
                let maxX = corners.map(\.x).max() ?? 0
                let minY = corners.map(\.y).min() ?? 0
                let maxY = corners.map(\.y).max() ?? 0
                return (recognized.transcript, CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
            }
            let text = LiveScanText.transcript(from: lines)
            guard LiveScanText.isUsable(text) else {
                candidateText = ""
                cancelPendingCapture()
                parent.status = "Looking for text..."
                return
            }
            guard text != candidateText else { return }

            candidateText = text
            cancelPendingCapture()
            parent.status = "Hold steady..."
            pendingCapture = Task { [weak self, weak scanner] in
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard let self, let scanner, !Task.isCancelled,
                      !self.delivered, self.candidateText == text else { return }
                self.delivered = true
                self.parent.status = "Got it"
                let image = try? await scanner.capturePhoto()
                guard !Task.isCancelled else { return }
                scanner.stopScanning()
                self.parent.onCapture(LiveScanCapture(text: text, image: image))
            }
        }
    }
}

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
