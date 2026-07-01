#!/usr/bin/env python3
"""
Grocery scan test harness — run REAL beer photos through the full on-device chain.

Flow when photos arrive:
  1. Photos dropped in  plans/prototypes/grocery_test/
  2. For each photo, the text visible on the label is written into  grocery_test/inputs.json
     (Claude reads each image and fills this in — standing in for iPhone camera OCR).
  3. Run:  python3 scan_test.py
     -> resolves each beer via the SAME logic as BeerResolver.swift (printed style/ABV ->
        bundled catalog -> unresolved), scores it with the SAME logic as TasteScorer.swift,
        prints a table, and writes a self-contained mobile report at grocery_test/report.html.

No iPhone / network / API keys needed — this is the resolver+catalog+scorer chain on real labels.
"""

import base64, io, json, os, re
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
TEST = os.path.join(HERE, "grocery_test")
CATALOG = os.path.join(DATA, "catalog.json")
INPUTS = os.path.join(TEST, "inputs.json")

# ---------------------------------------------------------------------------
# YOUR TASTE  —  edit this to match you (or tell Claude and it'll set it).
# Default: hop-forward. weights: bigger = stronger "order this" pull.
# ---------------------------------------------------------------------------
TASTE = {
    "liked":    {"ipa": 3, "pale ale": 2, "pilsner": 1, "lager": 1},
    "disliked": {"sour", "wheat"},
    "ideal_abv": 6.5,
    "abv_tolerance": 3.0,
}

# ---------------------------------------------------------------------------
# Style inference from a name/label blob  (mirrors TasteScorer.inferStyle)
# ---------------------------------------------------------------------------
STYLE_KEYWORDS = {
    "ipa":        ["double ipa","west coast","neipa","juicy","hazy","dipa","ipa","hop"],
    "pale ale":   ["pale ale","apa","pale","blonde","cream ale"],
    "lager":      ["lager","helles","vienna","festbier","märzen","oktoberfest","bock"],
    "pilsner":    ["pilsner","pils","kolsch","kölsch"],
    "stout":      ["imperial stout","milk stout","oatmeal","stout"],
    "porter":     ["porter"],
    "wheat":      ["hefeweizen","witbier","white ale","blanche","wheat","hefe","weizen"],
    "sour":       ["berliner","lambic","wild ale","sour","gose","kriek","funk","framboise"],
    "amber":      ["irish red","red ale","amber"],
    "brown ale":  ["nut brown","brown ale","brown"],
    "belgian":    ["belgian","tripel","dubbel","saison","quad","abbey","farmhouse"],
}
def infer_style(text):
    low = (text or "").lower()
    best = None
    for style, kws in STYLE_KEYWORDS.items():
        for kw in kws:
            if kw in low and (best is None or len(kw) > best[1]):
                best = (style, len(kw))
    return best[0] if best else None

ABV_RE = re.compile(r"(\d{1,2}(?:\.\d)?)\s?%")
def extract_abv(text):
    m = ABV_RE.search(text or "")
    if not m: return None
    v = float(m.group(1))
    return v if 0.5 <= v <= 20.0 else None       # plausibility bound (matches Swift)

# ---------------------------------------------------------------------------
# Bundled catalog lookup  (mirrors BundledCatalog: exact -> contains -> token)
# ---------------------------------------------------------------------------
def _norm(s): return re.sub(r"\s{2,}"," ",(s or "").lower().strip())

class Catalog:
    def __init__(self, path=CATALOG):
        self.rows = json.load(open(path)) if os.path.exists(path) else []
        self.exact = {}
        for r in self.rows:
            self.exact.setdefault(_norm(r["name"]), r)
    def lookup(self, text):
        q = _norm(text)
        if not q: return None
        if q in self.exact: return self.exact[q]
        # substring either direction — but only for reasonably specific names,
        # so short generic catalog names ("IPA", "Pils") don't swallow everything.
        for r in self.rows:
            n = _norm(r["name"])
            if len(n) >= 6 and (n in q or q in n):
                return r
        # token overlap fallback: >=2 shared words of length>=4
        qtok = {w for w in re.findall(r"[a-z0-9]+", q) if len(w) >= 4}
        best, bestn = None, 0
        for r in self.rows:
            rtok = {w for w in re.findall(r"[a-z0-9]+", _norm(r["name"])) if len(w) >= 4}
            n = len(qtok & rtok)
            if n > bestn: best, bestn = r, n
        return best if bestn >= 2 else None

