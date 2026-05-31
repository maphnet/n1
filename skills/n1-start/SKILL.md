---
name: n1-start
description: "Core orchestrator. Start working on a task: /n1:n1-start TRID-510 or /n1:n1-start need CSV export for users. Handles the full cycle: ticket → analysis → brainstorm → plan → implement → QA → review → PR."
argument-hint: "<ticket-id or brain dump>"
---

# N1 Core Orchestrator

## Overview

Single entry point for all task work. Accepts a ticket ID or a brain dump, then orchestrates the full development cycle using specialized agent personas: product-analyst, solution-architect, developer, qa-engineer, code-reviewer, security-reviewer, and tech-writer.

**Announce at start:** "I'm using the n1-start skill to work on this task."

## Prerequisites

Check if `.n1/n1.config.json` exists on disk (use Read or Bash `test -f`, NOT git commands — `.n1/` is gitignored):

- **If missing:** Tell the user: "N1 is not configured for this project. Would you like to run `/n1:n1-init` to set it up?" **Wait for response.** If yes — invoke `/n1:n1-init`, then resume. If no — **STOP.**
- **If exists:** Continue.

## Input Parsing

The user provides one of:
- **Ticket ID** — matches the tracker prefix from config (e.g., `TRID-510`, `PROJ-42`)
- **File path** — a path to a file containing requirements
- **Brain dump** — free-text description of what needs to be built
- **Resume** — ticket ID or slug where memory already exists

### Detect input type:

1. Read `.n1/n1.config.json` → get `tracker.prefix`
2. If input matches `<prefix>-<number>` pattern → **Ticket mode**
3. If input is a file path that exists on disk → **File mode**
4. Otherwise → **Brain dump mode**

## Model Resolution

When spawning any agent, resolve its model:

1. Read `.n1/n1.config.json` → check `models.<agent-name>`
2. If the key exists and value is not null → use that model
3. Otherwise → use the model from the agent's frontmatter default

This allows per-project model overrides (e.g., using sonnet for developer in a cost-sensitive project).

## Working Branch

N1 owns the branch lifecycle. The working branch is created **eagerly, the moment the `<ID>` is resolved**, so no commit (from implementation, QA fixes, or review fixes) can ever reach the default branch. This procedure is called at each ID-resolution point (see Step 1 and Memory Check). It is **idempotent** — safe to call again on resume.

**PROCEDURE: Ensure Working Branch (`<ID>`)**

1. Compute the target branch name from `git.branchPattern` (config) + `<ID>`:
   - `{prefix}-{id}` → e.g. `TRID-510`
   - `{id}` → e.g. `510`
   - `{slug}` or `feature/{slug}` → e.g. `feature/csv-export-users`

   Sanitize for git ref validity: lowercase the slug, replace spaces and illegal characters with `-`, collapse repeats, trim leading/trailing `-`. Ticket IDs are already ref-safe; only slugs need sanitizing.

2. Read current state:
   ```bash
   CURRENT=$(git branch --show-current)
   DEFAULT=<git.defaultBranch from config>
   ```

3. Decide (smart reuse + safe create):
   - **`CURRENT` == `TARGET`** → already on it. Reuse silently.
   - **A local branch named `TARGET` already exists** → `git checkout <TARGET>`.
   - **`CURRENT` == `DEFAULT`** → `git checkout -b <TARGET>` (any uncommitted changes carry over to the new branch — this is intended).
   - **`CURRENT` is some OTHER branch** → STOP and ask:
     ```
     You're on branch '<CURRENT>', not the default ('<DEFAULT>').
     1 — Create '<TARGET>' from here
     2 — Switch to '<DEFAULT>' and branch '<TARGET>' from there
     3 — Keep working on '<CURRENT>'
     ```
     Wait for the choice, then act accordingly.

4. Report: "Working on branch `<TARGET>`."

No `fetch`/`pull` is performed — the branch is created from the local default branch's current HEAD. The user owns keeping their local default up to date.

## Memory Check (Resume Support)

Check if `.n1/memory/<input>/overview.md` exists:

