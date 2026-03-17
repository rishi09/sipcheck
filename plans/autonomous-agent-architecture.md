# Autonomous Agent Architecture
**Operational playbook for SipCheck parallel development**

---

## The Problem

Building 10+ screens with iterative build-fix-test loops fills context fast. A single agent doing tab bar + data models + verdict cards + tests in one session will hit compaction, lose earlier decisions, and degrade in quality after ~35 minutes.

## The Solution: Planner → Workers → Judge

Three distinct roles, communicating through files (not context), each with a fresh context window.

```
                      ┌──────────────┐
                      │   PLANNER    │  (me, main context)
                      │              │
                      │ Reads specs  │
                      │ Decomposes   │
                      │ Writes tasks │
                      └──────┬───────┘
                             │
                writes task specs to /tmp/sipcheck-workers/
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
       ┌────────────┐ ┌────────────┐ ┌────────────┐
       │  WORKER 1  │ │  WORKER 2  │ │  WORKER 3  │
       │  worktree  │ │  worktree  │ │  worktree  │
       │            │ │            │ │            │
       │ code       │ │ code       │ │ code       │
       │ build      │ │ build      │ │ build      │
       │ fix (x5)   │ │ fix (x5)   │ │ fix (x5)   │
       │ commit     │ │ commit     │ │ commit     │
       └─────┬──────┘ └─────┬──────┘ └─────┬──────┘
             │              │              │
        writes result files to /tmp/sipcheck-workers/
             │              │              │
             └──────────────┼──────────────┘
                            ▼
                    ┌───────────────┐
                    │  GATE JUDGE   │  (script, deterministic)
                    │               │
                    │ 1. Merge      │
                    │ 2. Build      │
                    │ 3. Unit tests │
                    │ 4. UI tests   │
                    │ 5. E2E tests  │
                    └───────┬───────┘
                            │
              if gates pass, spawn judge panels
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
       CODE JUDGES (parallel)      PRODUCT JUDGES (sequential on sim)
       ┌──────┐ ┌──────┐ ┌──────┐  ┌──────┐ ┌──────┐ ┌──────┐
       │ Spec │ │Design│ │Convn.│  │Button│ │ Flow │ │Chaos │
       └──┬───┘ └──┬───┘ └──┬───┘  └──┬───┘ └──┬───┘ └──┬───┘
          │        │        │         │        │        │
          │        │        │      ┌──┴───┐ ┌──┴───┐ ┌──┴───┐
          │        │        │      │Voice │ │Speed │ │Simple│
          │        │        │      └──┬───┘ └──┬───┘ └──┬───┘
          └────────┼────────┘         └────────┼────────┘
                   │                           │
                   └───────────┬───────────────┘
                               ▼
                       ┌───────────────┐
                       │ REVIEW AGENT  │
                       │               │
                       │ Synthesizes   │
                       │ 9 reports →   │
                       │ 1 brief       │
                       └───────┬───────┘
                               │
                               ▼
                       ┌───────────────┐
                       │    RISHI      │
                       │               │
                       │ 1 summary     │
                       │ screenshots   │
                       │ clear action  │
                       │ Cmd+R device  │
                       └───────────────┘
```

## The Judge Panel

Not one judge — a **panel of specialists**, each with a narrow lens and fresh context.

### Layer 1: Gate Judge (deterministic, `judge.sh`)

Runs automatically. No AI needed. Non-negotiable.

| Gate | Tool | Pass criteria |
|------|------|---------------|
| Build compiles | `xcodebuild build` | Exit 0 |
| Unit tests | `run_tests.sh --unit-only` | All pass |
| UI tests | `run_tests.sh --ui-only` | All pass |
| E2E flows | `e2e_test.sh` | All pass |

If any gate fails → stop. Workers fix before subjective review.

### Layer 2: Code Judges (AI agents, parallel, fresh context each)

