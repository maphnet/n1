---
name: n1-start
description: "Core orchestrator. Start working on a task: /n1:n1-start TRID-510 or /n1:n1-start need CSV export for users. Handles the full cycle: ticket → analysis → brainstorm → plan → implement → QA → review → PR."
argument-hint: "<ticket-id or brain dump>"
model: inherit
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

**PROCEDURE: Reconcile Memory ID & Branch (`<oldId>`, `<newId>`)**

Heals state that leaked under a provisional slug before the final `<ID>` was known (e.g. if the orchestrator drifted into the ticket-less path after a "Yes"). **Idempotent** — safe to call when nothing leaked. `<oldId>` is the deterministically-computed provisional slug; `<newId>` is the final ID.

1. **If `<oldId>` == `<newId>`** → return (no-op).
2. **Memory move:** if `.n1/memory/<oldId>/` exists AND `.n1/memory/<newId>/` does NOT → filesystem-move the directory `<oldId>/` → `<newId>/` (`.n1/` is gitignored, so a plain `mv` / `Move-Item`, NOT `git mv`). If `.n1/memory/<newId>/` already exists, skip the move and report — the `<newId>` memory is authoritative (resume/collision guard).
3. **Frontmatter fix:** if `.n1/memory/<newId>/overview.md` exists (true only when an overview was already written under the slug and just moved — in the clean path it does not exist yet), rewrite its `ticket: <oldId>` → `ticket: <newId>` and its `# <oldId>: <Title>` heading → `# <newId>: <Title>`.
4. **Branch rename:** compute `<oldBranch>` and `<newBranch>` from `git.branchPattern` (config). If a local branch `<oldBranch>` exists AND `<newBranch>` does NOT → `git branch -m <oldBranch> <newBranch>` (rename preserves commits; N1 has not pushed yet — push happens at PR time in `n1-pr`). If `<newBranch>` already exists, skip the rename — the subsequent Ensure Working Branch will check it out.
5. Report: "Migrated memory + branch `<oldId>` → `<newId>`."

## Memory Check (Resume Support)

Check if `.n1/memory/<input>/overview.md` exists:

- **If exists:** Read the overview frontmatter to determine current step. Run **Ensure Working Branch(`<ID>`)** (see Working Branch above) to re-check out the branch — this covers resuming from `main` or a different branch. Then resume from where work left off: read the dependency files for the current step (see dependency map below) and continue. **Also read the loop counters** (`qa_fix_cycle`, `review_fix_cycle`, `clean_passes`, and `ci_fix_cycle` if present) so bounded loops resume at their true count, not zero (see Loop-Counter Durability below).
- **If not exists:** Fresh start. Create `.n1/memory/<ID>/` directory.

### Step dependency map

| Step | Reads | Writes |
|------|-------|--------|
| ticket | — | `ticket.md` |
| analysis | `ticket.md` | `analysis.md` |
| brainstorm | `ticket.md`, `analysis.md` | `brainstorm.md` |
| plan | `ticket.md`, `brainstorm.md`, `analysis.md` | `plan.md` |
| plan-review | `ticket.md`, `analysis.md`, `brainstorm.md`, `plan.md` | `plan.md` (in-place fixes) |
| implementation | `brainstorm.md`, `plan.md` | `implementation.md` |
| qa | `ticket.md`, `implementation.md`, `plan.md` | `qa.md` |
| review | `ticket.md`, `brainstorm.md`, `implementation.md`, `qa.md` | `review.md` |
| pr | `overview.md`, `review.md`, `qa.md`, `implementation.md` | — |
| ci | `overview.md`, `plan.md`, `implementation.md` | `overview.md` (CI status) |

Each step reads ONLY the files listed in its dependency column, not the full history.

### Loop-counter durability & crash-safe checkpointing

- **Loop counters live in overview frontmatter**, never only in orchestrator context: `qa_fix_cycle`, `review_fix_cycle`, `clean_passes` (and `ci_fix_cycle`, owned by n1-ci). Increment them in the file as each loop turns and read them back on resume. A bound held only in context resets to zero on restart, silently defeating it.
- **Overview is the single source of truth for progress.** Each step writes its output file FIRST, then updates `step:`/checkbox in overview LAST. On resume, a step counts as done only if overview says so. If a crash lands between the two writes (output file exists but overview still points at the prior step), re-running is safe because every artifact write is a full overwrite — idempotent, never an append.

