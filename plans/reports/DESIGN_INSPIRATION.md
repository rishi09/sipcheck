# SipCheck Design Borrow List
*Synthesis of ADA winners, Vivino, category scanners, visual-language, and cold-start research — against the audit's known weaknesses.*

---

## 1. North Star

The best-in-class SipCheck moment feels like Merlin Sound ID pointed at a beer shelf: you raise the phone, recognition highlights bloom over the label as it reads, and a huge, colored, *felt* (haptic + sound) TRY IT lands in under two seconds — offline, free, no shutter, no spinner. The verdict speaks like Gentler Streak's compass, not a judge: "TRY IT — juicy hazy IPA, like your last 4 thumbs-ups," grounded in *your* history, honest about what it doesn't know. Crouton and SwingVision prove this exact loop — camera in, on-device judgment out, built solo — is what Apple gives Design Awards to; the bar is not more capability, it's zero decisions between camera-raise and verdict.

---

## 2. The Borrow List
*Ranked by impact on the in-aisle moment.*

**1. Verdict is the entire above-the-fold screen.**
*From: Yuka result hierarchy; Noriko Gondo's Vivino teardown; watchOS glance typography.*
Invert the current layout: the verdict word (TRY IT / SKIP IT / YOUR CALL) becomes the hero — ~48pt, `.heavy`, `.fontDesign(.rounded)`, semantic color, thumbs SF Symbol — at the *top* of the result view. Beer name, style, ABV, provenance ("from label" / "catalog match") one glance below; history, notes, similar beers behind a sheet. Rule: readable in under 2 seconds at arm's length, pre-reading, via color + icon alone.
**Fixes:** verdict buried below the 320pt gray placeholder box.

**2. Never block on the network — verdict now, refine silently.**
*From: Flighty (Apple explicitly awarded "assumes no signal" as design); Vivino's offline scan queue.*
The on-device path (OCR → catalog → TasteScorer/Foundation Models) renders the verdict immediately, always. Online enrichment becomes a background task that silently upgrades the card and journal entry when connectivity returns — a small "refining…" shimmer on one detail row at most, never a full-screen spinner, and always cancelable by just… leaving. The offline verdict must be indistinguishable in polish from the online one.
**Fixes:** the 30–60s network-blocked spinner with no cancel.

**3. Honest confidence ladder instead of fake confidence.**
*From: Seek's 7-dot ID meter; Pl@ntNet's per-match percentages; Merlin's "best guess" framing.*
Give the resolver's rank ladder a visible face: three dots over the viewfinder filling as it climbs *Reading… → Style: IPA → Two Hearted, 7.0%*. When only the style resolves, say so and give the style-level verdict ("Hazy IPAs are usually a TRY for you"). When nothing resolves, the verdict is **YOUR CALL** with "we don't know this one — type the name?" — never a confident SKIP IT. Below a fuzzy-match confidence threshold, show "Best match: Two Hearted (72%)" with the next candidates one tap away.
**Fixes:** unknown beers getting fake-confident SKIP IT; doubles as camera framing guidance (weakness: none exists) because the dots visibly fill as the user finds the right angle — Seek proved this teaches framing with zero instructional text.

**4. Live recognition highlights on the viewfinder.**
*From: Merlin Sound ID's real-time highlight; SwingVision (ADA Innovation — "AI's thinking visible on the feed"); Google Lens dots.*
As `DataScannerViewController` recognizes beer names, draw teal-glow highlights on their bounding boxes live (VisionKit exposes them nearly free). In menu mode, freeze the frame once OCR stabilizes and overlay verdict chips on the recognized lines — the user can lower the phone and keep reading. No shutter anywhere.
**Fixes:** no framing guidance; makes the scan feel magical instead of a form.

**5. Confirmation tap = journal save = latency mask.**
*From: CapWords (2025 ADA winner — network round-trip hidden behind the confirm step); Merlin's "This is my bird!"*
Frame the resolved beer as "Looks like: **Two Hearted Ale** — Bell's" with **That's it / Not this one**. "That's it" simultaneously confirms the match *and* writes the journal entry — one gesture, no separate check-in. Run the online top-up *during* that confirmation moment behind a small pour micro-animation, so async refinement is never perceived as loading. "Not this one" pages to the next fuzzy candidate, then the typed-name path.
**Fixes:** trust erosion from mismatches (they become a conversation, not a failure); heavyweight logging.

