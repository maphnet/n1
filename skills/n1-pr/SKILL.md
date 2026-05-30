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

## Step 2: Documentation Update

**Spawn agent:** tech-writer (Phase 1 only)

Resolve model for `tech-writer`.

### Read doc config:
Read `.n1/n1.config.json` → check for optional `docs` section:
- `docs.include` — additional doc paths to scan (array of globs)
- `docs.exclude` — doc paths to skip (array of globs)
- `docs.autoUpdate` — if `true`, skip user confirmation (default: `false`)

### Determine mode:
- If called with `docUpdateMode: "autonomous"` (passed from n1-start) → `autonomous`
- If `docs.autoUpdate` is `true` in config → `autonomous`
- Otherwise → `confirm`

### Spawn tech-writer for Phase 1:
Pass to tech-writer:
- Default branch name (from Step 1)
- Paths to memory files: `implementation.md` (if available)
- Git diff stat output from Step 1
- Doc config: `docs.include`, `docs.exclude` (if present)
- Doc update mode: the resolved mode from above

### If mode is `confirm`:
After tech-writer completes Phase 1 scan, present findings to the user:

```
Documentation scan complete.

Updates to apply:
- <file>: <what will be updated> (<confidence>)

Apply or skip? (apply/skip)
```

- **apply** → tech-writer commits the doc changes
- **skip** → discard doc changes, proceed to Step 3

### If mode is `autonomous`:
Tech-writer applies updates and commits without prompting.

### If no stale docs found:
Proceed directly to Step 3.

## Step 3: Generate PR Content

**If PR title and body are provided as input** (e.g., when called from n1-start after tech-writer already ran): skip tech-writer spawning and use the provided content directly.

**Otherwise (standalone invocation):**

**Spawn agent:** tech-writer

Resolve model for `tech-writer`.

Spawn tech-writer with:
- Ticket ID (extracted from branch name, if available)
- Paths to memory files: `overview.md`, `review.md`, `qa.md`
- Git diff stat output from Step 1
- Doc update report from Step 2 Phase 1 (updated/flagged/needs_review lists) — for the Documentation section in the PR body

The tech-writer agent returns a structured PR title and body.

Present the generated title and body to the user. Ask: **"Create PR with this content? (yes/edit/cancel)"**

## Step 4: Push and Create PR

```bash
git push -u origin ${CURRENT_BRANCH}

gh pr create \
  --title "<generated title>" \
  --body "<generated body>" \
  --base ${DEFAULT_BRANCH}
```

Capture and display the PR URL.

## Step 5: Update Tracker (if configured)

Read `.n1/n1.config.json`. If `tracker.mcp` is not null:

1. **Move status to code review:**
   - Construct MCP tool call: `mcp__<tracker.mcp>__<tracker.operations.moveStatus>`
   - Use `tracker.statuses.codeReview` as the target status (this is "Code Review" if the tracker has it, or falls back to "In Progress")
   - For Jira: first call `mcp__<tracker.mcp>__<tracker.operations.getTransitions>` to get the transition ID for the `codeReview` status, then call `transitionJiraIssue`
   - For YouTrack: call `update_issue` with the `codeReview` status value

2. **Add PR link as comment:**
   - Construct MCP tool call: `mcp__<tracker.mcp>__<tracker.operations.addComment>`
   - Comment body: `PR created: <PR_URL>`

If tracker operations fail, warn but don't block — the PR is already created.

## Step 6: Update Memory

If N1 memory exists for this ticket:
- Update `overview.md`: mark PR step as done, add PR URL
- Add `docs_updated` to overview.md with the list of files updated, flagged, or skipped:
  ```yaml
  docs_updated:
    - file: README.md
      confidence: high
      action: updated
    - file: docs/migration.md
      confidence: none
      action: skipped
  ```
- Frontmatter: set `step: pr`

## Step 7: Report

```
PR created: <PR_URL>
PR #: <number>

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
- n1 agent: **tech-writer** — doc update (Phase 1) + PR content generation (Phase 2)
- Inline: git, gh, tracker MCP operations
