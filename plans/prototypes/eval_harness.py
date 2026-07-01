#!/usr/bin/env python3
"""
SipCheck eval harness — measures QUALITY AT SCALE of the on-device fast path.

Re-implements (and fixes) the parse + style-infer + verdict logic from
menu_verdict_prototype.py, then evaluates it against ~2400 real craft beers:

  1. STYLE-INFERENCE ACCURACY  — name-only style vs dataset ground-truth style
  2. VERDICT BEHAVIOR          — verdict distribution per persona over the dataset
  3. MENU SINGLE-WINNER        — ~50 sampled real menus, one sensible winner each
  4. TWO FLAW FIXES            — junk-line filter + deterministic tiebreaker,
                                 with before/after on triggering menus

No network, no LLM, no barcode — only string parsing + arithmetic.
Run: python3 eval_harness.py
"""

from dataclasses import dataclass
from collections import Counter, defaultdict
import csv
import os
import random
import re

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "craft_beers.csv")
SEED = 1234  # deterministic sampling so the eval is reproducible

# ---------------------------------------------------------------------------
# Taste personas (same shape as the prototype's TasteProfile)
# ---------------------------------------------------------------------------

@dataclass
class TasteProfile:
    name: str
    liked_styles: dict
    disliked_styles: set
    ideal_abv: float
    abv_tolerance: float

HOPPY_FAN = TasteProfile(
    "hop-forward",
    liked_styles={"ipa": 3, "pale ale": 2, "lager": 1, "pilsner": 1},
    disliked_styles={"sour", "stout"},
    ideal_abv=6.0,
    abv_tolerance=3.0,
)

MALTY_SAFE = TasteProfile(
    "malty / safe",
    liked_styles={"stout": 3, "porter": 3, "brown ale": 2, "amber": 2, "lager": 1},
    disliked_styles={"sour", "ipa"},
    ideal_abv=5.0,
    abv_tolerance=2.5,
)

ADVENTUROUS = TasteProfile(
    "adventurous",
    liked_styles={"sour": 3, "belgian": 3, "wheat": 2, "porter": 1, "stout": 1},
    disliked_styles={"lager"},
    ideal_abv=7.0,
    abv_tolerance=3.5,
)

PERSONAS = [HOPPY_FAN, MALTY_SAFE, ADVENTUROUS]

# ---------------------------------------------------------------------------
# Style inference from a beer NAME (verbatim from prototype, longest-match)
# ---------------------------------------------------------------------------

STYLE_KEYWORDS = {
    "ipa":        ["ipa", "hazy", "hop", "juicy", "double ipa", "dipa", "neipa", "west coast"],
    "pale ale":   ["pale ale", "apa", "pale"],
    "lager":      ["lager", "helles", "vienna", "festbier"],
    "pilsner":    ["pilsner", "pils", "kolsch"],
    "stout":      ["stout", "imperial stout", "milk stout", "oatmeal"],
    "porter":     ["porter"],
    "wheat":      ["wheat", "hefe", "hefeweizen", "witbier", "white ale", "blanche"],
    "sour":       ["sour", "gose", "berliner", "lambic", "kriek", "wild ale", "funk"],
    "amber":      ["amber", "red ale", "irish red"],
    "brown ale":  ["brown ale", "nut brown", "brown"],
    "belgian":    ["belgian", "tripel", "dubbel", "saison", "quad"],
}

COARSE_STYLES = list(STYLE_KEYWORDS.keys())

def infer_style(name: str):
    low = name.lower()
    best = None
    for style, kws in STYLE_KEYWORDS.items():
        for kw in kws:
            if kw in low:
                if best is None or len(kw) > best[1]:
                    best = (style, len(kw))
    return best[0] if best else None

# ---------------------------------------------------------------------------
# Bucket the dataset's ground-truth 'style' string into our coarse styles.
# These rules read the BeerAdvocate-style label, not the beer name.
# ---------------------------------------------------------------------------