**Dependency integrity guard (applies to every step).** Before spawning a step's agent or sub-skill, verify each of that step's declared dependency files exists and is non-empty. If any is missing or empty — a realistic state when resuming from an arbitrary step — **STOP and report which file is missing rather than proceeding** with a degraded handoff. Do not let an agent improvise around an absent `implementation.md` or an empty `analysis.md`. (`ticket.md` with no acceptance criteria is handled upstream by product-analyst and is not a hard stop.)

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

**ID-Final invariant.** No file may be written under `.n1/memory/` and no working branch may be created until `<ID>` is **final**: the ticket ID in ticket mode; the *created* ticket ID for brain-dump/file mode answered "Yes"; the slug only for brain-dump/file mode answered "No". Resolving the create-ticket decision (and, on "Yes", actually creating the ticket) therefore happens BEFORE the `ticket.md`/`overview.md` writes and branch creation below.

**Tracker ticket creation (brain dump and file modes):**

After product-analyst returns, if the input was a brain dump or file path, AND a tracker is configured (`tracker.mcp` is not null AND `tracker.operations.createIssue` exists):

Ask the user:
```
The task has been structured. Would you like to create a tracker ticket?
1 — Yes, create a ticket in <tracker.mcp>
2 — No, continue without a ticket
```

**If 1 (Yes):**

> ⚠ **Create the ticket now.** Creating the ticket via MCP is **mandatory and immediate** — it is the first action after the user answers "Yes". Do NOT proceed as if the run were ticket-less; the slug is adopted as `<ID>` ONLY on the explicit "No" path. (See the ID-Final invariant above.)

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
4. The returned ticket ID is the final `<ID>`. Adopt it deterministically:
   1. Compute the provisional `<slug>` exactly as the "No" path would (description slug for brain dump, filename slug for file mode).
   2. Run **Reconcile Memory ID & Branch(`<slug>`, `<ticketID>`)** (see Working Branch above) — a no-op in the clean path; it moves any leaked slug memory folder into the ticket-ID folder and renames the slug branch if drift occurred.
   3. Set `<ID>` = `<ticketID>`, then run **Ensure Working Branch(`<ticketID>`)** (see Working Branch above).
5. Extract the ticket URL from the MCP response (YouTrack returns it in the response body; for Jira construct it as `https://<cloud>/browse/<key>` from the response)
6. **Assign to creator.** Run this step ONLY if ALL of: `tracker.assignToCreator !== false`, `tracker.operations.getCurrentUser` exists, AND `tracker.operations.assign` exists. If any condition fails, skip this step silently (no message) and go to step 7.
   1. Resolve the current user: call `mcp__<tracker.mcp>__<tracker.operations.getCurrentUser>` (no arguments).
      - **YouTrack:** take `login` from the response.
      - **Jira:** take the account id (`account_id`) from the response; reuse the `cloudId` already resolved during creation.
   2. Assign the ticket: call `mcp__<tracker.mcp>__<tracker.operations.assign>`:
      - **YouTrack:** `change_issue_assignee` with `issueId`: `<ID>`, `assigneeLogin`: `<login>`.
      - **Jira:** `editJiraIssue` with `cloudId`: resolved cloud ID, `issueIdOrKey`: `<ID>`, `assignee_account_id`: `<account id>`.
   3. **On success:** set the report suffix to ` (assigned to you)`.
   4. **On failure** (either call errors — permission, unresolvable user, MCP error): do NOT roll back creation. Emit `⚠ Ticket created but could not auto-assign (<reason>); assign it manually.` and use an empty report suffix.
