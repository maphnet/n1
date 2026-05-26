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
- **Specialized agents** — Sonnet for mechanical tasks (ticket reading), Opus for judgment
- **Inline fallback** — orchestrator can do ticket reading inline for simple cases
- **Semantic memory files** — explicit dependency map between workflow steps, no numeric prefixes
- **`.n1/` is ephemeral** — fully gitignored, tool state never committed to project repos
- **Tracker routing via config** — `n1.config.json` holds MCP tool mappings

## Skills and Invocation

Skills invoke each other via declarative text instructions in SKILL.md body:
```
**REQUIRED SUB-SKILL:** Use superpowers:brainstorming to refine the scope.
**REQUIRED SUB-SKILL:** Use n1:n1-review to run the review loop.
```
Claude resolves `plugin:skill-name` → Skill tool call → loads SKILL.md → follows it.

### Superpowers Usage Map

| N1 Step | Superpowers Skill | Purpose |
|---------|-------------------|---------|
| Brainstorm | `superpowers:brainstorming` | Iterative scope refinement |
| Plan | `superpowers:writing-plans` | Detailed implementation plan |
| Implement | `superpowers:subagent-driven-development` | TDD + subagent per task |
| Review (request) | `superpowers:requesting-code-review` | Deep architectural review |
| Review (receive) | `superpowers:receiving-code-review` | Systematic fix of findings |
| Debug (if needed) | `superpowers:systematic-debugging` | Root cause analysis |

## Memory Structure (per-project, gitignored)

```
.n1/
├── n1.config.json          # Project configuration
├── memory/
│   └── <ticket-id>/
│       ├── overview.md     # Status, progress, key decisions (structured frontmatter)
│       ├── ticket.md       # Ticket fetch output or brain dump
│       ├── brainstorm.md   # Scope, AC, approach
│       ├── plan.md         # Reference to docs/plans/ + summary
│       ├── implementation.md  # Implementation results
│       └── review.md       # Latest review results
├── decisions/              # ADRs (future)
└── telemetry/              # Execution logs (future)
```

### Step Dependency Map

Each step reads ONLY its declared dependencies, not full history:

| Step | Reads | Writes |
|------|-------|--------|
| ticket | — | `ticket.md` |
| brainstorm | `ticket.md` | `brainstorm.md` |
| plan | `ticket.md`, `brainstorm.md` | `plan.md` |
| implementation | `brainstorm.md`, `plan.md` | `implementation.md` |
| review | `ticket.md`, `brainstorm.md`, `implementation.md` | `review.md` |
| pr | `overview.md`, `review.md` | — |

## n1.config.json Schema

```json
{
  "version": "0.1.0",
  "tracker": {
    "mcp": "plugin_atlassian_atlassian | youtrack | null",
    "prefix": "TRID",
    "projectKey": "TRID",
    "operations": { "readTicket": "...", "moveStatus": "...", "addComment": "...", "search": "...", "createIssue": "..." },
    "statuses": { "todo": "To Do", "inProgress": "In Progress", "review": "In Review", "done": "Done" }
  },
  "git": { "defaultBranch": "main", "branchPattern": "{prefix}-{id}" },
  "escalation": { "checkpoints": ["plan", "pr"], "alwaysAskOn": ["security", "architecture", "public-api"] },
  "review": { "minPasses": 1 },
  "memory": { "ticketContext": true, "decisions": true }
}
```

### Tracker Presets (populated by n1-init)

| Tracker | mcp | readTicket | moveStatus | addComment | getComments |
|---------|-----|------------|------------|------------|-------------|
| Jira | `plugin_atlassian_atlassian` | `getJiraIssue` | `transitionJiraIssue` | `addCommentToJiraIssue` | — (inline) |
| YouTrack | `youtrack` | `get_issue` | `update_issue` | `add_issue_comment` | `get_issue_comments` |

## Escalation Model

**Fixed checkpoints (always):**
- After plan → Tech Lead approves
- After PR creation → Tech Lead reviews

**Confidence-based (during implementation):**
- Low confidence + High blast radius → STOP, ask Tech Lead
- Low confidence + Low blast radius → proceed, note in memory
- High confidence → full autonomy

**Always escalate:** security, architecture decisions, public API changes.

## Git

- Default branch: main
- Commit messages: imperative mood, English
- No Co-Authored-By trailers
