# Beer-Label Image Libraries — Manifest for OCR/Label Eval

Purpose: a practical, accurate inventory of **open** beer-label / beer-product
**photo** libraries to evaluate SipCheck's on-device OCR/label path
(Apple Vision) against real labels.

- **Verified today (2026-06-30):** endpoint was actually hit from this
  environment and returned the documented result.
- **unverified:** could not be reached/confirmed here; treat with caution and
  re-check on a real network before relying on it.
- Reachability through this environment's HTTPS proxy is not the same as
  reachability from a developer laptop or a device on a real network. A failure
  here does not necessarily mean the source is down for everyone.

---

## 1. Open Food Facts (OFF) — product images

**Name:** Open Food Facts product image API + bulk image export
**URL:** https://world.openfoodfacts.org  (images host: https://images.openfoodfacts.org)
**Contains:** Crowd-sourced product photos (front / ingredients / nutrition /
packaging) for millions of food and drink products, including a large beer
subset. Front images are real-world phone photos of labels/bottles/cans —
exactly the kind of input the Vision OCR path will see.
**Rough scale:** ~3M+ products overall; a beer-category query returns
**~10,470 products** today (see search below). Many, but not all, have a front
image.
**License:** Product **data** under Open Database License (ODbL 1.0);
**images** under Creative Commons Attribution-ShareAlike (CC BY-SA). Attribution
+ share-alike required. Confirm per-image since contributors can vary.

### How to pull a sample

**a) Product by barcode — VERIFIED today (HTTP 200).**
Note: the CLAUDE/task-suggested Heineken barcode `8712000028473` returns
`product not found` (HTTP 404) — not every barcode is in OFF. A known-present
beer barcode is `3080216043807` (Tourtel Twist):

```bash
curl "https://world.openfoodfacts.org/api/v2/product/3080216043807.json?fields=code,product_name,image_front_url,selected_images"
```

Returns `image_front_url`, e.g.
`https://images.openfoodfacts.org/images/products/308/021/604/3807/front_en.228.400.jpg`
— **VERIFIED** this URL returns `HTTP 200, content-type image/jpeg`.

**b) Search API — VERIFIED WORKING today (contradicts the "down" note).**
The legacy CGI search returned `HTTP 200`, `count: 10470` for beer:

```bash
curl "https://world.openfoodfacts.org/cgi/search.pl?search_terms=beer&json=1&page_size=20"
```

Caveat: this endpoint is historically flaky / rate-limited and OFF asks you not
to hammer it. It worked in this environment right now, but treat heavy use as
**unreliable** and prefer the bulk export for volume.

**c) Image URL pattern (for building URLs from a barcode).**
Base: `https://images.openfoodfacts.org/images/products/`
Barcode is zero-padded to 13 digits and split `(...)(...)(...)(.*)` into folders.
- Raw image: `<folders>/<image_id>.jpg` (also `<image_id>.<resolution>.jpg`)
- Selected image: `<folders>/<type>_<lang>.<rev>.<resolution>.jpg`
  e.g. `.../316/893/001/0883/front_fr.4.400.jpg`
Docs: https://openfoodfacts.github.io/openfoodfacts-server/api/how-to-download-images/

**d) Bulk static exports — links VERIFIED present on the /data page.**
https://world.openfoodfacts.org/data
- MongoDB dump: `https://static.openfoodfacts.org/data/openfoodfacts-mongodbdump.gz`
- JSONL: `https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz`
- CSV: `https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz`
- Parquet (Hugging Face): `https://huggingface.co/datasets/openfoodfacts/product-database/resolve/main/food.parquet?download=true`
These give you barcodes + image references; download the actual image bytes via
(c) or (e). (Sizes not downloaded here, but link presence is verified.)

**e) Bulk IMAGE download via AWS S3 — VERIFIED bucket details from OFF docs.**
Bucket: `openfoodfacts-images`, region `eu-west-3`, public.
HTTP form (no AWS account needed), example from the docs:
```bash
wget https://openfoodfacts-images.s3.eu-west-3.amazonaws.com/data/401/235/911/4303/1.jpg
```
The docs say AWS CLI also works (e.g. with `--no-sign-request` against the
public bucket) but do not quote an exact `aws s3 cp` line — treat the precise
CLI syntax as **unverified** and confirm against
https://openfoodfacts.github.io/openfoodfacts-server/api/aws-images-dataset/

