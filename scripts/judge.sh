#!/bin/bash
# scripts/judge.sh — Judge agent: merge worker branches, run all tests, report
#
# Usage:
#   ./scripts/judge.sh tab-bar data-models verdict-card
#
# What it does:
#   1. Creates a judge/review branch from main
#   2. Merges each worker branch
#   3. Builds the merged result
#   4. Runs unit tests, UI tests, E2E tests
#   5. Takes screenshots
#   6. Writes judge report to /tmp/sipcheck-workers/judge/judge-report.md
#
# Can also be run as a Claude agent for subjective evaluation:
#   ./scripts/judge.sh --ai tab-bar data-models verdict-card

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKERS_DIR="/tmp/sipcheck-workers"
SIMULATOR_UDID="48FF0EDE-5280-4C70-AB5C-F06C750443DB"
REPORT="$WORKERS_DIR/judge/judge-report.md"
USE_AI=false

# Parse args
TASKS=()
for arg in "$@"; do
  case $arg in
    --ai) USE_AI=true ;;
    *) TASKS+=("$arg") ;;
  esac
done

if [ ${#TASKS[@]} -eq 0 ]; then
  echo "Usage: $0 [--ai] <task-name> [task-name] ..."
  exit 1
fi

echo "=== SipCheck Judge ==="
echo "Tasks to evaluate: ${TASKS[*]}"
echo "Report: $REPORT"
echo ""

# ---- Initialize Report ----

cat > "$REPORT" <<EOF
# Judge Report
Date: $(date '+%Y-%m-%d %H:%M')
Tasks evaluated: ${TASKS[*]}

EOF

# ---- Step 1: Create review branch ----

cd "$PROJECT_DIR"
REVIEW_BRANCH="judge/review-$(date +%s)"
git checkout -b "$REVIEW_BRANCH" main 2>/dev/null
echo "Created review branch: $REVIEW_BRANCH"

# ---- Step 2: Merge worker branches ----

echo "" >> "$REPORT"
echo "## Merge Status" >> "$REPORT"
echo "" >> "$REPORT"

MERGE_FAILURES=0
for task in "${TASKS[@]}"; do
  branch="worker/${task}"
  if git merge "$branch" --no-edit 2>/dev/null; then
    echo "| $branch | MERGED |" >> "$REPORT"
    echo "Merged: $branch"
  else
    echo "| $branch | CONFLICT |" >> "$REPORT"
    echo "CONFLICT: $branch — aborting merge"
    git merge --abort 2>/dev/null || true
    MERGE_FAILURES=$((MERGE_FAILURES + 1))
  fi
done

if [ $MERGE_FAILURES -gt 0 ]; then
  echo "" >> "$REPORT"
  echo "**$MERGE_FAILURES merge conflict(s). Manual resolution needed.**" >> "$REPORT"
  echo ""
  echo "Merge conflicts detected. Review branch: $REVIEW_BRANCH"
  echo "Report: $REPORT"

  if ! $USE_AI; then
    exit 1
  fi
fi

# ---- Step 3: Build ----

echo ""
echo "--- Building merged result ---"
echo "" >> "$REPORT"
echo "## Gate Results" >> "$REPORT"
echo "" >> "$REPORT"
echo "| Gate | Status | Detail |" >> "$REPORT"
echo "|------|--------|--------|" >> "$REPORT"

BUILD_OUTPUT=$(xcodebuild -project SipCheck.xcodeproj -scheme SipCheck \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -configuration Debug build 2>&1)

if echo "$BUILD_OUTPUT" | grep -q "BUILD SUCCEEDED"; then
  echo "| Build compiles | PASS | |" >> "$REPORT"
  echo "Build: PASS"
else
  ERRORS=$(echo "$BUILD_OUTPUT" | grep "error:" | head -5)
  echo "| Build compiles | FAIL | $(echo "$ERRORS" | head -1) |" >> "$REPORT"
  echo "Build: FAIL"
  echo "$ERRORS"

  echo "" >> "$REPORT"
  echo "## Recommendation" >> "$REPORT"
  echo "FIX — build does not compile. Errors:" >> "$REPORT"
  echo '```' >> "$REPORT"
  echo "$ERRORS" >> "$REPORT"
  echo '```' >> "$REPORT"

  if ! $USE_AI; then
    echo "Report: $REPORT"
    exit 1
  fi
fi

# ---- Step 4: Unit Tests ----

echo ""
echo "--- Running unit tests ---"

UNIT_OUTPUT=$(xcodebuild test \
  -project SipCheck.xcodeproj -scheme SipCheck \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -only-testing:SipCheckTests \
  2>&1)

if echo "$UNIT_OUTPUT" | grep -q "Test Suite.*passed"; then
  UNIT_SUMMARY=$(echo "$UNIT_OUTPUT" | grep "Executed" | tail -1)
  echo "| Unit tests | PASS | $UNIT_SUMMARY |" >> "$REPORT"
  echo "Unit tests: PASS"
else
  UNIT_ERRORS=$(echo "$UNIT_OUTPUT" | grep -E "(failed|error:)" | head -3)
  echo "| Unit tests | FAIL | $UNIT_ERRORS |" >> "$REPORT"
  echo "Unit tests: FAIL"
fi

# ---- Step 5: UI Tests ----

echo ""
echo "--- Running UI tests ---"

UI_OUTPUT=$(xcodebuild test \
  -project SipCheck.xcodeproj -scheme SipCheck \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -only-testing:SipCheckUITests \
  2>&1)

if echo "$UI_OUTPUT" | grep -q "Test Suite.*passed"; then
  UI_SUMMARY=$(echo "$UI_OUTPUT" | grep "Executed" | tail -1)
  echo "| UI tests | PASS | $UI_SUMMARY |" >> "$REPORT"
  echo "UI tests: PASS"
else
  UI_ERRORS=$(echo "$UI_OUTPUT" | grep -E "(failed|error:)" | head -3)
  echo "| UI tests | FAIL | $UI_ERRORS |" >> "$REPORT"
  echo "UI tests: FAIL"
fi

# ---- Step 6: E2E Tests ----

echo ""
echo "--- Running E2E tests ---"

# Build and install for E2E
xcrun simctl install "$SIMULATOR_UDID" \
  ~/Library/Developer/Xcode/DerivedData/SipCheck-*/Build/Products/Debug-iphonesimulator/SipCheck.app \
  2>/dev/null || true

E2E_OUTPUT=$(./scripts/e2e_test.sh 2>&1)
E2E_EXIT=$?

if [ $E2E_EXIT -eq 0 ]; then
  E2E_SUMMARY=$(echo "$E2E_OUTPUT" | grep "RESULTS:" | head -1)
  echo "| E2E flows | PASS | $E2E_SUMMARY |" >> "$REPORT"
  echo "E2E: PASS"
else
  E2E_FAILS=$(echo "$E2E_OUTPUT" | grep "FAIL:" | head -5)
  echo "| E2E flows | FAIL | $(echo "$E2E_FAILS" | head -1) |" >> "$REPORT"
  echo "E2E: FAIL"
fi

# ---- Step 7: Screenshots ----

echo ""
echo "--- Taking screenshots ---"

SCREENSHOT_DIR="$WORKERS_DIR/screenshots"
xcrun simctl launch --terminate-running-process "$SIMULATOR_UDID" com.sipcheck.app \
  --mock-ai --seed-data --isolated-storage 2>/dev/null || true
sleep 2

xcrun simctl io "$SIMULATOR_UDID" screenshot "$SCREENSHOT_DIR/judge-main.png" 2>/dev/null || true
echo "Screenshot: $SCREENSHOT_DIR/judge-main.png"

echo "" >> "$REPORT"
echo "## Screenshots" >> "$REPORT"
echo "- Main screen: $SCREENSHOT_DIR/judge-main.png" >> "$REPORT"

# ---- Step 8: Worker Results Summary ----

echo "" >> "$REPORT"
echo "## Worker Results" >> "$REPORT"
echo "" >> "$REPORT"

for task in "${TASKS[@]}"; do
  result_file="$WORKERS_DIR/results/result-${task}.md"
  if [ -f "$result_file" ]; then
    status=$(grep -m1 "Status:" "$result_file" 2>/dev/null || echo "UNKNOWN")
    echo "### $task" >> "$REPORT"
    echo "$status" >> "$REPORT"
    echo "" >> "$REPORT"
  else
    echo "### $task" >> "$REPORT"
    echo "No result file found." >> "$REPORT"
    echo "" >> "$REPORT"
  fi
done

# ---- Step 9: Recommendation ----

echo "" >> "$REPORT"
echo "## Recommendation" >> "$REPORT"

# Simple heuristic — if all gates passed, recommend SHIP
if grep -q "FAIL" "$REPORT"; then
  echo "FIX — see failed gates above." >> "$REPORT"
else
  echo "SHIP — all gates passed." >> "$REPORT"
fi

echo ""
echo "=== Judge Complete ==="
echo "Report: $REPORT"
echo "Review branch: $REVIEW_BRANCH"
echo ""
echo "Next steps:"
echo "  cat $REPORT                    # Read the verdict"
echo "  git checkout main              # Return to main"
echo "  git merge $REVIEW_BRANCH       # If SHIP recommended"
echo "  git branch -D $REVIEW_BRANCH   # Clean up"

# ---- Optional: AI Judge Panel ----

if $USE_AI; then
  echo ""
  echo "--- Spawning specialist judge panel (4 judges in parallel) ---"

  JUDGE_DIR="$WORKERS_DIR/judge"
  TASK_LIST="${TASKS[*]}"

  # ---- Spec Judge ----
  (
    claude -p "$(cat <<PROMPT
You are the SPEC JUDGE for SipCheck. You did NOT write this code.

YOUR LENS: Does the code match what was asked?

1. Read the gate judge report: $REPORT
2. Read each task spec in $WORKERS_DIR/tasks/
3. Read each worker result in $WORKERS_DIR/results/
4. Read the user flows design: plans/user-flows-design-2026-03-16.md
5. Read the actual changed/created files

For each task, evaluate:
- Did the worker build what the spec asked for?
- Are there missing features from the spec?
- Are there edge cases from the flows doc that aren't handled?
- Did the worker add anything NOT in the spec? (flag as scope creep)

Write your findings to: $JUDGE_DIR/spec-review.md
Format: Blockers (must fix), Issues (should fix), Notes (informational)
Be specific — reference file:line for every finding.
PROMPT
    )" --allowedTools "Read,Bash,Glob,Grep" \
    > "$JUDGE_DIR/spec-judge-log.txt" 2>&1
    echo "Spec judge done"
  ) &
  JUDGE_PIDS+=($!)

  # ---- Design Judge ----
  (
    claude -p "$(cat <<PROMPT
You are the DESIGN JUDGE for SipCheck. You did NOT write this code.

YOUR LENS: Does the UI match the design system?

1. Read the design direction: plans/design-direction-2026-03-16.md
2. Read all changed/created View files (SipCheck/Views/*.swift)
3. Look at screenshots in $WORKERS_DIR/screenshots/

Check:
- Color tokens: background #1A1A1E, surface #2A2A2E, primary teal #4ECDC4, cream text #F5F3F0
- Typography: SF Pro sizes (display 34pt Heavy, title 24pt Bold, headline 18pt Semibold, body 16pt Regular, subhead 14pt Medium, caption 12pt Regular)
- Verdict card gradients: green for Try It, coral/rust for Skip It, amber for Your Call
- Star rating: gold #F1C40F filled, #3A3A3E empty, 28-32pt tap targets
- Dark theme throughout (beer photos provide warmth, chrome stays recessive)
- No orange/amber/yellow as brand colors

Write your findings to: $JUDGE_DIR/design-review.md
Format: Blockers, Issues, Notes. Reference file:line for every finding.
PROMPT
    )" --allowedTools "Read,Bash,Glob,Grep" \
    > "$JUDGE_DIR/design-judge-log.txt" 2>&1
    echo "Design judge done"
  ) &
  JUDGE_PIDS+=($!)

  # ---- Convention Judge ----
  (
    claude -p "$(cat <<PROMPT
You are the CONVENTION JUDGE for SipCheck. You did NOT write this code.

YOUR LENS: Does the code follow project conventions?

1. Read CLAUDE.md for all project rules
2. Read all changed/created Swift files

Check:
- No Swift macros (@Observable, @Model, #Preview) — use PreviewProvider instead
- @EnvironmentObject for DrinkStore, not @Environment
- No SwiftData — JSON file persistence only
- iOS 17+ compatible APIs only
- Accessibility identifiers on all interactive elements (buttons, fields, pickers)
- No hardcoded API keys
- PreviewProvider structs present on new views
- No unnecessary imports or dead code

Write your findings to: $JUDGE_DIR/convention-review.md
Format: Blockers, Issues, Notes. Reference file:line for every finding.
PROMPT
    )" --allowedTools "Read,Bash,Glob,Grep" \
    > "$JUDGE_DIR/convention-judge-log.txt" 2>&1
    echo "Convention judge done"
  ) &
  JUDGE_PIDS+=($!)

  # ---- Integration Judge ----
  (
    claude -p "$(cat <<PROMPT
You are the INTEGRATION JUDGE for SipCheck. You did NOT write this code.

YOUR LENS: Do the merged branches work together as a coherent app?

1. Read the gate judge report: $REPORT
2. Read SipCheck/SipCheckApp.swift (app entry point)
3. Read all changed/created files holistically
4. Read plans/user-flows-design-2026-03-16.md for navigation structure

Check:
- Navigation: can users reach all screens? Are all tab targets wired?
- Data flow: do views that need DrinkStore/ScanStore get it via @EnvironmentObject?
- Model consistency: do views reference the right model types?
- No orphaned views (created but never navigated to)
- No circular dependencies
- State management: are @Published properties observed correctly?
- Launch args (--mock-ai, --seed-data, --isolated-storage) still work?

Write your findings to: $JUDGE_DIR/integration-review.md
Format: Blockers, Issues, Notes. Reference file:line for every finding.
PROMPT
    )" --allowedTools "Read,Bash,Glob,Grep" \
    > "$JUDGE_DIR/integration-judge-log.txt" 2>&1
    echo "Integration judge done"
  ) &
  JUDGE_PIDS+=($!)

  # Wait for all judges
  echo "Waiting for 4 specialist judges..."
  for pid in "${JUDGE_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  echo ""
  echo "--- All judges complete. Synthesizing review. ---"

  # ---- Review Agent: synthesize into single brief ----
  claude -p "$(cat <<PROMPT
You are the REVIEW AGENT for SipCheck. Your job is to synthesize multiple judge reports into ONE clear brief for the product owner (Rishi).

Read these reports:
1. Gate judge (automated): $REPORT
2. Spec review: $JUDGE_DIR/spec-review.md
3. Design review: $JUDGE_DIR/design-review.md
4. Convention review: $JUDGE_DIR/convention-review.md
5. Integration review: $JUDGE_DIR/integration-review.md
6. Screenshots in: $WORKERS_DIR/screenshots/

Produce a SINGLE summary. Write it to: $JUDGE_DIR/review-brief.md

FORMAT:

# Review Brief
[Date, tasks evaluated]

## Verdict: SHIP | FIX | REPLAN

## What Was Built
[2-3 sentence summary of what the workers produced]

## Blockers (must fix before merge)
[Numbered list — only things that are actually broken or wrong]
[Each item: what's wrong, where (file:line), suggested fix]

## Issues (should fix, not blocking)
[Numbered list]

## Device Build Status
[Is it ready for Cmd+R? If not, why?]

## Screenshots
[Reference screenshot paths with brief description of what each shows]

RULES:
- Be concise. Rishi is busy.
- Deduplicate across judges — if two judges flag the same thing, mention it once.
- Distinguish between "actually broken" and "could be better."
- If all gates passed and judges found nothing serious, say SHIP.
- Don't repeat the full judge reports — summarize and cite.
PROMPT
  )" --allowedTools "Read,Bash,Glob,Grep" \
  > "$JUDGE_DIR/review-agent-log.txt" 2>&1

  echo ""
  echo "=== Review Brief Ready ==="
  echo "Brief: $JUDGE_DIR/review-brief.md"
  echo ""
  if [ -f "$JUDGE_DIR/review-brief.md" ]; then
    head -20 "$JUDGE_DIR/review-brief.md"
    echo "..."
    echo ""
    echo "Full brief: cat $JUDGE_DIR/review-brief.md"
  fi
fi