**6. Personal history outranks the model.**
*From: Vivino scan history ("remembers every scan"); Untappd's gap.*
When the resolver matches a beer already in `drinks.json`, lead with it: "**You had this in March. You gave it 👍.**" Distinct badge state (small clock/check accent) so "previously tried" is glanceable. It's a DrinkStore lookup in the result path — the single highest-trust line the app can render.
**Fixes:** nothing broken — but it's the cheapest, most trusted verdict SipCheck can give.

**7. Every verdict carries a one-line "because" in compass voice.**
*From: Gentler Streak (2024 ADA — "a compass, not a report card"); Slate's Vivino critique (unexplained scores read as arbitrary).*
Verdict copy references the user's own data, friend-steering tone: "SKIP IT — too roasty for you; you rated 3 stouts under 2 stars." Below it, 2–3 collapsed Yuka-style pro/con rows from TasteScorer's signals (`DisclosureGroup` with green/red leading dots): "You rated 4 hazy IPAs 4+" / "8.5% — higher than you usually go." Personal evidence is SipCheck's version of Vivino's billion-scan credibility.
**Fixes:** fake-confidence distrust; gives the AI verdict a personality layer (the 2026 ADA Foundation Models trend — Harvee's "raw data → guidance").

**8. SKIP IT is never a dead end.**
*From: Yuka's alternative recommendations (the cited reason a red score feels helpful, not judgmental).*
Every SKIP IT immediately shows one "Grab this instead" card: in menu mode it's the MenuParser winner; in label mode, the nearest high-scoring style match from `catalog.json` via BeerMatcher. Fully offline.
**Fixes:** turns the app's harshest moment into its most useful one.

**9. Felt verdicts: signature haptic + sound pair.**
*From: (Not Boring) Camera (2026 ADA finalist — haptic detents, "Nintendo-level" sound); CapWords' multi-sensory results.*
A CoreHaptics "click" when DataScanner locks a beer name; a sharp two-note haptic+sound for TRY IT, a soft one for SKIP IT — the verdict is *felt* with the phone at arm's length before it's read. Plus a `spring(duration:bounce:)` scale+fade entrance on the badge — Denim (2025 ADA finalist) proves stock-SwiftUI polish on 3 key moments is award-caliber for a tiny team.
**Fixes:** verdict legibility under aisle conditions; makes scan feel like a device, not a form.

**10. Liquid Glass controls floating over the viewfinder; verdict capsule morphs into the card.**
*From: Apple iOS 26 design language; Tide Guide (2026 ADA winner — early Liquid Glass adoption by a tiny shop is itself award-noticed).*
The camera feed is the content; scan controls, torch, "type it instead," and the verdict chip are `.glassEffect()` elements with verdict-colored `.tint()` and `.interactive()`. The compact TRY IT capsule over the viewfinder morphs/expands into the full reasoning card on tap — one element transforming, not a modal replacing the camera. Material/blur fallback on iOS 17.
**Fixes:** the white-system-sheet-over-dark-screen flash (no more modal); positions SipCheck exactly where Vivino's Liquid Glass refresh says the category is heading.

**11. Menu mode: one hero winner, runner-up on tap, explicit mode toggle.**
*From: Vivino's list scanner (mental model) — deliberately inverted (their every-line overlay is overload under waiter pressure).*
Surface the menu/label mode switch as a visible toggle in the camera. Menu result = one "Order this" hero card + small runner-up affordance + collapsed list of all recognized beers with tiny verdict dots. Later: a Live Activity / Dynamic Island chip ("Order: Two Hearted") so the winner survives the phone locking while the waiter approaches — the exact wait-context Mela and Flighty were honored for.
**Fixes:** honors the locked "one clear winner" spec with a discoverable home.

**12. Cold start: 3-screen story → 3-question tile quiz → straight to scanner.**
*From: Spotify's pick-3+ artist grid; Netflix's rule of three; Pinterest's contextualized ask; Duolingo's placement test & gradual engagement.*
Compress onboarding: 2–3 story screens showing a mocked verdict badge (teaches the result UI before first use), then a `LazyVGrid` of big style tiles — "Pick 3+ you love — your very first scan will be tuned to you" — with an "I know my beers" fork that rates 5 famous beers from the catalog instead. **Persist each answer as it's tapped** (write-through to the taste library, not on quiz completion), and end on the scan screen so quiz → real verdict happens in session one. Skippers get a popularity-seeded default library, labeled honestly ("based on what most people like — rate a few to make this yours").
**Fixes:** quiz data silently lost on swipe; cold-start promise ("scan #1 is personalized") made explicit.

**13. Notification primer after the first verdict — never the native dialog first.**
*From: Braze/Appcues permission-priming research (contextual timing ≈ 3× opt-in); Yuka's just-in-time camera ask.*
Camera permission fires on first Scan tap with one benefit line ("Point at any beer — verdict in seconds"); denied state degrades to the typed-name path, fully functional. Notifications: a teal in-app primer card *after* the first successful verdict ("Want a ping when this beer's match improves?") with Allow / Not Now — only Allow calls `UNUserNotificationCenter`.
**Fixes:** notification dialog interrupting the first verdict; protects the one-shot native prompts.

**14. Scans become a collection; the taste profile becomes an artifact.**
*From: CapWords' scrapbook; Vivino's Taste Profile (tried/like/dislike per style, user-editable); Co-Star's "your chart" framing; Duolingo's instant-feedback chips.*
Save every captured photo and render each confirmed scan as a collectible card in the journal. Taste-profile page: per-style chips showing tried/liked/disliked counts, tappable to correct the model (same chip component as the quiz — disagreeing with a SKIP IT has a fix-it destination), plus a simple radar/flavor-wheel "Your Taste Chart" and a styles-explored grid that fills passively. A personalization meter ("Rate 3 more beers to unlock confidence scores") mirrors Vivino's threshold-to-payoff loop.
**Fixes:** captured photos never saved or shown; makes the opinionated verdict transparent and correctable.

---

## 3. Deliberate Differences — what NOT to copy

1. **No crowd ratings, ever.** Untappd's global average is the category's documented anti-pattern (style-skewed, inflated, answers "what does the crowd think" not "will *I* like it"), and Vivino's own users trust the personal match *more* than the star average while critics shred the crowd number (vintage-blind, novice-weighted, price-biased). SipCheck's hero is one taste-based verdict citing the user's own history — which sidesteps every listed bias.
2. **No shutter → preview → upload flow.** Vivino's shutter+confirm+cloud round-trip is a *costly necessity* of wine (Vuforia cloud image-matching against millions of labels), not a feature. Beer labels print the style as text; SipCheck's live point-and-read is structurally faster than the incumbent — preserve it and benchmark/advertise time-to-verdict.
3. **Never paywall the scan.** Moving list-scanning behind Premium is Vivino's single biggest 1-star driver. SipCheck's $0 on-device path is already locked architecture — state "free, on-device, no account" explicitly in-app and on the store page. It's a moat, not a footnote.
4. **Don't rate every menu line.** Vivino's overlay-everything list scanner forces comparison shopping under waiter pressure. One winner + tappable runner-up is the better fit for the moment and is already the locked spec — hold it.
5. **No streaks, badges, or challenges near the verdict.** Seek's challenge mechanics measurably distorted user behavior toward point-farming, and Untappd's social-first multi-step check-in is fatal in the aisle. Borrow only the passive end: styles-explored grid, counts, private-by-default one-tap logging.

---

## 4. Visual Language Reset

**Palette strategy — teal wins, coral retires.**
One brand. Expand teal `#4ECDC4` into a small ramp the way Starbucks builds a "family of greens": pale teal (selected chips, tags), core teal (interactive accents), deep desaturated teal (elevated dark surfaces, gradients). Coral is removed from onboarding entirely — onboarding uses the same ramp so the app is one product from screen one. The critical rule this buys: **teal = "the app," traffic colors = "the answer."** Semantic verdict colors never compete with brand color.

**Light + dark.** Dark-first is *correct* for this domain (Untappd's own retrofit post-mortem: bars are dim, camera chrome is dark) — but implemented as semantic tokens, not hardcoded hex. DoorDash-style, solo-dev-sized: ~15 semantic colors in the asset catalog with Any/Dark variants (`surfacePrimary`, `surfaceElevated`, `textPrimary`, `accentTeal`, `verdictTry`, `verdictSkip`, `verdictNeutral`…), ban raw `Color(hex:)` in views. No pure white text (use ~`#F5F5F0` off-white — pure white halates on dark), no pure black surfaces (elevated dark grey). This resolves the white-sheet-flash bug structurally: light mode becomes a designed variant, not a system betrayal.

**Verdict semantics — triple-redundant, graded, readable in sunlight.**
Word + color + SF Symbol thumbs, always together (Yuka/Nutri-Score: color earns the glance, the word carries the meaning; survives color-blindness and glare). Saturated, high-contrast bands — the eye-tracking research says muted badges literally get fewer fixations:
- **TRY IT** — strong green, off-white text
- **YOUR CALL** — amber with **dark text** (kills the unreadable white-on-gold badge) and visually the *middle of a scale*, softer than the poles
- **SKIP IT** — warm ember red, off-white text, always leading with the imperative word + reason (red alone doesn't change behavior)

**Typography scale.**
Verdict word: ~48pt, `.heavy`, `.fontDesign(.rounded)` — one huge word per glance, watchOS-complication style; rounded terminals keep traffic colors friendly, not clinical. Numbers (ABV, match %): Apple Sports treatment — `.font(.system(size: 44, weight: .heavy)).fontWidth(.compressed)`, `monospacedDigit` for anything updating live during scan. Everything else on Dynamic Type text styles (`.title3`, `.subheadline`, `.caption`) — no fixed point sizes outside the two hero elements — and test verdict + journal at the largest accessibility size. This is the Dynamic Type fix, done once at the token level.

**Photo / placeholder treatment — kill the gray box.**
Three states, no gray rectangle in any of them:
1. **User photo exists** (now saved at scan-confirm): photo hero, with a dominant color stored at save time as the CloudKit-sync placeholder (Wolt BlurHash pattern).
2. **No photo, known style:** SRM-derived two-stop `LinearGradient` header — pilsner pale gold, IPA amber, stout near-black with a warm edge — with style glyph or beer initials. Deterministic, offline, zero assets, category-meaningful.
3. **No photo, nothing known:** Co-Star type-led card — beer name large and heavy, brewery/style/ABV small and secondary, verdict as the only color, left-aligned, strict hierarchy. Two SwiftUI card layouts total.

---

## 5. Quick Wins vs. Big Bets

**< 1 day each**
- Verdict-first result layout (#1) + typography scale — reorder + restyle one view
- YOUR CALL amber/dark-text badge + triple-redundant badge component (word/color/symbol)
- Personal-history line from `drinks.json` lookup (#6)
- "Because" one-liner + compass-voice copy pass on verdict strings (#7)
- SKIP IT alternative card from BeerMatcher (#8)
- Verdict haptics + spring entrance (#9) — CoreHaptics + 3 lines of animation
- Quiz write-through persistence fix (#12, the data-loss part)
- Move notification ask to post-first-verdict primer (#13)
- SRM style-gradient placeholder + type-led card (#4's photo states 2–3)

**< 1 week each**
- Semantic color tokens + light-mode variants; delete hardcoded hex; retire coral (§4)
- Never-block scan flow: instant on-device verdict + background enrichment queue, spinner deleted (#2)
- Confidence ladder + threshold + style-only/YOUR CALL honest states (#3)
- "That's it / Not this one" confirm-as-save with latency-masking animation (#5)
- Save captured photos + journal collectible cards (#14, part 1)
- Onboarding rebuild: 3 story screens + tile quiz + skip-path defaults (#12)
- Dynamic Type audit at accessibility sizes
- Taste-profile chips (tried/liked/disliked, editable) + personalization meter (#14, part 2)

**Later (big bets)**
- Live viewfinder recognition highlights + menu freeze-frame overlay chips (#4) — device-only spike, pairs with the unproven DataScanner work
- Liquid Glass camera chrome + capsule-morphs-into-card verdict (#10) — iOS 26, ship promptly when targeting it (Tide Guide shows early adoption is itself noticed)
- Live Activity / Dynamic Island menu winner (#11)
- Taste Chart radar + styles-explored grid polish; verdict-tinted result atmosphere (Tide Guide's ambient theming)
- Post-drink "how was it?" scheduled prompt closing the taste-library loop (Mela pattern)

---

# Feasibility Critique & Corrected Priorities

# Critique: SipCheck Design Borrow List

*Verified against the repo. Load-bearing claims checked: the 320pt gray placeholder box exists (`VerdictCardView.swift:14-26`, verdict rendered below it), the scan pipeline does block on the network before any verdict (`ScanningPipeline.swift:42-43` awaits Gemini/OpenAI even though `CheckTabView.buildScan` then computes the on-device verdict anyway), the quiz persists only on `saveAndContinue` (`OnboardingView.swift:302-305`), the native notification prompt does fire at first verdict (`finalizeScan` → `scheduleFollowUp` → `requestAuthorization`, `NotificationService.swift:59`), the YOUR CALL badge is white-on-gold (`VerdictBadge.swift:32`), `catalog.json` is bundled in `SipCheck/Resources/`, and `BeerResolver`/`TasteScorer`/`BeerMatcher`/`MenuParser` all exist. The report's diagnosis is largely accurate.*

---

## 1. Infeasible or mis-costed under constraints

- **#3 confidence dots "< 1 week" is mis-bucketed.** The dots-fill-as-you-frame interaction requires live recognition, i.e. `DataScannerViewController` — which appears **nowhere in production code** (only in `plans/`; the current camera is a shutter-based `CameraView` → `capturedImage`). CLAUDE.md itself calls the DataScanner spike "the remaining unproven part." **Split it:** the honest-states half (YOUR CALL when unresolved, "Best match: Two Hearted (72%)", style-only verdicts — all derivable from `BeerResolver.ResolvedBeer.source` + `BeerMatcher` score today) is a genuine quick win; the live dots move to Later alongside #4.
- **#4 live viewfinder highlights** — correctly gated as Later, but say it louder: it's not "VisionKit exposes them nearly free," it's *contingent on an unbuilt, unproven device spike*. Don't let the North Star paragraph (written entirely in live-scan language) set expectations the shipping shutter flow can't meet.
- **#9 "signature sound pair"** — custom "Nintendo-level" audio is a design asset a solo dev can't produce; bad sound is worse than none. **Substitute:** iOS 17's `.sensoryFeedback(.success/.warning)` + optional system sounds. Keep the spring entrance. Also note `scheduleFollowUp` in `finalizeScan` implies sound may fire while a notification is pending — trivial, but test.
- **#10 Liquid Glass** — `.glassEffect()`/morph APIs are iOS 26-only against an iOS 17 target; the report knows this, but the "Material/blur fallback" undersells the cost: the capsule-morphs-into-card transition has no cheap iOS 17 equivalent beyond `matchedGeometryEffect`, which fights `sheet`-based navigation (the whole current result flow is sheets). Fine as Later; do not let it leak earlier.
- **§4 light mode is underscoped.** "Semantic tokens + light variants < 1 week" ignores that every view is designed dark-only; light mode is a full visual audit. **Substitute:** semantic tokens **dark-only**, and kill the white-sheet flash directly by applying `.preferredColorScheme(.dark)` at the app/sheet level — one line, ships today. Light mode becomes a someday-item, not a week-one deliverable.
- **#14 photo saving "< 1 week"** is optimistic *if* it includes CloudKit asset sync (`Scan` has no image field today; photos-through-CloudKit means asset management, size caps, LWW conflicts on binary blobs). **Substitute:** local-only photo files + filename in `Scan`, dominant-color placeholder synced; CloudKit photo sync deferred.
- **#5's "pour micro-animation"** — another asset ask. SF Symbol + spring is enough.

## 2. Conflicts with locked product constraints

- **#5 as written violates "zero decisions between camera-raise and verdict."** A "Looks like: Two Hearted — That's it / Not this one" gate *before* the verdict inserts exactly the decision step the North Star bans, and re-introduces a perceived wait ("run the online top-up during confirmation"). **Fix:** show the verdict immediately; "Not this one?" is a small affordance *on* the verdict card that pages fuzzy candidates and retroactively corrects the journal entry. Confirmation-as-save stays; confirmation-as-gate goes.
- **#8's "Grab this instead" in label mode fights physical reality.** In a grocery aisle, recommending a specific catalog beer the shelf may not stock is a dead-end dressed as help. Menu mode is fine (MenuParser winner is by definition orderable). **Substitute for label mode:** style-level steering ("you usually like porters better than stouts") or a match from the user's own want-to-try list. Also note "nearest high-scoring style match" requires scoring catalog candidates through `TasteScorer` — feasible, but it's a new code path, not a lookup.
- **#11's Live Activity is scope creep on the locked spec.** The one-winner card honors the spec; the Dynamic Island chip is an ActivityKit widget extension for a moment that lasts ~90 seconds. Keep Later, or cut.

## 3. Patterns that clash with each other

- **#1 (verdict is the hero) vs. §4 photo state 1 (photo is the hero).** Pick a rule and state it: *verdict word always owns the top; photo/gradient is backdrop or secondary*, or the two-second-glance requirement dies the day photos exist.
- **#2 (verdict instantly, no gate) vs. #5 (confirm gate masking latency)** — same conflict as above; the corrected #5 resolves it.
- **#3 (admit uncertainty, offer candidates) vs. #9 (celebratory haptic on lock-in).** Firing the confident TRY-IT haptic on a 60% fuzzy match is fake confidence in tactile form. Rule: full haptic only above the confidence threshold; below it, the soft/neutral cue.
- **#2's silent background upgrade vs. #5/#14's user-confirmed journal entries.** Async enrichment must never overwrite user-confirmed fields (and with CloudKit LWW, a late enrichment write can clobber an edit from the other device). Enrichment fills blanks only.

## 4. Solid — confirmed against the code

- **#1** — the 320pt gray box burying the verdict is real; the fix is a reorder of one view. The existing `SipColors` verdict tokens and `Verdict` enum make the triple-redundant badge a small component change.
- **#2** — the highest-value item in the report. The on-device path (`BeerResolver` + bundled catalog + `TasteScorer`) *already runs* in `buildScan`; it just runs *after* the awaited network calls. This is a reordering, not new architecture, and it's the locked constraint the current code violates.
- **#6** — genuinely a `DrinkStore` lookup; cheapest trust win available.
- **#7** — right idea; note `TasteScorer.assess` currently returns a flat `shortReason`, so the pro/con rows need it to expose structured signals (small refactor, it computes them internally anyway).
- **#12/#13** — both bugs confirmed in code; both fixes are small and correctly scoped.
- **§3 Deliberate Differences** — all five are correct and well-argued; "no crowd ratings" and "never paywall the scan" deserve to be written into CLAUDE.md as locked constraints.
- **§4 verdict semantics, typography scale, SRM gradient placeholders** — all iOS 17-safe (`fontDesign(.rounded)`, `fontWidth(.compressed)`, `spring(duration:bounce:)` all fine), asset-free, deterministic.

---

## Corrected Top 8

1. **Never-block scan** (#2): flip `ScanningPipeline` — on-device verdict renders first, network becomes background enrichment that fills blanks only. Deletes the spinner. *(This is a constraint violation today, not polish.)*
2. **Verdict-first result layout** (#1 + §4): kill the 320pt gray box, 48pt rounded-heavy verdict word on top, triple-redundant badge, amber/dark-text YOUR CALL.
3. **Honest states, offline half of #3 + corrected #5**: YOUR CALL when resolver misses, match % below threshold, "Not this one?" candidate paging *on* the verdict card — no pre-verdict gate. Live dots deferred with DataScanner.
4. **Personal history line** (#6) + **"because" copy in compass voice** (#7, incl. exposing TasteScorer signals).
5. **Two confirmed data/timing bugs**: quiz write-through persistence (#12) + notification primer after first verdict instead of native prompt at `finalizeScan` (#13).
6. **Felt verdict, cheap version** (#9): `.sensoryFeedback` + spring entrance; confidence-gated; no custom audio.
7. **Photo states without the gray box** (§4/#14): save photos locally, SRM gradient + type-led card fallbacks; CloudKit photo sync deferred.
8. **Dark-only semantic tokens + forced dark on sheets** (§4, descoped): fixes the white-flash structurally for one line now; light mode is a separate future project.

**Deferred (unchanged but re-justified):** live highlights + confidence dots (gated on the DataScanner spike, the project's stated riskiest unknown — prove it before designing on it), Liquid Glass (iOS 26), Live Activity (#11), taste radar, label-mode "grab instead" (needs a shelf-aware answer, not a catalog lookup).