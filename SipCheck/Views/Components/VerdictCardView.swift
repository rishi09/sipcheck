import SwiftUI

struct VerdictCardView: View {
    let scan: Scan
    /// Set when this beer matches one already in the user's history, so the
    /// card can say "you've had this" instead of treating it as new.
    var previousDrink: Drink? = nil
    /// True while background network enrichment is still filling in details.
    /// The verdict itself is final the moment the card renders — this only
    /// signals that copy/style/ABV may still improve in place.
    var refining: Bool = false
    /// Optimistic saved state: flips the Save button to a confirmed "Saved"
    /// immediately on tap (the silent button was the app's worst UX moment).
    var savedForLater: Bool = false
    var onSaveForLater: (() -> Void)?
    var onScanAnother: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: - Beer Photo Area
                ZStack(alignment: .bottom) {
                    // Placeholder photo area (~40% of screen)
                    Rectangle()
                        .fill(SipColors.surface)
                        .frame(height: 320)
                        .overlay(
                            VStack(spacing: 12) {
                                Image(systemName: "mug.fill")
                                    .font(.system(size: 64))
                                    .foregroundColor(SipColors.textSecondary.opacity(0.5))
                                Text(scan.beerName)
                                    .font(SipTypography.headline)
                                    .foregroundColor(SipColors.textSecondary.opacity(0.7))
                            }
                        )

                    // Dark overlay gradient at bottom of photo
                    LinearGradient(
                        colors: [Color.clear, SipColors.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                }

                // MARK: - Verdict Badge
                Text(verdictDisplayText)
                    .font(SipTypography.display)
                    .foregroundColor(verdictColor)
                    .padding(.top, 8)
                    .accessibilityIdentifier("verdictText")

                // MARK: - Refining Hint
                if refining {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("refining details…")
                            .font(SipTypography.caption)
                            .foregroundColor(SipColors.textSecondary)
                    }
                    .padding(.top, 6)
                    .transition(.opacity)
                    .accessibilityIdentifier("refiningHint")
                }

                // MARK: - Already-Tried Banner
                if let previous = previousDrink {
                    HStack(spacing: 8) {
                        Text(previous.rating.emoji)
                        Text("You've had this one — you rated it \(previous.rating.displayName.lowercased())")
                            .font(SipTypography.caption)
                            .foregroundColor(SipColors.textPrimary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(SipColors.surface))
                    .padding(.top, 12)
                    .accessibilityIdentifier("alreadyTriedBanner")
                }

                // MARK: - Beer Info
                VStack(spacing: 6) {
                    Text(scan.beerName)
                        .font(SipTypography.title)
                        .foregroundColor(SipColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(beerMetadata)
                        .font(SipTypography.subhead)
                        .foregroundColor(SipColors.textSecondary)
                }
                .padding(.top, 12)

                // MARK: - Explanation
                Text(scan.explanation)
                    .font(SipTypography.body)
                    .foregroundColor(SipColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    // Enrichment swaps this copy in place — cross-fade, don't jump.
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: scan.explanation)

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
                    .padding(.top, 16)
                }

                // MARK: - Action Buttons
                HStack(spacing: 16) {
                    // Save for Later — outline style; flips to a filled "Saved"
                    // confirmation instantly (optimistic — the store write and
                    // notification scheduling ride along behind it).
                    Button(action: { onSaveForLater?() }) {
                        HStack(spacing: 6) {
                            if savedForLater {
                                Image(systemName: "checkmark")
                            }
                            Text(savedForLater ? "Saved" : "Save for Later")
                        }
                        .font(SipTypography.headline)
                        .foregroundColor(savedForLater ? SipColors.background : SipColors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(savedForLater ? SipColors.primary : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(SipColors.primary, lineWidth: savedForLater ? 0 : 2)
                        )
                    }
                    .disabled(savedForLater)
                    .animation(.easeInOut(duration: 0.2), value: savedForLater)
                    .accessibilityIdentifier("saveForLater")

                    // Scan Another — filled style
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
                .padding(.horizontal, 24)
                .padding(.top, 32)
                // Clear the floating tab bar — 40 buried the buttons beneath it
                .padding(.bottom, 110)
            }
        }
        .background(verdictGradientBackground)
        .accessibilityIdentifier("verdictCard")
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
            colors: [verdictColor.opacity(0.3), SipColors.background],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }

    private var beerMetadata: String {
        var parts: [String] = []
        if let style = scan.style {
            parts.append(style)
        }
        if let abv = scan.abv {
            parts.append(String(format: "%.1f%% ABV", abv))
        }
        return parts.joined(separator: " \u{00B7} ")
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