Only run after all gates pass. Each judge reads code and checks a specific dimension.

| Judge | What it checks | Reads | Writes |
|-------|---------------|-------|--------|
| **Spec Judge** | Did workers build what was asked? Missing features? Wrong behavior? Edge cases from the flows doc? | Task specs + worker results + changed code + `user-flows-design.md` | `judge/spec-review.md` |
| **Design Judge** | Do colors match the design system? Typography correct? Component hierarchy right? Spacing reasonable? | `design-direction.md` + screenshots + changed view code | `judge/design-review.md` |
| **Convention Judge** | CLAUDE.md rules followed? No macros? Right patterns? Accessibility IDs on interactive elements? No hardcoded strings? | `CLAUDE.md` + changed code | `judge/convention-review.md` |

### Layer 3: Product Judges (AI agents, parallel — test the app like a user)

These don't review code. They interact with the running app via AXe on the simulator and evaluate the **experience**.

| Judge | Question it answers | Method | Writes |
|-------|-------------------|--------|--------|
| Judge | Question it answers | Method | Tier | Writes |
|-------|-------------------|--------|------|--------|
| **Button Judge** | Does every interactive element actually work? | AXe: `describe-ui` → find all buttons/fields → `tap` each → verify state changed. If tapping does nothing, that's a fail. | 2 (sim) | `judge/buttons-review.md` |
| **Flow Judge** | Can a user complete each flow start-to-finish? | AXe: walk each flow sequentially. Onboarding → scan → verdict → save → journal → detail → edit → back. Screenshot at every step. Flag dead ends. | 2 (sim) | `judge/flows-review.md` |
| **Speed Judge** | Is it fast enough for a bar? | AXe + timestamps: measure tap-to-response. Local UI < 300ms. AI calls < 2s. Flag unnecessary spinners or animations that delay. | 2 (sim) | `judge/speed-review.md` |
| **Delight Judge** | Does the app feel alive or like a wireframe? | AXe + screenshot comparison: Check for spring animations on verdict cards (scale 0.95→1.0 + fade per spec). Haptic triggers on star rating taps. Smooth tab transitions. Loading states that feel intentional. The camera viewfinder brackets pulsing during scan. If a screen just "appears" without transition, flag it. | 2 (sim) | `judge/delight-review.md` |
| **Consistency Judge** | Are similar things treated the same way? | Read all view files. Check: Is the back button always in the same spot? Are all list rows the same height pattern? Do all forms use the same spacing? Are all destructive actions red? Do all sheets dismiss the same way? Are all navigation titles the same font weight? Cross-reference screens: if Journal list rows have 50x50 thumbnails, do scan history rows match? | 1 (code) | `judge/consistency-review.md` |
| **Voice Judge** | Does the copy match the brand brief? | Read all user-facing strings. Check: "Calm Authority" tone? No beer-bro language? Button labels action-oriented? Error messages helpful, not generic? Consistent terminology (always "beer" not sometimes "brew")? | 1 (code) | `judge/voice-review.md` |
| **Simplicity Judge** | Are we asking too much from the user? | For every form: count the fields. For each: "essential? Could the app infer this from a photo or prior scan?" For each screen: "Glanceable in 2 seconds?" Flag unnecessary fields, steps that could be cut, places where a photo replaces 3 text inputs. | 1 (code) | `judge/simplicity-review.md` |

**Why these judges matter:**

The **Simplicity Judge** catches the proto problem: we ask users to type beer name, brewery, style, ABV, rating, and notes when a photo + "was it good?" might be enough. Every field must pass: **"Would someone at a bar, in dim lighting, with a beer in one hand, fill this out?"**

The **Consistency Judge** catches the death-by-a-thousand-cuts problem. No single inconsistency is a bug, but accumulated inconsistencies make the app feel unfinished. If the Journal uses 8pt corner radius but Profile uses 12pt, that's not a bug — but the Consistency Judge flags it.

