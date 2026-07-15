# Verified Bug Audit — full-app + camera merge (2026-07-02)

Method: 6 specialist lenses → dedup → adversarial verification (2 refuters for critical/high) → gap-hunt round. 68 raw findings, 57 confirmed, 5 refuted. Audited at main `30ad041`; statuses annotated after the verdict-first refactor.

Statuses: ✅ fixed · 🟡 partial/superseded · 🔵 open, recommended for the E2E/next track · ⚪ open, scheduled/backlog.

### [HIGH] `SipCheck/Services/ScanningPipeline.swift:76`
**Network LLM calls are on the critical path of every scan; the on-device verdict is only computed after they complete, violating the locked fast/$0/offline constraint.**

- **Status:** ✅ FIXED — verdict-first refactor (`4cc5cf4`)
- **Field scenario:** In the Trader Joe's beer aisle with one bar of LTE, every scan hangs on two URLSession requests (default 60s timeout each) while the spinner cycles 'Judging this beer...' — the 'instant' verdict can take 1-2 minutes; the spouse-is-waiting use case is dead. Fully offline it works only because both calls fail and fall through to stubs, still after the failure latency.
- **Detail:** CheckTabView.runScan (SipCheck/Views/Tabs/CheckTabView.swift:339) awaits ScanningPipeline.scan(image:), which after on-device OCR ALWAYS awaits `extractBeerInfoFromText` (Gemini then OpenAI, ScanningPipeline.swift:76,107-120) and then a SECOND network round trip `getVerdictAndExplanation` (ScanningPipeline.swift:77,128-137) — two sequential LLM calls with no timeout configuration. The pure on-device path (BeerResolver.resolve + TasteScorer.assess in CheckTabView.buildScan lines 388-402) runs only AFTER the pipeline returns, so it gates the verdict card on the network instead of showing the ins

### [HIGH] `SipCheck/Views/Tabs/CheckTabView.swift:339`
**MenuParser is dead code — the menu flow ('surface ONE clear winner') is not wired into the app at all; a menu photo goes through the single-beer label pipeline.**

- **Status:** ✅ FIXED — menu auto-detection now ranks parsed candidates, surfaces one winner, and keeps the runner-up behind a tap; verified with the deterministic tap-menu fixture and simulator walkthrough (2026-07-15)
- **Field scenario:** At a restaurant with the waiter approaching, the user photographs a 12-beer tap list. Instead of 'order this' with a winner, the app returns one arbitrary/garbled beer name (whatever the LLM picks out of the blob) or, offline, a Scan whose beerName is the entire multi-line menu text, scored as if it were one beer.
- **Detail:** No view or pipeline calls MenuParser.parse/evaluate/pickWinner; the only external reference to MenuParser is BeerResolver.swift:61 using its extractABV helper (verified by repo-wide grep). CheckTabView has exactly one image path, runScan(image:) → ScanningPipeline.scan(image:), which sends the whole OCR blob to an LLM expecting ONE beer (ScanningPipeline.swift:76) and returns a single BeerInfo. There is no menu-vs-label detection and no ranked-winner UI.

### [HIGH] `SipCheck/Services/TasteScorer.swift:81`
**A beer whose style cannot be determined is scored -0.5 and therefore gets a confident red 'SKIP IT' instead of 'YOUR CALL'.**

- **Status:** ✅ FIXED — verdict-first refactor (`4cc5cf4`)
- **Field scenario:** User scans a Trader Joe's house-brand can with a graphic name ('Boatswain', 'Providencia') that's not in the catalog and has no style keyword — the app flatly declares SKIP IT, steering them away from a beer it knows literally nothing about; the owner's field note 'said Skip It but should've been Try It' is exactly this bug.
- **Detail:** When resolvedStyle is nil, assess() applies score -= 0.5 with reason 'couldn't tell the style' (TasteScorer.swift:79-83). With no ABV signal the final score is -0.5, and verdict(for:) maps any score < 0 to .skipIt (TasteScorer.swift:106-113). So total ignorance produces the most confident negative verdict the app has, rendered as a big red 'SKIP IT' (VerdictCardView.swift:124-137) with no visual hedging. Locked constraint: 'a made-up brew name tells you nothing by itself' and the honest answer for zero signal should be YOUR CALL. The 'no idea' state actively pretends confidence in the wrong di

### [HIGH] `SipCheck/Services/VisionOCRService.swift:67`
**OCR ignores photo orientation: VNImageRequestHandler is built from image.cgImage without the CGImagePropertyOrientation, so every portrait camera capture is OCR'd rotated 90 degrees**

- **Status:** ✅ FIXED — follow-up fixes commit (this merge)
- **Field scenario:** User holds the phone upright (portrait, the natural grip in an aisle) and photographs a Boatswain can with perfectly legible text. OCR reads the sideways image as garbage, the pipeline declares low confidence, and either uploads the whole photo to OpenAI over a dying connection (15s hang) or, with no key/connectivity, shows a card titled 'Unknown Beer' with no style — for a label that was trivially readable. This alone explains most 'the scanner never reads anything' field reports.
- **Detail:** VisionOCRService.extractText uses `image.cgImage` (VisionOCRService.swift:15-16) and `VNImageRequestHandler(cgImage: cgImage, options: [:])` (line 67) without passing `CGImagePropertyOrientation(image.imageOrientation)`. UIImagePickerController camera photos (CameraView.swift:8-14, :30) carry .right/.left orientation metadata with the raw pixel buffer in landscape; dropping it means Vision sees the label text sideways and VNRecognizeTextRequest returns little or nothing. The result is confidence < 0.5, so ScanningPipeline.swift:74 never takes the fast on-device text path and always falls into 

### [HIGH] `SipCheck/Services/ScanningPipeline.swift:42`
**Network LLM calls sit on the critical path of every scan; the on-device verdict is computed only after up to four sequential 15s network requests complete or time out**

- **Status:** ✅ FIXED — verdict-first refactor (`4cc5cf4`)
- **Field scenario:** In the Trader Joe's beer aisle with 1-bar LTE, the user snaps a can; the 'Judging this beer...' spinner sits for 30-60 seconds while Gemini and OpenAI requests stall toward their 15s timeouts, spouse waiting. The identical thumbs-up/down verdict was computable on-device in <50ms. In airplane mode it fails fast; in typical weak-signal grocery/basement conditions it is the worst case.
- **Detail:** ScanningPipeline.scan(text:) (line 42-43) and scan(image:) (lines 76-77, 84, 98) each perform TWO sequential network stages before returning: extractBeerInfoFromText (Gemini, then OpenAI fallback — lines 107-120) and getVerdictAndExplanation (Gemini, then OpenAI fallback — lines 128-137). Each request has timeoutInterval = 15 (GeminiService.swift:164, OpenAIService.swift:294), so a scan can block on up to 4 x 15s = 60s of network before CheckTabView.buildScan (CheckTabView.swift:378-406) ever runs the free on-device BeerResolver/TasteScorer path. Worse, the network verdict is discarded anyway 

### [HIGH] `SipCheck/Services/TasteScorer.swift:69`
**A single historical dislike of a style permanently vetoes it (-5.0) even when the user has liked that style many times, because disliked-set is checked before liked weights.**

- **Status:** ⚪ OPEN — scorer tuning — one historical dislike vetoes a many-times-liked style
- **Field scenario:** User has liked 10 IPAs and thumbs-downed one bad one. At Trader Joe's every IPA they scan now says 'Skip it — you usually avoid ipa', the exact inverse of their taste, and it never self-corrects.
- **Detail:** TasteProfile.build keeps independent like/dislike counts per style (TasteProfile.swift:27-31) — a style with 10 likes and 1 dislike appears in BOTH favoriteStyles and dislikedStyles. TasteScorer.assess checks `dislikedSet.contains(key)` first (TasteScorer.swift:69) and applies -5.0, which no liked weight (capped at 3.0, line 224) or ABV bonus (+0.5) can overcome, so the verdict is always skipIt for the user's actual favorite style. No ratio/threshold logic exists.

### [HIGH] `SipCheck/Services/TasteScorer.swift:172`
**inferStyle does raw substring matching with no word boundaries ('hop', 'pale', 'funk', 'quad'), and BeerResolver treats a keyword hit anywhere in the OCR blob as authoritative 'printed on the label' style that overrides the catalog.**

