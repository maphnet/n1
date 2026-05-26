# N1 (No-One) — Claude Code Plugin

## Language Policy

ALL code, documentation, skills, agents, hooks, comments, and commit messages MUST be in English.
Russian is prohibited in any committed file.

## Stack

- **Platform:** Claude Code Plugin (marketplace distribution)
- **Runtime:** Bash (hooks), Markdown (skills, agents)
- **Dependency:** Superpowers plugin ^4.0 (declared in plugin.json)
- **No npm dependencies, no Node.js programs**

## Project Structure

```
n1/
├── .claude-plugin/
│   └── plugin.json             # Plugin manifest
├── skills/
│   ├── n1-start/SKILL.md      # Core orchestrator
│   ├── n1-pr/SKILL.md         # PR creation
│   ├── n1-review/SKILL.md     # Code review (loop + advisory)
│   └── n1-init/SKILL.md       # Project setup wizard
├── agents/
│   └── ticket-reader.md       # Sonnet — ticket fetch + distill
├── hooks/
│   ├── hooks.json              # Hook declarations
│   └── session-start.sh       # Light context injection
├── docs/
│   └── plans/                  # Design documents
└── CLAUDE.md                   # This file
```

## Testing

- **Local:** `claude --plugin-dir C:\Dev\n1` from any test project
- **Reload:** `/reload-plugins` after skill changes (no restart needed)
- **Always test on a separate repo before committing**
- **Dogfooding:** use N1 skills on N1 repo as soon as they're functional

## Conventions

- Skills: `skills/<name>/SKILL.md` — auto-discovered by Claude Code
- Agents: `agents/<name>.md` — frontmatter with name, description, model
- Hooks: `hooks/hooks.json` — event declarations
- One concern per file
- Frontmatter: `name` + `description` required for all skills/agents
- No wrapper commands — skills are accessed as `/n1:<skill-name>`

## Architecture Principles

- **Orchestration over reimplementation** — use Superpowers for heavy lifting
- **Specialized agents** — each agent does limited scope well and predictably
- **Model optimization** — Sonnet for mechanical tasks, Opus for judgment
- **Per-step memory files** — pipeline handoff pattern between workflow steps
- **`.n1/` is ephemeral** — tool state never committed to project repos
- **Tracker routing via config** — `n1.config.json` holds MCP tool mappings

## Git

- Default branch: main
- Commit messages: imperative mood, English
- No Co-Authored-By trailers
