# Motion Lab — frame-by-frame transition verification from a Linux session

How to *feel* SipCheck's animations without a Mac: record the simulator on a
GitHub Actions macOS runner, pull the video + extracted frames over git, and
analyze pixel deltas locally. Built for the design/polish track — screenshots
tell you what a screen looks like; this tells you how it *moves*.

Three pieces (all additive; the existing bridge protocol is unchanged):

| Piece | Where it runs | What it does |
|---|---|---|
| `record` / `flow` bridge actions | E2E Drive session (`scripts/ci_bridge.py`) | Wrap any command batch in a `simctl recordVideo` capture; artifacts arrive in the next state push under `motion/` |
| E2E Motion workflow (`.github/workflows/e2e-motion.yml`) | On demand | Drives a fixed "transition tour" and publishes recordings for every flow to `e2e-artifacts` under `motion/` |
| `scripts/motion_report.py` | Your Linux session | PIL/numpy pixel-diff analysis of pulled frames: flags pops, hard cuts, stalls; writes a markdown report |

## 1. Recording inside a live E2E Drive session

Start a drive session as usual (edit `.drive/request.json` on a `claude/**`
branch, or dispatch "E2E Drive"). Then wrap a batch in a recording — put
`{"do":"record"}` first; it covers every subsequent action in the batch and
auto-stops when the batch ends:

```json
{"seq": N, "actions": [
  {"do": "record", "seconds": 6, "fps": 10, "name": "journal-push"},
  {"do": "tap", "label": "Journal"},
  {"do": "wait", "seconds": 2}
]}
```

- `seconds` — minimum recording length (keeps capturing trailing animation
  even if actions finish early). `fps` — sampled-frame rate (default 10,
  max 15). `name` — artifact directory name. `bursts: false` skips the
  native-fps bursts. `{"do":"record_stop"}` stops mid-batch if you need
  un-recorded actions afterwards.
- Or capture a whole scripted transition in one command:
  `{"seq": N, "actions": [{"do": "flow", "name": "tab_tour"}]}`.
  Known flows: `tab_tour`, `text_verdict`, `save_for_later` (run it right
  after `text_verdict` — it needs a verdict card on screen),
  `journal_detail` (needs `--seed-data`), `onboarding` (relaunches without
  `--isolated-storage` to show the age gate + pages, then restores the
  hermetic launch).
- Also new and generally useful: `{"do": "tap_prefix", "prefix": "beer_"}`
  taps the first accessibility element whose identifier starts with a prefix
  (e.g. seeded journal rows `beer_<uuid>`).

The **next state push** then contains, alongside the usual
`screen.png`/`ui.json`/`meta.json` (meta gains a `"motion": [names]` key):

```
motion/<name>/rec.mp4          # raw video — ground truth, re-slice locally
motion/<name>/frames/f_*.jpg   # sampled at `fps`, half-res jpeg
motion/<name>/bursts/00_tap/   # native-fps burst around each tap/swipe/launch
motion/<name>/motion.json      # video info, action marks (±0.5s), ffprobe
                               # scene-change timeline, frame-timing stats
```

Pull it:

```bash
git fetch origin e2e-bridge-state
git show origin/e2e-bridge-state:meta.json                     # has "motion"
git show origin/e2e-bridge-state:motion/journal-push/motion.json
mkdir -p /tmp/motion && cd /tmp/motion
git --git-dir=/path/to/repo/.git archive origin/e2e-bridge-state motion | tar -x
```

State pushes are single-commit force-pushes: **motion artifacts survive only
until the next state push** — pull them before sending your next command.

## 2. The scripted transition tour (no session needed)

Trigger "E2E Motion" from the Actions tab (input `flows`, default runs all
five), or git-dispatch it from a `claude/**` branch:

```bash
echo '{"flows": "default"}' > .drive/motion-request.json
git add .drive/motion-request.json && git commit -m "motion tour" && git push
```

It builds the app, launches hermetic (`--mock-ai --seed-data
--isolated-storage`), records each flow as a separate video, and force-pushes
to `e2e-artifacts` under `motion/` — **preserving** the scripted E2E lane's
screenshots (and vice versa: `e2e-simulator.yml` preserves `motion/`).

```bash
git fetch origin e2e-artifacts
git show origin/e2e-artifacts:motion/index.json
git show origin/e2e-artifacts:motion/MOTION_SUMMARY.md
git --git-dir=.git archive origin/e2e-artifacts motion | tar -x -C /tmp/motion
```

## 3. Analyzing frames on Linux

```bash
pip install pillow numpy   # only deps
python3 scripts/motion_report.py /tmp/motion/motion/tab_tour/frames \
    --motion-json /tmp/motion/motion/tab_tour/motion.json --out report.md
# bursts are native-fps — pass the video's real rate:
python3 scripts/motion_report.py /tmp/motion/motion/tab_tour/bursts/00_tap --fps 30
```

The report gives an activity sparkline, a motion-segment table (duration,
peak screen-change %, changed-pixel bounding box — "did the tab bar move or
just the card?"), and findings:

- **POP** — single-frame delta towering over its neighbors mid-transition
  (layout jump / flash).
- **CUT** — screen replaced in one frame between two static frames where an
  animated transition was expected. At 10 fps a fast animation can look like
  a cut — confirm against the native-fps burst before filing it.
- **STALL** — a ~0.35–1s run of identical frames splitting one transition
  (animation hitch). Gaps >1s are treated as intentional idle.

For anything the sampled frames can't answer, `rec.mp4` is in the artifact —
re-slice any window locally at native fps:

```bash
ffmpeg -ss 2.8 -t 1.5 -i rec.mp4 -vsync vfr -q:v 4 win/f_%04d.jpg
```

## Timeline reading order

1. `motion.json` → `marks` (when you acted) + `scene_changes` (when pixels
   moved, ffprobe scene scores) → locate the transition.
2. `bursts/NN_<action>/` → the native-fps frames right around that action.
3. `motion_report.py` on frames/bursts → segments + findings.
4. `rec.mp4` → anything else.

## Budgets & guarantees

- Each recording is pruned to ≤12 MB (drop bursts → thin frames → drop
  frames; `rec.mp4` + `motion.json` always survive; `motion.json.pruned`
  says what was cut). Both artifact branches are single-commit force-pushes,
  so size never accumulates.
- Old bridge builds skip unknown actions with a log line — sending `record`
  to a pre-motion session is harmless.
- Recording timestamps: video t=0 is ~0.5–1 s after the `record` action
  executes; `marks` are corrected to video time but only to ~±0.5 s, which is
  why bursts pad 0.3 s before / 1.2 s after each mark.
