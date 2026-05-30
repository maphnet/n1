# Design: n1-ci Skill — Post-PR CI Watch & Fix

## Overview

A standalone skill (`/n1:n1-ci`) that monitors CI checks after PR creation, classifies failures, and either auto-fixes them via the developer agent or escalates to the user when max attempts are exhausted. Called automatically by n1-start after n1-pr, but also usable independently on any PR.

## Invocation

- **From n1-start:** Automatically after successful PR creation. Receives PR number from n1-pr output.
- **Standalone:** `/n1:n1-ci` (uses current branch's PR) or `/n1:n1-ci #123` (explicit PR number).

## Flow

```
1. Resolve PR number (from arg, or `gh pr view --json number`)
2. Poll `gh pr checks <PR#>` until all checks complete
3. If all green → report success, done
4. For each failed check:
   a. Fetch logs via `gh run view <run-id> --log-failed`
   b. Classify failure into category
   c. If "unknown" category → developer agent assesses confidence
      - Below threshold (0.7) → ask user
      - Above threshold → developer agent fixes
   d. All other categories → developer agent fixes
5. Developer commits fix, pushes
6. Loop back to step 2 (max 3 cycles)
7. If max attempts exhausted → block, present analysis, wait for user
8. Report final status
```

## Configuration

New `ciChecks` block in `n1.config.json`:

```json
{
  "ciChecks": {
    "enabled": true,
    "maxFixAttempts": 3,
    "confidenceThreshold": 0.7,
    "categories": {
      "lint": {
        "patterns": ["lint", "eslint", "prettier", "format", "style", "biome"],
        "behavior": "auto-fix"
      },
      "typecheck": {
        "patterns": ["typecheck", "tsc", "mypy", "type-check", "pyright"],
        "behavior": "auto-fix"
      },
      "test": {
        "patterns": ["test", "jest", "pytest", "spec", "vitest", "mocha"],
        "behavior": "auto-fix"
      },
      "build": {
        "patterns": ["build", "compile", "webpack", "vite", "esbuild"],
        "behavior": "auto-fix"
      },
      "security": {
        "patterns": ["security", "snyk", "dependabot", "codeql", "sast"],
        "behavior": "auto-fix"
      },
      "infra": {
        "patterns": ["timeout", "runner", "infrastructure"],
        "behavior": "auto-fix"
      }
    }
  }
}
```

All categories default to `"auto-fix"` (developer agent handles it). Teams can override any category to `"escalate"` (skip developer agent, ask user immediately) or `"skip"` (ignore that check entirely). The `confidenceThreshold` only applies to checks that don't match any category pattern.

`enabled: true` by default — set to `false` to skip the CI step entirely in n1-start.

## Agent & Delegation

The skill spawns the **developer agent** for fixes — same agent already used in the n1-review fix cycle. No new agent needed.

**Developer agent receives:**

- Failed check name and category
- Failed run logs (`--log-failed` output)
- Current git diff against base branch (full context of our changes)
- N1 memory files: `plan.md`, `implementation.md` (so it understands intent)

**Developer agent returns:**

- What it changed and why
- Confidence assessment (0-1) — only matters for "unknown" category checks

**Fix commit convention:** Developer agent commits with a descriptive message (e.g., `fix: resolve eslint no-unused-vars in auth.ts`) and pushes to the PR branch directly.

**Cycle mechanics:**

1. All fixable failures from a single CI run are batched into one developer agent spawn (not one agent per check)
2. Developer agent fixes all issues, commits, pushes
3. Skill polls for new CI run to complete
4. If new failures → spawn developer agent again (cycle 2)
5. Max 3 cycles, then block and present to user

## Integration with n1-start

Step 10 in the current n1-start pipeline is PR creation (n1-pr). The CI watch becomes step 11:

```
10. PR Creation  → n1:n1-pr (autonomous doc update mode)
11. CI Watch     → n1:n1-ci (auto, using PR number from step 10)
12. Finalize     → update overview.md, mark pipeline complete
```

**Behavior in pipeline context:**

- Only runs if `ciChecks.enabled: true` (default)
- Only runs if n1-pr succeeded and returned a PR number
- If all checks pass (with or without fixes) → pipeline continues to finalize
- If max attempts exhausted → blocks with failure analysis, waits for user instruction:
  - Provide guidance for another fix attempt
  - Say "skip" to finalize the pipeline with CI red
  - Fix manually and say "continue" to re-poll

**Integration with n1-pr:** n1-pr stays unchanged. It reports the PR URL as today. n1-start reads the PR number from n1-pr output and passes it to n1-ci.

## Memory

The skill writes no new memory file. It updates `overview.md` with:

- CI status (pass/fail)
- Number of fix cycles
- What was auto-fixed (if anything)
- What was escalated (if anything)

## Polling Strategy

**Waiting for checks to appear:**

- After PR creation or a fix push, CI checks may take a few seconds to register
- Initial delay: 15 seconds before first poll
- Then poll `gh pr checks <PR#> --json name,state,conclusion` every 30 seconds
- Timeout after 15 minutes if checks never appear → warn user and end

**Waiting for checks to complete:**

- Poll every 30 seconds until all checks have `state: completed`
- Timeout after 30 minutes → report which checks are still pending, ask user

**Output during polling:**

- Short status line each poll: `Waiting for CI... 3/5 checks complete`
- When a check finishes: report pass/fail per check

## Standalone Usage

`/n1:n1-ci` without arguments:

- Detects current branch, finds its open PR via `gh pr view --json number`
- Runs the same poll → classify → fix/escalate flow
- Works without N1 memory files — developer agent just uses the diff and failure logs

`/n1:n1-ci #123`:

- Operates on the specified PR number directly
- Checks out the PR branch if not already on it

## Key Decisions

- **Separate skill** reusable standalone or from n1-start
- **`gh pr checks` + `gh run view --log-failed`** for real failure context
- **Hybrid categories**: lint/types auto-fix, everything else auto-fix by default but configurable per team, unknown uses confidence threshold
- **Developer agent** handles all fixes, same agent as review fix cycle
- **3 max attempts** (configurable), then block and wait for user
- **No tracker updates**, no new memory files (only overview.md update)
- **All config in `ciChecks` block**, fully customizable categories and patterns
