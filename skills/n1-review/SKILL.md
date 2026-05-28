---
name: n1-review
description: "Code review with fix loop. No args = review current branch (fix cycle). With PR number = advisory review (report only)."
argument-hint: "[PR#]"
---

# N1 Code Review

## Overview

Two-mode code review using specialized agent personas: code-reviewer and security-reviewer for finding issues, developer for fixing them.

**Announce at start:** "I'm using the n1-review skill to review the code."

## Model Resolution

When spawning any agent, resolve its model:
1. Read `.n1/n1.config.json` → check `models.<agent-name>`
2. If the key exists → use that model
3. Otherwise → use the agent's frontmatter default

## Mode Detection

- **No arguments + on a feature branch** → Review Loop mode
- **Called from n1-start** → Review Loop mode
- **PR number provided** (e.g., `/n1:n1-review #340`) → Advisory mode

## Review Loop Mode

Iterative cycle: spawn reviewers → receive findings → spawn developer to fix → repeat until clean.

### Step 1: Collect Context

```bash
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
CURRENT_BRANCH=$(git branch --show-current)
```

If on the default branch: "You're on the default branch. Switch to a feature branch first, or provide a PR number for advisory review." **STOP.**

Read N1 memory if available:
- `.n1/memory/<ticket-id>/ticket.md` — original requirements
- `.n1/memory/<ticket-id>/brainstorm.md` — scope and approach decisions
- `.n1/memory/<ticket-id>/implementation.md` — what was built
- `.n1/memory/<ticket-id>/qa.md` — test coverage report

### Step 2: Spawn Reviewers

**Spawn agents in PARALLEL:** code-reviewer + security-reviewer

Resolve models for both agents.

Prepare shared review context:
- What was implemented (from memory or commit messages)
- Original requirements (from ticket.md or brainstorm.md)
- Implementation details (from implementation.md)
- QA results (from qa.md, if available)
- Base SHA: `git merge-base ${DEFAULT_BRANCH} HEAD`
- Head SHA: current `HEAD`

Spawn BOTH agents simultaneously with the shared context.

### Step 3: Evaluate Findings

After BOTH agents return, merge their findings:

Categorize all results:
- **Critical** — correctness bugs, security vulnerabilities, data loss risks
- **Important** — design problems, missing edge cases, test gaps
- **Minor** — style, naming, minor improvements

### Step 4: Route by Severity

**If critical or important findings exist:**

**Spawn agent:** developer

Resolve model for `developer`.

Pass to developer:
- Combined findings (Critical + Important from both reviewers)
- List of affected files

After developer fixes are applied, go back to **Step 2** (re-run both reviewers).

Maximum 3 review-fix cycles before escalating to user.

**If only minor findings:**

Auto-fix minor issues inline (style, naming). Then go back to **Step 2** for confirmation pass.

**If clean pass (no findings):**

Check review count:
- Read `n1.config.json` → `review.minPasses` (default: 1)
- If this is pass N and N < minPasses → go back to **Step 2**
- If N >= minPasses → **PASS**

### Step 5: Report Result

```
Review PASSED (N passes, 0 outstanding findings).

Fixed during review:
- [list of fixes applied]

Ready for PR creation.
```

Update N1 memory if available:
- Write `.n1/memory/<ticket-id>/review.md` with combined review results
- Update `.n1/memory/<ticket-id>/overview.md` checkbox: `[x] Review`

## Advisory Mode

Report-only review for an existing PR. No fixes applied.

### Step 1: Fetch PR diff

```bash
gh pr diff <PR_NUMBER>
```

Also fetch PR description:
```bash
gh pr view <PR_NUMBER>
```

### Step 2: Spawn Reviewer

**Spawn agent:** code-reviewer

Resolve model for `code-reviewer`.

Provide:
- PR diff as the code to review
- PR description as the requirements

Note: Advisory mode spawns code-reviewer only by default. If the user requests security review, also spawn security-reviewer.

### Step 3: Present Report

Structure the output:

```
## Review: PR #<number> — <title>

### Critical
- [findings]

### Important
- [findings]

### Minor
- [findings]

### Summary
<overall assessment: approve / request changes / needs discussion>
```

Do NOT apply any fixes. This is advisory only — the user decides what to do with the findings.

## Integration

**Called by:**
- **n1-start** — as the mandatory review loop before PR creation
- **Standalone** — `/n1:n1-review` or `/n1:n1-review #340`

**Invokes:**
- n1 agent: **code-reviewer** — code quality and correctness review
- n1 agent: **security-reviewer** — security vulnerability review (review loop mode only by default)
- n1 agent: **developer** — systematic fix of findings (review loop mode only)