The **Delight Judge** catches the "it works but it's dead" problem. The spec calls for spring animations on verdict cards, haptic feedback on star taps, pulsing brackets on the viewfinder. Without this judge, workers will build screens that function correctly but feel like wireframes.

### Future Judges (product + UX focused — add as flows mature)

**Sprint 2+ (after real components exist):**

| Judge | UX question it answers | Method | When |
|-------|----------------------|--------|------|
| **Empty State Judge** | What does a first-time user see? Is "no beers yet" helpful or just blank? Does it guide them to scan? | AXe: fresh install, navigate every screen, screenshot each empty state | After Journal + Profile tabs built |
| **Chaos Judge** | What breaks when users don't follow the happy path? Tab-hop mid-scan, dismiss a form halfway, go back 3 times. | AXe: 20+ random tap sequences, flag stuck states, blank screens, crashes | After 3+ flows connected |
| **Onboarding Judge** | Can a new user go from "what is this?" to first verdict in under 30 seconds? Is the persona picker obvious in 5s? | AXe: fresh install, time each step, screenshot. Count taps to first verdict. | After onboarding redesign |

**Sprint 3+ (after data flows working):**

| Judge | UX question it answers | Method | When |
|-------|----------------------|--------|------|
| **Permission Denied Judge** | What happens when someone says no to camera? Do they feel stuck or guided? | AXe + `simctl privacy`: deny camera, verify helpful error + "Type a beer name instead" is obvious | After Check tab built |
| **Error Judge** | What does "no internet at the grocery store" look like? Is "Your Call" the right fallback? Does it feel broken or graceful? | Airplane mode + AXe: scan a beer offline, verify queuing UX | After offline flow built |
| **Form Validation Judge** | When someone taps Save with no rating, what happens? Is the error helpful or just "Error"? | AXe: submit blank forms, verify specific actionable messages | After Log flow built |

**Sprint 4+ (polish):**

| Judge | UX question it answers | Method | When |
|-------|----------------------|--------|------|
| **Lifecycle Judge** | "I was rating a beer and got a phone call. When I come back, is my 4-star rating still there?" | XCUITest: background mid-form, return, verify state | After all forms built |
| **Competitor Judge** | How does our scan-to-verdict time compare to Vivino? Is our journal nicer than Untappd's? | Side-by-side flow comparison using `research_output/` | Before launch |

Note: Product judges using AXe run **sequentially** (one simulator). Code judges (Tier 1) run in parallel.

**This list will shift when Manus mockups arrive** (task F8TFU6PQttt7ErUgVwrp6L). Visual targets will sharpen what Design, Consistency, and Delight judges compare against.

### Layer 4: Review Agent (synthesizer)

Reads ALL judge reports (code + product) and produces a single brief for Rishi:

- **Blockers** (must fix — broken buttons, stuck flows, crashes)
- **Product Issues** (works but feels wrong — too many fields, wrong tone, slow)
- **Code Issues** (convention violations, missing a11y IDs, design mismatches)
- **Simplicity Report** — "Here's what we could cut or make easier"
- **Nitpicks** (nice to have, skip if time-pressed)
- **Screenshots** with callouts at each flow step
- **Recommendation**: SHIP / FIX (with specific list) / REPLAN
- **Device build status**: "Ready for Cmd+R" or "Not ready, because..."

Rishi sees ONE document. The review agent has already filtered, deduplicated, and prioritized across all 9 judge reports.

---

## Why This Works (Research-Confirmed)

| Finding | Source |
|---------|--------|
| Agents degrade after ~35 min continuous work | Cursor, Devin, Manus |
| Self-preference bias: 5-7% score inflation on own output | Academic (95% CI excluding zero) |
| Cursor tried combining Planner+Judge ("Integrator") — "created more bottlenecks than it solved" | Cursor R1 |
| Devin added separate "Devin Review" post-hoc → +30% more issues caught | Devin R2 |
| File system is memory — checkpoint to files, not context | Manus architecture |
| No agent-to-agent communication — coordinate through files only | Devin (explicit design choice) |
| Framework matters more than model — 22pt gap from scaffold vs 0.8pt from model | Academic |