7. Report: "Created ticket **[<ID>](<ticket URL>)**<report suffix>: <title>"
8. After writing ticket.md and overview.md, update tracker status to In Progress (same as ticket mode — call `mcp__<tracker.mcp>__<tracker.operations.moveStatus>`)

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
last_updated: <ISO timestamp>
qa_fix_cycle: 0
review_fix_cycle: 0
clean_passes: 0
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
- Directive: "Research relevant industry standards/best practices per agents/research-standards.md and include the cited Industry Standards & Best Practices section."

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
- **Stop after the design; do NOT auto-invoke `writing-plans`.** SP 5.1 brainstorming treats "invoke writing-plans" as its terminal state ("the ONLY skill you invoke after brainstorming is writing-plans"). Override this: once the design is written to `brainstorm.md` and approved, hand control back to the N1 orchestrator. N1 runs its own Complexity Decision, a second-pass analysis, and then invokes `writing-plans` itself with the overrides in Step 4. If brainstorming auto-chained into `writing-plans` directly, the plan would be produced WITHOUT N1's location and execution-handoff overrides — writing to `docs/superpowers/plans/` and offering execution options. Do not let it.

After brainstorming completes (the design already lives in `.n1/memory/<ID>/brainstorm.md` per the override above):
- Update overview: `[x] Brainstorm`, set `step: brainstorm`
- Record key decisions in overview's `## Key Decisions` section

### Complexity Decision

Based on brainstorming output, determine complexity:

- **Simple task** (clear scope, single component, no architectural decisions) → Skip to **IMPLEMENT**
- **Complex task** (multiple components, architectural decisions, needs research) → Continue to **PLAN**

State your reasoning: "This task is [simple/complex] because [reason]. [Skipping to implementation / Proceeding with detailed planning]."

**Deterministic floor.** The "simple" path skips PLAN and therefore PLAN-REVIEW (the CCR safety net). Before classifying a task as simple, check `analysis.md` for blast-radius signals: if it touches more than ~2 files, modifies a public API, or flags security/architecture concerns, treat it as complex regardless of the judgment call. When uncertain, prefer complex — plan-review is cheap insurance.

### 4. PLAN (complex tasks only)

**Spawn agent:** solution-architect (second invocation — deeper analysis)

Before calling superpowers:writing-plans, spawn solution-architect again with:
- Content of `ticket.md` and `brainstorm.md`
- Directive: "Focus on identifying the specific files that need to change, existing patterns to follow, and integration risks. This is a second-pass deeper analysis to inform detailed planning. Also research applicable industry standards/best practices per agents/research-standards.md and cite them."

Write output to `.n1/memory/<ID>/analysis.md` (overwrite with enriched version).

**Spawn agent:** planner

Resolve model for `planner` (see Model Resolution above).

The planner runs `superpowers:writing-plans` in an isolated subagent context. This is deliberate: the writing-plans skill ends with an "Execution Handoff" step that asks the user which execution mode to use, and when invoked in-context that prompt intermittently leaks to the user even though N1 predetermines the execution mode. A dispatched subagent has no interactive channel — any such prompt returns to the orchestrator as text and is absorbed here, never shown to the user. The planner also lacks `Bash`, so it cannot chain into implementation or commit.

Spawn the planner agent with:
- Content of `ticket.md`, `brainstorm.md`, and updated `analysis.md`
- Codebase context discovered during analysis
- **Output path:** `.n1/memory/<ID>/plan.md` — instruct the planner to write the plan there and nowhere else, and NOT to commit it (`.n1/` is gitignored and ephemeral; N1 owns this content in per-ticket memory).
- Directive: "Do NOT include any `REQUIRED SUB-SKILL` execution directive in the plan body — N1 controls execution mode; the plan contains only implementation tasks."

After the planner returns (the full plan body already lives in `.n1/memory/<ID>/plan.md`, written by the planner):
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

6. STANDARDS VALIDATION — Does the plan align with established industry standards
   and best practices for this domain? Research per agents/research-standards.md:
   corroborate across ≥2 independent trusted sources and cite the URL for any
   deviation you flag. Apply the fitness gate — prefer decisive standards over
   contestable practices, and do not flag a "best practice" the plan correctly
   omitted as over-engineering for this scope. If web tools are unavailable, skip
   this check and note it.

