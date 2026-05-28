# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

See [README.md](README.md) for user-facing documentation: installation, quick start, skill usage examples, and full feature overview.

## Language Policy

ALL code, documentation, skills, agents, hooks, comments, and commit messages MUST be in English.
Russian is prohibited in any committed file.

## What This Is

N1 is a Claude Code plugin that orchestrates the full development cycle (ticket read, analysis, brainstorm, plan, implement, QA, review, PR) using 7 specialized agent personas with scoped tools and configurable models. It delegates interactive work to [Superpowers](https://github.com/obra/superpowers) ^4.0 sub-skills and autonomous work to its own agents. It is a **thin controller** (~5-10K tokens per skill): skills load only the memory files they need, spawn agents or delegate to Superpowers, and write results back to per-ticket memory.

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
- Agents: `agents/<name>.md` — frontmatter requires `name`, `description`, `model`; optional `tools` for tool scoping
- Hooks: `hooks/hooks.json` — event declarations, scripts in `hooks/`
- One concern per file
- Skills invoke each other via `**REQUIRED SUB-SKILL:** Use plugin:skill-name` directives
- No Co-Authored-By trailers in commits

## Architecture

### Orchestration Pattern

Skills are lightweight controllers that delegate all heavy work:

| N1 Skill | Delegates To | Purpose |
|----------|-------------|---------|
| n1-start | product-analyst, solution-architect, qa-engineer agents + superpowers (brainstorming, writing-plans, SDD) | Full pipeline |
| n1-review | code-reviewer, security-reviewer, developer agents | Review + fix loop |
| n1-pr | tech-writer agent + inline git/gh/MCP | Push, create PR, update tracker |
| n1-init | (inline: analysis + prompts) | Project setup wizard |

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
| implementation | `brainstorm.md`, `plan.md` | `implementation.md` |
| qa | `ticket.md`, `implementation.md`, `plan.md` | `qa.md` |
| review | `ticket.md`, `brainstorm.md`, `implementation.md`, `qa.md` | `review.md` |
| pr | `overview.md`, `review.md`, `qa.md` | — |

### Tracker Routing

Tracker MCP tool names are never hardcoded — they're resolved at runtime from `n1.config.json` operations map. Two presets exist:

| Tracker | mcp value | Key operations |
|---------|-----------|---------------|
| Jira | `plugin_atlassian_atlassian` | `getJiraIssue`, `transitionJiraIssue`, `addCommentToJiraIssue`, `getTransitionsForJiraIssue` |
| YouTrack | `youtrack` | `get_issue`, `update_issue`, `add_issue_comment`, `get_issue_comments` |

### Agent Personas

7 atomic agents with scoped tools and configurable models:

| Agent | Default Model | Tools | Pipeline Stage |
|-------|---------------|-------|----------------|
| product-analyst | opus | Read, Tracker MCP | Ticket read |
| solution-architect | opus | Read, Grep, Glob | Analysis |
| developer | opus | Read, Edit, Write, Bash, Grep, Glob | Implementation, Fix cycle |
| code-reviewer | opus | Read, Grep, Glob | Review (parallel) |
| security-reviewer | opus | Read, Grep, Glob | Review (parallel) |
| qa-engineer | sonnet | Read, Edit, Write, Bash, Grep, Glob | QA |
| tech-writer | sonnet | Read, Grep | PR content |

Models default to agent frontmatter values, overridable via `models` section in `n1.config.json`.

### Session Start Hook

`hooks/session-start.sh` fires on session start/resume/clear/compact. It checks for `.n1/n1.config.json` in the working directory and injects context telling Claude to prefer N1 skills.

### Escalation Model

Fixed checkpoints: after plan (Tech Lead approves) and after PR creation (Tech Lead reviews).
Confidence-based: low confidence + high blast radius = stop and ask.
Always escalate: security, architecture, public API changes.

## Git

- Default branch: `main`
- Commit style: imperative mood, English
