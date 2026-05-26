# N1 (No-One)

AI-driven development orchestrator for Claude Code. No one writes the code.

N1 is an orchestration layer over [Superpowers](https://github.com/obra/superpowers) that adds tracker integration, per-ticket memory, adaptive workflow routing, confidence-based escalation, and a mandatory review loop.

## Requirements

- [Claude Code](https://claude.ai/code) 2.1+
- [Superpowers](https://github.com/obra/superpowers) plugin ^4.0
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
  → Ticket read (via MCP)
  → Brainstorm (superpowers:brainstorming)
  → Plan (superpowers:writing-plans) — if complex
  → Implement (superpowers:subagent-driven-development)
  → Review loop (n1:n1-review)
  → PR (n1:n1-pr)
  → Tracker update
```

- **Adaptive routing:** simple tasks skip the plan step
- **Resume support:** interrupt anytime, `/n1:n1-start TRID-510` picks up where you left off
- **Confidence-based escalation:** low confidence + high blast radius = stop and ask

### `/n1:n1-review` — Code Review

Two modes:

| Mode | Trigger | Behavior |
|------|---------|----------|
| Review Loop | No args, on feature branch | request → fix → repeat until clean |
| Advisory | `/n1:n1-review #340` | report only, no fixes |

### `/n1:n1-pr` — Pull Request Creation

Collects diff, generates PR title/body, pushes, creates PR via `gh`, and updates the tracker (status + comment with PR link).

### `/n1:n1-init` — Project Setup

Interactive wizard:

1. Analyzes your repo (stack, docker, test runner, linter)
2. Enriches CLAUDE.md with detected conventions
3. Configures tracker (Jira / YouTrack / None)
4. Sets up git defaults and review policy
5. Creates `.n1/` directory (fully gitignored)

## Tracker Support

| Tracker | MCP Server | Status |
|---------|------------|--------|
| Jira | `plugin_atlassian_atlassian` | Supported |
| YouTrack | `youtrack` | Supported |
| None | — | Works without tracker |

Tracker routing is config-driven via `.n1/n1.config.json` — all MCP tool names are mapped through operations presets populated by `n1-init`.

## How It Works

N1 is a **lightweight controller** (~5-10K tokens) that delegates all heavy work to Superpowers skills. Each step gets fresh context via subagents.

Per-ticket memory lives in `.n1/memory/<ticket-id>/` with semantic-named files and an explicit dependency map:

| Step | Reads | Writes |
|------|-------|--------|
| ticket | — | `ticket.md` |
| brainstorm | `ticket.md` | `brainstorm.md` |
| plan | `ticket.md`, `brainstorm.md` | `plan.md` |
| implementation | `brainstorm.md`, `plan.md` | `implementation.md` |
| review | `ticket.md`, `brainstorm.md`, `implementation.md` | `review.md` |
| pr | `overview.md`, `review.md` | — |

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
