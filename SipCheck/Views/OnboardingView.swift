import SwiftUI

// MARK: - Flow Variants (Onboarding Lab)

/// The onboarding flow shapes the Lab can switch between. Raw values are the
/// exact strings the Settings "Onboarding Lab" section writes to the
/// `onboardingFlowVariant` UserDefaults key — both sides hardcode them.
enum OnboardingVariant: String, CaseIterable, Identifiable {
    /// Classic flow: had-before picker + full taste quiz.
    case control
    /// Default: go-to picker + stay-away picker; stay-away completes.
    case goToStayAway
    /// Same as the default plus a vibe-only quiz at the end.
    case goToStayAwayPlusVibe

    var id: String { rawValue }

    var pages: [OnboardingPage] {
        switch self {
        case .control:
            return [.story(index: 0), .story(index: 1), .story(index: 2),
                    .legacyBeerPicker,
                    .quiz(includeAdventure: true, includeDislikes: true)]
        case .goToStayAway:
            return [.story(index: 0), .story(index: 1),
                    .goToPicker,
                    .stayAwayPicker]
        case .goToStayAwayPlusVibe:
            return [.story(index: 0), .story(index: 1),
                    .goToPicker,
                    .stayAwayPicker,
                    .quiz(includeAdventure: false, includeDislikes: false)]
        }
    }
}

enum OnboardingPage {
    case story(index: Int)           // 0, 1, 2
    case legacyBeerPicker
    case goToPicker
    case stayAwayPicker
    case quiz(includeAdventure: Bool, includeDislikes: Bool)

    /// Pages with their own CTA blocks hide the system page dots so buttons
    /// never fight the page indicator for the same bottom band.
    var hasOwnCTABlock: Bool {
        if case .story = self { return false }
        return true
    }
}

// MARK: - Shared option pools

/// The 16 recognizable picker beers — shared by the legacy, go-to, and
/// stay-away pickers so saved picks restore identically on every page.
/// Internal (not file-private): Settings' TastePreferencesEditorView renders
/// the same pool so edited picks stay restorable here.
let onboardingBeerOptions = [
    "Modelo", "Corona", "Heineken", "Blue Moon",
    "Sam Adams", "Guinness", "Sierra Nevada", "Lagunitas",
    "Hazy Little Thing", "Coors Light", "Bud Light", "Stella Artois",
    "Allagash White", "Dogfish Head", "Stone IPA", "Goose Island"
]

/// Style chips offered on the go-to and stay-away pickers (and Settings'
/// taste editor — internal so both surfaces stay in lockstep).
let onboardingStyleChips: [BeerStyle] = BeerStyle.allCases.filter { $0 != .other }

/// Pluralized DISPLAY labels for the style chips. Display only — persisted
/// values are always `BeerStyle.rawValue`, never these. Internal: Settings'
/// taste editor shows the same labels.
func styleChipLabel(_ style: BeerStyle) -> String {
    switch style {
    case .ipa: return "IPAs"
    case .paleAle: return "Pale ales"
    case .lager: return "Lagers"
    case .pilsner: return "Pilsners"
    case .stout: return "Stouts"
    case .porter: return "Porters"
    case .wheat: return "Wheat beers"
    case .sour: return "Sours"
    case .amber: return "Ambers"
    case .brownAle: return "Brown ales"
    case .belgian: return "Belgians"
    case .other: return style.rawValue
    }
}