# ---------------------------------------------------------------------------
# Resolve (mirrors BeerResolver.resolve) + Score (mirrors TasteScorer.assess)
# ---------------------------------------------------------------------------
def resolve(text, cat):
    printed_style = infer_style(text)
    printed_abv = extract_abv(text)
    hit = cat.lookup(text)
    style = printed_style or (hit and hit.get("coarse"))
    abv = printed_abv or (hit and hit.get("abv"))
    if printed_style:      source = "label text"
    elif hit and hit.get("coarse"): source = "catalog"
    else:                  source = "unresolved"
    return {
        "name": (hit or {}).get("name") or text,
        "brewery": (hit or {}).get("brewery"),
        "style": style, "abv": abv, "source": source,
    }

def score(style, abv):
    s, reasons = 0.0, []
    if style is None:
        s -= 0.5; reasons.append("couldn't tell the style")
    elif style in TASTE["disliked"]:
        s -= 5.0; reasons.append(f"you usually avoid {style}")
    elif style in TASTE["liked"]:
        s += TASTE["liked"][style]; reasons.append(f"matches your love of {style}")
    else:
        s += 0.2
    if abv is not None:
        gap = abs(abv - TASTE["ideal_abv"])
        if gap <= TASTE["abv_tolerance"]:
            s += 0.5
        else:
            s -= min(2.0, 0.5 * (gap - TASTE["abv_tolerance"]))
            reasons.append(f"{abv}% is off your usual strength")
    verdict = "ORDER THIS 👍" if s >= 2.0 else ("your call 🤷" if s >= 0.0 else "skip 👎")
    return verdict, s, ("; ".join(reasons) or "fits your taste")

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
def thumb_data_uri(path):
    if not path or not os.path.exists(path): return None
    try:
        from PIL import Image
        im = Image.open(path); im.thumbnail((420, 420))
        if im.mode not in ("RGB", "L"): im = im.convert("RGB")
        buf = io.BytesIO(); im.save(buf, "JPEG", quality=72)
        return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
    except Exception:
        return None

def run():
    cat = Catalog()
    if not os.path.exists(INPUTS):
        print(f"no inputs yet — drop photos in {TEST}/ and fill {INPUTS}")
        return
    items = json.load(open(INPUTS))
    results = []
    print(f"\n=== Grocery scan test — {len(items)} beers · taste={TASTE['liked']} ===\n")
    for it in items:
        text = it.get("text", "")
        r = resolve(text, cat)
        verdict, s, why = score(r["style"], r["abv"])
        r.update(verdict=verdict, score=s, why=why,
                 photo=it.get("photo"), read=text)
        results.append(r)
        ab = f"{r['abv']}%" if r["abv"] is not None else "—"
        print(f"  {verdict:14s} [{s:+.1f}]  {r['name'][:34]:34s} ({r['style'] or '?'}, {ab}) via {r['source']}")
    # winner across the batch (grocery aisle: what to grab)
    ranked = sorted(results, key=lambda x: (-x["score"],
                    abs((x["abv"] or 99) - TASTE["ideal_abv"]), x["name"].lower()))
    print(f"\n  >>> GRAB THIS: {ranked[0]['name']}  ({ranked[0]['why']})\n")
    write_report(results, ranked[0])

