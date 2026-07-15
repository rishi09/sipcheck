# U.S. Beer Drinker Behavioral Archetypes

Research date: 2026-07-15

## Product conclusion

SipCheck should model behavioral evidence, not demographic stereotypes. The useful axes are:

1. Explicit always-buy and always-avoid styles.
2. Positive and negative drinking history.
3. Familiarity seeking versus variety seeking.
4. Independent tolerance for sourness, bitterness, roast/body, and alcohol strength.
5. Current occasion or moderation intent.
6. Brand/local loyalty only as a tiebreak after taste fit.

Age and gender may be useful for fairness audits, but should not decide a verdict. A person can also
move between modes by occasion; "moderating tonight" is not necessarily a permanent identity.

## Evidence-backed modes

### 1. Familiarity-first lager loyalist

Mostly repeats American, Mexican, or other crisp lagers, has low brand/style diversity, and does not
seek flavor extremes. Recommend adjacent pilsners, Kolsch, blonde ale, and approachable pale lager.
Do not infer sour, roast, or bitterness tolerance from generic beer consumption.

### 2. Cautious adjacent explorer

Has a narrow base but occasionally tries nearby styles. Move one sensory step at a time: lager to
pilsner or blonde, stout to porter, IPA to pale ale. A distant high-ABV or strongly sour beer needs
positive evidence rather than a generic novelty bonus.

### 3. Craft variety maven

Shows high style and brand diversity with broad positive history. Novelty is useful evidence, but it
never overrides a recorded dislike or explicit stay-away choice.

### 4. Style specialist

Repeatedly chooses one family, such as hoppy beer, dark malt, wheat, or sour. "Craft" and popularity
are not evidence that another family fits. Fine distinctions such as hazy versus West Coast IPA or dry
versus pastry stout require a richer flavor schema than SipCheck v1 currently stores.

### 5. Local or taproom loyalist

May favor nearby producers and taproom experiences. Locality should break a close tie between equally
suitable beers; it must never override taste evidence.

### 6. Moderation-minded beer lover

Still cares about beer flavor but sometimes wants lower/no alcohol. Match flavor family first, then
honor the occasion's strength constraint. Low/no alcohol should not be treated as a standalone style.

### 7. Occasion-dependent switcher

Enjoys different strengths or styles in different settings. A single lifetime ABV average cannot
represent "tasting flight" and "outdoor afternoon" simultaneously. This needs an optional current-
occasion input in a later model.

### 8. Sparse-history drinker

Has too little evidence for strong personalization. One Blue Moon rating, for example, does not justify
a confident sour recommendation or rejection. Prefer YOUR CALL until an explicit pole or repeated
history exists.

## Stress-test oracle

`TRY`, `SKIP`, and `CALL` below are behavioral expectations, not population prevalence claims.

| Persona | Adjacent beer | Distant beer | Expected rule |
|---|---|---|---|
| Lager loyalist, cautious | Craft pilsner | Fruit sour | TRY adjacent; SKIP distant |
| Dark-malt regular, cautious | Porter | West Coast IPA | TRY adjacent; SKIP distant |
| Sour specialist | Gose/wild ale | Imperial stout | TRY sour; use explicit dark evidence for stout |
| Hop specialist | Pale ale/IPA | Sour | TRY hops; sour needs its own evidence |
| Broad explorer | Unfamiliar saison | Recorded avoid style | TRY novelty; SKIP hard avoid |
| Moderation mode | NA version of liked style | Double IPA tonight | TRY flavor match; SKIP occasion mismatch |
| Big-beer seeker | Tripel/imperial stout | Light lager | Use strength history separately from style |
| Sparse history | Related or distant style | Any flavor extreme | CALL unless explicit evidence exists |

The user's illustrative case is one row of this matrix: repeated light-lager history plus "Stick to
Favorites" and no tart evidence should SKIP a sour, while an adjacent craft pilsner should TRY.

## Implemented safeguards

The 2026-07-15 stress-test pass added deterministic coverage for:

- Explicit stay-away styles remain hard SKIP constraints until the user clears them.
- Adding a positive rating cannot lower an existing go-to recommendation.
- Adding a dislike cannot raise a recommendation.
- A new dislike cannot soften an existing quiz-level style rejection.
- Legacy history labels such as `Light Lager` contribute to the canonical Lager profile.
- Repeated cautious lager history tries an adjacent pilsner and skips a distant sour.
- A cautious light-lager preference does not treat American pale ale as automatically adjacent.
- A cautious stout preference tries porter and skips distant IPA.
- Generic adventurousness alone does not imply sour preference.
- One isolated positive rating does not create a confident distant-style rejection.
- Untrusted camera/catalog guesses cannot trigger an exact-beer history override.
- Beer picks that resolve to the same style are cross-locked between go-to and stay-away onboarding.
- Newly enriched facts are re-scored locally before the visible verdict is updated.

The LLM resolves beer facts only. The local deterministic scorer owns the personalized verdict.

## Known model gaps

- `BeerStyle` is coarse: hazy and West Coast are both IPA; dry and imperial are both Stout.
- Sour, bitterness, roast/body, and alcohol-strength tolerance are not independent stored attributes.
- There is no current-occasion or "lower alcohol tonight" input.
- Locality and brand loyalty are not modeled as tiebreak signals.
- Low/no alcohol is not represented independently from flavor style.

These gaps should be addressed through additional observed history or one optional contextual control,
not a longer required onboarding quiz. The existing two-pole onboarding remains the strongest cold-
start signal.

## Sources and caveats

- [Malone and Lusk, Agribusiness (2018)](https://doi.org/10.1002/agr.21511): survey of more than
  1,500 U.S. beer drinkers identified traditional, premium, maven, and locality-oriented segments.
  Useful for behavioral segmentation, but based on older stated-preference data.
- [Bronnenberg, Dube, and Joo, Marketing Science](https://doi.org/10.1287/mksc.2022.1371): historical
  exposure/availability explained most of the Millennial-Boomer craft-share gap. Supports learning
  from experience rather than using age as taste.
- [Higgins et al., Food Quality and Preference (2020)](https://doi.org/10.1016/j.foodqual.2020.103994):
  bitterness perception and sensation seeking interact; perceived bitterness alone does not imply
  dislike. Small U.S. sensory sample.
- [D'Andrea et al., Food Quality and Preference (2026)](https://doi.org/10.1016/j.foodqual.2025.105811):
  sour response separated into distinct groups and related to habitual tart-food intake, not generic
  sensation seeking. Tested acid solutions rather than beer.
- [Ramsey et al., Food Quality and Preference (2018)](https://doi.org/10.1016/j.foodqual.2018.03.019):
  alcohol level changed sweetness, fullness, warmth, and liking differently across consumer clusters.
- [Brewers Association/Harris Poll (2026)](https://www.brewersassociation.org/insights/mixed-signals-2026-consumer-survey/):
  craft drinkers show substantial brand variety while both high- and low-ABV interest are present.
  Trade-sponsored survey with limited public methodology.
- [Brewers Association, NA beer occasions (2026)](https://www.brewersassociation.org/brewing-industry-updates/rising-to-the-occasion-positioning-na-beer/):
  moderation often reflects an occasion rather than a fixed identity. Industry analysis.
- [Gallup (2025)](https://news.gallup.com/poll/693362/drinking-rate-new-low-alcohol-concerns-surge.aspx):
  beer remained the leading alcoholic category among U.S. drinkers while overall drinking frequency
  declined. National survey; not a beer-style preference study.
- [Hamerman et al., Appetite (2025)](https://pubmed.ncbi.nlm.nih.gov/40516613/): NA affinity related to
  taste, beer frequency, health consciousness, cut-back intent, and social exposure. Associations are
  not causal purchase evidence.
- [IWSR (2024)](https://www.theiwsr.com/insight/millennials-drive-no-alcohol-gains-in-the-us/):
  full-strength and no-alcohol use overlap. Proprietary industry methodology.

The archetypes are engineering fixtures for adversarial testing, not claims that every U.S. drinker
belongs to exactly one segment.