Detailed reports: `research_output/cursor_planner_judge_architecture.md`, `devin_verification_architecture_research.md`, `planner_judge_separation_research.md`

---

## File Protocol: How Agents Share Knowledge

All communication happens through `/tmp/sipcheck-workers/`. No agent reads another agent's context. The file system IS the shared memory.

```
/tmp/sipcheck-workers/
  tasks/
    task-tab-bar.md               # Planner writes. Worker reads.
    task-data-models.md
    task-verdict-card.md

  reasoning/
    reasoning-tab-bar.md          # Worker writes WHY it made each decision.
    reasoning-data-models.md      # Judges read this to give targeted feedback.

  knowledge/
    findings.md                   # Append-only. Every judge writes. Every worker reads.
    resolved.md                   # Worker marks findings as fixed (with commit hash + how).
    patterns.md                   # Accumulates ACROSS sprints. "We keep seeing X."

  results/
    result-tab-bar.md             # Worker writes final summary.
    result-data-models.md

  judge/
    spec-review.md                # Individual judge reports
    design-review.md
    convention-review.md
    consistency-review.md
    delight-review.md
    buttons-review.md
    flows-review.md
    voice-review.md
    simplicity-review.md
    speed-review.md
    review-brief.md               # Reviewer synthesis → Rishi

  screenshots/
    tab-bar-home.png
    verdict-try-it.png
```

### Worker Reasoning File (Worker → Judges)

Workers don't just write code — they explain their thinking. This is critical: when a judge gives feedback, the worker needs to understand what went wrong. Without reasoning, the judge says "this is wrong" but the worker doesn't know WHY it chose that approach.

```markdown
# Reasoning: [task-name]

## Decision Log

### 1. Tab bar icon choice
**Chose:** SF Symbol `camera.viewfinder` for Check tab
**Why:** Matches the scan/camera metaphor from user-flows-design.md line 12.
  The design spec says camera viewfinder, not a generic camera icon.
**Alternatives considered:** `camera.fill` (too generic), `barcode.viewfinder` (too specific)

### 2. Tab bar tint color
**Chose:** Teal accent (#4ECDC4) for selected tab
**Why:** design-direction.md line 32 specifies this as the primary/active color.
**Trade-off:** Could use white for selected + teal for accent, but spec is explicit.

### 3. Default tab on launch
**Chose:** Check tab (index 0)
**Why:** user-flows-design.md line 17: "Default tab on launch: Check (the core action)"
```

When a judge says "the tab icon is wrong," the worker can read its own reasoning, see "I chose camera.viewfinder because of line 12 in the spec," and either defend the choice or understand where it misread the spec.

### Finding Format (Judge → Knowledge Store → Worker)

```markdown
## [BLOCKER] Convention Judge — 2026-03-16 22:14
**Task:** tab-bar
**File:** SipCheck/Views/MainTabView.swift:23
**Finding:** Uses #Preview macro instead of PreviewProvider struct
**Expected:** PreviewProvider (per CLAUDE.md: "No Swift macros")
**Worker reasoning ref:** reasoning-tab-bar.md — no reasoning given for preview choice
**Suggested fix:** Replace #Preview { MainTabView() } with struct MainTabView_Previews: PreviewProvider { ... }
```

```markdown
## [ISSUE] Simplicity Judge — 2026-03-16 22:15
**Task:** tab-bar
**File:** SipCheck/Views/MainTabView.swift:8-12
**Finding:** Settings tab visible from day 1. Only 2 settings exist (persona, default tab).
  Consider: merge settings into Profile tab until there are 5+ settings.
**Worker reasoning ref:** reasoning-tab-bar.md §3 — worker followed spec literally ("4 tabs")
**Note:** This is a product question. If spec says 4 tabs, worker was right to build 4.
  Flag for Rishi.
```