If you find issues: fix them in-place in the plan file. State what you changed and why.
If the plan is clean: state "Plan validated, no issues found."

Output format:
## Plan Review Result
**Verdict:** CLEAN | FIXED
**Changes:** (list of fixes applied, or "None")
**Verified assumptions:** (list of codebase claims you confirmed via Grep/Read)
**Verified standards:** (list of best-practice/standard claims confirmed via web, with cited URLs; or "None")
```

After the agent returns:
- If verdict is FIXED: the plan file was updated in-place by the reviewer
- Record the plan-review verdict and a one-line summary of changes in overview's `## Key Decisions` — durable traceability that survives a resume, rather than living only in transient orchestrator context

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

**Before passing plan content:** If plan.md contains ANY execution-skill directive in its header — whether it names `superpowers:executing-plans`, `superpowers:subagent-driven-development`, or both (the wording varies across Superpowers versions; SP 5.1 emits "subagent-driven-development (recommended) or executing-plans") — IGNORE it. The authoritative execution skill is always superpowers:subagent-driven-development as specified here.

Resolve model for `developer`.

**Define success criteria before spawning.** For each plan task, transform it into a verifiable goal before passing to SDD. Example: "Add input validation" → "Write tests for empty, oversized, and malformed input, then make them pass." Include these criteria in the task descriptions so each subagent knows when it is done.

Pass to subagent-driven-development:
- The implementation plan from `plan.md` (or brainstorm.md for simple tasks), with success criteria appended to each task
- Codebase context
- **Developer persona constraints** — SDD's implementer subagents do NOT load `agents/developer.md`, so pass these as role guidance. They MIRROR the canonical persona in `agents/developer.md` (the single source of truth); keep the two in sync:
  - **Think Before Coding** — state assumptions explicitly; if uncertain, stop and report rather than guessing.
  - **Simplicity First** — write the minimum code that solves the task; no speculative abstractions, no features beyond what was asked.
  - **Surgical Changes** — touch only what the task requires; don't "improve" adjacent code, comments, or formatting.
  - **Goal-Driven Execution** — define verifiable success criteria first, then loop until they are met (see "Define success criteria" above).
  - Follow existing patterns; introduce no new architectural patterns or dependencies.
  - Every change has a corresponding test (or verify existing tests cover it); commit each logical change separately (atomic commits).
  - If a change requires architectural decisions, report it as "needs escalation" instead of implementing; do not refactor surrounding code.
- If config has a model override for developer, instruct: "Use model `<model>` for ALL implementer subagents, overriding SDD's own per-task Model Selection heuristic." (SP 5.1's SDD added a Model Selection section that picks the cheapest capable model per task based on how many files it touches; without this explicit instruction that heuristic silently wins over the N1 config override.) For a structural binding rather than a text instruction, set the `CLAUDE_CODE_SUBAGENT_MODEL` environment variable to `<model>` around the SDD dispatch — it is the documented highest-precedence override for subagent model selection and binds even when SDD spawns its own subagents. Fall back to the text instruction only if the env var cannot be set.

**SDD overrides (IMPORTANT):**
- **Do NOT call `superpowers:finishing-a-development-branch` under any circumstance.** SDD's flow ends by invoking it (it is the terminal node of SDD's process graph), and it would present merge/PR/discard options that could push, open a PR, or even delete the branch — colliding with N1's own QA → Review → PR pipeline (`n1-pr` owns push and PR at Step 9). STOP at the last completed task and hand control back to the N1 orchestrator.
- **Workspace isolation is already satisfied** — N1 created the working branch in Step 1 (see Working Branch). Treat SDD's `superpowers:using-git-worktrees` prerequisite as ALREADY MET: do NOT create a new worktree or switch branches. Work on the current branch directly, so SDD's commits land there, never on the default branch.
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
- The `## Key Decisions` and `## Escalations` slices of `overview.md` (NOT the whole file) — so QA knows which choices were deliberate and why, instead of re-litigating them

