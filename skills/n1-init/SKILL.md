---
name: n1-init
description: "Set up N1 for a project. Creates .n1/ directory, n1.config.json, and enriches CLAUDE.md with project conventions."
---

# N1 Project Setup

## Overview

Initialize N1 for the current project. This creates the `.n1/` directory structure, generates `n1.config.json` with tracker and git settings, and optionally enriches CLAUDE.md with detected project conventions.

**Announce at start:** "I'm using the n1-init skill to set up N1 for this project."

**UX rules:**
- Do NOT show step numbers to the user — they are internal structure only.
- All choice questions MUST offer numbered options (e.g., `1 — Yes / 2 — No`) so the user can answer with just a number.

## Prerequisites

Check if CLAUDE.md exists in the project root:
- **If missing:** Tell the user: "CLAUDE.md not found. Run `/init` first to create one, then re-run `/n1:n1-init`." **STOP.**
- **If exists:** Continue.

Check if `.n1/n1.config.json` already exists:
- **If exists:** Tell the user: "N1 is already configured for this project. Current config:" then show the config. Ask: "Reconfigure? **1** — Yes / **2** — No". If no — **STOP.**
- **If missing:** Continue with fresh setup.

## Analyze Repository

Explore the project to detect:

1. **Stack:** Look for `package.json`, `composer.json`, `Cargo.toml`, `go.mod`, `requirements.txt`, `pyproject.toml`, `Gemfile`, `pom.xml`, `build.gradle`, etc.
2. **Docker:** Check for `Dockerfile`, `docker-compose.yml`, `docker-compose.yaml`
3. **Monorepo:** Check for `lerna.json`, `pnpm-workspace.yaml`, `turbo.json`, or multiple `package.json` files
4. **Test runner:** Look in config files and scripts for test commands
5. **Linter/formatter:** Look for `.eslintrc*`, `.prettierrc*`, `phpcs.xml`, `rustfmt.toml`, `.flake8`, etc.
6. **CI/CD:** Check `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`, etc.

Read existing CLAUDE.md content to identify what's already documented.

## Enrich CLAUDE.md (if gaps found)

Compare what was detected vs. what's documented in CLAUDE.md.

If gaps exist, propose additions as a structured block. **Only add tool-agnostic information** — no N1-specific config in CLAUDE.md.

Present proposed additions to the user:
```
I found the following gaps in your CLAUDE.md:

## Proposed additions:

### Commands
docker compose exec app php artisan test
docker compose exec app ./vendor/bin/phpunit
npm run dev

### Project Structure
- app/Http/Controllers/ — HTTP controllers
- app/Services/ — Business logic
...

Add these to CLAUDE.md?
1 — Yes
2 — No
3 — Edit first
```

If approved (1), append to CLAUDE.md. If edit (3) — ask what to change first.

## Tracker Setup

Ask: **"Which issue tracker do you use?"**

```
1 — Jira (via Atlassian MCP)
2 — YouTrack (via YouTrack MCP)
3 — None (no tracker integration)
```

### If Jira:

**Verify MCP and get projects:**

Call `mcp__plugin_atlassian_atlassian__getVisibleJiraProjects` — this simultaneously checks connectivity and retrieves the project list.

- **Success** → MCP is connected. Proceed to project selection.
- **Failure (tool not found or error):**
  1. Tell the user: "The Atlassian MCP server is not connected or not configured."
  2. Ask: **"Would you like me to help set it up? 1 — Yes / 2 — Skip tracker"**
  3. If **1:** Guide the user through adding the Atlassian MCP server to their Claude Code MCP settings. **CRITICAL: NEVER store, save, log, or transmit API keys, tokens, or credentials anywhere — the user must enter them directly into their own MCP configuration only.** After setup, retry `getVisibleJiraProjects`. If still fails — report the error, set `tracker.mcp` to `null`, skip remaining tracker setup.
  4. If **2:** Set `tracker.mcp` to `null`, skip remaining tracker setup.