### Resolved Format (Worker → Knowledge Store)

```markdown
## RESOLVED — Convention Judge finding from 22:14
**Commit:** a1b2c3d
**What I fixed:** Replaced #Preview with PreviewProvider struct
**How:** Added `struct MainTabView_Previews: PreviewProvider` per CLAUDE.md convention
**Lesson for patterns.md:** Always use PreviewProvider, never #Preview, in this project
```

### Task Spec Format (Planner → Worker)

```markdown
# Task: [name]
Branch: worker/[name]

## What to Build
[Concrete description of the screen/component/model]

## Files to Create/Modify
- Create: SipCheck/Views/MainTabView.swift
- Modify: SipCheck/SipCheckApp.swift (replace HomeView with MainTabView)

## Acceptance Criteria
1. Build compiles (xcodebuild build exits 0)
2. [Specific assertions about behavior]
3. [Specific UI elements that must exist]

## Reference
- Design spec: plans/user-flows-design-2026-03-16.md, lines X-Y
- Visual spec: plans/design-direction-2026-03-16.md, lines X-Y

## Do NOT Touch
- [Files other workers are modifying]
- [Existing accessibility identifiers]
```

### Result Format (Worker → Judge/Planner)

```markdown
# Result: [name]
Branch: worker/[name]
Status: GREEN | RED | STUCK

## What I Did
- [List of changes with file:line references]

## Build Status
- Compile: PASS (attempt 2 of 5)
- Errors fixed: [description of what broke and how I fixed it]

## Decisions Made
- [Any judgment calls the worker made]

## Files Changed
- Created: SipCheck/Views/MainTabView.swift (85 lines)
- Modified: SipCheck/SipCheckApp.swift (lines 44-54)

## Open Questions
- [Anything the worker wasn't sure about]
```

### Judge Report Format (Judge → Planner)

```markdown
# Judge Report
Date: [timestamp]

## Merge Status
- worker/tab-bar: MERGED | CONFLICT | REJECTED
- worker/data-models: MERGED | CONFLICT | REJECTED

## Gate Results
| Gate | Status | Detail |
|------|--------|--------|
| Build compiles | PASS/FAIL | error message if fail |
| Unit tests | PASS/FAIL | X/Y passed |
| UI tests | PASS/FAIL | X/Y passed |
| E2E flows | PASS/FAIL | X/Y passed |

## Visual Check
- [Screenshot paths and observations]

## Issues Found
- [Anything that doesn't match spec]
- [Merge conflicts and how resolved]

## Recommendation
SHIP | FIX (list what) | REPLAN (list what)
```

---

## The Inner Loop: Workers + Judges Together

The old model was: workers build, then judges review after. That's a post-mortem — by the time a judge finds a problem, the worker's context is gone.

**The new model**: judges are INLINE. They run inside the worker's build loop. The worker codes, judges check, worker fixes, judges re-check. The loop continues until all judges pass. The reviewer at the end should find nothing — if it does, the loop broke upstream.

