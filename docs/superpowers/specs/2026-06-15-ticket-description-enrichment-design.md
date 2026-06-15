# Ticket Description Enrichment

When `n1-start` receives a ticket ID and the tracker description is poor or absent, N1 enriches it — writing structured content back to the tracker so the ticket becomes self-contained.

## Quality Assessment Model

The product-analyst performs a three-tier quality check after fetching the ticket:

| Tier | Condition | Action |
|------|-----------|--------|
| **Empty** | Description is blank or whitespace-only | Silent append: generate full structured description |
| **Skeletal** | ≤1 meaningful sentence OR missing acceptance criteria entirely | Silent append: add missing structural sections |
| **Weak** | ≥2 ambiguities flagged OR missing critical type-specific sections | Propose rewrite: show current vs proposed, wait for user approval |

### Type-Aware Minimum Viable Sections

What counts as "missing critical sections" depends on ticket type:

- **Bug**: steps to reproduce, actual vs expected behavior, environment, severity
- **Feature/Story**: user context, acceptance criteria, scope boundaries
- **Task/Improvement**: definition of done, acceptance criteria

These checklists are evaluated against the raw tracker description, not against the product-analyst's own enriched output.

## Two-Phase Enrichment

### Phase 1: Immediate Enrichment (product-analyst)

Runs during Step 1 (Requirements Analysis), after the ticket is fetched but before `ticket.md` is written.

**Flow:**

1. Fetch ticket via MCP (existing behavior)
2. Assess description quality → assign tier (Empty / Skeletal / Weak / Adequate)
3. If tier is **Adequate** → skip enrichment, proceed to normal analysis
4. If tier is **Empty** or **Skeletal** → generate enrichment content, update tracker description silently (append)
5. If tier is **Weak** → generate proposed rewrite, present to user:
   ```
   The ticket description has gaps (<list specific gaps>).
   
   **Current description:**
   <current>
   
   **Proposed rewrite:**
   <proposed>
   
   1 — Apply rewrite
   2 — Skip, continue with current description
   ```
   If user chooses 1 → update tracker description (full replace). If 2 → skip.

**Append format** (Empty/Skeletal tiers):

```
---
*Structured by N1*

### Acceptance Criteria
- [ ] <inferred criterion 1>
- [ ] <inferred criterion 2>

### <Type-specific section(s)>
<content inferred from title, comments, and available context>
```

The separator `---` + attribution line clearly marks auto-generated content. Sections are only added when missing — if the description already has acceptance criteria (however informal), the product-analyst does not duplicate them.

**Rewrite format** (Weak tier, user-approved):

The full description is replaced with the product-analyst's structured version. The original text is preserved as a collapsed section at the top:

```
<details><summary>Original description</summary>

<original text>

</details>

### Core Ask
<1-2 sentences>

### Acceptance Criteria
- [ ] <criterion>

### <Type-specific sections>
<content>

---
*Restructured by N1*
```

### Phase 2: Post-Brainstorm Enrichment (orchestrator)

Runs after Step 3 (Brainstorm) completes, before Step 4 (Plan).

The brainstorming step produces a richer understanding: refined requirements, design decisions, scope boundaries. This phase pushes two things back to the tracker:

**A. Description update** (append):

```
---
*Refined after design review — N1*

### Refined Acceptance Criteria
- [ ] <refined criterion — more specific than Phase 1>

### Scope Boundaries
- In scope: <what's included>
- Out of scope: <what's explicitly excluded>
```

This appends below any Phase 1 enrichment. Only sections that add new information are included — if brainstorming didn't refine the AC or scope, this step is skipped entirely.

**B. Comment** (activity feed):

A single comment summarizing the design outcome:

```
**Design Summary (N1)**

Approach: <1-2 sentence summary of chosen approach>
Key decisions:
- <decision 1>
- <decision 2>

Design doc: internal (per-ticket memory)
```

This keeps the tracker activity feed useful for team members who aren't in the Claude Code session.

## Config Changes

### New operation: `editTicket`

Added to `tracker.operations` in `n1.config.json`:

