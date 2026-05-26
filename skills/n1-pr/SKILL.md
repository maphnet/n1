---
name: n1-pr
description: "Create a pull request. Collects diff, generates PR description, pushes, creates PR, and updates tracker."
---

# N1 Pull Request Creation

## Overview

Create a pull request from the current feature branch. Collects changes, generates PR description, pushes to remote, creates PR via GitHub CLI, and optionally updates the issue tracker.

**Announce at start:** "I'm using the n1-pr skill to create a pull request."

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

### Title:
- If ticket known: `[TRID-510] <ticket title from overview.md>`
- If no ticket: Derive from commit messages (imperative mood, under 70 chars)

### Body:
```markdown
## Summary
<2-3 bullet points describing what changed and why>

## Changes
<grouped list of files changed with brief descriptions>

## Test Plan
- [ ] <specific verification steps>

## Ticket
<link to tracker ticket if available, otherwise omit section>
```

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

**Does NOT invoke sub-skills** — all operations are inline (git, gh, MCP tools).