```
Worker receives task spec
  │
  ├── 1. Read task spec + shared knowledge (findings.md, patterns.md)
  ├── 2. Implement the change
  ├── 3. Write reasoning file (WHY each decision was made)
  ├── 4. Build (compile check)
  │     ├── FAIL → read error → fix → go to 4 (max 5)
  │     └── PASS ↓
  │
  ├── 5. TIER 1: FAST JUDGES (parallel, code-only, no simulator)
  │     ├── Convention Judge
  │     ├── Simplicity Judge
  │     ├── Voice Judge
  │     ├── Consistency Judge
  │     │
  │     ├── Judges write findings → knowledge/findings.md
  │     │   (with references to worker's reasoning file)
  │     ├── BLOCKERS found → Worker reads findings → fix → go to 2
  │     └── CLEAN → continue (max 3 fix cycles per tier)
  │
  ├── 6. Install on simulator + screenshot
  │
  ├── 7. TIER 2: PRODUCT JUDGES (sequential, need simulator)
  │     ├── Button Judge
  │     ├── Flow Judge
  │     ├── Speed Judge
  │     ├── Delight Judge
  │     │
  │     ├── Judges write findings → knowledge/findings.md
  │     ├── BLOCKERS found → Worker reads findings → fix → go to 2
  │     └── CLEAN → continue (max 3 fix cycles)
  │
  ├── 8. TIER 3: SPEC JUDGES (parallel, code + screenshots)
  │     ├── Spec Judge
  │     ├── Design Judge
  │     │
  │     ├── Judges write findings → knowledge/findings.md
  │     ├── BLOCKERS found → Worker reads findings → fix → go to 2
  │     └── CLEAN → continue (max 3 fix cycles)
  │
  ├── 9. ALL TIERS CLEAN → git commit
  ├── 10. Write result summary
  └── 11. Mark all findings as resolved (with commit hash + how)
```

### Why Three Tiers?

Fix cheap problems first. No point running the Button Judge on code that violates conventions (Tier 1 catches that). No point running the Spec Judge if buttons don't work (Tier 2 catches that). Each tier gates the next.

### Max Iterations

Each tier gets max 3 fix cycles. If a worker can't satisfy a judge tier after 3 attempts:
- Write STUCK status to results file
- Document: what the judge wants, what the worker tried, why it's stuck
- Planner reads the stuck report and either adjusts the spec, reassigns, or escalates to Rishi

### The Feedback Loop

```
Judge finds issue
  → writes finding to knowledge/findings.md
  → references worker's reasoning file ("you chose X because of Y, but...")
  → suggests specific fix

Worker reads finding
  → understands WHY its choice was wrong (because reasoning is documented)
  → fixes the code
  → updates reasoning file (new decision log entry)
  → rebuilds

Judge re-checks
  → reads updated reasoning
  → verifies fix addresses the root cause, not just the symptom
```

Without the reasoning file, the feedback loop is blind: "this is wrong" → worker guesses what to change. With reasoning, it's targeted: "you chose X because you misread line 12 of the spec — it actually says Y."

---

## Simulator Constraint

**Workers compile in parallel. Simulator interactions are sequential.**

Multiple `xcodebuild build` can run simultaneously (separate DerivedData per worktree). But only one process can interact with the simulator at a time (install, launch, test, screenshot).

| Phase | Parallelism | Simulator? |
|-------|-------------|------------|
| Workers: code + Tier 1 judges | Parallel | No |
| Workers: Tier 2 judges | Sequential per worker | Yes |
| Workers: Tier 3 judges | Parallel | No (reads screenshots) |
| Reviewer: final synthesis | Sequential | No |

When multiple workers need Tier 2 (simulator), they queue. Worker A's Tier 2 runs, then Worker B's Tier 2, etc. Tier 1 and Tier 3 judges run in parallel since they only read code/files.

---

## Spawning Workers

### Method 1: Inside Claude Code (primary)

Planner uses the `Agent` tool to spawn workers as subagents.

Each worker gets:
- Fresh context (no history from planner)
- The task spec (inlined in prompt)
- The build + judge loop instructions
- Paths to knowledge store (findings.md, patterns.md, reasoning file)

Planner spawns multiple Agent calls in parallel for independent tasks.

### Method 2: CLI (for overnight/unattended runs)

```bash
./scripts/autonomous.sh task-tab-bar task-data-models task-verdict-card
```

### Method 3: Manual sequential (simplest)

Planner builds each screen one at a time, running judges mentally. No parallelism, but no coordination overhead. Good for tightly coupled changes.

---