| Tracker | Operation key | MCP tool |
|---------|--------------|----------|
| Jira | `editTicket` | `editJiraIssue` |
| YouTrack | `editTicket` | `update_issue` |

For Jira, `editJiraIssue` is already used for `assign` — it's a general-purpose issue edit tool that accepts field updates including `description`. The call passes `cloudId`, `issueIdOrKey`, and `description` (the full new description text). For YouTrack, `update_issue` is already used for `moveStatus` — it also accepts a `description` field. The call passes `issueId` and `description`.

In both cases, the caller must first read the current description (already fetched), then construct the full new value (original + appended sections for append, or the complete rewrite for replace) and send it as the `description` field.

### New config flag: `ticketEnrichment`

Top-level config block (optional — enrichment is ON by default when the operation exists):

```json
{
  "ticketEnrichment": {
    "enabled": true
  }
}
```

- `enabled: true` (default when block is absent) — enrichment runs as described
- `enabled: false` — all enrichment is skipped; product-analyst behaves as before

The flag is a simple on/off. The graduated quality tiers and user-confirmation-for-rewrite behavior are built into the product-analyst logic, not configurable.

### Backward Compatibility

When `tracker.operations.editTicket` is absent (existing configs that haven't been updated), enrichment is silently disabled — the product-analyst logs "Enrichment skipped: editTicket operation not configured" and proceeds with normal read-only analysis. No error, no user prompt.

## File Changes

### 1. `agents/product-analyst.md`

Add Phase 1 enrichment as a new responsibility after ticket fetch:

- New section: "Description Quality Assessment" between fetch and analysis
- Quality tier logic with type-aware minimum viable sections
- Enrichment content generation
- MCP call to update description (append or rewrite)
- User prompt for Weak tier rewrite approval
- New output field in ticket.md: `## Description Quality` with tier, action taken, and what was added

The agent needs `trackerMcp` and `operations` (already passed in ticket mode) plus the new `operations.editTicket` to call the edit tool.

### 2. `skills/n1-start/SKILL.md`

Add Phase 2 enrichment after brainstorming:

- New sub-step between "After brainstorming completes" and "Complexity Decision"
- Reads `brainstorm.md` to extract refined AC, scope, design summary
- Calls `mcp__<tracker.mcp>__<tracker.operations.editTicket>` to append refined sections
- Calls `mcp__<tracker.mcp>__<tracker.operations.addComment>` for design summary comment
- Gated on: ticket mode only (brain-dump/file/error-tracker modes that created tickets also qualify), `ticketEnrichment.enabled !== false`, `tracker.operations.editTicket` exists
- Skipped silently when brainstorming didn't produce meaningful refinements over Phase 1

### 3. `skills/n1-init/SKILL.md`

Add `editTicket` to the operations config templates for both Jira and YouTrack.

### 4. `CLAUDE.md`

Update the Tracker Routing table to include the new `editTicket` operation.

Update the Pipeline Steps dependency table if the enrichment step writes new artifacts (it doesn't — it writes to the tracker, not to memory files, except the `## Description Quality` section in `ticket.md`).

## Edge Cases

- **No tracker configured** (`tracker.mcp` is null): enrichment is impossible — skip silently.
- **MCP edit call fails** (permissions, network): log warning, proceed with read-only analysis. Enrichment is non-blocking — a failed update must never stop the pipeline.
- **Ticket already enriched** (resume scenario): the Phase 1 separator `---\n*Structured by N1*` acts as an idempotency marker. If the product-analyst detects this marker in the description, it skips Phase 1 enrichment entirely. Phase 2 uses its own marker `*Refined after design review — N1*`.
- **User declines rewrite**: product-analyst proceeds with normal analysis using the original description. The Ambiguities section in `ticket.md` captures the gaps for downstream agents.
- **Brain-dump that creates a ticket**: the ticket was just created with a clean structured description — quality is adequate by construction. Skip Phase 1. Phase 2 still runs after brainstorming.
- **Error-tracker mode that creates a ticket**: same as brain-dump — freshly created, skip Phase 1.
- **Description in a non-English language**: the product-analyst works with whatever language the description is in. Enrichment sections are written in the same language as the existing description content, not forced to English.