**Select project:**

Display the project list from `getVisibleJiraProjects` as numbered options:
```
Available Jira projects:
1 — TRID (Trident)
2 — PROJ (Project Alpha)
3 — BACK (Backend Services)
...
```

Ask: **"Which project should N1 use?"**

Set both `tracker.projectKey` and `tracker.prefix` from the selected project's key.

**Branch prefix:**

Ask: **"Use {KEY} as branch prefix? (e.g., branch name: {KEY}-123) 1 — Yes (default) / 2 — No"**

- If **1** (or enter/default): set `git.branchPattern` to `{prefix}-{id}`
- If **2**: set `git.branchPattern` to `{id}`

**Auto-detect workflow statuses:**

Detect statuses via MCP — do NOT ask the user to type status names:

1. Try calling `mcp__plugin_atlassian_atlassian__fetch` with the Jira REST endpoint `/rest/api/3/project/{projectKey}/statuses` to get all workflow statuses for the project.
2. If that fails or returns empty: find a sample issue via `mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql` (JQL: `project = {KEY} ORDER BY created DESC`, maxResults: 1), then call `mcp__plugin_atlassian_atlassian__getTransitionsForJiraIssue` on it to retrieve available transitions.

Auto-map detected statuses to N1 workflow slots by matching common names:
- **todo**: "To Do", "Open", "New", "Backlog", "Created"
- **inProgress**: "In Progress", "In Development", "Active", "In Work"
- **codeReview**: "Code Review" — if no exact match found, fall back to the `inProgress` value (N1 uses this after PR creation; the tracker's "Review"/"QA" columns are reserved for human QA outside the orchestrator)

Show the detected mapping for confirmation:
```
Detected workflow statuses:
  todo       → To Do
  inProgress → In Progress
  codeReview → Code Review (or In Progress if no Code Review status)

Correct? 1 — Yes / 2 — No, let me specify manually
```

- If **1**: use detected values.
- If **2** or auto-detection failed entirely: ask the user for the 3 status names (todo, inProgress, codeReview).

Set config:
```json
{
  "tracker": {
    "mcp": "plugin_atlassian_atlassian",
    "prefix": "<from project selection>",
    "projectKey": "<from project selection>",
    "assignToCreator": true,
    "operations": {
      "readTicket": "getJiraIssue",
      "getTransitions": "getTransitionsForJiraIssue",
      "moveStatus": "transitionJiraIssue",
      "addComment": "addCommentToJiraIssue",
      "search": "searchJiraIssuesUsingJql",
      "createIssue": "createJiraIssue",
      "getCurrentUser": "atlassianUserInfo",
      "assign": "editJiraIssue"
    },
    "statuses": {
      "todo": "<detected or manual>",
      "inProgress": "<detected or manual>",
      "codeReview": "<detected or inProgress fallback>"
    }
  }
}
```

### If YouTrack:

**Verify MCP and get projects:**

Call `mcp__youtrack__find_projects`.

- **Success** → MCP is connected. Proceed to project selection.
- **Failure:**
  1. Tell the user: "The YouTrack MCP server is not connected or not configured."
  2. Ask: **"Would you like me to help set it up? 1 — Yes / 2 — Skip tracker"**
  3. If **1:** Guide the user through adding the YouTrack MCP server. **CRITICAL: NEVER store, save, log, or transmit API keys, tokens, or credentials.** After setup, retry `find_projects`. If still fails — set `tracker.mcp` to `null`, skip tracker setup.
  4. If **2:** Set `tracker.mcp` to `null`, skip remaining tracker setup.

**Select project:**

Display projects from `find_projects` as numbered options. Ask: **"Which project should N1 use?"**

Set `tracker.projectKey` and `tracker.prefix` from the selected project's short name / ID.

**Branch prefix:**

Ask: **"Use {KEY} as branch prefix? (e.g., branch name: {KEY}-123) 1 — Yes (default) / 2 — No"**

Same config effect as Jira above.

**Auto-detect workflow statuses:**

Detect statuses via MCP — do NOT ask the user to type status names:

1. Try `mcp__youtrack__get_issue_fields_schema` — look for the State field and extract its bundle values (possible states).
2. If that doesn't return state values: search for a sample issue via `mcp__youtrack__search_issues` (query: `project: {shortName}`, limit: 1), then examine its State field to see available values.

Same auto-mapping and confirmation flow as Jira above.

Set config:
```json
{
  "tracker": {
    "mcp": "youtrack",
    "prefix": "<from project selection>",
    "projectKey": "<from project selection>",
    "assignToCreator": true,
    "operations": {
      "readTicket": "get_issue",
      "getComments": "get_issue_comments",
      "moveStatus": "update_issue",
      "addComment": "add_issue_comment",
      "search": "search_issues",
      "createIssue": "create_issue",
      "getCurrentUser": "get_current_user",
      "assign": "change_issue_assignee"
    },
    "statuses": {
      "todo": "<detected or manual>",
      "inProgress": "<detected or manual>",
      "codeReview": "<detected or inProgress fallback>"
    }
  }
}
```

### If None:

```json
{
  "tracker": {
    "mcp": null
  }
}
```

## Git Configuration

Detect **defaultBranch** automatically:
- Run `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'`
- Fall back to checking `main`/`master` branch existence

**branchPattern:**
- If a tracker was configured above → already set during Tracker Setup (branch prefix question)
- If no tracker (None) → default to `feature/{slug}`

```json
{
  "git": {
    "defaultBranch": "main",
    "branchPattern": "<from tracker setup or feature/{slug}>"
  }
}
```

## Ticket Tagging Configuration

Ask whether to tag N1-created tickets with a service (repo) name. **Default is No** — do not enable unless the user opts in.

```
Tag created tickets with a service name? (e.g. "payments-api | Add CSV export")
1 — Yes
2 — No (default)
```

**If 2 (No) or default:**
```json
{
  "ticketTagging": {
    "enabled": false
  }
}
```

**If 1 (Yes):**

Derive a default service name, then confirm it:
1. Run `git remote get-url origin 2>/dev/null`. If it succeeds, take the last path segment and strip a trailing `.git` (e.g. `git@github.com:org/payments-api.git` → `payments-api`, `https://github.com/org/payments-api` → `payments-api`).
2. If there is no `origin` remote, fall back to the current directory's base name.
3. Show and confirm:
   ```
   Detected service name: <detected>
   (from git remote origin)

   Use this? 1 — Yes / 2 — Enter a different name
   ```
   - **1** → use `<detected>`.
   - **2** → ask: "Service name:" and use the entered value (trimmed).

```json
{
  "ticketTagging": {
    "enabled": true,
    "service": "<confirmed name>"
  }
}
```

### On reconfiguration (n1-init re-run):

If `ticketTagging` already exists in the current config, show it and offer:
```
Current ticket tagging:
  enabled → <true/false>
  service → <value or "(none)">

1 — Keep current
2 — Update service name
3 — Disable tagging
```
- **1** → leave unchanged.
- **2** → run the derive+confirm flow above, set `enabled: true`.
- **3** → set `{ "enabled": false }`.

## Assign to Creator Configuration

Ask whether N1 should auto-assign tickets it creates to the user running it. **Default is Yes.**

```
Auto-assign tickets N1 creates to you? 1 — Yes (default) / 2 — No
```

- **1 (Yes) or default:**
```json
{ "tracker": { "assignToCreator": true } }
```
- **2 (No):**
```json
{ "tracker": { "assignToCreator": false } }
```

Store the value on the `tracker` block (alongside `mcp`/`operations`). Skip this question entirely when `tracker.mcp` is `null` (no tracker configured).

### On reconfiguration (n1-init re-run):

If `assignToCreator` already exists on the `tracker` block, show it and offer:
```
Auto-assign created tickets to you: <true/false>
1 — Keep current
2 — Toggle
```
- **1** → leave unchanged.
- **2** → flip the boolean.

## Review Configuration

Use `minCleanPasses: 1` by default. **Do NOT ask** the user about this unless they explicitly requested review customization when invoking n1-init.

```json
{
  "review": {
    "minCleanPasses": 1
  }
}
```

## CI Checks Configuration

Use defaults. **Do NOT ask** the user about this unless they explicitly requested CI customization when invoking n1-init.

- `enabled: true` — CI watch runs automatically after PR creation in n1-start
- `maxFixAttempts: 3` — developer agent gets 3 cycles to fix CI failures before escalating to user
- `confidenceThreshold: 0.7` — for checks that don't match any known category, developer agent must exceed this confidence to auto-fix

```json
{
  "ciChecks": {
    "enabled": true,
    "maxFixAttempts": 3,
    "confidenceThreshold": 0.7
  }
}
```

Categories use built-in defaults (lint, typecheck, test, build, security, infra — all `auto-fix`). Teams can override by adding a `categories` block after running n1-init.

## Plan Review Configuration

Use defaults. **Do NOT ask** the user about this unless they explicitly requested plan review customization when invoking n1-init.

- `reviewPlan: true` — after plan creation, solution-architect is re-spawned in fresh context to review the plan against specific adversarial criteria with codebase access
- `requirePlanApproval: false` — if the plan review passes (clean or self-fixed), proceed to implementation without a user checkpoint

```json
{
  "planReview": {
    "reviewPlan": true,
    "requirePlanApproval": false
  }
}
```

## Agent Model Configuration

Use default models from agent frontmatter. **Do NOT ask** about model customization unless the user explicitly requested it when invoking n1-init.

If the user did request customization, show the defaults table and accept per-agent overrides (valid values: opus, sonnet, haiku) — only store overrides that differ from the default.

Defaults:
```
product-analyst    sonnet
solution-architect opus
planner            opus
developer          opus
code-reviewer      opus
security-reviewer  opus
qa-engineer        sonnet
tech-writer        sonnet
```

## Write Configuration and Structure

Create all files:

**`.n1/n1.config.json`** — assembled from sections above:
```json
{
  "version": "0.2.0",
  "tracker": { ... },
  "git": { ... },
  "ticketTagging": { ... },
  "escalation": {
    "checkpoints": ["pr"],
    "alwaysAskOn": ["security", "architecture", "public-api"]
  },
  "review": { ... },
  "ciChecks": {
    "enabled": true,
    "maxFixAttempts": 3,
    "confidenceThreshold": 0.7
  },
  "planReview": {
    "reviewPlan": true,
    "requirePlanApproval": false
  },
  "memory": {
    "ticketContext": true,
    "decisions": true
  },
  "models": {
    "product-analyst": "sonnet",
    "solution-architect": "opus",
    "planner": "opus",
    "developer": "opus",
    "code-reviewer": "opus",
    "security-reviewer": "opus",
    "qa-engineer": "sonnet",
    "tech-writer": "sonnet"
  }
}
```

**Directory structure:**
```bash
mkdir -p .n1/memory
mkdir -p .n1/decisions
mkdir -p .n1/telemetry
```

**`.gitignore`** — append `.n1/` if not already present:
```bash
echo "" >> .gitignore
echo "# N1 plugin state" >> .gitignore
echo ".n1/" >> .gitignore
```

## Confirm

Show summary:
```
N1 is ready.

Tracker: Jira (TRID) / YouTrack / None
Default branch: main
Branch pattern: {prefix}-{id}
Ticket tagging: payments-api / disabled

Created:
  .n1/n1.config.json
  .n1/memory/
  .n1/decisions/
  .n1/telemetry/
  .claude/settings.json updated (if pinning configured)
  .gitignore updated

Next: Use /n1:n1-start <ticket-or-description> to begin working on a task.
```