## Worker Prompt Template

```
You are an autonomous coding agent working on SipCheck (iOS/SwiftUI).

PROJECT CONVENTIONS:
- Use @EnvironmentObject for DrinkStore, not @Environment
- Use PreviewProvider structs, not #Preview macro
- No Swift macros (@Observable, @Model, #Preview)
- iOS 17+ target, SF Pro typography, no custom fonts
- Color tokens: plans/design-direction-2026-03-16.md

YOUR TASK:
[task spec content here]

SHARED KNOWLEDGE:
Before you start, read these files if they exist:
- /tmp/sipcheck-workers/knowledge/findings.md (open issues from other judges)
- /tmp/sipcheck-workers/knowledge/patterns.md (lessons from prior sprints)

REASONING REQUIREMENT:
As you work, maintain a reasoning file at:
  /tmp/sipcheck-workers/reasoning/reasoning-{task-name}.md
For EVERY significant decision, log:
- What you chose
- Why (reference specific spec lines, design docs, or code)
- What alternatives you considered
This file is how judges give you targeted feedback. Without it, feedback is blind.

AUTONOMOUS BUILD + JUDGE LOOP:
1. Read the task spec and shared knowledge
2. Implement the change
3. Log your reasoning
4. Build:
   xcodebuild -project SipCheck.xcodeproj -scheme SipCheck \
     -destination 'platform=iOS Simulator,id=48FF0EDE-5280-4C70-AB5C-F06C750443DB' \
     -configuration Debug build 2>&1 | tail -20
5. If build fails → read error → fix → go to 4 (max 5 attempts)
6. When build passes → read knowledge/findings.md for any new judge findings
7. If there are BLOCKER findings for your task → fix them → go to 2
8. When clean on all judges → commit with descriptive message
9. Write result to: /tmp/sipcheck-workers/results/result-{task-name}.md
10. Mark resolved findings in: /tmp/sipcheck-workers/knowledge/resolved.md

RULES:
- Do NOT modify files listed in "Do NOT Touch"
- Do NOT add features beyond the task spec
- Do NOT remove existing accessibility identifiers
- Do NOT use Swift macros
- ALWAYS log reasoning before committing
- If stuck after 3 fix attempts on any judge tier, write STUCK and stop
```

---

## Task Decomposition: SipCheck Redesign

### Sprint 1: Foundation (3 parallel workers)

These are fully independent — no file conflicts.

| Worker | Task | Creates | Modifies | ~Time |
|--------|------|---------|----------|-------|
| W1 | Tab bar navigation | `MainTabView.swift` | `SipCheckApp.swift` | 15 min |
| W2 | Data models (Scan + JournalEntry) | `Scan.swift`, `JournalEntry.swift`, `ScanStore.swift`, `JournalStore.swift` | — | 20 min |
| W3 | Design system (colors + typography) | `DesignSystem.swift` | — | 10 min |

**After Sprint 1:** Judge merges, runs tests, reports. Planner reviews.

### Sprint 2: Core Components (3 parallel workers)

Depends on Sprint 1 being merged.

| Worker | Task | Creates | Modifies |
|--------|------|---------|----------|
| W4 | Verdict card component | `VerdictCardView.swift` | — |
| W5 | Star rating (1-5) | `StarRatingView.swift` | `RatingPicker.swift` |
| W6 | Onboarding persona picker | — | `OnboardingView.swift` |

### Sprint 3: Screens (2-3 parallel workers)

Depends on Sprint 1 + 2 being merged.

| Worker | Task | Creates/Modifies |
|--------|------|-----------------|
| W7 | Check tab (camera + text scan → verdict) | `CheckTabView.swift`, modify `CheckBeerView.swift` |
| W8 | Journal tab (list + detail + log flow) | `JournalTabView.swift`, modify `BeerListView.swift`, `BeerDetailView.swift` |
| W9 | Profile tab (stats + scan history) | `ProfileTabView.swift`, modify `StatsView.swift` |