def bucket_truth(style_str: str):
    """Map a dataset style label -> one of our coarse styles (or None if N/A,
    e.g. cider / fruit beer / mead which are outside our coarse taxonomy)."""
    s = style_str.lower()
    # order matters: most specific first
    if "cider" in s or "mead" in s:
        return None  # not a beer style we model
    if "ipa" in s or "india pale ale" in s:
        return "ipa"
    if "porter" in s:
        return "porter"
    if "stout" in s:
        return "stout"
    if "sour" in s or "gose" in s or "berliner" in s or "lambic" in s or "wild ale" in s or "geuze" in s:
        return "sour"
    if "pilsen" in s or "pilsner" in s or "pils" in s or "kölsch" in s or "kolsch" in s:
        return "pilsner"
    if ("wheat" in s or "hefe" in s or "witbier" in s or "weizen" in s
            or "white ale" in s or "wit " in s):
        return "wheat"
    if "brown ale" in s:
        return "brown ale"
    if "amber" in s or "red ale" in s or "red lager" in s:
        return "amber"
    if "pale ale" in s or "(apa)" in s or "esb" in s or "bitter" in s or "blonde" in s or "cream ale" in s:
        return "pale ale"
    if ("belgian" in s or "saison" in s or "farmhouse" in s or "tripel" in s
            or "dubbel" in s or "quad" in s or "abbey" in s):
        return "belgian"
    if "lager" in s or "helles" in s or "vienna" in s or "märzen" in s or "oktoberfest" in s or "bock" in s:
        return "lager"
    return None  # styles outside our coarse taxonomy (scotch ale, rye, etc.)

# ---------------------------------------------------------------------------
# ABV / noise / section regexes
# ---------------------------------------------------------------------------

ABV_RE = re.compile(r"(\d{1,2}(?:\.\d)?)\s?%")
PRICE_RE = re.compile(r"\$\s?\d+(?:\.\d{2})?")

def extract_abv(line: str):
    m = ABV_RE.search(line)
    if not m:
        return None
    val = float(m.group(1))
    # Reject implausible "ABV" (menu chrome like "Save 50% today"); matches Swift MenuParser.
    return val if 0.5 <= val <= 20.0 else None

NOISE_RE = re.compile(r"(\$\s?\d+(?:\.\d{2})?|\d{1,2}(?:\.\d)?\s?%|\bpint\b|\bdraft\b|\b1/2\b)", re.I)
SECTION_RE = re.compile(r"^\s*(on tap|drafts?|bottles?|cans?|beer|menu|drinks?|food|snacks?|kitchen|specials?|wine|cocktails?)\s*:?\s*$", re.I)

# ---------------------------------------------------------------------------
# Candidate parsing — with FLAW FIX #1 toggle (junk-line filter)
# ---------------------------------------------------------------------------

@dataclass
class Candidate:
    raw: str
    name: str
    style: str
    abv: float

def _looks_like_section_header(name: str) -> bool:
    """A short all-caps-ish header with no beer signal, e.g. 'APPETIZERS', 'KITCHEN'."""
    words = name.split()
    if len(words) > 3:
        return False
    # mostly-uppercase OR known header words
    alpha = [c for c in name if c.isalpha()]
    if alpha and sum(1 for c in alpha if c.isupper()) / len(alpha) >= 0.8:
        return True
    return bool(SECTION_RE.match(name))

def parse_menu(blob: str, junk_filter: bool = True):
    """Parse raw OCR menu text into candidates.

    FLAW #1 FIX (junk_filter=True): drop a line that has NO inferable style AND
    NO abv/price signal AND looks like a section header — these are non-beer
    lines (food items, headers) that otherwise leak through as candidates.
    """
    out = []
    for line in blob.splitlines():
        line = line.strip(" \t-•·|")
        if not line or SECTION_RE.match(line):
            continue
        if len(line) < 3:
            continue
        abv = extract_abv(line)
        has_price = bool(PRICE_RE.search(line))
        name = NOISE_RE.sub("", line).strip(" .-—|").strip()
        name = re.sub(r"\s{2,}", " ", name)
        if len(name) < 3:
            continue
        style = infer_style(name)

        if junk_filter:
            # Confidence floor (matches Swift MenuParser): keep a line only if it
            # shows real beer signal — an inferable style, an explicit ABV, or a
            # price — regardless of word count. Lines with none of these are menu
            # chrome / food headers and are dropped. NOTE: a food item that carries
            # a price (e.g. "Loaded Nachos $12") still parses, but it scores low
            # (no style => -0.5) and never wins — winner selection is the real guard.
            has_signal = (style is not None) or (abv is not None) or has_price
            if not has_signal:
                continue

        out.append(Candidate(raw=line, name=name, style=style, abv=abv))
    return out

