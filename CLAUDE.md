# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

See [README.md](README.md) for user-facing documentation: installation, quick start, skill usage examples, and full feature overview.

## Language Policy

ALL code, documentation, skills, agents, hooks, comments, and commit messages MUST be in English.
Russian is prohibited in any committed file.

## What This Is

N1 is a Claude Code plugin that orchestrates the full development cycle (ticket read, analysis, brainstorm, plan, implement, QA, review, PR). It uses a **hybrid delegation model**: 8 specialized agent personas handle autonomous work (analysis, QA, review, fixes, PR content), while [Superpowers](https://github.com/obra/superpowers) ^5.0 sub-skills handle interactive steps (brainstorming, planning, implementation dispatch via SDD). It is a **thin controller** (~5-10K tokens per skill): skills load only the memory files they need, spawn agents or invoke Superpowers, and write results back to per-ticket memory.

## Stack

- **Runtime:** Bash (hooks), Markdown (skills, agents) — no npm, no Node.js
- **Plugin manifest:** `.claude-plugin/plugin.json`
- **Dependency:** Superpowers plugin ^5.0

## Testing

- **Local dev:** `claude --plugin-dir C:\Dev\n1` from any test project
- **Reload skills:** `/reload-plugins` (no restart needed)
- **Always test on a separate repo before committing**
- **Dogfooding:** use N1 skills on the N1 repo itself

## Development Workflow

**Always develop via `--plugin-dir`** — it loads the **working tree live** (uncommitted edits included). No install, no commit, no version bump, no reinstall.

```
claude --plugin-dir C:\Dev\n1   # from a test project
# edit files → /reload-plugins → changes are live
```

Do NOT install N1 as a user-scope plugin for local development. A `file://` marketplace install copies from committed git HEAD into a cache, so local edits never show up without commit + version bump + reinstall — `--plugin-dir` avoids all of that.

### Notes for any future install/publish

- A `file://` marketplace install copies from committed git **HEAD** into a cache, not the working tree. Refreshing it requires a `version` bump (in **both** `plugin.json` and `marketplace.json`, which must match) followed by `claude plugin marketplace update n1` + `claude plugin update n1@n1`.
- The `plugin.json` schema rejects marketplace-qualified dependency names (`name@marketplace` gives `dependencies.0: Invalid input`). Use a bare name, e.g. `{ "name": "superpowers", "version": "^5.0" }`. The bare-name dependency resolver assumes the declaring plugin's own marketplace, which is why install-time dependency resolution against an external marketplace is unreliable — another reason to prefer `--plugin-dir`.

## Conventions

- **Skill authoring:** Always use `/writing-skills` skill when creating or modifying skills
- Skills: `skills/<name>/SKILL.md` — auto-discovered, invoked as `/n1:<skill-name>`
- Agents: `agents/<name>.md` — frontmatter requires `name`, `description`, `model`; optional `tools` (comma-separated allowlist of tool identifiers). Agents are dispatched as file-based subagents (by name), so Claude Code **enforces** this allowlist at runtime — it is a real capability boundary, not advisory. MCP tools must be named `mcp__<server>__<tool>`; a human label like "Tracker MCP" grants nothing. Omit `tools` entirely to inherit the orchestrator's full tool set — required when an agent needs config-dynamic tracker MCP tools whose names vary by tracker (e.g. product-analyst)
- Hooks: `hooks/hooks.json` — event declarations, scripts in `hooks/`
- One concern per file
- Skills invoke each other via `**REQUIRED SUB-SKILL:** Use plugin:skill-name` directives
- No Co-Authored-By trailers in commits
- **Timestamps:** Never let the model invent a timestamp — it has no clock and will hallucinate (e.g. drifting `+1h` on each rewrite). Date-only needs (spec/plan filenames `YYYY-MM-DD`) use the harness-injected `currentDate`. Precise time (time-of-day, durations) must come from the `date` command, e.g. `date -u +%Y-%m-%dT%H:%M:%SZ`. Don't add timestamp fields unless something actually reads them — file mtime already records "last modified".
- **Test & benchmark artifacts:** Tests/benchmarks that verify committed implementation (unit, integration, e2e tied to acceptance criteria) go in the repo and run in CI. Throwaway probes that only answer a current question (approach micro-benchmarks, repro scripts, viability spikes) go under `.n1/` (gitignored) — per-ticket `.n1/memory/<ID>/{benchmarks,tests}/`, or `.n1/scratch/{benchmarks,tests}/` when there is no ticket memory. When unsure, default to scratch. Bound into the `solution-architect`, `developer`, and `qa-engineer` personas; concrete paths are passed by the skills at spawn time.

## Architecture

### Orchestration Pattern

Skills are lightweight controllers that delegate all heavy work:

| N1 Skill | Delegates To | Purpose |
|----------|-------------|---------|
| n1-start | product-analyst, solution-architect, planner, qa-engineer agents + superpowers (brainstorming, writing-plans, SDD) | Full pipeline |
| n1-review | code-reviewer, security-reviewer, developer agents | Review + fix loop |
| n1-pr | tech-writer agent + inline git/gh/MCP | Doc update, push, create PR, update tracker |
| n1-ci | developer agent + inline gh CLI | Post-PR CI watch, classify failures, fix loop |
| n1-init | (inline: analysis + prompts) | Project setup wizard |
| n1-estimate | product-analyst, solution-architect agents + superpowers (brainstorming) + inline estimation | Standalone estimation |

Superpowers calls use the `superpowers:` prefix. Agent spawns use N1's own agent definitions. Each gets fresh context — the orchestrator never accumulates full history.

### Per-Ticket Memory (`.n1/`)

The `.n1/` directory is **ephemeral and gitignored**. It lives in target projects, not in this repo.

Each step reads ONLY its declared dependencies:

| Step | Reads | Writes |
|------|-------|--------|
| ticket | — | `ticket.md` |
| analysis | `ticket.md` | `analysis.md` |
| brainstorm | `ticket.md`, `analysis.md` | `brainstorm.md` |
| plan | `ticket.md`, `brainstorm.md`, `analysis.md` | `plan.md` |
| plan-review | `ticket.md`, `analysis.md`, `brainstorm.md`, `plan.md` | `plan.md` (in-place fixes) |
| estimation | `ticket.md`, `analysis.md`, `brainstorm.md`, `plan.md` (if exists) | `overview.md` (estimation section) |
| implementation | `brainstorm.md`, `plan.md` | `implementation.md` |
| qa | `ticket.md`, `implementation.md`, `plan.md` | `qa.md` |
| review | `ticket.md`, `brainstorm.md`, `implementation.md`, `qa.md` | `review.md` |
| pr | `overview.md`, `review.md`, `qa.md`, `implementation.md` | `overview.md` (updates) |
| ci | `overview.md`, `plan.md`, `implementation.md` | `overview.md` (CI status) |

### Tracker Routing

Tracker MCP tool names are never hardcoded — they're resolved at runtime from `n1.config.json` operations map. The `tracker.type` field (`"jira"` or `"youtrack"`) controls conditional branching (parameter shapes, cloudId resolution); the `tracker.mcp` field (e.g., `"jira-velosity"`, `"youtrack"`) controls MCP tool call prefix construction (`mcp__<tracker.mcp>__<operation>`). Two presets exist:

| Tracker | type | mcp value | Key operations |
|---------|------|-----------|---------------|
| Jira | `jira` | `plugin_atlassian_atlassian` | `getJiraIssue`, `transitionJiraIssue`, `addCommentToJiraIssue`, `getTransitionsForJiraIssue`, `atlassianUserInfo` (getCurrentUser), `editJiraIssue` (assign, editTicket) |
| YouTrack | `youtrack` | `youtrack` | `get_issue`, `update_issue` (moveStatus, editTicket), `add_issue_comment`, `get_issue_comments`, `get_current_user` (getCurrentUser), `change_issue_assignee` (assign) |

When `ticketTagging.enabled` is true, `n1-start` prefixes created tickets with `ticketTagging.service` (`{service} | title`) and adds a `**Service:**` line to the description. Off by default; configured by `n1-init`. Creation only — existing tickets are never re-tagged.

When `tracker.assignToCreator` is not `false` (default ON), `n1-start` assigns tickets it creates to the currently-authenticated tracker user via the `getCurrentUser` + `assign` operations. Creation only; non-fatal on failure; silently skipped when those operations are absent (legacy configs). Configured by `n1-init`.

On brain-dump/file runs where the user opts to create a ticket, `n1-start` adopts the **created ticket ID** as the per-ticket memory `<ID>` and branch name. An ID-Final invariant blocks any memory/branch write until that ID is known; if state was already written under the provisional slug, the idempotent `Reconcile Memory ID & Branch` procedure moves the memory folder and renames the branch (`git branch -m`) to the ticket-ID-based names.

### Ticket Description Enrichment

Optional two-phase enrichment that writes structured content back to the tracker when a ticket description is poor or absent. Gated on `ticketEnrichment.enabled` (default true) and the `editTicket` operation existing in config.

- **Phase 1** (product-analyst, Step 1): quality assessment (Empty / Skeletal / Weak / Adequate) → silent append for empty/skeletal descriptions, user-approved rewrite for weak descriptions. Idempotency markers: `*Structured by N1*` / `*Restructured by N1*`.
- **Phase 2** (orchestrator, after Step 3 Brainstorm): appends refined acceptance criteria and scope boundaries to description, posts a design summary comment. Idempotency marker: `*Refined after design review — N1*`.

Both phases are non-blocking — MCP failures are logged and skipped. Freshly created tickets (brain-dump/file/error-tracker modes) skip Phase 1 (adequate by construction).

### Estimation

Optional complexity classification and delivery time estimation. Gated on `estimation.enabled` (default false) in `n1.config.json`. When enabled, the orchestrator classifies task complexity into tiers (XS/S/M/L/XL), maps to a configurable time estimate, and writes results to overview.md + tracker ticket (description append + time field).

- **Pipeline integration:** after plan for complex tasks (Step 4c), after complexity decision for simple tasks (Step 5b). Uses the best available context — plan.md when present, brainstorm.md otherwise.
- **Standalone:** `n1-estimate` skill runs Steps 1–3 (ticket → analysis → brainstorm) then estimates. No implementation, no branch creation, no status transitions.
- **Default mapping** in `defaults/estimation.json` (N1 repo): XS=30m, S=2h, M=6h, L=2d, XL=5d. Overridable per-project via `estimation.mapping` in config (partial overrides merge with defaults).
- **Tracker writes:** Jira `originalEstimate` via `editJiraIssue`, YouTrack `Estimation` field via `update_issue`. Both non-blocking. Idempotency marker: `*Estimated by N1*`.

### Error Tracking Routing

Optional integration with error-tracking systems (Sentry first, extensible to Datadog/Rollbar). Config-driven via `errorTracking` block in `n1.config.json` — same operations-map pattern as tracker routing. When `errorTracking` is `null` or absent, the feature is fully disabled.

| Provider | mcp value | Key operations |
|----------|-----------|---------------|
| Sentry | `sentry` | `get_sentry_issue` (getIssue), `search_sentry_issues` (searchIssues), `list_projects` (listProjects), `get_autofix_state` (getAiAnalysis) |

Two pipeline touchpoints:
- **Intake** (n1-start + product-analyst): URL detection via `errorTracking.urlPattern`, MCP fetch of issue data + optional AI root-cause analysis, structured `ticket.md` with error-specific sections
- **Analysis** (solution-architect): search for related issues via `errorTracking.operations.searchIssues`, reported in `analysis.md`

Memory ID for error-tracker runs: `sentry-<issueId>` (provisional; replaced by tracker ticket ID if user creates one). Ticket creation is optional — reuses the brain-dump ticket-creation flow with a Sentry link prepended to the description.

### Agent Personas

8 atomic agents with scoped tools and configurable models:

| Agent | Default Model | Tools | Pipeline Stage |
|-------|---------------|-------|----------------|
| product-analyst | sonnet | inherits (needs dynamic tracker + error-tracking MCP) | Ticket read, Error intake, Description enrichment |
| solution-architect | opus | Read, Grep, Glob, Bash, WebSearch, WebFetch | Analysis, Bug investigation, Plan review (CCR) |
| planner | opus | Read, Grep, Glob, Write, Edit, Skill, WebSearch, WebFetch | Plan writing |
| developer | opus | Read, Edit, Write, Bash, Grep, Glob | Implementation, Fix cycle, CI fix |
| code-reviewer | opus | Read, Grep, Glob | Review (parallel) |
| security-reviewer | opus | Read, Grep, Glob | Review (parallel) |
| qa-engineer | sonnet | Read, Edit, Write, Bash, Grep, Glob | QA |
| tech-writer | sonnet | Read, Grep, Edit, Write, Glob | Doc update, PR content |

Models default to agent frontmatter values, overridable via `models` section in `n1.config.json`.

**Trusted web research (always on).** `solution-architect` and `planner` carry `WebSearch, WebFetch` to research industry standards and best practices during analysis, planning, and plan-review. Research is constrained by the shared rubric in `agents/research-standards.md`: trusted source tiers, a marketing reject-list, ≥2-source corroboration, mandatory URL citation, a standards-over-soft-practices fitness gate (guards against over-engineering), and graceful degradation when the network is unavailable. Library API docs still go through Context7, not web search.

### Session Start Hook

`hooks/session-start.sh` fires on session start/resume/clear/compact. It checks for `.n1/n1.config.json` in the working directory and injects context telling Claude to prefer N1 skills. When a tracker is configured, it also injects a **TRACKER ROUTING** directive containing the tracker type, MCP server name, full operations map, and a negative instruction to never use any other MCP server. This keeps the correct MCP server name in the model's attention window throughout the session. After running `n1-init`, the user must `/clear` or restart to pick up the new config.

### Escalation Model

Fixed checkpoints: after PR creation (Tech Lead reviews). Plan checkpoint is off by default (`requirePlanApproval: false`) — the plan-review CCR step validates the plan automatically. Enable `requirePlanApproval: true` to restore the manual plan checkpoint.
Confidence-based: low confidence + high blast radius = stop and ask.
Always escalate: security, architecture, public API changes.

## Git

- Default branch: `main`
- Commit style: imperative mood, English
- **Working branch lifecycle:** `n1-start` creates the working branch eagerly in Step 1, the moment the `<ID>` is resolved (ticket ID, newly created ticket, or slug), via the idempotent "Ensure Working Branch" procedure. This guarantees implementation/QA/review commits never land on the default branch. `n1-pr` performs the single `git push -u origin <branch>` at PR time.