def write_report(results, winner):
    def card(r):
        img = thumb_data_uri(os.path.join(TEST, r["photo"])) if r.get("photo") else None
        imgtag = f'<img src="{img}">' if img else '<div class="noimg">no photo</div>'
        vclass = "order" if "ORDER" in r["verdict"] else ("skip" if "skip" in r["verdict"] else "maybe")
        brew = f' · {r["brewery"]}' if r.get("brewery") else ""
        ab = f'{r["abv"]}%' if r["abv"] is not None else "—"
        star = " 🏆" if r["name"] == winner["name"] else ""
        return f"""<div class="beer">
          <div class="thumb">{imgtag}</div>
          <div class="info">
            <div class="bname">{r['name']}{star}</div>
            <div class="read">camera read: <span>{r['read'] or '—'}</span></div>
            <div class="res">→ {r['style'] or '?'} · {ab} · <em>{r['source']}</em>{brew}</div>
            <span class="verdict {vclass}">{r['verdict']}</span>
            <div class="why">{r['why']}</div>
          </div></div>"""
    cards = "\n".join(card(r) for r in results)
    html = f"""<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0,viewport-fit=cover">
<title>Grocery Scan Results</title><style>
:root{{--amber:#f5a623;--gold:#ffd479;--green:#4ec98a;--red:#e0704f;--muted:#b9a888;--text:#f7efe1;--line:#3d2f16;--card:#241a0c}}
*{{box-sizing:border-box}}body{{margin:0;background:radial-gradient(120% 80% at 50% -10%,#2a1e0b,#1a1206 60%);
color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;line-height:1.5;padding:20px 14px 50px;max-width:560px;margin:0 auto}}
h1{{font-size:22px;margin:0 0 2px}}.sub{{color:var(--muted);font-size:13.5px;margin:0 0 18px}}
.grab{{background:rgba(78,201,138,.12);border:1px solid rgba(78,201,138,.4);border-radius:14px;padding:13px;margin-bottom:16px;font-size:15px}}
.grab b{{color:var(--green)}}
.beer{{display:flex;gap:12px;background:var(--card);border:1px solid var(--line);border-radius:16px;padding:12px;margin:10px 0}}
.thumb{{flex:0 0 92px}}.thumb img{{width:92px;height:120px;object-fit:cover;border-radius:10px;background:#0e0a04}}
.noimg{{width:92px;height:120px;border-radius:10px;background:#0e0a04;border:1px dashed var(--line);display:flex;align-items:center;justify-content:center;color:var(--muted);font-size:11px;text-align:center}}
.info{{flex:1;min-width:0}}.bname{{font-size:17px;font-weight:700;margin-bottom:4px}}
.read{{font-size:12px;color:var(--muted)}}.read span{{font-family:ui-monospace,Menlo,monospace;color:var(--gold)}}
.res{{font-size:12.5px;color:var(--muted);margin:3px 0 8px}}.res em{{color:var(--amber);font-style:normal}}
.verdict{{display:inline-block;font-weight:700;font-size:13.5px;padding:5px 11px;border-radius:999px}}
.order{{background:rgba(78,201,138,.16);color:var(--green)}}.maybe{{background:#3a3320;color:var(--gold)}}.skip{{background:rgba(224,112,79,.16);color:var(--red)}}
.why{{font-size:12.5px;color:var(--muted);margin-top:7px}}.foot{{color:var(--muted);font-size:12px;text-align:center;margin-top:22px}}
</style></head><body>
<h1>Grocery scan results 🍺</h1>
<p class="sub">Your real photos → text read → resolved via the bundled catalog → verdict on your taste.</p>
<div class="grab">🏆 <b>Grab this:</b> {winner['name']} — {winner['why']}</div>
{cards}
<p class="foot">SipCheck · resolver + catalog + scorer on real labels · taste: hop-forward (edit in scan_test.py)</p>
</body></html>"""
    os.makedirs(TEST, exist_ok=True)
    open(os.path.join(TEST, "report.html"), "w").write(html)
    print(f"[wrote {os.path.join(TEST,'report.html')}]")

if __name__ == "__main__":
    run()
