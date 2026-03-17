# Autonomous Agent Architecture: Planner → Workers → Judge

> Status note: this is repo-level process research, not SipCheck product documentation. It does not describe the app's current implementation status.

## Goal
Parallelize autonomous work (building, testing, fixing) without context collapse or memory loss.

## Industry Research Summary

Researched Cursor, Devin, Manus, OpenHands, and general patterns (detailed reports in `research_output/`).

**Everyone converges on the same core pattern:**
- Planner decomposes work into independent tasks
- Workers execute in isolated contexts (VMs, worktrees, containers)
- Judge/verifier reviews results after workers complete
- No agent-to-agent communication (Devin explicitly argues against it)

**Key findings:**
- Agents degrade after ~35 min of continuous work — decompose into smaller tasks
- Context isolation > context management — don't manage the window, give each agent a fresh one
- File system is memory — workers checkpoint to `todo.md`/`progress.md`, not in-context
- KV-cache optimization matters at scale (Manus: 10x cost difference cached vs uncached)

## Planner vs Judge: Research-Confirmed Separation

**Decision: Planner and Judge are SEPARATE agents** (confirmed by 3 parallel research agents, March 2026).

### Evidence Summary

| Source | Finding |
|--------|---------|
| **Cursor** (R1) | Explicitly tried combining via "Integrator" — **"created more bottlenecks than it solved"**. Uses separate Planner (GPT-5.2), Workers, and Judge agents. |
| **Devin** (R2) | Uses integrated self-verification, but added "Devin Review" post-hoc layer → **+30% more issues caught**. Independent Agent-as-a-Judge research shows separate verifiers "dramatically outperform." |
| **Academic** (R3) | Self-preference bias: **5-7% score inflation** on own outputs (95% CI excluding zero). Fresh context detects hallucinations invisible during generation. Production systems (Claude Code Review, Open SWE, SWE-agent) all use separation. |

### Why Separation Works

1. **Self-preference bias is real** — same model rates its own output 5-7% higher
2. **Fresh context reduces blind spots** — LLMs catch errors in new sessions they miss during generation
3. **Cursor's lesson** — "removing complexity worked better than adding it"; the combined Integrator failed
4. **Adversarial by design** — "the person who writes the code shouldn't be the only one who reviews it"
5. **Framework matters more than model** — 22-point gap from scaffold design vs 0.8-point gap between models

### Judge Design Principles

- **Fresh context** — no shared history with workers (reduces bias)
- **Deterministic first** — run build + tests before subjective evaluation
- **Quality gate, not coordinator** — evaluates and reports, doesn't replan
- **Cycle boundary** — runs after ALL workers complete, not during
- **Reports to Planner** — pass/fail + reasoning feeds next planning cycle

### Research Reports
- `research_output/cursor_planner_judge_architecture.md` (R1: Cursor)
- `research_output/devin_verification_architecture_research.md` (R2: Devin)
- `research_output/planner_judge_separation_research.md` (R3: Academic/Industry)

## The Pattern

```
┌─────────────┐
│   PLANNER   │  expensive model, small context
│             │  - reads codebase structure
│             │  - decomposes into INDEPENDENT tasks
│             │  - writes task specs to files
└──────┬──────┘
       │ spawns N workers
       ▼
┌──────────┐  ┌──────────┐  ┌──────────┐
│ WORKER 1 │  │ WORKER 2 │  │ WORKER 3 │
│ worktree │  │ worktree │  │ worktree │
│ own ctx  │  │ own ctx  │  │ own ctx  │
│          │  │          │  │          │
│ code     │  │ code     │  │ code     │
│ build    │  │ build    │  │ build    │
│ fix loop │  │ fix loop │  │ fix loop │
└──────┬───┘  └────┬─────┘  └────┬─────┘
       │           │              │
       ▼           ▼              ▼
┌─────────────────────────────────────┐
│   JUDGE (separate agent, fresh ctx) │
│   1. Deterministic: build + tests   │
│   2. Evaluate: worker output vs plan│
│   3. Report: pass/fail + reasoning  │
│   4. If fail → feedback to PLANNER  │
└─────────────────────────────────────┘
```

## How It Maps to Tools

| Concept | Cursor | Devin | Manus | Claude Code |
|---------|--------|-------|-------|-------------|
| Execution env | Cloud VMs | Cloud VMs | E2B microVMs | Local machine |
| Isolation | Separate VMs | Separate VMs | Separate VMs | Git worktrees |
| Planner | GPT-5.2, recursive | Built-in planner | Orchestrator agent | You or Plan-mode agent |
| Workers | Up to 20 parallel | 1 per VM | 100+ parallel | Background agents |
| Feedback loop | Built-in judge | Built-in test runner | Built-in verifier | **Prompt-driven** |
| Cloud execution | Yes | Yes | Yes | No (local only) |

