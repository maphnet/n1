# Estimation Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add configurable estimation to N1 — classify task complexity into tiers (XS–XL), map to delivery time, write to tracker ticket and per-ticket memory.

**Architecture:** Estimation is an inline orchestrator step (no new agent). Two insertion points in n1-start: after plan for complex tasks, after brainstorm for simple tasks. Default mapping lives in `defaults/estimation.json` (N1 repo), overridable per-project in `n1.config.json`. A standalone `n1-estimate` skill runs Steps 1–3 then estimates. Configuration is added to `n1-init` wizard.

**Tech Stack:** Markdown (skills, agents), JSON (config, defaults), Bash (hooks). Jira MCP via `editJiraIssue`, YouTrack MCP via `update_issue`.

---

### Task 1: Create Default Estimation Mapping File

**Files:**
- Create: `defaults/estimation.json`

- [ ] **Step 1: Create the defaults directory and mapping file**

Create `defaults/estimation.json` with the default tier-to-time mapping:

```json
{
  "mapping": {
    "XS": "30m",
    "S": "2h",
    "M": "6h",
    "L": "2d",
    "XL": "5d"
  }
}
```

- [ ] **Step 2: Verify the file is valid JSON**

Run: `python -c "import json; json.load(open('defaults/estimation.json')); print('OK')"` or equivalent.
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add defaults/estimation.json
git commit -m "feat(estimation): add default tier-to-time mapping"
```

---

### Task 2: Add Estimation Wizard Step to n1-init

**Files:**
- Modify: `skills/n1-init/SKILL.md` — insert new section between Error Tracking Configuration and Review Configuration

The new section goes after the Error Tracking Configuration section (which ends with the reconfiguration block for `errorTracking`) and before the `## Review Configuration` heading.

- [ ] **Step 1: Add Estimation Configuration section to n1-init**

Insert the following new section in `skills/n1-init/SKILL.md` immediately before the `## Review Configuration` heading:

```markdown
## Estimation Configuration

Ask whether N1 should estimate task complexity and write delivery time to the tracker. **Default is No.**

```
Enable estimation for tickets?
Estimates task complexity and writes delivery time to tracker.
1 — Yes
2 — No (default)
```

**If 2 (No) or default:**
```json
{
  "estimation": {
    "enabled": false
  }
}
```

**If 1 (Yes):**

Set `estimation.enabled: true` and `estimation.writeToTracker: true`.

Show the default mapping table:
```
Default delivery time mapping:
  XS  30m   (config change, typo, single-line fix)
  S   2h    (single file, clear scope, no migrations)
  M   6h    (2-5 files, may need tests, straightforward)
  L   2d    (multiple files, migrations, new tests)
  XL  5d    (cross-cutting, architectural, multi-subsystem)

Customize mapping? 1 — Use defaults (recommended) / 2 — Customize
```

**If 1 (Use defaults):** omit `mapping` from the config entirely — the orchestrator loads defaults from `defaults/estimation.json` at runtime.

**If 2 (Customize):** ask for each tier value as a time string (e.g., `"4h"`, `"3d"`). Only store tiers the user actually changed — partial overrides merge with defaults at runtime.

```json
{
  "estimation": {
    "enabled": true,
    "writeToTracker": true,
    "mapping": {
      "M": "8h",
      "L": "3d"
    }
  }
}
```

### On reconfiguration (n1-init re-run):

If `estimation` already exists in the current config, show current state and offer:
```
Current estimation:
  enabled → <true/false>
  mapping → <default/custom>

1 — Keep current
2 — Enable
3 — Disable
4 — Update mapping
```
- **1** → leave unchanged.
- **2** → set `enabled: true`, `writeToTracker: true`. If mapping was not previously set, leave it (uses defaults).
- **3** → set `enabled: false`. Remove `writeToTracker` and `mapping` keys.
- **4** → show current mapping (merged with defaults), ask for changes. Only store overridden tiers.
```

- [ ] **Step 2: Add estimation block to the assembled config template**

In the `## Write Configuration and Structure` section of n1-init (near the 506), find the assembled config JSON template. Add the `estimation` block after `errorTracking`:

```json
  "estimation": {
    "enabled": false
  },
```

When estimation is enabled with customized mapping, it would look like:

```json
  "estimation": {
    "enabled": true,
    "writeToTracker": true,
    "mapping": {
      "M": "8h"
    }
  },
```

