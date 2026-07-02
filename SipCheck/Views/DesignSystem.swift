import SwiftUI

// MARK: - Color Tokens (dark values; asset-catalog Any/Dark split deferred to light-mode project)

enum SipColors {
    // Surfaces
    static let background       = Color(hex: "#1A1A1E")   // canvas
    static let surface          = Color(hex: "#2A2A2E")   // cards
    static let surfaceElevated  = Color(hex: "#34343A")   // stacked/nested cards

    // Text
    static let textPrimary      = Color(hex: "#F5F3F0")   // cream, never pure white
    static let textSecondary    = Color(hex: "#8E8E93")

    // Brand ramp (teal)
    static let accent           = Color(hex: "#4ECDC4")
    static let accentPressed    = Color(hex: "#3BA99E")   // ButtonStyle-internal pressed state
    static let accentSubtle     = Color(hex: "#4ECDC4").opacity(0.18)  // selected-chip/tag fills

    // Verdict semantics (traffic ≠ brand)
    static let verdictTry       = Color(hex: "#4CAF50")
    static let verdictSkip      = Color(hex: "#E85D4A")   // warm ember, distinct from destructive
    static let verdictNeutral   = Color(hex: "#E8A317")   // warm amber — intentionally NOT the star gold (crit watchlist: stars ≠ verdict hue)
    static let onVerdictNeutral = Color(hex: "#1A1A1E")   // dark text on amber — white-on-gold fix

    // Utility
    static let destructive      = Color(hex: "#FF453A")   // delete/sign-out only; delete ≠ skip
    static let starFilled       = Color(hex: "#F1C40F")   // gold = rating language only
    static let starEmpty        = Color(hex: "#3A3A3E")
    static let warning          = Color(hex: "#F1C40F")   // error-banner icon tint (replaces hardcoded .orange)
}

// MARK: - Typography (Dynamic Type; hierarchy by weight + opacity, not size soup)

enum SipTypography {
    static let verdictHero = Font.system(size: 48, weight: .heavy, design: .rounded)
    static let numberHero  = Font.system(size: 44, weight: .heavy)   // + .fontWidth(.compressed) + .monospacedDigit() at call site
    static let title       = Font.title2.weight(.bold)
    static let headline    = Font.headline
    static let body        = Font.body
    static let subhead     = Font.subheadline.weight(.medium)
    static let caption     = Font.caption                            // nothing below .caption2 ever
}
// Hero scaling pattern (call-site, since @ScaledMetric is a property wrapper):
//   @ScaledMetric(relativeTo: .largeTitle) private var verdictSize: CGFloat = 48
//   Text(word).font(.system(size: verdictSize, weight: .heavy, design: .rounded))

// MARK: - Spacing / Radius

enum SipSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum SipRadius {
    static let badge: CGFloat = 6
    static let control: CGFloat = 12
    static let card: CGFloat = 16
    static let hero: CGFloat = 24
    // chips = Capsule. Concentric rule: nested radius = outer radius − padding.
}

// MARK: - Verdict presentation (single source; replaces duplicated switches)

struct VerdictStyle {
    let word: String        // EXACTLY "TRY IT" / "SKIP IT" / "YOUR CALL" — test-load-bearing, do not reword
    let color: Color
    let symbol: String
    let textColor: Color    // textPrimary for try/skip; onVerdictNeutral for yourCall

    static func style(for verdict: Verdict) -> VerdictStyle {
        switch verdict {
        case .tryIt:
            return VerdictStyle(word: "TRY IT",
                                color: SipColors.verdictTry,
                                symbol: "hand.thumbsup.fill",
                                textColor: SipColors.textPrimary)
        case .skipIt:
            return VerdictStyle(word: "SKIP IT",
                                color: SipColors.verdictSkip,
                                symbol: "hand.thumbsdown.fill",
                                textColor: SipColors.textPrimary)
        case .yourCall:
            return VerdictStyle(word: "YOUR CALL",
                                color: SipColors.verdictNeutral,
                                symbol: "hand.raised.fill",
                                textColor: SipColors.onVerdictNeutral)
        }
    }
}

// MARK: - Shared button/chip/card styles

struct SipPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SipTypography.headline)
            .foregroundColor(isEnabled ? SipColors.background : SipColors.textSecondary)
            .padding(.vertical, 14)
            .padding(.horizontal, SipSpacing.l)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                    .fill(isEnabled
                          ? (configuration.isPressed ? SipColors.accentPressed : SipColors.accent)
                          : SipColors.surface)
            )
            .animation(.snappy(duration: 0.25), value: configuration.isPressed)
    }
}

struct SipSecondaryButtonStyle: ButtonStyle {
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    init(tint: Color = SipColors.accent) {
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SipTypography.headline)
            .foregroundColor(isEnabled ? tint : SipColors.textSecondary)
            .padding(.vertical, 14)
            .padding(.horizontal, SipSpacing.l)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                    .strokeBorder(isEnabled ? tint : SipColors.textSecondary, lineWidth: 2)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.snappy(duration: 0.25), value: configuration.isPressed)
    }
}

