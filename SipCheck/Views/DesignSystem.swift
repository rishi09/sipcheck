import SwiftUI

// Upload-retry marker (harmless): 2

// MARK: - Color Tokens (dark values; asset-catalog Any/Dark split deferred to light-mode project)

enum SipColors {
    // Surfaces
    static let background       = Color(hex: "#1A1A1E")   // canvas
    static let surface          = Color(hex: "#2A2A2E")   // cards
    static let surfaceElevated  = Color(hex: "#34343A")   // stacked/nested cards

    // Text
    static let textPrimary      = Color(hex: "#F5F3F0")   // cream, never pure white
    static let textSecondary    = Color(hex: "#8E8E93")
    // Ink for LIGHT SRM surfaces (pale-gold → amber beer headers). Round-2 crit
    // #2: textSecondary gray measured 1.9:1 on the amber header — light SRM
    // surfaces take this warm near-black instead (same dark-on-gold move as the
    // YOUR CALL chip). Pair via StyleGradient.ink(for:), never ad hoc.
    static let srmInk           = Color(hex: "#241505")

    // Brand ramp (teal)
    static let accent           = Color(hex: "#4ECDC4")
    static let accentPressed    = Color(hex: "#3BA99E")   // ButtonStyle-internal pressed state
    static let accentSubtle     = Color(hex: "#4ECDC4").opacity(0.18)  // selected-chip/tag fills

    // Verdict semantics (traffic ≠ brand)
    static let verdictTry       = Color(hex: "#4CAF50")
    static let verdictSkip      = Color(hex: "#E85D4A")   // warm ember, distinct from destructive
    // Text-on-dark variant of verdictSkip: for "Not For Me"/skip chip TEXT on
    // the dark tinted chip fill (verdictSkip.opacity(0.15) blends to ~#392425,
    // where verdictSkip itself only reaches ~3:1 — round-2 crit #5). ~6.3:1.
    static let verdictSkipText  = Color(hex: "#FF8A75")
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
                // Disabled still reads as a BUTTON: elevated fill + hairline.
                // (Round-2 crit #4: surface-on-surface made a disabled Save on
                // a surface-colored sheet look like orphaned placeholder text.)
                RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                    .fill(isEnabled
                          ? (configuration.isPressed ? SipColors.accentPressed : SipColors.accent)
                          : SipColors.surfaceElevated)
            )
            .overlay {
                if !isEnabled {
                    RoundedRectangle(cornerRadius: SipRadius.control, style: .continuous)
                        .strokeBorder(SipColors.textSecondary.opacity(0.35), lineWidth: 1)
                }
            }
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
    var fillsAvailableWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SipTypography.subhead)
            .foregroundColor(isSelected ? SipColors.background : SipColors.textSecondary)
            .padding(.horizontal, SipSpacing.l)
            .padding(.vertical, SipSpacing.s)
            .frame(maxWidth: fillsAvailableWidth ? .infinity : nil, minHeight: 44)
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
            // Luminance floor (round-2 crit #3): the old #2A1B12→#14100C pour
            // vanished into the #1A1A1E canvas — a stout swatch read as a
            // failed image load and a stout bar as 0%. Still the darkest
            // style, but never canvas-dark.
            return (Color(hex: "#4A2F1D"), Color(hex: "#2B1D12"))
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

    /// True when the style's SRM surface is LIGHT (pale gold → amber) and
    /// therefore needs dark ink. Mid (amber/red, sour) and dark (stout,
    /// porter, unknown) surfaces keep cream ink — their stops are too dark for
    /// `srmInk` to clear 4.5:1.
    ///
    /// Mirrors `stops(for:)` bucket precedence EXACTLY: a "Red IPA" resolves
    /// to the amber/red (mid) surface, so it must take cream ink, not dark.
    static func hasLightSurface(_ style: String?) -> Bool {
        guard let raw = style?.lowercased(), !raw.isEmpty else { return false }
        func has(_ keys: String...) -> Bool { keys.contains { raw.contains($0) } }

        if has("stout") { return false }
        if has("porter", "brown") { return false }
        if has("amber", "red", "märzen", "marzen") { return false }
        if has("sour", "fruit") { return false }
        if has("wheat", "hefeweizen", "wit") { return true }
        if has("ipa", "pale ale") { return true }
        if has("pilsner", "lager", "helles") { return true }
        return false
    }

    /// Ink pair guaranteed legible on the style's SRM surface (round-2 crit #2
    /// — the global textSecondary gray hit 1.9:1 on the amber verdict header).
    /// Light surfaces: warm near-black, same dark-on-gold treatment as the
    /// YOUR CALL chip. Everything else: cream — callers pair the cream branch
    /// with a bottom legibility scrim.
    static func ink(for style: String?) -> (primary: Color, secondary: Color) {
        if hasLightSurface(style) {
            return (SipColors.srmInk, SipColors.srmInk.opacity(0.85))
        }
        return (SipColors.textPrimary, SipColors.textPrimary.opacity(0.8))
    }
}

// MARK: - SRM swatch (shared tile — hairline keeps dark pours visible)

/// Standard SRM thumbnail/tile: the style gradient plus a 1px hairline stroke
/// so dark pours (stout, porter) never dissolve into the dark canvas (round-2
/// crit #3 — a hairline-less stout swatch read as a failed image load).
/// Use this instead of a raw gradient-filled RoundedRectangle; size at the
/// call site with `.frame(...)`.
struct SRMSwatch: View {
    let style: String?
    var cornerRadius: CGFloat = SipRadius.control

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(StyleGradient.gradient(for: style))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
    }
}

// MARK: - Floating tab-bar clearance (shared bottom-inset contract)

/// Single clearance number every tab root inherits — round-2 crit #1 replaced
/// the three per-screen 110pt magic paddings that kept drifting out of sync.
/// The floating bar occupies y≈584–646 on a 375×667pt screen; 96pt of reserved
/// inset rests scrolled-to-end content above the bar and hosts the fade scrim.
enum SipTabBarInset {
    static let height: CGFloat = 96
}

private struct SipTabBarClearanceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            // Bottom fade scrim: drawn inside the reserved zone (under the
            // glass bar, over passing content) so rows scrolling beneath the
            // bar dim out instead of ghosting at full strength behind it.
            LinearGradient(
                colors: [
                    SipColors.background.opacity(0),
                    SipColors.background.opacity(0.85),
                    SipColors.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: SipTabBarInset.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Apply to every tab-root view in `MainTabView` (and nowhere else).
    /// Child ScrollViews inherit the clearance through the safe area — never
    /// add per-screen bottom paddings for the tab bar again.
    func sipTabBarClearance() -> some View {
        modifier(SipTabBarClearanceModifier())
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
                    colorSwatch(SipColors.srmInk, name: "srmInk")
                }

                // MARK: Verdict semantics
                sectionHeader("Verdict")
                HStack(spacing: SipSpacing.m) {
                    colorSwatch(SipColors.verdictTry, name: "verdictTry")
                    colorSwatch(SipColors.verdictSkip, name: "verdictSkip")
                    colorSwatch(SipColors.verdictNeutral, name: "verdictNeutral")
                    colorSwatch(SipColors.verdictSkipText, name: "verdictSkipText")
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