---

## 2. Open Beer Facts (OBF) — sister project

**Name:** Open Beer Facts
**URL:** https://world.openbeerfacts.org  (also https://openbeerfacts.org)
**Contains:** A beer-specific Open*Facts sibling: beer products with labels,
brewery, ABV, style, and photos. Smaller and less complete than OFF.
**Rough scale:** Small (tens of thousands of products historically; far fewer
with photos). Treat scale as **unverified**.
**License:** Same model as OFF — data ODbL, images CC BY-SA.

### Reachability — FLAGGED
**Unreachable from this environment today.** Both `world.openbeerfacts.org`,
`openbeerfacts.org`, and `world.openbeerfacts.net` returned `HTTP 000`
(no connection) through this environment's proxy. This may be a proxy/DNS issue
here rather than a global outage — **re-verify from a normal network.**

### How to pull a sample (pattern, **unverified** here)
Mirrors the OFF v2 API; if/when reachable:
```bash
curl "https://world.openbeerfacts.org/api/v2/product/<barcode>.json"
```
Image URLs follow the same `images.openbeerfacts.org/images/products/<folders>/...`
convention as OFF. Bulk exports are historically published under
`https://static.openbeerfacts.org/data/`. All **unverified** — confirm live.

---

## 3. Wikimedia Commons — beer-label / beer-bottle categories

**Name:** Wikimedia Commons (MediaWiki API)
**URL:** https://commons.wikimedia.org
**Contains:** Freely licensed images, including categories of beer labels,
bottles, and cans. Mix of historical/vintage labels, studio shots, and amateur
photos. Quality and "looks like a phone scan" varies widely.
**Rough scale:** Hundreds to low-thousands per relevant category (e.g.
`Category:Beer labels`, `Category:Beer bottles`, `Category:Beer cans`).
**License:** Per-file (CC BY / CC BY-SA / public domain). Many vintage labels
are PD. **Check each file's license + attribution** — Commons mixes licenses.

### How to pull a sample — VERIFIED today (both calls HTTP 200)

**a) List files in a category:**
```bash
curl "https://commons.wikimedia.org/w/api.php?action=query&list=categorymembers&cmtitle=Category:Beer_labels&cmlimit=20&cmtype=file&format=json"
```
Verified: returns file titles like `File:1872-Porter.png`,
`File:Aber-Fine Beer 01.jpg`; paginate with the returned `cmcontinue` token.

**b) Resolve a file title to a downloadable image URL:**
```bash
curl "https://commons.wikimedia.org/w/api.php?action=query&titles=File:Aber-Fine%20Beer%2001.jpg&prop=imageinfo&iiprop=url|size|mime&format=json"
```
Verified: returns
`https://upload.wikimedia.org/wikipedia/commons/f/f4/Aber-Fine_Beer_01.jpg`
(`image/jpeg`, 1100x2260). Download that URL directly for the bytes.

Other useful categories to query the same way: `Category:Beer bottles`,
`Category:Beer cans`, `Category:Beer labels by country`.

---

## 4. craft-beers / craft-cans datasets — METADATA ONLY (no label photos)

**Name:** nickhould "Craft Beers Dataset" (a.k.a. Kaggle "Craft Cans"); related:
Open Brewery DB.
**URLs:**
- https://github.com/nickhould/craft-beers-dataset
- https://www.kaggle.com/datasets/nickhould/craft-cans
- https://www.openbrewerydb.org/ , https://github.com/openbrewerydb/openbrewerydb
**Contains:** **Tabular metadata, NOT label images.** ~2,000+ US canned craft
beers and ~500+ breweries: name, style, ABV, IBU, ounces, brewery, city/state.
**Rough scale:** ~2,400 beers / ~560 breweries (Open Brewery DB is larger for
brewery records).
**License:** nickhould dataset is CC (commonly cited CC BY-NC-SA 4.0 — confirm on
the page before commercial use); Open Brewery DB data is open with a
developer-friendly API (no key, no rate limit).

### IMPORTANT — not an image source
**VERIFIED:** the repo's `images/` directory contains only project/chart PNGs
(`CraftCans.png`, `ChromeInspect.png`, `craft-beer-cans.jpg`, etc.) — **no
per-beer label photos.** The data lives in `data/processed/beers.csv` (160 KB)
and `data/processed/breweries.csv` (25 KB).

