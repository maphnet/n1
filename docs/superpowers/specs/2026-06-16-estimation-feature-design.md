# Estimation Feature Design

## Overview

Add configurable estimation to the N1 orchestrator. The system classifies task complexity into tiers (XS/S/M/L/XL) internally, maps tiers to delivery time estimates via a configurable mapping table, and writes results to the tracker ticket (description + time field) and per-ticket memory.

Estimation is off by default. When enabled via `n1-init` or manual config, it runs automatically as part of the `n1-start` pipeline and is available standalone via the `n1-estimate` skill.

## Design Decisions

- **Internal unit:** complexity tier (XS/S/M/L/XL) — coarse, transparent, hard to over-interpret
- **External unit:** time estimate (total delivery time including QA/review, not just coding)
- **No new agents:** estimation is an inline orchestrator step (same pattern as post-brainstorm enrichment)
- **Non-blocking:** all tracker writes are non-blocking on failure — pipeline continues regardless
- **Idempotent:** `*Estimated by N1*` marker prevents duplicate writes on restart/re-estimation

## Research Basis

- Zero-shot LLM estimation outperforms supervised ML baselines (Pearson 0.404 on Choetkiertikul benchmark) — and N1 has far richer context than title + description alone
- Community sentiment (Stack Overflow 2025): 69% resist AI for planning — transparency and coarse granularity are critical mitigations
- Estimation accuracy scales with available context — post-plan estimation has the richest signal
- AI estimation should be positioned as suggestion, not commitment — the "Basis" line in output addresses this

## Configuration Schema

New `estimation` block in `.n1/n1.config.json`:

```json
{
  "estimation": {
    "enabled": false,
    "writeToTracker": true,
    "mapping": {
      "XS": "30m",
      "S":  "2h",
      "M":  "6h",
      "L":  "2d",
      "XL": "5d"
    }
  }
}
```

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `false` | Master switch. Off by default, enabled via n1-init. |
| `writeToTracker` | boolean | `true` | Write estimate to tracker description + time field. When false, estimate is written to memory and output only. |
| `mapping` | object | (from `defaults/estimation.json`) | Tier-to-time mapping. Partial overrides merge with defaults — only specify tiers you want to change. |

### Time format

Same period notation used by Jira and YouTrack natively: `30m`, `2h`, `1d`, `1d 4h`, `1w 2d`. Passed through to tracker APIs without conversion.

### Gating logic

Estimation step runs when ALL conditions are met:
- `estimation.enabled === true`

Tracker writes happen when additionally:
- `tracker.mcp` exists
- `tracker.operations.editTicket` exists
- `estimation.writeToTracker !== false`

When tracker writes are gated off, estimation still runs and writes to memory + conversation output.

## N1 Repo Defaults

New file `defaults/estimation.json` — single source of truth for default mapping:

```json
{
  "mapping": {
    "XS": "30m",
    "S":  "2h",
    "M":  "6h",
    "L":  "2d",
    "XL": "5d"
  }
}
```

At runtime, the orchestrator loads this file, then merges any project-level `estimation.mapping` overrides on top. Projects only need to specify tiers they want to change.

### Default tier characteristics

| Tier | Time | Characteristics |
|------|------|-----------------|
| XS | 30m | Config change, typo, single-line fix |
| S | 2h | Single file, clear scope, no migrations |
| M | 6h | 2-5 files, may need tests, straightforward |
| L | 2d | Multiple files, migrations, new tests |
| XL | 5d | Cross-cutting, architectural, multi-subsystem |

## Pipeline Integration

### Insertion points

Two insertion points in `n1-start`, same estimation logic at both:

**Complex path** — after Step 6b (Plan Review), before Step 7 (Plan Checkpoint):
```
... → Step 6 (plan) → Step 6b (plan review) → [Step 6c: ESTIMATE] → Step 7 (checkpoint) → ...
```

**Simple path** — after Step 5 (complexity decision: simple), before Step 8 (implement):
```
... → Step 5 (simple) → [Step 5b: ESTIMATE] → Step 8 (implement) → ...
```

### Estimation step logic

