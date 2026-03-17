# SipCheck User Flows Design
**Date:** March 16, 2026

---

## Navigation Structure

**Tab bar with 4 tabs:**

| Tab | Label | Icon | Purpose |
|-----|-------|------|---------|
| 1 | Check | `camera.viewfinder` | Camera/text scan -> verdict |
| 2 | Journal | `book.closed` | Beer log, ratings, want-to-try list |
| 3 | Profile | `person.crop.circle` | Taste profile, stats, scan history |
| 4 | Settings | `gearshape` | Account, prefs, export |

**Default tab on launch:** Check (the core action)

First-time flow is pre-tab-bar: Landing -> Login -> Profile Setup -> (Optional Scan) -> Tab bar.

---

## Data Model

Two core entities, intentionally separated:

### Scan (lightweight, automatic)
Created every time the user checks a beer. Never requires user input beyond pointing the camera.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | |
| beerName | String | Extracted from label or typed |
| style | String? | If detected |
| abv | Double? | If detected |
| verdict | Verdict | `.tryIt` / `.skipIt` / `.yourCall` |
| explanation | String | AI reasoning (2-3 sentences) |
| timestamp | Date | |
| wantToTry | Bool | Default false. User can flag from verdict screen or discovery. |
| linkedJournalId | UUID? | Set when user logs this beer in Journal |

### JournalEntry (rich, intentional)
Created when the user deliberately logs a beer they've tried.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | |
| beerName | String | |
| brand | String | |
| style | String | |
| abv | Double? | |
| rating | Int | 1-5 stars |
| notes | String? | |
| photoFileName | String? | |
| dateLogged | Date | When they logged it |
| dateTried | Date? | Optional, defaults to dateLogged |
| linkedScanId | UUID? | If created from a scan |

### Verdict (enum)
```
.tryIt    — strong match to taste profile (green)
.skipIt   — doesn't match preferences (red)
.yourCall — mixed signals or insufficient data (amber)
```

### TasteProfile (computed, not stored)
Derived from JournalEntry ratings + persona selection. Used to generate verdicts and recommendations.

| Field | Source |
|-------|--------|
| persona | User selection (onboarding, editable) |
| selectedBeers | Beer picker selections from onboarding |
| favoriteStyles | Computed from 4-5 star journal entries |
| dislikedStyles | Computed from 1-2 star journal entries |
| avgABV | Computed from all journal entries with ABV |
| totalLogged | Count of journal entries |
| totalLiked | Count of 4-5 star entries |

### Migration note
Current `Drink` model (ratingValue 0/1/2) maps to JournalEntry. Existing data migrates as:
- `dislike` (0) -> 1 star
- `neutral` (1) -> 3 stars
- `like` (2) -> 5 stars

---

## Flow 1: First Time User

**Design goal:** Under 30 seconds to personalized. Only one required input screen.

### Screen 1.1 — Landing
- App logo + tagline ("Know before you sip")
- **Sign in with Apple** button (primary)
- **Sign in with Google** button (secondary)
- "Skip for now" link at bottom (creates guest session)

No email/password auth. Apple and Google OAuth only. No passwords to manage or recover.

Guest sessions store all data locally. Nudge to create account when they have 5+ journal entries ("Create an account to keep your data safe").

### Screen 1.2 — Build Your Taste (required)

Two beats on one screen, progressive disclosure:

**Beat 1 (top):** "What kind of drinker are you?"

Horizontal scroll of persona cards. Each card shows:
- Persona name
- One-line description
- 2-3 example beers as social proof

| Persona | Subtitle | Examples |
|---------|----------|----------|
| Hop Head | Into bold, bitter, citrusy IPAs | Hazy Little Thing, Voodoo Ranger |
| Keep It Classic | Crisp lagers and easy-drinking ales | Modelo, Coors Banquet, Sam Adams |
| Dark & Rich | Stouts, porters, and malty brews | Guinness, Founders Porter |
| Wheat & Chill | Smooth wheats, Belgians, light sours | Blue Moon, Allagash White |
| Try Everything | No style loyalty, just good beer | A mix of all the above |

Tapping a persona highlights it and animates Beat 2 into view below.

