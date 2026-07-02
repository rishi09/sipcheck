#!/usr/bin/env python3
"""Frame-by-frame motion analysis for SipCheck simulator recordings.

Runs on LINUX (or anywhere) against a directory of frames pulled from the
`e2e-bridge-state` (motion/<name>/frames) or `e2e-artifacts`
(motion/<flow>/frames or bursts/<n>) branches. Pure PIL + numpy — no ffmpeg
needed here (re-slicing the mp4 is optional and separate).

What it flags (design/polish signal, not pass/fail truth):
  POP    — a single frame whose pixel delta towers over its neighbors in the
           middle of an otherwise smooth transition (layout jump, flash).
  CUT    — the screen is mostly replaced between two frames that are static
           on both sides: a hard cut where an animated transition was likely
           intended (only meaningful at burst/native fps; at low sample fps
           a fast animation legitimately looks like a cut — check a burst).
  STALL  — a run of visually identical frames splitting two active spans of
           the same transition: the animation hitched mid-flight.

Usage:
  python3 scripts/motion_report.py <frames_dir> \
      [--motion-json motion.json] [--fps N] [--out report.md]

  frames_dir     directory of f_*.jpg/png, lexicographic order = time order
  --motion-json  the recording's motion.json (adds real fps, action marks,
                 and scene-change context to the report)
  --fps          frame rate of the sequence if no motion.json (default 10;
                 for bursts use the video's native fps from video_info)
  --out          write the markdown report here (default: stdout)

Exit code: 0 always (findings are advisory). Deps: pip install pillow numpy
"""

import argparse
import json
import math
import os
import sys

try:
    import numpy as np
    from PIL import Image
except ImportError as e:
    sys.exit(f"motion_report needs pillow + numpy: {e}\n"
             f"  pip install pillow numpy")

ANALYSIS_WIDTH = 360        # downscale width for speed / noise suppression
PIXEL_CHANGE_THRESH = 12    # 0-255 gray delta for a pixel to count as changed
ACTIVE_FRAC = 0.002         # changed-pixel fraction => "something is moving"
CUT_FRAC = 0.45             # changed-pixel fraction => "screen replaced"
POP_RATIO = 4.0             # delta vs neighbor median to call a pop
POP_MIN_FRAC = 0.03         # a pop must also move at least this much screen
STALL_MIN_S = 0.35          # dead time inside a transition to call a stall
MAX_GAP_MERGE = 2           # frames of quiet tolerated inside one segment


def load_gray(path):
    img = Image.open(path).convert("L")
    if img.width > ANALYSIS_WIDTH:
        h = max(int(img.height * ANALYSIS_WIDTH / img.width), 1)
        img = img.resize((ANALYSIS_WIDTH, h), Image.BILINEAR)
    return np.asarray(img, dtype=np.float32)


def pair_stats(a, b):
    """(mean_abs_delta, changed_fraction, bbox-or-None) for a frame pair."""
    d = np.abs(a - b)
    changed = d > PIXEL_CHANGE_THRESH
    frac = float(changed.mean())
    bbox = None
    if changed.any():
        ys, xs = np.where(changed)
        bbox = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))
    return float(d.mean()), frac, bbox


def segments_from(active, max_gap=MAX_GAP_MERGE):
    """Merge runs of active pair-indices (gaps <= max_gap) into segments."""
    segs = []
    start = prev = None
    for i, on in enumerate(active):
        if on:
            if start is None:
                start = i
            prev = i
        elif start is not None and i - prev > max_gap:
            segs.append((start, prev))
            start = prev = None
    if start is not None:
        segs.append((start, prev))
    return segs


def fname_ref(names, pair_idx):
    """A pair index i is the transition names[i] -> names[i+1]."""
    return f"{names[pair_idx]} -> {names[pair_idx + 1]}"


def sparkline(values, width=60):
    if not values:
        return ""
    blocks = " ▁▂▃▄▅▆▇█"
    step = max(len(values) / width, 1)
    peak = max(values) or 1
    out = []
    i = 0.0
    while int(i) < len(values):
        chunk = values[int(i):int(i + step)] or [0]
        out.append(blocks[min(int(max(chunk) / peak * 8), 8)])
        i += step
    return "".join(out)