1. **Gate check:** `estimation.enabled !== true` → skip silently
2. **Load mapping:** read `estimation.mapping` from project config, merge with `defaults/estimation.json` for missing tiers
3. **Read context** — load available memory files:
   - Always: `ticket.md`, `analysis.md`, `brainstorm.md`
   - Complex path only: `plan.md`
4. **Classify complexity tier** (XS/S/M/L/XL) using these signals:
   - Number of files/components affected (from plan or brainstorm)
   - Whether new infrastructure is needed (migrations, new services, new dependencies)
   - Test requirements (new test suites vs. extending existing)
   - Cross-cutting concerns (touches multiple subsystems?)
   - Uncertainty level (new territory vs. well-understood patterns)
5. **Map tier → time** using the merged mapping table
6. **Generate basis** — one sentence explaining why this tier was chosen, referencing concrete signals from the context
7. **Write to memory:** append estimation section to `overview.md`
8. **Write to ticket description** (if tracker + writeToTracker gating passes):
   - Fetch current description via `readTicket` operation
   - Check for `*Estimated by N1*` marker — if present, skip (idempotent)
   - Append estimation block (format below)
   - Call `editTicket` — non-blocking on failure
9. **Write to tracker time field** (if tracker + writeToTracker gating passes):
   - Jira: set `timetracking.originalEstimate` via `editJiraIssue`
   - YouTrack: set `Estimation` field via `update_issue`
   - Non-blocking on failure

### Memory output

Written to `overview.md`:

```markdown
### Estimation
**Complexity:** M (Medium)
**Estimated delivery:** 6h
**Basis:** 4 files affected, includes new tests, no migrations. Design is straightforward with existing patterns.
```

### Tracker description output

Appended to ticket description:

```markdown
---
*Estimated by N1*

**Complexity:** M (Medium)
**Estimated delivery:** 6h
**Basis:** 4 files affected, includes new tests, no migrations.
```

### Memory dependency update

| Step | Reads | Writes |
|------|-------|--------|
| estimation | `ticket.md`, `analysis.md`, `brainstorm.md`, `plan.md` (if exists) | `overview.md` (estimation section) |

## Standalone Estimation Skill (`n1-estimate`)

New skill for estimating existing tickets without running the full pipeline.

### Invocation

`/n1:n1-estimate` — accepts ticket ID, file path, or brain dump (same input modes as n1-start).

### Flow

1. **Gate check:** `estimation.enabled !== true` → refuse with "Estimation is not enabled. Run `/n1:n1-init` to configure."
2. **Input resolution** — spawn `product-analyst` (same as n1-start Step 1)
   - No working branch creation
   - No status transition (does not move ticket to "In Progress")
3. **Analysis** — spawn `solution-architect` (same as n1-start Step 2)
4. **Brainstorm** — invoke `superpowers:brainstorming` (same as n1-start Step 3)
5. **Estimate** — run the estimation step logic (Section: Estimation step logic above)
6. **Stop** — do not continue to implementation, QA, review, or PR

### Key differences from n1-start

- Stops after estimation — no implementation, QA, review, or PR
- No working branch creation (read-only analysis)
- No status transitions
- Memory written to `.n1/memory/<ID>/` as usual — if user later runs `/n1:n1-start` on the same ticket, existing memory files (ticket.md, analysis.md, brainstorm.md) are reused

### Output

- If tracker configured + `writeToTracker`: writes to tracker description + time field automatically
- If no tracker or writeToTracker disabled: outputs estimate to conversation

## n1-init Integration

New wizard step after Error Tracking configuration (current Step 8), before Review Configuration.

### Flow

```
Ask: "Enable estimation for tickets?
Estimates task complexity and writes delivery time to tracker.
1 — Yes
2 — No (default)"
```

**If 2 (No) or default:**
- Set `estimation.enabled: false`
- Skip mapping customization
- Omit `writeToTracker` and `mapping` from config

**If 1 (Yes):**
- Set `estimation.enabled: true`
- Set `estimation.writeToTracker: true`
- Show default mapping table:

```
Default delivery time mapping:
  XS  30m   (config change, typo, single-line fix)
  S   2h    (single file, clear scope, no migrations)
  M   6h    (2-5 files, may need tests, straightforward)
  L   2d    (multiple files, migrations, new tests)
  XL  5d    (cross-cutting, architectural, multi-subsystem)

Customize mapping? 1 — Use defaults (recommended) / 2 — Customize
```