## Autonomous Testing: The Inner Loop

Every worker runs this loop internally. The "autonomy" is just putting the test command in the prompt.

```
Worker receives task spec
  │
  ├── 1. Read task spec
  ├── 2. Implement the change
  ├── 3. Run build/tests
  │     │
  │     ├── FAIL → read error → fix code → go to 3 (max 5 attempts)
  │     │
  │     └── PASS → continue
  │
  ├── 4. Git commit with descriptive message
  └── 5. Write summary to results file
```

### SipCheck Build Command for Workers

```bash
SIMULATOR_UDID="48FF0EDE-5280-4C70-AB5C-F06C750443DB"

xcodebuild -project SipCheck.xcodeproj -scheme SipCheck \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -configuration Debug build 2>&1
```

### Worker Prompt Template

```
You are an autonomous coding agent working on SipCheck (iOS/SwiftUI).

TASK: [describe the task]

CONVENTIONS:
- Use @EnvironmentObject for DrinkStore, not @Environment
- Use PreviewProvider structs, not #Preview macro
- No Swift macros (@Observable, @Model, #Preview)
- iOS 17+ target

AUTONOMOUS LOOP:
1. Implement the feature/fix
2. Run the build:
   xcodebuild -project SipCheck.xcodeproj -scheme SipCheck \
     -destination 'platform=iOS Simulator,id=48FF0EDE-5280-4C70-AB5C-F06C750443DB' \
     -configuration Debug build 2>&1
3. If build fails, read the errors, fix the code, go to step 2
4. Max 5 fix attempts. If still failing, document what's wrong
5. When green, commit with a descriptive message
6. Write a summary of what you did and any decisions made to [results path]
```

## Claude Code Implementation

### Spawning Parallel Workers

```python
# In Claude Code, spawn workers like this:
Agent(
  prompt="[task spec with build loop]",
  isolation="worktree",          # isolated git branch + directory
  run_in_background=True         # non-blocking, parallel
)
```

### Shell Script Wrapper

```bash
#!/bin/bash
# scripts/autonomous.sh
# Usage: ./scripts/autonomous.sh "task1" "task2" "task3"

SIMULATOR_UDID="48FF0EDE-5280-4C70-AB5C-F06C750443DB"
BUILD_CMD="xcodebuild -project SipCheck.xcodeproj -scheme SipCheck -destination 'platform=iOS Simulator,id=$SIMULATOR_UDID' build 2>&1"

for task in "$@"; do
  claude --print \
    --worktree \
    --allowedTools "Read,Write,Edit,Bash,Glob,Grep" \
    "You are an autonomous coding agent. Your task: $task

     RULES:
     - Implement the feature
     - Run: $BUILD_CMD
     - If build fails, fix and rebuild. Loop until green.
     - Max 5 fix attempts. If still failing, write what's wrong to /tmp/stuck.md
     - When green, git commit with descriptive message
     - Write summary to /tmp/results-\$(date +%s).md" &
done

wait
echo "All workers done. Review branches with: git branch"
```

## Key Design Rules

1. **Tasks MUST be independent** — no worker waits on another worker
2. **Keep tasks under 35 minutes** — agent quality degrades after this
3. **Workers checkpoint to files** — not context (Manus's insight)
4. **No agent-to-agent communication** — coordinate through files only (Devin's insight)
5. **Include the test command in the prompt** — that's the whole "autonomous" part
6. **Prefer 5 small tasks over 2 big ones** — more parallelism, less context pressure
7. **Judge runs AFTER all workers** — fresh context, reviews everything

## Rollout Plan

1. **Phase 1 (now):** Manual planner — you decompose tasks, spawn 2-3 workers with worktrees
2. **Phase 2:** Add build-loop to every worker prompt, verify fix-iterate cycle works
3. **Phase 3:** Add judge agent that reviews all branches post-completion
4. **Phase 4:** Script it — `scripts/autonomous.sh` for one-command parallel execution

## Sources

Detailed research reports:
- `research_output/cursor_agent_architecture_research.md`
- `research_output/autonomous_coding_agents_architecture_research.md`
- `research_output/autonomous_agent_architecture_research.md`
- `research_output/manus_ai_architecture_research.md`
