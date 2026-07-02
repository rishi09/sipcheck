#!/usr/bin/env python3
"""Interactive simulator bridge for remote Claude Code sessions.

Runs on a macOS CI runner next to a booted simulator with SipCheck installed.
Loop: post the current screen (screenshot + AXe accessibility dump) to the
`e2e-bridge-state` branch, then poll the `e2e-bridge-cmd` branch for a command
batch with the matching sequence number, execute it via AXe/simctl, repeat.

The remote session drives it by pushing cmd.json to e2e-bridge-cmd:
    {"seq": <seq from latest meta.json>, "actions": [
        {"do": "tap", "id": "addBeer"},
        {"do": "tap", "label": "Save"},
        {"do": "tap", "x": 370, "y": 90},
        {"do": "tap_prefix", "prefix": "beer_"},
        {"do": "type", "text": "Hazy IPA"},
        {"do": "swipe", "x1": 200, "y1": 600, "x2": 200, "y2": 200},
        {"do": "wait", "seconds": 2},
        {"do": "launch", "args": ["--mock-ai", "--seed-data"]},
        {"do": "terminate"},
        {"do": "home"},
        {"do": "end"}
    ]}

Motion recording (additive — old bridges skip unknown actions harmlessly):
    {"do": "record", "seconds": 8, "fps": 10, "name": "tab-switch"}
        Start `simctl io recordVideo`. Recording covers all SUBSEQUENT actions
        in the batch and auto-stops at the end of the batch (or at an explicit
        {"do": "record_stop"}), waiting until at least `seconds` have elapsed.
        The next state push then contains motion/<name>/ with:
          rec.mp4        — the raw video (ground truth, re-slice locally)
          frames/        — jpeg frames sampled at `fps` (default 10, max 15)
          bursts/        — native-fps jpeg bursts around each tap/swipe/launch
          motion.json    — video info, action marks, ffprobe scene-change
                           timeline, frame-timing (dup/drop) stats
    {"do": "record_stop"}
        Stop the active recording mid-batch (optional; batch end also stops).
    {"do": "flow", "name": "tab_tour"}
        Run a named, scripted interaction sequence wrapped in its own
        recording — one command captures a whole transition. Known flows:
        tab_tour, text_verdict, save_for_later, journal_detail, onboarding.
    {"do": "reset_onboarding"}
        Delete the age-gate/onboarding UserDefaults keys (used by the
        onboarding flow; app must be relaunched WITHOUT --isolated-storage
        to actually show onboarding).

Analysis of the pulled frames happens on the Linux side with
scripts/motion_report.py. See plans/reports/MOTION_LAB.md.

Standalone tour mode (no bridge loop, used by the E2E Motion workflow):
    python3 ci_bridge.py --udid <UDID> --tour default --out publish/motion

Both branches are single-commit force-pushed, so they never conflict and
never grow.
"""

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

BUNDLE_ID = "com.rishishah.sipcheck"
STATE_BRANCH = "e2e-bridge-state"
CMD_BRANCH = "e2e-bridge-cmd"

# ---- motion recording budgets (per recording; branches are single-commit
# force-pushed so this is a per-push cost, never cumulative) ----
MOTION_BUDGET_BYTES = 12 * 1024 * 1024
MAX_SAMPLE_FPS = 15
MAX_SAMPLED_FRAMES = 240
MAX_BURSTS = 6
BURST_PRE_S = 0.3
BURST_POST_S = 1.2
BURST_MAX_FRAMES = 90
MARKED_ACTIONS = ("tap", "tap_prefix", "swipe", "type", "launch", "terminate")

