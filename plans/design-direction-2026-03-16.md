# SipCheck Design Direction
**Date:** March 16, 2026
**Purpose:** Design brief for Manus to produce production-grade visuals

---

## One-Line Brief

A dark, calm, teal-accented interface where your beer photos are the color, the AI gives you one clear answer, and nothing about the design screams "beer bro app."

---

## Strategic Positioning

Every beer app uses amber/orange/yellow. Untappd = yellow. DraughtPick = orange. Pint Please = orange. Brewzy = yellow. BeerRate = dark brown + amber. SipCheck differentiates by NOT being orange.

**SipCheck's aesthetic = "Calm Authority"**
- Premium but not pretentious
- Confident but not aggressive
- Warm but not generic-beer-colored
- Approachable to casual drinkers, not just craft snobs

---

## Color System

| Token | Hex (approx) | Usage |
|-------|-------------|-------|
| `background` | #1A1A1E | Near-black with warmth. Main canvas. |
| `surface` | #2A2A2E | Cards, elevated containers |
| `surfaceLight` | #F5F3F0 | Light mode variant (settings, forms) |
| `primary` | #4ECDC4 | Teal/sage. Buttons, tab active state, links |
| `primaryDark` | #3BA99E | Pressed states, darker teal variant |
| `textPrimary` | #F5F3F0 | Warm white/cream. Main text on dark |
| `textSecondary` | #8E8E93 | Muted gray. Metadata, timestamps |
| `verdictTryIt` | Gradient: #2D7D46 → #4CAF50 | Green. "Try It" verdict card |
| `verdictSkipIt` | Gradient: #C0392B → #E74C3C | Coral/rust. "Skip It" verdict card |
| `verdictYourCall` | Gradient: #D4A017 → #F1C40F | Amber/gold. "Your Call" verdict card |
| `starFilled` | #F1C40F | Gold. Filled rating stars |
| `starEmpty` | #3A3A3E | Dark gray outline. Empty stars |
| `wantToTry` | #4ECDC4 | Teal (matches primary). "Save for later" |
| `destructive` | #E74C3C | Delete, sign out |

**Key principle:** Beer photos provide the warmth and color. The app chrome stays dark and recessive.

---

## Typography

SF Pro (system font). No custom fonts except possibly the wordmark.

| Name | Size | Weight | Usage |
|------|------|--------|-------|
| `display` | 34pt | Heavy | Verdict text ("Try It"), landing title |
| `title` | 24pt | Bold | Screen titles, beer name on detail |
| `headline` | 18pt | Semibold | Section headers, persona names |
| `body` | 16pt | Regular | Explanations, notes, descriptions |
| `subhead` | 14pt | Medium | Style, ABV, dates, metadata |
| `caption` | 12pt | Regular | Timestamps, tertiary info |

Avoid thin/light weights — hard to read in bar lighting.

---

## Logo Direction

**Icon 4 (Bottle Cap + Checkmark)** is the winner.

- Gold metallic cap on deep burgundy = premium + recognizable
- Checkmark encodes "SipCheck" semantically
- Burgundy is unclaimed territory (no competitor uses it)
- Serrated cap edges stay distinctive at 29x29pt smallest size
- Pairs naturally with the dark + teal app aesthetic

Need Manus to:
- Refine Icon 4 to final production quality
- Generate all required iOS icon sizes (29, 40, 60, 76, 83.5, 1024)
- Create a wordmark "SipCheck" that pairs with the cap icon
- Create a horizontal lockup (cap icon + wordmark) for onboarding/marketing

---

## Component Visual Specs

### Verdict Cards (the hero component)

Full-width card, ~60% screen height. Spring animation on appear (scale 0.95 → 1.0 + fade).

Three variants:
- **Try It:** Green gradient background. Large checkmark icon. "Try It" in 34pt Heavy white. Explanation in 16pt Regular white below.
- **Skip It:** Coral/rust gradient. X-mark icon. Same text hierarchy.
- **Your Call:** Amber/gold gradient. Balance-scale icon. Same text hierarchy.

Below: beer name, style, ABV in subhead. Action buttons at bottom ("Save for later" / "Scan another"). Share icon top-right.

**The shareable card** variant: tighter layout for iMessage/Instagram — beer name, verdict stamp, one-line explanation, SipCheck logo at bottom.

### Persona Cards (onboarding)

Horizontal scroll, ~140x180pt per card.
- Custom illustration or stylized icon at top (NOT SF Symbols — needs custom art)
- Persona name in 18pt Semibold
- One-line subtitle in 14pt Regular secondary
- 2-3 beer names as small pill chips below
- Unselected: outlined card, subtle border
- Selected: filled background with primary teal, slight scale-up

