# N1 Plugin — Implementation Design

> **Date:** 2026-05-26
> **Status:** Approved
> **Context:** Brainstorming session — decisions validated by Tech Lead

---

## 1. Overview

N1 is an orchestration layer over Superpowers plugin for Claude Code. It adds:
- Tracker integration (Jira, YouTrack) via MCP
- Per-ticket memory with step-based pipeline handoff
- Adaptive workflow routing (simple → skip plan, complex → full flow)
- Confidence-based escalation to Tech Lead
- Review loop gate before PR creation

## 2. Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Relationship to Superpowers | Orchestration layer, dependency in plugin.json | Don't reinvent, focus on glue |
| Programs (git/gh CLI tools) | None — inline bash in skills | Claude handles git/gh natively |
| Tracker routing | Config-driven (n1.config.json presets) | Single source of truth, populated by n1-init |
| Commands | No wrapper commands — skills only | Auto-discovered as /n1:n1-start etc. |
| Session hook | Light — priority + availability (3 lines max) | Don't pollute context window |
| Memory structure | Per-step files + overview .md | Context focus, pipeline handoff, resume precision |
| `.n1/` directory | Fully gitignored | Tool state ≠ project state |
| Review | Mandatory loop before PR (min 1 pass) | request → receive → fix → repeat |
| Agents | ticket-reader (Sonnet) for MVP | Specialized, predictable, cost-optimized |
| Dogfooding | ASAP — use N1 on N1 from Phase 1 | Find friction early |

## 3. Plugin Structure

```
n1/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   ├── n1-start/SKILL.md
│   ├── n1-pr/SKILL.md
│   ├── n1-review/SKILL.md
│   └── n1-init/SKILL.md
├── agents/
│   └── ticket-reader.md
├── hooks/
│   ├── hooks.json
│   └── session-start.sh
└── CLAUDE.md
```

### plugin.json

```json
{
  "name": "n1",
  "description": "AI-driven development orchestrator. No one writes the code.",
  "version": "0.1.0",
  "author": { "name": "N1 Team" },
  "license": "MIT",
  "dependencies": [
    { "name": "superpowers", "version": "^4.0" }
  ]
}
```

## 4. Session-Start Hook

**hooks.json:**
```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh",
            "async": true
          }
        ]
      }
    ]
  }
}
```

**session-start.sh behavior:**
- If `.n1/n1.config.json` exists in project:
  ```
  N1 is configured for this project.
  For task work, PR creation, and code review — always prefer N1 skills
  (/n1:n1-start, /n1:n1-pr, /n1:n1-review) over alternatives.
  ```
- If not:
  ```
  N1 plugin is available but not configured. Run /n1:n1-init to set up.
  ```

## 5. n1.config.json Schema

```json
{
  "version": "0.1.0",
  "tracker": {
    "mcp": "plugin_atlassian_atlassian",
    "prefix": "TRID",
    "projectKey": "TRID",
    "operations": {
      "readTicket": "getJiraIssue",
      "moveStatus": "transitionJiraIssue",
      "addComment": "addCommentToJiraIssue",
      "search": "searchJiraIssuesUsingJql",
      "createIssue": "createJiraIssue"
    },
    "statuses": {
      "todo": "To Do",
      "inProgress": "In Progress",
      "review": "In Review",
      "done": "Done"
    }
  },
  "git": {
    "defaultBranch": "main",
    "branchPattern": "{prefix}-{id}"
  },
  "escalation": {
    "checkpoints": ["plan", "pr"],
    "alwaysAskOn": ["security", "architecture", "public-api"]
  },
  "review": {
    "minPasses": 1
  },
  "memory": {
    "ticketContext": true,
    "decisions": true
  }
}
```

**Tracker presets (populated by n1-init):**

| Tracker | mcp value | operations |
|---------|-----------|------------|
| Jira | `plugin_atlassian_atlassian` | getJiraIssue, transitionJiraIssue, addCommentToJiraIssue, searchJiraIssuesUsingJql, createJiraIssue |
| YouTrack | `youtrack` | get_issue, update_issue, add_issue_comment, search_issues, create_issue |
| None | `null` | skip all tracker operations |