def analyze(frames_dir, fps, motion=None):
    names = sorted(f for f in os.listdir(frames_dir)
                   if f.lower().endswith((".jpg", ".jpeg", ".png")))
    if len(names) < 3:
        return names, [], [], []
    imgs = [load_gray(os.path.join(frames_dir, n)) for n in names]
    shapes = {im.shape for im in imgs}
    if len(shapes) > 1:  # e.g. rotation mid-recording; keep the majority
        from collections import Counter
        keep = Counter(im.shape for im in imgs).most_common(1)[0][0]
        pairs_ok = [im.shape == keep for im in imgs]
        imgs = [im for im, ok in zip(imgs, pairs_ok) if ok]
        names = [n for n, ok in zip(names, pairs_ok) if ok]

    stats = [pair_stats(imgs[i], imgs[i + 1]) for i in range(len(imgs) - 1)]
    deltas = [s[0] for s in stats]
    fracs = [s[1] for s in stats]
    active = [f > ACTIVE_FRAC for f in fracs]
    segs = segments_from(active)

    findings = []
    stall_pairs = max(int(math.ceil(STALL_MIN_S * fps)), 2)

    for (s, e) in segs:
        seg_deltas = deltas[s:e + 1]
        # POP: one pair towers over its in-segment neighbors. A popped frame
        # produces two big deltas (entering + leaving it) — merge adjacent.
        if len(seg_deltas) >= 3:
            last_pop = -10
            for i in range(s, e + 1):
                neigh = [deltas[j] for j in range(max(s, i - 3),
                                                  min(e, i + 3) + 1) if j != i]
                med = sorted(neigh)[len(neigh) // 2] if neigh else 0
                if (fracs[i] >= POP_MIN_FRAC and med > 0
                        and deltas[i] > POP_RATIO * med):
                    if i - last_pop > 1:
                        findings.append(
                            ("POP", i,
                             f"single-frame jump ({fracs[i]:.0%} of screen, "
                             f"delta {deltas[i]:.1f} vs neighbor median "
                             f"{med:.1f}) at {fname_ref(names, i)}"))
                    last_pop = i
        # CUT: screen mostly replaced in one pair, quiet on both sides.
        for i in range(s, e + 1):
            before = fracs[i - 1] if i > 0 else 0
            after = fracs[i + 1] if i + 1 < len(fracs) else 0
            if (fracs[i] >= CUT_FRAC and before < ACTIVE_FRAC * 4
                    and after < ACTIVE_FRAC * 4):
                findings.append(
                    ("CUT", i,
                     f"screen replaced in one frame ({fracs[i]:.0%} changed, "
                     f"static on both sides) at {fname_ref(names, i)} — "
                     f"expected an animated transition? verify against a "
                     f"native-fps burst before judging at low sample fps"))

    # STALL: a short dead gap splitting two active segments — the animation
    # hitched mid-flight. Longer gaps (> ~1s) are treated as intentional
    # idle between separate interactions, not a hitch.
    for (s1, e1), (s2, _e2) in zip(segs, segs[1:]):
        gap_pairs = s2 - e1 - 1
        if stall_pairs <= gap_pairs and gap_pairs / fps <= 1.0:
            findings.append(
                ("STALL", e1 + 1,
                 f"animation hitched for ~{gap_pairs / fps:.2f}s "
                 f"({gap_pairs} identical frames) between active spans, "
                 f"starting at {fname_ref(names, e1 + 1)}"))

    seg_rows = []
    for (s, e) in segs:
        dur = (e - s + 1) / fps
        peak = max(fracs[s:e + 1])
        bboxes = [stats[i][2] for i in range(s, e + 1) if stats[i][2]]
        if bboxes:
            bb = (min(b[0] for b in bboxes), min(b[1] for b in bboxes),
                  max(b[2] for b in bboxes), max(b[3] for b in bboxes))
            region = f"x{bb[0]}-{bb[2]} y{bb[1]}-{bb[3]} (of {imgs[0].shape[1]}x{imgs[0].shape[0]})"
        else:
            region = "-"
        seg_rows.append((names[s], names[min(e + 1, len(names) - 1)],
                         dur, peak, region))

    return names, deltas, seg_rows, findings


def main():
    p = argparse.ArgumentParser()
    p.add_argument("frames_dir")
    p.add_argument("--motion-json", default=None)
    p.add_argument("--fps", type=float, default=None)
    p.add_argument("--out", default=None)
    args = p.parse_args()

    motion = None
    if args.motion_json and os.path.exists(args.motion_json):
        with open(args.motion_json) as f:
            motion = json.load(f)
    fps = args.fps or (motion or {}).get("sample_fps") or 10.0

    names, deltas, seg_rows, findings = analyze(args.frames_dir, fps, motion)

    lines = []
    lines.append(f"# Motion report — {args.frames_dir}")
    lines.append(f"- frames: {len(names)}  |  fps assumed: {fps:g}  |  "
                 f"analysis width: {ANALYSIS_WIDTH}px")
    if motion:
        lines.append(f"- recording: {motion.get('name')} "
                     f"(video {motion.get('video_info')})")
        if motion.get("marks"):
            lines.append(f"- action marks (s from video start): "
                         f"{motion['marks']}")
    if len(names) < 3:
        lines.append("\nNot enough frames to analyze (need >= 3).")
    else:
        lines.append(f"- activity sparkline (per frame pair delta):")
        lines.append(f"  `{sparkline(deltas)}`")
        lines.append("")
        lines.append("## Motion segments")
        if seg_rows:
            lines.append("| from | to | duration | peak screen changed | changed region |")
            lines.append("|---|---|---|---|---|")
            for a, b, dur, peak, region in seg_rows:
                lines.append(f"| {a} | {b} | {dur:.2f}s | {peak:.0%} | {region} |")
        else:
            lines.append("No motion detected — the sequence is static.")
        lines.append("")
        lines.append("## Findings")
        if findings:
            findings.sort(key=lambda f: f[1])
            for kind, _i, msg in findings:
                lines.append(f"- **{kind}**: {msg}")
        else:
            lines.append("No pops, hard cuts, or stalls detected.")
    if motion and motion.get("scene_changes"):
        top = sorted(motion["scene_changes"],
                     key=lambda s: -s["score"])[:8]
        lines.append("")
        lines.append("## ffprobe scene-change peaks (from motion.json)")
        for s in sorted(top, key=lambda s: s["t"]):
            lines.append(f"- t={s['t']}s score={s['score']}")

    report = "\n".join(lines) + "\n"
    if args.out:
        with open(args.out, "w") as f:
            f.write(report)
        print(f"wrote {args.out}")
    else:
        print(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
