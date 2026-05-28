---
name: n1-pr
description: "Create a pull request. Collects diff, generates PR description via tech-writer agent, pushes, creates PR, and updates tracker."
---

# N1 Pull Request Creation

## Overview

Create a pull request from the current feature branch. Spawns the tech-writer agent for PR content generation, then handles git push, PR creation via GitHub CLI, and tracker update.

**Announce at start:** "I'm using the n1-pr skill to create a pull request."

## Model Resolution

When spawning any agent, resolve its model:
1. Read `.n1/n1.config.json` → check `models.<agent-name>`
2. If the key exists → use that model
3. Otherwise → use the agent's frontmatter default

## Prerequisites

Verify the working state:

```bash
CURRENT_BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
```

- **On default branch?** → "You're on the default branch. Switch to a feature branch first." **STOP.**
- **Uncommitted changes?** → Commit them first. Summarize what's being committed and ask for confirmation.

## Step 1: Collect Information

### Git context:
```bash
git log ${DEFAULT_BRANCH}..HEAD --oneline
git diff ${DEFAULT_BRANCH}...HEAD --stat
```

### N1 memory (if available):
Read from `.n1/memory/<ticket-id>/`:
- `overview.md` — ticket title, status, key decisions
- `review.md` — review results (confirm review passed)
- `qa.md` — test coverage report

### N1 config:
Read `.n1/n1.config.json` for:
- `tracker.prefix` — to detect ticket ID from branch name
- `tracker.mcp` — to know if tracker update is needed
- `git.defaultBranch` — confirmed default branch
- `git.branchPattern` — to extract ticket ID

### Extract ticket ID:
Parse from branch name using `git.branchPattern`. Example:
- Branch: `TRID-510` + pattern `{prefix}-{id}` → ticket = `TRID-510`

## Step 2: Generate PR Content

**If PR title and body are provided as input** (e.g., when called from n1-start after tech-writer already ran): skip tech-writer spawning and use the provided content directly.

**Otherwise (standalone invocation):**

**Spawn agent:** tech-writer

Resolve model for `tech-writer`.

Spawn tech-writer with:
- Ticket ID (extracted from branch name, if available)
- Paths to memory files: `overview.md`, `review.md`, `qa.md`
- Git diff stat output from Step 1

The tech-writer agent returns a structured PR title and body.

Present the generated title and body to the user. Ask: **"Create PR with this content? (yes/edit/cancel)"**

## Step 3: Push and Create PR

```bash
git push -u origin ${CURRENT_BRANCH}

gh pr create \
  --title "<generated title>" \
  --body "<generated body>" \
  --base ${DEFAULT_BRANCH}
```

Capture and display the PR URL.

## Step 4: Update Tracker (if configured)

Read `.n1/n1.config.json`. If `tracker.mcp` is not null:

1. **Move status to review:**
   - Construct MCP tool call: `mcp__<tracker.mcp>__<tracker.operations.moveStatus>`
   - For Jira: first call `mcp__<tracker.mcp>__<tracker.operations.getTransitions>` to get the transition ID for the review status, then call `transitionJiraIssue`
   - For YouTrack: call `update_issue` with the review status field

2. **Add PR link as comment:**
   - Construct MCP tool call: `mcp__<tracker.mcp>__<tracker.operations.addComment>`
   - Comment body: `PR created: <PR_URL>`

If tracker operations fail, warn but don't block — the PR is already created.

## Step 5: Update Memory

If N1 memory exists for this ticket:
- Update `overview.md`: mark PR step as done, add PR URL
- Frontmatter: set `step: pr`

## Step 6: Report

```
PR created: <PR_URL>

Title: <title>
Base: <default branch>
Tracker: <status updated / not configured / failed>

CHECKPOINT: Ready for Tech Lead review.
```

## Integration

**Called by:**
- **n1-start** — after review loop passes
- **Standalone** — `/n1:n1-pr`

**Invokes:**
- n1 agent: **tech-writer** — PR content generation
- Inline: git, gh, tracker MCP operations