# Named interaction sequences captured under a single recording by
# {"do": "flow", "name": ...} or --tour. Labels/ids come from the app's
# accessibility tree (MainTabView tabs, CheckTabView, VerdictCardView...).
FLOWS = {
    # Tab-bar switches: Check -> Journal -> Profile -> Check.
    "tab_tour": [
        {"do": "tap", "label": "Journal"},
        {"do": "wait", "seconds": 1.5},
        {"do": "tap", "label": "Profile"},
        {"do": "wait", "seconds": 1.5},
        {"do": "tap", "label": "Check"},
        {"do": "wait", "seconds": 1.5},
    ],
    # Enter-beer sheet -> typed name -> verdict card appearance.
    "text_verdict": [
        {"do": "tap", "id": "enterTextButton"},
        {"do": "wait", "seconds": 1.2},
        {"do": "tap", "id": "beerTextInput"},
        {"do": "type", "text": "Two Hearted"},
        {"do": "tap", "id": "checkBeerButton"},
        {"do": "wait", "seconds": 3},
    ],
    # Save-for-later flip on the verdict card, then scan-another reset.
    # (Run after text_verdict so a verdict card is on screen.)
    "save_for_later": [
        {"do": "tap", "id": "saveForLater"},
        {"do": "wait", "seconds": 1.5},
        {"do": "tap", "id": "scanAnother"},
        {"do": "wait", "seconds": 1.5},
    ],
    # Journal detail push + edge-swipe back (needs --seed-data rows).
    "journal_detail": [
        {"do": "tap", "label": "Journal"},
        {"do": "wait", "seconds": 1.5},
        {"do": "tap_prefix", "prefix": "beer_"},
        {"do": "wait", "seconds": 2},
        {"do": "swipe", "x1": 3, "y1": 300, "x2": 320, "y2": 300,
         "duration": 0.4},
        {"do": "wait", "seconds": 1.5},
    ],
    # First-launch onboarding pages. Relaunches WITHOUT --isolated-storage
    # (which force-skips onboarding) but keeps network/CloudKit off, then
    # restores the standard hermetic launch at the end.
    "onboarding": [
        {"do": "terminate"},
        {"do": "reset_onboarding"},
        {"do": "launch", "args": ["--mock-ai", "--disable-cloudkit"]},
        {"do": "wait", "seconds": 2},
        {"do": "tap", "label": "I'm 21 or Older"},
        {"do": "wait", "seconds": 2},
        {"do": "swipe", "x1": 320, "y1": 350, "x2": 50, "y2": 350},
        {"do": "wait", "seconds": 1.2},
        {"do": "swipe", "x1": 320, "y1": 350, "x2": 50, "y2": 350},
        {"do": "wait", "seconds": 1.2},
        {"do": "swipe", "x1": 320, "y1": 350, "x2": 50, "y2": 350},
        {"do": "wait", "seconds": 1.2},
        {"do": "launch", "args": ["--mock-ai", "--seed-data",
                                  "--isolated-storage"]},
        {"do": "wait", "seconds": 2},
    ],
}
DEFAULT_TOUR = ["tab_tour", "text_verdict", "save_for_later",
                "journal_detail", "onboarding"]


def sh(cmd, check=False, capture=False, timeout=120, cwd=None):
    print(f"+ {' '.join(cmd)}", flush=True)
    return subprocess.run(
        cmd, check=check, timeout=timeout, cwd=cwd,
        capture_output=capture, text=True,
    )


def dir_size(path):
    total = 0
    for root, _dirs, files in os.walk(path):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return total


def frame_center(fr):
    """Center point of an AXe frame value (dict or '{{x, y}, {w, h}}' str)."""
    if isinstance(fr, dict):
        try:
            return (float(fr["x"]) + float(fr["width"]) / 2,
                    float(fr["y"]) + float(fr["height"]) / 2)
        except (KeyError, TypeError, ValueError):
            return None
    if isinstance(fr, str):
        nums = re.findall(r"-?\d+(?:\.\d+)?", fr)
        if len(nums) >= 4:
            x, y, w, h = (float(n) for n in nums[:4])
            return (x + w / 2, y + h / 2)
    return None