**If 1 (Use defaults):** omit `mapping` from config (orchestrator loads from `defaults/estimation.json`)

**If 2 (Customize):** ask for each tier value as a time string. Only store tiers the user changed — partial overrides merge with defaults at runtime.

### Reconfiguration

When `.n1/n1.config.json` already exists:
- Show current state: "Estimation: enabled/disabled, mapping: default/custom"
- Offer: "Keep / Enable / Disable / Update mapping"

### No new tracker operations needed

Estimation uses existing operations:
- `readTicket` — fetch current description before append
- `editTicket` — write description + time field

Jira time field: `timetracking.originalEstimate` is part of the standard `editJiraIssue` payload, no field discovery needed.

YouTrack time field: `Estimation` is a standard period field, set via `update_issue`.

## Tracker Write Mechanics

### Jira

**Time estimate:**
```
mcp__plugin_atlassian_atlassian__editJiraIssue with:
  cloudId: <from discovery>
  issueIdOrKey: <ticket ID>
  timetracking: { originalEstimate: "6h" }
```

Time format (`"30m"`, `"2h"`, `"1d 4h"`, `"5d"`) passes through directly — native Jira format.

**Description append** (separate or combined call):
```
mcp__plugin_atlassian_atlassian__editJiraIssue with:
  cloudId: <cloudId>
  issueIdOrKey: <ticket ID>
  description: <current description + estimation block>
```

Requires read-before-write via `getJiraIssue` to append rather than overwrite. If the read fails, skip the description append (non-blocking) but still attempt the time field write.

### YouTrack

**Time estimate:**
```
mcp__youtrack__update_issue with:
  issueId: <ticket ID>
  Estimation field via customFields or command
```

Period format (`"2h"`, `"1d"`, `"5d"`) is native to YouTrack.

**Description append:**
```
mcp__youtrack__update_issue with:
  issueId: <ticket ID>
  description: <current description + estimation block>
```

Same read-before-write pattern via `get_issue`. If the read fails, skip description append (non-blocking) but still attempt the time field write.

### Failure handling

All tracker writes (description append, time field) are non-blocking:
- Try MCP call
- On failure: log `"⚠ Estimation write failed: <reason>"`, continue pipeline
- Never roll back prior steps
- Never stop the pipeline for estimation failures

### Idempotency

`*Estimated by N1*` marker in description checked before any write. If present, skip description append. Time field is overwritten (latest estimate wins — re-estimation after plan changes should update the time).

## Complexity Classification Prompt

The orchestrator classifies the tier using a structured prompt that reads all available memory files and evaluates:

1. **Scope signals:**
   - File count (from plan task list or brainstorm design)
   - Component/module count
   - Whether changes cross subsystem boundaries
2. **Infrastructure signals:**
   - Database migrations needed
   - New services or dependencies
   - Configuration changes (env vars, feature flags)
3. **Test signals:**
   - New test suites required vs. extending existing
   - Integration test needs
   - Manual testing requirements
4. **Uncertainty signals:**
   - New technology or unfamiliar patterns
   - External dependency risks
   - Ambiguities noted in ticket.md or analysis.md

The prompt outputs: tier (XS/S/M/L/XL), full tier name, and a one-sentence basis referencing specific signals.

## Files Changed

| File | Change |
|------|--------|
| `defaults/estimation.json` | **New** — default tier-to-time mapping |
| `skills/n1-start/SKILL.md` | Add estimation step at two insertion points (Step 5b, Step 6c) |
| `skills/n1-estimate/SKILL.md` | **New** — standalone estimation skill |
| `skills/n1-init/SKILL.md` | Add estimation wizard step after error tracking |
| `CLAUDE.md` | Update architecture tables (pipeline steps, config schema, memory dependencies) |
| `README.md` | Add estimation to feature list and configuration docs |

## Non-Goals

- Story points output (only time estimates)
- Historical estimation accuracy tracking (future consideration)
- Per-developer velocity adjustment
- Estimation for sub-tasks within a plan (estimation is per-ticket only)
- Separate estimator agent (orchestrator handles inline)
