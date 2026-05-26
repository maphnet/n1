---
name: n1-init
description: "Set up N1 for a project. Creates .n1/ directory, n1.config.json, and enriches CLAUDE.md with project conventions."
---

# N1 Project Setup

## Overview

Initialize N1 for the current project. This creates the `.n1/` directory structure, generates `n1.config.json` with tracker and git settings, and optionally enriches CLAUDE.md with detected project conventions.

**Announce at start:** "I'm using the n1-init skill to set up N1 for this project."

## Prerequisites

Check if CLAUDE.md exists in the project root:
- **If missing:** Tell the user: "CLAUDE.md not found. Run `/init` first to create one, then re-run `/n1:n1-init`." **STOP.**
- **If exists:** Continue.

Check if `.n1/n1.config.json` already exists:
- **If exists:** Tell the user: "N1 is already configured for this project. Current config:" then show the config. Ask if they want to reconfigure. If no — **STOP.**
- **If missing:** Continue with fresh setup.

## Step 1: Analyze Repository

Explore the project to detect:

1. **Stack:** Look for `package.json`, `composer.json`, `Cargo.toml`, `go.mod`, `requirements.txt`, `pyproject.toml`, `Gemfile`, `pom.xml`, `build.gradle`, etc.
2. **Docker:** Check for `Dockerfile`, `docker-compose.yml`, `docker-compose.yaml`
3. **Monorepo:** Check for `lerna.json`, `pnpm-workspace.yaml`, `turbo.json`, or multiple `package.json` files
4. **Test runner:** Look in config files and scripts for test commands
5. **Linter/formatter:** Look for `.eslintrc*`, `.prettierrc*`, `phpcs.xml`, `rustfmt.toml`, `.flake8`, etc.
6. **CI/CD:** Check `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`, etc.

Read existing CLAUDE.md content to identify what's already documented.

## Step 2: Enrich CLAUDE.md (if gaps found)

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

Add these to CLAUDE.md? (yes/no/edit)
```

If approved, append to CLAUDE.md. If "edit" — ask what to change first.

## Step 3: Tracker Setup

Ask: **"Which issue tracker do you use?"**

Present options:
1. **Jira** (via Atlassian MCP)
2. **YouTrack** (via YouTrack MCP)
3. **None** (no tracker integration)

### If Jira:

Set config values:
```json
{
  "tracker": {
    "mcp": "plugin_atlassian_atlassian",
    "prefix": "<ask user>",
    "projectKey": "<ask user>",
    "operations": {
      "readTicket": "getJiraIssue",
      "getTransitions": "getTransitionsForJiraIssue",
      "moveStatus": "transitionJiraIssue",
      "addComment": "addCommentToJiraIssue",
      "search": "searchJiraIssuesUsingJql",
      "createIssue": "createJiraIssue"
    },
    "statuses": {
      "todo": "<ask user or detect>",
      "inProgress": "<ask user or detect>",
      "review": "<ask user or detect>",
      "done": "<ask user or detect>"
    }
  }
}
```

Ask for:
- Ticket prefix (e.g., "TRID", "PROJ")
- Project key (often same as prefix)
- Workflow statuses: "What are your workflow status names? Common: To Do, In Progress, In Review, Done"

### If YouTrack:

Set config values:
```json
{
  "tracker": {
    "mcp": "youtrack",
    "prefix": "<ask user>",
    "projectKey": "<ask user>",
    "operations": {
      "readTicket": "get_issue",
      "getComments": "get_issue_comments",
      "moveStatus": "update_issue",
      "addComment": "add_issue_comment",
      "search": "search_issues",
      "createIssue": "create_issue"
    },
    "statuses": {
      "todo": "<ask user>",
      "inProgress": "<ask user>",
      "review": "<ask user>",
      "done": "<ask user>"
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

## Step 4: Git Configuration

Detect automatically:
- **defaultBranch:** Run `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'` or fall back to checking `main`/`master` existence
- **branchPattern:** Ask user. Default suggestion: `{prefix}-{id}` (e.g., `TRID-510`)

```json
{
  "git": {
    "defaultBranch": "main",
    "branchPattern": "{prefix}-{id}"
  }
}
```

## Step 5: Review Configuration

Ask: **"Minimum review passes before PR creation? (default: 1)"**

```json
{
  "review": {
    "minPasses": 1
  }
}
```

## Step 6: Write Configuration and Structure

Create all files:

**`.n1/n1.config.json`** — assembled from steps above:
```json
{
  "version": "0.1.0",
  "tracker": { ... },
  "git": { ... },
  "escalation": {
    "checkpoints": ["plan", "pr"],
    "alwaysAskOn": ["security", "architecture", "public-api"]
  },
  "review": { ... },
  "memory": {
    "ticketContext": true,
    "decisions": true
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

## Step 7: Confirm

Show summary:
```
N1 is ready.

Tracker: Jira (TRID) / YouTrack / None
Default branch: main
Branch pattern: {prefix}-{id}
Review passes: 1

Created:
  .n1/n1.config.json
  .n1/memory/
  .n1/decisions/
  .n1/telemetry/
  .gitignore updated

Next: Use /n1:n1-start <ticket-or-description> to begin working on a task.
```