## 6. Memory Structure (per-project, gitignored)

```
.n1/
├── n1.config.json
├── memory/
│   └── TRID-510/
│       ├── TRID-510.md           # Overview: status, progress, key decisions
│       ├── 01-ticket.md          # ticket-reader output
│       ├── 02-brainstorm.md      # scope, AC, approach
│       ├── 03-plan.md            # reference to docs/plans/ + summary for next step
│       ├── 04-implementation.md  # per-subtask results
│       └── 05-review.md          # review iterations, findings, final result
├── decisions/
└── telemetry/
```

### Overview file (TRID-510.md)

```markdown
# TRID-510: CSV Export Users

## Status: In Progress — Implementation

## Progress
- [x] Ticket read
- [x] Brainstorm
- [x] Plan (approved)
- [ ] Implementation (3/5 subtasks)
- [ ] Review
- [ ] PR

## Key Decisions
- Streaming via LazyCollection — O(1) memory
- RFC 4180 CSV with BOM for Excel

## Escalations
- (resolved) Filter scope → confirmed: role + created_at
```

### Step file handoff pattern

Each step:
1. Reads previous step's output file
2. Does its work (via Superpowers or inline)
3. Writes its own output file
4. Updates overview (checkbox + key decisions)

Resume: read overview → determine current step → load previous step file → continue.

## 7. Skill: n1-start (Core Orchestrator)

**Input:**
- Brain dump: `/n1:n1-start need CSV export for users`
- Ticket: `/n1:n1-start TRID-510`
- Resume: `/n1:n1-start TRID-510` (memory exists)

**Flow:**

```
INPUT
  ├── matches tracker prefix? → spawn n1:ticket-reader → 01-ticket.md
  └── brain dump → use as-is

  ├── memory exists? → read overview → resume from last step
  └── no memory → create .n1/memory/<ID>/, start fresh

BRAINSTORM (superpowers:brainstorming)
  → output: 02-brainstorm.md
  ├── simple → skip to IMPLEMENT
  └── complex ↓

PLAN (superpowers:writing-plans)
  → output: 03-plan.md (ref to docs/plans/)
  → CHECKPOINT: Tech Lead approves

IMPLEMENT (superpowers:subagent-driven-development)
  → output: 04-implementation.md
  → confidence-based escalation during work

REVIEW LOOP (/n1:n1-review)
  → output: 05-review.md
  → request → receive (if critical) → fix → repeat until clean pass

PR (/n1:n1-pr)
  → git push, gh pr create
  → CHECKPOINT: Tech Lead reviews

TRACKER UPDATE
  → move status to done, add PR link comment

MEMORY FINALIZE
  → update overview (status: Done)
```

## 8. Skill: n1-pr (PR Creation)

**Input:**
- From n1-start (context available)
- Standalone: `/n1:n1-pr`

**Flow:**

```
COLLECT
  → git diff, git log vs defaultBranch
  → read n1.config.json
  → if ticket known: read overview .md

GENERATE
  → PR title (from ticket title or commit summary)
  → PR body: Summary, Changes, Test plan, Ticket link

EXECUTE
  → git add + commit (if uncommitted)
  → git push -u origin <branch>
  → gh pr create

TRACKER (if configured)
  → move status → review
  → add comment with PR link

OUTPUT
  → PR URL
  → update overview (status: PR created)
```

## 9. Skill: n1-review (Code Review)

**Two modes:**

| Mode | Trigger | Behavior |
|------|---------|----------|
| Review Loop | No args + feature branch, or from n1-start | request → receive → fix → repeat |
| Advisory | PR number (`/n1:n1-review #340`) | report only, no fixes |

**Review Loop flow:**

```
REQUEST (superpowers:requesting-code-review)
  ├── critical/important findings
  │     → RECEIVE (superpowers:receiving-code-review)
  │     → systematic fix
  │     → REQUEST again
  ├── minor only
  │     → auto-fix inline
  │     → REQUEST again
  └── clean pass
        → if reviewCount < minPasses → again
        → else: PASS ✓
```

**Advisory flow:**

