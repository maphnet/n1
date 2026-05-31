# Working Branch Creation in n1-start

**Date:** 2026-05-31
**Status:** Designed

## Problem

`n1-start` never creates a git branch. Both `skills/n1-start/SKILL.md:334` and
`CLAUDE.md` claim *"N1 manages the branch lifecycle"*, but no step ever runs
`git checkout -b`. As a result, **Step 5 (IMPLEMENT)** dispatches Superpowers SDD
— which commits each logical change on the *current* branch — and those commits
land on whatever branch the user started on, usually `main`.

The only branch awareness in the pipeline is a reactive guard in `n1-pr`
(`skills/n1-pr/SKILL.md:30`): *"On default branch? → STOP."* That fires long
after commits have already polluted `main`.

## Goal

Create the working branch **eagerly, the moment the `<ID>` is resolved** in
Step 1, so no commit can ever reach the default branch. The branch name follows
the existing `git.branchPattern` config:

| Config pattern    | Example branch          |
|-------------------|-------------------------|
| `{prefix}-{id}`   | `TRID-510`              |
| `{id}`            | `510`                   |
| `feature/{slug}`  | `feature/csv-export-users` |

## Design

### 1. Shared procedure: "Ensure Working Branch"

A single reusable procedure added to `n1-start/SKILL.md`, called at each path's
ID-resolution point. It is **idempotent** so it is safe to call again on resume.

```
PROCEDURE: Ensure Working Branch (<ID>)

1. Compute target branch name from git.branchPattern + <ID>:
   - "{prefix}-{id}"  -> e.g. TRID-510
   - "{id}"           -> e.g. 510
   - "feature/{slug}" -> e.g. feature/csv-export-users
   Sanitize for git ref validity: lowercase the slug, replace spaces/illegal
   chars with "-", collapse repeats, trim. Ticket IDs are already ref-safe;
   only slugs need sanitizing.

2. Read current state:
   CURRENT = git branch --show-current
   DEFAULT = git.defaultBranch (from config)

3. Decide (smart reuse + safe create):
   a. CURRENT == TARGET            -> reuse silently. Done.
   b. local branch TARGET exists   -> git checkout TARGET. Done.
   c. CURRENT == DEFAULT           -> git checkout -b TARGET
                                      (uncommitted changes carry over). Done.
   d. CURRENT is some OTHER branch -> STOP and ask:
      "You're on branch '<CURRENT>', not the default. Create '<TARGET>'
       from here, switch to default and branch, or keep '<CURRENT>'?"
      Wait for choice.

4. Report: "Working on branch <TARGET>."
```

No `fetch`/`pull` — the branch is created from the local default branch's
current HEAD. Fully offline, no surprise merge conflicts; the user owns keeping
local default up to date.

### 2. Call sites

All fresh-start call sites live in **Step 1 (REQUIREMENTS ANALYSIS)**; one more
covers resume.

- **Ticket mode** — ID known before the analyst runs: call
  `Ensure Working Branch(<ticketId>)` right after input parsing detects ticket
  mode, before spawning product-analyst.
- **Brain-dump / File mode WITH ticket creation** — in the "If 1 (Yes)" block,
  right after the returned ticket ID becomes the memory `<ID>`, call
  `Ensure Working Branch(<new ticket ID>)`.
- **Brain-dump / File mode WITHOUT ticket** — in the "If 2 (No)" block, right
  after the slug is derived, call `Ensure Working Branch(<slug>)`.
- **Resume path** — in `Memory Check`, when `overview.md` already exists, after
  reading the ID from frontmatter, call `Ensure Working Branch(<ID>)` before
  continuing. Idempotency means this just re-checks out the existing branch,
  covering a resume from `main` or a different branch.

In every path the branch exists before `ticket.md` / `overview.md` are written,
and long before Step 5 makes any commit.

### 3. Supporting cleanup

- Make the "N1 manages the branch lifecycle" claims true: keep the SDD override
  (`Do NOT use using-git-worktrees — work on the current branch directly`) but
  reflect that the branch was already created in Step 1; add a one-line note in
  `CLAUDE.md` documenting Step 1 branch creation.
- Keep `n1-pr`'s "On default branch → STOP" guard as defense-in-depth for
  standalone `n1-pr` invocations. No change.
- No changes to `n1-review` / `n1-ci` — they only read the current branch and
  benefit automatically.

## Scope boundary (YAGNI)

Not in scope: branch deletion/cleanup, worktree support, remote-tracking setup,
or push-on-create. The branch is created locally; `n1-pr` Step 4 already does
`git push -u origin <branch>` at PR time — that remains the single push point.
