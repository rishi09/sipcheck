#!/usr/bin/env python3
"""
SipCheck prototype — validates the riskiest product claim:

  "From a messy photographed beer MENU (no barcode, no network), can we pick
   ONE good 'order this' beer, instantly, using only the user's taste library?"

This is a *logic* validation of the on-device fast path. It deliberately uses
NO barcode, NO network, NO LLM — only string parsing + arithmetic, the kind of
thing that runs in <1ms on-device. If this picks sensible winners on realistic
menu text, the core experience the user asked for is viable. The real app would
port this logic to Swift (Vision OCR text -> this parser -> verdict).

Run: python3 menu_verdict_prototype.py
"""

from dataclasses import dataclass, field
import re

# ---------------------------------------------------------------------------
# 1. Taste library  (what the "quick taste quiz" + rating history produce)
# ---------------------------------------------------------------------------

@dataclass
class TasteProfile:
    liked_styles: dict          # style -> weight (from quiz + 👍 history)
    disliked_styles: set        # hard avoids (from quiz dislikes + 👎)
    ideal_abv: float            # sweet spot
    abv_tolerance: float        # how far from ideal before it counts against

# Example: a hop-forward drinker who hates sour, likes moderate ABV.
# (This is exactly what the "quick taste quiz" captures on first launch.)
HOPPY_FAN = TasteProfile(
    liked_styles={"ipa": 3, "pale ale": 2, "lager": 1, "pilsner": 1},
    disliked_styles={"sour", "stout"},
    ideal_abv=6.0,
    abv_tolerance=3.0,
)

# A second persona to prove the same code personalizes, not hard-codes a winner.
MALTY_SAFE = TasteProfile(
    liked_styles={"stout": 3, "porter": 3, "brown ale": 2, "amber": 2, "lager": 1},
    disliked_styles={"sour", "ipa"},
    ideal_abv=5.0,
    abv_tolerance=2.5,
)

# ---------------------------------------------------------------------------
# 2. Style inference from a beer NAME  (no database, no network)
#    Keyword map — beer names almost always telegraph style.
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

def infer_style(name: str) -> str | None:
    low = name.lower()
    # check longest/most-specific keywords first
    best = None
    for style, kws in STYLE_KEYWORDS.items():
        for kw in kws:
            if kw in low:
                if best is None or len(kw) > best[1]:
                    best = (style, len(kw))
    return best[0] if best else None

ABV_RE = re.compile(r"(\d{1,2}(?:\.\d)?)\s?%")

def extract_abv(line: str) -> float | None:
    m = ABV_RE.search(line)
    return float(m.group(1)) if m else None

# ---------------------------------------------------------------------------
# 3. Parse a raw OCR menu blob -> candidate beers
#    Real menus are noisy: name + brewery + ABV + price, wrapped lines, $.
# ---------------------------------------------------------------------------

@dataclass
class Candidate:
    raw: str
    name: str
    style: str | None
    abv: float | None

NOISE_RE = re.compile(r"(\$\s?\d+(?:\.\d{2})?|\d{1,2}(?:\.\d)?\s?%|\bpint\b|\bdraft\b|\b1/2\b)", re.I)
SECTION_RE = re.compile(r"^\s*(on tap|drafts?|bottles?|cans?|beer|menu|drinks?)\s*:?\s*$", re.I)

def parse_menu(blob: str) -> list[Candidate]:
    out = []
    for line in blob.splitlines():
        line = line.strip(" \t-•·|")
        if not line or SECTION_RE.match(line):
            continue
        if len(line) < 3:
            continue
        abv = extract_abv(line)
        name = NOISE_RE.sub("", line).strip(" .-—|").strip()
        # collapse trailing brewery dashes / multiple spaces
        name = re.sub(r"\s{2,}", " ", name)
        if len(name) < 3:
            continue
        style = infer_style(name)
        out.append(Candidate(raw=line, name=name, style=style, abv=abv))
    return out

# ---------------------------------------------------------------------------
# 4. Heuristic verdict — score a candidate against the taste library.
#    THIS is the "instant, free, offline" verdict. Pure arithmetic.
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
        s += 0.2  # neutral / unknown-but-not-disliked

    if cand.abv is not None:
        gap = abs(cand.abv - t.ideal_abv)
        if gap <= t.abv_tolerance:
            s += 0.5
        else:
            s -= 0.5 * (gap - t.abv_tolerance)
            reasons.append(f"{cand.abv}% is off your usual strength")

    if s >= 2.0:
        verdict = "ORDER THIS 👍"
    elif s >= 0.0:
        verdict = "your call 🤷"
    else:
        verdict = "skip 👎"

    return Scored(cand, s, verdict, "; ".join(reasons) or "fits your taste")

def pick_winner(blob: str, t: TasteProfile):
    cands = parse_menu(blob)
    scored = sorted((score(c, t) for c in cands), key=lambda x: x.score, reverse=True)
    return cands, scored

# ---------------------------------------------------------------------------
# 5. Realistic test menus (typical of what Vision OCR would emit from a photo)
# ---------------------------------------------------------------------------

MENU_RESTAURANT = """
ON TAP
Pliny the Elder - Russian River Double IPA  8.0%  $9
Sierra Nevada Pale Ale   5.6%   $7
Guinness Draught Stout   4.2%   $7
Allagash White (Belgian Wheat)   5.0%   $8
Founders Breakfast Stout   8.3%   $10
Firestone 805 Blonde Ale   4.7%   $6
Pizza Port Swami's IPA   6.8%   $8
"""

MENU_CHALKBOARD = """
drafts
hazy lil thing ipa 6.7
modelo especial lager 4.4
old rasputin imperial stout 9
the crisp pilsner 5.2
goose island sofie saison 6.5
"""

MENU_GROCERY_SHELF = """  # OCR off a cooler door — sparse, no ABV/price
Voodoo Ranger Juicy Haze IPA
Blue Moon Belgian White
Coors Light
Lagunitas Sumpin Sour Ale
Deschutes Black Butte Porter
"""

def run(label, blob, profile, profile_name):
    print(f"\n{'='*70}\n{label}   (taste profile: {profile_name})\n{'='*70}")
    cands, scored = pick_winner(blob, profile)
    print(f"parsed {len(cands)} beers from menu text\n")
    for sc in scored:
        st = sc.cand.style or "?"
        ab = f"{sc.cand.abv}%" if sc.cand.abv is not None else "—"
        print(f"  {sc.verdict:14s} [{sc.score:+.1f}]  {sc.cand.name[:42]:42s} ({st}, {ab})")
    winner = scored[0]
    print(f"\n  >>> ONE CLEAR WINNER: {winner.cand.name}")
    print(f"      why: {winner.reason}")

if __name__ == "__main__":
    run("RESTAURANT MENU", MENU_RESTAURANT, HOPPY_FAN, "hop-forward")
    run("CHALKBOARD",      MENU_CHALKBOARD, HOPPY_FAN, "hop-forward")
    run("GROCERY SHELF",   MENU_GROCERY_SHELF, HOPPY_FAN, "hop-forward")
    # same restaurant menu, opposite palate — proves it personalizes:
    run("RESTAURANT MENU", MENU_RESTAURANT, MALTY_SAFE, "malty / safe")