- [ ] **Step 3: Add estimation to the summary output**

In the `## Confirm` section of n1-init (near the 562), add an estimation line to the summary block. Insert after the `Error tracking:` line:

```
Estimation: enabled (default mapping) / enabled (custom mapping) / disabled
```

- [ ] **Step 4: Verify skill parses correctly**

Read through the full modified `skills/n1-init/SKILL.md` to confirm:
- The new section is properly positioned between Error Tracking and Review Configuration
- The JSON snippets are valid
- The numbered options follow the UX rules (numbered options for all choices)
- The reconfiguration flow handles all cases

- [ ] **Step 5: Commit**

```bash
git add skills/n1-init/SKILL.md
git commit -m "feat(n1-init): add estimation configuration wizard step"
```

---

### Task 3: Add Estimation Step to n1-start Pipeline

**Files:**
- Modify: `skills/n1-start/SKILL.md` — add estimation logic at two insertion points

This is the core change. The estimation step is added in two places:
1. **Simple path:** after the Complexity Decision routes to "simple", before IMPLEMENT
2. **Complex path:** after Plan Review (4b), before Plan Checkpoint

Both use identical estimation logic.

- [ ] **Step 1: Add the shared Estimation Step section to n1-start**

Insert a new `### Estimation` section in `skills/n1-start/SKILL.md` immediately after the `### Post-Brainstorm Enrichment (Phase 2)` section (which ends around line 416) and before the `### Complexity Decision` section. This defines the shared estimation logic that both insertion points reference:

```markdown
### Estimation

**Gate:** `estimation.enabled` in `.n1/n1.config.json` is `true`. If absent, `false`, or not exactly `true` → skip silently.

When the gate passes, run estimation at the appropriate pipeline point:
- **Simple tasks:** after Complexity Decision routes to simple, before IMPLEMENT
- **Complex tasks:** after Plan Review (4b), before Plan Checkpoint

**Estimation procedure:**

1. **Load mapping.** Read `estimation.mapping` from `.n1/n1.config.json`. For any tier (XS/S/M/L/XL) not present in the project config, load the default from `defaults/estimation.json` in the N1 plugin directory. Merge: project overrides win, defaults fill gaps.

2. **Read context.** Load from `.n1/memory/<ID>/`:
   - Always: `ticket.md`, `analysis.md`, `brainstorm.md`
   - Complex path only (when `plan.md` exists): `plan.md`

3. **Classify complexity tier.** Evaluate the context and assign exactly one tier — XS, S, M, L, or XL — using these signals:
   - **Scope:** file count, component/module count, whether changes cross subsystem boundaries
   - **Infrastructure:** database migrations, new services or dependencies, configuration changes
   - **Testing:** new test suites required vs. extending existing, integration test needs
   - **Uncertainty:** new technology or unfamiliar patterns, external dependency risks, ambiguities from ticket.md or analysis.md

   Tier reference (for classification, not output):
   | Tier | Characteristics |
   |------|-----------------|
   | XS | Config change, typo, single-line fix |
   | S | Single file, clear scope, no migrations |
   | M | 2-5 files, may need tests, straightforward |
   | L | Multiple files, migrations, new tests |
   | XL | Cross-cutting, architectural, multi-subsystem |

4. **Map tier to time.** Look up the classified tier in the merged mapping table to get the time estimate string.

5. **Generate basis.** Write one sentence explaining why this tier was chosen, referencing concrete signals from the context (e.g., "4 files affected, includes new tests, no migrations").

6. **Write to memory.** Append an Estimation section to `.n1/memory/<ID>/overview.md`:

   ```markdown
   ### Estimation
   **Complexity:** <TIER> (<Full Name>)
   **Estimated delivery:** <time>
   **Basis:** <one sentence>
   ```

   Full names: XS = "Extra Small", S = "Small", M = "Medium", L = "Large", XL = "Extra Large".

7. **Write to tracker description** (conditional). Run ONLY when ALL conditions are met:
   - A tracker ticket ID exists
   - `tracker.mcp` is not null
   - `tracker.operations.editTicket` exists
   - `estimation.writeToTracker` in config is not `false` (default `true`)

   Process:
   a. Fetch current description via `mcp__<tracker.mcp>__<tracker.operations.readTicket>` with the ticket ID. If the read fails, log "⚠ Could not read ticket for estimation — skipping description update" and skip to step 8 (still attempt time field write).
   b. Check for `*Estimated by N1*` marker in the current description. If present, skip description append (idempotent).
   c. Append estimation block to description:
      ```
      ---
      *Estimated by N1*

      **Complexity:** <TIER> (<Full Name>)
      **Estimated delivery:** <time>
      **Basis:** <one sentence>
      ```
   d. Call `mcp__<tracker.mcp>__<tracker.operations.editTicket>`. Use exactly `mcp__<tracker.mcp>__` as the tool prefix — the value from config, not from the tool list.
      - If `tracker.type == "jira"`: with `cloudId` (resolve via `mcp__<tracker.mcp>__getAccessibleAtlassianResources` if not cached), `issueIdOrKey`: `<ticketId>`, `description`: `<current description + appended block>`
      - Else (`tracker.type == "youtrack"`): with `issueId`: `<ticketId>`, `description`: `<current description + appended block>`
   e. If the MCP call fails: log "⚠ Estimation description update failed: <reason>" and continue — non-blocking.

8. **Write to tracker time field** (conditional). Same gating conditions as step 7.

   Call `mcp__<tracker.mcp>__<tracker.operations.editTicket>`. Use exactly `mcp__<tracker.mcp>__` as the tool prefix.
   - If `tracker.type == "jira"`: with `cloudId`, `issueIdOrKey`: `<ticketId>`, `timetracking`: `{ "originalEstimate": "<time>" }`
   - Else (`tracker.type == "youtrack"`): with `issueId`: `<ticketId>`, set the `Estimation` field to `<time>` (period format)

   If the MCP call fails: log "⚠ Estimation time field update failed: <reason>" and continue — non-blocking.

9. **Report.** Log: "Estimated complexity: **<TIER>** — <time>. Basis: <one sentence>"
```