### Scan Viewfinder

- Full-screen camera, dark chrome
- Four corner brackets (white, 2pt stroke, no full rectangle)
- "Point at a label or menu" helper text, 15pt Medium white with drop shadow, fades after 3s
- Reading state: brackets pulse inward gently, text changes to "Reading label..."
- Bottom: "Type a beer name instead" link over frosted-glass bar
- "Suggest a beer" secondary button below viewfinder area

### Star Rating

- 5 tappable stars in horizontal row (not a slider)
- Filled: warm gold (#F1C40F)
- Empty: dark gray outline (#3A3A3E)
- Size: 28-32pt for tap targets (bar-friendly)
- No half-stars
- Subtle haptic on tap (light impact)

### Journal Rows

- Photo thumbnail (50x50, rounded 8pt) or placeholder icon
- Beer name in headline weight
- Brand + style + ABV in subhead, secondary color
- Star rating (display-only, small)
- Date in caption

### Scan History Rows

- Beer name
- Verdict dot (green/red/amber, 8pt circle)
- Date
- Optional "Logged" badge chip if linked to journal entry

### Flavor Pills (future)

- Rounded pill tags: "Crisp", "Hoppy", "Malty", "Fruity", "Roasty"
- Color-coded by flavor family
- Horizontal scroll on verdict and detail screens
- Stolen from Brewzy, executed with more polish

---

## Emotional Arc

| Moment | Feeling | Visual Treatment |
|--------|---------|-----------------|
| Onboarding | Recognition — "that's me" | Warm, illustrated persona cards. Inviting copy. |
| Scanning at store | Confidence — "I got this" | Dark, focused camera. No clutter. Fast feedback. |
| Getting verdict | Clarity — "now I know" | Bold color-coded card. One clear answer. |
| Logging at home | Reflection — "let me think" | Calm, spacious form. No urgency. |
| Browsing journal | Pride — "look what I've explored" | Photo-forward grid. Rich stats. Personal collection. |

---

## What to Steal

| From | Pattern | How SipCheck Adapts It |
|------|---------|----------------------|
| Vivino | Match % display, camera brackets, immersive detail pages | Verdict card (Try/Skip/Your Call) instead of percentage. Same bracket camera UI. |
| BeerRate | Photo grid journal, dark mode, "Found it!" confirmation | Photo-first journal view. Dark canvas. Re-scan detection. |
| WhichCraft | Marketing voice, binary rating simplicity, "New to You" search split | Confident copy ("Know before you sip"). 3-tier verdict. Recent scans in journal "+". |
| Brewzy | Flavor note pills, attribute gauges | Flavor pills on verdict/detail screens. |
| Pint Please | Full-bleed product hero on rating screen | Photo hero on journal detail view. |

## What to Avoid

- Orange/amber/yellow as brand color (category default — makes you invisible)
- Social feed as home screen (utility-first, not social-first)
- Gamification badges and levels (Untappd/Pint Please territory)
- Template/generic iOS appearance (Brewzy's failure)
- Information overload on first view (Untappd's sprawl)
- Paywall indicators in core UI
- Beer-bro language ("Beer Nerd", "Bachelor of Ale")
- Serifs for body text (too wine-coded)
- Condensed uppercase (too sports/bro-coded)

---

## Manus Tasks Needed

1. **Refine app icon** — Polish Icon 4 (bottle cap + checkmark) to final quality. Generate all iOS sizes. Create wordmark + lockup.

2. **App Store screenshots** — 5-6 screens showing:
   - Scan viewfinder (camera UI)
   - Verdict card ("Try It" with explanation)
   - Journal photo grid
   - Onboarding persona picker
   - Profile/stats view
   Use iPhone 16 frame, dark theme, the teal + burgundy palette.

3. **Persona illustrations** — 5 custom icons for:
   - Hop Head (hop cone / bold IPA imagery)
   - Keep It Classic (clean lager glass / pilsner)
   - Dark & Rich (stout glass silhouette / dark tones)
   - Wheat & Chill (wheat stalk / light golden)
   - Try Everything (mixed collage / diverse)

4. **Verdict card designs** — High-fidelity mockups of:
   - Try It (green gradient)
   - Skip It (coral/rust gradient)
   - Your Call (amber gradient)
   - Share card variant (compact, iMessage-ready)

5. **Launch screen** — Simple: SipCheck logo (bottle cap) on dark background with subtle gradient.

6. **Empty state illustrations** — 3 needed:
   - No beers yet (journal empty)
   - No scans yet (scan history empty)
   - First scan prompt ("Your first scan is going to be fun")
