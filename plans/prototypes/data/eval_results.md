# SipCheck eval results

_Dataset: 2405 real craft beers (craft_beers.csv). On-device fast path: parse + name-style-infer + verdict. No network, no LLM, no barcode. Seed=1234._

## 1. Style-inference accuracy (name-only vs ground truth)

- Beers in dataset: **2405**
- Mapped to a coarse style we model (denominator): **2086** (319 are cider/rye/scotch/etc. outside our 11-style taxonomy)
- Name produced a style guess: **57.3%** of those (890 names gave no guess)
- **HEADLINE ACCURACY: 51.0%** correct coarse-style from NAME alone (1063/2086)
- Accuracy when a guess IS made: **88.9%** (1063/1196)

Per-style precision (truth -> top confusions):

| truth style | n | correct | top wrong guesses |
|---|---|---|---|
| ipa | 571 | 352 (61%) | (no guess):167, pale ale:48, belgian:1 |
| pale ale | 448 | 187 (41%) | (no guess):249, ipa:5, stout:2 |
| lager | 178 | 73 (41%) | (no guess):96, amber:5, ipa:2 |
| pilsner | 133 | 65 (48%) | (no guess):57, lager:9, pale ale:2 |
| stout | 100 | 69 (69%) | (no guess):31 |
| porter | 74 | 54 (72%) | (no guess):19, stout:1 |
| wheat | 201 | 81 (40%) | (no guess):98, ipa:12, belgian:9 |
| sour | 27 | 14 (51%) | (no guess):11, belgian:1, pale ale:1 |
| amber | 175 | 84 (48%) | (no guess):70, lager:20, pale ale:1 |
| brown ale | 88 | 58 (65%) | (no guess):29, stout:1 |
| belgian | 91 | 26 (28%) | (no guess):63, amber:1, ipa:1 |

## 2. Verdict distribution per persona (whole dataset)

Two columns per persona, so the numbers are honest about what ships:

- **real (name-inferred)** — style inferred from the NAME only, exactly what the on-device path does. **This is the number to quote.**
- **upper bound (perfect style)** — style taken from the dataset's ground-truth label; the app does NOT have this. Shown only as a ceiling.

| persona | real (name-inferred): ORDER / your call / skip | upper bound: ORDER / your call / skip |
|---|---|---|
| hop-forward | 624 (25%) / 1614 (67%) / 167 (6%) | 1017 (42%) / 1230 (51%) / 158 (6%) |
| malty / safe | 275 (11%) / 1513 (62%) / 617 (25%) | 413 (17%) / 1281 (53%) / 711 (29%) |
| adventurous | 152 (6%) / 2102 (87%) / 151 (6%) | 318 (13%) / 1898 (78%) / 189 (7%) |

Sanity: no persona collapses into a single bucket. The real column shows fewer ORDER THIS than the upper bound because names that yield no style guess default toward 'your call' — i.e. the app stays cautious rather than over-promising.

## 3. Menu single-winner (50 sampled real menus)

| persona | winner not a disliked style | strictly-unique top score | winner is 'ORDER THIS' |
|---|---|---|---|
| hop-forward | 50/50 | 26/50 | 44/50 |
| malty / safe | 50/50 | 34/50 | 30/50 |
| adventurous | 50/50 | 31/50 | 25/50 |