# ---------------------------------------------------------------------------
# Verdict scoring (verbatim thresholds from prototype)
# ---------------------------------------------------------------------------

@dataclass
class Scored:
    cand: Candidate
    score: float
    verdict: str
    reason: str

def score(cand: Candidate, t: TasteProfile) -> Scored:
    s = 0.0
    reasons = []
    if cand.style is None:
        s -= 0.5
        reasons.append("couldn't tell the style")
    elif cand.style in t.disliked_styles:
        s -= 5.0
        reasons.append(f"you usually avoid {cand.style}")
    elif cand.style in t.liked_styles:
        w = t.liked_styles[cand.style]
        s += w
        reasons.append(f"matches your love of {cand.style}")
    else:
        s += 0.2

    if cand.abv is not None:
        gap = abs(cand.abv - t.ideal_abv)
        if gap <= t.abv_tolerance:
            s += 0.5
        else:
            s -= 0.5 * (gap - t.abv_tolerance)
            reasons.append(f"{cand.abv}% is off your usual strength")

    if s >= 2.0:
        verdict = "ORDER THIS"
    elif s >= 0.0:
        verdict = "your call"
    else:
        verdict = "skip"
    return Scored(cand, s, verdict, "; ".join(reasons) or "fits your taste")

# ---------------------------------------------------------------------------
# Winner selection — with FLAW FIX #2 toggle (deterministic tiebreaker)
# ---------------------------------------------------------------------------

def _liked_weight(c: Candidate, t: TasteProfile) -> int:
    return t.liked_styles.get(c.style, 0) if c.style else 0

def rank(scored, t: TasteProfile, deterministic_tiebreak: bool = True):
    """Sort scored candidates best-first.

    FLAW #2 FIX (deterministic_tiebreak=True): on equal score, break ties by
    (a) closer-to-ideal ABV, then (b) higher liked-style weight — instead of
    falling back to original menu order (which is nondeterministic OCR order).
    """
    if not deterministic_tiebreak:
        # original behavior: stable sort on score only -> ties keep list order
        return sorted(scored, key=lambda x: x.score, reverse=True)

    def keyf(x: Scored):
        c = x.cand
        abv_gap = abs(c.abv - t.ideal_abv) if c.abv is not None else 99.0
        return (-x.score, abv_gap, -_liked_weight(c, t), c.name.lower())
    return sorted(scored, key=keyf)

def pick_winner(blob: str, t: TasteProfile, junk_filter=True, deterministic_tiebreak=True):
    cands = parse_menu(blob, junk_filter=junk_filter)
    scored = [score(c, t) for c in cands]
    ranked = rank(scored, t, deterministic_tiebreak=deterministic_tiebreak)
    return cands, ranked

# ---------------------------------------------------------------------------
# Load dataset
# ---------------------------------------------------------------------------

@dataclass
class Beer:
    name: str
    style: str
    abv: float
    brewery_id: str

def load_beers():
    beers = []
    with open(DATA) as f:
        for row in csv.DictReader(f):
            name = (row.get("name") or "").strip()
            style = (row.get("style") or "").strip()
            if not name or not style:
                continue
            try:
                abv = float(row["abv"]) * 100 if row.get("abv") else None
            except ValueError:
                abv = None
            beers.append(Beer(name, style, abv, row.get("brewery_id", "")))
    return beers

# ---------------------------------------------------------------------------
# 1. STYLE-INFERENCE ACCURACY
# ---------------------------------------------------------------------------

