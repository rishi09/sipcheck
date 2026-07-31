import SwiftUI
import ImageIO

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

/// Compact attribution for a connected identity match. It deliberately sits
/// apart from recommendation copy: the linked page grounded the beer match,
/// while SipCheck's local scorer produced the verdict.
struct BeerFactSourceLink: View {
    let source: BeerFactSource
    var linkAccessibilityIdentifier: String = "beerFactSourceLink"

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalAttribution
            stackedAttribution
        }
        .font(SipTypography.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var horizontalAttribution: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            sourceLine
            if let licenseURL = source.licenseURL {
                Text("\u{00B7}")
                    .foregroundColor(SipColors.textSecondary)
                licenseLink(licenseURL)
            }
        }
    }

    @ViewBuilder
    private var stackedAttribution: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sourcePrefix)
                .foregroundColor(SipColors.textSecondary)
            sourceLink
            if let licenseURL = source.licenseURL {
                licenseLink(licenseURL)
            }
        }
    }

    private var sourceLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(sourcePrefix)
                .foregroundColor(SipColors.textSecondary)
                .fixedSize(horizontal: true, vertical: false)
            sourceLink
        }
    }

    private var sourcePrefix: String {
        source.kind == .catalogBeer ? "Beer match adapted from" : "Beer match source"
    }

    private var sourceLink: some View {
        Link(destination: source.url) {
            HStack(spacing: 3) {
                Text(source.kind == .catalogBeer ? "Catalog.beer" : source.displayHost)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "arrow.up.right")
                    .accessibilityHidden(true)
            }
            .foregroundColor(SipColors.accent)
        }
        .accessibilityLabel("Open beer match source, \(source.displayHost)")
        .accessibilityIdentifier(linkAccessibilityIdentifier)
    }

    private func licenseLink(_ url: URL) -> some View {
        Link("CC BY 4.0", destination: url)
            .foregroundColor(SipColors.accent)
            .accessibilityLabel("Creative Commons Attribution 4.0 license")
            .accessibilityIdentifier("\(linkAccessibilityIdentifier)License")
    }
}

