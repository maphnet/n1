# N1 (No-One)

AI-driven development orchestrator for Claude Code. No one writes the code.

N1 orchestrates the full development cycle using 8 specialized agent personas and [Superpowers](https://github.com/obra/superpowers) sub-skills. Agents handle autonomous work (analysis, QA, review, fixes, PR content); Superpowers handles interactive steps (brainstorming, planning, implementation dispatch). Adds tracker integration, per-ticket memory, adaptive workflow routing, confidence-based escalation, parallel security review, and a mandatory review loop.

## Requirements

- [Claude Code](https://claude.ai/code) 2.1+
- [Superpowers](https://github.com/obra/superpowers) plugin ^5.0
- `git` and `gh` (GitHub CLI) on PATH
- Optional: Jira (Atlassian MCP) or YouTrack MCP for tracker integration

## Installation

Install from the Claude Code marketplace:

```
/install-plugin n1
```

Or load locally for development:

```bash
claude --plugin-dir /path/to/n1
```

## Quick Start

```
# 1. Set up N1 for your project
/n1:n1-init

# 2. Start working on a task
/n1:n1-start TRID-510              # from a tracker ticket
/n1:n1-start add CSV export users  # from a brain dump

# 3. Or use skills standalone
/n1:n1-review                      # review current branch (fix loop)
/n1:n1-review #340                 # advisory review of a PR
/n1:n1-pr                          # create a pull request
```

## Skills

### `/n1:n1-start` — Core Orchestrator

Single entry point for all task work. Full pipeline:

```
Input (ticket or brain dump)
  → Ticket read (product-analyst agent)
  → Codebase analysis (solution-architect agent)
  → Brainstorm (superpowers:brainstorming, with architect's analysis)
  → Plan (planner agent → superpowers:writing-plans) — if complex
  → Implement (superpowers:SDD + developer persona)
  → QA (qa-engineer agent)
  → Review (code-reviewer + security-reviewer agents, parallel)
  → Fix loop (developer agent, if needed)
  → PR (n1:n1-pr → tech-writer agent)
  → Tracker update
```

- **Agent personas:** 8 specialized agents with scoped tools and configurable models
- **Parallel security review:** code-reviewer and security-reviewer run simultaneously
- **Adaptive routing:** simple tasks skip the plan step
- **Resume support:** interrupt anytime, `/n1:n1-start TRID-510` picks up where you left off
- **Confidence-based escalation:** low confidence + high blast radius = stop and ask

### `/n1:n1-review` — Code Review

Two modes:

| Mode | Trigger | Behavior |
|------|---------|----------|
| Review Loop | No args, on feature branch | code-reviewer + security-reviewer (parallel) → developer fixes → repeat until clean |
| Advisory | `/n1:n1-review #340` | code-reviewer report only, no fixes |

### `/n1:n1-pr` — Pull Request Creation

Spawns tech-writer agent for PR content, pushes, creates PR via `gh`, and updates the tracker (status + comment with PR link).

### `/n1:n1-init` — Project Setup

Interactive wizard:

1. Analyzes your repo (stack, docker, test runner, linter)
2. Enriches CLAUDE.md with detected conventions
3. Configures tracker (Jira / YouTrack / None)
4. Sets up git defaults and review policy
5. Configures agent models (defaults or custom per-agent)
6. Creates `.n1/` directory (fully gitignored)

## Tracker Support

| Tracker | MCP Server | Status |
|---------|------------|--------|
| Jira | `plugin_atlassian_atlassian` | Supported |
| YouTrack | `youtrack` | Supported |
| None | — | Works without tracker |

Tracker routing is config-driven via `.n1/n1.config.json` — all MCP tool names are mapped through operations presets populated by `n1-init`.

Created tickets can optionally be tagged with a service name. When `ticketTagging.enabled` is set (off by default; configured by `n1-init`), N1-created tickets get a `{service} | <title>` summary prefix and a `**Service:** <service>` line in the description.

## How It Works

N1 is a **lightweight controller** (~5-10K tokens) that uses a hybrid delegation model: 8 specialized agent personas handle autonomous work (analysis, QA, review, fixes, PR content), while Superpowers sub-skills handle interactive steps (brainstorming, planning, implementation dispatch via SDD). Each agent gets fresh context with scoped tools.

### Agent Personas

| Agent | Default Model | Role |
|-------|---------------|------|
| product-analyst | sonnet | Ticket distillation and requirements extraction |
| solution-architect | opus | Codebase analysis and architecture assessment |
| planner | opus | Isolated implementation-plan writing |
| developer | opus | Implementation and review fix cycles |
| code-reviewer | opus | Adversarial code quality review |
| security-reviewer | opus | Security vulnerability review (OWASP, CWE) |
| qa-engineer | sonnet | Test design and implementation |
| tech-writer | sonnet | PR content generation |

Models are configurable per-project via `models` section in `.n1/n1.config.json`.

### Per-Ticket Memory

Per-ticket memory lives in `.n1/memory/<ticket-id>/` with semantic-named files and an explicit dependency map:

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

The `.n1/` directory is fully gitignored — tool state never gets committed to your project.

## Escalation Model

**Fixed checkpoints (always):**
- After plan — Tech Lead approves
- After PR creation — Tech Lead reviews

**Confidence-based (during implementation):**
- Low confidence + High blast radius → stop and ask
- Low confidence + Low blast radius → proceed, note decision
- High confidence → full autonomy

**Always escalates for:** security changes, new architecture patterns, public API changes.

## License

MIT