/// Exemplar brand anchors for the style chips — one widely recognizable beer
/// (or style descriptor) per style, so answering never requires beer
/// vocabulary: "Stouts — like Guinness". The brand name is the input
/// language; the style is only the stored output. Display only, never
/// persisted. Internal: Settings' taste editor shows the same anchors.
func styleChipAnchor(_ style: BeerStyle) -> String? {
    switch style {
    case .ipa: return "like Lagunitas"
    case .paleAle: return "like Sierra Nevada"
    case .lager: return "like Modelo"
    case .pilsner: return "like Stella"
    case .stout: return "like Guinness"
    case .porter: return "like Founders Porter"
    case .wheat: return "like Blue Moon"
    case .sour: return "like a gose"
    case .amber: return "like Fat Tire"
    case .brownAle: return "like Newcastle"
    case .belgian: return "like Chimay"
    case .other: return nil
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // Onboarding Lab variant switches — written by Settings' Onboarding Lab,
    // read live here so the next preview picks up changes with zero plumbing.
    @AppStorage("onboardingFlowVariant") private var flowVariantRaw = OnboardingVariant.goToStayAway.rawValue
    @AppStorage("onboardingCopyVariantPage1") private var copyVariantPage1 = "A"
    @AppStorage("onboardingScanVignette") private var scanVignetteRaw = "full"
    @AppStorage("onboardingPickerCopyVariant") private var pickerCopyVariant = "primary"

    /// Lab-preview hook: when set, finishing (or the close button) calls this
    /// instead of flipping `hasCompletedOnboarding` — a preview must never
    /// touch real completion state.
    var onFinish: (() -> Void)? = nil

    @State private var currentPage = 0

    private var variant: OnboardingVariant {
        OnboardingVariant(rawValue: flowVariantRaw) ?? .goToStayAway
    }

    /// Lab previews (`onFinish != nil`) must be non-destructive: every page
    /// stays fully interactive in memory, but ALL persistence is suppressed —
    /// Settings' footer promises "Preview never touches your taste data."
    private var isPreview: Bool { onFinish != nil }

    var body: some View {
        TabView(selection: $currentPage) {
            ForEach(0..<variant.pages.count, id: \.self) { idx in
                pageView(
                    for: variant.pages[idx],
                    tag: idx,
                    isLast: idx == variant.pages.count - 1
                )
                .tag(idx)
            }
        }
        // min() guards a live flow-variant switch shrinking the page count
        // while a later page is selected.
        .tabViewStyle(.page(indexDisplayMode: variant.pages[min(currentPage, variant.pages.count - 1)].hasOwnCTABlock ? .never : .always))
        // A live flow-variant switch can shrink the page count, leaving the
        // selection pointing at a removed tag (blank TabView). Restart the
        // new flow from its first page.
        .onChange(of: flowVariantRaw) { _, _ in
            currentPage = 0
        }
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(SipColors.background.ignoresSafeArea())
        .accessibilityIdentifier("onboardingPreviewRoot")
        .overlay(alignment: .topTrailing) {
            if onFinish != nil {
                Button(action: finish) {
                    Image(systemName: "xmark.circle.fill")
                        .font(SipTypography.title)
                        .foregroundColor(SipColors.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("onboardingPreviewCloseButton")
                .padding(SipSpacing.l)
            }
        }
    }

    /// The ONLY completion point: Lab previews dismiss via `onFinish`; the
    /// real first run flips `hasCompletedOnboarding`.
    private func finish() {
        if let onFinish {
            onFinish()
        } else {
            hasCompletedOnboarding = true
        }
    }

    private func advanceAction(from tag: Int, isLast: Bool) -> () -> Void {
        if isLast { return finish }
        return {
            withAnimation(.smooth) {
                currentPage = tag + 1
            }
        }
    }

    @ViewBuilder
    private func pageView(for page: OnboardingPage, tag: Int, isLast: Bool) -> some View {
        switch page {
        case .story(let index):
            storyPage(index: index, tag: tag, isLast: isLast)
        case .legacyBeerPicker:
            BeerPickerPage(
                isPreview: isPreview,
                onAdvance: advanceAction(from: tag, isLast: isLast)
            )
        case .goToPicker:
            GoToPickerPage(
                copyVariant: pickerCopyVariant,
                isPreview: isPreview,
                onAdvance: advanceAction(from: tag, isLast: isLast)
            )
        case .stayAwayPicker:
            StayAwayPickerPage(
                copyVariant: pickerCopyVariant,
                isLast: isLast,
                isPreview: isPreview,
                onAdvance: advanceAction(from: tag, isLast: isLast)
            )
        case .quiz(let includeAdventure, let includeDislikes):
            TasteQuizPage(
                includeAdventure: includeAdventure,
                includeDislikes: includeDislikes,
                isPreview: isPreview,
                onFinish: finish
            )
        }
    }

    private var pageOneCopy: (title: String, description: String) {
        switch copyVariantPage1 {
        case "B": return ("Know what to buy.", "A quick answer, tuned to your taste.")
        case "C": return ("Find your next favorite.", "Personal picks before you buy.")
        // D keeps the palate-vs-crowd contrast as the differentiator while
        // every variant leads with the shopper's outcome, not the machinery.
        case "D": return ("Buy beer you'll love.", "Picked for your taste, not the crowd's.")
        default:  return ("Pick the right beer, fast.", "Personalized to your taste, right when you need it.")
        }
    }

    private func storyPage(index: Int, tag: Int, isLast: Bool) -> StoryPage {
        let onAdvance = advanceAction(from: tag, isLast: isLast)
        let ctaID = "onboardingContinuePage\(index)"
        switch index {
        case 0:
            let copy = pageOneCopy
            return StoryPage(
                icon: "mug.fill",
                title: copy.title,
                description: copy.description,
                // Beer-native amber hero (matches the Check idle motif) — the
                // age gate already owns the teal mug; don't repeat it here.
                iconStyle: AnyShapeStyle(StyleGradient.gradient(for: "IPA")),
                contentAccessibilityID: "onboardingStoryBuyingHelp",
                continueAccessibilityID: ctaID,
                onAdvance: onAdvance
            )
        case 1:
            if scanVignetteRaw == "icon" {
                return StoryPage(
                    icon: "camera.fill",
                    title: variant == .control ? "Scan a label, get a verdict" : "Your call, in a glance.",
                    description: variant == .control
                        ? "Based on your taste, not the hype."
                        : "A personal TRY IT or SKIP IT that gets sharper with every rating.",
                    contentAccessibilityID: "onboardingStoryVerdictLearning",
                    continueAccessibilityID: ctaID,
                    onAdvance: onAdvance
                )
            }
            return StoryPage(
                icon: "camera.fill",
                title: variant == .control ? "Try it. Skip it. Your call." : "Your call, in a glance.",
                description: variant == .control
                    ? "Point your camera. Get your verdict."
                    : "A personal TRY IT or SKIP IT that gets sharper with every rating.",
                hero: AnyView(ScanVignetteView(variant: ScanVignetteVariant(rawValue: scanVignetteRaw) ?? .full)),
                contentAccessibilityID: "onboardingStoryVerdictLearning",
                continueAccessibilityID: ctaID,
                onAdvance: onAdvance
            )
        default:
            return StoryPage(
                icon: "sparkles",
                title: "The more you log, the better it gets",
                description: "Every beer you rate teaches SipCheck your taste. Your picks get sharper every week.",
                contentAccessibilityID: "onboardingStoryLearningControl",
                continueAccessibilityID: ctaID,
                onAdvance: onAdvance
            )
        }
    }
}

// MARK: - Story Page

private struct StoryPage: View {
    let icon: String
    let title: String
    let description: String
    /// Optional custom hero (e.g. the scan vignette). When nil, the SF Symbol
    /// `icon` renders in its place.
    var hero: AnyView? = nil
    var iconStyle: AnyShapeStyle = AnyShapeStyle(SipColors.accent)
    let contentAccessibilityID: String
    let continueAccessibilityID: String
    let onAdvance: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var heroIconSize: CGFloat = 80

    var body: some View {
        VStack(spacing: SipSpacing.xl) {
            Spacer()
            if let hero {
                hero
            } else {
                Image(systemName: icon)
                    .font(.system(size: heroIconSize))
                    .foregroundStyle(iconStyle)
            }
            Text(title)
                .font(SipTypography.title)
                .foregroundColor(SipColors.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("\(contentAccessibilityID)Title")
            Text(description)
                .font(SipTypography.body)
                .foregroundColor(SipColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .accessibilityIdentifier("\(contentAccessibilityID)Description")
            Spacer()

            // Swipe-only advance is undiscoverable — every story page gets an
            // explicit primary Continue.
            Button(action: onAdvance) {
                Text("Continue")
            }
            .buttonStyle(SipPrimaryButtonStyle())
            .accessibilityIdentifier(continueAccessibilityID)
            .padding(.horizontal, SipSpacing.xl)
            // Clear the system page dots below the CTA.
            .padding(.bottom, 56)
        }
    }
}

// MARK: - Picker Page Scaffold

private func onboardingGridColumns(
    normalCount: Int,
    dynamicTypeSize: DynamicTypeSize
) -> [GridItem] {
    let count = dynamicTypeSize.isAccessibilitySize ? 1 : normalCount
    return Array(
        repeating: GridItem(.flexible(minimum: 0), spacing: SipSpacing.s),
        count: count
    )
}

// MARK: - Visual Beer Picker

/// Compact, code-native product cues for onboarding. The palette and wordmark
/// are deliberately brand-specific so a familiar can is recognizable before
/// the user has to read a dense list of names.
private struct OnboardingBeerBrand {
    let top: Color
    let bottom: Color
    let label: Color
    let ink: Color
    let accent: Color
    let mark: String
}

private func onboardingBeerBrand(for beer: String) -> OnboardingBeerBrand {
    switch beer {
    case "Modelo":
        return OnboardingBeerBrand(top: Color(hex: "#E7D5A6"), bottom: Color(hex: "#B9903C"), label: Color(hex: "#F5E9C8"), ink: Color(hex: "#18233A"), accent: Color(hex: "#C62828"), mark: "MODELO")
    case "Corona":
        return OnboardingBeerBrand(top: Color(hex: "#F6E6A7"), bottom: Color(hex: "#D4A72C"), label: Color(hex: "#F8F1D7"), ink: Color(hex: "#163B69"), accent: Color(hex: "#D4A72C"), mark: "CORONA")
    case "Heineken":
        return OnboardingBeerBrand(top: Color(hex: "#168544"), bottom: Color(hex: "#075A2C"), label: Color(hex: "#F2F0DF"), ink: Color(hex: "#075A2C"), accent: Color(hex: "#D9272E"), mark: "HEINEKEN")
    case "Blue Moon":
        return OnboardingBeerBrand(top: Color(hex: "#214B83"), bottom: Color(hex: "#102B52"), label: Color(hex: "#E7EDF4"), ink: Color(hex: "#14335F"), accent: Color(hex: "#F18A2A"), mark: "BLUE\nMOON")
    case "Sam Adams":
        return OnboardingBeerBrand(top: Color(hex: "#133C67"), bottom: Color(hex: "#09223E"), label: Color(hex: "#F4E9D3"), ink: Color(hex: "#12355B"), accent: Color(hex: "#B4292E"), mark: "SAM\nADAMS")
    case "Guinness":
        return OnboardingBeerBrand(top: Color(hex: "#26221D"), bottom: Color(hex: "#090909"), label: Color(hex: "#E8D6A3"), ink: Color(hex: "#15100B"), accent: Color(hex: "#C9A24B"), mark: "GUINNESS")
    case "Sierra Nevada":
        return OnboardingBeerBrand(top: Color(hex: "#30653A"), bottom: Color(hex: "#173B23"), label: Color(hex: "#E8D8A4"), ink: Color(hex: "#23462A"), accent: Color(hex: "#C56D2E"), mark: "SIERRA\nNEVADA")
    case "Lagunitas":
        return OnboardingBeerBrand(top: Color(hex: "#F0E8D6"), bottom: Color(hex: "#C8B998"), label: Color(hex: "#F6F1E6"), ink: Color(hex: "#17304C"), accent: Color(hex: "#B5202A"), mark: "LAGUNITAS")
    case "Hazy Little Thing":
        return OnboardingBeerBrand(top: Color(hex: "#58B9A7"), bottom: Color(hex: "#277C75"), label: Color(hex: "#F0B52E"), ink: Color(hex: "#173F3A"), accent: Color(hex: "#F6D66A"), mark: "HAZY\nLITTLE")
    case "Coors Light":
        return OnboardingBeerBrand(top: Color(hex: "#E8EAEC"), bottom: Color(hex: "#AEB5BC"), label: Color(hex: "#F6F6F3"), ink: Color(hex: "#A4232C"), accent: Color(hex: "#4E7EA7"), mark: "COORS")
    case "Bud Light":
        return OnboardingBeerBrand(top: Color(hex: "#1A69B7"), bottom: Color(hex: "#084B8D"), label: Color(hex: "#E9F2F8"), ink: Color(hex: "#145B9F"), accent: Color(hex: "#F5F3F0"), mark: "BUD\nLIGHT")
    case "Stella Artois":
        return OnboardingBeerBrand(top: Color(hex: "#F0E6CF"), bottom: Color(hex: "#CDBE9E"), label: Color(hex: "#F5EFE2"), ink: Color(hex: "#9C1F27"), accent: Color(hex: "#C79C32"), mark: "STELLA")
    case "Allagash White":
        return OnboardingBeerBrand(top: Color(hex: "#3E7EB5"), bottom: Color(hex: "#22527D"), label: Color(hex: "#F0E0A8"), ink: Color(hex: "#204E78"), accent: Color(hex: "#E6AD31"), mark: "ALLAGASH")
    case "Dogfish Head":
        return OnboardingBeerBrand(top: Color(hex: "#476B3E"), bottom: Color(hex: "#223B27"), label: Color(hex: "#1C1C1C"), ink: Color(hex: "#F29A38"), accent: Color(hex: "#F29A38"), mark: "DOGFISH")
    case "Stone IPA":
        return OnboardingBeerBrand(top: Color(hex: "#252525"), bottom: Color(hex: "#090909"), label: Color(hex: "#147A5A"), ink: Color(hex: "#F3F1E8"), accent: Color(hex: "#58B98E"), mark: "STONE")
    default: // Goose Island
        return OnboardingBeerBrand(top: Color(hex: "#23735B"), bottom: Color(hex: "#104B3B"), label: Color(hex: "#F3E9C9"), ink: Color(hex: "#175A47"), accent: Color(hex: "#E2B52D"), mark: "GOOSE")
    }
}

private func onboardingAccessibilitySlug(_ value: String) -> String {
    value.lowercased()
        .replacingOccurrences(of: "&", with: "and")
        .replacingOccurrences(of: " ", with: "-")
}

private struct OnboardingBeerCan: View {
    let beer: String

    private var brand: OnboardingBeerBrand { onboardingBeerBrand(for: beer) }

    var body: some View {
        let can = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ZStack {
            can.fill(
                LinearGradient(
                    colors: [brand.top, brand.bottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            VStack(spacing: 0) {
                Capsule()
                    .fill(SipColors.textPrimary.opacity(0.4))
                    .frame(width: 34, height: 3)
                    .padding(.top, 4)
                Spacer()
                Capsule()
                    .fill(SipColors.background.opacity(0.28))
                    .frame(width: 34, height: 3)
                    .padding(.bottom, 4)
            }

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(brand.label)
                .frame(width: 44, height: 35)
                .overlay {
                    Text(brand.mark)
                        .font(SipTypography.caption.weight(.black))
                        .foregroundColor(brand.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(brand.mark.contains("\n") ? 2 : 1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 2)
                }

            Circle()
                .fill(brand.accent)
                .frame(width: 9, height: 9)
                .offset(x: 18, y: -27)
        }
        .frame(width: 54, height: 78)
        .clipShape(can)
        .overlay(can.strokeBorder(SipColors.textPrimary.opacity(0.18), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

private struct OnboardingBeerTile: View {
    let beer: String
    let isSelected: Bool
    let accessibilityPrefix: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            VStack(spacing: SipSpacing.s) {
                OnboardingBeerCan(beer: beer)

                Text(beer)
                    .font(SipTypography.caption.weight(.semibold))
                    .foregroundColor(isSelected ? SipColors.textPrimary : SipColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 48 : 34)
            }
            .padding(.horizontal, SipSpacing.s)
            .padding(.vertical, SipSpacing.s)
            .frame(width: dynamicTypeSize.isAccessibilitySize ? 118 : 102,
                   height: dynamicTypeSize.isAccessibilitySize ? 158 : 132)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? SipColors.accentSubtle : SipColors.surface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? SipColors.accent : SipColors.textSecondary.opacity(0.2),
                                  lineWidth: isSelected ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(SipTypography.headline)
                        .foregroundStyle(SipColors.background, SipColors.accent)
                        .padding(SipSpacing.xs)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(beer)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to \(isSelected ? "remove" : "select")")
        .accessibilityIdentifier("\(accessibilityPrefix).\(onboardingAccessibilitySlug(beer))")
    }
}

private struct OnboardingBeerCarousel: View {
    let selectedBeers: Set<String>
    let accessibilityPrefix: String
    let onToggle: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: SipSpacing.s) {
                ForEach(onboardingBeerOptions, id: \.self) { beer in
                    OnboardingBeerTile(
                        beer: beer,
                        isSelected: selectedBeers.contains(beer),
                        accessibilityPrefix: accessibilityPrefix
                    ) {
                        onToggle(beer)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct OnboardingStyleStrip: View {
    let selectedStyles: Set<BeerStyle>
    let accessibilityPrefix: String
    let onToggle: (BeerStyle) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var rows: [GridItem] {
        let rowCount = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.fixed(dynamicTypeSize.isAccessibilitySize ? 68 : 48), spacing: SipSpacing.s),
                     count: rowCount)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: rows, spacing: SipSpacing.s) {
                ForEach(onboardingStyleChips, id: \.self) { style in
                    ChipButton(
                        label: styleChipLabel(style),
                        isSelected: selectedStyles.contains(style),
                        anchorCaption: styleChipAnchor(style),
                        fillsAvailableWidth: true
                    ) {
                        onToggle(style)
                    }
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? 176 : 152)
                    .accessibilityIdentifier("\(accessibilityPrefix).\(onboardingAccessibilitySlug(style.rawValue))")
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 72 : 106)
    }
}

/// Shared chrome for every CTA-block page: scrolling header + content above a
/// reserved bottom band (one primary CTA and one quiet skip). Used by the
/// legacy picker, both new pickers, and the
/// taste quiz.
private struct PickerPageScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let primaryTitle: String
    let primaryAccessibilityID: String
    var primaryDisabled: Bool = false
    let primaryAction: () -> Void
    let quietTitle: String
    let quietAccessibilityID: String
    let quietAction: () -> Void
    let content: () -> Content

    init(
        title: String,
        subtitle: String,
        primaryTitle: String,
        primaryAccessibilityID: String,
        primaryDisabled: Bool = false,
        primaryAction: @escaping () -> Void,
        quietTitle: String,
        quietAccessibilityID: String,
        quietAction: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.primaryTitle = primaryTitle
        self.primaryAccessibilityID = primaryAccessibilityID
        self.primaryDisabled = primaryDisabled
        self.primaryAction = primaryAction
        self.quietTitle = quietTitle
        self.quietAccessibilityID = quietAccessibilityID
        self.quietAction = quietAction
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SipSpacing.xl) {
                VStack(alignment: .leading, spacing: SipSpacing.s) {
                    Text(title)
                        .font(SipTypography.title)
                        .foregroundColor(SipColors.textPrimary)
                    Text(subtitle)
                        .font(SipTypography.subhead)
                        .foregroundColor(SipColors.textSecondary)
                }
                .padding(.top, SipSpacing.xl)

                content()
            }
            .padding(.horizontal, SipSpacing.xl)
            .padding(.bottom, SipSpacing.l)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: SipSpacing.m) {
                Button(action: primaryAction) {
                    Text(primaryTitle)
                }
                .buttonStyle(SipPrimaryButtonStyle())
                .disabled(primaryDisabled)
                .accessibilityIdentifier(primaryAccessibilityID)

                Button(action: quietAction) {
                    Text(quietTitle)
                }
                .buttonStyle(SipQuietButtonStyle())
                .accessibilityIdentifier(quietAccessibilityID)
            }
            .padding(.horizontal, SipSpacing.xl)
            .padding(.top, SipSpacing.m)
            .padding(.bottom, SipSpacing.s)
            .background(SipColors.background)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(SipColors.textSecondary.opacity(0.16))
                    .frame(height: 0.5)
            }
        }
    }
}

// MARK: - Legacy Beer Picker Page (control variant — strings unchanged)

private struct BeerPickerPage: View {
    /// Lab preview: chips stay interactive but nothing persists.
    let isPreview: Bool
    let onAdvance: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedBeers: Set<String> = []
    /// Monotonic guard: only the newest persistSelections snapshot may write.
    @State private var persistGeneration = 0

    var body: some View {
        PickerPageScaffold(
            title: "Beers you've had before?",
            subtitle: "Tap any you've tried. We'll use it to calibrate your taste.",
            primaryTitle: "Next →",
            primaryAccessibilityID: "onboardingPickerNext",
            primaryAction: advance,
            quietTitle: "Skip",
            quietAccessibilityID: "onboardingPickerSkip",
            // Skip must NOT persist — write-through on every tap already
            // stored real picks; a skip only moves on.
            quietAction: onAdvance
        ) {
            LazyVGrid(
                columns: onboardingGridColumns(normalCount: 3, dynamicTypeSize: dynamicTypeSize),
                alignment: .leading,
                spacing: SipSpacing.s
            ) {
                ForEach(onboardingBeerOptions, id: \.self) { beer in
                    ChipButton(
                        label: beer,
                        isSelected: selectedBeers.contains(beer),
                        fillsAvailableWidth: true
                    ) {
                        toggleBeer(beer)
                    }
                }
            }
        }
        .onAppear {
            // Replay/reinstall: restore prior picks so the first new tap's
            // write-through doesn't overwrite a multi-beer selection (and its
            // synced seed styles) with a single beer.
            if selectedBeers.isEmpty {
                selectedBeers = Set(TastePreferences.savedKnownBeers).intersection(Set(onboardingBeerOptions))
            }
        }
    }

    private func toggleBeer(_ beer: String) {
        if selectedBeers.contains(beer) {
            selectedBeers.remove(beer)
        } else {
            selectedBeers.insert(beer)
        }
        // Write-through on every tap: swiping to the next page (instead of
        // tapping Next) used to silently discard all picks.
        persistSelections()
    }

    /// Persist the picks AND the styles they resolve to — the seed the verdict
    /// engine actually consumes. Resolution runs off-main (catalog decode);
    /// the generation guard makes the LATEST tap's snapshot win — unordered
    /// task completion must not let a stale subset be the last write.
    private func persistSelections() {
        guard !isPreview else { return } // Lab preview never touches taste data
        persistGeneration += 1
        let generation = persistGeneration
        let beers = Array(selectedBeers)

        Task {
            let styles: [String] = await Task.detached(priority: .utility) {
                // Same catalog+inference fusion the scan path uses, so the
                // seed style for a beer matches what scanning it would resolve.
                Array(Set(beers.compactMap {
                    (TastePreferences.styleForOnboardingBeer($0)
                        ?? BeerResolver.resolve(recognizedText: $0, using: BundledCatalog.shared).style)?.rawValue
                })).sorted()
            }.value
            guard generation == persistGeneration else { return } // stale snapshot
            TastePreferences.saveKnownBeers(beers, seedStyles: styles)
        }
    }

    private func advance() {
        persistSelections()
        onAdvance()
    }
}

// MARK: - Go-To Picker Page

/// "What's your go-to?" — positive cold-start seed from recognizable beer
/// cans and compact style chips. The modern flow asks only the two behavioral
/// poles: always-buy and always-avoid.
private struct GoToPickerPage: View {
    /// "primary" | "alt" — the Lab's `onboardingPickerCopyVariant` value.
    let copyVariant: String
    /// Lab preview: chips stay interactive but nothing persists.
    let isPreview: Bool
    let onAdvance: () -> Void

    @State private var selectedBeers: Set<String> = []
    @State private var selectedGoToStyles: Set<BeerStyle> = []
    /// Replays intentionally open blank. This distinguishes an untouched page
    /// (Next/Skip preserves saved data) from an explicit new answer.
    @State private var hasEditedSelections = false
    /// Monotonic guard: only the newest persistSelections snapshot may write.
    @State private var persistGeneration = 0

    private var title: String {
        copyVariant == "alt" ? "What's in your fridge right now?" : "What's your go-to?"
    }

    // Present/past indicative only — recall of purchases that already happen,
    // never a conditional "what would you enjoy?".
    private var subtitle: String {
        copyVariant == "alt"
            ? "Tap what's actually in there."
            : "Tap the beers you buy without thinking."
    }

    var body: some View {
        PickerPageScaffold(
            title: title,
            subtitle: subtitle,
            primaryTitle: "Next →",
            primaryAccessibilityID: "onboardingPickerNext",
            primaryAction: advance,
            quietTitle: "Skip",
            quietAccessibilityID: "onboardingPickerSkip",
            // Skip never writes — real picks were already written through.
            quietAction: onAdvance
        ) {
            VStack(alignment: .leading, spacing: SipSpacing.m) {
                Text("Beers")
                    .font(SipTypography.headline)
                    .foregroundColor(SipColors.textPrimary)
                OnboardingBeerCarousel(
                    selectedBeers: selectedBeers,
                    accessibilityPrefix: "onboardingGoToBeerTile",
                    onToggle: toggleBeer
                )
            }

            VStack(alignment: .leading, spacing: SipSpacing.m) {
                Text("Styles")
                    .font(SipTypography.headline)
                    .foregroundColor(SipColors.textPrimary)
                OnboardingStyleStrip(
                    selectedStyles: selectedGoToStyles,
                    accessibilityPrefix: "onboardingGoToStyle",
                    onToggle: toggleStyle
                )
            }
        }
    }

    private func toggleStyle(_ style: BeerStyle) {
        if selectedGoToStyles.contains(style) {
            selectedGoToStyles.remove(style)
        } else {
            selectedGoToStyles.insert(style)
        }
        hasEditedSelections = true
        // Write-through on every tap.
        persistSelections()
    }

    private func toggleBeer(_ beer: String) {
        if selectedBeers.contains(beer) {
            selectedBeers.remove(beer)
        } else {
            selectedBeers.insert(beer)
        }
        hasEditedSelections = true
        // Write-through on every tap: swiping to the next page (instead of
        // tapping Next) must not silently discard picks.
        persistSelections()
    }

    /// Persist the picks, the explicit style chips, AND the styles the beer
    /// picks resolve to — the seed the verdict engine actually consumes.
    /// Resolution runs off-main (catalog decode); the generation guard makes
    /// the LATEST tap's snapshot win — unordered task completion must not let
    /// a stale subset be the last write.
    private func persistSelections() {
        // An untouched replay page is visually blank by design. Next and Skip
        // must not turn that presentation choice into a destructive clear.
        guard hasEditedSelections, !isPreview else { return }
        persistGeneration += 1
        let generation = persistGeneration
        let beers = Array(selectedBeers)
        // Snapshot the chips BEFORE the async hop — the save writes all three
        // keys, so a stale chip set must never ride along with a fresh
        // beer resolution.
        let styleChips = selectedGoToStyles.map(\.rawValue).sorted()

        Task {
            let styles: [String] = await Task.detached(priority: .utility) {
                // Same catalog+inference fusion the scan path uses, so the
                // seed style for a beer matches what scanning it would resolve.
                Array(Set(beers.compactMap {
                    (TastePreferences.styleForOnboardingBeer($0)
                        ?? BeerResolver.resolve(recognizedText: $0, using: BundledCatalog.shared).style)?.rawValue
                })).sorted()
            }.value
            guard generation == persistGeneration else { return } // stale snapshot
            TastePreferences.saveGoTo(beers: beers, styleChips: styleChips, seedStyles: styles)
        }
    }

    private func advance() {
        persistSelections()
        onAdvance()
    }
}

// MARK: - Stay-Away Picker Page

/// "What do you always walk past?" — the negative seed (founder point 4).
/// Persists the raw picks (beer names + style rawValues) plus the styles they
/// resolve to; the scorer's avoid set is checked before liked weights.
private struct StayAwayPickerPage: View {
    /// "primary" | "alt" — the Lab's `onboardingPickerCopyVariant` value.
    let copyVariant: String
    /// When this is the flow's last page its CTA completes onboarding.
    let isLast: Bool
    /// Lab preview: chips stay interactive but nothing persists.
    let isPreview: Bool
    let onAdvance: () -> Void

    @State private var selectedAvoidBeers: Set<String> = []
    @State private var selectedAvoidStyles: Set<BeerStyle> = []
    /// Styles the current picks resolve to — the inline echo's source.
    /// Display-only mirror of what persistAvoidSelections saves, so it also
    /// updates in Lab previews (resolution is read-only; persistence isn't).
    @State private var echoedAvoidStyles: [String] = []
    /// Replays intentionally open blank. An untouched page must preserve the
    /// saved hard-avoid profile even when its primary CTA is used.
    @State private var hasEditedAvoidSelections = false
    /// Monotonic guard (own counter, parallel to the go-to page's): only the
    /// newest persistAvoidSelections snapshot may write.
    @State private var avoidGeneration = 0

    private var title: String {
        copyVariant == "alt" ? "Any hard passes?" : "What do you always walk past?"
    }

    private var subtitle: String {
        copyVariant == "alt"
            ? "We'll steer you clear. No judgment."
            : "Tap what's never coming home with you."
    }

    /// "Got it — steering you clear of stouts, sours." Style rawValues from
    /// the resolver, rendered mid-sentence: pluralized display labels,
    /// lowercased unless the singular is an acronym ("IPAs" stays "IPAs").
    private var echoLine: String {
        let names = echoedAvoidStyles.map { raw -> String in
            guard let style = BeerStyle(rawValue: raw) else { return raw.lowercased() }
            let label = styleChipLabel(style)
            let singular = String(label.dropLast())
            return singular == singular.uppercased() ? label : label.lowercased()
        }
        return "Got it — steering you clear of \(names.joined(separator: ", "))."
    }

    var body: some View {
        PickerPageScaffold(
            title: title,
            subtitle: subtitle,
            primaryTitle: isLast ? "See my picks" : "Next →",
            primaryAccessibilityID: "onboardingStayAwayNext",
            primaryAction: advance,
            quietTitle: "Nothing's off the table",
            quietAccessibilityID: "onboardingStayAwaySkip",
            quietAction: clearAvoidsAndAdvance
        ) {
            VStack(alignment: .leading, spacing: SipSpacing.m) {
                Text("Beers")
                    .font(SipTypography.headline)
                    .foregroundColor(SipColors.textPrimary)
                OnboardingBeerCarousel(
                    selectedBeers: selectedAvoidBeers,
                    accessibilityPrefix: "onboardingStayAwayBeerTile",
                    onToggle: toggleBeer
                )
            }

            VStack(alignment: .leading, spacing: SipSpacing.m) {
                Text("Styles")
                    .font(SipTypography.headline)
                    .foregroundColor(SipColors.textPrimary)
                OnboardingStyleStrip(
                    selectedStyles: selectedAvoidStyles,
                    accessibilityPrefix: "onboardingStayAwayStyle",
                    onToggle: toggleStyle
                )
            }

            // Inline echo of the style generalization the picks resolve to
            // ("Guinness" → stouts) — confirms the avoid registered at the
            // category level and pre-teaches the verdict's "you said so"
            // voice. Appears the moment resolution lands, hides when the
            // last pick is cleared.
            if !echoedAvoidStyles.isEmpty {
                Text(echoLine)
                    .font(SipTypography.caption)
                    .foregroundColor(SipColors.textSecondary)
                    .accessibilityIdentifier("avoidEchoLine")
                    .transition(.opacity)
            }
        }
    }

    private func toggleStyle(_ style: BeerStyle) {
        if selectedAvoidStyles.contains(style) {
            selectedAvoidStyles.remove(style)
        } else {
            selectedAvoidStyles.insert(style)
        }
        hasEditedAvoidSelections = true
        // Write-through on every tap.
        persistAvoidSelections()
    }

    private func toggleBeer(_ beer: String) {
        if selectedAvoidBeers.contains(beer) {
            selectedAvoidBeers.remove(beer)
        } else {
            selectedAvoidBeers.insert(beer)
        }
        hasEditedAvoidSelections = true
        // Write-through on every tap.
        persistAvoidSelections()
    }

    /// Persist the raw avoid picks AND the styles they resolve to. Style
    /// chips resolve directly; beer names go through the same catalog+
    /// inference fusion the scan path uses ("avoid Guinness" must penalize
    /// stouts). Off-main with a generation guard — the LATEST tap's snapshot
    /// wins.
    private func persistAvoidSelections() {
        // Blank is a presentation state until the user touches a choice. This
        // keeps replaying and advancing from erasing a real saved hard avoid.
        guard hasEditedAvoidSelections else { return }
        avoidGeneration += 1
        let generation = avoidGeneration
        let picks = selectedAvoidBeers.sorted() + selectedAvoidStyles.map(\.rawValue).sorted()

        Task {
            let styles: [String] = await Task.detached(priority: .utility) {
                var resolved: Set<String> = []
                for pick in picks {
                    if let direct = BeerStyle.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(pick) == .orderedSame }) {
                        resolved.insert(direct.rawValue)
                    } else if let style = TastePreferences.styleForOnboardingBeer(pick)
                        ?? BeerResolver.resolve(recognizedText: pick, using: BundledCatalog.shared).style {
                        resolved.insert(style.rawValue)
                    }
                }
                return resolved.sorted()
            }.value
            guard generation == avoidGeneration else { return } // stale snapshot
            // Update the inline echo BEFORE the preview gate: the echo is
            // display-only, so Lab previews get it too.
            await MainActor.run {
                withAnimation(.snappy(duration: 0.25)) {
                    echoedAvoidStyles = styles
                }
            }
            guard !isPreview else { return } // Lab preview never touches taste data
            TastePreferences.saveAvoidBeers(picks, avoidStyles: styles)
        }
    }

    private func advance() {
        persistAvoidSelections()
        onAdvance()
    }

    private func clearAvoidsAndAdvance() {
        // This label is an explicit answer, not a generic skip. Invalidate any
        // in-flight resolution from a prior tap before clearing the channel.
        avoidGeneration += 1
        selectedAvoidBeers.removeAll()
        selectedAvoidStyles.removeAll()
        echoedAvoidStyles.removeAll()
        hasEditedAvoidSelections = true
        if !isPreview {
            TastePreferences.saveAvoidBeers([], avoidStyles: [])
        }
        onAdvance()
    }
}

// MARK: - Taste Quiz Page

private struct TasteQuizPage: View {
    /// Q2 ("How adventurous?") — control only. The modern flows use only the
    /// always-buy and always-avoid poles, with an optional vibe experiment.
    let includeAdventure: Bool
    /// Q3 ("Anything you hate?") — control only; the new flows have a whole
    /// stay-away page, so the question would overlap.
    let includeDislikes: Bool
    /// Lab preview: answers stay interactive but nothing persists.
    let isPreview: Bool
    /// The quiz is always the flow's final page: submit and skip both finish.
    let onFinish: () -> Void

    @State private var selectedVibe: String? = nil
    @State private var selectedAdventure: String? = nil
    @State private var selectedDislikes: Set<String> = []

    // Single-sourced from TastePreferences so Settings' editor offers the
    // exact same answer strings (drift would corrupt saved answers).
    private let vibeOptions = TastePreferences.vibeOptions
    private let adventureOptions = TastePreferences.adventureOptions
    private let dislikeOptions = TastePreferences.dislikeOptions

    private var hasRequiredSelections: Bool {
        includeAdventure
            ? selectedVibe != nil && selectedAdventure != nil
            : selectedVibe != nil
    }

    var body: some View {
        PickerPageScaffold(
            title: "Last one — dial in your taste",
            subtitle: "Ten seconds. Way better picks.",
            primaryTitle: "See my picks",
            primaryAccessibilityID: "onboardingQuizSubmit",
            primaryDisabled: !hasRequiredSelections,
            primaryAction: saveAndFinish,
            quietTitle: "Skip — you can tune this later",
            quietAccessibilityID: "onboardingQuizSkip",
            // Skip must NOT persist: it only ends onboarding. Real answers
            // were already written through by the onChange handlers below.
            quietAction: onFinish
        ) {
            // Q1: Vibe
            QuizQuestion(
                question: "Pick your vibe",
                options: vibeOptions,
                multiSelect: false,
                selectedSingle: $selectedVibe,
                selectedMulti: .constant([])
            )

            // Q2: Adventure (control only)
            if includeAdventure {
                QuizQuestion(
                    question: "How adventurous?",
                    options: adventureOptions,
                    multiSelect: false,
                    selectedSingle: $selectedAdventure,
                    selectedMulti: .constant([])
                )
            }

            // Q3: Dislikes (optional; control only)
            if includeDislikes {
                QuizQuestion(
                    question: "Anything you hate?",
                    questionSuffix: "(optional)",
                    options: dislikeOptions,
                    multiSelect: true,
                    selectedSingle: .constant(nil),
                    selectedMulti: $selectedDislikes
                )
            }
        }
        .onAppear {
            restoreSavedAnswers()
        }
        .onChange(of: selectedVibe) { _, _ in persistAnswers() }
        .onChange(of: selectedAdventure) { _, _ in persistAnswers() }
        .onChange(of: selectedDislikes) { _, _ in persistAnswers() }
    }

    /// Restore any previously saved answers so replaying onboarding (or a
    /// reinstall with iCloud KVS answers) starts from what the user already
    /// said — and so Skip can never erase real answers with blanks.
    private func restoreSavedAnswers() {
        let saved = TastePreferences.current
        if selectedVibe == nil, !saved.vibe.isEmpty { selectedVibe = saved.vibe }
        if selectedAdventure == nil, !saved.adventure.isEmpty { selectedAdventure = saved.adventure }
        if selectedDislikes.isEmpty, !saved.dislikes.isEmpty { selectedDislikes = Set(saved.dislikes) }
    }

    /// Write-through on every selection change: quiz answers survive swiping
    /// away mid-quiz, backgrounding, or skipping the final button.
    /// Questions this variant doesn't ask are sourced from the saved profile
    /// at write time — the vibe-only quiz must never blank the adventure the
    /// go-to page just saved (save() writes all three keys locally).
    private func persistAnswers() {
        guard !isPreview else { return } // Lab preview never touches taste data
        let saved = TastePreferences.current
        let adventure = includeAdventure
            ? (selectedAdventure ?? "")
            : (selectedAdventure ?? saved.adventure)
        let dislikes = includeDislikes
            ? selectedDislikes.joined(separator: ",")
            : saved.dislikes.joined(separator: ",")
        TastePreferences.save(
            vibe: selectedVibe ?? "",
            adventure: adventure,
            dislikes: dislikes
        )
    }

    private func saveAndFinish() {
        persistAnswers()
        onFinish()
    }
}

// MARK: - Quiz Question

private struct QuizQuestion: View {
    let question: String
    var questionSuffix: String? = nil
    let options: [String]
    let multiSelect: Bool
    @Binding var selectedSingle: String?
    @Binding var selectedMulti: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: SipSpacing.m) {
            HStack(spacing: SipSpacing.xs) {
                Text(question)
                    .font(SipTypography.headline)
                    .foregroundColor(SipColors.textPrimary)
                if let suffix = questionSuffix {
                    Text(suffix)
                        .font(SipTypography.subhead)
                        .foregroundColor(SipColors.textSecondary)
                }
            }
            ChipGrid(
                options: options,
                multiSelect: multiSelect,
                selectedSingle: $selectedSingle,
                selectedMulti: $selectedMulti
            )
        }
    }
}

// MARK: - Chip Grid

private struct ChipGrid: View {
    let options: [String]
    let multiSelect: Bool
    @Binding var selectedSingle: String?
    @Binding var selectedMulti: Set<String>

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(
            columns: onboardingGridColumns(normalCount: 2, dynamicTypeSize: dynamicTypeSize),
            alignment: .leading,
            spacing: SipSpacing.s
        ) {
            ForEach(options, id: \.self) { option in
                ChipButton(
                    label: option,
                    isSelected: multiSelect
                        ? selectedMulti.contains(option)
                        : selectedSingle == option,
                    fillsAvailableWidth: true
                ) {
                    if multiSelect {
                        if selectedMulti.contains(option) {
                            selectedMulti.remove(option)
                        } else {
                            selectedMulti.insert(option)
                        }
                    } else {
                        selectedSingle = option
                    }
                }
            }
        }
    }
}

// MARK: - Chip Button (thin wrapper over the shared SipChipStyle)
// Internal (not file-private): Settings' TastePreferencesEditorView renders
// the same chips — selected, locked, and captioned — for go-to/stay-away edits.

struct ChipButton: View {
    let label: String
    let isSelected: Bool
    /// Non-nil = locked: the chip is claimed by the opposite picker page.
    /// Locked chips dim, show the caption, and ignore taps — visible but
    /// inert, never hidden.
    var lockedCaption: String? = nil
    /// Optional exemplar anchor ("like Guinness") rendered as a second,
    /// smaller line — style chips carry a concrete beer so answering never
    /// requires beer vocabulary. Display only. While locked, the lock
    /// caption owns the second line and the anchor is suppressed.
    var anchorCaption: String? = nil
    /// Grid-backed chips fill their cell so rows align and the full cell is a
    /// tap target. Standalone chips preserve their compact intrinsic width.
    var fillsAvailableWidth = false
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: {
            if lockedCaption == nil {
                action()
            }
        }) {
            if let caption = lockedCaption ?? anchorCaption {
                VStack(spacing: 2) {
                    Text(label)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(caption)
                        .font(SipTypography.caption)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(label)
                    .lineLimit(fillsAvailableWidth ? 2 : 1, reservesSpace: fillsAvailableWidth)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .buttonStyle(SipChipStyle(
            isSelected: isSelected && lockedCaption == nil,
            fillsAvailableWidth: fillsAvailableWidth
        ))
        .opacity(lockedCaption == nil ? 1 : 0.4)
    }
}

// MARK: - Preview

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .preferredColorScheme(.dark)
    }
}