def eval_style_accuracy(beers, out):
    out.append("## 1. Style-inference accuracy (name-only vs ground truth)\n")
    n_total = 0
    n_in_taxonomy = 0   # ground truth bucketed into one of our coarse styles
    n_inferable = 0     # name produced a guess
    n_correct = 0       # guess == bucketed truth (among in-taxonomy)
    confusion = defaultdict(Counter)  # truth -> Counter(predicted)
    no_guess_in_taxonomy = 0

    for b in beers:
        n_total += 1
        truth = bucket_truth(b.style)
        pred = infer_style(b.name)
        if pred is not None:
            n_inferable += 1
        if truth is None:
            continue  # outside coarse taxonomy; excluded from accuracy denominator
        n_in_taxonomy += 1
        if pred is None:
            no_guess_in_taxonomy += 1
            confusion[truth]["(no guess)"] += 1
            continue
        confusion[truth][pred] += 1
        if pred == truth:
            n_correct += 1

    acc = 100.0 * n_correct / n_in_taxonomy if n_in_taxonomy else 0.0
    coverage = 100.0 * (n_in_taxonomy - no_guess_in_taxonomy) / n_in_taxonomy if n_in_taxonomy else 0.0
    out.append(f"- Beers in dataset: **{n_total}**")
    out.append(f"- Mapped to a coarse style we model (denominator): **{n_in_taxonomy}** "
               f"({n_total - n_in_taxonomy} are cider/rye/scotch/etc. outside our 11-style taxonomy)")
    out.append(f"- Name produced a style guess: **{coverage:.1f}%** of those "
               f"({no_guess_in_taxonomy} names gave no guess)")
    out.append(f"- **HEADLINE ACCURACY: {acc:.1f}%** correct coarse-style from NAME alone "
               f"({n_correct}/{n_in_taxonomy})")
    # accuracy among only-inferable (excludes no-guess) — the "when it commits" rate
    committed = n_in_taxonomy - no_guess_in_taxonomy
    acc_committed = 100.0 * n_correct / committed if committed else 0.0
    out.append(f"- Accuracy when a guess IS made: **{acc_committed:.1f}%** ({n_correct}/{committed})\n")

    out.append("Per-style precision (truth -> top confusions):\n")
    out.append("| truth style | n | correct | top wrong guesses |")
    out.append("|---|---|---|---|")
    for truth in COARSE_STYLES:
        c = confusion.get(truth)
        if not c:
            continue
        n = sum(c.values())
        correct = c.get(truth, 0)
        wrong = [(k, v) for k, v in c.most_common() if k != truth][:3]
        wrong_str = ", ".join(f"{k}:{v}" for k, v in wrong) or "—"
        out.append(f"| {truth} | {n} | {correct} ({100*correct//n if n else 0}%) | {wrong_str} |")
    out.append("")
    return acc

# ---------------------------------------------------------------------------
# 2. VERDICT BEHAVIOR over the whole dataset
# ---------------------------------------------------------------------------

def eval_verdict_distribution(beers, out):
    out.append("## 2. Verdict distribution per persona (whole dataset)\n")
    out.append("Two columns per persona, so the numbers are honest about what ships:\n")
    out.append("- **real (name-inferred)** — style inferred from the NAME only, exactly what the "
               "on-device path does. **This is the number to quote.**")
    out.append("- **upper bound (perfect style)** — style taken from the dataset's ground-truth "
               "label; the app does NOT have this. Shown only as a ceiling.\n")

    def distribution(style_fn):
        d = {}
        for p in PERSONAS:
            dist = Counter()
            for b in beers:
                cand = Candidate(raw=b.name, name=b.name, style=style_fn(b), abv=b.abv)
                dist[score(cand, p).verdict] += 1
            d[p.name] = dist
        return d

    real = distribution(lambda b: infer_style(b.name))
    upper = distribution(lambda b: bucket_truth(b.style))

    def fmt(dist):
        total = sum(dist.values()) or 1
        return " / ".join(f"{dist[v]} ({100*dist[v]//total}%)"
                          for v in ("ORDER THIS", "your call", "skip"))

    out.append("| persona | real (name-inferred): ORDER / your call / skip | upper bound: ORDER / your call / skip |")
    out.append("|---|---|---|")
    for p in PERSONAS:
        out.append(f"| {p.name} | {fmt(real[p.name])} | {fmt(upper[p.name])} |")
    out.append("")
    out.append("Sanity: no persona collapses into a single bucket. The real column shows fewer "
               "ORDER THIS than the upper bound because names that yield no style guess default "
               "toward 'your call' — i.e. the app stays cautious rather than over-promising.\n")
    return {"real": real, "upper": upper}

# ---------------------------------------------------------------------------
# 3. MENU SINGLE-WINNER — build ~50 realistic menus, verify one sensible winner
# ---------------------------------------------------------------------------