**Beat 2 (slides up after persona pick):** "Any of these your go-to?"
- Grid of 8-12 popular beers, contextual to the selected persona
  - Hop Head -> IPAs: Hazy Little Thing, Voodoo Ranger, Two Hearted, Lagunitas IPA, Bell's Hopslam, etc.
  - Keep It Classic -> lagers/ales: Modelo Especial, Coors Banquet, Sam Adams Boston Lager, Yuengling, Dos Equis, etc.
  - Dark & Rich -> stouts/porters: Guinness Draught, Founders Porter, Left Hand Milk Stout, Old Rasputin, etc.
  - Wheat & Chill -> wheats/belgians: Blue Moon, Allagash White, Hoegaarden, Leinenkugel Summer Shandy, etc.
  - Try Everything -> mixed: top 2-3 from each category above
- Multi-select, tap to toggle. No minimum required.
- "Done" button at bottom

Persona + beer selections are stored in TasteProfile and immediately used for the first verdict.

### Screen 1.3 — Ready to Go
- "You're all set! Try scanning a beer."
- Big camera button in center
- "Skip — take me in" text link below
- Tapping camera opens Check flow (Screen 2.1)
- Tapping skip drops user into tab bar at Check tab

---

## Flow 2: Check a Beer (Core Loop)

**Context:** User is at a grocery store or bar. Speed is everything. Glance and go.

### Entry points
- Check tab in tab bar (default tab)
- Screen 1.3 during onboarding

### Screen 2.1 — Scan
- Full-screen camera viewfinder
- "Point at a label or menu" helper text (fades after first successful scan or after 3 seconds)
- Text input toggle at bottom: "Type a beer name instead"
  - Tapping opens a search field with type-ahead over beer names
- Scans automatically on recognition (no shutter button needed)
- Loading state: brief pulse animation, "Reading label..." (sub-1s target on OCR path)

### Screen 2.2 — Verdict (new beer)

Shown when the scanned beer has NO matching JournalEntry.

- **Beer info header:** Name, style, ABV (if detected)
- **Verdict (large, centered, color-coded):**
  - **Try It** (green background) — strong match to taste profile
  - **Skip It** (red background) — doesn't match preferences
  - **Your Call** (amber background) — mixed signals or not enough data
- **Explanation (2-3 sentences):** e.g., "You've rated 4 IPAs highly this year. This West Coast IPA has similar citrus and pine notes to Lagunitas, which you gave 5 stars."
- **Actions (bottom):**
  - "Save for later" — marks scan as `wantToTry = true`
  - "Scan another" — back to camera
  - Share button (top right) — generates verdict card image -> iOS share sheet
- **Auto-behavior:** Scan record is always saved regardless of which action they tap.

### Screen 2.2b — Verdict variant: Already Tried (re-scan)

Shown when the scanned beer MATCHES an existing JournalEntry.

- **Beer info header:** Name, style, ABV
- **"You've had this" badge** (instead of verdict)
- **Their rating:** 1-5 stars displayed, tappable to edit inline
- **Their notes** (if any)
- **Date logged**
- **Actions:**
  - "Update rating" — inline star edit, saves immediately
  - "Scan another" — back to camera

No new scan record created for re-scans of logged beers.

### Screen 2.2c — Verdict variant: Offline

Shown when OCR succeeds but LLM call fails (no network / timeout).

- **Beer info header:** Name, style (best effort from OCR only)
- **"No signal" indicator** — "We couldn't get a recommendation right now"
- **Actions:**
  - "Save for later" — saves scan with `verdict = nil`, queued for retry
  - "Scan another" — back to camera

**Retry behavior:** On next app open with connectivity, queued scans (verdict = nil) get processed in background. Results appear as badge on Check tab: "3 verdicts ready" -> tapping shows a scrollable list of verdict cards.

---

## Flow 3: Log a Beer

**Context:** User tried a beer — maybe hours or days after scanning it. This is a reflective, unhurried moment.

### Entry points
- Journal tab -> "+" button (floating action or toolbar)
- From scan history in Profile tab -> "I tried this" action
- From "want to try" list in Journal tab -> "Log it" action