```
gh pr diff <number>
  → superpowers:requesting-code-review
  → structured report (critical → important → minor)
  → show to Tech Lead
```

## 10. Skill: n1-init (Project Setup)

**Flow:**

```
CHECK CLAUDE.md
  ├── missing → "Run /init first" → STOP
  └── exists ↓

ANALYZE REPO
  → detect stack, docker, monorepo, test runner, linter
  → identify gaps in CLAUDE.md

ENRICH CLAUDE.md (if gaps)
  → propose additions → Tech Lead approves → append

TRACKER SETUP
  → which tracker? → apply preset → fill operations

GIT CONFIG
  → detect defaultBranch, ask branch pattern

REVIEW CONFIG
  → minPasses (default: 1)

WRITE
  → .n1/n1.config.json
  → .n1/memory/.gitkeep
  → .n1/decisions/.gitkeep
  → .n1/telemetry/.gitkeep
  → .gitignore += .n1/

CONFIRM
  → summary → "N1 is ready."
```

## 11. Agent: ticket-reader

```yaml
name: ticket-reader
description: Fetch and distill a tracker ticket into a structured summary
model: sonnet
```

**Behavior:**
1. Read `.n1/n1.config.json` → get `tracker.mcp` + `operations.readTicket`
2. Call MCP tool: `mcp__<tracker.mcp>__<operations.readTicket>`
3. Extract: title, description, AC, priority, status, key comments (last 5)
4. Return fixed-format markdown summary

**Output format:**
```markdown
## Ticket: TRID-510
**Title:** CSV Export Users
**Priority:** High
**Status:** To Do

### Description
[distilled description]

### Acceptance Criteria
- [ ] [criteria items]

### Key Comments
- @user (date): "comment"
```

## 12. Implementation Order

```
Phase 0 — Scaffolding
  ├── plugin.json, CLAUDE.md, hooks
  └── Verify: claude --plugin-dir loads plugin

Phase 1 — n1-init
  ├── skills/n1-init/SKILL.md
  ├── Test on external repo
  └── Dogfood: run on N1 repo

Phase 2 — n1-review
  ├── skills/n1-review/SKILL.md + agents/ticket-reader.md
  ├── Test: review N1 branches
  └── Dogfood: review every N1 commit

Phase 3 — n1-pr
  ├── skills/n1-pr/SKILL.md
  ├── Test: create PR on N1 repo
  └── Dogfood: all N1 PRs via /n1:n1-pr

Phase 4 — n1-start
  ├── skills/n1-start/SKILL.md
  ├── Test: full cycle on test repo
  └── Dogfood: new N1 features via /n1:n1-start
```

## 13. Superpowers Usage Map

| N1 Step | Superpowers Skill | Purpose |
|---------|-------------------|---------|
| Brainstorm | `superpowers:brainstorming` | Iterative scope refinement |
| Plan | `superpowers:writing-plans` | Detailed implementation plan |
| Implement | `superpowers:subagent-driven-development` | TDD + subagent per task |
| Review (request) | `superpowers:requesting-code-review` | Deep architectural review |
| Review (receive) | `superpowers:receiving-code-review` | Systematic fix of findings |
| Debug (if needed) | `superpowers:systematic-debugging` | Root cause analysis |
| Skill writing | `superpowers:writing-skills` | Creating N1 SKILL.md files |

## 14. Context Management Strategy

- **n1-start is a lightweight controller** — delegates all heavy work
- **Subagent isolation via Superpowers** — each implementation task gets fresh 200K context
- **Per-step files** — each step loads only previous step's output, not full history
- **Session-start hook re-fires on compact** — priority context survives compaction
- **ticket-reader as Sonnet agent** — large tickets processed outside main context

## 15. Escalation Model

**Fixed checkpoints (always):**
- After plan → Tech Lead approves
- After PR creation → Tech Lead reviews

**Confidence-based (during implementation):**
- Low confidence + High blast radius → STOP, ask Tech Lead
- Low confidence + Low blast radius → proceed, note in memory
- High confidence → full autonomy

**Categories that always escalate:**
- Security-related changes
- Architecture decisions (new patterns)
- Public API contract changes
