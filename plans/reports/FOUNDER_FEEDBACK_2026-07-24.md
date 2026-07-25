# Founder Video Feedback Follow-up — 2026-07-24

## Inputs

- `RPReplay_Final1784936563.MP4`: make both preference questions easier to scan with larger
  horizontal beer choices, real product art, Beers/Styles switching, and search.
- `RPReplay_Final1784936774.MP4`: protect recommendation quality with a small set of realistic
  taste archetypes and positive/negative cases instead of optimizing a global verdict ratio.
- `RPReplay_Final1784936878.MP4`: do not recommend from the first unstable OCR guess and then
  reverse the visible recommendation as identity resolution improves.

## Product decisions

### Preference onboarding

Both "go-to" and "stay-away" now use the same searchable two-column picker. A native segmented
control switches between named beers and styles. Larger landscape tiles use recognizable product
or brand art and keep stable sizing across selection and search states. This removes the nested
horizontal carousel that could compete with the onboarding page swipe while preserving both the
concrete-brand input and the hard category-level avoid signal described in `FOUNDER_TASTE.md`.

### Recommendation regression eval

`RecommendationArchetypeEvalTests` defines 14 named candidate oracles across six behavioral modes:
lager loyalist, cautious dark-malt explorer, hop specialist, sour specialist, broad explorer with
an explicit boundary, and sparse-history drinker. Every candidate asserts its own verdict and an
evidence-bearing reason. The suite deliberately has no aggregate TRY/SKIP/YOUR CALL quota: a target
distribution could pass while an individual persona receives the wrong answer. Explicit stay-away
preferences are separately verified to beat even an exact prior like.

### Live-scan settlement

Live OCR now needs 1.2 seconds of unchanged text before capture; any transcript change restarts the
bounded local timer. A weak camera-only name guess without directly printed style evidence settles
to an honest `YOUR CALL` and withholds guessed metadata. Directly printed style can still produce an
immediate offline TRY/SKIP, and typed names, strong catalog matches, and menu winners retain their
existing paths. Later enrichment may improve displayed facts, but it cannot reverse the already
visible verdict or rationale for a provisional camera identity. A typed styleless name may still
gain a specific verdict once on-device facts resolve it.

## Beer artwork provenance

These marks and product images identify the selectable beers; all associated trademarks remain the
property of their owners. Every file is sourced from Wikimedia Commons or a source-linked Flickr
record under a public-domain or commercial-use Creative Commons declaration. Public-domain and
simple-logo classifications do not waive trademark rights. Required authors, source links, license links,
and modification notices are exposed in Settings > About > Beer artwork credits. CC BY-SA
adaptations remain under their listed licenses.

| Beer | Source | Rights note |
|---|---|---|
| Modelo | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Modelo_especial.jpg) | Public-domain text logo; resized |
| Corona | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Corona_Extra_text_logo.svg) | Public-domain/simple logo; trademark remains |
| Heineken | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Heineken_Logo.svg) | Public-domain/simple logo; trademark remains |
| Blue Moon | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Blue_Moon_Beer.jpg) | Aneil Lutchman; CC BY-SA 2.0; resized |
| Sam Adams | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Samuel_Adams_logo.svg) | Public-domain/simple logo; trademark remains |
| Guinness | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Guinness-Logo-1.png) | Unmodified; CC BY-SA 4.0; credit Evanodunaigh and license link exposed in Settings > About |
| Sierra Nevada | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Sierra_Nevada_Pale_Ale.jpg) | SteveR; CC BY 2.0; resized |
| Lagunitas | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Lagunitas-logo-2017.png) | Public-domain/simple logo; trademark remains |
| Two Hearted Ale | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Bell%27s_Two_Hearted_Ale.jpg) | edwin; CC BY 2.0; resized |
| Coors Light | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Coors_Light_logo.svg) | Public-domain/simple logo; trademark remains |
| Bud Light | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Bud_Light_-_June_2024_-_Sarah_Stierch.jpg) | Sarah Stierch; CC BY 4.0; resized |
| Stella Artois | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Stella_Artois_current_logo_2015.png) | Stella Artois UK / AB InBev; CC BY 3.0; unmodified |
| Allagash White | [Flickr](https://www.flickr.com/photos/89562459@N03/36639521043) | Allagash Brewing; CC BY 2.0; resized |
| Dogfish Head | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Happy_Saturday_(238576229)_(cropped).jpeg) | Terry Lucas; CC BY 3.0; resized |
| Stone IPA | [Flickr](https://www.flickr.com/photos/98178986@N00/2537689794) | joefoodie; CC BY 2.0; resized |
| Goose Island | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Goose_Island_Beer_Co._logo_(31478241163).jpg) | Ruth Hartnup; CC BY 2.0; resized |

## Verification

- Asset-catalog JSON validation: passed.
- Python baseline-capture syntax validation: passed.
- Unsigned generic simulator Debug build, including asset compilation: passed.
- Unsigned generic simulator `build-for-testing` for app, unit tests, and UI tests: passed.
- Local XCTest execution and screenshots: blocked before app install by a stalled CoreSimulator
  install coordinator; no assertion or compilation failure was observed. Branch CI is the clean-runner
  source of truth for execution and visual artifacts. The branch simulator workflow now runs both
  `SipCheckTests` and `SipCheckUITests` so the new recommendation oracles are an enforced gate.
