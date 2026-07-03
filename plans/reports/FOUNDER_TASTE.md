# Founder Design Taste Profile — FINAL v2
Source: founder video feedback on onboarding, 2026-07-03 (timestamped transcript), refined against
external evidence (see plans/reports/DESIGN_INSPIRATION.md + fresh negative-preference/cold-start/copy
research, 2026-07-03). Screens referenced = SipCheck/Views/OnboardingView.swift pages 1–5.
This is revealed taste, not a ticket list. Run every user-facing surface through the litmus questions.
§4 bounds what this doc may be cited for.

## 1. Principles (ranked by confidence)

### P1. Outcome-punchline over mechanism — HIGH
One punchline, and it's what the user gets: "buy better beer."
- Evidence: [4.1s] "the main point is that you are going to buy better beer"; [11.2s] "However that
  happens is kind of irrelevant." External: category leader Vivino leads every surface with the same
  formula — "Buy the Right Wine," 4-word imperative outcome, scanning demoted to supporting copy.
- Rejects: feature-first taglines; explaining how before why; any headline that dies when you delete
  the mechanism clause.
- Litmus: delete every mechanism word. Does the promise survive intact?
- When in doubt: write the Vivino form — imperative verb + outcome, ≤5 words — then stop.

P1a corollary: mechanism-agnosticism — HIGH. The stack is not a user-facing feature. If swapping the
entire pipeline would force the screen to change, the screen is selling plumbing. Scope: communication
only — fast/free/offline stay locked engineering constraints, just never narrated. "Free"/"no account"
are outcome-adjacent (safe); "on-device" is mechanism (store page at most, never in-app).
- When in doubt: describe the moment ("know in the aisle"), never the machinery ("on-device AI").

### P2. Concrete behavioral recall over taxonomy — HIGH
Elicitation triggers memories of actual purchases, never self-classification against beer vocabulary.
- Evidence: [42.0s] "what's your go-to, what's in your fridge"; [49.4s] "the point is to trigger…
  what do you buy without any hesitation." External: survey methodology — recall accuracy is highest
  for recent/frequent/distinctive behavior ("what's in your fridge" is all three); attitudinal
  self-classification carries known response bias and mispredicts behavior (Sage, NN/g). Spotify asks
  named artists, never genre checkboxes, and measures −13.8% recommendation quality without that signal.
- Rejects: style-tile grids, flavor sliders, IBU/hazy jargon, any question requiring beer vocabulary.
- Phrasing rule (research-added): present/past indicative only — "What's in your fridge right now?",
  never conditional ("What would you enjoy?").
- Litmus: can a casual drinker answer in two seconds with a brand name, zero vocabulary?
- When in doubt: ask about a purchase that already happened; brands are the input language, styles
  may only be the stored output (Stitch Fix rule: concrete instances elicit, categories store).

### P3. Show the magic moment, don't describe it — HIGH
The payoff depicted happening in its real context, four beats: person + phone raised + beer in a
grocery aisle + instant thumbs. A depiction missing a beat misses the spec.
- Evidence: [17.8s] full storyboard, verbatim. Converges with DESIGN_BASELINE_CRIT slop-watchlist #1
  (no SF Symbol as content imagery) and ADA winners' result-in-context grammar (CapWords).
- Rejects: icon+text feature slides; the loop described in words where it could be demonstrated.
- Constraint: depicted flow must not overpromise — shipping scan is shutter-based, no live-highlight UI.
- Litmus: is the payoff visible in a recognizable real-world scene on this screen, or merely claimed?
- When in doubt: composite the real verdict badge into the real scene; never illustrate abstractly.

### P4. Negative preference is first-class, hard, and category-level — HIGH (hardened by research)
"Never" gets its own question with equal standing, and the answer is a hard constraint, not a weight.
- Evidence: [61.2s] "what are you always going to stay away from?"; [64.4s] "a Guinness or a stout of
  any kind" — brand entry generalizing to style. External hardening: (a) Netflix declined a
  two-thumbs-down because users rarely volunteer dislikes in-product → onboarding is the ONE moment
  to capture negatives; weight avoid-seeds at least as strongly as love-seeds. (b) Mozilla/YouTube
  20k-user study: item-level dislikes stop 12% of unwanted recs, category/source-level blocks stop
  43% → store the avoid as the STYLE ("stouts"), not the item ("Guinness"). (c) Hinge dealbreakers:
  same UI, binary hard-filter tier, framed as self-knowledge not negativity. (d) Mozilla: unhonored
  negative feedback collapses trust in the whole system — the avoid must visibly bind in the verdict.
