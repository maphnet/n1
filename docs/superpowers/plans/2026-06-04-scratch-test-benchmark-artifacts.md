# Scratch vs. Committed Test/Benchmark Artifacts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teach N1's agents to route throwaway investigative tests/benchmarks into the gitignored `.n1/` scratch area while keeping real, CI-worthy tests in the repo.

**Architecture:** A three-line classification rule is added to the Constraints of the three agents that write these artifacts (`solution-architect`, `developer`, `qa-engineer`). The orchestrating skills (`n1-start`, `n1-review`, `n1-ci`) pass the concrete scratch path at spawn time — per-ticket `.n1/memory/<ID>/{benchmarks,tests}/`, or the `.n1/scratch/{benchmarks,tests}/` fallback when no ticket memory exists. The developer rule is additionally mirrored into `n1-start`'s inline SDD persona constraints, because SDD implementer subagents do not load `agents/developer.md`. Docs get a short discoverability note.

**Tech Stack:** Markdown skills (`skills/*/SKILL.md`) and agents (`agents/*.md`), Bash plugin — **no test runner**. Verification is by `grep`/`rg` assertions on the edited files plus manual dogfooding (`claude --plugin-dir C:\Dev\n1`), matching the convention of prior N1 plans.

**Canonical text (reused verbatim across tasks — keep identical):**

- **Writer-agent clause** (solution-architect, developer):
  > - **Scratch vs. committed test artifacts.** A test or benchmark written only to answer a question you have *right now* — a micro-benchmark comparing approaches, a repro script, a viability spike — is throwaway. Write it under the scratch directory the orchestrator gives you (under `.n1/`, gitignored), never into the repo's test suite. Only tests that verify the committed implementation and should run in CI forever (unit, integration, e2e tied to acceptance criteria) belong in the repo. When unsure, default to scratch.

- **qa-engineer clause** (its default is to write *real* tests, so the wording differs):
  > - **Scratch vs. committed test artifacts.** Your acceptance, edge-case, and error-path tests verify the committed implementation — commit them to the repo's test suite as usual. But a throwaway probe written only to answer a question — a spike checking whether an approach is viable, a one-off benchmark — goes under the scratch directory the orchestrator gives you (under `.n1/`, gitignored), never into the repo. When unsure whether a test protects shipped code, default to scratch.

- **Per-ticket spawn directive** (n1-start architect & qa spawns):
  > - Directive: "Scratch-artifact policy: write any throwaway benchmark or investigative/spike test (one that answers a current question rather than verifying committed code) under `.n1/memory/<ID>/benchmarks/` or `.n1/memory/<ID>/tests/` (both gitignored; create the directory if needed) — never into the repo's test suite. Tests that verify the implementation still go into the repo as usual. When unsure, default to scratch."

- **Fallback spawn directive** (n1-review & n1-ci developer spawns — no ticket memory):
  > - Scratch-artifact policy: write any throwaway benchmark or investigative/spike test (one answering a current question rather than verifying committed code) under `.n1/scratch/benchmarks/` or `.n1/scratch/tests/` (both gitignored; create the directory if needed) — never into the repo's test suite. Fixes that need real regression coverage still get committed tests in the repo as usual. When unsure, default to scratch.

- **Mirrored SDD persona bullet** (n1-start Step 5 inline constraints):
  > - **Scratch vs. committed test artifacts** — a benchmark or test written only to answer a current question (approach comparison, repro, spike) is throwaway: write it under `.n1/memory/<ID>/benchmarks/` or `.n1/memory/<ID>/tests/` (gitignored), never into the repo's test suite. Tests verifying the committed change still go into the repo. When unsure, default to scratch.

---

### Task 1: Add the scratch clause to `solution-architect`

**Files:**
- Modify: `agents/solution-architect.md` (Constraints list, after the last bullet ~line 86)

- [ ] **Step 1: Add the writer-agent clause as the final Constraints bullet**

Find the last line of the Constraints list:

```markdown
- If no similar features exist, say so explicitly rather than forcing a comparison
```

Append immediately after it (new line):

```markdown
- **Scratch vs. committed test artifacts.** A test or benchmark written only to answer a question you have *right now* — a micro-benchmark comparing approaches, a repro script, a viability spike — is throwaway. Write it under the scratch directory the orchestrator gives you (under `.n1/`, gitignored), never into the repo's test suite. Only tests that verify the committed implementation and should run in CI forever (unit, integration, e2e tied to acceptance criteria) belong in the repo. When unsure, default to scratch.
```