struct SipQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SipTypography.subhead)
            .foregroundColor(SipColors.accent)
            .padding(.horizontal, SipSpacing.m)
            .frame(minHeight: 44)   // quiet ≠ untappable
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.snappy(duration: 0.25), value: configuration.isPressed)
    }
}

struct SipChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SipTypography.subhead)
            .foregroundColor(isSelected ? SipColors.background : SipColors.textSecondary)
            .padding(.horizontal, SipSpacing.l)
            .padding(.vertical, SipSpacing.s)
            .frame(minHeight: 44)
            .background(
                Capsule()
                    .fill(isSelected ? SipColors.accent : SipColors.surface)
            )
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.snappy(duration: 0.25), value: configuration.isPressed)
    }
}

extension View {
    /// Standard opaque card treatment. Content sits on opaque surfaces — never glass.
    func sipCard(radius: CGFloat = SipRadius.card, fill: Color = SipColors.surface) -> some View {
        self.padding(SipSpacing.l)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
    }
}

// MARK: - SRM style gradient (deterministic, asset-free beer-color backdrops)

enum StyleGradient {
    /// Deterministic two-stop beer colors for a style string.
    /// stout near-black brown → pilsner pale gold. nil/unknown → neutral surfaces (verdict is the only color).
    static func stops(for style: String?) -> (top: Color, bottom: Color) {
        guard let raw = style?.lowercased(), !raw.isEmpty else {
            return (SipColors.surface, SipColors.surfaceElevated)
        }
        func has(_ keys: String...) -> Bool { keys.contains { raw.contains($0) } }

        if has("stout") {
            return (Color(hex: "#2A1B12"), Color(hex: "#14100C"))   // near-black w/ warm edge
        }
        if has("porter", "brown") {
            return (Color(hex: "#6B3A22"), Color(hex: "#3A1E12"))
        }
        if has("amber", "red", "märzen", "marzen") {
            return (Color(hex: "#C86A2E"), Color(hex: "#8E3B1B"))
        }
        if has("sour", "fruit") {
            return (Color(hex: "#E06A8A"), Color(hex: "#A03A5C"))
        }
        if has("wheat", "hefeweizen", "wit") {
            return (Color(hex: "#F5D06F"), Color(hex: "#E0A83C"))
        }
        if has("ipa", "pale ale") {
            return (Color(hex: "#E8A33D"), Color(hex: "#B96A24"))   // amber
        }
        if has("pilsner", "lager", "helles") {
            return (Color(hex: "#F8E08E"), Color(hex: "#D9A441"))   // pale gold
        }
        return (SipColors.surface, SipColors.surfaceElevated)
    }

    static func gradient(for style: String?) -> LinearGradient {
        let colors = stops(for: style)
        return LinearGradient(colors: [colors.top, colors.bottom],
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing)
    }

    /// Single representative beer color (top stop) — for dots, tints, mini accents.
    static func color(for style: String?) -> Color {
        stops(for: style).top
    }
}

// MARK: - Liquid Glass compatibility helpers (the ONLY place glass APIs are called)

extension View {
    @ViewBuilder
    func compatGlass(cornerRadius: CGFloat = SipRadius.card, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                .regular.tint(tint).interactive(interactive),
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    func compatGlassCircle(interactive: Bool = true) -> some View {   // camera-overlay round buttons
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(interactive), in: .circle)
        } else {
            self.background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    func compatScrollEdgeSoft() -> some View {                        // journal/profile scroll-edge tuning
        if #available(iOS 26.0, *) { self.scrollEdgeEffectStyle(.soft, for: .top) } else { self }
    }
}

// Container: no-op pre-26. REQUIRED around any group of sibling compatGlass views (glass cannot sample glass).
struct CompatGlassContainer<Content: View>: View {
    let spacing: CGFloat?
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

// MARK: - Color Hex Extension
// Use of Color(hex:) is BANNED outside DesignSystem.swift.

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Preview

struct DesignSystem_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SipSpacing.xl) {
                // MARK: Surfaces
                sectionHeader("Surfaces")
                HStack(spacing: SipSpacing.m) {
                    colorSwatch(SipColors.background, name: "background")
                    colorSwatch(SipColors.surface, name: "surface")
                    colorSwatch(SipColors.surfaceElevated, name: "surfaceElevated")
                }

                // MARK: Brand ramp
                sectionHeader("Brand (teal)")
                HStack(spacing: SipSpacing.m) {
                    colorSwatch(SipColors.accent, name: "accent")
                    colorSwatch(SipColors.accentPressed, name: "accentPressed")
                    colorSwatch(SipColors.accentSubtle, name: "accentSubtle")
                }

                // MARK: Text
                sectionHeader("Text")
                HStack(spacing: SipSpacing.m) {
                    colorSwatch(SipColors.textPrimary, name: "textPrimary")
                    colorSwatch(SipColors.textSecondary, name: "textSecondary")
                }

