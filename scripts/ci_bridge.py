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
        {"do": "type", "text": "Hazy IPA"},
        {"do": "swipe", "x1": 200, "y1": 600, "x2": 200, "y2": 200},
        {"do": "wait", "seconds": 2},
        {"do": "launch", "args": ["--mock-ai", "--seed-data"]},
        {"do": "terminate"},
        {"do": "home"},
        {"do": "end"}
    ]}

Both branches are single-commit force-pushed, so they never conflict and
never grow.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

BUNDLE_ID = "com.rishishah.sipcheck"
STATE_BRANCH = "e2e-bridge-state"
CMD_BRANCH = "e2e-bridge-cmd"


def sh(cmd, check=False, capture=False, timeout=120):
    print(f"+ {' '.join(cmd)}", flush=True)
    return subprocess.run(
        cmd, check=check, timeout=timeout,
        capture_output=capture, text=True,
    )


class Bridge:
    def __init__(self, udid, repo_url, minutes):
        self.udid = udid
        self.repo_url = repo_url
        self.deadline = time.time() + minutes * 60
        self.seq = 0

    # ---- simulator interaction ----

    def axe(self, *args, timeout=60):
        return sh(["axe", *args, "--udid", self.udid], timeout=timeout)

    def screenshot(self, path):
        sh(["xcrun", "simctl", "io", self.udid, "screenshot", path])

    def ui_dump(self):
        r = sh(["axe", "describe-ui", "--udid", self.udid], capture=True)
        return r.stdout if r.returncode == 0 and r.stdout.strip() else "[]"

    def execute(self, action):
        do = action.get("do")
        if do == "tap" and "id" in action:
            self.axe("tap", "--id", str(action["id"]), "--post-delay", "1")
        elif do == "tap" and "label" in action:
            self.axe("tap", "--label", str(action["label"]), "--post-delay", "1")
        elif do == "tap":
            self.axe("tap", "-x", str(action["x"]), "-y", str(action["y"]),
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
        else:
            print(f"unknown action skipped: {action}", flush=True)

    # ---- git transport ----

    def post_state(self, note):
        d = tempfile.mkdtemp()
        try:
            self.screenshot(os.path.join(d, "screen.png"))
            with open(os.path.join(d, "ui.json"), "w") as f:
                f.write(self.ui_dump())
            with open(os.path.join(d, "meta.json"), "w") as f:
                json.dump({"seq": self.seq, "note": note,
                           "deadline_epoch": int(self.deadline)}, f)
            git = ["git", "-C", d]
            sh([*git, "init", "-q", "-b", STATE_BRANCH])
            sh([*git, "config", "user.name", "e2e-bridge"])
            sh([*git, "config", "user.email", "bridge@ci"])
            sh([*git, "add", "-A"])
            sh([*git, "commit", "-qm", f"state {self.seq}"])
            for attempt in range(3):
                r = sh([*git, "push", "-qf", self.repo_url, STATE_BRANCH])
                if r.returncode == 0:
                    break
                time.sleep(2 ** attempt)
            print(f"posted state seq={self.seq} ({note})", flush=True)
        finally:
            shutil.rmtree(d, ignore_errors=True)

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
            time.sleep(1)
            self.seq += 1
            if ended:
                self.post_state("session ended by remote command")
                return
            self.post_state(f"after actions: {json.dumps(actions)[:200]}")
        self.post_state("session deadline reached")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--udid", required=True)
    p.add_argument("--minutes", type=float, default=40)
    args = p.parse_args()

    token = os.environ["GITHUB_TOKEN"]
    repo = os.environ["GITHUB_REPOSITORY"]
    repo_url = f"https://x-access-token:{token}@github.com/{repo}.git"

    Bridge(args.udid, repo_url, args.minutes).run()


if __name__ == "__main__":
    sys.exit(main())
