# Grocery scan test — drop zone

**When you have photos:**
1. Put the image files in this folder.
2. Claude reads each one and fills `inputs.json` with `{ "photo": "<file>", "text": "<label text seen>" }`.
3. `python3 ../scan_test.py` → prints verdicts + writes `report.html` (a phone-friendly card per beer).

`inputs.json` currently holds a demo set (incl. the Smog City can) so you can see the format.
Taste profile lives at the top of `scan_test.py` — tell Claude your taste and it'll set it.