                // MARK: Verdict semantics
                sectionHeader("Verdict")
                HStack(spacing: SipSpacing.m) {
                    colorSwatch(SipColors.verdictTry, name: "verdictTry")
                    colorSwatch(SipColors.verdictSkip, name: "verdictSkip")
                    colorSwatch(SipColors.verdictNeutral, name: "verdictNeutral")
                    colorSwatch(SipColors.destructive, name: "destructive")
                }
                HStack(spacing: SipSpacing.m) {
                    verdictBadge(.tryIt)
                    verdictBadge(.skipIt)
                    verdictBadge(.yourCall)
                }

                // MARK: Stars / utility
                sectionHeader("Stars & Utility")
                HStack(spacing: SipSpacing.m) {
                    colorSwatch(SipColors.starFilled, name: "starFilled")
                    colorSwatch(SipColors.starEmpty, name: "starEmpty")
                    colorSwatch(SipColors.warning, name: "warning")
                }

                Divider()
                    .background(SipColors.textSecondary)

                // MARK: Typography
                sectionHeader("Typography")
                VStack(alignment: .leading, spacing: SipSpacing.m) {
                    Text("TRY IT")
                        .font(SipTypography.verdictHero)
                        .foregroundColor(SipColors.verdictTry)
                    Text("128")
                        .font(SipTypography.numberHero)
                        .monospacedDigit()
                        .foregroundColor(SipColors.textPrimary)
                    Text("Title — title2 bold")
                        .font(SipTypography.title)
                        .foregroundColor(SipColors.textPrimary)
                    Text("Headline")
                        .font(SipTypography.headline)
                        .foregroundColor(SipColors.textPrimary)
                    Text("Body — descriptions")
                        .font(SipTypography.body)
                        .foregroundColor(SipColors.textPrimary)
                    Text("Subhead — metadata (ABV, style)")
                        .font(SipTypography.subhead)
                        .foregroundColor(SipColors.textSecondary)
                    Text("Caption — timestamps")
                        .font(SipTypography.caption)
                        .foregroundColor(SipColors.textSecondary)
                }

                Divider()
                    .background(SipColors.textSecondary)

                // MARK: Button styles
                sectionHeader("Buttons")
                VStack(spacing: SipSpacing.m) {
                    Button("Primary — Log it") {}
                        .buttonStyle(SipPrimaryButtonStyle())
                    Button("Primary disabled") {}
                        .buttonStyle(SipPrimaryButtonStyle())
                        .disabled(true)
                    Button("Secondary — Save for Later") {}
                        .buttonStyle(SipSecondaryButtonStyle())
                    Button("Secondary destructive") {}
                        .buttonStyle(SipSecondaryButtonStyle(tint: SipColors.destructive))
                    Button("Quiet — Scan Another") {}
                        .buttonStyle(SipQuietButtonStyle())
                    HStack(spacing: SipSpacing.s) {
                        Button("Selected") {}
                            .buttonStyle(SipChipStyle(isSelected: true))
                        Button("Unselected") {}
                            .buttonStyle(SipChipStyle(isSelected: false))
                    }
                }

                // MARK: Style gradients
                sectionHeader("Style Gradients (SRM)")
                HStack(spacing: SipSpacing.m) {
                    gradientSwatch("Pilsner")
                    gradientSwatch("Hefeweizen")
                    gradientSwatch("IPA")
                    gradientSwatch("Stout")
                }

                // MARK: Card
                sectionHeader("Card")
                Text("Opaque card — never glass")
                    .font(SipTypography.body)
                    .foregroundColor(SipColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sipCard()
            }
            .padding(SipSpacing.l)
        }
        .background(SipColors.background)
        .preferredColorScheme(.dark)
        .previewDisplayName("Design System")
    }

    private static func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(SipTypography.headline)
            .foregroundColor(SipColors.accent)
    }

    private static func colorSwatch(_ color: Color, name: String) -> some View {
        VStack(spacing: SipSpacing.xs) {
            RoundedRectangle(cornerRadius: SipRadius.badge, style: .continuous)
                .fill(color)
                .frame(width: 60, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: SipRadius.badge, style: .continuous)
                        .stroke(SipColors.textSecondary.opacity(0.3), lineWidth: 1)
                )
            Text(name)
                .font(SipTypography.caption)
                .foregroundColor(SipColors.textSecondary)
        }
    }

    private static func verdictBadge(_ verdict: Verdict) -> some View {
        let style = VerdictStyle.style(for: verdict)
        return HStack(spacing: SipSpacing.xs) {
            Image(systemName: style.symbol)
            Text(style.word)
        }
        .font(SipTypography.caption)
        .foregroundColor(style.textColor)
        .padding(.horizontal, SipSpacing.s)
        .padding(.vertical, SipSpacing.xs)
        .background(Capsule().fill(style.color))
    }

    private static func gradientSwatch(_ style: String) -> some View {
        VStack(spacing: SipSpacing.xs) {
            RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                .fill(StyleGradient.gradient(for: style))
                .frame(width: 70, height: 60)
            Text(style)
                .font(SipTypography.caption)
                .foregroundColor(SipColors.textSecondary)
        }
    }
}