- **Status:** ✅ FIXED — follow-up fixes commit (this merge)
- **Field scenario:** User scans a dry-hopped pilsner can at Trader Joe's; the blob contains 'dry-hopped' so the beer is scored as an IPA. A user who dislikes IPAs ('Super Bitter' quiz dislike → ipa) gets 'Skip it — you usually avoid ipa' for a crisp pilsner they'd love, even though the bundled catalog has the correct style.
- **Detail:** styleKeywords includes 3-5 char fragments matched via `lower.contains(keyword)` (TasteScorer.swift:189-199): 'Bishop's Finger' contains 'hop' → IPA; 'Missouri Mule' contains 'sour'; 'Quadrant' contains 'quad' → Belgian. Worse, BeerResolver.resolve runs inferStyle over the ENTIRE label blob (BeerResolver.swift:60) — marketing copy like 'dry-hopped for aroma' on a pilsner can matches 'hop' → IPA — then `printedStyle ?? hit?.style` (line 66) lets that guess override a correct catalog style, and source is stamped .labelText, 'most trustworthy' (lines 71-72), which also suppresses correction via en

### [HIGH] `SipCheck/Services/ScanLog.swift:25`
**ScanEvent device/OS/build stamps are silently re-written to the CURRENT device values every time the log is loaded from disk, corrupting the per-device triage data the log exists to provide**

- **Status:** ✅ FIXED — follow-up fixes commit (this merge)
- **Field scenario:** Owner scans 30 beers at Trader Joe's on the iPhone 14 Pro (no Foundation Models), gets weird verdicts, updates the app build that evening, relaunches, does one more scan, then exports scan_log.json for triage — every one of the 30 field events now claims the new build (and would claim the wrong device model if the file were shared/restored across devices), making 'was this the FM path or the heuristic path?' unanswerable.
- **Detail:** deviceModel, osVersion, and appBuild are declared as `let` properties WITH initial values (ScanLog.swift:25-27). Swift's synthesized Decodable skips immutable properties that have default values ('immutable property will not be decoded' warning), so loadFromDisk (lines 165-171) decodes historical events and re-initializes all three fields from DeviceInfo on the current device/build. The values ARE encoded on save, so after any app relaunch, every persisted event is re-stamped and re-persisted with today's device model, OS, and build on the next record(). The header comment says these exist so 

### [HIGH] `SipCheck/Views/CheckBeerView.swift:281`
**The CheckBeerView flow (reachable from HomeView) hard-requires OpenAI on the critical path — offline it produces an error and no verdict at all, and its in-flight Task is never cancelled on sheet dismiss.**

- **Status:** ⚪ N/A (dead code) — HomeView subtree unreachable; scheduled for SPEED_PLAN cleanup
- **Field scenario:** User taps the Home-screen check flow at Trader Joe's with no signal: spinner, then a red 'check your connection' error — zero thumbs-up/down ever appears. Or they give up and close the sheet; the orphaned Task keeps burning two network calls in the background.
- **Detail:** searchBeer() and processImage() both end in `try await OpenAIService.shared.getRecommendation(...)` (CheckBeerView.swift:281, :318) with no on-device fallback: any thrown error (no key, airplane mode, timeout) lands in the catch and shows 'Couldn't get AI recommendation. Check your connection and try again.' (:109). processImage additionally awaits the full ScanningPipeline.scan(image:) first (:311), stacking its serial network waits on top. None of the on-device stack (BeerResolver/TasteScorer/BundledCatalog) is used here, so this entry point violates 'a verdict must appear even with zero con

### [HIGH] `SipCheck/Views/Tabs/CheckTabView.swift:406`
**The verdict badge and the explanation come from two different engines and can directly contradict each other**

- **Status:** ✅ FIXED — verdict-first refactor (`4cc5cf4`)
- **Field scenario:** TasteScorer scores a hazy IPA at 1.5 (YOUR CALL) while Gemini returns TRY_IT with 'This matches your love of hazy IPAs — definitely grab it!'. The card shows a yellow 'YOUR CALL' headline directly above copy urging the user to definitely try it. In the aisle this reads as the app arguing with itself.
- **Detail:** buildScan always uses the on-device TasteScorer verdict (assessment.verdict, CheckTabView.swift:396-402, :428) and discards the network verdict (ScanResult.verdict is never read), but it keeps the network's explanation when present (usableNetworkExplanation, CheckTabView.swift:406, :438-444). That explanation was generated by Gemini/OpenAI to justify ITS OWN verdict (GeminiService.swift:102-115 asks for '{verdict, explanation}' as a pair). When the two engines disagree — common, since one uses LLM world knowledge and the other a heuristic score — the card renders mismatched content (VerdictCar

### [HIGH] `SipCheck/Views/Tabs/CheckTabView.swift:388`
**The menu flow is unwired: MenuParser.evaluate/pickWinner has zero callers, so photographing a menu never produces the required single ranked winner**

- **Status:** ✅ FIXED — MenuParser is wired into the image path with one-winner and runner-up UI; covered by parser/integration tests and simulator E2E (2026-07-15)
- **Field scenario:** At a restaurant with a 12-beer tap list, the user snaps the menu; offline they get a verdict card whose title is the whole menu text scored as one 'beer', and online they get a verdict for whichever single beer the LLM happened to pick — never the taste-ranked 'order this' winner the product requires.
- **Detail:** Grep across SipCheck/ finds no call sites for MenuParser.parse/evaluate/pickWinner (SipCheck/Services/MenuParser.swift:41, :76, :115) outside the file itself — only MenuParser.extractABV is used, on a single name string inside BeerResolver.resolve (BeerResolver.swift:61). A menu photo goes down the one-beer label path: ScanningPipeline.scan(image:) OCRs the whole menu and sends the blob to the text LLM, which extracts one arbitrary beer (ScanningPipeline.swift:76), or with no provider stubs beerInfo.name to the ENTIRE multi-line menu text (ScanningPipeline.swift:118-119). CheckTabView.buildSca

### [HIGH] `SipCheck/Services/BeerResolver.swift:219`
**BundledCatalog name matching is effectively dead for label scans: normalize() does not strip the newlines that VisionOCRService puts between every OCR line, so the 2,410-beer offline catalog almost never matches.**

- **Status:** ✅ FIXED — verdict-first refactor (`4cc5cf4`)
- **Field scenario:** Offline at Trader Joe's, user scans a Sierra Nevada Pale Ale can; OCR returns "SIERRA\nNEVADA\nPALE ALE". The catalog contains the beer with its real 5.6% ABV, but lookup misses; style comes only from the 'pale' keyword and ABV is nil, so the verdict is degraded — and for beers whose names don't telegraph a style ("Watt Strike") the result is 'couldn't tell the style' + YOUR CALL even though the beer is in the bundled catalog.
- **Detail:** VisionOCRService joins recognized lines with "\n" (VisionOCRService.swift:57). When the network is unreachable, ScanningPipeline stubs beerInfo.name to that full multi-line blob (ScanningPipeline.swift:96, :119) and buildScan feeds it to BeerResolver.resolve → BundledCatalog.lookup. normalize() (BeerResolver.swift:219-223) only lowercases, trims the string ends, and collapses one pass of double spaces — interior newlines and punctuation survive. So the exactIndex lookup and both substring checks (q.contains(n) / n.contains(q), BeerResolver.swift:192-195) fail for any label whose name OCRs acro

### [HIGH] `SipCheck/Services/MenuParser.swift:76`
**The menu path — a locked product requirement ('menu → ONE clear winner') — is not wired into the app at all; MenuParser.evaluate/pickWinner is dead code.**

- **Status:** ✅ FIXED — automatic menu detection produces one ranked winner and an optional tap-to-reveal runner-up (2026-07-15)
- **Field scenario:** User at a restaurant photographs the tap list (one of the three locked input types); instead of 'order this' with a tap-for-runner-up, the whole menu text is treated as one beer name — the LLM or keyword matcher latches onto whichever style word appears first and returns a single meaningless verdict for the entire menu.
- **Detail:** The only production caller of MenuParser is BeerResolver.resolve using extractABV on a single line (BeerResolver.swift:61). MenuParser.evaluate / pickWinner (MenuParser.swift:76-121) and TasteScorer.ranksAhead are never invoked from any view or pipeline. CheckTabView offers only 'Scan Label' and 'Enter beer name' (CheckTabView.swift:145-173); there is no menu detection (e.g. multi-line OCR with several style/ABV/price lines) and no winner UI. A menu photo is funneled through the single-beer pipeline as one blob.

### [HIGH] `SipCheck/Views/Tabs/CheckTabView.swift:45`
**The scanning spinner screen has no cancel button — the user is trapped for the full duration of the network waits.**

