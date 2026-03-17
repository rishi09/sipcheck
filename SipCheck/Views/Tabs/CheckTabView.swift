import SwiftUI

struct CheckTabView: View {
    @EnvironmentObject var scanStore: ScanStore
    @State private var showingResult = false

    var body: some View {
        ZStack {
            SipColors.background
                .ignoresSafeArea()

            if let latestScan = scanStore.scans.first {
                // Show verdict card for most recent scan
                VerdictCardView(
                    scan: latestScan,
                    onSaveForLater: {
                        saveForLater(latestScan)
                    },
                    onScanAnother: {
                        // Camera/scanning flow will come in a later sprint
                    }
                )
            } else {
                // No scans yet — show scan prompt
                scanPromptView
            }
        }
        .accessibilityIdentifier("checkTab")
    }

    // MARK: - Scan Prompt (Empty State)

    private var scanPromptView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(SipColors.textSecondary)

            VStack(spacing: 8) {
                Text("Scan a Beer")
                    .font(SipTypography.title)
                    .foregroundColor(SipColors.textPrimary)

                Text("Point your camera at a beer label to get a personalized recommendation")
                    .font(SipTypography.body)
                    .foregroundColor(SipColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: {
                // Camera flow will come in a later sprint
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                    Text("Scan Now")
                }
                .font(SipTypography.headline)
                .foregroundColor(SipColors.background)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(SipColors.primary)
                )
            }
        }
    }

    // MARK: - Actions

    private func saveForLater(_ scan: Scan) {
        var updated = scan
        updated.wantToTry = true
        scanStore.updateScan(updated)
    }
}

struct CheckTabView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // With seed data
            CheckTabView()
                .environmentObject(
                    ScanStore(
                        storageDirectory: FileManager.default.temporaryDirectory,
                        useSeedData: true
                    )
                )
                .previewDisplayName("With Scan Result")

            // Empty state
            CheckTabView()
                .environmentObject(
                    ScanStore(
                        storageDirectory: FileManager.default.temporaryDirectory,
                        useSeedData: false
                    )
                )
                .previewDisplayName("Empty State")
        }
    }
}
