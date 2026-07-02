import SwiftUI

/// Where the resolved beer identity came from — drives the provenance segment
/// on the metadata line. WO-3 plumbs the real value from `ScanOutcome.source`;
/// until then the default `nil` omits the segment entirely.
enum VerdictProvenance {
    case label
    case catalog
    case bestGuess

    var copy: String {
        switch self {
        case .label:     return "from label"
        case .catalog:   return "catalog match"
        case .bestGuess: return "our best guess"
        }
    }
}

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
    /// Provenance of the resolved identity. Defaults nil (line segment omitted)
    /// until WO-3's plumbing lands.
    var source: VerdictProvenance? = nil
    /// Resolver confidence 0–1. Below 0.9 the card surfaces a "Best match"
    /// caption and (if alternates exist) a "Not this one?" escape hatch —
    /// after the verdict, never as a pre-verdict gate.
    var confidence: Double? = nil
    /// Fuzzy alternate candidate names, revealed by "Not this one?".
    var alternates: [String] = []
    /// Structured pro/con signals for the because-rows. Empty renders nothing —
    /// blocked on the scan track's TasteScorer refactor.
    var becauseRows: [(text: String, isPro: Bool)] = []
    var onSaveForLater: (() -> Void)?
    var onScanAnother: (() -> Void)?
    /// Called when the user picks a fuzzy alternate; wiring lands with WO-3.
    var onSelectAlternate: ((String) -> Void)? = nil

    @ScaledMetric(relativeTo: .largeTitle) private var verdictSize: CGFloat = 48
    @State private var heroRevealed = false
    @State private var showingAlternates = false
    @State private var showingLogSheet = false
    @State private var becauseExpanded = false

    private var verdictStyle: VerdictStyle {
        VerdictStyle.style(for: scan.verdict)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                verdictHero
                identityBlock
                    .padding(.horizontal, SipSpacing.l)

                // MARK: - History Capsule (highest-trust line — elevated chip, SF thumb, no raw emoji)
                if let previous = previousDrink {
                    HStack(spacing: SipSpacing.s) {
                        Image(systemName: ratingSymbol(for: previous.rating))
                            .font(SipTypography.caption)
                            .foregroundColor(ratingColor(for: previous.rating))
                            .accessibilityHidden(true)
                        Text(historyLine(for: previous.rating))
                            .font(SipTypography.caption)
                            .foregroundColor(SipColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, SipSpacing.l)
                    .padding(.vertical, SipSpacing.m)
                    .background(Capsule().fill(SipColors.surfaceElevated))
                    .padding(.top, SipSpacing.m)
                    .accessibilityIdentifier("alreadyTriedBanner")
                }

                // MARK: - Low-Confidence Escape Hatch (post-verdict, never a gate)
                if let confidence, confidence < 0.9 {
                    VStack(spacing: SipSpacing.xs) {
                        Text("Best match: \(scan.beerName) (\(Int(confidence * 100))%)")
                            .font(SipTypography.caption)
                            .foregroundColor(SipColors.textSecondary)
                        if !alternates.isEmpty {
                            Button("Not this one?") {
                                withAnimation(.smooth) { showingAlternates.toggle() }
                            }
                            .buttonStyle(SipQuietButtonStyle())
                            if showingAlternates {
                                VStack(spacing: SipSpacing.xs) {
                                    ForEach(alternates, id: \.self) { candidate in
                                        Button(candidate) {
                                            onSelectAlternate?(candidate)
                                        }
                                        .buttonStyle(SipChipStyle(isSelected: false))
                                    }
                                }
                                .transition(.opacity)
                            }
                        }
                    }
                    .padding(.top, SipSpacing.m)
                }

                // MARK: - Explanation
                Text(scan.explanation)
                    .font(SipTypography.body)
                    .foregroundColor(SipColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, SipSpacing.xl)
                    .padding(.top, SipSpacing.xl)
                    // Enrichment swaps this copy in place — cross-fade, don't jump.
                    .contentTransition(.opacity)
                    .animation(.smooth, value: scan.explanation)

                // MARK: - Because-Rows (renders nothing until TasteScorer emits structured signals)
                if !becauseRows.isEmpty {
                    DisclosureGroup(isExpanded: $becauseExpanded) {
                        VStack(alignment: .leading, spacing: SipSpacing.s) {
                            ForEach(becauseRows.indices, id: \.self) { index in
                                HStack(alignment: .top, spacing: SipSpacing.s) {
                                    Circle()
                                        .fill(becauseRows[index].isPro
                                              ? SipColors.verdictTry
                                              : SipColors.verdictSkip)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, SipSpacing.xs)
                                    Text(becauseRows[index].text)
                                        .font(SipTypography.subhead)
                                        .foregroundColor(SipColors.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.top, SipSpacing.s)
                    } label: {
                        Text("Why this verdict")
                            .font(SipTypography.subhead)
                            .foregroundColor(SipColors.textSecondary)
                    }
                    .tint(SipColors.accent)
                    .padding(.horizontal, SipSpacing.xl)
                    .padding(.top, SipSpacing.l)
                }

                // MARK: - Origin Card
                if let origin = scan.origin, !origin.isEmpty {
                    HStack(alignment: .top, spacing: SipSpacing.s) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(SipColors.textSecondary)
                            .font(SipTypography.subhead)
                        Text(origin)
                            .font(SipTypography.caption)
                            .foregroundColor(SipColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(SipSpacing.m)
                    .background(
                        RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                            .fill(SipColors.surface)
                    )
                    .padding(.horizontal, SipSpacing.xl)
                    .padding(.top, SipSpacing.l)
                }

                // MARK: - Action Buttons
                VStack(spacing: SipSpacing.m) {
                    // Drinking it — log it: primary path, prefilled from this scan.
                    Button(action: { showingLogSheet = true }) {
                        Text("Drinking it — log it")
                    }
                    .buttonStyle(SipPrimaryButtonStyle())
                    .accessibilityIdentifier("logItButton")

                    // Save for Later — flips to a confirmed "Saved" instantly
                    // (optimistic — the store write and notification scheduling
                    // ride along behind it).
                    Button(action: { onSaveForLater?() }) {
                        HStack(spacing: SipSpacing.s) {
                            if savedForLater {
                                Image(systemName: "checkmark")
                            }
                            Text(savedForLater ? "Saved" : "Save for Later")
                        }
                    }
                    .buttonStyle(SipSecondaryButtonStyle())
                    .disabled(savedForLater)
                    .animation(.snappy(duration: 0.25), value: savedForLater)
                    .accessibilityIdentifier("saveForLater")

                    Button(action: { onScanAnother?() }) {
                        Text("Scan Another")
                    }
                    .buttonStyle(SipQuietButtonStyle())
                    .accessibilityIdentifier("scanAnother")
                }
                .padding(.horizontal, SipSpacing.xl)
                .padding(.top, SipSpacing.xxl)
                // Tab-bar clearance is inherited from MainTabView's shared
                // .sipTabBarClearance() safe-area contract — no magic padding.
                .padding(.bottom, SipSpacing.xl)
            }
        }
        .background(
            ZStack {
                SipColors.background
                // Full-height verdict atmosphere: runs behind the status bar
                // (round-2 crit #6 — the tint used to cut in at the safe-area
                // seam) and fades out by mid-screen so the reading zone below
                // stays canvas-dark.
                LinearGradient(
                    colors: [verdictStyle.color.opacity(0.22), Color.clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.5)
                )
            }
            .ignoresSafeArea()
        )
        .sheet(isPresented: $showingLogSheet) {
            AddBeerView(prefill: AddBeerPrefill(
                name: scan.beerName,
                style: scan.style ?? BeerStyle.other.rawValue,
                abv: scan.abv,
                scanId: scan.id
            ))
        }
        .accessibilityIdentifier("verdictCard")
    }

    // MARK: - Verdict Hero (the answer owns the top — .bouncy is reserved for exactly this reveal)

    private var verdictHero: some View {
        VStack(spacing: SipSpacing.s) {
            Image(systemName: verdictStyle.symbol)
                .font(.system(size: verdictSize * 0.5, weight: .heavy))
                .foregroundColor(verdictStyle.color)
                .accessibilityHidden(true)
            Text(verdictStyle.word)
                .font(.system(size: verdictSize, weight: .heavy, design: .rounded))
                .foregroundColor(verdictStyle.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityIdentifier("verdictText")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SipSpacing.xl)
        // The verdict tint is the card's BACKGROUND layer (full height,
        // behind the status bar) — no hero-local gradient, so there's no
        // hard seam where the hero ends.
        .scaleEffect(heroRevealed ? 1 : 0.8)
        .opacity(heroRevealed ? 1 : 0)
        .animation(.bouncy, value: scan.verdict)
        .onAppear {
            withAnimation(.bouncy) { heroRevealed = true }
        }
    }

    // MARK: - Identity Block (SRM gradient header — name printed exactly once)

    /// SRM-surface ink pair (round-2 crit #2): dark warm ink on light beer
    /// surfaces (the gray textSecondary token measured 1.9:1 on amber), cream
    /// on mid/dark surfaces — where a bottom scrim keeps it legible instead.
    private var identityInk: (primary: Color, secondary: Color) {
        StyleGradient.ink(for: scan.style)
    }

    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: SipSpacing.xs) {
            Text(scan.beerName)
                .font(SipTypography.title)
                .foregroundColor(identityInk.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SipSpacing.s) {
                if !beerMetadata.isEmpty {
                    Text(beerMetadata)
                        .font(SipTypography.subhead)
                        .foregroundColor(identityInk.secondary)
                }
                // Refining rides the row it will patch — bottom-aligned with
                // the metadata, not wedged between verdict and banner.
                if refining {
                    HStack(spacing: SipSpacing.xs) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(identityInk.secondary)
                        Text("refining details…")
                            .font(SipTypography.caption)
                            .foregroundColor(identityInk.secondary)
                    }
                    .transition(.opacity)
                    .accessibilityIdentifier("refiningHint")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(SipSpacing.l)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .bottomLeading)
        .background(
            ZStack {
                StyleGradient.gradient(for: scan.style)
                // Legibility: LIGHT SRM surfaces carry dark ink directly (no
                // scrim to fight it); mid/dark surfaces keep cream ink over
                // this bottom scrim (slop watchlist: no white-on-gold).
                if !StyleGradient.hasLightSurface(scan.style) {
                    LinearGradient(
                        colors: [Color.clear, SipColors.background.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: SipRadius.hero, style: .continuous))
    }

    // MARK: - Computed Properties

    /// style · ABV · provenance — subhead metadata line under the name.
    private var beerMetadata: String {
        var parts: [String] = []
        if let style = scan.style {
            parts.append(style)
        }
        if let abv = scan.abv {
            parts.append(String(format: "%.1f%% ABV", abv))
        }
        if let source {
            parts.append(source.copy)
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// Full sentence per rating — round-2 crit #7: interpolating the raw
    /// rating name produced the truncated-sounding "you rated it like".
    private func historyLine(for rating: Rating) -> String {
        switch rating {
        case .like:    return "You've had this one — you gave it a thumbs up."
        case .dislike: return "You've had this one — you gave it a thumbs down."
        case .neutral: return "You've had this one — you were on the fence."
        }
    }

    private func ratingSymbol(for rating: Rating) -> String {
        switch rating {
        case .like:    return "hand.thumbsup.fill"
        case .neutral: return "hand.raised.fill"
        case .dislike: return "hand.thumbsdown.fill"
        }
    }

    private func ratingColor(for rating: Rating) -> Color {
        switch rating {
        case .like:    return SipColors.verdictTry
        case .neutral: return SipColors.verdictNeutral
        case .dislike: return SipColors.verdictSkip
        }
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

            VerdictCardView(
                scan: ScanStore.seedScans[0],
                refining: true,
                source: .catalog,
                confidence: 0.72,
                alternates: ["Two Hearted Ale", "Two Hearted IPA"],
                becauseRows: [
                    (text: "Matches your love of pale ale", isPro: true),
                    (text: "Higher ABV than you usually pick", isPro: false)
                ]
            )
            .previewDisplayName("Refining + Low Confidence")
        }
        .preferredColorScheme(.dark)
    }
}