- [ ] **Step 2: Wire estimation into the Simple path**

In the `### Complexity Decision` section of n1-start, find the simple task routing. Currently it says:

```
- **Simple task** (clear scope, single component, no architectural decisions) → Skip to **IMPLEMENT**
```

After the line `State your reasoning: "This task is [simple/complex] because [reason]. [Skipping to implementation / Proceeding with detailed planning]."` and the deterministic floor paragraph, add:

```markdown
**If simple:** Before proceeding to IMPLEMENT, run the **Estimation** procedure (see above). Then continue to Step 5 (IMPLEMENT).
```

- [ ] **Step 3: Wire estimation into the Complex path**

Find the `### Plan Checkpoint (conditional)` section. Insert immediately before it (after Plan Review 4b ends):

```markdown
### 4c. Estimation (complex tasks)

Run the **Estimation** procedure (see Estimation section above). The `plan.md` file is available, providing maximum context for accurate classification.
```

- [ ] **Step 4: Update the step dependency map**

In the `### Step dependency map` table in n1-start (near the 113), add the estimation row:

```markdown
| estimation | `ticket.md`, `analysis.md`, `brainstorm.md`, `plan.md` (if exists) | `overview.md` (estimation section) |
```

Insert this after the `plan-review` row and before the `implementation` row.

- [ ] **Step 5: Add estimation checkbox to the overview.md template**

In the `Create initial overview.md` section (near the 286), add an Estimation checkbox to the Progress section. Insert after `- [ ] Plan` and before `- [ ] Implementation`:

```markdown
- [ ] Estimation
```

And update the estimation step to mark this checkbox: after writing the estimation section to overview.md in step 6 of the Estimation procedure, also update the checkbox `[x] Estimation` and set `step: estimation` in the frontmatter.

- [ ] **Step 6: Verify consistency**

Read through the full modified pipeline to confirm:
- The estimation procedure section is positioned correctly (after Post-Brainstorm Enrichment, before Complexity Decision)
- Both insertion points reference the same procedure
- The step dependency map includes estimation
- The overview.md template includes the Estimation checkbox
- The gating logic matches the spec (estimation.enabled, tracker conditions)
- MCP call patterns match existing enrichment patterns (same prefix construction, same non-blocking error handling)

- [ ] **Step 7: Commit**

```bash
git add skills/n1-start/SKILL.md
git commit -m "feat(n1-start): add estimation step to pipeline"
```

---

### Task 4: Create Standalone n1-estimate Skill

**Files:**
- Create: `skills/n1-estimate/SKILL.md`