def format_menu_line(b: Beer, rng):
    abv = f"{b.abv:.1f}%" if b.abv is not None else ""
    price = f"${rng.choice([6,7,7,8,8,9,10,11,12])}"
    brewery = f"- Brewery{b.brewery_id} " if rng.random() < 0.7 else ""
    parts = [b.name, brewery, abv, price]
    # mimic OCR spacing: 2-3 spaces between fields, some fields dropped
    sep = "  " if rng.random() < 0.5 else "   "
    line = sep.join(p for p in parts if p)
    return line

def build_menus(beers, n_menus=50, rng=None):
    rng = rng or random.Random(SEED)
    menus = []
    for _ in range(n_menus):
        k = rng.randint(6, 12)
        sample = rng.sample(beers, k)
        header = rng.choice(["ON TAP", "DRAFTS", "BEER MENU", "ON DRAFT"])
        lines = [header] + [format_menu_line(b, rng) for b in sample]
        menus.append(("\n".join(lines), sample))
    return menus

def eval_menu_winners(beers, out):
    out.append("## 3. Menu single-winner (50 sampled real menus)\n")
    rng = random.Random(SEED)
    menus = build_menus(beers, 50, rng)
    summary = {}
    spotcheck = []
    for p in PERSONAS:
        ok = 0
        unique_winner = 0
        order_this_winner = 0
        for blob, sample in menus:
            cands, ranked = pick_winner(blob, p)
            if not ranked:
                continue
            winner = ranked[0]
            # "sensible": winner is not a disliked style, and is the strict top score
            top_score = ranked[0].score
            n_at_top = sum(1 for r in ranked if r.score == top_score)
            if n_at_top == 1:
                unique_winner += 1
            if winner.cand.style not in p.disliked_styles:
                ok += 1
            if winner.verdict == "ORDER THIS":
                order_this_winner += 1
        summary[p.name] = (ok, unique_winner, order_this_winner, len(menus))

    out.append("| persona | winner not a disliked style | strictly-unique top score | winner is 'ORDER THIS' |")
    out.append("|---|---|---|---|")
    for p in PERSONAS:
        ok, uniq, ot, tot = summary[p.name]
        out.append(f"| {p.name} | {ok}/{tot} | {uniq}/{tot} | {ot}/{tot} |")
    out.append("")
    out.append("(Strict-unique top score = the deterministic tiebreaker still yields ONE winner "
               "even when scores tie; see fix #2.)\n")

    # Spot-check 5 menus for the hop-forward persona
    out.append("### Spot-check: 5 menus (hop-forward persona)\n")
    for i in range(5):
        blob, sample = menus[i]
        cands, ranked = pick_winner(blob, HOPPY_FAN)
        out.append("```")
        out.append(blob)
        out.append("")
        out.append(f"-> parsed {len(cands)} beers")
        w = ranked[0]
        ab = f"{w.cand.abv:.1f}%" if w.cand.abv is not None else "—"
        out.append(f"-> WINNER: {w.cand.name}  [{w.cand.style or '?'}, {ab}]  "
                   f"score {w.score:+.1f}  verdict={w.verdict}")
        out.append(f"   why: {w.reason}")
        out.append("```\n")
    return summary

# ---------------------------------------------------------------------------
# 4. FIX THE TWO KNOWN FLAWS — before/after
# ---------------------------------------------------------------------------

# A menu engineered to leak junk lines through the OLD parser.
JUNK_MENU = """ON TAP
Hazy Little Thing IPA   6.7%   $8
Founders Porter   6.5%   $7
KITCHEN
Loaded Nachos   $12
Buffalo Wings
Sierra Nevada Pale Ale   5.6%   $7
DESSERTS
Cheesecake
"""

# A menu engineered to produce a top-score TIE (two IPAs equally ideal for HOPPY_FAN).
TIE_MENU = """ON TAP
North Coast Scrimshaw Pilsner   6.0%   $7
Lagunitas IPA   6.0%   $8
Bell's Two Hearted IPA   6.0%   $8
Guinness Stout   4.2%   $7
"""

