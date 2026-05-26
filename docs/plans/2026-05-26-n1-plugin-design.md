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
| Memory structure | Semantic-named files + overview .md + explicit dependency map | Context focus, pipeline handoff, non-linear flow support |
| `.n1/` directory | Fully gitignored | Tool state ≠ project state |
| Review | Mandatory loop before PR (min 1 pass) | request → receive → fix → repeat |
| Agents | ticket-reader inline for MVP, Sonnet agent for large tickets later | Avoid spawn overhead for typical tickets; extract when 10K+ tokens justified |
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
│   ├── session-start.cmd    # Polyglot wrapper (Windows + Unix)
│   └── session-start.sh     # Actual implementation
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
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.cmd\"",
            "async": true
          }
        ]
      }
    ]
  }
}
```

**Cross-platform execution:**

Claude Code on Windows cannot run `.sh` directly. Use a polyglot `.cmd` wrapper
(same pattern as Superpowers):

```
hooks/
├── hooks.json              # Points to .cmd wrapper
├── session-start.cmd       # Polyglot: Windows CMD + Unix passthrough
└── session-start.sh        # Actual logic (pure bash)
```

`session-start.cmd` dispatches to `session-start.sh` via Git Bash on Windows,
or runs it directly on Unix. Verified pattern from Superpowers 4.2.0.

**Hook output format (required by Claude Code):**

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "...injected into Claude context..."
  }
}
```

**Project root detection:**

`CLAUDE_PLUGIN_ROOT` points to the plugin directory, not the project.
Use `$PWD` to detect the project root — Claude Code runs hooks from the
project working directory. Verify empirically in Phase 0.

**session-start.sh behavior:**
- If `$PWD/.n1/n1.config.json` exists:
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
      "getTransitions": "getTransitionsForJiraIssue",
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
| Jira | `plugin_atlassian_atlassian` | getJiraIssue, getTransitionsForJiraIssue, transitionJiraIssue, addCommentToJiraIssue, searchJiraIssuesUsingJql, createJiraIssue |
| YouTrack | `youtrack` | get_issue, get_issue_comments, update_issue, add_issue_comment, search_issues, create_issue |
| None | `null` | skip all tracker operations |

## 6. Memory Structure (per-project, fully gitignored)

```
.n1/
├── n1.config.json
├── memory/
│   └── TRID-510/
│       ├── overview.md     # Status, progress, key decisions (structured frontmatter)
│       ├── ticket.md       # Ticket fetch output
│       ├── brainstorm.md   # Scope, AC, approach
│       ├── plan.md         # Reference to docs/plans/ + summary
│       ├── implementation.md  # Implementation results summary
│       └── review.md       # Latest review results
├── decisions/
└── telemetry/
```

`.n1/` is fully gitignored — tool state never committed to project repos.
ADRs that matter to the team belong in `docs/decisions/`, not in `.n1/`.

**File naming:** Semantic names without numeric prefixes. Optional steps simply don't
have a file. Additional steps (debug, extra review iterations) add files without
renumbering. Review iterations use `-r1`, `-r2` suffix.

### Overview file (overview.md)

```markdown
---
ticket: TRID-510
step: implementation
substep: 3
iteration: 1
last_updated: 2026-05-26T14:30:00
---

# TRID-510: CSV Export Users

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

### Step dependency map

Each step declares which files it reads (not just the previous step):

| Step | Reads | Writes |
|------|-------|--------|
| ticket | — | `ticket.md` |
| brainstorm | `ticket.md` | `brainstorm.md` |
| plan | `ticket.md`, `brainstorm.md` | `plan.md` |
| implementation | `brainstorm.md`, `plan.md` | `implementation.md` |
| review | `ticket.md`, `brainstorm.md`, `implementation.md` | `review.md` |
| pr | `overview.md`, `review.md` | — |

### Step file handoff pattern

Each step:
1. Reads files from its dependency list (see map above)
2. Does its work (via Superpowers or inline)
3. Writes its own output file
4. Updates overview (checkbox + key decisions + frontmatter)

Resume: read overview frontmatter → determine current step → load dependency files → continue.

## 7. Skill: n1-start (Core Orchestrator)

**Input:**
- Brain dump: `/n1:n1-start need CSV export for users`
- Ticket: `/n1:n1-start TRID-510`
- Resume: `/n1:n1-start TRID-510` (memory exists)

**Flow:**

```
INPUT
  ├── matches tracker prefix? → fetch ticket inline → ticket.md
  └── brain dump → use as-is

  ├── memory exists? → read overview frontmatter → resume from current step
  └── no memory → create .n1/memory/<ID>/, start fresh