- **If exists:** Read the overview frontmatter to determine current step. Run **Ensure Working Branch(`<ID>`)** (see Working Branch above) to re-check out the branch — this covers resuming from `main` or a different branch. Then resume from where work left off: read the dependency files for the current step (see dependency map below) and continue.
- **If not exists:** Fresh start. Create `.n1/memory/<ID>/` directory.

### Step dependency map

| Step | Reads | Writes |
|------|-------|--------|
| ticket | — | `ticket.md` |
| analysis | `ticket.md` | `analysis.md` |
| brainstorm | `ticket.md`, `analysis.md` | `brainstorm.md` |
| plan | `ticket.md`, `brainstorm.md`, `analysis.md` | `plan.md` |
| implementation | `brainstorm.md`, `plan.md` | `implementation.md` |
| qa | `ticket.md`, `implementation.md`, `plan.md` | `qa.md` |
| review | `ticket.md`, `brainstorm.md`, `implementation.md`, `qa.md` | `review.md` |
| pr | `overview.md`, `review.md`, `qa.md`, `implementation.md` | — |
| ci | `overview.md`, `plan.md`, `implementation.md` | `overview.md` (CI status) |

Each step reads ONLY the files listed in its dependency column, not the full history.

## Pipeline Steps

Steps 3 (Brainstorm) and 4 (Plan checkpoint) are **INTERACTIVE** — Superpowers handles user interaction during brainstorming, and the orchestrator pauses for explicit plan approval. All other steps run autonomously.

### 1. REQUIREMENTS ANALYSIS

**Spawn agent:** product-analyst

Resolve model for `product-analyst` (see Model Resolution above).

The product-analyst accepts three input modes. Choose based on input type:

**Ticket mode** (input matches `<prefix>-<number>`):
0. The `<ID>` is already known (the ticket ID). Run **Ensure Working Branch(`<ticketId>`)** (see Working Branch above) now, before spawning the analyst.
1. Read `.n1/n1.config.json` → `tracker.mcp` and `tracker.operations`
2. Spawn product-analyst with:
   - `mode`: "ticket"
   - `ticketId`: the parsed ticket ID
   - `trackerMcp`: from config
   - `operations`: from config
3. After agent returns, update tracker status to In Progress:
   - Call `mcp__<tracker.mcp>__<tracker.operations.moveStatus>`

**File mode** (input is a file path that exists on disk):
1. Spawn product-analyst with:
   - `mode`: "file"
   - `filePath`: the provided path

**Brain dump mode** (free text):
1. Spawn product-analyst with:
   - `mode`: "text"
   - `content`: the raw input text

**Tracker ticket creation (brain dump and file modes):**

After product-analyst returns, if the input was a brain dump or file path, AND a tracker is configured (`tracker.mcp` is not null AND `tracker.operations.createIssue` exists):

Ask the user:
```
The task has been structured. Would you like to create a tracker ticket?
1 — Yes, create a ticket in <tracker.mcp>
2 — No, continue without a ticket
```

**If 1 (Yes):**
1. Extract the Title and structured content from the product-analyst output
2. **Resolve ticket tagging.** Read `ticketTagging` from `.n1/n1.config.json`.
   - **If `ticketTagging.enabled` is `true` AND `ticketTagging.service` is a non-empty string** → tagging is ON:
     - `<summary>` = `<service> | <Title>` — but if `<Title>` already begins with `<service> |`, use `<Title>` unchanged (idempotency guard for resume/retry).
     - `<description>` = `**Service:** <service>` as the first line, a blank line, then the Core Ask + Description + Acceptance Criteria sections.
   - **Otherwise** (block missing, `enabled` false, or `service` empty) → tagging is OFF:
     - `<summary>` = the Title from product-analyst output.
     - `<description>` = the Core Ask + Description + Acceptance Criteria sections.
3. Create the ticket via MCP:
   - **YouTrack:** Call `mcp__<tracker.mcp>__<tracker.operations.createIssue>` with:
     - `project`: `tracker.projectKey`
     - `summary`: `<summary>`
     - `description`: `<description>`
   - **Jira:** First resolve `cloudId` via `mcp__<tracker.mcp>__getAccessibleAtlassianResources`, then call `mcp__<tracker.mcp>__<tracker.operations.createIssue>` with:
     - `cloudId`: resolved cloud ID
     - `projectKey`: `tracker.projectKey`
     - `issueTypeName`: "Task"
     - `summary`: `<summary>`
     - `description`: `<description>`