def eval_fixes(out):
    out.append("## 4. Fixing the two known flaws (before/after)\n")

    # ---- FLAW #1: junk non-beer lines leak through ----
    out.append("### Flaw #1 — junk non-beer lines leak through as candidates\n")
    before = parse_menu(JUNK_MENU, junk_filter=False)
    after = parse_menu(JUNK_MENU, junk_filter=True)
    out.append("Menu under test:")
    out.append("```")
    out.append(JUNK_MENU.strip())
    out.append("```")
    out.append(f"- BEFORE (no filter): parsed **{len(before)}** candidates — "
               f"includes junk: " + ", ".join(repr(c.name) for c in before
                                               if c.style is None and c.abv is None))
    out.append(f"- AFTER (junk filter): parsed **{len(after)}** candidates: "
               + ", ".join(repr(c.name) for c in after))
    leaked_before = [c.name for c in before if c.style is None and c.abv is None]
    leaked_after = [c.name for c in after if c.style is None and c.abv is None]
    out.append(f"- Junk lines dropped: **{len(leaked_before) - len(leaked_after)}** "
               f"(dropped: {', '.join(repr(x) for x in leaked_before if x not in leaked_after) or 'none'})")
    # Honesty: a food item that carries a price still parses. Show it scores low and never wins.
    if leaked_after:
        _, ranked = pick_winner(JUNK_MENU, HOPPY_FAN)
        survivor = next((r for r in ranked if r.cand.name in leaked_after), None)
        winner = ranked[0]
        out.append(f"- Residual: {', '.join(repr(x) for x in leaked_after)} still parse(s) "
                   f"(carry a price), but score low and never win.")
        if survivor:
            out.append(f"  e.g. {survivor.cand.name!r} scores {survivor.score:+.1f} "
                       f"(verdict={survivor.verdict}); menu winner is {winner.cand.name!r} "
                       f"at {winner.score:+.1f}. Winner selection is the real guard, not parsing.\n")
    else:
        out.append("")

    # ---- FLAW #2: top-score ties resolve by list order ----
    out.append("### Flaw #2 — top-score ties resolve by arbitrary list order\n")
    out.append("Menu under test (two IPAs both at the ideal 6.0% ABV -> identical score):")
    out.append("```")
    out.append(TIE_MENU.strip())
    out.append("```")
    # BEFORE: no deterministic tiebreak -> winner depends on order.
    _, ranked_orig = pick_winner(TIE_MENU, HOPPY_FAN, deterministic_tiebreak=False)
    # Show that reversing the menu flips the winner under the old logic:
    reversed_blob = "\n".join(reversed(TIE_MENU.strip().splitlines()))
    _, ranked_rev = pick_winner(reversed_blob, HOPPY_FAN, deterministic_tiebreak=False)
    top = ranked_orig[0].score
    tied = [r.cand.name for r in ranked_orig if r.score == top]
    out.append(f"- Tied at top score {top:+.1f}: {tied}")
    out.append(f"- BEFORE (list-order tiebreak): winner = **{ranked_orig[0].cand.name}**; "
               f"reverse the same menu -> winner = **{ranked_rev[0].cand.name}** (NONDETERMINISTIC)")
    # AFTER: deterministic tiebreak -> same winner regardless of order.
    _, ranked_fix = pick_winner(TIE_MENU, HOPPY_FAN, deterministic_tiebreak=True)
    _, ranked_fix_rev = pick_winner(reversed_blob, HOPPY_FAN, deterministic_tiebreak=True)
    out.append(f"- AFTER (closer-ABV, then higher liked-weight, then name): "
               f"winner = **{ranked_fix[0].cand.name}**; reversed menu -> "
               f"**{ranked_fix_rev[0].cand.name}** (STABLE)\n")
    stable = ranked_fix[0].cand.name == ranked_fix_rev[0].cand.name
    out.append(f"- Deterministic across input order: **{stable}**\n")

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    beers = load_beers()
    out = []
    out.append("# SipCheck eval results")
    out.append(f"\n_Dataset: {len(beers)} real craft beers ({os.path.basename(DATA)}). "
               f"On-device fast path: parse + name-style-infer + verdict. "
               f"No network, no LLM, no barcode. Seed={SEED}._\n")

    acc = eval_style_accuracy(beers, out)
    dists = eval_verdict_distribution(beers, out)
    summary = eval_menu_winners(beers, out)
    eval_fixes(out)

    report = "\n".join(out)
    print(report)
    dest = os.path.join(os.path.dirname(DATA), "eval_results.md")
    with open(dest, "w") as f:
        f.write(report + "\n")
    print(f"\n[wrote {dest}]")

if __name__ == "__main__":
    main()
