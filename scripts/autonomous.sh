#!/bin/bash
# scripts/autonomous.sh — Spawn parallel Claude Code workers in isolated worktrees
#
# Usage:
#   ./scripts/autonomous.sh task-tab-bar task-data-models task-verdict-card
#
# Each task name maps to a task spec file at:
#   /tmp/sipcheck-workers/tasks/task-{name}.md
#
# Workers:
#   - Get their own git worktree (branch: worker/{name})
#   - Run the build-fix loop autonomously (max 5 fix attempts)
#   - Commit to their branch when green
#   - Write results to /tmp/sipcheck-workers/results/result-{name}.md
#
# After all workers complete, run ./scripts/judge.sh to evaluate.

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKERS_DIR="/tmp/sipcheck-workers"
WORKTREE_BASE="/tmp/sipcheck-worktrees"
SIMULATOR_UDID="48FF0EDE-5280-4C70-AB5C-F06C750443DB"

# ---- Setup ----

mkdir -p "$WORKERS_DIR/tasks" "$WORKERS_DIR/results" "$WORKERS_DIR/judge" "$WORKERS_DIR/screenshots"

if [ $# -eq 0 ]; then
  echo "Usage: $0 <task-name> [task-name] ..."
  echo ""
  echo "Each task-name must have a spec at:"
  echo "  $WORKERS_DIR/tasks/task-{name}.md"
  echo ""
  echo "Example:"
  echo "  $0 tab-bar data-models verdict-card"
  exit 1
fi

# Verify all task specs exist
for task in "$@"; do
  spec="$WORKERS_DIR/tasks/task-${task}.md"
  if [ ! -f "$spec" ]; then
    echo "ERROR: No task spec found at $spec"
    echo "Write the task spec first, then re-run."
    exit 1
  fi
done

echo "=== SipCheck Autonomous Build ==="
echo "Tasks: $*"
echo "Worktrees: $WORKTREE_BASE"
echo "Results: $WORKERS_DIR/results/"
echo ""

# ---- Worker Prompt ----

worker_prompt() {
  local task_name="$1"
  local task_spec
  task_spec=$(cat "$WORKERS_DIR/tasks/task-${task_name}.md")
  local result_path="$WORKERS_DIR/results/result-${task_name}.md"

  cat <<PROMPT
You are an autonomous coding agent working on SipCheck (iOS/SwiftUI).

PROJECT CONVENTIONS (from CLAUDE.md):
- Use @EnvironmentObject for DrinkStore, not @Environment
- Use PreviewProvider structs, not #Preview macro
- No Swift macros (@Observable, @Model, #Preview)
- iOS 17+ target
- Store data in JSON files, not SwiftData

YOUR TASK:
$task_spec

AUTONOMOUS BUILD LOOP:
1. Read the task spec carefully
2. Read any referenced files (design specs, existing code you'll modify)
3. Implement the change
4. Build:
   xcodebuild -project SipCheck.xcodeproj -scheme SipCheck \\
     -destination 'platform=iOS Simulator,id=$SIMULATOR_UDID' \\
     -configuration Debug build 2>&1 | tail -20
5. If build fails: read the error, fix the code, go to step 4
6. Max 5 fix attempts. If still failing after 5, document what's wrong and stop.
7. When build passes, commit with a descriptive message
8. Write your result summary to: $result_path

RESULT FORMAT:
Write a markdown file with these sections:
- Status: GREEN | RED | STUCK
- What I Did (list of changes with file paths)
- Build Status (which attempt passed, what errors were fixed)
- Decisions Made (any judgment calls)
- Files Changed (created/modified with line counts)
- Open Questions (anything you weren't sure about)

RULES:
- Do NOT modify files listed in "Do NOT Touch"
- Do NOT add features beyond the task spec
- Do NOT remove existing accessibility identifiers
- Do NOT use Swift macros
- If stuck, document what's blocking — don't guess
PROMPT
}

# ---- Spawn Workers ----

PIDS=()

for task in "$@"; do
  branch="worker/${task}"
  worktree_dir="$WORKTREE_BASE/$task"

  # Clean up any existing worktree for this task
  if [ -d "$worktree_dir" ]; then
    git -C "$PROJECT_DIR" worktree remove --force "$worktree_dir" 2>/dev/null || true
  fi
  git -C "$PROJECT_DIR" branch -D "$branch" 2>/dev/null || true

  # Create fresh worktree + branch
  git -C "$PROJECT_DIR" worktree add -b "$branch" "$worktree_dir" HEAD
  echo "Created worktree: $worktree_dir (branch: $branch)"

  # Spawn Claude in the worktree
  prompt=$(worker_prompt "$task")

  (
    cd "$worktree_dir"
    claude -p "$prompt" \
      --allowedTools "Read,Write,Edit,Bash,Glob,Grep" \
      > "$WORKERS_DIR/results/log-${task}.txt" 2>&1
    echo "Worker $task completed (exit $?)"
  ) &

  PIDS+=($!)
  echo "Spawned worker: $task (PID ${PIDS[-1]})"
done

echo ""
echo "=== All ${#PIDS[@]} workers spawned ==="
echo "Waiting for completion..."
echo ""

# ---- Wait for All Workers ----

FAILURES=0
for i in "${!PIDS[@]}"; do
  task="${@:$((i+1)):1}"
  if wait "${PIDS[$i]}"; then
    echo "DONE: $task"
  else
    echo "FAIL: $task (check $WORKERS_DIR/results/log-${task}.txt)"
    FAILURES=$((FAILURES + 1))
  fi
done

echo ""
echo "=== Summary ==="
echo "Workers completed: $#"
echo "Failures: $FAILURES"
echo ""
echo "Results: $WORKERS_DIR/results/"
echo "Worktree branches:"
for task in "$@"; do
  echo "  worker/$task"
done
echo ""
echo "Next step: ./scripts/judge.sh $*"