- [ ] **Step 2: Verify the clause is present**

Run: `rg -c "Scratch vs. committed test artifacts" agents/solution-architect.md`
Expected: `1`

- [ ] **Step 3: Commit**

```bash
git add agents/solution-architect.md
git commit -m "feat(solution-architect): route throwaway test/benchmark probes to .n1 scratch"
```

---

### Task 2: Add the scratch clause to `developer`

**Files:**
- Modify: `agents/developer.md` (Constraints list, after the last bullet ~line 71)

- [ ] **Step 1: Add the writer-agent clause as the final Constraints bullet**

Find the last line of the Constraints list:

```markdown
- If a test reveals an unrelated bug, note it in output but do not fix it
```

Append immediately after it (new line):

```markdown
- **Scratch vs. committed test artifacts.** A test or benchmark written only to answer a question you have *right now* — a micro-benchmark comparing approaches, a repro script, a viability spike — is throwaway. Write it under the scratch directory the orchestrator gives you (under `.n1/`, gitignored), never into the repo's test suite. Only tests that verify the committed implementation and should run in CI forever (unit, integration, e2e tied to acceptance criteria) belong in the repo. When unsure, default to scratch.
```

- [ ] **Step 2: Verify the clause is present**

Run: `rg -c "Scratch vs. committed test artifacts" agents/developer.md`
Expected: `1`

- [ ] **Step 3: Commit**

```bash
git add agents/developer.md
git commit -m "feat(developer): route throwaway test/benchmark probes to .n1 scratch"
```

---

### Task 3: Add the scratch clause to `qa-engineer`

**Files:**
- Modify: `agents/qa-engineer.md` (Constraints list, after the last bullet ~line 86)

- [ ] **Step 1: Add the qa-engineer clause as the final Constraints bullet**

Find the last line of the Constraints list:

```markdown
- Touch only test files related to the implemented feature — do not "improve" or refactor existing unrelated tests
```

Append immediately after it (new line):

```markdown
- **Scratch vs. committed test artifacts.** Your acceptance, edge-case, and error-path tests verify the committed implementation — commit them to the repo's test suite as usual. But a throwaway probe written only to answer a question — a spike checking whether an approach is viable, a one-off benchmark — goes under the scratch directory the orchestrator gives you (under `.n1/`, gitignored), never into the repo. When unsure whether a test protects shipped code, default to scratch.
```

- [ ] **Step 2: Verify the clause is present**

Run: `rg -c "Scratch vs. committed test artifacts" agents/qa-engineer.md`
Expected: `1`

- [ ] **Step 3: Commit**

```bash
git add agents/qa-engineer.md
git commit -m "feat(qa-engineer): keep throwaway probes out of the repo test suite"
```

---

### Task 4: Wire scratch paths into `n1-start` spawns

**Files:**
- Modify: `skills/n1-start/SKILL.md` — ANALYSIS spawn (~line 259), PLAN second-pass spawn (~line 300), IMPLEMENT mirrored persona constraints (~line 417), QA spawn (~line 481)

This file references `<ID>` as a placeholder throughout — keep it literal in the inserted text.

- [ ] **Step 1: Add the per-ticket directive to the ANALYSIS (Step 2) architect spawn**

Find this bullet in the `### 2. ANALYSIS` section:

```markdown
- Directive: "Research relevant industry standards/best practices per agents/research-standards.md and include the cited Industry Standards & Best Practices section."
```

Append immediately after it (new line):

```markdown
- Directive: "Scratch-artifact policy: write any throwaway benchmark or investigative/spike test (one that answers a current question rather than verifying committed code) under `.n1/memory/<ID>/benchmarks/` or `.n1/memory/<ID>/tests/` (both gitignored; create the directory if needed) — never into the repo's test suite. Tests that verify the implementation still go into the repo as usual. When unsure, default to scratch."
```

- [ ] **Step 2: Add the per-ticket directive to the PLAN (Step 4) second-pass architect spawn**

Find this bullet in the `### 4. PLAN (complex tasks only)` section:

```markdown
- Directive: "Focus on identifying the specific files that need to change, existing patterns to follow, and integration risks. This is a second-pass deeper analysis to inform detailed planning. Also research applicable industry standards/best practices per agents/research-standards.md and cite them."
```