- Rejects: likes-only seeding; dislikes as 1-star ratings; avoid signal softened to a mid-score.
- Litmus: does the flow ask "what do you always avoid?" as directly as "what do you love?" — and does
  a scanned avoided-style beer get an unambiguous 👎 with the user's own words cited?
- When in doubt: hard filter, style-level, visibly honored, service-framed ("so we never waste your money").

### P5. Poles over midpoints — HIGH
Seed from the unconditional extremes only: always-buy and always-avoid.
- Evidence: [49.4s] "without any hesitation… at all times of year"; [61.2s] "always." External: quiz
  economics — every extra field costs 3–5% completion; two questions already yield strong
  segmentation; ≤90s total. His two pole questions are a near-optimal quiz by the data.
- Rejects: rating scales at cold-start; situational qualifiers; graded dislikes; a third "nuance"
  question; "how adventurous?" as a required gate.
- Litmus: does this question capture an always or a never? He asked only for always and never.
- When in doubt: cut the question. The amber middle accrues from logging, not interrogation.

### P6. Word economy — one idea per screen — HIGH
- Evidence: [1.5s] his first reaction was a word count. External: top onboarding flows carry one
  emotional hook per screen; type-scale rule = copy rule (one big element → one idea).
- Litmus: would the founder cut this word? If the headline says it, the body is dead weight.
- When in doubt: delete the body line entirely; restore only what the headline can't carry.

### P7. Instant, binary, glanceable payoff — MEDIUM-HIGH
- Evidence: [17.8s] "immediately seeing a thumbs up, thumbs down." External: Netflix stars→thumbs
  ~doubled rating engagement — binary is lower-friction AND less noisy.
- Rejects: spinners/reveal sequences in the hero moment; numeric scores or percentages as first read.
- Litmus: is the answer a binary glyph seen the instant you look, or something read/waited for?
- When in doubt: thumbs first, everything else behind a tap; numbers never above the fold.

### P8. Personalization is THE differentiator — MEDIUM
Never "this beer is good"; always "YOU will like this," warranted by the user's own palate/history.
The one mechanism-adjacent idea he voices — it survives P1 because it's the outcome's warrant.
- Evidence: [17.8s] "that they are going to like it based on their palate and preferences."
  External contrast is the moat: Vivino's "right" is crowd-defined; SipCheck's "better" is
  palate-defined — that contrast IS the permitted body line. No crowd ratings, ever.
- Litmus: does this line say the beer is good, or that YOU will like it? Only the second is on-taste.
- When in doubt: cite the user's own evidence ("you told us no stouts", "like your last 4 thumbs-ups");
  if the taste library is popularity-seeded (skip path), say so honestly.

### P9. Triage incrementalism — MEDIUM
"Fine for now, keep it" [39.5s]: don't churn unflagged surfaces; don't read "keep" as permanent.
- Litmus: was it flagged? If not — functional fix allowed, aesthetic churn isn't.
- When in doubt: spend effort surgically on flagged/key moments (Denim pattern), leave the rest.

## 2. Calibration — reading this founder
1. Hedged delivery, firm asks: "I think / probably / kind of" is politeness, not optionality.
2. He dogfoods every prompt on himself ("for me, it's going to be a Guinness"). Reviewer rule: if you
   can't answer a proposed prompt for yourself in one breath with a real brand, he will bounce it.
3. He speaks in numbered priorities and scenes. Pitch back the same way: the scene, then the screen.
4. He reasons from the shopper's moment (aisle, fridge, waiter), never from app structure.

## 3. Decision shortcut (all principles, one line)
State the outcome (P1), show it happening (P3), ask about real purchases at the poles (P2/P4/P5),
answer with a thumbs (P7), warrant it with the user's own taste (P8), in as few words as possible (P6),
touching only flagged surfaces (P9).

## 4. What this profile does NOT license
No signal on: color/palette, typography, motion/haptics, dark mode, journal/detail screens,
gamification, monetization, navigation, engineering architecture. Use DESIGN_INSPIRATION.md /
DESIGN_BASELINE_CRIT.md / DESIGN_CRIT_ROUND2.md for those. Mine future founder reviews into v3.
