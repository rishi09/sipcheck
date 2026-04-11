import SwiftUI

struct VerdictCardView: View {
    let scan: Scan
    var onSaveForLater: (() -> Void)?
    var onScanAnother: (() -> Void)?

    @State private var verdictAppeared = false
    @State private var savedToList = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: - Verdict Hero
                VStack(spacing: 16) {
                    // Verdict pill — the hero element
                    Text(verdictDisplayText)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 22)
                                .fill(verdictColor)
                                .shadow(color: verdictColor.opacity(0.55), radius: 20, y: 10)
                        )
                        .scaleEffect(verdictAppeared ? 1.0 : 0.6)
                        .opacity(verdictAppeared ? 1.0 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.65), value: verdictAppeared)
                        .accessibilityIdentifier("verdictText")

                    // Beer name
                    Text(scan.beerName)
                        .font(SipTypography.title)
                        .foregroundColor(SipColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .opacity(verdictAppeared ? 1.0 : 0)
                        .animation(.easeOut(duration: 0.3).delay(0.2), value: verdictAppeared)

                    if !beerMetadata.isEmpty {
                        Text(beerMetadata)
                            .font(SipTypography.subhead)
                            .foregroundColor(SipColors.textSecondary)
                            .opacity(verdictAppeared ? 1.0 : 0)
                            .animation(.easeOut(duration: 0.3).delay(0.25), value: verdictAppeared)
                    }
                }
                .padding(.top, 52)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)

                // MARK: - Explanation
                Text(scan.explanation)
                    .font(SipTypography.body)
                    .foregroundColor(SipColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .opacity(verdictAppeared ? 1.0 : 0)
                    .animation(.easeOut(duration: 0.3).delay(0.3), value: verdictAppeared)

                // MARK: - Origin Card
                if let origin = scan.origin, !origin.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(SipColors.textSecondary)
                            .font(.system(size: 16))
                        Text(origin)
                            .font(SipTypography.caption)
                            .foregroundColor(SipColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(SipColors.surface)
                    .cornerRadius(12)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .opacity(verdictAppeared ? 1.0 : 0)
                    .animation(.easeOut(duration: 0.3).delay(0.35), value: verdictAppeared)
                }
                // MARK: - Action Buttons
                VStack(spacing: 12) {
                    // Share verdict — top button
                    ShareLink(item: shareText) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Verdict")
                        }
                        .font(SipTypography.headline)
                        .foregroundColor(SipColors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(SipColors.primary, lineWidth: 1.5)
                        )
                    }

                    HStack(spacing: 12) {
                        // Add to My List — outline
                        Button(action: {
                            onSaveForLater?()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                savedToList = true
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                savedToList = false
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: savedToList ? "checkmark" : "bookmark")
                                Text(savedToList ? "Saved!" : "Add to My List")
                            }
                            .font(SipTypography.headline)
                            .foregroundColor(savedToList ? SipColors.verdictTryIt : SipColors.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(savedToList ? SipColors.verdictTryIt : SipColors.primary, lineWidth: 1.5)
                            )
                        }
                        .accessibilityIdentifier("saveForLater")

                        // Scan Another — filled
                        Button(action: { onScanAnother?() }) {
                            Text("Scan Another")
                                .font(SipTypography.headline)
                                .foregroundColor(SipColors.background)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(SipColors.primary)
                                )
                        }
                        .accessibilityIdentifier("scanAnother")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 40)
                .opacity(verdictAppeared ? 1.0 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.4), value: verdictAppeared)
            }
        }
        .background(verdictGradientBackground)
        .accessibilityIdentifier("verdictCard")
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                verdictAppeared = true
                // Haptic on verdict reveal
                switch scan.verdict {
                case .tryIt:
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                case .skipIt:
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                case .yourCall:
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var verdictDisplayText: String {
        switch scan.verdict {
        case .tryIt: return "TRY IT"
        case .skipIt: return "SKIP IT"
        case .yourCall: return "YOUR CALL"
        }
    }

    private var verdictColor: Color {
        switch scan.verdict {
        case .tryIt: return SipColors.verdictTryIt
        case .skipIt: return SipColors.verdictSkipIt
        case .yourCall: return SipColors.verdictYourCall
        }
    }

    private var verdictGradientBackground: some View {
        LinearGradient(
            colors: [verdictColor.opacity(0.25), SipColors.background],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }

    private var beerMetadata: String {
        var parts: [String] = []
        if let style = scan.style { parts.append(style) }
        if let abv = scan.abv { parts.append(String(format: "%.1f%% ABV", abv)) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var shareText: String {
        var lines = ["\(verdictDisplayText) 🍺 \(scan.beerName)"]
        if let style = scan.style { lines.append(style) }
        if !scan.explanation.isEmpty {
            lines.append("\n\(scan.explanation)")
        }
        lines.append("\n— via SipCheck")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Preview

struct VerdictCardView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            VerdictCardView(scan: ScanStore.seedScans[0])
                .previewDisplayName("Try It")

            VerdictCardView(scan: ScanStore.seedScans[1])
                .previewDisplayName("Skip It")

            VerdictCardView(scan: ScanStore.seedScans[2])
                .previewDisplayName("Your Call")
        }
    }
}
