# Design Spec

SipCheck design modernization — single source of truth for parallel build agents.
Derived from: iOS 26 Liquid Glass API cheat-sheet (verified 2026-07-02), modern-adoption pattern research, and file-by-file redlines audited against the working tree. Repo: `/home/user/sipcheck`. Current `DesignSystem.swift` inventory verified against source at `SipCheck/Views/DesignSystem.swift` (148 lines, matches redline audit).

**Global rules for every work order:**
- WO-1 lands first; all other WOs depend on it and are mutually disjoint (no file appears in two WOs).
- iOS 17.0 deployment target, built with Xcode 26 / iOS 26 SDK. All Liquid Glass APIs behind `if #available(iOS 26.0, *)` via the WO-1 helpers only — never call `glassEffect` raw at a call site.
- NO Swift macros: no `#Preview`, no `@Observable`, no `@Model`. `PreviewProvider` structs only. `@EnvironmentObject` for `DrinkStore`.
- Do not change any logic, persistence, navigation routing, or scan pipeline behavior unless the WO explicitly orders it. Visual layer only.
- Never rename an `accessibilityIdentifier` or a test-load-bearing label (full list in §4).
- `SipCheck/Views/Tabs/CheckTabView.swift` and `SipCheck/Services/ScanningPipeline.swift` are **reserved by the verdict-first track** (CLAUDE.md Active Tracks) — WO-3 is a hand-off packet, not a direct-edit order.

---

## 1. Design language decisions (final)