(Strict-unique top score = the deterministic tiebreaker still yields ONE winner even when scores tie; see fix #2.)

### Spot-check: 5 menus (hop-forward persona)

```
ON TAP
Saison 88  - Brewery392   5.5%  $9
Pale Alement  - Brewery24   5.5%  $11
Brew Free! or Die IPA (2009)   7.0%   $7
Plum St. Porter   - Brewery219    6.0%   $8
Edward’s Portly Brown   - Brewery14    4.5%   $11
Aslan Amber  - Brewery353   7.7%  $12
Live Local Golden Ale  - Brewery107   4.7%  $12
Mind Games   - Brewery10    4.1%   $9
Ranger IPA   - Brewery82    6.5%   $8
Farmer Brown Ale  7.0%  $6
35 K  - Brewery1   7.7%  $9
Arjuna  - Brewery193   6.0%  $10

-> parsed 12 beers
-> WINNER: Ranger IPA - Brewery82  [ipa, 6.5%]  score +3.5  verdict=ORDER THIS
   why: matches your love of ipa
```

```
DRAFTS
South Ridge Amber Ale  - Brewery472   6.0%  $8
Green Collar  - Brewery422   5.9%  $6
Upslope Christmas Ale  8.2%  $7
Salamander Slam  7.0%  $10
IPA #11   - Brewery121    5.7%   $11
Boont Amber Ale (2010)   5.8%   $11
Bohemian Pils   - Brewery143    5.2%   $7
Polar Pale Ale  - Brewery493   5.2%  $11
Knotty Blonde Ale   - Brewery153    4.0%   $7

-> parsed 9 beers
-> WINNER: IPA #11 - Brewery121  [ipa, 5.7%]  score +3.5  verdict=ORDER THIS
   why: matches your love of ipa
```

```
DRAFTS
Coq D'Or  5.0%  $9
Steam Engine Lager  - Brewery119   5.7%  $7
Orlison India Pale Lager  6.7%  $8
Oregon Trail Unfiltered Raspberry Wheat   4.5%   $7
Mjolnir Imperial IPA  - Brewery201   6.9%  $9
Session '33 (2011)   4.0%   $8
Zaison (2012)  - Brewery10   9.0%  $8
Arkansas Red   - Brewery139    5.2%   $11
#002 American I.P.A.  7.1%  $9
Day Tripper Pale Ale   - Brewery277    5.4%   $10

-> parsed 10 beers
-> WINNER: Mjolnir Imperial IPA - Brewery201  [ipa, 6.9%]  score +3.5  verdict=ORDER THIS
   why: matches your love of ipa
```

```
DRAFTS
Ryecoe  - Brewery8   6.2%  $7
1554 Black Lager  5.6%  $7
Rivet Irish Red Ale   - Brewery17    5.1%   $9
Indie Pale Ale   - Brewery145    6.5%   $6
Bourbon Barrel Cowbell  $7
Trader Session IPA  4.0%  $10
6 String Saison   8.0%   $10
Boxer   - Brewery134    5.0%   $8

-> parsed 8 beers
-> WINNER: Trader Session IPA  [ipa, 4.0%]  score +3.5  verdict=ORDER THIS
   why: matches your love of ipa
```

```
BEER MENU
Mana Wheat  - Brewery375   5.5%  $12
Wild Wolf Wee Heavy Scottish Style Ale   - Brewery181    5.7%   $8
Jai Alai IPA   - Brewery141    7.5%   $10
Cornstalker Dark Wheat  - Brewery282   $11
Lucky U IPA  - Brewery391   6.2%  $10
The One They Call Zoe   - Brewery395    5.1%   $10
Joseph James American Lager   - Brewery233    5.2%   $11
Firemans #4 Blonde Ale (2013)  - Brewery128   5.1%  $7
Mind's Eye PA   - Brewery11    6.7%   $9

-> parsed 9 beers
-> WINNER: Lucky U IPA - Brewery391  [ipa, 6.2%]  score +3.5  verdict=ORDER THIS
   why: matches your love of ipa
```

## 4. Fixing the two known flaws (before/after)

### Flaw #1 — junk non-beer lines leak through as candidates

Menu under test:
```
ON TAP
Hazy Little Thing IPA   6.7%   $8
Founders Porter   6.5%   $7
KITCHEN
Loaded Nachos   $12
Buffalo Wings
Sierra Nevada Pale Ale   5.6%   $7
DESSERTS
Cheesecake
```
- BEFORE (no filter): parsed **7** candidates — includes junk: 'Loaded Nachos', 'Buffalo Wings', 'DESSERTS', 'Cheesecake'
- AFTER (junk filter): parsed **4** candidates: 'Hazy Little Thing IPA', 'Founders Porter', 'Loaded Nachos', 'Sierra Nevada Pale Ale'
- Junk lines dropped: **3** (dropped: 'Buffalo Wings', 'DESSERTS', 'Cheesecake')
- Residual: 'Loaded Nachos' still parse(s) (carry a price), but score low and never win.
  e.g. 'Loaded Nachos' scores -0.5 (verdict=skip); menu winner is 'Hazy Little Thing IPA' at +3.5. Winner selection is the real guard, not parsing.

### Flaw #2 — top-score ties resolve by arbitrary list order

Menu under test (two IPAs both at the ideal 6.0% ABV -> identical score):
```
ON TAP
North Coast Scrimshaw Pilsner   6.0%   $7
Lagunitas IPA   6.0%   $8
Bell's Two Hearted IPA   6.0%   $8
Guinness Stout   4.2%   $7
```
- Tied at top score +3.5: ['Lagunitas IPA', "Bell's Two Hearted IPA"]
- BEFORE (list-order tiebreak): winner = **Lagunitas IPA**; reverse the same menu -> winner = **Bell's Two Hearted IPA** (NONDETERMINISTIC)
- AFTER (closer-ABV, then higher liked-weight, then name): winner = **Bell's Two Hearted IPA**; reversed menu -> **Bell's Two Hearted IPA** (STABLE)

- Deterministic across input order: **True**

