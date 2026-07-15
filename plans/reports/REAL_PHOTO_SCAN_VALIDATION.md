# Real-photo scan validation (2026-07-15)

## What was tested

- Device: iPhone 15 Pro (A17 Pro), iOS 26.5.2.
- Input set: 17 real photographs, with no generated or stylized test images.
- Coverage: six grocery-store photos supplied by the owner, one Bia Viet label,
  and ten public real photos spanning single-product and deliberately difficult
  shelf/display scenes.
- Path: Apple Vision OCR, bundled catalog, label-text style extraction, and the
  deterministic `TasteScorer`. The measured batch did not use a paid API.
- Separate live-camera check: VisionKit DataScanner reported supported and
  available, recognized a Bia Viet display, and handed a 1.6 MB captured frame to
  the app for persistence.
- Separate on-device-model check: Apple Foundation Models was available and
  returned structured facts for Guinness Draught Stout. The final post-fix smoke
  returned brewery `Guinness`, style `Stout`, and ABV `5.5%`.

The owner photos remain workspace-local and are not redistributed by this report.

## Results

| Measure | Result |
|---|---:|
| Photos processed | 17/17 |
| Style-level verdict available offline | 14/17 |
| Owner grocery photos with a style-level verdict | 6/6 |
| Median local processing time | 235 ms |
| At or below 525 ms | 16/17 |
| Cold first scan | 1,217 ms |

The free path was fast enough to put a verdict on screen for every owner photo.
It correctly identified the broad printed style for Headlands Whoosh, Boatswain,
Juicy Nuevo, Stefano, and the Altamont/Pizza Port can. It matched Firestone Walker
805 in the bundled catalog. Exact product identity remains less reliable than style:
large logos, vertical type, partial words, foreign labels, and shelves with several
products can produce a useful style while choosing the wrong display name. For
example, the Altamont/Pizza Port image received an incorrect moderate catalog match
to `Centennial IPA`, despite the correct IPA family.

That distinction is intentional in the product flow: a printed style can generate
an immediate offline verdict, while uncertain label identity may be corrected
asynchronously by the image-aware OpenAI fallback. The fallback now treats the
photograph as authoritative, includes OCR only as context, and does not substitute a
text-only model guess when visual identification fails.

The three unresolved single-bottle cases were Orion, Tusker, and Tyskie. They are
useful evidence for the optional visual fallback, not a reason to block the free
critical path. Multi-product shelf scenes are stress cases; there is no single
unambiguous target unless the user frames one product.

## Artifacts

- Final device results:
  `.artifacts/validation-real-photos-2026-07-15/device-image-batch-results-final.json`
- Device corpus:
  `.artifacts/validation-real-photos-2026-07-15/ValidationSamples/`
- Owner originals: `.artifacts/7152026 samples/`
- Final 30 fps flow recording:
  `.artifacts/sipcheck-walkthroughs-2026-07-15/final-polish-real-photo-30fps.mp4`

The local API key currently returns HTTP 401, so the paid correction path was not
counted as validated by this device batch and no model tokens were spent on it. The
branch CI performs a zero-token authentication check against the GitHub
`OPENAI_API_KEY` secret before merge.

## Public image sources

All downloaded validation images are real photographs from Wikimedia Commons.
The files remain workspace-local test artifacts.

| Subject | Author | License | Source |
|---|---|---|---|
| Baby Face / Huskie | Pansebert | CC0 | [Commons](https://commons.wikimedia.org/wiki/File:Baby_Face_(The_Huskie_Craft_Beer_Company).jpg) |
| Brauerei Zwonitz IPA | 5snake5 | CC0 | [Commons](https://commons.wikimedia.org/wiki/File:Brauerei_Zw%C3%B6nitz_-_India_Pale_Ale_Craft_Beer.jpg) |
| Beer Can Museum display | Beercanmuseum | CC BY-SA 3.0 | [Commons](https://commons.wikimedia.org/wiki/File:Cans_on_display_at_the_Beer_Can_Museum.jpg) |
| Phuket craft beer display | Chainwit. | CC BY-SA 4.0 | [Commons](https://commons.wikimedia.org/wiki/File:Craft_beer_of_Thailand_%22Phuket%22_%E0%B8%84%E0%B8%A3%E0%B8%B2%E0%B8%9F%E0%B8%97%E0%B9%8C%E0%B9%80%E0%B8%9A%E0%B8%B5%E0%B8%A2%E0%B8%A3%E0%B9%8C%E0%B9%84%E0%B8%97%E0%B8%A2_%E0%B8%A0%E0%B8%B9%E0%B9%80%E0%B8%81%E0%B9%87%E0%B8%95.jpg) |
| Thai craft beer brands | Chainwit. | CC BY-SA 4.0 | [Commons](https://commons.wikimedia.org/wiki/File:Craft_beer_of_Thailand_many_brands_%E0%B8%84%E0%B8%A3%E0%B8%B2%E0%B8%9F%E0%B8%97%E0%B9%8C%E0%B9%80%E0%B8%9A%E0%B8%B5%E0%B8%A2%E0%B8%A3%E0%B9%8C%E0%B9%84%E0%B8%97%E0%B8%A2_%E0%B8%AB%E0%B8%A5%E0%B8%B2%E0%B8%A2%E0%B8%A2%E0%B8%B5%E0%B9%88%E0%B8%AB%E0%B9%89%E0%B8%AD.jpg) |
| OakNOLA vintage cans | Infrogmation of New Orleans | CC BY-SA 3.0 | [Commons](https://commons.wikimedia.org/wiki/File:OakNOLABeerCans.JPG) |
| Orion bottle | Yuet Man Lee | CC BY-SA 4.0 | [Commons](https://commons.wikimedia.org/wiki/File:Orion_Premium_Draft_Beer,_633_mL_bottle_as_sold_in_Canada.jpg) |
| Tusker bottle | Bahnfrend | CC BY-SA 4.0 | [Commons](https://commons.wikimedia.org/wiki/File:Tusker_beer_bottle_with_beer_glass,_Thorn_Tree_Cafe,_2025_(01).jpg) |
| Tyskie bottle | Bahnfrend | CC BY-SA 4.0 | [Commons](https://commons.wikimedia.org/wiki/File:Tyskie_beer_bottle_with_beer_glass,_Wikimania_2024_(01).jpg) |
| White Cap bottle | Bahnfrend | CC BY-SA 4.0 | [Commons](https://commons.wikimedia.org/wiki/File:White_Cap_beer_bottle_with_beer_glass,_Carnivore,_2025_(01).jpg) |