4. Use the returned ticket ID as the memory `<ID>` (replacing the slug). Now that the final `<ID>` is known, run **Ensure Working Branch(`<new ticket ID>`)** (see Working Branch above).
5. Extract the ticket URL from the MCP response (YouTrack returns it in the response body; for Jira construct it as `https://<cloud>/browse/<key>` from the response)
6. Report: "Created ticket **[<ID>](<ticket URL>)**: <title>"
7. After writing ticket.md and overview.md, update tracker status to In Progress (same as ticket mode — call `mcp__<tracker.mcp>__<tracker.operations.moveStatus>`)

**If 2 (No):**
- Use description slug as memory ID for brain dump (e.g., `csv-export-users`) or filename slug for file mode (e.g., `requirements` from `requirements.md`)
- Now that the slug `<ID>` is known, run **Ensure Working Branch(`<slug>`)** (see Working Branch above)
- Skip tracker status updates throughout the pipeline

**For all modes:**
- Write the agent's output to `.n1/memory/<ID>/ticket.md`
- ID is: ticket ID for ticket mode (or brain dump/file mode with ticket creation), filename slug for file mode without ticket, description slug for brain dump without ticket (e.g., `csv-export-users`)

**Create initial overview.md:**
```markdown
---
ticket: <ID>
step: ticket
substep: 0
iteration: 1
last_updated: <ISO timestamp>
---

# <ID>: <Title>

## Progress
- [x] Ticket read
- [ ] Analysis
- [ ] Brainstorm
- [ ] Plan
- [ ] Implementation
- [ ] QA
- [ ] Review
- [ ] PR
- [ ] CI

## Key Decisions
(none yet)

## Escalations
(none yet)
```

### 2. ANALYSIS

**Spawn agent:** solution-architect

Resolve model for `solution-architect`.

Spawn the solution-architect agent with:
- Content of `ticket.md` as the scope to analyze
- The **Type** field extracted from `ticket.md` (bug/feature/task/improvement) — pass it explicitly so the architect knows whether to perform bug investigation

After the agent returns:
- Write its output to `.n1/memory/<ID>/analysis.md`
- Update overview: `[x] Analysis`, set `step: analysis`

### 3. BRAINSTORM

**REQUIRED SUB-SKILL:** Use superpowers:brainstorming to explore the scope and refine the approach.

Pass to brainstorming:
- The content of `ticket.md` as the idea to explore
- The content of `analysis.md` as **pre-researched codebase context** — tell brainstorming: "Here is a codebase analysis already performed by our solution architect — use this as your starting context instead of exploring from scratch."
- **If ticket type is `bug`:** Also tell brainstorming: "This is a bug. The analysis includes a Bug Investigation section with the likely root cause and affected code path. Use these findings to ask informed questions about the fix approach rather than generic questions."

**Brainstorming overrides (IMPORTANT):**
- **Spec location:** Write the design doc directly to `.n1/memory/<ID>/brainstorm.md` — NOT to `docs/superpowers/specs/`. The brainstorming skill honors "user preferences for spec location override this default," so this is the sanctioned location override. The skill's User Review Gate message will reference this path.
- **Do NOT commit the spec.** `.n1/` is gitignored and ephemeral — N1 owns this content in per-ticket memory. No spec artifact may be committed to the target repo.

After brainstorming completes (the design already lives in `.n1/memory/<ID>/brainstorm.md` per the override above):
- Update overview: `[x] Brainstorm`, set `step: brainstorm`
- Record key decisions in overview's `## Key Decisions` section

### Complexity Decision

Based on brainstorming output, determine complexity:

- **Simple task** (clear scope, single component, no architectural decisions) → Skip to **IMPLEMENT**
- **Complex task** (multiple components, architectural decisions, needs research) → Continue to **PLAN**

State your reasoning: "This task is [simple/complex] because [reason]. [Skipping to implementation / Proceeding with detailed planning]."