Append immediately after it (new line):

```markdown
- Directive: "Scratch-artifact policy: write any throwaway benchmark or investigative/spike test (one that answers a current question rather than verifying committed code) under `.n1/memory/<ID>/benchmarks/` or `.n1/memory/<ID>/tests/` (both gitignored; create the directory if needed) — never into the repo's test suite. Tests that verify the implementation still go into the repo as usual. When unsure, default to scratch."
```

- [ ] **Step 3: Mirror the scratch rule into the IMPLEMENT (Step 5) SDD persona constraints**

The developer persona is mirrored inline here because SDD implementer subagents do not load `agents/developer.md`. Find the last bullet of that mirrored list:

```markdown
  - If a change requires architectural decisions, report it as "needs escalation" instead of implementing; do not refactor surrounding code.
```

Append immediately after it (same 2-space indentation as the surrounding bullets):

```markdown
  - **Scratch vs. committed test artifacts** — a benchmark or test written only to answer a current question (approach comparison, repro, spike) is throwaway: write it under `.n1/memory/<ID>/benchmarks/` or `.n1/memory/<ID>/tests/` (gitignored), never into the repo's test suite. Tests verifying the committed change still go into the repo. When unsure, default to scratch.
```

- [ ] **Step 4: Add the per-ticket directive to the QA (Step 6) spawn**

Find this bullet in the `### 6. QA` section (the last bullet of the qa-engineer spawn input list):

```markdown
- The `## Key Decisions` and `## Escalations` slices of `overview.md` (NOT the whole file) — so QA knows which choices were deliberate and why, instead of re-litigating them
```

Append immediately after it (new line):

```markdown
- Directive: "Scratch-artifact policy: write any throwaway benchmark or investigative/spike test (one that answers a current question rather than verifying committed code) under `.n1/memory/<ID>/benchmarks/` or `.n1/memory/<ID>/tests/` (both gitignored; create the directory if needed) — never into the repo's test suite. Tests that verify the implementation still go into the repo as usual. When unsure, default to scratch."
```

- [ ] **Step 5: Verify all four insertions are present**

Run: `rg -c "Scratch-artifact policy|Scratch vs. committed test artifacts" skills/n1-start/SKILL.md`
Expected: `4`

- [ ] **Step 6: Commit**

```bash
git add skills/n1-start/SKILL.md
git commit -m "feat(n1-start): pass per-ticket scratch paths to architect, developer, qa spawns"
```

---

### Task 5: Wire the scratch fallback into `n1-review`

**Files:**
- Modify: `skills/n1-review/SKILL.md` — developer fix-cycle spawn (~line 121-123)

- [ ] **Step 1: Add the fallback directive to the developer spawn input list**

Find this block in the review fix phase:

```markdown
Pass to developer:
- Confirmed findings (Critical + High only)
- List of affected files
```

Replace it with:

```markdown
Pass to developer:
- Confirmed findings (Critical + High only)
- List of affected files
- Scratch-artifact policy: write any throwaway benchmark or investigative/spike test (one answering a current question rather than verifying committed code) under `.n1/scratch/benchmarks/` or `.n1/scratch/tests/` (both gitignored; create the directory if needed) — never into the repo's test suite. Fixes that need real regression coverage still get committed tests in the repo as usual. When unsure, default to scratch.
```

- [ ] **Step 2: Verify the directive is present**

Run: `rg -c "Scratch-artifact policy" skills/n1-review/SKILL.md`
Expected: `1`

- [ ] **Step 3: Commit**

```bash
git add skills/n1-review/SKILL.md
git commit -m "feat(n1-review): pass .n1/scratch fallback path to developer fix cycle"
```

---

### Task 6: Wire the scratch fallback into `n1-ci`

**Files:**
- Modify: `skills/n1-ci/SKILL.md` — developer fix-cycle spawn (~line 167-172)

- [ ] **Step 1: Add the fallback directive to the developer spawn input list**

Find the last bullet of the `Pass to developer:` list in `## Step 6: Fix Cycle`:

```markdown
- For each failed check: the check name, category, and truncated log output
```

Append immediately after it (new line):

```markdown
- Scratch-artifact policy: write any throwaway benchmark or investigative/spike test (one answering a current question rather than verifying committed code) under `.n1/scratch/benchmarks/` or `.n1/scratch/tests/` (both gitignored; create the directory if needed) — never into the repo's test suite. Fixes that need real regression coverage still get committed tests in the repo as usual. When unsure, default to scratch.
```