After the agent returns:
- Write its output to `.n1/memory/<ID>/qa.md`
- Update overview: `[x] QA`, set `step: qa`
- If QA verdict is FAIL (test reveals a bug):
  - Report bug details to the user
  - Spawn developer agent (resolve model for `developer`) to fix the bug
  - Increment `qa_fix_cycle` in overview frontmatter, then re-run QA
  - **Bounded loop:** stop after `qa.maxFixAttempts` cycles (config, default 3). On exhaustion, escalate instead of looping forever: "After <N> QA fix cycles this test still fails: [details]. Please advise." The counter is persisted, so the bound survives a resume.

### 7. REVIEW

**Spawn agents in PARALLEL:** code-reviewer + security-reviewer

Resolve models for both agents.

Prepare review context (curated per reviewer, not one identical bundle):
- **Shared:** `ticket.md`, `implementation.md`, `qa.md`, default branch name, and the `## Key Decisions` + `## Escalations` slices of `overview.md` — so neither reviewer flags a deliberate, recorded choice as a defect.
- **code-reviewer also receives** `brainstorm.md` — design intent matters for a design-quality review.
- **security-reviewer does NOT receive** `brainstorm.md` — the design narrative is low-signal for vulnerability scanning. Keep its context lean: acceptance criteria + changed-file list + the diff are its high-signal inputs.

Spawn BOTH agents simultaneously:
- **code-reviewer** with the shared review context
- **security-reviewer** with the shared review context

After BOTH return, merge findings:
- Combine outputs into `.n1/memory/<ID>/review.md`
- Prefix code-reviewer findings with [CR-N], security-reviewer with [SEC-N]
- Combined verdict: FAIL if either reviewer returned FAIL
- **Partial-failure handling:** if one reviewer errors, times out, or returns malformed output, retry that reviewer once. If it still fails, proceed with the other reviewer's findings, record the gap explicitly in review.md ("⚠ security-reviewer did not complete — review incomplete"), and do NOT treat the missing reviewer as a PASS.

### 8. FIX (if review failed)

If either reviewer returned FAIL verdict:

**Spawn agent:** developer

Resolve model for `developer`.

Pass to developer:
- Combined review findings (Critical + High only)
- List of affected files

After developer returns:
- Increment `review_fix_cycle` in overview frontmatter (so the bound survives a resume)
- Go back to **Step 7** (REVIEW) — re-run both reviewers
- **Oscillation guard:** fingerprint each confirmed Critical/High finding (file + line + title). If a fix attempt does NOT reduce the confirmed Critical/High count, or the same fingerprint reappears after being marked fixed, escalate early — don't burn the remaining cycles making negative progress.
- Maximum 3 review-fix cycles before escalating to user:
  "After 3 review cycles, these findings remain unresolved: [list]. Please advise."

If both reviewers returned PASS:
- Increment `clean_passes` in overview frontmatter
- If `clean_passes` < `review.minCleanPasses` (config, minimum consecutive clean passes): go back to Step 7
- If `clean_passes` >= `review.minCleanPasses`: proceed

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

If any step fails, first classify the failure:

- **Transient** (tracker/MCP timeout, `gh` rate-limit, agent-spawn hiccup, network blip) → retry once or twice with brief backoff before escalating. Most external-call failures are transient.
- **Terminal or ambiguous** (logic error, repeated failure after retry, an unresolvable blocker) → do not retry blindly:
  1. Note the failure in overview.md under `## Escalations`
  2. Report to the user with context
  3. On next `/n1:n1-start <ID>`, resume support picks up from the last successful step

## Context Management

This orchestrator is a **lightweight controller**. It:
- Delegates all heavy work to specialized agent personas (each gets fresh context)
- Loads only the dependency files needed for the current step
- Writes output to memory files after each step (explicit handoff)
- Never accumulates full history in its own context

### Memory hygiene

- **Soft size budget per memory file.** If a file grows large (a long bug investigation in `analysis.md`, a multi-cycle `review.md`), compact it to its high-signal conclusions before the next step reads it — verbose, stale notes are the raw material of context poisoning on long or resumed runs.
- **Re-derive volatile facts on resume.** Treat files-changed lists and test results stored in memory as hints, not ground truth: on resume, re-derive them from `git` and the test suite rather than trusting potentially stale markdown.