### 4. PLAN (complex tasks only)

**Spawn agent:** solution-architect (second invocation — deeper analysis)

Before calling superpowers:writing-plans, spawn solution-architect again with:
- Content of `ticket.md` and `brainstorm.md`
- Directive: "Focus on identifying the specific files that need to change, existing patterns to follow, and integration risks. This is a second-pass deeper analysis to inform detailed planning."

Write output to `.n1/memory/<ID>/analysis.md` (overwrite with enriched version).

**REQUIRED SUB-SKILL:** Use superpowers:writing-plans to create a detailed implementation plan.

Pass to writing-plans:
- Content of `ticket.md`, `brainstorm.md`, and updated `analysis.md`
- Codebase context discovered during analysis

**Writing-plans overrides (IMPORTANT):**
- **Plan location:** Write the plan directly to `.n1/memory/<ID>/plan.md` — NOT to `docs/superpowers/plans/`. The writing-plans skill honors "user preferences for plan location override this default," so this is the sanctioned location override.
- **Do NOT commit the plan.** `.n1/` is gitignored and ephemeral — N1 owns this content in per-ticket memory. No plan artifact may be committed to the target repo.
- Do NOT include any `REQUIRED SUB-SKILL` execution directive in the plan document header. N1 controls execution mode — the plan should contain only implementation tasks, not instructions about which skill executes them.
- Omit the "Execution Handoff" section entirely — do not offer the user a choice between SDD and parallel session. N1 will invoke SDD directly.

After plan is created (the full plan body already lives in `.n1/memory/<ID>/plan.md` per the override above):
- Update overview: `[x] Plan`, set `step: plan`
- Record a 2-3 sentence summary of the approach in overview's `## Key Decisions` section

### 4b. PLAN REVIEW (Cross-Context Review)

Read `.n1/n1.config.json` → check `planReview.reviewPlan` (default: `true`).

**If `planReview.reviewPlan` is `false`:** skip to checkpoint logic below.

**If `planReview.reviewPlan` is `true`:**

**Spawn agent:** solution-architect (fresh context — CCR)

Resolve model for `solution-architect`. Spawn with:
- Content of `ticket.md`, `analysis.md`, `brainstorm.md`, `plan.md` (the full plan body)
- Codebase access (Read, Grep, Glob)
- Review-oriented instructions (NOT generative — this is a review, not a second plan):

```
You are reviewing an existing implementation plan. Do NOT rewrite or restructure the plan.
Your job is to find specific issues in these categories:

1. ASSUMPTION VALIDATION — Does the plan rely on assumptions about the codebase
   that aren't verified? Use Grep/Read to check: do the referenced files, functions,
   patterns, and APIs actually exist as described?

2. SCOPE DRIFT — Compare the plan against the ticket. Does it solve what was asked,
   or has it drifted beyond scope? Flag any tasks that don't trace back to a ticket
   requirement.

3. MISSING EDGE CASES — Are there failure modes, error paths, or data states the
   plan doesn't address but should?

4. ORDERING/DEPENDENCY RISKS — Are implementation steps in the right order? Are
   there hidden dependencies between tasks that could cause issues if executed
   in the listed sequence?

5. BLAST RADIUS — Does the plan touch more files or systems than necessary? Could
   the same result be achieved with fewer changes?

If you find issues: fix them in-place in the plan file. State what you changed and why.
If the plan is clean: state "Plan validated, no issues found."

Output format:
## Plan Review Result
**Verdict:** CLEAN | FIXED
**Changes:** (list of fixes applied, or "None")
**Verified assumptions:** (list of codebase claims you confirmed via Grep/Read)
```

After the agent returns:
- If verdict is FIXED: the plan file was updated in-place by the reviewer
- Log the review result (verdict + changes) to the orchestrator context for traceability

### Plan Checkpoint (conditional)

Read `.n1/n1.config.json` → check `planReview.requirePlanApproval` (default: `false`).

**If `planReview.requirePlanApproval` is `true`:**

Present the plan to the user for approval:
"Plan is ready at `.n1/memory/<ID>/plan.md`. Please review and approve before I proceed with implementation."

**Wait for explicit approval before continuing.**

