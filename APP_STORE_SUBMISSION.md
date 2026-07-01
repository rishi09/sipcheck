# SipCheck — App Store Submission Notes

Drafted content for the App Store Connect listing. Review before submitting.

## Listing copy

- **App name (≤30 chars):** `SipCheck: Beer Scanner` (alts: `SipCheck — Beer Tracker`, `SipCheck: Beer Verdict`)
- **Subtitle (≤30):** `Scan a beer, get the verdict`
- **Promotional text (≤170):** Point your camera at any beer label and get an instant TRY IT, SKIP IT, or YOUR CALL verdict tuned to your taste. Keep a private journal of every pour.
- **Keywords (≤100):** `beer,brew,scanner,label,IPA,craft,tasting,journal,tracker,ale,lager,rating,verdict,notes,pint`
- **Category:** Primary **Food & Drink**, Secondary **Lifestyle**
- **What's New (1.0):** Welcome to SipCheck 1.0 — scan a beer label for an instant verdict, keep a tasting journal, and sync privately to iCloud.

**Description:**

> Ever stare at a wall of beers and have no idea which one you'll actually like? SipCheck reads the label for you. Point your camera at any bottle, can, or tap list, and SipCheck identifies the beer, then gives you a clear verdict: TRY IT, SKIP IT, or YOUR CALL. The recommendation learns from the beers you've rated, so the more you log, the more it sounds like your own taste.
>
> Every scan can become a journal entry. Rate what you drank, jot tasting notes, and snap a photo so you remember the standouts (and the ones to avoid next time). Browse your history any time to see your favorite styles, your go-to ABV range, and how your palate is shifting.
>
> Your beer log stays yours. Everything is stored on your device and synced to your own private iCloud, so it follows you across your iPhone and iPad without an account, a password, or a profile to set up. No ads. No analytics. No selling your data.
>
> SipCheck is built for grown-ups who enjoy good beer and want to remember the good ones. Please drink responsibly, know your limits, and never drink and drive. You must be of legal drinking age to use this app.

## App Privacy questionnaire

Two defensible options:
- **Option A — "Data Not Collected"** (cleanest, technically correct): no backend; CloudKit data lives only in the user's **private** DB (not developer-accessible); label images/text go to OpenAI/Google only to service the real-time scan; no identifiers/analytics/tracking.
- **Option B — conservative:** declare **Photos** + **Other User Content**, both *Not Linked to You* and *Not Used for Tracking*, purpose *App Functionality*.

**Recommendation:** Use **A** *if* you can confirm OpenAI/Google API terms don't retain/train on inputs; otherwise ship **B**. In all cases: **Tracking = No**, **Linked to identity = No**. The user's private CloudKit data does **not** count as "collected."

## Age rating

Answer **"Alcohol, Tobacco, or Drug Use or References" = Frequent/Intense** → yields **17+** (18+ on new scale). All other content categories: None. Unrestricted web access: No. Do **not** enroll in Kids category. Note: comply with App Review Guideline 1.4.3 (frame as tracking/journaling for adults, not encouraging consumption).

## Screenshots

Required sizes: **6.9"** (1320×2868) and **6.5"** (1242×2688). 6 shots each (12 total):
1. Check/scan viewfinder — "Point. Scan. Know in seconds."
2. Verdict card TRY IT — "Honest verdicts: TRY IT, SKIP IT, or YOUR CALL."
3. Verdict card w/ explanation — "AI tasting notes that explain why."
4. Journal — "Your whole beer history, in one journal."
5. Profile/stats — "Track styles, ratings, and trends over time."
6. Onboarding/age gate — "Private by design — synced only to your iCloud."

Capture via Simulator (iPhone 16 Pro Max + iPhone 11 Pro Max); set clean status bar (`simctl status_bar … override --time 9:41`); use realistic seed data; avoid the grey photo placeholder as a hero element; keep all shots dark-mode; composite captions in post.

## Open items
- `AgeGateView` says **21+** while the App Store rating is 17+/18+ (Apple has no 21+ tier). This is fine (you can gate stricter than Apple rates) — just be deliberate/consistent.
- "Seed Sample Data" button is currently visible in release builds for testing — **remove before public submission**.
- Privacy Policy + Terms are hosted at `/docs/privacy/` and `/docs/terms/` — enable GitHub Pages so the URLs resolve.