struct VerdictCardView: View {
    let scan: Scan
    /// Set only by the canonical beer-library projection when this strict beer
    /// identity has a surviving encounter. The source-aware record keeps copy
    /// honest: star ratings are not described as thumb gestures.
    var previousTaste: BeerTasteRecord? = nil
    /// True while background network enrichment is still filling in details.
    /// The verdict itself is final the moment the card renders — this only
    /// signals that copy/style/ABV may still improve in place.
    var refining: Bool = false
    /// Optimistic saved state: flips the Save button to a confirmed "Saved"
    /// immediately on tap (the silent button was the app's worst UX moment).
    var savedForLater: Bool = false
    /// In-memory frame for the immediate scan -> log transition. A persisted
    /// filename on `scan` covers later entry from Want to Try / notifications.
    var capturedImage: UIImage? = nil
    /// Menu mode's second-ranked choice, intentionally hidden until requested.
    var runnerUp: Scan? = nil
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
    var onBack: (() -> Void)? = nil
    var onSaveForLater: (() -> Void)?
    var onScanAnother: (() -> Void)?
    /// Called when the user picks a fuzzy alternate; wiring lands with WO-3.
    var onSelectAlternate: ((String) -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingAlternates = false
    @State private var showingLogSheet = false
    @State private var showingRunnerUp = false

    private var verdictStyle: VerdictStyle {
        VerdictStyle.style(for: scan.verdict)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topControls
                    .padding(.horizontal, SipSpacing.l)

                passportHeader
                    .padding(.horizontal, SipSpacing.l)
                    .padding(.top, SipSpacing.m)

                if let factSource = scan.factSource {
                    BeerFactSourceLink(
                        source: factSource,
                        linkAccessibilityIdentifier: "verdictBeerFactSource"
                    )
                    .padding(.horizontal, SipSpacing.xl)
                    .padding(.top, SipSpacing.m)
                }

                // MARK: - History Capsule (highest-trust line — elevated chip, SF thumb, no raw emoji)
                if let previousTaste {
                    HStack(spacing: SipSpacing.s) {
                        Image(systemName: ratingSymbol(for: previousTaste.rating))
                            .font(SipTypography.caption)
                            .foregroundColor(ratingColor(for: previousTaste.rating))
                            .accessibilityHidden(true)
                        Text(historyLine(for: previousTaste))
                            .font(SipTypography.caption)
                            .foregroundColor(SipColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, SipSpacing.l)
                    .padding(.vertical, SipSpacing.m)
                    .background(Capsule().fill(SipColors.surfaceElevated))
                    .padding(.horizontal, SipSpacing.l)
                    .padding(.top, SipSpacing.m)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(historyLine(for: previousTaste))
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SipSpacing.l)
                    .padding(.top, SipSpacing.m)
                }

                tasteSection
                    .padding(.horizontal, SipSpacing.l)
                    .padding(.top, SipSpacing.xl)

                whyItFitsSection
                    .padding(.horizontal, SipSpacing.l)
                    .padding(.top, SipSpacing.xl)

                if let runnerUp {
                    VStack(alignment: .leading, spacing: SipSpacing.s) {
                        Button {
                            withAnimation(.snappy(duration: 0.25)) {
                                showingRunnerUp.toggle()
                            }
                        } label: {
                            Label(
                                showingRunnerUp ? "Hide runner-up" : "See runner-up",
                                systemImage: showingRunnerUp ? "chevron.up" : "medal"
                            )
                        }
                        .buttonStyle(SipQuietButtonStyle())
                        .accessibilityIdentifier("menuRunnerUpButton")

                        if showingRunnerUp {
                            VStack(alignment: .leading, spacing: SipSpacing.xs) {
                                Text(runnerUp.beerName)
                                    .font(SipTypography.headline)
                                    .foregroundColor(SipColors.textPrimary)
                                Text(runnerUp.explanation)
                                    .font(SipTypography.caption)
                                    .foregroundColor(SipColors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .accessibilityIdentifier("menuRunnerUpDetails")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SipSpacing.xl)
                    .padding(.top, SipSpacing.m)
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
                brand: scan.brand ?? "",
                style: scan.style ?? BeerStyle.other.rawValue,
                abv: scan.abv,
                capturedImage: capturedImage,
                photoFileName: scan.photoFileName,
                scanId: scan.id,
                factSource: scan.factSource
            ))
        }
        .accessibilityIdentifier("verdictCard")
    }

    // MARK: - Taste Passport Header

    private var topControls: some View {
        CompatGlassContainer(spacing: SipSpacing.m) {
            HStack {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(SipColors.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                    .compatGlassCircle()
                    .accessibilityLabel("Back to Check")
                    .accessibilityIdentifier("tastePassportBack")
                }

                Spacer()

                if onSaveForLater != nil {
                    Button(action: { onSaveForLater?() }) {
                        Image(systemName: savedForLater ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(savedForLater ? SipColors.accent : SipColors.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                    .compatGlassCircle()
                    .disabled(savedForLater)
                    .accessibilityLabel(savedForLater ? "Saved for later" : "Save for later")
                    .accessibilityIdentifier("tastePassportSave")
                }
            }
        }
        .padding(.top, SipSpacing.s)
    }

    @ViewBuilder
    private var passportHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: SipSpacing.m) {
                HStack(alignment: .top) {
                    passportArtwork
                    Spacer(minLength: SipSpacing.m)
                    verdictMark
                }
                identityCopy
            }
        } else {
            HStack(alignment: .top, spacing: SipSpacing.m) {
                passportArtwork
                identityCopy
                    .frame(maxWidth: .infinity, alignment: .leading)
                verdictMark
            }
        }
    }

    private var passportArtwork: some View {
        BeerPassportArtwork(
            beerName: scan.beerName,
            brewery: scan.brand,
            style: scan.style,
            capturedImage: capturedImage,
            storedPhotoFileName: scan.photoFileName,
            referenceImageURL: scan.referenceImageURL
        )
        .frame(width: 88, height: 112)
        .accessibilityIdentifier("tastePassportArtwork")
    }

    private var identityCopy: some View {
        VStack(alignment: .leading, spacing: SipSpacing.s) {
            Text(scan.beerName)
                .font(SipTypography.title)
                .foregroundColor(SipColors.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if !beerMetadata.isEmpty {
                Text(beerMetadata)
                    .font(SipTypography.subhead)
                    .foregroundColor(SipColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if refining {
                HStack(spacing: SipSpacing.xs) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(SipColors.textSecondary)
                    Text("refining details…")
                        .font(SipTypography.caption)
                        .foregroundColor(SipColors.textSecondary)
                }
                .transition(.opacity)
                .accessibilityIdentifier("refiningHint")
            }
        }
    }

    private var verdictMark: some View {
        VStack(spacing: SipSpacing.xs) {
            Image(systemName: verdictStyle.symbol)
                .font(.system(size: 30, weight: .bold))
                .accessibilityHidden(true)
            Text(verdictStyle.word)
                .font(.headline.weight(.heavy))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .foregroundColor(verdictDisplayColor)
        .frame(minWidth: 72, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verdict: \(verdictStyle.word.lowercased())")
        .accessibilityIdentifier("verdictText")
    }

    private var verdictDisplayColor: Color {
        scan.verdict == .skipIt ? SipColors.verdictSkipText : verdictStyle.color
    }

    // MARK: - Taste Passport Content

    private var tasteSection: some View {
        VStack(alignment: .leading, spacing: SipSpacing.m) {
            Text("What it tastes like")
                .font(SipTypography.headline)
                .foregroundColor(SipColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if let style = scan.style?.trimmingCharacters(in: .whitespacesAndNewlines),
               !style.isEmpty {
                Text("Typical \(style) profile")
                    .font(SipTypography.caption)
                    .foregroundColor(SipColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let passport = TastePassportProfile.profile(for: scan.style) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: SipSpacing.s),
                        GridItem(.flexible(), spacing: SipSpacing.s)
                    ],
                    alignment: .leading,
                    spacing: SipSpacing.s
                ) {
                    ForEach(Array(passport.notes.enumerated()), id: \.offset) { index, note in
                        Text(note)
                            .font(SipTypography.subhead)
                            .foregroundColor(index < 2 ? SipColors.textPrimary : SipColors.textSecondary)
                            .padding(.horizontal, SipSpacing.m)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                Capsule().fill(index < 2 ? SipColors.accentSubtle : SipColors.surfaceElevated)
                            )
                    }
                }

                TasteAxisView(
                    leadingLabel: "Soft",
                    trailingLabel: "Bitter",
                    value: passport.bitterness
                )
                TasteAxisView(
                    leadingLabel: "Light",
                    trailingLabel: "Full",
                    value: passport.body
                )
            } else {
                Text("Taste details will appear when we can identify the beer style.")
                    .font(SipTypography.body)
                    .foregroundColor(SipColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("tastePassportTasteSection")
    }

    private var whyItFitsSection: some View {
        VStack(alignment: .leading, spacing: SipSpacing.m) {
            Text(whyHeading)
                .font(SipTypography.headline)
                .foregroundColor(SipColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("tastePassportWhyHeading")

            HStack(alignment: .top, spacing: SipSpacing.m) {
                Image(systemName: verdictStyle.symbol)
                    .font(SipTypography.subhead)
                    .foregroundColor(verdictDisplayColor)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(verdictDisplayColor.opacity(0.15)))
                    .accessibilityHidden(true)

                Text(personalReason)
                    .font(SipTypography.body)
                    .foregroundColor(SipColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .animation(.smooth, value: personalReason)
            }
            .padding(SipSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                    .fill(SipColors.surface)
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tastePassportWhyReason")
        }
    }

    private var whyHeading: String {
        switch scan.verdict {
        case .tryIt: return "Why it fits you"
        case .skipIt: return "Why it may not fit"
        case .yourCall: return "What to consider"
        }
    }

    private var personalReason: String {
        let candidates = becauseRows.map(\.text) + [scan.explanation]
        if let reason = candidates
            .map(Self.removingStrengthProximityCopy)
            .first(where: { !$0.isEmpty }) {
            return reason
        }
        switch scan.verdict {
        case .tryIt: return "This lines up with the preferences in your taste profile."
        case .skipIt: return "This sits outside the preferences you have shared so far."
        case .yourCall: return "Your taste history does not point strongly either way yet."
        }
    }

    nonisolated static func isStrengthProximityCopy(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.contains("near your usual")
            && (normalized.contains("strength") || normalized.contains("abv") || normalized.contains("%"))
    }

    nonisolated static func removingStrengthProximityCopy(_ value: String) -> String {
        // Split manually so decimal ABVs such as 6.4% do not look like a
        // sentence boundary. The removed copy is generated as its own sentence;
        // preserving every other sentence keeps useful personalized evidence.
        var segments: [String] = []
        var segmentStart = value.startIndex
        var cursor = value.startIndex

        while cursor < value.endIndex {
            let character = value[cursor]
            let next = value.index(after: cursor)
            let isBoundary: Bool
            if character == "." {
                let previousCharacter = cursor > value.startIndex
                    ? value[value.index(before: cursor)]
                    : nil
                let nextCharacter = next < value.endIndex ? value[next] : nil
                isBoundary = !(previousCharacter?.isNumber == true && nextCharacter?.isNumber == true)
            } else {
                isBoundary = character == "!" || character == "?" || character == ";"
            }

            if isBoundary {
                segments.append(String(value[segmentStart..<next]))
                segmentStart = next
            }
            cursor = next
        }
        if segmentStart < value.endIndex {
            segments.append(String(value[segmentStart..<value.endIndex]))
        }

        return segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isStrengthProximityCopy($0) }
            .joined(separator: " ")
    }

    // MARK: - Computed Properties

    /// style · ABV · provenance — subhead metadata line under the name.
    private var beerMetadata: String {
        var parts: [String] = []
        if let brand = scan.brand, !brand.isEmpty { parts.append(brand) }
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
    private func historyLine(for record: BeerTasteRecord) -> String {
        if let stars = record.stars {
            return "You've had this one — last time: \(stars) out of 5."
        }
        switch record.rating {
        case .like:    return "You've had this one — you liked it last time."
        case .dislike: return "You've had this one — it wasn't for you last time."
        case .neutral: return "You've had this one — it was a maybe last time."
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

// MARK: - Taste Passport Artwork

/// Resolves the thumbnail without ever conflating reference art with a user's
/// photo. The visible order is intentionally strict: current capture, saved
/// capture, exact bundled product art, connected product art, honest fallback.
struct BeerPassportArtwork: View {
    @EnvironmentObject private var drinkStore: DrinkStore

    let beerName: String
    let brewery: String?
    let style: String?
    let capturedImage: UIImage?
    let storedPhotoFileName: String?
    let referenceImageURL: URL?

    @State private var storedImage: UIImage?
    @State private var storedLoadFinished = false
    @State private var remoteImage: UIImage?
    @State private var remoteLoadFinished = false

    var body: some View {
        Group {
            if let capturedImage {
                framed(Image(uiImage: capturedImage).resizable().scaledToFill())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Photo you took of \(beerName)")
            } else if let storedImage {
                framed(Image(uiImage: storedImage).resizable().scaledToFill())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Photo you took of \(beerName)")
            } else if storedPhotoFileName != nil, !storedLoadFinished {
                framed(
                    ZStack {
                        fallbackArtwork
                        ProgressView().tint(SipColors.textPrimary)
                    }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading photo you took of \(beerName)")
            } else if let assetName = BeerProductArtwork.assetName(
                beerName: beerName,
                brewery: brewery
            ) {
                framed(Image(assetName).resizable().scaledToFill())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Product photo of \(beerName)")
            } else if BeerReferenceImageURL.validated(referenceImageURL) != nil {
                if let remoteImage {
                    framed(Image(uiImage: remoteImage).resizable().scaledToFill())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Product photo of \(beerName)")
                } else if !remoteLoadFinished {
                    framed(
                        ZStack {
                            fallbackArtwork
                            ProgressView().tint(SipColors.textPrimary)
                        }
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Loading product photo of \(beerName)")
                } else {
                    framed(fallbackArtwork)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("No photo available for \(beerName); beer color shown")
                }
            } else {
                framed(fallbackArtwork)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("No photo available for \(beerName); beer color shown")
            }
        }
        .task(id: loadRequestID) {
            storedImage = nil
            remoteImage = nil
            storedLoadFinished = capturedImage != nil || storedPhotoFileName == nil
            remoteLoadFinished = capturedImage != nil || referenceImageURL == nil
            guard capturedImage == nil else { return }

            if let storedPhotoFileName {
                let loadedStoredImage = await drinkStore.loadPhotoAsync(named: storedPhotoFileName)
                guard !Task.isCancelled else { return }
                storedImage = loadedStoredImage
                storedLoadFinished = true
                if loadedStoredImage != nil { return }
            }

            guard BeerProductArtwork.assetName(beerName: beerName, brewery: brewery) == nil,
                  let referenceImageURL = BeerReferenceImageURL.validated(referenceImageURL) else {
                remoteLoadFinished = true
                return
            }
            let loadedRemoteImage = await BeerReferenceImageLoader.load(from: referenceImageURL)
            guard !Task.isCancelled else { return }
            remoteImage = loadedRemoteImage
            remoteLoadFinished = true
        }
    }

    private var loadRequestID: String {
        [
            capturedImage == nil ? "no-capture" : "capture",
            storedPhotoFileName ?? "no-stored-photo",
            referenceImageURL?.absoluteString ?? "no-reference"
        ].joined(separator: "|")
    }

    private var fallbackArtwork: some View {
        ZStack {
            SRMSwatch(style: style, cornerRadius: SipRadius.card)
            Text(initials)
                .font(.title3.weight(.heavy))
                .foregroundColor(StyleGradient.ink(for: style).primary)
                .accessibilityHidden(true)
        }
    }

    private var initials: String {
        beerName
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    private func framed<Content: View>(_ content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: SipRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SipRadius.card, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    .accessibilityHidden(true)
            )
    }
}

private final class BeerArtworkRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Common product CDNs redirect paths on the same host. Revalidate that
        // target, but never follow a cross-host hop (or private-looking URL)
        // behind the original validator's back.
        let priorHost = response.url?.host?.lowercased()
            ?? task.currentRequest?.url?.host?.lowercased()
            ?? task.originalRequest?.url?.host?.lowercased()
        guard let redirectedURL = BeerReferenceImageURL.validated(request.url),
              redirectedURL.host?.lowercased() == priorHost else {
            completionHandler(nil)
            return
        }
        var safeRequest = request
        safeRequest.url = redirectedURL
        completionHandler(safeRequest)
    }
}

enum BeerReferenceImageLoader {
    private static let maximumBytes = 4 * 1_024 * 1_024
    private static let maximumPixels = 24_000_000
    private static let acceptedMIMETypes: Set<String> = [
        "image/jpeg", "image/png", "image/webp", "image/heic", "image/heif", "image/avif", "image/gif"
    ]

    nonisolated static func load(from rawURL: URL) async -> UIImage? {
        guard let url = BeerReferenceImageURL.validated(rawURL) else { return nil }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--mock-beer-images"),
           url.host == "mock-images.sipcheck.app" {
            return await MainActor.run { TastePassportFixtureImage.remoteProductPhoto() }
        }
        #endif
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = [
            "Accept": "image/avif,image/webp,image/heic,image/png,image/jpeg,image/gif"
        ]
        let session = URLSession(
            configuration: configuration,
            delegate: BeerArtworkRedirectDelegate(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let mimeType = http.mimeType?.lowercased(),
                  acceptedMIMETypes.contains(mimeType),
                  response.expectedContentLength <= Int64(maximumBytes) else {
                return nil
            }

            var data = Data()
            if response.expectedContentLength > 0 {
                data.reserveCapacity(Int(response.expectedContentLength))
            }
            for try await byte in bytes {
                guard data.count < maximumBytes else { return nil }
                data.append(byte)
            }
            guard !data.isEmpty else { return nil }
            return downsampledImage(from: data)
        } catch {
            return nil
        }
    }

    nonisolated private static func downsampledImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0,
              width <= maximumPixels / height,
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 1_200
                  ] as CFDictionary
              ) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}

#if DEBUG
enum TastePassportFixtureImage {
    @MainActor static func capturedPhoto() -> UIImage {
        render(
            background: UIColor(red: 0.32, green: 0.08, blue: 0.42, alpha: 1),
            foreground: .white,
            title: "YOUR\nPHOTO",
            accent: UIColor(red: 1.0, green: 0.45, blue: 0.30, alpha: 1)
        )
    }

    @MainActor static func remoteProductPhoto() -> UIImage {
        render(
            background: UIColor(red: 0.03, green: 0.30, blue: 0.32, alpha: 1),
            foreground: .white,
            title: "HARBOR\nFOG",
            accent: UIColor(red: 0.25, green: 0.85, blue: 0.72, alpha: 1)
        )
    }

    @MainActor private static func render(
        background: UIColor,
        foreground: UIColor,
        title: String,
        accent: UIColor
    ) -> UIImage {
        let size = CGSize(width: 360, height: 480)
        return UIGraphicsImageRenderer(size: size).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            accent.setFill()
            UIBezierPath(
                roundedRect: CGRect(x: 86, y: 54, width: 188, height: 360),
                cornerRadius: 42
            ).fill()
            background.withAlphaComponent(0.75).setFill()
            UIBezierPath(
                roundedRect: CGRect(x: 106, y: 156, width: 148, height: 150),
                cornerRadius: 20
            ).fill()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            (title as NSString).draw(
                in: CGRect(x: 106, y: 188, width: 148, height: 96),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 31, weight: .black),
                    .foregroundColor: foreground,
                    .paragraphStyle: paragraph
                ]
            )
        }
    }
}
#endif

enum BeerProductArtwork {
    private struct Entry {
        let asset: String
        let breweryRoot: String
    }

    private static let exactAssets: [String: Entry] = [
        "allagash white": Entry(asset: "BeerBrandAllagashWhite", breweryRoot: "allagash"),
        "bud light": Entry(asset: "BeerBrandBudLight", breweryRoot: "anheuser busch"),
        "sierra nevada pale ale": Entry(asset: "BeerBrandSierraNevada", breweryRoot: "sierra nevada"),
        "stone ipa": Entry(asset: "BeerBrandStoneIPA", breweryRoot: "stone brewing"),
        "two hearted ale": Entry(asset: "BeerBrandTwoHearted", breweryRoot: "bell s")
    ]

    static func assetName(beerName: String, brewery: String?) -> String? {
        // Exact beer identity only. Brewery logos and contains-matches would
        // violate the promise that search shows this specific beer.
        guard let brewery,
              let entry = exactAssets[BeerDiscoveryText.normalize(beerName)],
              BeerDiscoveryText.normalize(brewery).contains(entry.breweryRoot) else {
            return nil
        }
        return entry.asset
    }
}

// MARK: - Taste Passport Profile

struct TastePassportProfile: Equatable {
    let notes: [String]
    let bitterness: Double
    let body: Double

    static func profile(for styleName: String?) -> TastePassportProfile? {
        guard let styleName else { return nil }
        let normalizedStyle = BeerDiscoveryText.normalize(styleName)
        if normalizedStyle.contains("milkshake") && normalizedStyle.contains("ipa") {
            return profile("Tropical", "Vanilla", "Creamy", "Sweet finish", bitterness: 0.35, body: 0.82)
        }
        if (normalizedStyle.contains("hazy") || normalizedStyle.contains("new england"))
            && normalizedStyle.contains("ipa") {
            return profile("Tropical", "Citrus", "Juicy", "Soft finish", bitterness: 0.48, body: 0.68)
        }
        if normalizedStyle.contains("black") && normalizedStyle.contains("ipa") {
            return profile("Roasty", "Pine", "Citrus", "Dry finish", bitterness: 0.78, body: 0.68)
        }
        if normalizedStyle.contains("west coast") && normalizedStyle.contains("ipa") {
            return profile("Citrus", "Pine", "Resinous", "Dry finish", bitterness: 0.86, body: 0.55)
        }
        if (normalizedStyle.contains("double") || normalizedStyle.contains("imperial"))
            && normalizedStyle.contains("ipa") {
            return profile("Citrus", "Pine", "Resinous", "Warming", bitterness: 0.85, body: 0.78)
        }
        if normalizedStyle.contains("session") && normalizedStyle.contains("ipa") {
            return profile("Citrus", "Hoppy", "Crisp", "Dry finish", bitterness: 0.70, body: 0.36)
        }
        let style = BeerStyle.allCases.first {
            $0.rawValue.caseInsensitiveCompare(styleName) == .orderedSame
        } ?? TasteScorer.inferStyle(from: styleName)

        switch style {
        case .ipa:
            return profile("Citrus", "Pine", "Hoppy", "Dry finish", bitterness: 0.82, body: 0.62)
        case .paleAle:
            return profile("Citrus", "Caramel", "Hoppy", "Crisp", bitterness: 0.68, body: 0.50)
        case .lager:
            return profile("Crisp", "Grainy", "Clean", "Dry finish", bitterness: 0.30, body: 0.34)
        case .pilsner:
            return profile("Crisp", "Herbal", "Bready", "Clean", bitterness: 0.46, body: 0.32)
        case .stout:
            return profile("Roasty", "Coffee", "Chocolate", "Creamy", bitterness: 0.58, body: 0.82)
        case .porter:
            return profile("Chocolate", "Caramel", "Roasty", "Smooth", bitterness: 0.50, body: 0.72)
        case .wheat:
            return profile("Citrus", "Bready", "Soft spice", "Smooth", bitterness: 0.22, body: 0.42)
        case .sour:
            return profile("Tart", "Fruity", "Bright", "Dry finish", bitterness: 0.18, body: 0.36)
        case .amber:
            return profile("Caramel", "Toasty", "Balanced", "Smooth", bitterness: 0.42, body: 0.58)
        case .brownAle:
            return profile("Nutty", "Caramel", "Toasty", "Smooth", bitterness: 0.38, body: 0.62)
        case .belgian:
            return profile("Fruity", "Spicy", "Bready", "Dry finish", bitterness: 0.34, body: 0.64)
        case .other, .none:
            return nil
        }
    }

    private static func profile(
        _ first: String,
        _ second: String,
        _ third: String,
        _ fourth: String,
        bitterness: Double,
        body: Double
    ) -> TastePassportProfile {
        TastePassportProfile(
            notes: [first, second, third, fourth],
            bitterness: bitterness,
            body: body
        )
    }
}

private struct TasteAxisView: View {
    let leadingLabel: String
    let trailingLabel: String
    let value: Double

    private var clampedValue: CGFloat {
        CGFloat(min(max(value, 0), 1))
    }

    var body: some View {
        VStack(spacing: SipSpacing.s) {
            HStack {
                Text(leadingLabel)
                Spacer()
                Text(trailingLabel)
            }
            .font(SipTypography.caption)
            .foregroundColor(SipColors.textSecondary)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(SipColors.surfaceElevated)
                    Circle()
                        .fill(SipColors.accent)
                        .frame(width: 16, height: 16)
                        .offset(x: (proxy.size.width - 16) * clampedValue)
                }
            }
            .frame(height: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(leadingLabel) to \(trailingLabel), \(Int(clampedValue * 100)) percent toward \(trailingLabel.lowercased())"
        )
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
        .environmentObject(DrinkStore())
    }
}