**If `planReview.requirePlanApproval` is `false`:**

Proceed directly to implementation. Log: "Plan review passed — proceeding to implementation."

### 5. IMPLEMENT

**Execution mode is predetermined:** Do NOT present execution options to the user. Do NOT invoke superpowers:executing-plans. Always use superpowers:subagent-driven-development regardless of what the plan document or writing-plans suggests.

**REQUIRED SUB-SKILL:** Use superpowers:subagent-driven-development to implement the plan task by task.

**Before passing plan content:** If plan.md or the referenced plan file contains a `REQUIRED SUB-SKILL: Use superpowers:executing-plans` directive (legacy header from older Superpowers versions), IGNORE it. The authoritative execution skill is superpowers:subagent-driven-development as specified here.

Resolve model for `developer`.

**Define success criteria before spawning.** For each plan task, transform it into a verifiable goal before passing to SDD. Example: "Add input validation" → "Write tests for empty, oversized, and malformed input, then make them pass." Include these criteria in the task descriptions so each subagent knows when it is done.

Pass to subagent-driven-development:
- The implementation plan from `plan.md` (or brainstorm.md for simple tasks), with success criteria appended to each task
- Codebase context
- Developer persona constraints (include these as additional role guidance for each implementer subagent):
  - **Think before coding:** state assumptions explicitly; if uncertain, stop and report rather than guessing
  - **Simplicity first:** write the minimum code that solves the task — no speculative abstractions, no features beyond what was asked
  - **Surgical changes:** touch only what the task requires — don't "improve" adjacent code, comments, or formatting
  - Follow existing patterns — do not introduce new architectural patterns or dependencies
  - Every change must have a corresponding test (or verify existing tests cover it)
  - Commit each logical change separately (atomic commits)
  - If a change requires architectural decisions, report it as "needs escalation" instead of implementing
  - Do not refactor surrounding code — change only what the task describes
