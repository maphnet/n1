# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

See [README.md](README.md) for user-facing documentation: installation, quick start, skill usage examples, and full feature overview.

## Language Policy

ALL code, documentation, skills, agents, hooks, comments, and commit messages MUST be in English.
Russian is prohibited in any committed file.

## What This Is

N1 is a Claude Code plugin that orchestrates the full development cycle (ticket read, brainstorm, plan, implement, review, PR) by delegating to [Superpowers](https://github.com/obra/superpowers) ^4.0 sub-skills. It is a **thin controller** (~5-10K tokens per skill): skills load only the memory files they need, delegate heavy work to Superpowers via subagents, and write results back to per-ticket memory.

## Stack

- **Runtime:** Bash (hooks), Markdown (skills, agents) — no npm, no Node.js
- **Plugin manifest:** `.claude-plugin/plugin.json`
- **Dependency:** Superpowers plugin ^4.0

## Testing

- **Local dev:** `claude --plugin-dir C:\Dev\n1` from any test project
- **Reload skills:** `/reload-plugins` (no restart needed)
- **Always test on a separate repo before committing**
- **Dogfooding:** use N1 skills on the N1 repo itself

## Conventions

- Skills: `skills/<name>/SKILL.md` — auto-discovered, invoked as `/n1:<skill-name>`
- Agents: `agents/<name>.md` — frontmatter requires `name`, `description`, `model`
- Hooks: `hooks/hooks.json` — event declarations, scripts in `hooks/`
- One concern per file
- Skills invoke each other via `**REQUIRED SUB-SKILL:** Use plugin:skill-name` directives
- No Co-Authored-By trailers in commits

## Architecture

### Orchestration Pattern

Skills are lightweight controllers that delegate all heavy work:

| N1 Skill | Delegates To | Purpose |
|----------|-------------|---------|
| n1-start | brainstorming, writing-plans, subagent-driven-development | Full pipeline |
| n1-review | requesting-code-review, receiving-code-review | Review + fix loop |
| n1-pr | (inline: git, gh, MCP) | Push, create PR, update tracker |
| n1-init | (inline: analysis + prompts) | Project setup wizard |

All Superpowers calls use the `superpowers:` prefix. Each subagent gets fresh context — the orchestrator never accumulates full history.

### Per-Ticket Memory (`.n1/`)

The `.n1/` directory is **ephemeral and gitignored**. It lives in target projects, not in this repo.

Each step reads ONLY its declared dependencies:

| Step | Reads | Writes |
|------|-------|--------|
| ticket | — | `ticket.md` |
| brainstorm | `ticket.md` | `brainstorm.md` |
| plan | `ticket.md`, `brainstorm.md` | `plan.md` |
| implementation | `brainstorm.md`, `plan.md` | `implementation.md` |
| review | `ticket.md`, `brainstorm.md`, `implementation.md` | `review.md` |
| pr | `overview.md`, `review.md` | — |

### Tracker Routing

Tracker MCP tool names are never hardcoded — they're resolved at runtime from `n1.config.json` operations map. Two presets exist:

| Tracker | mcp value | Key operations |
|---------|-----------|---------------|
| Jira | `plugin_atlassian_atlassian` | `getJiraIssue`, `transitionJiraIssue`, `addCommentToJiraIssue`, `getTransitionsForJiraIssue` |
| YouTrack | `youtrack` | `get_issue`, `update_issue`, `add_issue_comment`, `get_issue_comments` |

### Session Start Hook

`hooks/session-start.sh` fires on session start/resume/clear/compact. It checks for `.n1/n1.config.json` in the working directory and injects context telling Claude to prefer N1 skills.

### Escalation Model

Fixed checkpoints: after plan (Tech Lead approves) and after PR creation (Tech Lead reviews).
Confidence-based: low confidence + high blast radius = stop and ask.
Always escalate: security, architecture, public API changes.

## Git

- Default branch: `main`
- Commit style: imperative mood, English