**Use it for:** ground-truth strings to match OCR output against (beer name,
brewery, ABV, style), synthetic test cases, and validating parsing — **not** as
image input. Pull metadata:
```bash
curl "https://api.github.com/repos/nickhould/craft-beers-dataset/contents/data/processed"
# or raw:
curl "https://raw.githubusercontent.com/nickhould/craft-beers-dataset/master/data/processed/beers.csv"
```
Open Brewery DB API (metadata, no key):
```bash
curl "https://api.openbrewerydb.org/v1/breweries?per_page=5"
```

---

## Recommended starter set for OCR eval

Goal: a few dozen real beer-label photos with known ground-truth text, pulled
quickly, on permissive-enough licenses for an internal eval.

1. **Primary image source — Open Food Facts.** Best ratio of real phone-style
   front-label photos to effort, and verified reachable today.
   - Quick start (small N): use the search API to grab beer barcodes
     (`search_terms=beer`), then fetch each product's `image_front_url` and
     download it. ~20-50 fronts is enough for a first Vision OCR pass.
   - For volume / repeatability: download a bulk export (JSONL or Parquet),
     filter to `categories` containing beer, and pull images from the
     `openfoodfacts-images` S3 bucket / `images.openfoodfacts.org` rather than
     hammering the live search API.
   - You get implicit ground truth: `product_name`, `brands`, and often ABV in
     the same record to score OCR against.

2. **Supplement with Wikimedia Commons** for variety (vintage labels, different
   countries, studio vs. casual shots). Verified reachable. Use the
   `categorymembers` -> `imageinfo` two-step. Good for stress-testing OCR on
   stylized / non-standard label typography. Track each file's license.

3. **Ground-truth text — nickhould craft-beers CSV + Open Brewery DB.** No
   images, but useful as a dictionary of real beer/brewery names, styles, and
   ABV to validate and score OCR extraction (fuzzy-match recognized text
   against known strings).

4. **Open Beer Facts — defer until reachability confirmed.** Beer-specific and
   would be ideal, but it was **unreachable from this environment today**
   (HTTP 000). Re-test from a real network; if up, mirror the OFF v2
   barcode/image approach. Do not block the eval on it.

**Suggested first concrete pull (verified-working commands only):**
```bash
# 1. Get beer barcodes
curl "https://world.openfoodfacts.org/cgi/search.pl?search_terms=beer&json=1&page_size=30" \
  | python3 -c "import sys,json;[print(p['code']) for p in json.load(sys.stdin)['products']]"

# 2. For each barcode, fetch front image URL and download
curl "https://world.openfoodfacts.org/api/v2/product/<code>.json?fields=product_name,brands,image_front_url"
# then download the returned image_front_url

# 3. Add a few Commons labels for variety
curl "https://commons.wikimedia.org/w/api.php?action=query&list=categorymembers&cmtitle=Category:Beer_labels&cmlimit=20&cmtype=file&format=json"
```

---

### Verification log (this environment, 2026-06-30)
- OFF product-by-barcode `3080216043807`: **HTTP 200**, returned `image_front_url`.
- OFF suggested barcode `8712000028473`: **HTTP 404** product not found.
- OFF `image_front_url` (Tourtel front_en.228.400.jpg): **HTTP 200, image/jpeg**.
- OFF search.pl `search_terms=beer`: **HTTP 200, count=10470** (worked despite
  reputation for being rate-limited/down).
- OFF `/data` export page: **HTTP 200**, MongoDB/JSONL/CSV/Parquet links present.
- OFF S3 image bucket: `openfoodfacts-images` / `eu-west-3` (from OFF docs).
- Open Beer Facts (3 hostnames): **HTTP 000 — unreachable here.**
- Commons `categorymembers` (Category:Beer_labels): **HTTP 200**, file list returned.
- Commons `imageinfo`: **HTTP 200**, resolved to upload.wikimedia.org JPEG (1100x2260).
- nickhould `images/`: **HTTP 200** — only chart/project PNGs, no label photos.
- nickhould `data/processed/`: beers.csv (160 KB), breweries.csv (25 KB).