- If config has a model override for developer, instruct: "Use model `<model>` for implementer subagents." (Note: this is best-effort — the orchestrator passes the instruction as text, but cannot structurally enforce the model parameter in SDD's subagent dispatch.)

**SDD overrides (IMPORTANT):**
- Do NOT call `superpowers:finishing-a-development-branch` after tasks complete — N1 orchestrator handles the post-implementation pipeline (QA, Review, PR).
- Do NOT use `superpowers:using-git-worktrees` — work on the current branch directly. N1 already created the working branch in Step 1 (see Working Branch), so SDD's commits land there, never on the default branch.
- Skip the final whole-implementation code review after all tasks — N1's Review stage (Step 7) handles this with dedicated code-reviewer and security-reviewer agents. Per-task spec and code-quality reviews are kept.
- Run in CONTINUOUS mode: do NOT pause between tasks to ask for user approval or feedback. Execute all plan tasks sequentially without stopping. The only valid reasons to stop are: (1) a blocker you cannot resolve from context, (2) a decision that hits the "Low confidence + High blast radius" escalation threshold below, or (3) all tasks complete.

### Confidence-Based Escalation

During implementation, evaluate each significant decision:

**High confidence → Full autonomy.** Proceed without asking.

**Low confidence + Low blast radius → Proceed with note.** Make the decision, note it in overview's `## Key Decisions`, continue.

**Low confidence + High blast radius → ESCALATE.** Stop and ask:
```
I'm not confident about this decision and it has high impact:

**Decision:** <what needs to be decided>
**Options:**
A. <option> — <tradeoff>
B. <option> — <tradeoff>
C. <option> — <tradeoff>

**My recommendation:** <option> because <reason>

Which approach?
```

**Always escalate for:** security changes, new architectural patterns, public API contract changes (per `escalation.alwaysAskOn` in config).

After implementation:
- Write `.n1/memory/<ID>/implementation.md`:
  ```markdown
  ## Implementation Summary
  
  ### Completed Tasks
  - Task 1: <description> — <result>
  - Task 2: <description> — <result>
  
  ### Files Changed
  - <file path> — <what changed>
  
  ### Test Results
  <test suite output summary>
  
  ### Decisions Made
  - <decision>: <choice> (reason: <why>)
  ```
- Update overview: `[x] Implementation`, set `step: implementation`

### 6. QA

**Spawn agent:** qa-engineer

Resolve model for `qa-engineer`.

Spawn the qa-engineer agent with:
- Content of `ticket.md` (acceptance criteria)
- Content of `implementation.md` (what was built, files changed)
- Content of `plan.md` or `brainstorm.md` (scope context)

After the agent returns:
- Write its output to `.n1/memory/<ID>/qa.md`
- Update overview: `[x] QA`, set `step: qa`
- If QA verdict is FAIL (test reveals a bug):
  - Report bug details to the user
  - Spawn developer agent (resolve model for `developer`) to fix the bug
  - Re-run QA after fix

### 7. REVIEW

**Spawn agents in PARALLEL:** code-reviewer + security-reviewer

Resolve models for both agents.

Prepare shared review context:
- Content of `ticket.md`
- Content of `brainstorm.md`
- Content of `implementation.md`
- Content of `qa.md`
- Default branch name from config

Spawn BOTH agents simultaneously:
- **code-reviewer** with the shared review context
- **security-reviewer** with the shared review context

After BOTH return, merge findings:
- Combine outputs into `.n1/memory/<ID>/review.md`
- Prefix code-reviewer findings with [CR-N], security-reviewer with [SEC-N]
- Combined verdict: FAIL if either reviewer returned FAIL

### 8. FIX (if review failed)

If either reviewer returned FAIL verdict:

**Spawn agent:** developer

Resolve model for `developer`.

Pass to developer:
- Combined review findings (Critical + Important only)
- List of affected files

After developer returns:
- Go back to **Step 7** (REVIEW) — re-run both reviewers
- Maximum 3 review-fix cycles before escalating to user:
  "After 3 review cycles, these findings remain unresolved: [list]. Please advise."

If both reviewers returned PASS:
- Check review count vs `review.minCleanPasses` from config (minimum number of consecutive clean passes required)
- If clean passes < minCleanPasses: go back to Step 7
- If clean passes >= minCleanPasses: proceed

Update overview: `[x] Review`, set `step: review`

### 9. PR CREATION

**REQUIRED SUB-SKILL:** Use n1:n1-pr to create the pull request.

Pass to n1-pr:
- `docUpdateMode: "autonomous"` — doc updates run without user confirmation in the full pipeline

The PR skill handles documentation update, tech-writer spawning, git push, PR creation, and tracker update.

After PR is created:
- The PR skill reports the URL

**CHECKPOINT:** "PR created at <URL>. Ready for Tech Lead review."

### 10. CI WATCH (conditional)

Read `.n1/n1.config.json` → check `ciChecks.enabled` (default: `true`).

**If `ciChecks.enabled` is `false`:** Skip to FINALIZE MEMORY.

**REQUIRED SUB-SKILL:** Use n1:n1-ci to monitor CI checks and fix failures.

The n1-ci skill receives the PR number from the PR creation step above. It:
1. Polls CI checks until all complete
2. Classifies failures and delegates fixes to the developer agent
3. Loops up to `ciChecks.maxFixAttempts` cycles
4. Escalates to user only if max attempts exhausted or unknown check below confidence threshold

**After n1-ci returns:**
- If all checks passed (with or without fixes) → continue to FINALIZE
- If user chose "skip" (CI still red) → continue to FINALIZE with CI status noted
- If user is still providing guidance → wait (n1-ci handles the interaction)

### 11. FINALIZE MEMORY

Update overview.md:
- All checkboxes checked
- Frontmatter: `step: done`
- Add `docs_updated` field from n1-pr's Phase 1 results (if any doc updates occurred)
- Final status line added

## Error Recovery

If any step fails:
1. Note the failure in overview.md under `## Escalations`
2. Report to the user with context
3. On next `/n1:n1-start <ID>`, resume support will pick up from the last successful step

## Context Management

This orchestrator is a **lightweight controller**. It:
- Delegates all heavy work to specialized agent personas (each gets fresh context)
- Loads only the dependency files needed for the current step
- Writes output to memory files after each step (explicit handoff)
- Never accumulates full history in its own context
