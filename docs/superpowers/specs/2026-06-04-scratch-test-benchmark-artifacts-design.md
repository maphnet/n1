# Scratch vs. Committed Test/Benchmark Artifacts — Design

**Date:** 2026-06-04
**Status:** Approved (design)

## Problem

When N1's agents work a task, they sometimes write tests or benchmarks
that exist only to answer a question the agent has *right now* — "is a
Map faster than an object here?", "does this library actually behave
that way?", "does this bug reproduce?". These are disposable: once the
question is answered, they have no reason to run again.

Today there is no convention separating those throwaway probes from
*real* tests that verify the shipped feature. The risk is that
investigative spikes and micro-benchmarks get committed into the target
project's test suite, where they add noise, run in CI forever, and rot.

## Goal

A single, universal rule every N1 agent applies:

> Does this verify the **committed implementation** (→ repo, git) or
> answer a **question I'm currently investigating** (→ `.n1/`,
> gitignored)?

Real unit/e2e/acceptance tests keep going to the repo and CI exactly as
they do today. Throwaway investigative artifacts go to `.n1/`, where
they are already gitignored and scoped to the task.

## The Classification Rule

**Throwaway / investigative → `.n1/` (gitignored)**
An artifact whose purpose is to answer a question the agent has now, not
to protect the shipped code. Examples:
- A micro-benchmark comparing two approaches to inform a design choice.
- A repro script confirming a bug exists or a library's behavior.
- A "spike" test exploring whether an approach is viable at all.
- Anything testing a *hypothesis about the world*, not the *committed
  implementation*.

Tell: **if you deleted it, no real test coverage is lost** — it was
never meant to run again in CI.

**Real / functional → repo (committed to git, normal test locations)**
An artifact that verifies the implemented feature and should keep
running to catch regressions. Examples:
- Unit tests for the functions/classes that were built.
- E2E / integration tests exercising the actual feature path.
- Anything tied to an acceptance criterion.

Tell: **it tests code that lives in the repo, and should run in CI
forever.**

**Default at the boundary:** when it is ambiguous, default to **scratch
(`.n1/`)**. An agent writes a test/benchmark into the repo only when it
clearly verifies committed implementation, or when the user explicitly
asks to keep it.

## Path Convention

| Context | Scratch benchmarks | Scratch tests |
|---------|--------------------|---------------|
| Per-ticket (pipeline has an `<ID>`) | `.n1/memory/<ID>/benchmarks/` | `.n1/memory/<ID>/tests/` |
| Standalone (no ticket memory, e.g. `n1-review`/`n1-ci`) | `.n1/scratch/benchmarks/` | `.n1/scratch/tests/` |

Both live under `.n1/`, which is already fully gitignored — no new
ignore rules are required. Per-ticket artifacts are cleaned up naturally
when that ticket's memory folder is removed.

## Where the Rule Lives

A separate shared doc (à la `agents/research-standards.md`) is **not**
warranted: that file earns its place because it is a large rubric
(source tiers, reject-list, corroboration thresholds, citation format,
fitness gate). This rule is three lines. Splitting three lines into a
file the agent must go Read is ceremony, not clarity.

Instead, the rule is split along N1's natural persona/controller seam:

1. **The decision rule lives with the persona that makes it.** A short
   (~2-line) clause is added to the Constraints of the three agents that
   actually write these artifacts:
   - `solution-architect` — investigation/repro/benchmark probes during
     analysis and bug investigation.
   - `developer` — scratch comparisons during implementation and fix
     cycles (real tests for the change are still committed).
   - `qa-engineer` — default behavior is unchanged (writes *real* tests
     to the repo following project conventions); it gains one explicit
     clause so exploratory/throwaway probes go to scratch rather than
     being dumped into the project's test suite.

   The clause sits next to each agent's existing constraints (e.g.
   qa-engineer's "Commit tests separately"), making each agent
   self-documenting. The only duplication is one short, stable clause;
   for text this stable, locality beats a shared file.

2. **The concrete path comes from the controller.** Because `<ID>` is
   dynamic, the resolved scratch path must be passed at spawn time. The
   orchestrating skills already inject per-ticket memory paths when
   spawning agents — they additionally name the scratch directory
   (`.n1/memory/<ID>/{benchmarks,tests}/`, or the `.n1/scratch/...`
   fallback when no ticket memory exists). This mirrors how `planner`
   already receives its `plan.md` output path. No rule text is
   duplicated across skills — only the path each skill already passes.

## Skill Wiring

- **`n1-start`** — when spawning `solution-architect`, `developer`, and
  `qa-engineer`, include the resolved per-ticket scratch path
  (`.n1/memory/<ID>/...`) in the spawn prompt.
- **`n1-review` / `n1-ci`** — when spawning `developer` for fix cycles
  with no ticket memory present, pass the `.n1/scratch/...` fallback
  path. (Reviewer agents don't write tests, so they need no change.)

## Documentation

- A short "Test & benchmark artifacts" note in CLAUDE.md Conventions.
- A line in README so the convention is discoverable by humans.

## Out of Scope (YAGNI)

- **No auto-cleanup job** — gitignore + per-ticket scoping already
  handle lifecycle.
- **No config toggle** — this is a universal convention, not a
  per-project choice.
- **No hook enforcement** — the rule is prompt-bound, consistent with
  how N1's other agent constraints work. (A PreToolUse path-scoping hook
  could harden it later, but is out of scope here, same as the existing
  qa-engineer "tests only" boundary.)
