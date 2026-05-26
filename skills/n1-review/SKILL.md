---
name: n1-review
description: "Code review with fix loop. No args = review current branch (fix cycle). With PR number = advisory review (report only)."
argument-hint: "[PR#]"
---

# N1 Code Review

## Overview

Two-mode code review: iterative fix loop for your own work, or advisory review for any PR.

**Announce at start:** "I'm using the n1-review skill to review the code."

## Mode Detection

- **No arguments + on a feature branch** → Review Loop mode
- **Called from n1-start** → Review Loop mode
- **PR number provided** (e.g., `/n1:n1-review #340`) → Advisory mode

## Review Loop Mode

Iterative cycle: request review → receive findings → fix → repeat until clean.

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

### Step 2: Request Review

**REQUIRED SUB-SKILL:** Use superpowers:requesting-code-review to perform deep code review.

Provide the reviewer with:
- What was implemented (from memory or commit messages)
- Original requirements (from ticket.md or brainstorm.md)
- Base SHA: merge-base with default branch
- Head SHA: current HEAD

### Step 3: Evaluate Findings

Categorize results:
- **Critical** — correctness bugs, security issues, data loss risks
- **Important** — design problems, missing edge cases, test gaps
- **Minor** — style, naming, minor improvements

### Step 4: Route by Severity

**If critical or important findings exist:**

**REQUIRED SUB-SKILL:** Use superpowers:receiving-code-review to systematically fix each finding.

After fixes are applied, go back to **Step 2** (request review again).

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
- Write `.n1/memory/<ticket-id>/review.md` with review results
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

### Step 2: Request Review

**REQUIRED SUB-SKILL:** Use superpowers:requesting-code-review to perform deep code review.

Provide:
- PR diff as the code to review
- PR description as the requirements

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
- `superpowers:requesting-code-review` — deep architectural review
- `superpowers:receiving-code-review` — systematic fix of findings (loop mode only)