- **Status:** ✅ FIXED — network is off the critical path; real label fixtures resolve on-device in about 2.2-2.5s after OCR warmup (2026-07-15)
- **Field scenario:** Scan hangs on store Wi-Fi captive portal; user watches 'Forming an opinion...' loop for a minute with no cancel, gives up, force-quits the app in the aisle.
- **Detail:** When isScanning is true the entire tab is replaced by scanningView (CheckTabView.swift:45-46, 179-217), which contains only a spinner and cycling phrases. There is no cancel/back control, and scanTask is only cancelled from resetScanState via the verdict card's 'Scan Another' button (CheckTabView.swift:53-55, 461). Combined with the up-to-60s network critical path, the user cannot abort a hung scan, retake the photo, or drop to typed entry; their only escape is switching tabs (which doesn't cancel the task) or killing the app.

### [HIGH] `SipCheck/Services/MenuParser.swift:115`
**Menu mode is completely unwired: MenuParser.pickWinner is never called from any view, so a menu photo is treated as one giant single-beer label.**

- **Status:** ✅ FIXED — the image flow calls MenuParser's evaluation path and renders its winner/runner-up in VerdictCardView (2026-07-15)
- **Field scenario:** User photographs a 20-beer tap list at a restaurant with the waiter approaching; instead of 'order the Two Hearted', the app returns one verdict card for an arbitrary/garbled 'beer' the LLM plucked from the blob (or the raw blob itself offline) — the flagship menu use case simply does not exist in the shipped UI.
- **Detail:** MenuParser.evaluate/pickWinner (MenuParser.swift:74-121) — the component that implements the locked 'menus must surface ONE clear winner' requirement — has zero call sites in the UI (grep shows only BeerResolver using MenuParser.extractABV). CheckTabView offers only 'Scan Label' and feeds every image through ScanningPipeline.scan(image:) (CheckTabView.swift:339), which OCRs the whole menu into one blob and asks the network LLM to extract a single beer's name/style/ABV (ScanningPipeline.swift:76). There is no menu/label mode distinction anywhere in the scan UI, no ranked list, no runner-up tap.

### [HIGH] `SipCheck/Views/Components/CameraView.swift:8`
**Capture uses UIImagePickerController — a full shutter + 'Use Photo' confirmation flow — instead of the specified live point-and-read scanner.**

- **Status:** ⚪ OPEN — next phase — DataScanner live-scan spike (device required)
- **Field scenario:** Holding a six-pack in one hand, the user must aim, hit the shutter, then hit 'Use Photo' on the confirm screen — three precise taps per can; comparing four cans means twelve taps plus four camera relaunches while the spouse waits.
- **Detail:** CameraView wraps UIImagePickerController with sourceType = .camera (CameraView.swift:8-13). That imposes iOS's stock still-photo UI: frame, tap shutter, then a Retake/'Use Photo' confirmation screen before capturedImage is set. The locked architecture calls for VisionKit DataScannerViewController ('live point-and-read, no shutter'). Tap count from app-open to verdict is: tap 'Scan Label' (1) → tap shutter (2) → tap 'Use Photo' (3) → wait; and every additional beer repeats all three. One-handed operation with a phone-sized shutter+confirm dance is exactly the friction the spec forbids.

### [HIGH] `SipCheck/Services/ScanningPipeline.swift:96`
**Offline/no-key scans use the entire newline-joined OCR dump as the 'beer name', which is displayed raw on the card and defeats the catalog match.**

- **Status:** ✅ FIXED — verdict-first refactor (`4cc5cf4`)
- **Field scenario:** In a dead zone, the verdict card headline is 'HAZY\nIPA\n12 FL OZ\nGOVERNMENT WARNING...' repeated twice, and the 2,410-beer offline catalog contributes nothing because the newline-riddled query can't match, so style falls back to keyword luck.
- **Detail:** When no LLM provider responds, the stub BeerInfo's name is the whole OCR text (ScanningPipeline.swift:93-96 for images; 115-119 for text path), which VisionOCRService joins with '\n' across every line on the label (VisionOCRService.swift:57). buildScan passes that blob as the display name and to BeerResolver (CheckTabView.swift:380-391); VerdictCardView then renders the multiline blob twice — inside the photo placeholder and as the title (VerdictCardView.swift:22, 46). BundledCatalog.normalize never strips newlines or collapses whitespace properly (BeerResolver.swift:219-223, it only string-re

### [HIGH] `SipCheck/Views/OnboardingView.swift:209`
**Onboarding beer-picker selections ('knownBeers') are written to UserDefaults but never read anywhere in the codebase, so the 'calibrate your taste' page is completely inert.**

- **Status:** ✅ FIXED — every onboarding beer maps to an explicit style and named go-to picks seed the full-weight taste profile; all 16 choices are covered by tests (2026-07-15)
- **Field scenario:** New user taps Guinness, Stone IPA, Sierra Nevada, Corona etc. during onboarding, walks into Trader Joe's, and scans a stout: the verdict engine has zero liked-style history (favoriteStyles is empty), so their picks are silently discarded and scan #1 behaves as if they told the app nothing about beers they already know.
- **Detail:** BeerPickerPage.advance() writes the selected beers to UserDefaults key 'knownBeers' (OnboardingView.swift:209). A repo-wide grep shows that is the ONLY occurrence of 'knownBeers' — no code in TastePreferences, TasteScorer, TasteProfile, BeerResolver, or any store ever reads it. The page explicitly promises 'Tap any you've tried. We'll use it to calibrate your taste.' (OnboardingView.swift:89), and the locked cold-start constraint says the quiz 'seeds the taste library so scan #1 is personalized'. The taste library (TasteProfile.build, TasteProfile.swift:14) is built only from drinkStore.drinks

### [HIGH] `SipCheck/Services/DrinkStore.swift:141`
**One bad element in drinks.json silently wipes the entire taste library, and the 'backup' is clobbered on the very next launch with no restore path anywhere**

