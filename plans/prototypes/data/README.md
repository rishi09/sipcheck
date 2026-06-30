# Craft Beers Dataset (scan eval ground truth)

## Source
- **URL:** https://raw.githubusercontent.com/nickhould/craft-beers-dataset/master/data/processed/beers.csv
- **Repo:** https://github.com/nickhould/craft-beers-dataset
- **Origin:** Scraped from CraftCans.com (Jean-Nicholas Hould). Style names follow
  BeerAdvocate-style free-text conventions.

## License / Attribution
The repository does not ship an explicit OSS license file. The data was published
by Jean-Nicholas Hould for educational/analysis use (originally a tutorial on data
cleaning) and is widely redistributed for non-commercial learning purposes. Use here
is limited to **internal evaluation of the SipCheck scan pipeline** (ground-truth for
style/ABV bucketing accuracy). Attribute to Jean-Nicholas Hould / CraftCans if
surfaced anywhere user-facing. Do not redistribute as a product asset without
confirming licensing.

## Schema
Columns: `,abv,ibu,id,name,style,brewery_id,ounces`
- First (unnamed) column is a row index.
- `abv` is a **0-1 fraction** (e.g. `0.05` = 5.0% ABV), NOT a percentage.
- `ibu` is frequently blank.
- `style` is free-text BeerAdvocate-style names.

## Row / value counts
- **Data rows:** 2410 (file has 2411 lines incl. header)
- **Distinct `style` values:** 100 (includes 5 rows with a blank style)
- **`abv` present:** 2348 rows; **missing:** 62 rows

## ABV (fraction, multiply by 100 for %)
- **min:** 0.001 (0.1%)
- **max:** 0.128 (12.8%)
- **mean:** 0.05977 (~5.98%)

## Note for the eval: style bucketing required
The `style` field is high-cardinality free text (100 distinct values) using
BeerAdvocate naming, e.g. "American IPA", "American Double / Imperial IPA",
"Oatmeal Stout", "Saison / Farmhouse Ale", "Witbier", "Kölsch". The scan eval must
**bucket these into SipCheck's coarse styles**:

`ipa, pale ale, lager, pilsner, stout, porter, wheat, sour, amber, brown ale, belgian, other`

Suggested bucketing heuristics (case-insensitive substring matching, check in a
sensible order so e.g. IPA wins over generic "ale"):
- **ipa** — contains "IPA" or "India Pale" (covers American IPA, Imperial IPA,
  Belgian IPA, White IPA, India Pale Lager, etc.)
- **pale ale** — "Pale Ale" / "APA" / "ESB" / "Bitter" (not already IPA)
- **pilsner** — "Pilsener" / "Pilsner" / "Pils"
- **lager** — "Lager" / "Helles" / "Märzen" / "Oktoberfest" / "Bock" / "Vienna" /
  "Dunkel" (lager) / "Schwarzbier" / "Kölsch" / "Cream Ale" / "Steam" / "Common"
- **stout** — "Stout"
- **porter** — "Porter"
- **wheat** — "Wheat" / "Weizen" / "Hefe" / "Witbier" / "Weissbier" / "Gose" /
  "Berliner"
- **sour** — "Sour" / "Wild Ale" / "Flanders" / "Oud Bruin" / "Gose" (sour overlaps
  wheat for Gose/Berliner — decide precedence in the eval)
- **amber** — "Amber" / "Red Ale" / "Red Lager" / "Altbier"
- **brown ale** — "Brown"
- **belgian** — "Belgian" / "Saison" / "Farmhouse" / "Tripel" / "Dubbel" /
  "Quadrupel" / "Abbey" / "Bière de Garde" / "Grisette" / "Witbier" (Belgian)
- **other** — everything else (Cider, Mead, Fruit/Vegetable, Pumpkin, Barleywine,
  Radler, Shandy, Smoked, Braggot, blank style, etc.)

Several styles legitimately match multiple buckets (Witbier is Belgian + wheat; Gose
is wheat + sour). The eval should fix a deterministic precedence order and document
it; the bucket mapping itself is part of what the eval measures.

### Top styles by frequency (for sanity-checking the bucketer)
```
424  American IPA
245  American Pale Ale (APA)
133  American Amber / Red Ale
108  American Blonde Ale
105  American Double / Imperial IPA
 97  American Pale Wheat Ale
 70  American Brown Ale
 68  American Porter
 52  Saison / Farmhouse Ale
 51  Witbier
 49  Fruit / Vegetable Beer
 42  Kölsch
 40  Hefeweizen
 39  American Pale Lager
 39  American Stout
 37  Cider
 36  American Black Ale
 36  German Pilsener
 30  Märzen / Oktoberfest
 29  American Amber / Red Lager
```
(Full 100-value distribution available via:
`python3 -c "import csv,collections;print(collections.Counter(r['style'] for r in csv.DictReader(open('craft_beers.csv'))).most_common())"`)
