---
name: n1-start
description: "Core orchestrator. Start working on a task: /n1:n1-start TRID-510 or /n1:n1-start need CSV export for users. Handles the full cycle: ticket → brainstorm → plan → implement → review → PR."
argument-hint: "<ticket-id or brain dump>"
---

# N1 Core Orchestrator

## Overview

Single entry point for all task work. Accepts a ticket ID or a brain dump, then orchestrates the full development cycle: ticket reading → brainstorming → planning → implementation → review → PR → tracker update.

**Announce at start:** "I'm using the n1-start skill to work on this task."

## Input Parsing

The user provides one of:
- **Ticket ID** — matches the tracker prefix from config (e.g., `TRID-510`, `PROJ-42`)
- **Brain dump** — free-text description of what needs to be built
- **Resume** — ticket ID where memory already exists

### Detect input type:

1. Read `.n1/n1.config.json` → get `tracker.prefix`
2. If input matches `<prefix>-<number>` pattern → **Ticket mode**
3. Otherwise → **Brain dump mode**

## Memory Check (Resume Support)

Check if `.n1/memory/<input>/overview.md` exists:

- **If exists:** Read the overview frontmatter to determine current step. Resume from where work left off. Read the dependency files for the current step (see dependency map below) and continue.
- **If not exists:** Fresh start. Create `.n1/memory/<ID>/` directory.

### Step dependency map

| Step | Reads | Writes |
|------|-------|--------|
| ticket | — | `ticket.md` |
| brainstorm | `ticket.md` | `brainstorm.md` |
| plan | `ticket.md`, `brainstorm.md` | `plan.md` |
| implementation | `brainstorm.md`, `plan.md` | `implementation.md` |
| review | `ticket.md`, `brainstorm.md`, `implementation.md` | `review.md` |
| pr | `overview.md`, `review.md` | — |

Each step reads ONLY the files listed in its dependency column, not the full history.

## Pipeline Steps

### 1. TICKET READ (if ticket mode)

Read the tracker ticket and write a structured summary.

**Inline approach (default for tickets under ~50 comments):**

1. Read `.n1/n1.config.json` → `tracker.mcp` and `tracker.operations`
2. Call MCP tool: `mcp__<tracker.mcp>__<tracker.operations.readTicket>` with the ticket ID
3. For YouTrack: also call `mcp__<tracker.mcp>__<tracker.operations.getComments>`
4. For Jira: also call `mcp__<tracker.mcp>__<tracker.operations.getTransitions>`
5. Distill into structured format and write to `.n1/memory/<ID>/ticket.md`:

```markdown
## Ticket: <ID>
**Title:** <title>
**Priority:** <priority>
**Status:** <current status>

### Description
<distilled description>

### Acceptance Criteria
- [ ] <criteria>

### Key Comments
- @author (date): "comment"
```

6. Update tracker status to In Progress:
   - Call `mcp__<tracker.mcp>__<tracker.operations.moveStatus>`

**For brain dump mode:** Use the input text directly as the scope. Write it to `.n1/memory/<ID>/ticket.md` where ID is derived from the description (slugified, e.g., `csv-export-users`).

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
- [ ] Brainstorm
- [ ] Plan
- [ ] Implementation
- [ ] Review
- [ ] PR

## Key Decisions
(none yet)

## Escalations
(none yet)
```

### 2. BRAINSTORM

**REQUIRED SUB-SKILL:** Use superpowers:brainstorming to explore the scope and refine the approach.

Pass to brainstorming:
- The content of `ticket.md` as the idea to explore
- Any relevant codebase context you've discovered

After brainstorming completes:
- Save the design output to `.n1/memory/<ID>/brainstorm.md`
- Update overview: `[x] Brainstorm`, set `step: brainstorm`
- Record key decisions in overview's `## Key Decisions` section

### Complexity Decision

Based on brainstorming output, determine complexity:

- **Simple task** (clear scope, single component, no architectural decisions) → Skip to **IMPLEMENT**
- **Complex task** (multiple components, architectural decisions, needs research) → Continue to **PLAN**

State your reasoning: "This task is [simple/complex] because [reason]. [Skipping to implementation / Proceeding with detailed planning]."

### 3. PLAN (complex tasks only)

**REQUIRED SUB-SKILL:** Use superpowers:writing-plans to create a detailed implementation plan.

Pass to writing-plans:
- Content of `ticket.md` and `brainstorm.md`
- Codebase context discovered during brainstorming

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

### 4. IMPLEMENT

**REQUIRED SUB-SKILL:** Use superpowers:subagent-driven-development to implement the plan task by task.

Pass to subagent-driven-development:
- The implementation plan from `plan.md` (or brainstorm.md for simple tasks)
- Codebase context

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

### 5. REVIEW LOOP

**REQUIRED SUB-SKILL:** Use n1:n1-review to run the review loop.

The review skill handles the iterative fix cycle (request → receive → fix → repeat). It will update memory files when done.

After review passes:
- Verify overview shows `[x] Review`

### 6. PR CREATION

**REQUIRED SUB-SKILL:** Use n1:n1-pr to create the pull request.

The PR skill handles git push, PR creation, and tracker update.

After PR is created:
- The PR skill reports the URL

**CHECKPOINT:** "PR created at <URL>. Ready for Tech Lead review."

### 7. FINALIZE MEMORY

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
- Delegates all heavy work to Superpowers sub-skills (each gets fresh context)
- Loads only the dependency files needed for the current step
- Writes output to memory files after each step (explicit handoff)
- Never accumulates full history in its own context
