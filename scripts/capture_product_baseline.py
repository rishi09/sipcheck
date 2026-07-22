#!/usr/bin/env python3
"""Capture SipCheck's canonical Release UI from a booted iOS simulator."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import struct
import subprocess
import time
from pathlib import Path
from typing import Any, Callable


BUNDLE_ID = "com.rishishah.sipcheck"


def run(command: list[str], *, capture: bool = False, check: bool = True,
        timeout: int = 120) -> subprocess.CompletedProcess[str]:
    print("+ " + " ".join(command), flush=True)
    return subprocess.run(
        command,
        check=check,
        capture_output=capture,
        text=True,
        timeout=timeout,
    )


def frame_center(frame: Any) -> tuple[int, int] | None:
    if isinstance(frame, dict):
        try:
            return (
                round(float(frame["x"]) + float(frame["width"]) / 2),
                round(float(frame["y"]) + float(frame["height"]) / 2),
            )
        except (KeyError, TypeError, ValueError):
            return None
    if isinstance(frame, str):
        numbers = re.findall(r"-?\d+(?:\.\d+)?", frame)
        if len(numbers) >= 4:
            x, y, width, height = (float(value) for value in numbers[:4])
            return round(x + width / 2), round(y + height / 2)
    return None


def walk(node: Any):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk(value)


def identifier(node: dict[str, Any]) -> str:
    return str(
        node.get("AXIdentifier")
        or node.get("identifier")
        or node.get("AXUniqueId")
        or ""
    )


def label(node: dict[str, Any]) -> str:
    return str(node.get("AXLabel") or node.get("label") or "")


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as source:
        header = source.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise RuntimeError(f"not a PNG: {path}")
    return struct.unpack(">II", header[16:24])


class CaptureSession:
    def __init__(self, udid: str, output: Path) -> None:
        self.udid = udid
        self.output = output
        self.output.mkdir(parents=True, exist_ok=True)
        self.captures: list[dict[str, Any]] = []

    def axe(self, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return run(["axe", *arguments, "--udid", self.udid], check=check, timeout=60)

    def ui(self) -> Any:
        result = run(
            ["axe", "describe-ui", "--udid", self.udid],
            capture=True,
            timeout=60,
        )
        return json.loads(result.stdout)

    def find(self, predicate: Callable[[dict[str, Any]], bool]) -> dict[str, Any] | None:
        return next((node for node in walk(self.ui()) if predicate(node)), None)

    def wait(self, predicate: Callable[[dict[str, Any]], bool], description: str,
             timeout: float = 15) -> dict[str, Any]:
        deadline = time.time() + timeout
        while time.time() < deadline:
            match = self.find(predicate)
            if match is not None:
                return match
            time.sleep(0.5)
        raise RuntimeError(f"timed out waiting for {description}")

    def wait_id(self, expected: str, timeout: float = 15) -> dict[str, Any]:
        return self.wait(lambda node: identifier(node) == expected, expected, timeout)

    def tap_id(self, expected: str, timeout: float = 15) -> None:
        self.wait_id(expected, timeout)
        self.axe("tap", "--id", expected, "--post-delay", "1")

    def tap_label(self, expected: str, timeout: float = 15) -> None:
        self.wait(lambda node: label(node) == expected, f"label {expected!r}", timeout)
        self.axe("tap", "--label", expected, "--post-delay", "1")

    def tap_matching(self, predicate: Callable[[dict[str, Any]], bool],
                     description: str, timeout: float = 15) -> None:
        node = self.wait(predicate, description, timeout)
        center = frame_center(node.get("frame") or node.get("AXFrame"))
        if center is None:
            raise RuntimeError(f"{description} has no tappable frame")
        self.axe(
            "tap", "-x", str(center[0]), "-y", str(center[1]),
            "--post-delay", "1",
        )

    def tap_id_prefix(self, prefix: str, timeout: float = 15) -> None:
        self.tap_matching(
            lambda node: identifier(node).startswith(prefix),
            f"identifier prefix {prefix!r}",
            timeout,
        )

    def type_text(self, text: str) -> None:
        self.axe("type", text)
        time.sleep(0.8)

    def swipe(self, x1: int, y1: int, x2: int, y2: int) -> None:
        self.axe(
            "swipe", "--start-x", str(x1), "--start-y", str(y1),
            "--end-x", str(x2), "--end-y", str(y2),
            "--duration", "0.4", "--post-delay", "1",
        )

    def launch(self, *arguments: str) -> None:
        run(
            ["xcrun", "simctl", "terminate", self.udid, BUNDLE_ID],
            check=False,
        )
        run(["xcrun", "simctl", "launch", self.udid, BUNDLE_ID, *arguments])
        time.sleep(3)

    def dismiss_notification_prompt(self) -> None:
        choices = {"Don’t Allow", "Don't Allow", "Allow"}
        node = self.find(lambda item: label(item) in choices)
        if node is None:
            return
        center = frame_center(node.get("frame") or node.get("AXFrame"))
        if center:
            self.axe("tap", "-x", str(center[0]), "-y", str(center[1]),
                     "--post-delay", "1")

    def snap(self, relative_path: str, title: str, state: str) -> None:
        path = self.output / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        run(["xcrun", "simctl", "io", self.udid, "screenshot", str(path)])
        ui_path = path.with_suffix(".ax.json")
        ui_path.write_text(json.dumps(self.ui(), indent=2, sort_keys=True) + "\n")
        width, height = png_dimensions(path)
        self.captures.append({
            "id": relative_path.removesuffix(".png").replace("/", "."),
            "path": relative_path,
            "title": title,
            "state": state,
            "width": width,
            "height": height,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        })

    def write_manifest(self) -> None:
        result = run(
            ["xcrun", "simctl", "list", "devices", "available", "-j"],
            capture=True,
        )
        devices = json.loads(result.stdout).get("devices", {})
        device_name = "unknown"
        runtime = "unknown"
        for runtime_id, entries in devices.items():
            for entry in entries:
                if entry.get("udid") == self.udid:
                    device_name = entry.get("name", "unknown")
                    runtime = runtime_id.rsplit(".", 1)[-1].replace("-", ".")
        xcode = run(["xcodebuild", "-version"], capture=True).stdout.strip()
        manifest = {
            "schema": 1,
            "source_sha": os.environ.get("GITHUB_SHA", "local"),
            "build_configuration": "Release",
            "bundle_id": BUNDLE_ID,
            "device": device_name,
            "udid": self.udid,
            "runtime": runtime,
            "appearance": "dark",
            "locale": "en_US",
            "xcode": xcode,
            "captures": self.captures,
        }
        (self.output / "capture-manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n"
        )


def capture(session: CaptureSession) -> None:
    session.launch("--disable-cloudkit", "-AppleLanguages", "(en)",
                   "-AppleLocale", "en_US")
    session.wait(lambda node: label(node) == "I'm 21 or Older", "age gate")
    session.snap("primary/onboarding/01-age-gate.png", "Age gate", "Fresh install")

    session.tap_label("I'm Under 21")
    session.wait_id("ageGateGoBack")
    session.snap(
        "primary/onboarding/02-under-age-recovery.png",
        "Under-age recovery",
        "Under 21 selected",
    )
    session.tap_id("ageGateGoBack")
    session.tap_label("I'm 21 or Older")

    session.wait_id("onboardingContinuePage0")
    session.snap(
        "primary/onboarding/03-outcome-story.png",
        "Outcome story",
        "First onboarding story",
    )
    session.tap_id("onboardingContinuePage0")
    session.wait_id("onboardingContinuePage1")
    session.snap(
        "primary/onboarding/04-verdict-story.png",
        "Verdict story",
        "Second onboarding story",
    )
    session.tap_id("onboardingContinuePage1")

    session.wait_id("onboardingGoToBeerTile.modelo")
    session.snap(
        "primary/onboarding/05-go-to-blank.png",
        "Go-to picker",
        "Blank-slate purchase recall",
    )
    session.tap_id("onboardingGoToBeerTile.modelo")
    session.tap_id("onboardingGoToStyle.ipa")
    session.snap(
        "primary/onboarding/06-go-to-selected.png",
        "Go-to selections",
        "Modelo and IPA selected",
    )
    session.tap_id("onboardingPickerNext")

    session.wait_id("onboardingStayAwayNext")
    session.snap(
        "primary/onboarding/07-stay-away-blank.png",
        "Stay-away picker",
        "Independent blank slate",
    )
    session.tap_id("onboardingStayAwayBeerTile.heineken")
    session.wait_id("avoidEchoLine")
    session.snap(
        "primary/onboarding/08-stay-away-selected.png",
        "Stay-away selection",
        "Named avoid with category echo",
    )
    session.tap_id("onboardingStayAwayNext")

    session.wait_id("checkTab")
    session.launch("--seed-data", "--disable-cloudkit", "-AppleLanguages", "(en)",
                   "-AppleLocale", "en_US")
    session.wait_id("checkTab")
    session.snap("primary/check/01-idle.png", "Check", "Seeded Release launch")

    session.tap_id("enterTextButton")
    session.wait_id("beerTextInput")
    session.type_text("Sierra Nevada Pale Ale")
    session.wait_id("suggestionRow_0")
    session.snap(
        "primary/check/02-typed-suggestions.png",
        "Typed lookup",
        "Keyboard and offline catalog suggestions",
    )
    # Selecting the canonical offline-catalog row exercises the same submit
    # path without relying on a bottom-edge coordinate tap in headless AXe.
    session.tap_id("suggestionRow_0")
    # SwiftUI flattens VerdictCardView into its visible children in Release,
    # so the container/button identifiers are intentionally not relied on.
    session.wait(lambda node: label(node) == "TRY IT", "TRY IT verdict", timeout=30)
    session.snap(
        "primary/check/03-personalized-verdict.png",
        "Personalized verdict",
        "Exact prior-rating history",
    )

    session.tap_label("Save for Later")
    time.sleep(1)
    session.dismiss_notification_prompt()
    session.wait(lambda node: label(node) == "Saved", "saved confirmation")
    session.snap(
        "primary/check/04-saved-for-later.png",
        "Saved for later",
        "Optimistic saved state",
    )
    session.tap_label("Drinking it — log it")
    session.wait_id("beerName")
    session.snap(
        "primary/check/05-add-beer-prefill.png",
        "Add Beer",
        "Resolved metadata prefilled from verdict",
    )
    session.tap_label("Cancel")

    session.tap_label("Journal")
    session.wait_id("journalTab")
    session.snap(
        "primary/journal/01-library.png",
        "Journal",
        "Want to Try and seeded history",
    )
    session.tap_id("journalSearch")
    session.type_text("No Such Beer")
    session.wait(lambda node: "No beers match" in label(node), "no-match state")
    session.snap(
        "primary/journal/02-no-match.png",
        "Journal no-match",
        "Search excludes all history",
    )

    session.launch("--disable-cloudkit", "-AppleLanguages", "(en)",
                   "-AppleLocale", "en_US")
    session.tap_label("Journal")
    session.tap_matching(
        lambda node: label(node).startswith("Guinness Draught"),
        "Guinness journal row",
    )
    session.wait_id("detailDelete")
    session.snap(
        "primary/journal/03-detail.png",
        "Journal detail",
        "Editable rating, notes, Save, and Delete hierarchy",
    )
    session.tap_label("Close")

    session.tap_label("Profile")
    session.wait_id("profileTab")
    session.snap(
        "primary/profile/01-overview.png",
        "Profile overview",
        "Persona, stats, and top styles",
    )
    session.swipe(200, 700, 200, 260)
    session.wait_id("recentScans")
    session.snap(
        "primary/profile/02-recent-scans.png",
        "Recent scans",
        "Verdict history list",
    )
    session.tap_id_prefix("recentScanRow_")
    session.wait_id("recentScanDetail")
    session.snap(
        "primary/profile/03-scan-detail.png",
        "Scan detail",
        "Persisted rationale and metadata",
    )

    session.launch("--disable-cloudkit", "-AppleLanguages", "(en)",
                   "-AppleLocale", "en_US")
    session.tap_label("Profile")
    session.tap_id("settingsButton")
    session.wait_id("settingsTab")
    session.snap(
        "primary/settings/01-release-settings.png",
        "Settings",
        "Shipping Release controls",
    )
    session.tap_label("Edit taste preferences")
    session.wait_id("tastePreferencesDoneButton")
    session.snap(
        "primary/settings/02-taste-preferences.png",
        "Taste preferences",
        "Editable go-to and stay-away profile",
    )
    session.tap_matching(
        lambda node: identifier(node) == "tastePreferencesDoneButton",
        "taste preferences Done button",
    )
    session.swipe(200, 700, 200, 240)
    session.swipe(200, 700, 200, 240)
    session.snap(
        "primary/settings/03-data-and-about.png",
        "Settings data controls",
        "Export, replay, clear, version, and policies",
    )

    # Exercise the simulator-supported photo-library route with the single
    # menu fixture installed by the workflow. The fixed Pro viewport makes the
    # first Photos grid cell deterministic while the surrounding state is
    # still verified through the live accessibility tree.
    session.launch("--seed-data", "--disable-cloudkit", "-AppleLanguages", "(en)",
                   "-AppleLocale", "en_US")
    session.tap_label("Scan Label")
    # AXe continues to expose the presenting app while Apple's out-of-process
    # Photos picker is foregrounded, so pixels are the readiness signal here.
    time.sleep(2)
    session.snap(
        "primary/check/06-menu-photo-picker.png",
        "Menu photo picker",
        "Single deterministic menu fixture",
    )
    session.axe("tap", "-x", "67", "-y", "380", "--post-delay", "1")
    session.wait(
        lambda node: label(node) == "Two Hearted IPA",
        "menu winner",
        timeout=45,
    )
    session.wait(lambda node: label(node) == "See runner-up", "runner-up control")
    session.snap(
        "primary/check/07-menu-winner.png",
        "Menu winner",
        "On-device best-of-menu recommendation",
    )
    session.tap_label("See runner-up")
    session.wait(
        lambda node: label(node) == "Allagash White Wheat",
        "expanded menu runner-up",
    )
    session.snap(
        "primary/check/08-menu-runner-up.png",
        "Menu runner-up",
        "Second-ranked menu option expanded",
    )
    session.write_manifest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    session = CaptureSession(arguments.udid, arguments.output)
    try:
        capture(session)
    except Exception:
        # Preserve the failing screen and AX tree; a red run should still say
        # exactly where the live product diverged from the capture contract.
        try:
            session.snap(
                "failure/failing-state.png",
                "Capture failure",
                "Unexpected state at the point of failure",
            )
            session.write_manifest()
        except Exception as evidence_error:
            print(f"could not save failure evidence: {evidence_error}", flush=True)
        raise
    print(f"captured {len(session.captures)} screenshots", flush=True)


if __name__ == "__main__":
    main()