- [ ] **Step 1: Create the n1-estimate skill file**

Create `skills/n1-estimate/SKILL.md` with the following content:

```markdown
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
```

- [ ] **Step 2: Verify the skill file has correct frontmatter**

Read back the created file and confirm:
- Frontmatter has `name`, `description`, `argument-hint`, `model`
- The `name` matches the directory name (`n1-estimate`)
- The `description` is a single-line string
- No `tools` field (inherits orchestrator's full tool set — needed for dynamic tracker MCP)

- [ ] **Step 3: Commit**

```bash
git add skills/n1-estimate/SKILL.md
git commit -m "feat(n1-estimate): add standalone estimation skill"
```

---

### Task 5: Update CLAUDE.md Architecture Documentation

**Files:**
- Modify: `CLAUDE.md` — update orchestration table, memory dependency table, add estimation section, update config docs

- [ ] **Step 1: Add n1-estimate to the Orchestration Pattern table**

In `CLAUDE.md`, find the Orchestration Pattern table (near the 63). Add a new row after `n1-init`:

```markdown
| n1-estimate | product-analyst, solution-architect agents + superpowers (brainstorming) + inline estimation | Standalone estimation |
```

- [ ] **Step 2: Add estimation to the memory dependency table**

In `CLAUDE.md`, find the Per-Ticket Memory dependency table (near the 79). Add a row after `plan-review` and before `implementation`:

```markdown
| estimation | `ticket.md`, `analysis.md`, `brainstorm.md`, `plan.md` (if exists) | `overview.md` (estimation section) |
```

- [ ] **Step 3: Add Estimation section to Architecture**

In `CLAUDE.md`, add a new `### Estimation` section after the `### Ticket Description Enrichment` section (which ends around line 115) and before `### Error Tracking Routing`:

```markdown
### Estimation

Optional complexity classification and delivery time estimation. Gated on `estimation.enabled` (default false) in `n1.config.json`. When enabled, the orchestrator classifies task complexity into tiers (XS/S/M/L/XL), maps to a configurable time estimate, and writes results to overview.md + tracker ticket (description append + time field).

- **Pipeline integration:** after plan for complex tasks (Step 4c), after complexity decision for simple tasks (Step 5b). Uses the best available context — plan.md when present, brainstorm.md otherwise.
- **Standalone:** `n1-estimate` skill runs Steps 1–3 (ticket → analysis → brainstorm) then estimates. No implementation, no branch creation, no status transitions.
- **Default mapping** in `defaults/estimation.json` (N1 repo): XS=30m, S=2h, M=6h, L=2d, XL=5d. Overridable per-project via `estimation.mapping` in config (partial overrides merge with defaults).
- **Tracker writes:** Jira `originalEstimate` via `editJiraIssue`, YouTrack `Estimation` field via `update_issue`. Both non-blocking. Idempotency marker: `*Estimated by N1*`.
```

- [ ] **Step 4: Verify all three changes are consistent**

Read the modified CLAUDE.md and confirm:
- The orchestration table has 6 rows (n1-start, n1-review, n1-pr, n1-ci, n1-init, n1-estimate)
- The memory dependency table includes the estimation row in the right position
- The Estimation section accurately reflects the spec
- No contradictions with existing sections

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(CLAUDE.md): document estimation feature architecture"
```

---

### Task 6: Update README.md

**Files:**
- Modify: `README.md` — add estimation to Quick Start, Skills, and feature documentation

- [ ] **Step 1: Add n1-estimate to Quick Start**

In `README.md`, find the Quick Start section (near the 29). Add a new example line in the "standalone skills" block:

```markdown
/n1:n1-estimate TRID-510             # estimate a ticket
```

Insert this after the `/n1:n1-review` lines and before any closing comments.

- [ ] **Step 2: Add n1-estimate skill section**

In `README.md`, find the Skills section. Add a new subsection after the `### /n1:n1-init` section (near the 96):

```markdown
### `/n1:n1-estimate` — Task Estimation

Estimates task complexity and delivery time. Runs the analysis pipeline (ticket read → codebase analysis → brainstorm), classifies complexity into a tier (XS–XL), and maps to a time estimate.

- Writes estimate to tracker ticket (description + time field) when enabled
- Reuses existing analysis if the ticket was previously analyzed
- No branch creation or status transitions — read-only analysis
- Configure via `/n1:n1-init` or set `estimation.enabled: true` in `.n1/n1.config.json`
```

- [ ] **Step 3: Add estimation to n1-init wizard description**

In `README.md`, find the n1-init wizard steps list (near the 89). Add a new step after step 5 (error tracking):

```markdown
6. Configures estimation (off by default — complexity tier → delivery time)
```

Renumber the subsequent steps (current 6 and 7 become 7 and 8).

- [ ] **Step 4: Add Estimation section after Error Tracking Support**

In `README.md`, add a new section after `## Error Tracking Support` (near the 119) and before `## How It Works`:

```markdown
## Estimation

Optional complexity classification that maps tasks to delivery time estimates. Off by default — enable via `n1-init` or set `estimation.enabled: true` in `.n1/n1.config.json`.

| Tier | Default Time | Characteristics |
|------|-------------|-----------------|
| XS | 30m | Config change, typo, single-line fix |
| S | 2h | Single file, clear scope, no migrations |
| M | 6h | 2-5 files, may need tests, straightforward |
| L | 2d | Multiple files, migrations, new tests |
| XL | 5d | Cross-cutting, architectural, multi-subsystem |

Times represent total delivery (including QA/review), not just coding. Default mapping is overridable per-project via `estimation.mapping` in config.

When enabled, estimation runs automatically in the `n1-start` pipeline (after plan for complex tasks, after brainstorm for simple tasks) and writes to the tracker's time field (Jira `originalEstimate`, YouTrack `Estimation`). Use `/n1:n1-estimate` standalone to estimate without running the full pipeline.
```

- [ ] **Step 5: Add estimation row to Per-Ticket Memory table**

In `README.md`, find the Per-Ticket Memory table (near the 143). Add an estimation row after `plan` and before `implementation`:

```markdown
| estimation | `ticket.md`, `analysis.md`, `brainstorm.md`, `plan.md` (if exists) | `overview.md` |
```

- [ ] **Step 6: Verify all changes are consistent**

Read the modified README.md and confirm:
- Quick Start shows n1-estimate
- Skills section includes n1-estimate
- n1-init wizard steps are correctly numbered
- Estimation section accurately reflects the spec
- Memory table is consistent with CLAUDE.md

- [ ] **Step 7: Commit**

```bash
git add README.md
git commit -m "docs(README.md): add estimation feature documentation"
```

---

### Task 7: End-to-End Verification

**Files:**
- Read: all modified files

This task verifies cross-file consistency. No code changes — just validation.

- [ ] **Step 1: Verify n1-start estimation step references resolve**

Read `skills/n1-start/SKILL.md` and confirm:
- The Estimation section exists and is complete
- The simple path references "run the Estimation procedure"
- The complex path has Step 4c referencing the Estimation section
- The step dependency map includes the estimation row
- The overview.md template includes the Estimation checkbox

- [ ] **Step 2: Verify n1-estimate references n1-start estimation procedure**

Read `skills/n1-estimate/SKILL.md` and confirm:
- Step 4 (ESTIMATE) references the n1-start Estimation procedure
- The gate check matches the spec (`estimation.enabled === true`)
- Memory reuse logic is correct (skip to estimation if prior files exist)
- No branch creation, no status transitions

- [ ] **Step 3: Verify n1-init produces valid config**

Read `skills/n1-init/SKILL.md` and confirm:
- The estimation section is between Error Tracking and Review Configuration
- The assembled config template includes the estimation block
- The summary output includes the estimation line
- Reconfiguration flow handles all cases (Keep/Enable/Disable/Update mapping)

- [ ] **Step 4: Verify defaults/estimation.json matches all references**

Read `defaults/estimation.json` and confirm:
- The tier names (XS/S/M/L/XL) match those used in n1-start, n1-estimate, n1-init, CLAUDE.md, and README.md
- The time values (30m/2h/6h/2d/5d) match the n1-init default display and README table

- [ ] **Step 5: Verify CLAUDE.md and README.md are consistent**

Compare the estimation sections in both files:
- Memory dependency tables match
- Orchestration table in CLAUDE.md includes n1-estimate
- Feature description in README.md matches spec
- Tier table values match defaults/estimation.json

- [ ] **Step 6: Run a final git status and log**

Run: `git status` and `git log --oneline -10`
Expected: clean working tree, 7 new commits (one per task above)