- **Status:** 🔵 OPEN — data safety (recommend next track, HIGH) — bad element can wipe taste library; backup clobbered
- **Field scenario:** User's drinks.json picks up one malformed record (sample-data injection, interrupted schema experiment, or a field type drift between builds on the two test iPhones). Next launch at Trader Joe's: decode throws, store silently loads empty, the taste profile shows 0 beers, every scan verdict reverts to cold-start 'YOUR CALL'. The user shrugs and logs the beer in their hand — that save permanently overwrites years of taste history, and one more launch destroys the only backup copy.
- **Detail:** loadDrinks() decodes the whole file with JSONDecoder().decode([Drink].self, from:) (DrinkStore.swift:136) — an all-or-nothing array decode. If ANY single element throws, the catch at :139-143 resets drinks = [] and tombstones = []. The next mutation (addDrink at :39-47, or updateDrink) calls saveDrinks() (:115-123), which overwrites drinks.json with only the new record — the full history is destroyed on disk. The per-field tolerant decoder in Drink.init(from:) (Drink.swift:61-75) handles MISSING keys (so the scan branch's new lastModifiedLocal/isDeleted fields migrate fine), but decodeIfPresen

### [HIGH] `SipCheck/Services/CloudKitSyncService.swift:115`
**Upload path has no last-write-wins guard: a device whose fetch failed blindly re-uploads every stale record, permanently clobbering the newer rating entered on the other iPhone; offline saves are also silently dropped with no retry**

- **Status:** 🔵 OPEN — sync correctness (recommend E2E/next track)
- **Field scenario:** iPhone 15 Pro rates 'Two Hearted' as like; server updated. iPhone 14 Pro launches inside Trader Joe's with no signal: fetch returns [], fullSync enqueues its stale copy of the same record; when signal returns in the parking lot, the stale rating overwrites the server. The 14 Pro never shows the rating, and if the 15 Pro ever restores from CloudKit (e.g. after the drinks.json wipe in the critical finding), the rating is gone everywhere — the taste library silently degrades across devices.
- **Detail:** fetchAllDrinks/fetchAllScans/fetchAllJournalEntries (:57, :72, :87) use `try? await db.records(...)` and return [] on ANY error (no network, iCloud signed out, CloudKit 'recordName not queryable' schema error). fullSync (:114-125) then computes remoteDrinkIDs as an empty set and calls save() for EVERY local record. saveRecord (:30-47) fetches the server record and populates local field values unconditionally — there is no lastModifiedLocal comparison on the upload path — and the .serverRecordChanged handler (:37-41) explicitly refetches the server copy and force-overwrites the concurrent write

### [MEDIUM] `SipCheck/Services/BeerResolver.swift:192`
**BundledCatalog fuzzy lookup is a first-match bidirectional substring test with no query-length guard, so generic catalog names confidently match the wrong beer.**

- **Status:** ✅ FIXED — verdict-first refactor (`4cc5cf4`)
- **Field scenario:** User types 'lager' (a documented input mode) — the card confidently shows '#001 Golden Amber Lager, Wisconsin Brewing Company, 5.5%'. User scans 'Trader Joe's 2015 Vintage Ale — truly a beer to savor' — it resolves to the catalog entry 'A Beer' with someone else's style/ABV and scores the wrong beer.
- **Detail:** lookup() (BeerResolver.swift:192-198) returns `entries.first(where:)` whose normalized name is ≥6 chars and is a substring of the query OR contains the query. The catalog (alphabetical) contains entries literally named 'A Beer', 'Amber Ale', 'India Pale Ale', 'Oktoberfest' (x6), 'Original', 'Summer Ale' (verified in SipCheck/Resources/catalog.json) — any label blob containing the phrase 'a beer' or 'amber ale' hits those rows and returns that random brewery's ABV. The reverse direction has no minimum query length: typing 'lager' matches the first entry containing it, '#001 Golden Amber Lager' 

### [MEDIUM] `SipCheck/Views/Components/VerdictCardView.swift:84`
**The verdict card is a dead end for the 'I'm buying it' moment: no way to log/journal the beer now — only 'Save for Later' and 'Scan Another'.**

- **Status:** ✅ FIXED — verdict cards can open Add Beer immediately with the resolved metadata and captured photo prefilled (2026-07-15)
- **Field scenario:** User gets 'TRY IT', tosses the beer in the cart, and wants to mark it tried right there — there is no button; they must remember to do it from the Journal tab manually or wait two days for a notification, so the taste library (which powers every future verdict) never learns.
- **Detail:** VerdictCardView's only actions are onSaveForLater and onScanAnother (VerdictCardView.swift:84-115). There is no 'Drinking it / Log it' action that opens AddBeerView, even though CheckTabView already has the full showingAddBeer + AddBeerPrefill machinery wired (CheckTabView.swift:95-107) — it is reachable only via FollowUpView, and CheckTabView's own FollowUpView sheet is dead code because showingFollowUp is never set to true anywhere in the view (declared CheckTabView.swift:23, only ever set false at 77-90). The only working path to logging a scan is the 48/72-hour-later push notification (Not

### [MEDIUM] `SipCheck/Services/MenuParser.swift:167`
**extractABV inspects only the first %-token and returns nil if it is implausible, misses no-%-sign formats ('ABV: 7', 'ALC 5.9 BY VOL'), fails on two-decimal ABVs ('7.25%'), and accepts '20% off' as a 20.0 ABV.**

- **Status:** ✅ FIXED — ABV extraction handles multiple candidates, two decimals, `ABV:`/`ALC ... BY VOL`, and ignores discount percentages; covered by tests (2026-07-15)
- **Field scenario:** A tap list printed as 'Two Hearted IPA — ABV: 7 — $6' produces abv=nil (loses the ABV proximity signal and tiebreak); a menu with a 'Happy Hour 50% off' banner text on the beer's line loses its real ABV; a '20% off' line scores a phantom 20% ABV penalty ('20% is off your usual strength').
- **Detail:** extractABV (MenuParser.swift:167-175) takes abvRegex.firstMatch and, when the value falls outside 0.5...20.0, returns nil instead of scanning subsequent matches — so 'Happy hour 50% off — Pliny the Elder 8.0%' yields no ABV although 8.0% is right there. plausibleABV includes 20.0, so '20% off pints' parses as ABV=20 and triggers the max strength penalty (TasteScorer.swift:94). The regex `(\d{1,2}(?:\.\d)?)\s?%` (line 148) allows only one decimal digit, so '7.25%' matches as '25' (rejected → nil); and it requires a % sign, so common menu/label formats 'ABV: 7', 'ABV 6.5', 'ALC. 5.9 BY VOL' are 

### [MEDIUM] `SipCheck/Services/MenuParser.swift:64`
**Style-word section headers ('IPAs', 'Stouts', 'Sours') pass the parse-confidence floor as beer candidates and can be ranked as the menu winner.**

- **Status:** ✅ FIXED — style-only menu section headings are filtered before ranking; covered by menu tests (2026-07-15)
- **Field scenario:** A menu sectioned 'IPAs / Lagers / Sours' where the user loves IPAs: the app's single clear winner is the literal word 'IPAs' — 'order this: IPAs' — instead of any orderable beer.
- **Detail:** sectionRegex (MenuParser.swift:141) only knows generic headers (on tap/drafts/bottles/cans/beer/menu/drinks). A header line like 'IPAs' or 'Local Sours' is ≥3 chars, not a section header per the regex, and inferStyle returns a style for it, so the `style != nil || abv != nil || hasPrice` floor (line 64) keeps it. With a liked style weight (e.g. ipa = 3.0) and no ABV, the header scores 3.0 while a real IPA at 9.5% scores 3.0 - 1.25 + ... less — the header can outrank every actual beer and become MenuVerdict.winner.

### [MEDIUM] `SipCheck/Services/BeerMatcher.swift:16`
**BeerMatcher contains-match has no minimum-length guard and the Levenshtein pass returns the first drink over threshold rather than the best match.**

- **Status:** ⚪ OPEN (low)
- **Field scenario:** User with a logged beer named 'IPA' checks any IPA at the store — the app claims they've already tried it and shows that old rating; OCR that drops an apostrophe ('Bells Two Hearted') fails the exact and contains passes it should trivially hit.
- **Detail:** The bidirectional contains check (BeerMatcher.swift:16) means a history drink named 'IPA' matches every query containing 'ipa' (and query 'ipa' matches any drink name containing it) — first array element wins, not best. The fuzzy loop (lines 22-27) returns the FIRST drink with similarity ≥0.7 in storage order instead of the maximum-similarity drink, so 'Sierra Nevada Torpedo' can match 'Sierra Nevada Pale Ale' while a closer entry sits later in the list. normalize (lines 33-38) does one non-iterative double-space replace, keeps punctuation and diacritics ('Bell's' vs 'Bells', 'Kölsch' vs 'Kols

### [MEDIUM] `SipCheck/Services/ScanningPipeline.swift:119`
**With API keys empty (CI-injected secrets absent) an image scan's 'beer name' becomes the entire raw OCR blob, which is then rendered as the card title and fed to the resolver**

- **Status:** ✅ FIXED — verdict-first refactor (`4cc5cf4`)
- **Field scenario:** TestFlight build produced without the OPENAI/GEMINI secrets set: user scans a stout can whose ingredients line says 'malted barley, hops, water' and gets a card titled with five lines of label legalese, classified as IPA ('hop' keyword), with a verdict scored against the wrong style.
- **Detail:** When Config.geminiAPIKey/openAIAPIKey are empty (CI writes them from repo secrets, .github/workflows/testflight.yml Secrets heredoc; Secrets.swift is gitignored and absent locally), extractBeerInfoFromText returns BeerInfo(name: <full OCR text>) (ScanningPipeline.swift:118-119) and the vision-fallback stub does the same (lines 95-96). CheckTabView.buildScan uses that as the display name (line 380) and VerdictCardView renders it as the photo-overlay label and title (VerdictCardView.swift:22, :46). The multi-line blob (government warning, '12 FL OZ', brewery legal text) also drives style inferen

### [MEDIUM] `SipCheck/Services/VisionOCRService.swift:72`
**Possible double-resume of the checked continuation in VisionOCRService when handler.perform throws after the request completion handler already ran**

- **Status:** ✅ FIXED — follow-up fixes commit (this merge)
- **Field scenario:** A capture that Vision rejects (e.g. corrupt/zero-sized frame under memory pressure in the store) causes the request to complete with an error AND perform() to throw; the continuation resumes twice and the app crashes mid-scan instead of falling back to 'Unknown Beer'.
- **Detail:** The VNRecognizeTextRequest completion handler resumes the continuation on error (VisionOCRService.swift:20-26), and the catch around `try handler.perform([request])` resumes it again (lines 69-73). Vision invokes a request's completionHandler (with error set) for failed requests and perform() then also throws — in that sequence the checked continuation is resumed twice, which traps at runtime (fatal error). This is only reachable on Vision-level failures (unsupported/exotic image, internal error), but the guard structure makes both resumes possible for one failure.

### [MEDIUM] `SipCheck/Services/NotificationService.swift:59`
**The system notification-permission dialog pops over the very first scan verdict, interrupting the in-the-moment flow.**

- **Status:** ✅ FIXED — authorization is requested only after the user explicitly chooses Save for Later, never over the first verdict (2026-07-15)
- **Field scenario:** First-ever scan at Trader Joe's: the instant the TRY IT card appears, an 'SipCheck Would Like to Send You Notifications' alert covers it. User, in a hurry, dismisses with Don't Allow — the verdict was obscured at the critical moment and the entire follow-up loop (48/72h check-ins) is permanently disabled.
- **Detail:** finalizeScan calls notificationService.scheduleFollowUp for every non-skip scan (CheckTabView.swift:448), and scheduleFollowUp unconditionally calls requestAuthorization() (NotificationService.swift:56-59) which triggers UNUserNotificationCenter's modal permission alert the first time. There is no pre-permission priming and no deferral to a calmer moment (e.g. onboarding or Save for Later). If the user reflexively taps 'Don't Allow' in the aisle, all follow-up notifications are silently dead forever, and center.add failures are only printed.

### [MEDIUM] `SipCheck/Views/Tabs/CheckTabView.swift:448`
**finalizeScan schedules a follow-up push notification for every non-skip scan, not just saved ones — scanning the aisle generates notification spam.**

- **Status:** ✅ FIXED — only Save for Later schedules a follow-up; ordinary comparison scans do not create reminders (2026-07-15)
- **Field scenario:** User comparison-scans 8 cans at Trader Joe's and buys one; over the next three days their lock screen fills with 'Did you try Boatswain Twin Screw? 🍺', 'Ever get around to Simpler Times Lager?' — seven of them about beers left on the shelf — until they disable notifications.
- **Detail:** finalizeScan calls notificationService.scheduleFollowUp(for: scan) for every completed scan (CheckTabView.swift:446-451); scheduleFollowUp only skips .skipIt verdicts (NotificationService.swift:56-61) and pays no attention to wantToTry (which is false at this point, CheckTabView.swift:430). saveForLater then schedules again (CheckTabView.swift:457). So every TRY IT / YOUR CALL verdict the user merely glanced at becomes a 48-72h reminder.

### [MEDIUM] `SipCheck/Views/Components/VerdictCardView.swift:14`
**The verdict is not the visually dominant element: a 320pt empty gray placeholder box tops the card, pushing the 34pt verdict to mid-screen, and the user's actual photo is discarded.**

- **Status:** ✅ FIXED — the empty gray block is gone; captured/library photos are no longer discarded and persist into Add Beer, Journal, detail, and relaunch; verified with two real label fixtures (2026-07-15)
- **Field scenario:** User glances at the phone held at arm's length over the cart: the top 40% of the screen is an empty gray rectangle with a faint mug; they have to squint/scroll to find whether it said TRY IT or SKIP IT.
- **Detail:** The card leads with a fixed 320pt Rectangle placeholder containing a dim mug icon and the beer name (VerdictCardView.swift:14-26) — there is no image property on Scan and the capturedImage from the camera is never passed in (CheckTabView.swift:48-56), so this area is always empty chrome. The verdict itself is 34pt text (SipTypography.display, DesignSystem.swift:25) sitting below it (VerdictCardView.swift:38-42) with no thumbs-up/down glyph. At arm's length the eye lands on a big blank gray box, not the 👍/👎 answer the 8-second use case demands; on smaller phones the action buttons are pushed be

### [MEDIUM] `SipCheck/Views/Tabs/CheckTabView.swift:460`
**Re-scan requires a full teardown loop: Scan Another → prompt screen → 'Scan Label' → shutter → 'Use Photo' for every subsequent beer.**

- **Status:** 🟡 PARTIAL — state machine simplifies re-scan; shutter flow itself is the DataScanner spike
- **Field scenario:** Deciding between five IPAs on the shelf, the user does the full three-tap camera relaunch ritual five times; by beer three they give up and just buy their usual.
- **Detail:** onScanAnother calls resetScanState (CheckTabView.swift:53-55, 460-468) which returns to scanPromptView; the camera sheet is not re-presented, so the user must tap 'Scan Label' again (CheckTabView.swift:145-160) and repeat the UIImagePickerController shutter + confirm dance. Comparing N beers costs 3N taps and N camera cold-starts. A live scanner (or at minimum reopening the camera directly from 'Scan Another') would make consecutive scans continuous.

### [MEDIUM] `SipCheck/Services/CloudKitSyncService.swift:72`
**fetchAllScans returns [] on any error and truncates silently at the query limit, so fullSync re-uploads every local record one-by-one (2 network round trips each, serialized) and remote records beyond the first page never merge**

- **Status:** 🔵 OPEN — sync correctness (recommend E2E/next track)
- **Field scenario:** Opening the app inside Trader Joe's (no iCloud reachability) queues hundreds of doomed serialized CloudKit ops at launch — radio spun up the whole visit, battery drain, and the scans the user takes right now sit behind that queue waiting to sync. Long-term, once history passes the query page size, the MacBook-adjacent iPhone and the field iPhone permanently disagree about scan history with no error surfaced.
- **Detail:** fetchAllScans/fetchAllDrinks/fetchAllJournalEntries use `guard let results = try? await db.records(matching:resultsLimit: 2000) else { return [] }` (lines 57, 72, 87) — a network failure, an un-queryable-index CKError, or result-set truncation (CloudKit serves pages; no queryCursor handling exists) all look identical to 'remote is empty'. fullSync (lines 114-126) then treats every local drink/scan/journal as missing from remote and calls save() per record; each save does fetchOrCreate (a fetch RTT) + db.save (another RTT) serialized through WriteQueue (lines 30-47), so N records = 2N sequentia

### [MEDIUM] `SipCheck/Services/TastePreferences.swift:9`
**Quiz taste preferences live only in device-local UserDefaults.standard and are excluded from CloudKit sync, so taste is NOT shared between the iPhone 14 Pro and 15 Pro, violating the locked cross-device constraint.**

- **Status:** 🔵 OPEN — sync (quiz prefs don't sync)
- **Field scenario:** Owner completes the taste quiz on the 15 Pro at home ('Hoppy & Bitter', dislikes 'Really Sour'), then field-tests at Trader Joe's with the 14 Pro: on that phone TastePreferences.current is empty, the +2.0 vibe boost and -5.0 dislike veto never fire, and the same IPA that says TRY IT on the 15 Pro comes back as a bland 'your call' — looking like random/broken personalization rather than the documented Foundation-Models wording difference.
- **Detail:** TastePreferences.current reads tasteVibe/tasteAdventure/tasteDislikes from UserDefaults.standard (TastePreferences.swift:9-11), and OnboardingView writes them there (OnboardingView.swift:303-305). UserDefaults.standard never syncs across devices; grep confirms NSUbiquitousKeyValueStore appears nowhere in the project. The CloudKit launch sync (SipCheckApp.swift:206-215, performLaunchSync) only syncs drinks, scans, and journal entries. The key strings themselves match perfectly between writer and reader — the store is the problem, not the keys. Note this also means every scan's verdict (CheckTab

### [MEDIUM] `SipCheck/Views/OnboardingView.swift:303`
**saveAndContinue unconditionally overwrites all three taste keys even on 'Skip for now', so replaying onboarding and skipping the quiz silently ERASES previously saved quiz answers.**

- **Status:** ⚪ OPEN — onboarding batch
- **Field scenario:** Owner replays onboarding to show a friend or fix a setting, gets to the quiz page, taps 'Skip for now' because the answers 'are already saved' — their vibe and dislikes are wiped to empty, and every subsequent in-aisle scan loses the dislike veto (e.g. sours they hate now score 'your call' instead of SKIP IT), with no error or indication anything changed.
- **Detail:** Both the primary CTA (OnboardingView.swift:278) and the 'Skip for now' button (:288) call the same saveAndContinue(), which writes selectedVibe ?? "" / selectedAdventure ?? "" / joined dislikes to UserDefaults (:303-305) with no guard for 'user answered nothing — keep existing values'. Settings offers 'Replay Onboarding' (SettingsTabView.swift:56-68) as the only re-entry into the quiz; going through it and skipping (or tapping the primary button without re-selecting) resets tasteVibe/tasteAdventure/tasteDislikes to empty strings, destroying the previously saved profile. TastePreferences.curren

### [MEDIUM] `SipCheck/Services/TasteScorer.swift:262`
**Quiz vibe 'Fruity & Easy' maps to liked styles {sour, wheat} — identical to 'Sour & Weird' — so easy-drinking users get a +2.0 boost on sour beers they likely hate, and get no boost on lagers/wheats-adjacent easy styles.**

- **Status:** ⚪ OPEN — scorer tuning
- **Field scenario:** A 'Fruity & Easy' user (thinking shandies and juicy easy-drinkers) scans a Trader Joe's gose or Berliner Weisse: score gets +2.0 and the card says 'TRY IT — matches your love of sour'; they buy it, hate it, and lose trust in the verdicts.
- **Detail:** vibeStyleKeys (TasteScorer.swift:249-266) checks lower.contains("fruit") || contains("sour") || contains("tart") and maps both to ["sour", "wheat"] (:262-264). The quiz offers 'Fruity & Easy' and 'Sour & Weird' as distinct personas (OnboardingView.swift:226), but the scorer collapses them into the same liked-style set, and nothing in the 'Fruity & Easy' branch maps to lager/pilsner/fruit-forward pale styles despite 'Easy'. ProfileTabView even brands these users differently ('Flavor Chaser' vs 'Sour Seeker', ProfileTabView.swift:17-19) while their verdicts are identical. This is a real vocabula

### [MEDIUM] `SipCheck/Views/OnboardingView.swift:231`
**The required 'How adventurous?' quiz answer is never consumed by the on-device verdict path — TasteScorer ignores preferences.adventure entirely, so it only affects optional network prompts.**

- **Status:** ⚪ OPEN — onboarding batch
- **Field scenario:** Two users answer identically except one picks 'Stick to Favorites' and the other 'Give Me the Weird Stuff'; with no connectivity in the store aisle, both get byte-identical verdicts on every beer — the required question the app made them answer changes nothing in the moment it was built for.
- **Detail:** hasRequiredSelections (OnboardingView.swift:230-232) treats selectedAdventure as required alongside vibe, but TasteScorer.assess/likedStyleWeights/dislikedStyleKeys only read preferences.vibe and preferences.dislikes (TasteScorer.swift:229, :242); 'adventure' appears in no scoring code. Its only consumers are TastePreferences.promptSummary (TastePreferences.swift:23) injected into OpenAIService (:152, :238) and GeminiService (:77, :93) prompts — the network enrichment path that the locked constraints say is never on the critical path and must work at $0 offline. So on the offline/fast path (an

### [MEDIUM] `SipCheck/Views/Tabs/SettingsTabView.swift:66`
**There is no lightweight way to (re)take or edit the taste quiz: the only re-entry, 'Replay Onboarding', also resets the age gate and forces back through all five intro pages, and (combined with the overwrite bug) risks wiping saved answers.**

- **Status:** ⚪ OPEN — onboarding batch
- **Field scenario:** User skipped the quiz on first launch, notices at Trader Joe's that verdicts feel generic, opens Profile hoping to set preferences — finds only a read-only 'Explorer' badge; the fix is buried in Settings behind a destructive-looking 'Replay' alert that re-runs the 21+ gate while the spouse waits.
- **Detail:** ProfileTabView reads tasteVibe/tasteAdventure only to render the persona badge (ProfileTabView.swift:11-22) with no edit affordance. SettingsTabView's 'Replay Onboarding' (SettingsTabView.swift:56-73) sets hasConfirmedAge = false (:66) in addition to hasCompletedOnboarding = false (:67), so fixing one quiz answer requires re-confirming age and swiping through three marketing pages plus the beer picker before reaching the quiz. There is no direct 'Edit taste preferences' entry point anywhere, which is the only recovery path for a user who skipped the quiz (per the skippable-CTA finding) or want

### [MEDIUM] `SipCheck/Services/OpenAIService.swift:358`
**resizeImage renders at device screen scale (3x), so the 'max 1024' vision upload is actually a 3072-pixel JPEG — roughly 9x the intended pixel count on flaky LTE**

- **Status:** ✅ FIXED — follow-up fixes commit (this merge)
- **Field scenario:** Low-confidence OCR triggers the vision fallback (ScanningPipeline.swift:84). On grocery-store LTE, uploading a multi-megabyte base64 payload stalls; the 15s inactivity timeout fires or the upload crawls for tens of seconds, the fallback fails, and the user drops to the raw-OCR stub path — slow AND wrong.
- **Detail:** resizeImage (OpenAIService.swift:352-360) creates `UIGraphicsImageRenderer(size: newSize)` without a format whose `scale = 1`. The default renderer format uses the main screen scale (3.0 on iPhone 14/15/16 Pro), so a newSize of 1024pt renders a UIImage whose backing bitmap is 3072x3072 px; `jpegData` (line 41) encodes at pixel resolution. The base64 body sent to /chat/completions (line 71) is therefore several MB instead of a few hundred KB, and OpenAI vision token cost/latency scales with resolution ('detail' is unset → auto → high for large images). ImageCompressor.compress has the identical

### [MEDIUM] `SipCheck/Config.swift:11`
**Key validity is only ever checked as !isEmpty, so placeholder keys from Secrets.swift.example pass every gate and force doomed sequential network round trips per scan**

- **Status:** ⚪ OPEN (low)
- **Field scenario:** The build on the field iPhone was compiled locally (CLAUDE.md mandates Xcode Cmd+R for device builds) with a Secrets.swift copied from the example. At Trader Joe's, every scan makes 2-4 real network requests to endpoints guaranteed to reject the key, each waiting on spotty LTE, before showing the raw-OCR stub — matching the observed breakage.
- **Detail:** Secrets.swift is gitignored and absent from the working tree (CI-injects it), so local/device builds require hand-creating it; copying Secrets.swift.example verbatim yields non-empty strings like "your-gemini-api-key-here" (Secrets.swift.example:6-8). Every guard in the stack tests only emptiness: GeminiService.swift:43/73/89, OpenAIService.swift:35/90/148/214, and the provider-selection gates ScanningPipeline.swift:108 and 129. With placeholder (or revoked/wrong) keys, the pipeline selects Gemini as primary, performs a real HTTPS round trip that fails 400/403, then sequentially tries OpenAI (

### [MEDIUM] `SipCheck/Services/CloudKitSyncService.swift:57`
**fetchAll* ignore the CloudKit query cursor, so only the first server page of drinks/journal history ever syncs down — a second device gets a truncated taste library**

- **Status:** 🔵 OPEN — sync correctness (recommend E2E/next track)
- **Field scenario:** User has 250 logged beers. They reinstall SipCheck (or the drinks.json wipe fires) and rely on CloudKit to restore, or they pick up the second test iPhone: only ~the first page of drinks comes down. TasteProfile.build runs on a truncated history, so the same beer scanned at Trader Joe's gets a different verdict on the 14 Pro than the 15 Pro for reasons that have nothing to do with Foundation Models availability.
- **Detail:** fetchAllDrinks (:56-62), fetchAllScans (:70-77), and fetchAllJournalEntries (:85-92) call db.records(matching:resultsLimit: 2000) and consume only matchResults. CKDatabase.records(matching:) pages server-side (typically ~100-200 records per response) and returns a queryCursor that must be followed via records(continuingMatchFrom:); the cursor is never read. resultsLimit: 2000 does not force a single 2000-record response. Any record beyond page one never reaches the merging device. Compounding with fullSync :114-116: records past page one look 'missing from remote' on the device that owns them 

### [MEDIUM] `SipCheck/SipCheckApp.swift:145`
**Follow-up notification tap silently does nothing when the scan record can't be found, and remote tombstone sync never cancels the pending local notification**

- **Status:** 🔵 OPEN — recommend E2E track
- **Field scenario:** User scans a beer at Trader Joe's on the 15 Pro (48h follow-up scheduled), later deletes the scan from the 14 Pro; the tombstone syncs back. Two days later the push still fires on the 15 Pro — 'Did you try Watt Strike?' — the user taps it and the app opens to whatever tab was last active with no follow-up sheet, no error. The 'did you actually like it' answer that should have fed TasteScorer is lost.
- **Detail:** RootView's handler does `if let scan = scanStore.scans.first(where: { $0.id == scanID })` with no else branch — if the lookup misses, pendingFollowUpScanID is cleared (:150) and the tap is swallowed. Lookups miss in real cases: (a) the scan was deleted on the OTHER device — ScanStore.applyRemoteScans (ScanStore.swift:84-99) moves remotely-tombstoned scans out of `scans` but never calls NotificationService.cancelFollowUp (only the local tombstone() path at ScanStore.swift:73 cancels), so this device keeps a pending notification pointing at a record it can no longer resolve; (b) scans.json faile

### [MEDIUM] `SipCheck/Views/AddBeerView.swift:124`
**Save button stays enabled during the async save, so a double-tap creates duplicate Drink + JournalEntry records that skew the taste profile and sync to CloudKit**

- **Status:** ✅ FIXED — AddBeerView gates Save with `isSaving`; persistence and dismissal execute once (2026-07-15)
- **Field scenario:** Trader Joe's aisle, spouse waiting: user taps Save, the sheet doesn't dismiss instantly because the label photo is compressing, they tap Save again. Two identical 'Hazy Little Thing' entries appear in the journal and drinks list, the style is double-weighted in TasteScorer, and deleting one by hand still leaves the duplicate on the other device until sync catches up.
- **Detail:** saveBeer() (:177-231) launches a Task that first awaits drinkStore.savePhoto (ImageCompressor at 1024px — hundreds of ms for a 12MP camera photo) before inserting the drink and dismissing. There is no isSaving flag; the toolbar Save button (:123-129) is only gated on `canSave` (non-empty name), and the form stays fully interactive. Each tap generates a fresh `UUID()` (:178), so a second tap produces a second Drink and a second mirrored JournalEntry with distinct IDs — de-duplication by ID can never catch them, and both upload to CloudKit (DrinkStore.swift:46) so the duplicates propagate to the

### [LOW] `SipCheck/Services/ScanStore.swift:109`
**Every scan synchronously re-encodes and rewrites the entire scan history (including never-pruned tombstones) on the main thread, with unbounded growth**

- **Status:** ⚪ OPEN — perf (SPEED_PLAN Later)
- **Field scenario:** After a few months of daily use (hundreds of scans, plus every 'deleted' scan still encoded as a tombstone), each thumbs-up at the store adds a >100ms main-thread hitch right as the verdict card animates in; 'Delete all scans' makes the file no smaller and the stall permanent. On the 14 Pro the spinner-to-card transition visibly stutters.
- **Detail:** finalizeScan runs on MainActor (CheckTabView.swift:446-451) and calls scanStore.addScan -> saveScans (ScanStore.swift:37-45, 107-114), which JSONEncodes `scans + tombstones` and writes the whole file with Data.write, all synchronously on the main thread — once per scan, plus again on every updateScan ('Save for later', follow-up responses) and on applyRemoteScans at launch (line 98). Nothing ever caps or prunes the array: deleteScan/deleteAllScans (lines 57-63) only convert records to tombstones (lines 67-81) which are kept and re-encoded forever ('kept only so the deletion can sync' — but the

### [LOW] `SipCheck/Views/Tabs/CheckTabView.swift:200`
**After a failed scan the retry spinner is frozen (repeatForever animation no-ops because spinnerDegrees is still 360), and startPhraseCycling can leak a second live Timer that double-advances the phrase index.**

- **Status:** ✅ FIXED — verdict-first refactor (`4cc5cf4`)
- **Field scenario:** First scan at Trader Joe's fails on flaky network; user immediately retries; the progress ring sits motionless for the whole 15-60s network wait — the app looks hard-hung, user force-quits mid-scan. Meanwhile the status phrases flicker at double speed from the leaked timer.
- **Detail:** The error paths (:344-349, :369-374) set isScanning=false but never reset spinnerDegrees/scanningPhraseIndex — only resetScanState (:466-467), reachable solely from a successful verdict card, does. On the next scan attempt scanningView re-enters and .onAppear (:200-205) runs `withAnimation(.repeatForever) { spinnerDegrees = 360 }` with the value already 360: no state change, no animation, static arc for the entire (potentially 60s) scan. Separately, startPhraseCycling (:219-229) schedules a new repeating Timer on every appearance; the old timer only self-invalidates on its next 2.2s tick if is

### [LOW] `SipCheck/Services/BeerResolver.swift:157`
**BundledCatalog swallows any bundle/decode failure with try? and silently ships an empty catalog with zero diagnostics.**

- **Status:** ⚪ OPEN (diag) — empty-catalog failure should log loudly
- **Field scenario:** A future commit renames a JSON key or the resource gets dropped from the Resources build phase; the app builds green in CI, every field scan silently loses the catalog, and the only symptom is 'the scanner got dumber' — exactly the class of failure that burned this release, with no log line to triage it.
- **Detail:** The init (BeerResolver.swift:155-163) does `if let url = bundle.url(...), let data = try? Data(...), let decoded = try? JSONDecoder().decode(...)` and otherwise sets entries = []. There is no os_log, assert, or ScanLog event when the 349KB catalog.json fails to load or decode, so the entire offline tier can vanish without a trace — and ScanLog would just show src=unresolved on every scan. (Verified today's catalog.json does decode against Entry — 2,410 rows, keys name/brewery/style/coarse/abv with the extra 'state' key ignored — so this is a latent trap, not currently firing. Note the load als

### [LOW] `SipCheck/Services/BeerResolver.swift:155`
**BundledCatalog re-normalizes all 2,410 entry names on every fuzzy lookup and decodes the 350KB catalog synchronously on first access**

- **Status:** 🟡 PARTIAL — per-lookup renormalization fixed (precomputed indexes); first-use decode still lazy+sync — launch prewarm is in SPEED_PLAN
- **Field scenario:** First scan of the session pays JSON-decode plus a full normalize-the-catalog pass right at the moment the user wants the instant verdict; on the A16 iPhone 14 Pro this adds avoidable tens-to-hundreds of ms and memory churn per scan, and if the resource ever fails to copy into a build, every scan quietly reports source=unresolved with nothing in the log.
- **Detail:** The init builds exactIndex of normalized names (lines 166-169) but throws the normalized strings away; the fuzzy path (lines 192-197) calls BundledCatalog.normalize($0.name) — lowercased + trim + replacingOccurrences, three string allocations — for every one of the 2,410 entries on every lookup that misses exact (which is nearly all OCR input, since normalize keeps newlines). That's ~7,000+ transient string allocations plus 2,410 substring scans against a potentially multi-hundred-character OCR blob, per scan. `static let shared` (line 139) also decodes the 350KB / 2,410-row JSON synchronously

### [LOW] `SipCheck/Models/TasteProfile.swift:35`
**averageABV (the 'ideal ABV' anchor for scoring and tiebreaks) is computed over ALL drinks including disliked ones.**

- **Status:** ⚪ OPEN — scorer tuning
- **Field scenario:** A user who mostly drinks 5% lagers but logged several disliked 10% imperial stouts gets an ideal ABV around 7 — the app then nudges them toward stronger beers they've consistently rejected and penalizes their actual 4.8% favorites in menu tiebreaks.
- **Detail:** The abvSum/abvCount accumulation (TasteProfile.swift:35-38) runs for every drink regardless of rating, so beers the user explicitly disliked pull the 'ideal' toward themselves. TasteScorer uses this as idealABV for both the ±3.0 tolerance bonus/penalty (TasteScorer.swift:86-98) and the ranking tiebreak (lines 137-142). Liked-only (or like-weighted) ABV would reflect actual preference.

### [LOW] `SipCheck/Views/Tabs/CheckTabView.swift:316`
**First-time camera permission denial is a silent dead end: the .notDetermined branch does nothing when the user taps 'Don't Allow'**

- **Status:** ✅ FIXED — verdict-first refactor (`4cc5cf4`)
- **Field scenario:** New user in the aisle taps 'Scan Label', reflexively hits 'Don't Allow' on the iOS prompt, and the screen just sits there — the button appears broken. Only if they tap Scan Label again do they get the Settings alert.
- **Detail:** requestCameraAndScan's .notDetermined branch only handles granted == true (CheckTabView.swift:315-323); on denial the closure falls through with no alert, no banner, no state change. The 'Camera Access Required' alert with the Settings deep link (lines 108-117) exists but is only reached on a SUBSEQUENT tap once status is .denied (line 324-325). The @unknown default (line 326-327) is also a silent no-op.

### [LOW] `SipCheck/Services/BeerResolver.swift:16`
**The on-device LLM tier of the resolver fusion (and all async enrichment) is not implemented — ResolvedBeer.Source.onDeviceLLM/.online are unreachable dead code on every device**

- **Status:** ⚪ OPEN — next phase — Foundation Models tier = the device spike
- **Field scenario:** On the Foundation-Models-capable iPhone 15 Pro, a popular beer missing from the catalog ('Josephsbrau PLZNR') that the on-device LLM would trivially know still resolves as 'unresolved' and gets the erroneous SKIP IT — the promised free on-device knowledge tier silently does not exist in the shipped code.
- **Detail:** No file imports FoundationModels or references any LanguageModel API (repo-wide grep: 0 hits), no AsyncBeerCatalog conformer exists, and BeerResolver.shouldEnrich/enrich (BeerResolver.swift:110-128) have no callers. So fusion steps 3 and 4 of the locked architecture exist only as enum cases (BeerResolver.swift:16-17). This means the iPhone 15 Pro gets no better resolution than the iPhone 14 Pro — both are catalog+keyword only — and the 'refine asynchronously' half of 'show now, refine later' never happens; only the blocking network calls in ScanningPipeline (finding 1) exist.

### [LOW] `SipCheck/Views/Tabs/CheckTabView.swift:416`
**Scan telemetry misattributes the style source and records network latency as scan latency, undermining the field-triage purpose of ScanLog.**

- **Status:** ✅ FIXED — verdict-first refactor (`4cc5cf4`)
- **Field scenario:** Triaging 'this beer said SKIP at Trader Joe's': the log claims src=unresolved with a valid style and 14,800ms latency, sending the owner hunting in the catalog matcher when the style really came from Gemini and the latency was a network timeout — the exact 14 Pro vs 15 Pro triangulation the log was built for is not possible because the availability flag was never recorded.
- **Detail:** buildScan logs source: resolved.source.rawValue (CheckTabView.swift:416), but resolved comes only from the catalog/keyword resolve; when the style actually came from the network (fusedStyle = beerInfo.style ?? resolved.style, line 392) the event says 'unresolved' or 'catalog' while style is populated from Gemini. latencyMs is result.latencyMs — the network pipeline time — not verdict-on-screen time. Additionally, contrary to CLAUDE.md ('ScanLog stamps... whether Foundation Models is available'), ScanEvent has no Foundation Models availability field (ScanLog.swift:8-28), and no Foundation Model

### [LOW] `SipCheck/Views/Tabs/CheckTabView.swift:266`
**Typed-name fallback: the text field is not auto-focused and Return does not submit, adding taps to the rescue path.**

- **Status:** ✅ FIXED — verdict-first refactor (`4cc5cf4`)
- **Field scenario:** Camera misread the stylized label twice; user opens 'Enter beer name', has to tap the empty field to summon the keyboard, types 'lagunitas ipa', hits Return — nothing happens — then hunts for the submit button.
- **Detail:** textEntrySheet's TextField (CheckTabView.swift:266-268) has no @FocusState/.focused to raise the keyboard on presentation and no .onSubmit/.submitLabel(.go) to submit from the keyboard; the user must tap the field, type, then reach up past the keyboard to tap 'Check This Beer' (CheckTabView.swift:272-290). This is the fallback used precisely when the camera already failed, i.e. when the user is most frustrated.

### [LOW] `SipCheck/Services/BeerMatcher.swift:58`
**BeerMatcher Levenshtein allocates a full (m+1)x(n+1) matrix per comparison and is fed unbounded OCR blobs as the query**

- **Status:** ⚪ OPEN (low)
- **Field scenario:** User with a 300-beer history checks a label offline via CheckBeerView; the fuzzy pass allocates ~300 matrices of 500x~25 Ints, causing a perceptible pause and memory churn before the (network-gated) result screen.
- **Detail:** levenshteinDistance builds a complete 2D [[Int]] matrix (line 58) instead of two rolling rows — O(m*n) memory and nested-array indexing per drink compared. findMatch runs it over every drink in history (lines 22-27) after exact/contains fail. It is invoked from CheckBeerView.processImage (CheckBeerView.swift:315) with beerName from the scan pipeline, which offline is the FULL multi-line OCR text (ScanningPipeline.swift:96) — so m can be 500+ chars against every drink name, i.e. tens of thousands of Int cells allocated per drink, inside a Task that (like CheckTabView's) reads drinkStore.drinks 

### [LOW] `SipCheck/Views/AgeGateView.swift:71`
**Accidentally tapping 'I'm Under 21' puts the app into a dead-end locked screen with no undo — only force-quitting resets it (and because the lockout is non-persistent @State, it is also trivially bypassed on relaunch).**

- **Status:** 🔵 OPEN — recommend E2E track — accidental under-21 tap is a dead end
- **Field scenario:** Owner replays onboarding, fat-fingers 'I'm Under 21' in the aisle, and the app becomes a brick with no visible recovery; they have to know to force-kill SipCheck from the app switcher to get back to scanning.
- **Detail:** The 'I'm Under 21' button sets isLockedOut = true (AgeGateView.swift:69-72), replacing all buttons with a static 'SipCheck is only available for adults 21+' message (:37-49) and no back/undo control. isLockedOut is plain @State (:5), not persisted, so killing and relaunching the app shows the age gate again — meaning the lockout is simultaneously an in-session dead end for a mis-tap and a non-functional gate for an actual minor. Note this screen is also reachable by adult users mid-use via Settings 'Replay Onboarding' which resets hasConfirmedAge (SettingsTabView.swift:66).

### [LOW] `SipCheck/Services/GeminiService.swift:84`
**getVerdictAndExplanation asks the paid remote LLM to decide TRY_IT/SKIP_IT on every scan, yet every consumer discards ScanResult.verdict — pure critical-path latency and API cost**

- **Status:** 🟡 SUPERSEDED — scan flow no longer requests LLM verdicts; legacy method kept for old callers
- **Field scenario:** Waiter approaching at a restaurant: after the extract round trip, the app spends another 15-30s on flaky LTE asking Gemini then OpenAI for a TRY_IT/SKIP_IT that the card never shows, doubling the in-aisle wait and the per-scan API bill for nothing.
- **Detail:** GeminiService.getVerdictAndExplanation (GeminiService.swift:84-144) and its OpenAI twin (OpenAIService.swift:143-202) prompt the remote LLM to choose the verdict itself, injecting TastePreferences.current.promptSummary (GeminiService.swift:93, OpenAIService.swift:152). ScanningPipeline runs this leg on every scan (ScanningPipeline.swift:43, 77, 98 via getVerdictAndExplanation at 128-137, Gemini then OpenAI sequentially). But no consumer uses the verdict: CheckTabView.buildScan recomputes it on-device via TasteScorer.assess and ignores result.verdict (CheckTabView.swift:396-428), CheckBeerView.

### [LOW] `SipCheck/Services/GeminiService.swift:154`
**Gemini API key transmitted as a URL query parameter instead of a header**

- **Status:** ⚪ ACCEPTED — query-param key is the Gemini API convention
- **Field scenario:** Corporate or coffee-shop network middleboxes and any HTTPS-terminating proxy (or a future debug log of failing request URLs) capture the production Gemini key in plaintext URLs, enabling quota theft billed to the app's account.
- **Detail:** makeRequest appends the key via `URLQueryItem(name: "key", value: apiKey)` (GeminiService.swift:153-155). Query strings are recorded in proxy logs, server access logs, analytics, and OS-level network diagnostics, unlike the Authorization/x-goog-api-key header pattern OpenAIService uses (OpenAIService.swift:297). Google's API supports the `x-goog-api-key` header for exactly this reason. Additionally, GeminiError.apiError surfaces raw server messages to the UI via errorDescription (GeminiService.swift:19-20 → CheckTabView.swift:372), which can echo request details.

### [LOW] `SipCheck/Views/Tabs/CheckTabView.swift:72`
**CheckTabView's FollowUpView sheet is unreachable dead code, and its scan resolution falls back to 'most recent scan' rather than the follow-up's scan**

- **Status:** ⚪ OPEN (low) — dead FollowUp sheet in CheckTabView
- **Field scenario:** No user-visible failure today because the sheet never presents, but the next developer wiring 'return to a scan' through CheckTabView inherits an id-mismatch: user answers a follow-up about Two Hearted and the app instead clears the want-to-try flag on last night's Pliny scan.
- **Detail:** `showingFollowUp` (:23) is only ever assigned false (:77, :82, :85) — nothing in CheckTabView sets it true, so the sheet at :72-94 can never present (the real notification flow lives in RootView). Worse, its content resolves the scan as `currentScan ?? scanStore.scans.first` (:73 and again in onNotGoing at :86), i.e. if it were ever wired up (or copied as a template, which its duplication from RootView suggests already happened once), a follow-up about beer A would display and mutate whichever beer was scanned most recently. The onNotGoing at :86-90 would clear wantToTry on the wrong scan.

### [LOW] `SipCheck/Services/DrinkStore.swift:118`
**Every drink/journal mutation re-encodes and rewrites the full array synchronously on the main thread, and photo loads do synchronous disk I/O inside view body**

- **Status:** 🟡 PARTIAL — photo reads now use `loadPhotoAsync`; full-array JSON writes remain synchronous and are still a later performance item (2026-07-15)
- **Field scenario:** A user with a few hundred logged beers taps Save on AddBeerView while the verdict/journal UI is up: two full-file JSON encodes+writes land on the main thread in one frame, producing a visible hitch right at the moment the CLAUDE.md 'fast in-the-moment' requirement cares about most; opening a beer with a photo stutters on first render.
- **Detail:** saveDrinks() (:115-123) encodes drinks + tombstones and writes to disk inline; all callers run on the main actor (addDrink from AddBeerView.swift:218-229 inside MainActor.run, and from the notification lovedIt handler at SipCheckApp.swift:173). JournalStore.saveEntries (JournalStore.swift:105-112) is identical, and AddBeerView performs both writes back-to-back in one main-actor block (:219-220), plus a third for the scan link (:227). Cost grows linearly with history size, on every single log. Writes ARE atomic (.atomic at :119), so this is jank, not corruption risk. Also loadPhoto (:165-175) d
