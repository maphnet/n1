---
name: n1-estimate
description: "Estimate an existing ticket or task. Runs analysis pipeline then writes complexity tier and delivery time to tracker. Usage: /n1:n1-estimate TRID-510 or /n1:n1-estimate need CSV export for users"
argument-hint: "<ticket-id or task description>"
model: inherit
---

# N1 Estimation

## Overview

Estimate task complexity and delivery time for a ticket or task description. Runs the analysis pipeline (ticket read → codebase analysis → brainstorm) to build context, then classifies complexity and maps to a time estimate. Writes results to the tracker (if configured and enabled) or outputs to the user.

**Announce at start:** "I'm using the n1-estimate skill to estimate this task."

## Prerequisites

Check if `.n1/n1.config.json` exists on disk (use Read or Bash `test -f`, NOT git commands — `.n1/` is gitignored):

- **If missing:** Tell the user: "N1 is not configured for this project. Run `/n1:n1-init` to set it up." **STOP.**
- **If exists:** Continue.

**Gate check:** Read `.n1/n1.config.json` → check `estimation.enabled`.
- If `estimation.enabled` is not `true`: Tell the user: "Estimation is not enabled. Run `/n1:n1-init` to configure it, or set `estimation.enabled: true` in `.n1/n1.config.json`." **STOP.**

## Input Parsing

Same as n1-start — the user provides one of:
- **Ticket ID** — matches the tracker prefix from config (e.g., `TRID-510`, `PROJ-42`)
- **File path** — a path to a file containing requirements
- **Brain dump** — free-text description of what needs to be built

### Detect input type:

1. Read `.n1/n1.config.json` → get `tracker.prefix`
2. If input matches `<prefix>-<number>` pattern → **Ticket mode**
3. If input is a file path that exists on disk → **File mode**
4. Otherwise → **Brain dump mode**

Error tracker URLs are NOT supported in n1-estimate — use n1-start for error-tracker flows.

## Model Resolution

Same as n1-start: check `models.<agent-name>` in config, fall back to agent frontmatter default.

## Memory

Write to `.n1/memory/<ID>/` as usual:
- **Ticket mode:** `<ID>` is the ticket ID
- **File mode:** `<ID>` is a filename slug
- **Brain dump:** `<ID>` is a description slug

If `.n1/memory/<ID>/` already has `ticket.md`, `analysis.md`, and `brainstorm.md` from a prior run, reuse them — skip to the estimation step directly. This avoids duplicate work when the user runs n1-estimate before n1-start.

**No working branch creation.** This is a read-only analysis — do not create or switch branches.

**No status transitions.** Do not move the ticket status in the tracker.

## Pipeline

### 1. REQUIREMENTS ANALYSIS

**Spawn agent:** product-analyst

Same as n1-start Step 1, with these differences:
- **No working branch creation** — skip the Ensure Working Branch procedure
- **No tracker ticket creation** — for brain dump/file modes, do NOT prompt to create a ticket. Use the slug as `<ID>` directly.
- **No status transition** — do not move ticket to "In Progress"
- **Enrichment:** still runs if eligible (same gating as n1-start) — estimation benefits from a well-structured description

After agent returns:
- Write output to `.n1/memory/<ID>/ticket.md`
- Create initial `overview.md` (same template as n1-start, but without working branch info)

### 2. ANALYSIS

**Spawn agent:** solution-architect

Same as n1-start Step 2. After the agent returns:
- Write output to `.n1/memory/<ID>/analysis.md`

### 3. BRAINSTORM

**REQUIRED SUB-SKILL:** Use superpowers:brainstorming

Same as n1-start Step 3, with the same overrides:
- Write to `.n1/memory/<ID>/brainstorm.md`
- Do NOT commit the spec
- Skip User Review Gate
- Stop after design — do NOT auto-invoke writing-plans

### 4. ESTIMATE

Run the **Estimation** procedure from n1-start (see n1-start SKILL.md, Estimation section). The context available is: `ticket.md`, `analysis.md`, `brainstorm.md` (no `plan.md` — n1-estimate does not run planning).

After estimation:
- Update overview: `[x] Estimation`, set `step: done`

### 5. OUTPUT

Report the estimate to the user:

```
Estimation complete for <ID>:

**Complexity:** <TIER> (<Full Name>)
**Estimated delivery:** <time>
**Basis:** <one sentence>
```

If tracker writes were performed, append: "Estimate written to tracker."
If tracker writes were skipped (no tracker, writeToTracker false, or MCP failure), append: "Estimate saved to memory only."

**STOP.** Do not continue to implementation, QA, review, or PR.