### 1.1 Brand color resolution: TEAL WINS, coral retires
- The app has two competing accents: `SipColors.primary` teal `#4ECDC4` (tab bar, MainTabView tint) and the asset-catalog `AccentColor` coral `#EE8864` (onboarding, RatingPicker, CameraCaptureButton, legacy views). **Resolution: teal is the single brand accent.**
- Structural fix: repoint `SipCheck/Resources/Assets.xcassets/AccentColor.colorset/Contents.json` from coral `#EE8864` (components 0.933/0.533/0.392) to teal `#4ECDC4` (components `"red": "0.306", "green": "0.804", "blue": "0.769"`). This one asset edit converts every `.accentColor`/`Color.accentColor` site to teal with zero code changes.
- Teal `#4ECDC4` is already a bright, high-luminosity dark-mode accent (per the "brighten/desaturate accents in dark mode" rule) — keep as-is. `#3BA99E` survives only as the pressed state inside ButtonStyles.
- **Traffic colors are the answer; teal is the app.** Verdict green/red/amber never appear on app chrome (buttons, chips, tab tint); teal never carries verdict meaning. (Exception fix ordered in WO-5: FollowUpView's green CTA becomes teal.)

### 1.2 Verdict color semantics + contrast-fixed values (exact hex)

| Token | Hex | Text on it | Meaning |
|---|---|---|---|
| `verdictTry` | `#4CAF50` | `textPrimary` `#F5F3F0` | Thumbs-up. Symbol `hand.thumbsup.fill` |
| `verdictSkip` | `#E85D4A` (warm ember, retinted from `#E74C3C`) | `textPrimary` `#F5F3F0` | Thumbs-down. Symbol `hand.thumbsdown.fill` |
| `verdictNeutral` | `#F1C40F` (amber) | **`onVerdictNeutral` `#1A1A1E`** | Your call. Symbol `hand.raised.fill` |
| `onVerdictNeutral` | `#1A1A1E` | — | **The white-on-gold fix, enforced at token level.** Any text/glyph on an amber fill uses this, never white |
| `destructive` | `#FF453A` | `textPrimary` | Delete/sign-out only. Now distinct from `verdictSkip` — "delete" and "skip this beer" no longer share a hex |

- Verdict badges are **triple-redundant**: color + SF Symbol thumbs glyph + word. Never color-only.
- `starFilled` stays `#F1C40F`; documented as "gold = rating, amber = neutral verdict — shared hue by design."
- Never pure white (`#F5F3F0` cream avoids halation) and never pure black (`Color.black` is banned; use `background`/`onVerdictNeutral` token).

### 1.3 Surfaces (dark-only for now; light mode is a later project)
- `background` `#1A1A1E` (canvas) → `surface` `#2A2A2E` (cards) → `surfaceElevated` `#34343A` NEW (stacked/nested cards, deep desaturated-teal-tinted grey). Content sits on these opaque surfaces — **never on glass**.
- Deleted tokens: `surfaceLight` (dead), `wantToTry` (dead duplicate of primary). `primary`→`accent`, `primaryDark`→`accentPressed` (ButtonStyle-internal only).

### 1.4 Typography — Dynamic Type mapping

| Token | Definition | Replaces | Notes |
|---|---|---|---|
| `verdictHero` | `Font.system(size: 48, weight: .heavy, design: .rounded)` | `display` 34pt for the verdict word | Hero views scale it via `@ScaledMetric(relativeTo: .largeTitle) var verdictSize: CGFloat = 48` |
| `numberHero` | `Font.system(size: 44, weight: .heavy)` | stat numbers | Call sites add `.fontWidth(.compressed)` + `.monospacedDigit()` |
| `title` | `Font.title2.weight(.bold)` | fixed 24 | Dynamic Type |
| `headline` | `Font.headline` | fixed 18 semibold | Dynamic Type |
| `body` | `Font.body` | fixed 16 | Dynamic Type |
| `subhead` | `Font.subheadline.weight(.medium)` | fixed 14 | Dynamic Type |
| `caption` | `Font.caption` | fixed 12 | Dynamic Type; nothing below `caption2` ever (kills 9pt/10pt badges) |

One family (SF Pro; `.rounded` only for `verdictHero`), hierarchy by weight + opacity, not size soup. Anything that ticks (scores, counts, ABV) gets `.monospacedDigit()`. Every hard-coded `.system(size:)` in views is replaced by a token or `@ScaledMetric`. Test verdict card + journal at AX5.

### 1.5 Spacing / radius tokens
- `SipSpacing`: `xs=4, s=8, m=12, l=16, xl=24, xxl=32`. Existing usage is ~90% on these stops; codify, don't reflow layouts.
- `SipRadius`: `badge=6`, `control=12` (buttons, fields, small tiles), `card=16`, `hero=24` (verdict card), chips = `Capsule`. Collapse existing 14→12 or 16, 20→Capsule, 4→6, 10→12. All `RoundedRectangle` use `style: .continuous`.
- **Concentric rule** (the #1 dated-vs-modern tell): nested radius = outer radius − padding. E.g. verdict card 24 with 8pt inset chip → chip radius 16. Do the arithmetic manually (iOS 17-safe); do not use `ConcentricRectangle` (26-only, unnecessary).
- Tap targets: **44×44pt minimum everywhere**, enforced via shared styles (`SipChipStyle` min height 44, `SipQuietButtonStyle` minHeight 44) and explicit `.frame(width: 44, height: 44)` on icon buttons.

### 1.6 Motion rules
- Springs only, never `easeInOut`. Defaults: `.snappy(duration: 0.25)` for control state changes; `.smooth` for layout changes; **`.bouncy` reserved for exactly one moment — the verdict reveal** (scale+fade entrance of the verdict hero).
- Haptics: `.sensoryFeedback(.success, trigger:)` on thumbs-up verdict (the haptic half already ships in CheckTabView:105–108 — don't duplicate).
- Motion is feedback, not decoration: no pulsing, no idle animation. Respect Reduce Motion (springs degrade gracefully; glass morphs are auto-disabled by the system — do not gate manually).

### 1.7 Glass philosophy for SipCheck
**Glass = floating chrome only. Content is always opaque.** The verdict card body, journal rows, stat cards, and all text surfaces never get glass. Per Apple guidance: "limit to the most important functional elements."

| Surface | iOS 26 | iOS 17–25 fallback |
|---|---|---|
| Tab bar (`MainTabView` — native `TabView`) | **Free** — automatic Liquid Glass floating bar. Do NOT add backgrounds/appearance overrides | Stock opaque bar (unchanged binary behavior). Keep the existing 110pt bottom-clearance paddings in VerdictCardView:171 / JournalTabView:76 / ProfileTabView:58 **unchanged this pass** (E2E bridge assumes bar at y≈584–646; `.tabBarMinimizeBehavior` is explicitly deferred) |
| Sheets, `Form`s (AddBeerView, SettingsTabView), alerts, menus | **Free** — automatic. Keep them native; remove nothing, add nothing | Stock rendering |
| Nav bars / scroll edges (Journal, Profile) | **Free** — never set `.toolbarBackground(.visible)` or opaque bar colors (breaks the effect). Optional tuning: `scrollEdgeEffectStyle(.soft, for: .top)` via `compatScrollEdgeSoft()` | No-op |
| Camera overlay controls (capture button, future scan-tab chrome floating over live feed) | `.glassEffect(.regular.interactive(), in: .circle)` (or `.capsule`) via WO-1 helpers, **all siblings inside one `GlassEffectContainer`** (one container = one backdrop pass — critical over a live camera feed) | `.ultraThinMaterial` in same shape + 0.5pt `white.opacity(0.15)` hairline stroke |
| Verdict card, journal cards, chips, stat boxes, onboarding pages | **Never glass.** Opaque `surface`/`surfaceElevated` | Same |

Hard rules: apply `.padding()` *before* glass (glass fills the frame incl. padding); never nest/overlap independent glass (glass can't sample glass — siblings share a container); never put custom glass inside an already-glass sheet/toolbar; don't rely on translucency for meaning (26.1 "Tinted" mode + Reduce Transparency render it near-opaque). Banned symbols: `glassEffect(...isEnabled:)` (removed pre-GM), `Glass.thin/.ultraThin` (never existed), `glassBackgroundEffect` (visionOS).

---

## 2. DesignSystem.swift target API

Complete target public surface of `SipCheck/Views/DesignSystem.swift` after WO-1. Everything below is iOS 17-compatible, macro-free, and uses only cheat-sheet-**verified** iOS 26 APIs inside availability gates.

```swift
import SwiftUI

// MARK: - Color Tokens (dark values; asset-catalog Any/Dark split deferred to light-mode project)
enum SipColors {
    // Surfaces
    static let background       = Color(hex: "#1A1A1E")
    static let surface          = Color(hex: "#2A2A2E")
    static let surfaceElevated  = Color(hex: "#34343A")   // NEW — stacked/nested cards
    // Text
    static let textPrimary      = Color(hex: "#F5F3F0")   // cream, never pure white
    static let textSecondary    = Color(hex: "#8E8E93")
    // Brand ramp (teal)
    static let accent           = Color(hex: "#4ECDC4")   // rename of `primary`
    static let accentPressed    = Color(hex: "#3BA99E")   // rename of `primaryDark`; ButtonStyle-internal
    static let accentSubtle     = Color(hex: "#4ECDC4").opacity(0.18)  // selected-chip/tag fills
    // Verdict semantics (traffic ≠ brand)
    static let verdictTry       = Color(hex: "#4CAF50")
    static let verdictSkip      = Color(hex: "#E85D4A")   // warm ember, distinct from destructive
    static let verdictNeutral   = Color(hex: "#F1C40F")
    static let onVerdictNeutral = Color(hex: "#1A1A1E")   // dark text on amber — white-on-gold fix
    // Utility
    static let destructive      = Color(hex: "#FF453A")   // delete ≠ skip
    static let starFilled       = Color(hex: "#F1C40F")   // gold = rating; amber = neutral verdict (shared hue by design)
    static let starEmpty        = Color(hex: "#3A3A3E")
    static let warning          = Color(hex: "#F1C40F")   // error-banner icon tint (replaces hardcoded .orange)
    // DELETED: surfaceLight, wantToTry, primary, primaryDark (temporary
    // deprecated aliases primary/primaryDark → accent/accentPressed allowed during WO rollout; remove before merge-train ends)
}

// MARK: - Typography (Dynamic Type; see §1.4)
enum SipTypography {
    static let verdictHero = Font.system(size: 48, weight: .heavy, design: .rounded)
    static let numberHero  = Font.system(size: 44, weight: .heavy)   // + .fontWidth(.compressed) + .monospacedDigit() at call site
    static let title       = Font.title2.weight(.bold)
    static let headline    = Font.headline
    static let body        = Font.body
    static let subhead     = Font.subheadline.weight(.medium)
    static let caption     = Font.caption
}
// Hero scaling pattern (call-site, since @ScaledMetric is a property wrapper):
//   @ScaledMetric(relativeTo: .largeTitle) private var verdictSize: CGFloat = 48
//   Text(word).font(.system(size: verdictSize, weight: .heavy, design: .rounded))

// MARK: - Spacing / Radius
enum SipSpacing { static let xs: CGFloat = 4;  static let s: CGFloat = 8;  static let m: CGFloat = 12
                  static let l:  CGFloat = 16; static let xl: CGFloat = 24; static let xxl: CGFloat = 32 }
enum SipRadius  { static let badge: CGFloat = 6; static let control: CGFloat = 12
                  static let card: CGFloat = 16;  static let hero: CGFloat = 24 }  // chips = Capsule

// MARK: - Verdict presentation (single source; replaces 3 duplicated switches)
struct VerdictStyle {
    let word: String        // EXACTLY "TRY IT" / "SKIP IT" / "YOUR CALL" — test-load-bearing, do not reword
    let color: Color
    let symbol: String      // "hand.thumbsup.fill" / "hand.thumbsdown.fill" / "hand.raised.fill"
    let textColor: Color    // textPrimary for try/skip; onVerdictNeutral for yourCall
    static func style(for verdict: Verdict) -> VerdictStyle
}

// MARK: - Shared button/chip/card styles
struct SipPrimaryButtonStyle: ButtonStyle {}
// accent fill (accentPressed when pressed), foreground SipColors.background, SipTypography.headline,
// .padding(.vertical, 14), minHeight 50, RoundedRectangle(SipRadius.control, .continuous).
// Owns disabled state: surface fill + textSecondary when !isEnabled (kills inline disabled-gray hacks).

struct SipSecondaryButtonStyle: ButtonStyle {}
// clear fill, 2pt accent strokeBorder, accent text, same metrics as primary.
// init(tint: Color = SipColors.accent) — destructive variant passes SipColors.destructive.

struct SipQuietButtonStyle: ButtonStyle {}
// text-only, SipTypography.subhead, accent text, .frame(minHeight: 44) — quiet ≠ untappable.

struct SipChipStyle: ButtonStyle {
    let isSelected: Bool
}
// Capsule; selected: accent fill + SipColors.background text; unselected: surface fill + textSecondary text.
// .frame(minHeight: 44). Replaces ChipButton (OnboardingView:437–461) and filterChip (JournalTabView:134–148).

extension View {
    func sipCard(radius: CGFloat = SipRadius.card, fill: Color = SipColors.surface) -> some View
    // padding(SipSpacing.l) + RoundedRectangle(radius, .continuous).fill(fill) background. Opaque — never glass.
}

// MARK: - SRM style gradient (deterministic, asset-free beer-color backdrops)
enum StyleGradient {
    static func gradient(for style: String?) -> LinearGradient
    // Deterministic switch on lowercased style keywords → two-stop LinearGradient(topLeading→bottomTrailing):
    //   pilsner/lager/helles  #F8E08E → #D9A441   (pale gold)
    //   wheat/hefeweizen/wit  #F5D06F → #E0A83C
    //   pale ale/IPA          #E8A33D → #B96A24   (amber)
    //   amber/red/märzen      #C86A2E → #8E3B1B
    //   brown/porter          #6B3A22 → #3A1E12
    //   stout                 #2A1B12 → #14100C   (near-black w/ warm edge)
    //   sour/fruit            #E06A8A → #A03A5C
    //   nil/unknown           surface → surfaceElevated (type-led; verdict is the only color)
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
    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) { ... }
    var body: some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: spacing, content: content) }
        else { content() }
    }
}

// Keep: Color(hex:) extension — but its use is BANNED outside DesignSystem.swift after WO-1
// (CI lint: `grep -rn 'Color(hex:' SipCheck/Views --include=*.swift | grep -v DesignSystem.swift` must be empty).
// Keep: DesignSystem_Previews as PreviewProvider struct, updated to the new tokens.
```

Glass API whitelist for all WOs (verified, safe against iOS 26 SDK behind `#available`): `glassEffect(_:in:)` · `Glass.regular/.clear/.identity` · `.tint(_:)`/`.interactive()` · `GlassEffectContainer(spacing:content:)` · `glassEffectID(_:in:)` · `glassEffectUnion(id:namespace:)` · `glassEffectTransition(_:)` · `.buttonStyle(.glass)`/`.buttonStyle(.glassProminent)` · `scrollEdgeEffectStyle(_:for:)` · `tabBarMinimizeBehavior(_:)` · `tabViewBottomAccessory(content:)` · `Tab(role: .search)` · `ToolbarSpacer` · `backgroundExtensionEffect()`.

**Verify-at-compile appendix** (do NOT put in the main design system; if a WO wants one, confirm in Xcode autocomplete first): parameterized `.buttonStyle(.glass(_:))` taking a `Glass` config; `GlassEffectTransition.materialize`/`.identity`; `@Environment(\.tabViewBottomAccessoryPlacement)` case names (`.inline` vs `.collapsed`); `.interactive()` default-argument form (use explicit `.interactive(true)` if the no-arg form fails).

---

## 3. Work orders (file-partitioned, no overlaps)

### WO-1 — Foundation: DesignSystem.swift + Assets (RUNS FIRST)
**Files:** `SipCheck/Views/DesignSystem.swift`, `SipCheck/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`.
1. Rewrite `DesignSystem.swift` to the exact §2 API. Ship temporary deprecated aliases `static let primary = accent` / `static let primaryDark = accentPressed` so parallel WOs compile before their token migration; the last WO to merge removes them.
2. Repoint `AccentColor` asset: coral `#EE8864` → teal `#4ECDC4` (`"red": "0.306", "green": "0.804", "blue": "0.769"`, alpha 1, sRGB). This alone retires coral app-wide.
3. Update `DesignSystem_Previews` (PreviewProvider struct — keep) to swatch the new tokens, including a `VerdictStyle` row and the three ButtonStyles.
4. `VerdictStyle.style(for:)` must produce the exact strings `"TRY IT"` / `"SKIP IT"` / `"YOUR CALL"` — copied verbatim from `VerdictCardView.swift:181–185`; these are asserted by `SipCheckUITests.testTypedNameProducesVerdict`.
**Do NOT touch:** any view file; any `Verdict` model logic. **Glass:** helpers defined here per §2; no rendering changes.

### WO-2 — Verdict surface: `Components/VerdictCardView.swift`, `Components/VerdictBadge.swift`, `Components/WantToTryCard.swift`
The #1 priority screen. All opaque — **no glass anywhere in this WO**.
1. **VerdictCardView — verdict-first reorder:**
   - Delete the 320pt gray box (lines 22–45: `Rectangle().fill(SipColors.surface).frame(height: 320)` + 64pt mug + overlay gradient) and the `.system(size: 64)` glyph with it.
   - New order top→bottom: **(a) verdict hero** — `VerdictStyle` symbol + word, `@ScaledMetric(relativeTo: .largeTitle) verdictSize = 48` heavy rounded, verdict color, entrance `withAnimation(.bouncy)` scale+fade (`.animation(.bouncy, value: verdict)`); keep `accessibilityIdentifier("verdictText")` on the word and do not reword the strings. **(b) identity block** on a `StyleGradient.gradient(for: scan.style)` backdrop (radius `SipRadius.hero` 24, `.continuous`): beer name (`SipTypography.title`), then `style · ABV · provenance` line (`subhead`, `textSecondary`). When `style == nil`, backdrop is the surface→surfaceElevated fallback (verdict is the only color). Verdict word always owns the top; gradient is backdrop only. Reduce the existing full-card verdict gradient (196–203) to the hero area only — no two competing gradients.
   - **New parameters (API change):** add `source` (provenance) and `confidence: Double?` + optional alternates to the view. Provenance copy: `"from label"` / `"catalog match"` / `"our best guess"`. When `confidence < 0.9`: caption `"Best match: {name} ({Int(confidence*100)}%)"` + quiet button **"Not this one?"** that pages fuzzy candidates on the card (no pre-verdict gate). Until WO-3's plumbing lands, default the new params (`source = nil` → omit provenance line) so this WO compiles standalone.
   - **Because-rows:** `DisclosureGroup` below the explanation (97–105) with 2–3 pro/con rows, leading 8pt dots in `verdictTry`/`verdictSkip`. Blocked on a `TasteScorer` refactor (flat `shortReason` → structured signals) owned by the scan track — build the UI against an optional `[(text: String, isPro: Bool)]` param defaulting to `[]` (renders nothing when empty).
   - **Actions row (126–167):** add primary **"Drinking it — log it"** → opens `AddBeerView` prefilled via existing `AddBeerPrefill(name:style:abv:scanId:)`. Order: Log it (`SipPrimaryButtonStyle`) / Save for Later (`SipSecondaryButtonStyle`, keep id `saveForLater`) / Scan Another (`SipQuietButtonStyle`, keep id `scanAnother`). Delete inline fill/stroke builders.
   - **Refining pill (55–66):** move from between verdict and banner to a shimmer on the metadata row it will patch, bottom-aligned with `beerMetadata`. Keep `accessibilityIdentifier("refiningHint")`.
   - Fonts: `.system(size: 16)` line 112 → `SipTypography.subhead`. Keep bottom clearance `110` (line 171) exactly — do not migrate to contentMargins this pass.
2. **VerdictBadge:** replace duplicated switches (6–29) with `VerdictStyle`; **line 32 `foregroundColor(.white)` → `style.textColor`** (this is the white-on-gold fix); add the thumbs symbol before the word; line 36 → `SipTypography.caption`; add `accessibilityLabel("Verdict: \(word capitalized)")` (e.g. "Verdict: Try it").
3. **WantToTryCard:** lines 55–56 (9pt white-on-gold capsule) → reuse `VerdictBadge` or min `.caption2` with `VerdictStyle.textColor`. Lines 10–27 gray box → `StyleGradient` mini-tile (100×80, radius `SipRadius.control`) with beer initials. Verdict switch (66–71) → `VerdictStyle`. Add `accessibilityIdentifier("wantToTryCard_\(scan.id)")` and `accessibilityLabel("\(scan.beerName), \(verdict word), want to try")`.
**Identifiers to preserve:** `verdictText`, `refiningHint`, `alreadyTriedBanner`, `saveForLater`, `scanAnother`, `verdictCard`. **Do NOT touch:** verdict computation, `Scan`/`Verdict` models, CheckTabView.

### WO-3 — CheckTabView visual layer ⚠️ HAND-OFF PACKET (file reserved by scan track — deliver these redlines to `claude/review-project-status-5ihff`, do not edit directly)
**File:** `SipCheck/Views/Tabs/CheckTabView.swift`.
1. **Copy (exact strings):** lines 62–67 `scanningPhrases` → `["Reading the label…", "Checking it against your taste…", "Almost there…"]` (3, not 4). Line 167 → `"Point it at any beer — verdict in seconds, no signal needed."`. Keep line 163 `"What Are You Drinking?"` and line 405 failure copy as-is.
2. **Buttons → shared styles:** Scan Label (174–190) → `SipPrimaryButtonStyle` (label "Scan Label" unchanged, keep `scanNowButton`); Enter beer name (192–202) → `SipQuietButtonStyle` minHeight 44 (label unchanged, keep `enterTextButton`); Check This Beer (308–323) → `SipPrimaryButtonStyle` with style-owned disabled state, delete inline gray at 318 (label unchanged, keep `checkBeerButton`).
3. Error-banner ✕ (274–279): `.frame(width: 44, height: 44)` + `accessibilityLabel("Dismiss")`. Line 269 `.orange` → `SipColors.warning`. Fonts: line 159 `.system(size: 64)` and 226 `.system(size: 24)` → `@ScaledMetric`/tokens.
4. **Plumbing for WO-2:** pass `ScanOutcome.source`, `score`, `nameIsGuess`/confidence (609–613) and fuzzy alternates through to `VerdictCardView` at 80–93; wire the `AddBeerPrefill` log-now path; expose `TasteScorer` structured signals for because-rows.
5. **Glass (only if the scan track adds live-camera chrome):** overlay controls (torch/flip/type-instead) use `compatGlassCircle()` inside ONE `CompatGlassContainer`; overflow as `Menu` from a glass button (but never a `Menu` inside the container on 26 — known morph breaker; hang it adjacent). No glass behind the scanning UI itself (opaque `SipColors.background` ZStack at 70–72 stays).
**Identifiers to preserve:** `checkTab` + `.accessibilityElement(children: .contain)` at :101 (the F12 fix — do not remove), `scanNowButton`, `enterTextButton`, `beerTextInput`, `checkBeerButton`. **Do NOT touch:** `ScanOutcome` logic, `ScanningPipeline.swift`, haptics at 105–108.

### WO-4 — First-run: `OnboardingView.swift`, `AgeGateView.swift`
1. **OnboardingView tokens:** `.accentColor` at 39, 162, 318, 452, 456 → already teal via WO-1 asset repoint; hard-swap to `SipColors.accent` for explicitness. `.white` CTA text at 159, 315, 447 → `SipColors.textPrimary` (fill-button text becomes `SipColors.background` when moving to `SipPrimaryButtonStyle`). `Color(UIColor.systemBackground)` gradient at 179 → `SipColors.background`.
2. **CTA hierarchy (intended behavior change — see §4):** primary CTAs (156–164, 312–320) → `SipPrimaryButtonStyle`; Skip (166–170, 322–326) → `SipQuietButtonStyle`. TasteQuizPage: primary label exactly `"See My Picks"`, **disabled until `hasRequiredSelections`**; Skip label exactly `"Skip — you can tune this later"` and Skip must only set `hasCompletedOnboarding = true` — it must NOT call `saveAndContinue`/`persistAnswers` (skip leaves saved prefs untouched; answered-state write-through at 337–339 already persists real answers).
3. **Page dots:** hide system dots on pages 3–4 (own CTAs) or custom indicator above the CTA block; minimum fix: bottom padding = safe area + 56 (replaces fragile `.bottom, 44` at 175, 329).
4. Story pages (34–53): add a `"Continue"` primary button (at least page 1) — swipe-only advance is undiscoverable.
5. `ChipButton` (437–461) → shared `SipChipStyle` (min height 44; fixes <44pt targets and `.white` selected text at 447).
6. **AgeGateView:** line 17 `.system(size: 72)` and 41 `.system(size: 28)` → `@ScaledMetric`. "I tapped by mistake — go back" (50–60) → `SipQuietButtonStyle` (minHeight 44), keep id `ageGateGoBack`. Buttons 66–96 → `SipPrimaryButtonStyle` / `SipSecondaryButtonStyle` ("I'm Under 21" stays ghost secondary). Do not touch `isLockedOut` logic.
**Glass:** none — onboarding/age-gate content is opaque. (Quiz-chip glass moment is deferred; not in this pass.) **Identifiers:** `ageGateGoBack`. No ids in OnboardingView — E2E drives it by label, so any changed button strings above must be flagged to the E2E track for `ci_bridge` script updates.

### WO-5 — Journal cluster: `Tabs/JournalTabView.swift`, `Components/JournalEntryRow.swift`, `JournalEntryDetailView.swift`, `FollowUpView.swift`
1. **JournalTabView:** `filterChip` (134–148) → `SipChipStyle` (fixes ~33pt height and hardcoded `Color.black` at 141 → style handles it); keep ids `filterAll`/`filterLoved`/`filterOK`/`filterNotForMe`. Fonts 107/213 → tokens. Empty state split: no data → `"Nothing logged yet — scan a beer to start"`, filtered-out → `"No beers match"` — use `ContentUnavailableView` (iOS 17-safe) for both (`systemImage: "book"` / `.search` style). Keep `journalSearch`, `journalTab` + `.contain` (79–82), and `.padding(.bottom, 110)` at :76 exactly. Add `.compatScrollEdgeSoft()` on the scroll container; ensure no `.toolbarBackground(.visible)` is introduced.
2. **JournalEntryRow:** fonts 20/35 → `headline`/`caption`; 10pt "Not For Me" badge (42) → `.caption2` minimum. Circle-mug placeholder (15–21) → `StyleGradient` mini-tile. Star row (33–38): `.accessibilityElement(children: .ignore)` + `accessibilityLabel("Rated \(entry.rating) of 5")`. Line 26 may restyle name/style as two lines, but the beer name must remain the accessibility-label prefix (tests do `BEGINSWITH "Guinness Draught"`).
3. **JournalEntryDetailView:** star buttons (78–87) → `.frame(width: 44, height: 44)` each + `accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")`; keep ids `detailStar_1…5`. Fonts 48/83 → `@ScaledMetric`. Delete button (107–120) → `SipSecondaryButtonStyle(tint: SipColors.destructive)`; keep `detailDelete`, `detailNotes`. Mug circle (43–50) → `StyleGradient` tile when style known.
4. **FollowUpView:** "Not going to" (89–96) → `SipQuietButtonStyle` (minHeight 44). Line 15 `.system(size: 48)` → `@ScaledMetric`. **Line 67: "Yes, I tried it" fill `verdictTryIt` → `SipPrimaryButtonStyle` (teal)** — traffic colors are answers, not app chrome. Keep copy; keep ids `followUpTriedIt`, `followUpNotYet`, `followUpNotGoing`, `followUpView`.
**Glass:** none — list content and rows are opaque by rule; nav/scroll-edge treatment is free/system. **Do NOT touch:** filtering logic, JournalStore, follow-up scheduling.

### WO-6 — Profile + Settings: `Tabs/ProfileTabView.swift`, `Tabs/SettingsTabView.swift`
1. **ProfileTabView:** gear (83–88) → `.frame(width: 44, height: 44)` + `accessibilityLabel("Settings")` + NEW `accessibilityIdentifier("settingsButton")`. Fonts 85/103/254 → tokens. `statBox` (137–154) numbers → `numberHero` + `.fontWidth(.compressed)` + `.monospacedDigit()`. Persona badge `leaf.fill` → `mug.fill` (cosmetic). `scanRow` mug (253–256) → verdict-colored 8pt dot or `StyleGradient` mini-tile (rows stay non-tappable — revisitable scans is future work, note only). **StyleBarView normalization consumer:** change scale basis at :176 from `maxPercentage` to absolute 100% (fixes "33% renders ~90% wide"). Keep `.padding(.bottom, 110)` at :58. Add `.compatScrollEdgeSoft()`. Keep ids `profileTab` (+`.contain`), `profileTitle`, `beersLoggedCount`, `lovedCount`, `topStyles`, `recentScans`; labels "My Profile"/"Beers Logged" are test-asserted — do not reword.
2. **SettingsTabView:** keep native `Form` (free Liquid Glass on 26 — add no backgrounds). Line 78 `.red` → `SipColors.destructive`. Line 23 `NavigationView` → `NavigationStack`. Copy: line 43 → `"We'll check in a day or two after you save one"`; drop the duplicate footer at 51. Add "Edit taste preferences" row deep-linking to the quiz page only (no age-gate reset). Hide AI Provider picker (27–33) behind a debug flag (`#if DEBUG`). **Add "Export my data" row** hosting the CSV/JSON export + `ShareSheet` relocated from StatsView (coordinate with WO-8: WO-6 lands the new export UI by copying `exportAsCSV`/`exportAsJSON` logic + moving `ShareSheet` into `Components/`; WO-8 deletes the originals after). Keep id `settingsTab`.
**Glass:** none custom; Form/nav are system surfaces. **Do NOT touch:** TasteProfile computation, notification scheduling.

### WO-7 — Shell + shared inputs: `MainTabView.swift`, `AddBeerView.swift`, `Components/CameraView.swift`, `Components/RatingPicker.swift`, `Components/StylePicker.swift`, `Components/StyleBarView.swift`
1. **MainTabView** (stock `TabView`, three `.tabItem`s, `.tint` at :26 is the only styling): change `.tint(SipColors.primary)` → `.tint(SipColors.accent)`. **Do NOT adopt `.tabBarMinimizeBehavior` or the `Tab` builder this pass** — the E2E bridge assumes the bar at y≈584–646 and three views carry 110pt clearance hacks; adoption is a coordinated follow-up (leave a `// TODO(glass-followup)` noting `.tabBarMinimizeBehavior(.onScrollDown)` + `.contentMargins(.bottom, for: .scrollContent)` as the migration). Add no `UITabBarAppearance`, no bar backgrounds (would break automatic glass). Tab labels `"Check"`/`"Journal"`/`"Profile"` and symbols stay exactly as-is (test-critical).
2. **AddBeerView:** keep native `Form`. Line 110 `.red` → `SipColors.destructive`; line 109 copy → `"Couldn't read the label — fill in what you know."`. Keep ids `beerName`, `breweryName`, `abvField`, `saveBeer`; keep "Save" label.
3. **CameraView / CameraCaptureButton (43–92):** line 55 `.background(Color.accentColor)` + line 56 `.white` → `SipPrimaryButtonStyle`. **The one custom-glass adoption of this pass:** if the button floats over the live feed, use `.compatGlassCircle()` wrapped in `CompatGlassContainer` instead of the primary fill (26 = interactive glass circle; 17–25 = ultraThinMaterial circle + hairline). Fix `.notDetermined` branch (81–87): set `showingPermissionAlert = true` on denial instead of silent no-op (bug-class fix, explicitly ordered).
4. **RatingPicker:** line 23/27 accent already teal via asset; line 27 `Color.gray.opacity(0.3)` → `SipColors.starEmpty`; tokenize `.primary`/`.secondary` at 17. Add `accessibilityLabel(ratingOption.displayName)` on each button. Keep ids `rating_like`/`rating_neutral`/`rating_dislike`. Targets already ≥64pt.
5. **StylePicker:** no changes (native Picker; must survive WO-8 — consumed by AddBeerView:77 and legacy BeerDetailView:40).
6. **StyleBarView:** accept absolute percentages (WO-6 changes the caller); add `.accessibilityElement(children: .ignore)` + `accessibilityLabel("\(style), \(Int(percentage)) percent")`. Keep 30pt min bar width; `foregroundColor(SipColors.background)` on teal is correct.
**Do NOT touch:** tab selection logic, UIImagePickerController plumbing (DataScanner spike replaces it later), Drink model.

### WO-8 — Dead-code deletion: `HomeView.swift`, `CheckBeerView.swift`, `BeerListView.swift`, `BeerDetailView.swift`, `StatsView.swift` + `SipCheck.xcodeproj/project.pbxproj`
**Preconditions (hard blockers, in order):** (a) strike SPEED_PLAN.md items #12 (CheckBeerView.swift:278–318) and #15 (BeerListView.swift:176) with a "resolved by deletion — unreachable code" note and update the CLAUDE.md Active Tracks note per E2E_FINDINGS F3-withdrawn; (b) WO-6's export relocation merged (CSV/JSON export + `ShareSheet` live in Settings/Components — this is the app's only data-export path).
1. Delete the five files (unreachability grep-confirmed: zero external references; `RootView` routes only AgeGate → Onboarding → MainTabView).
2. **pbxproj surgery:** remove PBXBuildFile lines 13, 15, 16, 22, 33 (A1000004/06/07/13/24); PBXFileReference lines 95, 97, 98, 104, 115 (A2000004/06/07/13/24); group children lines 228, 231, 232, 234, 235; Sources phase lines 466, 468, 469, 475, 483. Verify with a clean `xcodebuild` for simulator afterward.
3. **Move, don't delete:** `ShareSheet` (StatsView) → `SipCheck/Views/Components/ShareSheet.swift` + add to pbxproj (unless WO-6 already moved it — coordinate; exactly one WO performs the move).
4. **Must survive (defined elsewhere, only consumed by legacy):** `RatingPicker`, `StylePicker`, `CameraCaptureButton`, `DrinkStore.findMatch`. **Verified-orphan types deleted with their files:** `BeerRowView`, `SortOption`, `StatCard`, `RatingBar`, `CheckResult`.
5. **Accepted losses (record in BUG_AUDIT):** Drink-record editing UI (BeerDetailView was the only `Drink` editor; JournalEntryDetailView edits `JournalEntry` only — note as accepted loss or file a follow-up to write through), stats visualizations (partially duplicated by ProfileTabView). Orphaned ids `addBeer`, `checkBeer`, `searchField`, `searchButton`, `beer_{uuid}` and the `"recentSearches"` AppStorage key die with the files (current `SipCheckUITests.swift` uses none — verified). Mark BUG_AUDIT [HIGH] CheckBeerView.swift:281 and the BeerMatcher-via-CheckBeerView [LOW] as resolved-by-deletion.
**Glass:** N/A. **Do NOT touch:** any live view, `AddBeerView` (WO-7's file), any Service.

---

## 4. Preservation contract

### 4.1 accessibilityIdentifiers that MUST survive (★ = directly asserted/tapped in `SipCheckUITests.swift`; all others used by the e2e-drive bridge)

| File | Identifiers |
|---|---|
| CheckTabView | `checkTab` (container — MUST keep `.accessibilityElement(children: .contain)` at :101), `scanNowButton`, `enterTextButton`, ★`beerTextInput`, `checkBeerButton` |
| VerdictCardView | `verdictText`, `refiningHint`, `alreadyTriedBanner`, `saveForLater`, `scanAnother`, `verdictCard` |
| JournalTabView | ★`journalTab` (+ `.contain`), ★`journalSearch`, `filterAll`, `filterLoved`, `filterOK`, `filterNotForMe` |
| ProfileTabView | `profileTab` (+ `.contain`), `profileTitle`, `beersLoggedCount`, `lovedCount`, `topStyles`, `recentScans`; NEW: `settingsButton` |
| SettingsTabView | `settingsTab` |
| JournalEntryDetailView | ★`detailStar_1…5`, `detailNotes`, ★`detailDelete` |
| AddBeerView | `beerName`, `breweryName`, `abvField`, `saveBeer` |
| AgeGateView | `ageGateGoBack` |
| FollowUpView | `followUpTriedIt`, `followUpNotYet`, `followUpNotGoing`, `followUpView` |
| RatingPicker | `rating_like`, `rating_neutral`, `rating_dislike` |
| WantToTryCard | NEW: `wantToTryCard_{scan.id}` |
| Legacy (deletable with WO-8 only) | `searchField`, `searchButton`, `addBeer`, `checkBeer`, `beer_{uuid}` |

### 4.2 Label/string dependencies (renames break tests even though they aren't identifiers)
- Tab labels: `"Check"`, `"Journal"`, `"Profile"`.
- Buttons: `"Scan Label"`, `"Enter beer name"`, `"Check This Beer"`, `"Save"`.
- Static texts: `"My Beers"`, `"My Profile"`, `"Beers Logged"`.
- Verdict strings **exactly** `"TRY IT"` / `"SKIP IT"` / `"YOUR CALL"` (asserted by label match; centralized in `VerdictStyle` — that helper is now the single place these strings live).
- Seed names `"Guinness Draught"`, `"Bud Light"` must remain row-label **prefixes** (tests use `BEGINSWITH`).
- OnboardingView has no ids — E2E drives it by label; WO-4's new strings (`"See My Picks"`, `"Skip — you can tune this later"`, `"Continue"`) must be reported to the E2E track for `ci_bridge` updates in the same PR description.

### 4.3 Behaviors that must not change
- All scan/resolve/score logic (`TasteScorer`, `BeerResolver`, `MenuParser`, `ScanningPipeline`, `ScanOutcome` computation), persistence (`Documents/drinks.json`, stores), CloudKit sync, notification scheduling, age-gate lockout logic, haptics at CheckTabView:105–108.
- The 110pt bottom-clearance paddings (`VerdictCardView:171`, `JournalTabView:76`, `ProfileTabView:58`) stay byte-identical this pass; `.tabBarMinimizeBehavior` adoption is explicitly deferred (E2E bridge geometry contract: bar at y≈584–646 on a 375×667pt screen).
- Sole **intended** behavior changes (ordered above, list is exhaustive): WO-4 quiz-Skip no longer persists picks + primary CTA disabled until selections; WO-6 StyleBar scales to absolute 100%; WO-7 camera `.notDetermined` denial surfaces the permission alert; WO-2 adds the log-now action/params (additive).

### 4.4 Compile constraints
- Deployment target iOS 17.0; SDK iOS 26 (Xcode 26 CI). Every iOS 26 symbol behind `if #available(iOS 26.0, *)` — exclusively via the WO-1 helpers (`compatGlass`, `compatGlassCircle`, `compatScrollEdgeSoft`, `CompatGlassContainer`); banned raw symbols: `glassEffect(...isEnabled:)`, `Glass.thin/.ultraThin`, `glassBackgroundEffect`, and everything in the §2 verify-at-compile appendix unless autocomplete-confirmed.
- No Swift macros: no `#Preview` (use `PreviewProvider` structs), no `@Observable` (use `ObservableObject` + `@EnvironmentObject`), no `@Model`/SwiftData.
- `Color(hex:)` usable only inside `DesignSystem.swift` (lint: `grep -rn 'Color(hex:' SipCheck/Views --include='*.swift' | grep -v DesignSystem.swift` → empty).
- New files (e.g. `Components/ShareSheet.swift`) must be registered in `project.pbxproj` (PBXBuildFile + PBXFileReference + group + Sources phase) — no automatic file discovery.
- Each WO must pass: `xcodebuild -project SipCheck.xcodeproj -scheme SipCheck -destination 'platform=iOS Simulator,name=iPhone 16e' -configuration Debug build` and the existing `SipCheckUITests` suite; verify dark scheme (app forces `preferredColorScheme(.dark)`), and spot-check AX5 Dynamic Type on the verdict card and journal.
- Merge order: WO-1 → {WO-2, WO-4, WO-5, WO-7} in parallel → WO-6 → WO-8 (blocked on WO-6 export relocation + SPEED_PLAN strike-through). WO-3 routes through the reserved scan track at any point after WO-1. The last merging WO removes the temporary `primary`/`primaryDark` aliases from `DesignSystem.swift`.