BRAINSTORM (superpowers:brainstorming)
  → reads: ticket.md
  → output: brainstorm.md
  ├── simple → skip to IMPLEMENT
  └── complex ↓

PLAN (superpowers:writing-plans)
  → reads: ticket.md, brainstorm.md
  → output: plan.md (ref to docs/plans/)
  → CHECKPOINT: Tech Lead approves

IMPLEMENT (superpowers:subagent-driven-development)
  → reads: brainstorm.md, plan.md
  → output: implementation.md (per subtask)
  → confidence-based escalation during work

REVIEW LOOP (/n1:n1-review)
  → reads: ticket.md, brainstorm.md, implementation.md
  → output: review.md (overwritten each iteration)
  → request → receive (if critical) → fix → repeat until clean pass

PR (/n1:n1-pr)
  → git push, gh pr create
  → CHECKPOINT: Tech Lead reviews

TRACKER UPDATE
  → move status to done, add PR link comment

MEMORY FINALIZE
  → update overview (status: Done)
```

### Skill-to-skill invocation pattern

n1-start invokes Superpowers and N1 sub-skills via **declarative text instructions**
in SKILL.md body. Claude reads these instructions and calls the `Skill` tool
automatically. No programmatic API between skills.

Pattern (verified from Superpowers 4.2.0):
```markdown
**REQUIRED SUB-SKILL:** Use superpowers:brainstorming to refine the scope.
```

For N1 internal skills:
```markdown
**REQUIRED SUB-SKILL:** Use n1:n1-review to run the review loop.
**REQUIRED SUB-SKILL:** Use n1:n1-pr to create the pull request.
```

Claude resolves `n1:n1-review` → Skill tool call → loads SKILL.md → follows it.
This is the same mechanism Superpowers uses for chaining (e.g., brainstorming →
writing-plans → executing-plans → finishing-a-development-branch).

## 8. Skill: n1-pr (PR Creation)

**Input:**
- From n1-start (context available)
- Standalone: `/n1:n1-pr`

**Flow:**

```
COLLECT
  → git diff, git log vs defaultBranch
  → read n1.config.json
  → if ticket known: read overview.md

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

## 11. Ticket Reading

### MVP: Inline in orchestrator

For MVP, ticket reading is performed inline by the n1-start orchestrator (Opus).
Typical tickets are 2-5K tokens — the spawn overhead of a separate agent is not
justified at this scale.

**Behavior:**
1. Read `.n1/n1.config.json` → get `tracker.mcp` + `operations.readTicket`
2. Call MCP tool: `mcp__<tracker.mcp>__<operations.readTicket>`
3. For YouTrack: also call `mcp__<tracker.mcp>__<operations.readComments>` (comments are separate)
4. For Jira: also call `mcp__<tracker.mcp>__<operations.getTransitions>` (cache available transitions)
5. Extract: title, description, AC, priority, status, key comments (last 5)
6. Write `ticket.md` in fixed-format markdown

**Output format (ticket.md):**
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

### Future: Sonnet agent for large tickets

Extract ticket reading into a dedicated Sonnet agent when:
- Tickets consistently exceed 10K tokens of raw content (50+ comments, attached docs)
- Context pressure from ticket reading measurably impacts orchestrator performance

```yaml
name: ticket-reader
description: Fetch and distill a tracker ticket into a structured summary
model: sonnet
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
  ├── skills/n1-review/SKILL.md
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

- **n1-start is a lightweight controller** (~5-10K tokens working context) — delegates all heavy work
- **Subagent isolation via Superpowers** — each implementation task gets fresh 200K context
- **Explicit dependency map** — each step loads only the files it needs (see §6 dependency map), not full history
- **Active handoff between steps** — after each major step, save output to file and summarize key decisions before invoking next skill; don't let context accumulate passively
- **Session-start hook re-fires on compact** — priority context survives compaction (verify empirically in Phase 0)
- **Ticket reading inline for MVP** — avoids agent spawn overhead; extract to Sonnet agent only when tickets consistently exceed 10K tokens

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