### Screen 3.1 — Find the Beer
- Search bar at top (type-ahead)
- **"Recent scans" section** — scans without a linked JournalEntry, most recent first
  - Each row: beer name, verdict icon (green/red/amber), date scanned
  - Tap to pre-fill the log form with scan data
  - This is the natural scan-to-journal bridge
- **"Want to try" section** (if any flagged scans exist) — scans with `wantToTry = true`
- If no scans exist: just search bar + "Or add manually" text
- "Add manually" always available at bottom -> opens blank Screen 3.2

### Screen 3.2 — Rate & Log
- Beer name + style pre-filled (from scan or search, editable)
- Brand field (optional, editable)
- **Rating: 1-5 stars** (tap to set, required)
- "Add notes" expandable section (collapsed by default)
  - Text field, 3-6 lines
- "Add photo" button (collapsed by default)
  - Camera or photo library picker
- **"Save" button** (disabled until rating is set)
- Done. Returns to Journal list. If created from a scan, links the two records.

---

## Flow 4: Journal / Beer Management

### Journal tab — main screen

**Default view:** List of logged beers (JournalEntries), most recent first.

Each row:
- Photo thumbnail (or placeholder icon)
- Beer name
- Brand + style (secondary text)
- Star rating (1-5, displayed as filled/empty stars)
- Date logged

**Top controls:**
- Search bar (searches name, brand, notes)
- Filter: segmented control or chips
  - All | 4-5 stars | 3 stars | 1-2 stars
  - Style dropdown if many entries
- Sort menu (top-right): Date (default), Name, Rating, Style

**"Want to try" section** — if any scans are flagged `wantToTry = true` and not yet logged, show as a collapsible section at the top of the Journal list with a distinct visual treatment (e.g., lighter background, "Want to try" header). Each row shows beer name + verdict + date scanned, with a "Log it" action.

**Swipe actions:**
- Swipe left to delete

**Tap -> Beer detail view**

### Beer detail view
- Photo (if saved, large at top)
- Beer name, brand, style, ABV
- Star rating (1-5, tappable to edit)
- Notes (tappable to edit)
- Date logged
- "Originally scanned on [date]" link if linked to a scan (shows what the verdict was)
- Share button (top right) -> generates rating card image -> iOS share sheet
- "Delete" at bottom (confirmation alert)

---

## Flow 5: Profile / Taste

### Profile tab — main screen

**Top section: Identity**
- Persona badge (e.g., "Hop Head") with icon
- Tap to change persona (opens persona picker, same as onboarding Beat 1)
- Changing persona doesn't delete data, just adjusts future verdicts

**Middle section: Stats**
- Summary line: "42 beers logged · 28 loved"
- Top styles breakdown:
  - "IPAs: 12 tried, 10 loved (avg 4.2 stars)"
  - "Stouts: 6 tried, 4 loved (avg 3.8 stars)"
  - Top 5 styles, sorted by count
- Rating distribution bar (visual)
- Avg ABV
- Timeline: beers per month (last 6 months)

**Bottom section: Scan History**
- List of all past scans, most recent first
- Each row: beer name, verdict icon (green/red/amber), date
- "Logged" badge if linked to a journal entry
- For unlogged scans: "I tried this" action -> opens Flow 3 Screen 3.2 pre-filled
- Scan count: "127 beers checked"

---

## Flow 6: Settings

### Settings tab — main screen

**Account section:**
- Current login method (Apple / Google / Guest)
- If guest: "Create account" CTA -> Apple/Google sign-in flow
- If signed in: email display, option to link additional provider

**Preferences section:**
- Change persona (links to persona picker)
- Default tab on launch (Check / Journal)

**Data section:**
- Export journal as JSON
- Export journal as CSV
- "X journal entries, Y scans" count

**About section:**
- App version
- Privacy policy
- Terms of service

**Danger zone:**
- Sign out
- Delete account (confirmation required, explains data loss)

---

## Flow 7: Discovery ("What should I try?")

Single button on the Check tab, below the camera viewfinder area: **"Suggest a beer"**

### Screen 7.1 — Suggestion
- App generates 1 recommendation based on taste profile
- Shows: beer name, style, ABV (if known)
- Why it fits: "You love citrusy IPAs — this West Coast IPA from Firestone Walker has similar notes to Two Hearted, which you gave 5 stars."
- **Actions:**
  - "Show me another" — generates new suggestion (replaces current)
  - "Want to try" — saves as a Scan with `wantToTry = true`, appears in Journal's want-to-try section
  - "Done" — dismisses back to Check tab
