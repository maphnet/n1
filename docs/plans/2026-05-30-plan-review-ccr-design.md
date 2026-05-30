# Plan Review via Solution-Architect CCR

## Problem

Planning errors are the most expensive to fix — a wrong assumption in `plan.md` propagates through implementation, QA, and review, where each downstream step amplifies the cost. Today the only quality gate between plan creation and implementation is the user checkpoint, which is often approved quickly.

## Decision

Add a single-pass Cross-Context Review (CCR) step after plan creation. The solution-architect agent is spawned again in fresh context with review-oriented instructions. If the plan is clean or fixable, proceed straight to implementation without a user checkpoint.

## Research Basis

Key findings from the academic literature:

- **Same-session self-review degrades quality.** Huang et al. (ICLR 2024) showed that reviewing output in the same context changes correct answers to wrong ones more often than it fixes errors.
- **Cross-Context Review works.** Song (2026) demonstrated CCR achieves F1 of 28.6% vs same-session review at 24.6% (p=0.008). Context separation itself is the mechanism, not repetition.
- **Single pass is optimal.** "More Rounds, More Noise" (Song, 2026) found that multi-turn review degrades quality through false positive pressure (fabricated findings) and review target drift (critiquing the conversation instead of the artifact).
- **Adversarial prompting is essential.** "Is this good?" produces rubber-stamping. Specific criteria produce useful critique.
- **Tool-augmented critique outperforms pure reflection.** The CRITIC framework showed that giving the reviewer access to external tools (codebase access in our case) significantly improves results.

### Known limitations

- **Correlated blind spots:** Same model (Opus) reviewing its own output shares the same reasoning failure patterns. CCR mitigates but does not eliminate this.
- **~33% silent endorsement rate:** The reviewer confidently approves broken output roughly one in three times. This is supplementary, not a safety net.

## Design

### Pipeline Change

Current flow:
```
... → plan → CHECKPOINT (user approval) → implementation → ...
```

New flow:
```
... → plan → plan-review (solution-architect CCR) → implementation → ...
```

The user checkpoint is removed by default. If the reviewer finds issues, it fixes them in `plan.md` in the same pass — no second validation round (per the "single pass is optimal" finding).

### Review Step Details

**Agent:** solution-architect (same persona, same model as plan production)

**Context:** Fresh spawn. Receives only:
- `ticket.md`
- `analysis.md`
- `brainstorm.md`
- `plan.md` (or `docs/plans/<file>.md` referenced by plan.md)

**Tools:** Read, Grep, Glob (codebase access for assumption verification)

**Review criteria (adversarial prompt):**
1. **Assumption validation** — Does the plan rely on assumptions about the codebase that weren't verified? Grep/Read to confirm.
2. **Scope drift vs. ticket** — Does the plan solve what the ticket asked for, or has it drifted beyond scope?
3. **Missing edge cases** — Are there failure modes, error paths, or data states the plan doesn't address?
4. **Ordering/dependency risks** — Are implementation steps in the right order? Hidden dependencies between steps?
5. **Blast radius** — Does the plan touch more files/systems than necessary?

**Output behavior:**
- No issues found → log clean result, proceed to implementation
- Issues found → fix them in-place in the plan file in the same pass, log what was changed, proceed to implementation

### Configuration

In `n1.config.json`:

```json
{
  "planReview": {
    "reviewPlan": true,
    "requirePlanApproval": false
  }
}
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `planReview.reviewPlan` | boolean | `true` | Enable/disable the plan review CCR step |
| `planReview.requirePlanApproval` | boolean | `false` | If true, present plan to user for approval after review (restores the old checkpoint behavior) |

### Cost

- ~10-15K additional tokens per pipeline run
- ~15-60 seconds additional latency
- No context pollution to the orchestrator (separate agent spawn)

## Impact on Step Dependency Map

The review step reads and potentially writes `plan.md`. No new memory file is created — the review is an in-place refinement, not a separate artifact.

| Step | Reads | Writes |
|------|-------|--------|
| plan-review | `ticket.md`, `analysis.md`, `brainstorm.md`, `plan.md` | `plan.md` (in-place fixes) |

## Implementation Status

Implemented. Changes:
- `skills/n1-start/SKILL.md` — Step 4b added (plan review CCR), checkpoint made conditional
- `skills/n1-init/SKILL.md` — `planReview` config section added to wizard and template
- `.n1/n1.config.json` — `planReview` section added, `"plan"` removed from `escalation.checkpoints`
- `CLAUDE.md` — dependency map, agent table, and escalation model updated
