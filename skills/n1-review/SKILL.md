---
name: n1-review
description: "Code review with fix loop. No args = review current branch (fix cycle). With PR number = advisory review (report only)."
argument-hint: "[PR#]"
---

# N1 Code Review

## Overview

Three-phase code review: **find → verify → report**. Specialized agents hunt for bugs ranked by priority (Critical/High/Medium/Low). A verification pass then rules out false positives before producing the final report.

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

## Priority Levels

All findings use a four-tier priority scale:

| Priority | Label | Criteria |
|----------|-------|----------|
| **Critical** | Blocker | Correctness bugs, security vulnerabilities, data loss/corruption risks |
| **High** | Must fix | Design flaws, missing edge cases, broken contracts, test gaps for critical paths |
| **Medium** | Should fix | Suboptimal patterns, minor edge cases, incomplete error handling |
| **Low** | Nice to have | Style, naming, minor improvements, hardening suggestions |

## Review Loop Mode

Three-phase cycle: find bugs → verify findings → report. If confirmed bugs exist, fix and repeat.

### Phase 1: Collect Context

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

### Phase 2: Find Bugs

**Spawn agents in PARALLEL:** code-reviewer + security-reviewer

Resolve models for both agents.

Prepare shared review context:
- What was implemented (from memory or commit messages)
- Original requirements (from ticket.md or brainstorm.md)
- Implementation details (from implementation.md)
- QA results (from qa.md, if available)
- Base SHA: `git merge-base ${DEFAULT_BRANCH} HEAD`
- Head SHA: current `HEAD`

Spawn BOTH agents simultaneously. Each returns findings ranked by priority (Critical → High → Medium → Low).

**Wait for ALL agents to complete before proceeding.**

### Phase 3: Verify Findings (False-Positive Elimination)

After BOTH agents return, merge their raw findings into a single list ordered by priority.

**Spawn agent:** code-reviewer (with verification prompt)

Resolve model for `code-reviewer`.

Pass to verification agent:
- The complete merged findings list from Phase 2
- Access to the full codebase for independent investigation

The verification agent MUST for each finding:
1. **Read the actual code** at the referenced file:line
2. **Check surrounding context** — callers, tests, framework guarantees
3. **Determine verdict:** CONFIRMED (real issue) or FALSE POSITIVE (with reason)
4. **Re-assess priority** — a finding may shift priority after deeper analysis

The verification agent returns findings in two groups:
- **Confirmed findings** — real issues, with updated priority if changed
- **Dismissed findings** — false positives, with explanation of why each was ruled out

### Phase 4: Route by Severity

Work with **confirmed findings only** (false positives are discarded).

**Clean = no Critical or High findings.** Medium and Low findings are reported but do not block the pass.

**If Critical or High confirmed findings exist:**

**Spawn agent:** developer

Resolve model for `developer`.

Pass to developer:
- Confirmed findings (Critical + High only)
- List of affected files

After developer fixes are applied, go back to **Phase 2** (full re-review: find → verify → report).

**Oscillation guard:** fingerprint each confirmed Critical/High finding (file + line + title). If a fix attempt does not reduce the confirmed Critical/High count, or the same fingerprint reappears after being marked fixed, escalate early rather than burning the remaining cycles.

Maximum 3 review-fix cycles before escalating to user.

**If no Critical or High confirmed findings (clean pass):**

Review is clean. Medium and Low findings are included in the final report as suggestions but do not trigger a fix cycle.

Check review count:
- Read `n1.config.json` → `review.minCleanPasses` (default: 1) — minimum consecutive clean passes required
- If this is clean pass N and N < minCleanPasses → go back to **Phase 2**
- If N >= minCleanPasses → **PASS**

### Phase 5: Final Report

```markdown
## Review Report

### Confirmed Findings (Fixed)
| # | Priority | Finding | File | Fix Applied |
|---|----------|---------|------|-------------|
| 1 | Critical | ... | path:line | commit hash |

### Confirmed Findings (Deferred)
| # | Priority | Finding | File | Reason |
|---|----------|---------|------|--------|

### Dismissed (False Positives)
| # | Original Priority | Finding | Reason Dismissed |
|---|-------------------|---------|------------------|

### Stats
- Review cycles: N
- Raw findings: X → Confirmed: Y → Fixed: Z
- False positives eliminated: N

### Verdict: PASS / FAIL
```

Update N1 memory if available:
- Write `.n1/memory/<ticket-id>/review.md` with the final report
- Update `.n1/memory/<ticket-id>/overview.md` checkbox: `[x] Review`

## Advisory Mode

Report-only review for an existing PR. Same find → verify → report flow, but no fixes applied.

### Step 1: Fetch PR diff

```bash
gh pr diff <PR_NUMBER>
```

Also fetch PR description:
```bash
gh pr view <PR_NUMBER>
```

### Step 2: Find Bugs

**Spawn agents in PARALLEL:** code-reviewer + security-reviewer

Resolve models for both agents.

Provide:
- PR diff as the code to review
- PR description as the requirements

**Wait for ALL agents to complete before proceeding.**

### Step 3: Verify Findings

Same verification process as Review Loop Phase 3:

**Spawn agent:** code-reviewer (with verification prompt)

For each finding: read the actual code, check context, determine CONFIRMED or FALSE POSITIVE, re-assess priority.

### Step 4: Present Final Report

```markdown
## Review: PR #<number> — <title>

### Critical
- [confirmed findings only]

### High
- [confirmed findings only]

### Medium
- [confirmed findings only]

### Low
- [confirmed findings only]

### Dismissed (False Positives)
- [findings ruled out with reasons]

### Summary
- Raw findings: X → Confirmed: Y → False positives: Z
<overall assessment: approve / request changes / needs discussion>
```

Do NOT apply any fixes. This is advisory only — the user decides what to do with the findings.

## Integration

**Called by:**
- **n1-start** — as the mandatory review loop before PR creation
- **Standalone** — `/n1:n1-review` or `/n1:n1-review #340`

**Invokes:**
- n1 agent: **code-reviewer** — bug finding (Phase 2) and false-positive verification (Phase 3)
- n1 agent: **security-reviewer** — security vulnerability finding (Phase 2)
- n1 agent: **developer** — systematic fix of confirmed findings (Phase 4, review loop mode only)
