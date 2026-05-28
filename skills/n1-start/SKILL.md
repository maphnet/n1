---
name: n1-start
description: "Core orchestrator. Start working on a task: /n1:n1-start TRID-510 or /n1:n1-start need CSV export for users. Handles the full cycle: ticket → analysis → brainstorm → plan → implement → QA → review → PR."
argument-hint: "<ticket-id or brain dump>"
---

# N1 Core Orchestrator

## Overview

Single entry point for all task work. Accepts a ticket ID or a brain dump, then orchestrates the full development cycle using specialized agent personas: product-analyst, solution-architect, developer, qa-engineer, code-reviewer, security-reviewer, and tech-writer.

**Announce at start:** "I'm using the n1-start skill to work on this task."

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

## Memory Check (Resume Support)

Check if `.n1/memory/<input>/overview.md` exists:

- **If exists:** Read the overview frontmatter to determine current step. Resume from where work left off. Read the dependency files for the current step (see dependency map below) and continue.
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
| pr | `overview.md`, `review.md`, `qa.md` | — |

Each step reads ONLY the files listed in its dependency column, not the full history.

## Pipeline Steps

Steps 3 (Brainstorm) and 4 (Plan checkpoint) are **INTERACTIVE** — they pause for user input. All other steps run autonomously.

### 1. REQUIREMENTS ANALYSIS

**Spawn agent:** product-analyst

Resolve model for `product-analyst` (see Model Resolution above).

The product-analyst accepts three input modes. Choose based on input type:

**Ticket mode** (input matches `<prefix>-<number>`):
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

**For all modes:**
- Write the agent's output to `.n1/memory/<ID>/ticket.md`
- ID is: ticket ID for ticket mode, filename slug for file mode, description slug for brain dump (e.g., `csv-export-users`)

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

After the agent returns:
- Write its output to `.n1/memory/<ID>/analysis.md`
- Update overview: `[x] Analysis`, set `step: analysis`

### 3. BRAINSTORM

**REQUIRED SUB-SKILL:** Use superpowers:brainstorming to explore the scope and refine the approach.

Pass to brainstorming:
- The content of `ticket.md` as the idea to explore
- The content of `analysis.md` as **pre-researched codebase context** — tell brainstorming: "Here is a codebase analysis already performed by our solution architect — use this as your starting context instead of exploring from scratch."

After brainstorming completes:
- Save the design output to `.n1/memory/<ID>/brainstorm.md`
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

After plan is created:
- Save reference to `.n1/memory/<ID>/plan.md`:
  ```markdown
  ## Plan Reference
  **File:** docs/plans/<date>-<feature>.md
  
  ## Summary
  <2-3 sentence summary of the approach>
  
  ## Tasks
  <list of task names from the plan>
  ```
- Update overview: `[x] Plan`, set `step: plan`

**CHECKPOINT:** Present the plan to the user for approval.

"Plan is ready at `docs/plans/<file>`. Please review and approve before I proceed with implementation."

**Wait for explicit approval before continuing.** This is a mandatory checkpoint.

### 5. IMPLEMENT

**REQUIRED SUB-SKILL:** Use superpowers:subagent-driven-development to implement the plan task by task.

Resolve model for `developer`.

Pass to subagent-driven-development:
- The implementation plan from `plan.md` (or brainstorm.md for simple tasks)
- Codebase context
- Developer persona context: read the **Constraints section** from `agents/developer.md` and include it as additional guidance: "When dispatching implementer subagents, include these constraints as additional role guidance for each implementer."
- If config has a model override for developer, instruct: "Use model `<model>` for implementer subagents." (Note: this is best-effort — the orchestrator passes the instruction as text, but cannot structurally enforce the model parameter in SDD's subagent dispatch.)

**SDD overrides (IMPORTANT):**
- Do NOT call `superpowers:finishing-a-development-branch` after tasks complete — N1 orchestrator handles the post-implementation pipeline (QA, Review, PR).
- Do NOT use `superpowers:using-git-worktrees` — work on the current branch directly. N1 manages the branch lifecycle.
- Skip the final whole-implementation code review after all tasks — N1's Review stage (Step 7) handles this with dedicated code-reviewer and security-reviewer agents. Per-task spec and code-quality reviews are kept.

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
- Check review count vs `review.minPasses` from config
- If passes < minPasses: go back to Step 7
- If passes >= minPasses: proceed

Update overview: `[x] Review`, set `step: review`

### 9. PR CREATION

**Spawn agent:** tech-writer

Resolve model for `tech-writer`.

Spawn tech-writer with:
- Ticket ID
- Paths to `overview.md`, `review.md`, `qa.md`
- Git diff stat: `git diff ${DEFAULT_BRANCH}...HEAD --stat`

After tech-writer returns PR content:

**REQUIRED SUB-SKILL:** Use n1:n1-pr with the generated PR title and body.

The PR skill handles git push, PR creation, and tracker update.

After PR is created:
- The PR skill reports the URL

**CHECKPOINT:** "PR created at <URL>. Ready for Tech Lead review."

### 10. FINALIZE MEMORY

Update overview.md:
- All checkboxes checked
- Frontmatter: `step: done`
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