- [ ] **Step 2: Verify the directive is present**

Run: `rg -c "Scratch-artifact policy" skills/n1-ci/SKILL.md`
Expected: `1`

- [ ] **Step 3: Commit**

```bash
git add skills/n1-ci/SKILL.md
git commit -m "feat(n1-ci): pass .n1/scratch fallback path to developer fix cycle"
```

---

### Task 7: Document the convention (CLAUDE.md + README)

**Files:**
- Modify: `CLAUDE.md` (`## Conventions` list — after the `**Timestamps:**` bullet)
- Modify: `README.md` (after the gitignore note in the Per-Ticket Memory section, ~line 142)

- [ ] **Step 1: Add a Conventions bullet to CLAUDE.md**

In the `## Conventions` section, find the `**Timestamps:**` bullet (it ends with `file mtime already records "last modified".`). Append a new bullet immediately after it:

```markdown
- **Test & benchmark artifacts:** Tests/benchmarks that verify committed implementation (unit, integration, e2e tied to acceptance criteria) go in the repo and run in CI. Throwaway probes that only answer a current question (approach micro-benchmarks, repro scripts, viability spikes) go under `.n1/` (gitignored) — per-ticket `.n1/memory/<ID>/{benchmarks,tests}/`, or `.n1/scratch/{benchmarks,tests}/` when there is no ticket memory. When unsure, default to scratch. Bound into the `solution-architect`, `developer`, and `qa-engineer` personas; concrete paths are passed by the skills at spawn time.
```

- [ ] **Step 2: Add a discoverability line to README.md**

Find this line in the `### Per-Ticket Memory` section:

```markdown
The `.n1/` directory is fully gitignored — tool state never gets committed to your project.
```

Append a new paragraph immediately after it:

```markdown
Throwaway investigative tests and benchmarks (one-off probes that answer a question rather than verify shipped code) are written under `.n1/` too — they never land in your repo's test suite. Real unit/integration/e2e tests that cover the implemented feature are committed to the repo as usual.
```

- [ ] **Step 3: Verify both docs updated**

Run: `rg -c "Test & benchmark artifacts" CLAUDE.md` → Expected: `1`
Run: `rg -c "Throwaway investigative tests" README.md` → Expected: `1`

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: document scratch vs committed test/benchmark convention"
```

---

### Task 8: Final consistency sweep

**Files:** none modified — verification only.

- [ ] **Step 1: Confirm the rule reached every intended surface**

Run:
```bash
rg -l "Scratch vs. committed test artifacts|Scratch-artifact policy|Test & benchmark artifacts|Throwaway investigative tests" agents skills CLAUDE.md README.md
```
Expected: exactly these 8 files —
`agents/solution-architect.md`, `agents/developer.md`, `agents/qa-engineer.md`, `skills/n1-start/SKILL.md`, `skills/n1-review/SKILL.md`, `skills/n1-ci/SKILL.md`, `CLAUDE.md`, `README.md`.

- [ ] **Step 2: Confirm no scratch artifact path was accidentally pointed at a committed location**

Run: `rg -n "scratch/benchmarks|scratch/tests|memory/<ID>/benchmarks|memory/<ID>/tests" agents skills CLAUDE.md README.md`
Expected: every hit is under `.n1/` — no path outside `.n1/`.

- [ ] **Step 3: Manual dogfood (record result, do not block on tooling)**

Per CLAUDE.md, run N1 against a scratch project: `claude --plugin-dir C:\Dev\n1`. Trigger a task whose analysis or implementation would naturally produce a benchmark (e.g. "compare two sort approaches and pick the faster"). Confirm the agent writes the benchmark under `.n1/memory/<ID>/benchmarks/` (or `.n1/scratch/...`) and not into the project's test directory. This step is manual — record the observed behavior in the PR description.

---

## Notes for the Implementer

- **No test runner exists.** "Verify" steps are `rg` assertions on the edited Markdown, not unit tests. This matches every prior N1 plan.
- **Keep the canonical text identical** across Tasks 1–7. The wording is intentionally repeated (not factored into a shared file) per the approved design — locality beats a shared doc for a three-line rule. If you reword one instance, reword all of them.
- **`<ID>` stays literal** in skill edits — it is N1's per-ticket placeholder, resolved at runtime, not a value you substitute.