### Sprint 4: Integration + Polish

Sequential (too coupled for parallelism):
- Settings tab
- Scan-to-Journal linking
- Data migration (Drink → Scan + JournalEntry)
- Test suite updates
- E2E script rewrite

---

## Rishi's Role in the Loop

Rishi is the **final gate**, not the first reviewer. By the time Rishi sees anything, it has already passed through every judge tier inline — the workers have already fixed everything the judges caught.

```
Planner decomposes tasks, writes specs + reasoning expectations
    ↓
Workers build with INLINE judge loop:
  code → Tier 1 judges → fix → Tier 2 judges → fix → Tier 3 judges → fix → clean
  (each worker loops until all judges pass, max 3 cycles per tier)
    ↓
Workers commit clean code + reasoning files + resolved findings
    ↓
Gate Judge: build + unit + UI + E2E on merged result (deterministic, non-negotiable)
    ↓
Reviewer: reads all judge reports, worker reasoning, gate results
  - Should be BORED — inline judges already caught everything
  - If reviewer finds new issues, that means the inline loop has a gap
  - Produces 1 brief for Rishi
    ↓
Rishi gets:
  - 1 curated summary
  - Annotated screenshots at each flow step
  - Device-ready build (ready for Cmd+R)
  - Only things that need HUMAN judgment
    ↓
If approved → merge to main, next sprint
If changes needed → specific feedback → Planner adjusts specs
```

**What the system handles (Rishi doesn't check):**
- Does it compile? (Gate Judge)
- Do tests pass? (Gate Judge)
- Does code match spec? (Spec Judge, inline)
- Are colors/typography right? (Design Judge, inline)
- Are conventions followed? (Convention Judge, inline)
- Do buttons work? (Button Judge, inline)
- Are flows coherent? (Flow Judge, inline)
- Is it fast? (Speed Judge, inline)
- Is it consistent? (Consistency Judge, inline)
- Does it feel alive? (Delight Judge, inline)
- Is the copy right? (Voice Judge, inline)
- Is it simple enough? (Simplicity Judge, inline)

**What ONLY Rishi can check:**
- Does it feel right on the physical device?
- Is this the right product direction?
- Camera behavior in real-world lighting
- Haptic feedback quality (simulator can't test this)
- "Would my wife/lawyer buddy actually use this?"

**Note:** This architecture will shift once Manus delivers the full flow mockups (task F8TFU6PQttt7ErUgVwrp6L). The visual targets will give the Design Judge concrete reference images, and may change what the Consistency and Delight judges look for.

---

## Key Rules

1. **Judges are inline, not post-hoc** — judges run inside the worker loop, not after it. If a judge finds a problem, the worker fixes it before committing.
2. **Workers explain their reasoning** — every decision logged to reasoning file. Without reasoning, judge feedback is blind.
3. **File system is the shared memory** — findings.md, resolved.md, patterns.md. No agent reads another's context.
4. **The reviewer should be bored** — if the reviewer finds something, the inline loop has a gap. Fix the gap, not just the finding.
5. **Tasks MUST be independent** — no worker waits on another worker's output.
6. **Keep tasks under 35 minutes** — agent quality degrades after this.
7. **3 judge tiers, gated** — Tier 1 (code, fast) → Tier 2 (product, sim) → Tier 3 (spec, thorough). Fix cheap problems before running expensive judges.
8. **Max 3 fix cycles per tier** — if stuck after 3, write STUCK and stop. Planner decides what to do.
9. **5 small tasks > 2 big ones** — more parallelism, less context pressure.
10. **Patterns accumulate across sprints** — patterns.md is a living document. What we learn in Sprint 1 makes Sprint 2 smoother.
11. **This architecture will evolve** — once Manus mockups arrive and real flows are built, judges will get more specific. Start with the structure, refine the details.
