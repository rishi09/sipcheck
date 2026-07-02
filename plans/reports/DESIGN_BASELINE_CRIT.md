## Baseline verdict (3 sentences, honest)

The bones are good — the dark ramp is correct, teal is used with restraint, and the copy voice ("worth your money," "Matches your love of pale ale") is genuinely the app's — but the hero screen is the worst screen: the verdict arrives third, below a 320pt gray placeholder that looks like a failed image load. Two of nine renders have interactive content physically buried under the floating tab bar, and the app's only "imagery" is the same gray/teal mug glyph stamped on four screens, which makes a beer app read like a generic AI-scaffolded scanner template. Fixable fast, because most of it collapses into three primitives: a verdict-first card, an SRM color helper, and a real bottom-inset contract.

## Steering notes (ranked, max 15, each 1-2 sentences, screen-tagged)

1. **[Verdict]** Invert the card: verdict word at top, ~48pt heavy rounded, symbol + semantic surface; the gray mug + gray name block occupying the top half dies. Header becomes a ≤120pt SRM two-stop gradient, beer name printed once, history capsule under the name, "refining…" demoted below the "because" line.
2. **[Global]** Give the floating tab bar a contract: ~100pt bottom content inset on every scrollable screen plus a bg→clear scrim under the bar. Verdict action buttons and Profile's recent scans are currently sliced/unreachable behind it — shipping blocker, not polish.
3. **[Global]** Build one `styleSRMColor()` helper and spend it everywhere the mug currently is: journal row chips, detail-sheet hero, verdict header, Top Styles bars. It's the only element that could *only* belong to a beer app; a stout and a light lager must look different.
4. **[Global]** One verdict-badge component: colored surface + dark text + SF Symbol, used identically on verdict screen and profile chips. Profile's white-on-gold YOUR CALL is 1.7:1 — the single worst pixel in the app; fix today.
5. **[Global]** Gold is doing double duty: `#F1C40F` is both star-rating and verdict amber, and stars vs thumbs/TRY-SKIP are two competing rating languages. Split the tokens (verdict amber warmer, ~#E8A317) and pick one rating vocabulary app-wide.
6. **[Enter Beer]** Kill the pure-#000 text field — inputs sit *lighter* than the sheet; reuse the `#2A2A2E` well the notes/search fields already have, anchor the CTA just above the keyboard, and surface live `BeerMatcher` catalog suggestions as you type. Same fix for all sheets: `#1A1A1E`-on-`#1A1A1E` sheets don't read as sheets — elevated token or material.
7. **[Verdict]** Rebuild the history pill: it's the highest-trust line in the app rendered as its sloppiest element — brightest surface on screen, raw 👍 emoji, truncated copy. Dark elevated chip, SF thumb symbol, full sentence, placed under the name block.
8. **[Verdict]** The olive band behind the status bar is amber tint escaping its bounds and it reads as a bug. Either commit to a full verdict-tinted atmosphere from the top or kill the bleed — the 44pt half-measure is the worst of both.
9. **[Global]** Collapse the type scale: sizes cluster at 18–28pt so nothing outranks anything. Two hero sizes (verdict 48, stat numerals 44), Dynamic Type styles for the rest, section headers drop to caption — "Tried · 3 beers" is metadata, not a second title.
10. **[Global]** Three reds within two screens (`#BE4236`, `#D7483A`, `#E74C3C`) — collapse to one `verdictSkip` token at fill/text/border strengths, and lighten the "Not For Me" chip text, which currently fails contrast at ~3.3:1.
11. **[Profile]** Teal fills are for tappable things only: the Explorer badge outshouts the scan CTA (invert to dark fill + teal text, and lose the leaf icon — it's a wellness-template default on a beer app), and the Top Styles bars are the heaviest teal mass in the app.
12. **[Profile]** The Top Styles chart lies — all values 33%, bars filled ~85%. Bar length encodes the value or the bars become count chips; either way, SRM colors, labels leading.
13. **[Journal]** Unglue "Name - Style" titles — style is the load-bearing datum and it's the part being truncated. Name on line 1, style + rating on a shared metadata baseline; fix "1 beers" while in there.
14. **[Detail]** The destructive action is the sheet's visual hero — Delete is the only saturated full-width button while Save sits disabled in the corner. Delete goes to the bottom as plain red text, and add the missing loop-closer: "We said TRY IT — you gave it ★★★★."
15. **[Check]** The gray camera glyph reads as a disabled state and the alternating gray-glyph/headline/button empty state is pure template. Tint or replace it with a beer-native idle animation (viewfinder brackets + glass filling amber) that doubles as scan progress, and give the Scan CTA the app's one glow — subtle gradient/glass + soft teal shadow.

## Do-not-lose list (what the current design gets right)

- The copy voice: "Snap a label. We'll tell you if it's worth your money." / "Matches your love of pale ale." — bar-buddy, not chatbot.
- The floating pill tab bar with the scan-frame Check icon (once the inset contract exists).
- Non-blocking "refining details…" — verdict now, enrich async. Keep the pattern, just move the row.
- The dark ramp: `#1A1A1E` base / `#2A2A2E` elevated / off-white `#F5F3F0` heroes, no pure-black surfaces (except the one text field). Formalize as tokens.
- Teal restraint — one brand hue, used sparingly. The Check tab's two-hue palette is the reference screen.
- Loved / OK / Not For Me filter language (in-voice, not "4+ stars") and verdict chips on Recent Scans.
- The `#2A2A2E` input-well treatment on notes/search fields — it's the correct component; propagate it.
- Profile stat cards: elevated gray + heavy off-white numerals — the template for all elevation.
- The history capsule *content* ("You've had this one") — highest-trust line in the app; only its rendering is wrong.

## Slop watchlist (yes/no, answerable from a screenshot)

1. Is any gray SF Symbol (mug, camera) standing in as content imagery anywhere?
2. Does the identical glyph/avatar appear as the hero on more than one screen?
3. On the verdict card, is the verdict word the first thing you read at arm's length, above the fold, in under 2 seconds?
4. Is the beer name printed twice on any screen?
5. Is any interactive or informational element clipped by or ghosting behind the floating tab bar?
6. Is white text sitting on gold/amber anywhere?
7. Is the same yellow used for both star ratings and a verdict badge?
8. Is any raw emoji (👍) rendered next to semantic color instead of a tinted SF Symbol?
9. Is any fill pure `#000000`?
10. Is teal used on anything that isn't tappable (badges, data bars, status labels)?
11. Do the Top Styles bar lengths actually encode their printed values?
12. Does any count string read "1 beers" (or similar plural seam)?
13. Is a destructive button more visually prominent than the primary/save action on its screen?
14. Do sheets visibly separate from the base background at rest (not just during the slide)?
15. Are there more than two hero type sizes, or do two same-weight "titles" compete on one screen?
16. Is there any tint band bleeding into the status bar that isn't a deliberate full-height atmosphere?