class Bridge:
    def __init__(self, udid, repo_url, minutes):
        self.udid = udid
        self.repo_url = repo_url
        self.deadline = time.time() + minutes * 60
        self.seq = 0
        self.rec = None            # active recording: proc/dir/t0/marks/params
        self.pending_motion = []   # [(name, processed-output-dir), ...]

    # ---- simulator interaction ----

    def axe(self, *args, timeout=60):
        return sh(["axe", *args, "--udid", self.udid], timeout=timeout)

    def screenshot(self, path):
        sh(["xcrun", "simctl", "io", self.udid, "screenshot", path])

    def ui_dump(self):
        r = sh(["axe", "describe-ui", "--udid", self.udid], capture=True)
        return r.stdout if r.returncode == 0 and r.stdout.strip() else "[]"

    def find_center_by_prefix(self, prefix):
        """Center of the first accessibility element whose identifier starts
        with `prefix`. Tolerant of AXe describe-ui schema variants."""
        try:
            data = json.loads(self.ui_dump())
        except (ValueError, TypeError):
            return None
        hits = []

        def walk(node):
            if hits:
                return
            if isinstance(node, dict):
                ident = (node.get("AXIdentifier") or node.get("identifier")
                         or node.get("AXUniqueId") or "")
                if isinstance(ident, str) and ident.startswith(prefix):
                    c = frame_center(node.get("frame") or node.get("AXFrame"))
                    if c:
                        hits.append(c)
                        return
                for v in node.values():
                    walk(v)
            elif isinstance(node, list):
                for v in node:
                    walk(v)

        walk(data)
        return hits[0] if hits else None

    def execute(self, action):
        do = action.get("do")
        if self.rec is not None and do in MARKED_ACTIONS:
            self.rec["marks"].append(
                [round(time.time() - self.rec["t0"], 2), do])
        if do == "tap" and "id" in action:
            self.axe("tap", "--id", str(action["id"]), "--post-delay", "1")
        elif do == "tap" and "label" in action:
            self.axe("tap", "--label", str(action["label"]), "--post-delay", "1")
        elif do == "tap":
            self.axe("tap", "-x", str(action["x"]), "-y", str(action["y"]),
                     "--post-delay", "1")
        elif do == "tap_prefix":
            c = self.find_center_by_prefix(str(action.get("prefix", "")))
            if c is None:
                print(f"tap_prefix: no element matches {action}", flush=True)
            else:
                self.axe("tap", "-x", str(int(c[0])), "-y", str(int(c[1])),
                         "--post-delay", "1")
        elif do == "type":
            self.axe("type", str(action["text"]))
            time.sleep(0.5)
        elif do == "swipe":
            self.axe("swipe",
                     "--start-x", str(action.get("x1", 200)),
                     "--start-y", str(action.get("y1", 600)),
                     "--end-x", str(action.get("x2", 200)),
                     "--end-y", str(action.get("y2", 200)),
                     "--duration", str(action.get("duration", 0.3)),
                     "--post-delay", "1")
        elif do == "wait":
            time.sleep(min(float(action.get("seconds", 1)), 30))
        elif do == "home":
            self.axe("button", "home")
        elif do == "terminate":
            sh(["xcrun", "simctl", "terminate", self.udid, BUNDLE_ID])
        elif do == "launch":
            sh(["xcrun", "simctl", "terminate", self.udid, BUNDLE_ID])
            time.sleep(1)
            sh(["xcrun", "simctl", "launch", self.udid, BUNDLE_ID,
                *action.get("args", [])])
            time.sleep(2)
        elif do == "record":
            self.record_start(action)
        elif do == "record_stop":
            self.record_stop(action)
        elif do == "flow":
            self.run_flow(action)
        elif do == "reset_onboarding":
            for key in ("hasCompletedOnboarding", "hasConfirmedAge"):
                sh(["xcrun", "simctl", "spawn", self.udid, "defaults",
                    "delete", BUNDLE_ID, key])
        else:
            print(f"unknown action skipped: {action}", flush=True)

    # ---- motion recording ----

    def record_start(self, params):
        if self.rec is not None:
            print("record: already recording, ignored", flush=True)
            return
        d = tempfile.mkdtemp(prefix="motion-rec-")
        path = os.path.join(d, "rec.mp4")
        print(f"recording -> {path}", flush=True)
        proc = subprocess.Popen(
            ["xcrun", "simctl", "io", self.udid, "recordVideo",
             "--codec", "h264", "--force", path],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # recordVideo needs a beat to start capturing; t0 approximates the
        # video's t=0 (marks are accurate to ~±0.5s; bursts pad for this).
        time.sleep(1.0)
        self.rec = {"proc": proc, "dir": d, "path": path,
                    "t0": time.time() - 0.5, "marks": [],
                    "params": dict(params)}

    def record_stop(self, extra_params=None):
        if self.rec is None:
            return
        rec, self.rec = self.rec, None
        params = dict(rec["params"])
        params.update(extra_params or {})
        min_s = float(params.get("seconds", 0) or 0)
        elapsed = time.time() - rec["t0"]
        if elapsed < min_s:
            time.sleep(min(min_s - elapsed, 60))
        rec["proc"].send_signal(signal.SIGINT)  # SIGINT finalizes the mp4
        try:
            rec["proc"].wait(timeout=20)
        except subprocess.TimeoutExpired:
            rec["proc"].kill()
            rec["proc"].wait(timeout=5)
        if not os.path.exists(rec["path"]) or os.path.getsize(rec["path"]) == 0:
            print("record_stop: no video produced", flush=True)
            shutil.rmtree(rec["dir"], ignore_errors=True)
            return
        name = str(params.get("name") or f"seq{self.seq:03d}")
        name = re.sub(r"[^A-Za-z0-9._-]+", "_", name)
        taken = {n for n, _ in self.pending_motion}
        if name in taken:
            name = f"{name}_{len(self.pending_motion)}"
        try:
            out = self.process_recording(rec, params, name)
            self.pending_motion.append((name, out))
            print(f"motion '{name}' ready ({dir_size(out)} bytes)", flush=True)
        except Exception as e:
            print(f"record_stop: processing failed: {e}", flush=True)
        finally:
            shutil.rmtree(rec["dir"], ignore_errors=True)

    def abort_recording(self):
        """Kill a live recorder without processing (crash/exit safety)."""
        if self.rec is None:
            return
        rec, self.rec = self.rec, None
        try:
            rec["proc"].send_signal(signal.SIGINT)
            rec["proc"].wait(timeout=10)
        except Exception:
            rec["proc"].kill()
        shutil.rmtree(rec["dir"], ignore_errors=True)

    def process_recording(self, rec, params, name):
        """rec.mp4 -> output dir with video, sampled frames, action bursts,
        and motion.json (scene-change + frame-timing analysis)."""
        out = tempfile.mkdtemp(prefix="motion-out-")
        video = os.path.join(out, "rec.mp4")
        shutil.move(rec["path"], video)

        info = {"width": None, "height": None, "duration": None}
        r = sh(["ffprobe", "-v", "error", "-print_format", "json",
                "-show_streams", "-show_format", "rec.mp4"],
               capture=True, cwd=out)
        try:
            probe = json.loads(r.stdout)
            for s in probe.get("streams", []):
                if s.get("codec_type") == "video":
                    info["width"] = s.get("width")
                    info["height"] = s.get("height")
            info["duration"] = float(probe.get("format", {})
                                     .get("duration", 0)) or None
        except (ValueError, TypeError):
            pass
        duration = info["duration"] or (time.time() - rec["t0"])

        # Scene-change timeline: when the UI moved, and how much.
        scene = []
        r = sh(["ffprobe", "-v", "error", "-f", "lavfi", "-i",
                "movie=rec.mp4,select=gt(scene\\,0.01)",
                "-show_entries",
                "frame=pts_time:frame_tags=lavfi.scene_score",
                "-of", "json"], capture=True, cwd=out, timeout=300)
        try:
            for fr in json.loads(r.stdout).get("frames", []):
                t = float(fr.get("pts_time", 0))
                sc = float(fr.get("tags", {}).get("lavfi.scene_score", 0))
                scene.append({"t": round(t, 3), "score": round(sc, 4)})
        except (ValueError, TypeError):
            pass
        scene = sorted(scene, key=lambda x: -x["score"])[:100]
        scene.sort(key=lambda x: x["t"])

        # Frame-timing stats (duplicated/dropped frame detection).
        gaps_info = {}
        r = sh(["ffprobe", "-v", "error", "-select_streams", "v:0",
                "-show_entries", "frame=pts_time", "-of", "csv=p=0",
                "rec.mp4"], capture=True, cwd=out, timeout=300)
        try:
            pts = []
            for tok in r.stdout.split():
                tok = tok.strip().strip(",")  # first frame may carry ",side_data"
                try:
                    pts.append(float(tok))
                except ValueError:
                    continue
            gaps = [round(b - a, 4) for a, b in zip(pts, pts[1:])]
            if gaps:
                srt = sorted(gaps)
                median = srt[len(srt) // 2]
                irregular = [round(t, 3) for t, g in zip(pts[1:], gaps)
                             if median > 0 and g > 2.5 * median][:50]
                gaps_info = {"frames": len(pts),
                             "median_gap_s": median,
                             "max_gap_s": max(gaps),
                             "irregular_gap_times": irregular}
        except (ValueError, TypeError):
            pass

        # Sampled frames at a capped fps (jpeg, half-res — budget-friendly).
        fps = min(float(params.get("fps", 10) or 10), MAX_SAMPLE_FPS)
        if duration and duration > 0:
            fps = min(fps, max(MAX_SAMPLED_FRAMES / duration, 1))
        frames_dir = os.path.join(out, "frames")
        os.makedirs(frames_dir, exist_ok=True)
        sh(["ffmpeg", "-v", "error", "-i", "rec.mp4",
            "-vf", f"fps={fps:.3f},scale=iw/2:-2", "-q:v", "4",
            "-frames:v", str(MAX_SAMPLED_FRAMES),
            "frames/f_%05d.jpg"], cwd=out, timeout=300)

        # Native-fps bursts around each action mark (the transition itself).
        bursts = params.get("bursts", True)
        if bursts and rec["marks"]:
            for i, (t, label) in enumerate(rec["marks"][:MAX_BURSTS]):
                start = max(t - BURST_PRE_S, 0)
                bdir = os.path.join(out, "bursts", f"{i:02d}_{label}")
                os.makedirs(bdir, exist_ok=True)
                sh(["ffmpeg", "-v", "error",
                    "-ss", f"{start:.2f}", "-t",
                    f"{BURST_PRE_S + BURST_POST_S:.2f}",
                    "-i", "rec.mp4", "-vsync", "vfr", "-q:v", "4",
                    "-frames:v", str(BURST_MAX_FRAMES),
                    os.path.join(bdir, "f_%04d.jpg")], cwd=out, timeout=300)

        pruned = self.prune_to_budget(out)

        with open(os.path.join(out, "motion.json"), "w") as f:
            json.dump({
                "name": name,
                "created_epoch": int(time.time()),
                "video": "rec.mp4",
                "video_info": info,
                "sample_fps": round(fps, 3),
                "marks": rec["marks"],
                "marks_note": ("seconds from video start; accurate to "
                               "~±0.5s — bursts pad the window"),
                "scene_changes": scene,
                "frame_timing": gaps_info,
                "pruned": pruned,
            }, f, indent=1)
        return out

    def prune_to_budget(self, out):
        """Keep the artifact under MOTION_BUDGET_BYTES. Drop bursts first,
        then thin sampled frames, then drop frames entirely. Never drop
        rec.mp4 or motion.json."""
        pruned = []
        if dir_size(out) <= MOTION_BUDGET_BYTES:
            return pruned
        bursts = os.path.join(out, "bursts")
        if os.path.isdir(bursts):
            shutil.rmtree(bursts, ignore_errors=True)
            pruned.append("bursts (size budget)")
        frames_dir = os.path.join(out, "frames")
        while dir_size(out) > MOTION_BUDGET_BYTES and os.path.isdir(frames_dir):
            frames = sorted(os.listdir(frames_dir))
            if len(frames) <= 20:
                shutil.rmtree(frames_dir, ignore_errors=True)
                pruned.append("frames (size budget)")
                break
            for fname in frames[1::2]:
                os.remove(os.path.join(frames_dir, fname))
            pruned.append(f"thinned frames to {len(frames) - len(frames[1::2])}")
        return pruned

    def run_flow(self, action):
        name = str(action.get("name", ""))
        seq = FLOWS.get(name)
        if seq is None:
            print(f"unknown flow skipped: {name} "
                  f"(known: {', '.join(FLOWS)})", flush=True)
            return
        nested = self.rec is not None
        if not nested:
            params = {k: v for k, v in action.items() if k != "do"}
            params.setdefault("name", name)
            self.record_start(params)
        for a in seq:
            try:
                self.execute(a)
            except Exception as e:
                print(f"flow '{name}' action failed ({a}): {e}", flush=True)
        if not nested:
            self.record_stop()

    # ---- git transport ----

    def post_state(self, note):
        d = tempfile.mkdtemp()
        try:
            self.screenshot(os.path.join(d, "screen.png"))
            with open(os.path.join(d, "ui.json"), "w") as f:
                f.write(self.ui_dump())
            meta = {"seq": self.seq, "note": note,
                    "deadline_epoch": int(self.deadline)}
            if self.pending_motion:
                meta["motion"] = [n for n, _ in self.pending_motion]
                for n, src in self.pending_motion:
                    shutil.copytree(src, os.path.join(d, "motion", n))
            with open(os.path.join(d, "meta.json"), "w") as f:
                json.dump(meta, f)
            git = ["git", "-C", d]
            sh([*git, "init", "-q", "-b", STATE_BRANCH])
            sh([*git, "config", "user.name", "e2e-bridge"])
            sh([*git, "config", "user.email", "bridge@ci"])
            sh([*git, "add", "-A"])
            sh([*git, "commit", "-qm", f"state {self.seq}"])
            for attempt in range(3):
                r = sh([*git, "push", "-qf", self.repo_url, STATE_BRANCH],
                       timeout=300)
                if r.returncode == 0:
                    break
                time.sleep(2 ** attempt)
            print(f"posted state seq={self.seq} ({note})", flush=True)
        finally:
            shutil.rmtree(d, ignore_errors=True)
            for _n, src in self.pending_motion:
                shutil.rmtree(src, ignore_errors=True)
            self.pending_motion = []

    def fetch_cmd(self):
        d = tempfile.mkdtemp()
        try:
            r = sh(["git", "clone", "-q", "--depth", "1", "--branch", CMD_BRANCH,
                    self.repo_url, d])
            if r.returncode != 0:
                return None
            path = os.path.join(d, "cmd.json")
            if not os.path.exists(path):
                return None
            with open(path) as f:
                return json.load(f)
        except Exception as e:
            print(f"fetch_cmd error: {e}", flush=True)
            return None
        finally:
            shutil.rmtree(d, ignore_errors=True)

    # ---- main loop ----

    def run(self):
        try:
            self._run_loop()
        finally:
            self.abort_recording()

    def _run_loop(self):
        self.post_state("session started — app launched, awaiting first command")
        while time.time() < self.deadline:
            cmd = self.fetch_cmd()
            if not cmd or cmd.get("seq") != self.seq:
                time.sleep(6)
                continue
            actions = cmd.get("actions", [])
            print(f"executing seq={self.seq}: {json.dumps(actions)}", flush=True)
            ended = False
            for action in actions:
                if action.get("do") == "end":
                    ended = True
                    break
                try:
                    self.execute(action)
                except Exception as e:
                    print(f"action failed ({action}): {e}", flush=True)
            if self.rec is not None:  # batch over -> finalize open recording
                try:
                    self.record_stop()
                except Exception as e:
                    print(f"auto record_stop failed: {e}", flush=True)
                    self.abort_recording()
            time.sleep(1)
            self.seq += 1
            if ended:
                self.post_state("session ended by remote command")
                return
            self.post_state(f"after actions: {json.dumps(actions)[:200]}")
        self.post_state("session deadline reached")

    # ---- standalone tour mode (E2E Motion workflow) ----

    def run_tour(self, tour, out_dir):
        names = (DEFAULT_TOUR if tour in ("default", "all")
                 else [n.strip() for n in tour.split(",") if n.strip()])
        os.makedirs(out_dir, exist_ok=True)
        results = []
        for name in names:
            try:
                self.execute({"do": "flow", "name": name})
            except Exception as e:
                print(f"tour flow '{name}' failed: {e}", flush=True)
                self.abort_recording()
        for name, src in self.pending_motion:
            dst = os.path.join(out_dir, name)
            shutil.rmtree(dst, ignore_errors=True)
            shutil.copytree(src, dst)
            results.append({"flow": name, "bytes": dir_size(dst)})
            shutil.rmtree(src, ignore_errors=True)
        self.pending_motion = []
        with open(os.path.join(out_dir, "index.json"), "w") as f:
            json.dump({"created_epoch": int(time.time()),
                       "requested": names, "recordings": results}, f, indent=1)
        print(f"tour complete: {json.dumps(results)}", flush=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--udid", required=True)
    p.add_argument("--minutes", type=float, default=40)
    p.add_argument("--tour", default=None,
                   help="Run named flows (comma list, or 'default') with "
                        "recording, write artifacts to --out, and exit — "
                        "no bridge loop, no git transport.")
    p.add_argument("--out", default="motion-out",
                   help="Output directory for --tour artifacts")
    args = p.parse_args()

    if args.tour:
        bridge = Bridge(args.udid, repo_url=None, minutes=args.minutes)
        bridge.run_tour(args.tour, args.out)
        return 0

    token = os.environ["GITHUB_TOKEN"]
    repo = os.environ["GITHUB_REPOSITORY"]
    repo_url = f"https://x-access-token:{token}@github.com/{repo}.git"

    Bridge(args.udid, repo_url, args.minutes).run()


if __name__ == "__main__":
    sys.exit(main())