- Share button (top right) -> generates recommendation card -> iOS share sheet

One screen. The app picks for you. No browsing, no catalog.

---

## Share (cross-cutting)

Not a standalone flow — a button that appears on three screens:

| Screen | What's shared |
|--------|--------------|
| Verdict (Screen 2.2) | Card: beer name, style, verdict (Try It / Skip It / Your Call), SipCheck branding |
| Journal detail (Flow 4) | Card: beer name, style, star rating, user's notes excerpt, SipCheck branding |
| Discovery suggestion (Screen 7.1) | Card: beer name, style, "Recommended by SipCheck", branding |

All generate a shareable card image. Standard iOS share sheet (iMessage, Instagram Stories, AirDrop, etc.)

---

## Edge Cases & Behavior Rules

### Scan matching logic
When a beer is scanned, check for matches in this order:
1. **Exact name match** against JournalEntries -> show "Already tried" variant (Screen 2.2b)
2. **Fuzzy name match** (Levenshtein distance or `localizedStandardContains`) against JournalEntries -> show "Already tried" with "Is this the same beer?" confirmation
3. **No match** -> show standard verdict (Screen 2.2)

### Verdict generation
The LLM prompt includes:
- Scanned beer info (name, style, ABV)
- User's persona
- TasteProfile summary (favorite/disliked styles, top-rated beers, avg ABV)
- Instruction to return structured response: verdict (try/skip/your_call) + explanation (2-3 sentences)

### Guest-to-account conversion
- Guest data (scans + journal entries) is stored locally
- When guest creates an account, all local data migrates to their account
- No data loss on conversion

### Text-based check (no camera)
- User types beer name on Check tab -> search field with type-ahead
- System looks up beer info (name, style, ABV) from knowledge base or LLM
- Same verdict flow as camera scan, just without OCR step

---

## Screen Inventory

Total unique screens:

| # | Screen | Type |
|---|--------|------|
| 1.1 | Landing | Full screen (pre-tab-bar) |
| 1.2 | Build Your Taste | Full screen (pre-tab-bar) |
| 1.3 | Ready to Go | Full screen (pre-tab-bar) |
| 2.1 | Scan (camera/text) | Check tab content |
| 2.2 | Verdict (new beer) | Push/modal from scan |
| 2.2b | Verdict (re-scan) | Variant of 2.2 |
| 2.2c | Verdict (offline) | Variant of 2.2 |
| 3.1 | Find Beer to Log | Modal from Journal "+" |
| 3.2 | Rate & Log | Push from 3.1 |
| 4.0 | Journal list | Journal tab content |
| 4.1 | Beer detail | Push from Journal list |
| 5.0 | Profile | Profile tab content |
| 6.0 | Settings | Settings tab content |
| 7.1 | Discovery suggestion | Modal from Check tab |
| — | Persona picker | Reusable (onboarding + settings) |
| — | Share card preview | System share sheet |

**16 screens total.** 3 are onboarding-only (seen once). 3 are verdict variants (same layout, different content). Core ongoing experience is ~10 screens.

---

## Key Design Principles

1. **Check is fast.** Verdict screen in under 2 seconds. No decisions required. Glance and go.
2. **Log is separate.** Never interrupt a scan flow with "rate this now." Logging happens later, at the user's pace.
3. **Recent scans bridge the gap.** The Journal "+" screen surfaces unlogged scans. The path from check to log is one tap, but never forced.
4. **Three tiers for verdicts, five stars for ratings.** The app speaks simply (try/skip/your call). The user can be more nuanced (1-5 stars).
5. **Guest-first.** Account creation is optional. Don't gate the core experience behind auth.
6. **Persona creates instant identity.** User should see themselves in the onboarding within 5 seconds.
7. **Want-to-try is a first-class concept.** Scans flagged "save for later" and discovery suggestions both feed into a visible list in the Journal, closing the loop from store to home.
8. **Offline is graceful.** OCR works without signal. Verdicts queue and resolve when connectivity returns.
