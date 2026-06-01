# Use Created Ticket ID in Memory Path (n1-start) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `n1-start` deterministically adopt a newly-created ticket ID as the per-ticket memory `<ID>` and branch name, and migrate any state that leaked under a provisional slug.

**Architecture:** Two complementary edits to `skills/n1-start/SKILL.md` — (1) *prevention*: an ID-Final invariant plus a hard "create the ticket immediately on Yes" gate; (2) *recovery*: a new idempotent `Reconcile Memory ID & Branch` procedure that moves the slug memory folder into the ticket-ID folder and renames the slug branch. Plus a one-line traceability note in `CLAUDE.md`.

**Tech Stack:** Markdown skill authoring (no runtime, no tests). Verification is by inspection, `Grep`, and a manual dogfood trace.

**Spec:** `docs/superpowers/specs/2026-06-01-n1-start-ticket-id-memory-path-design.md`

---

## Note on TDD adaptation

These files are Claude Code skill/instruction Markdown — there is no automated test
harness. Each task therefore replaces "write failing test → make it pass" with
"apply exact edit → verify by `Grep`/`Read` that the intended text is present and the
old text is gone." A final task does an end-to-end dogfood trace of the instructions.

## File Structure

- **Modify:** `skills/n1-start/SKILL.md` — all behavioral changes:
  - New `Reconcile Memory ID & Branch` procedure (in the `## Working Branch` section).
  - ID-Final invariant + "Yes" red-flag note (in the ticket-creation block).
  - Rewired Step 1 "Yes" item 4.
- **Modify:** `CLAUDE.md` — one-line note in the Tracker Routing section.

The two `SKILL.md` regions (Working Branch section ~lines 47-81; ticket-creation block
~lines 147-199) are edited independently and do not overlap.

---

### Task 1: Add the `Reconcile Memory ID & Branch` procedure

**Files:**
- Modify: `skills/n1-start/SKILL.md` (insert after the "Ensure Working Branch" procedure, before `## Memory Check (Resume Support)`)

- [ ] **Step 1: Apply the edit**

Use `Edit` on `skills/n1-start/SKILL.md`.

`old_string`:
```
No `fetch`/`pull` is performed — the branch is created from the local default branch's current HEAD. The user owns keeping their local default up to date.

## Memory Check (Resume Support)
```

`new_string`:
```
No `fetch`/`pull` is performed — the branch is created from the local default branch's current HEAD. The user owns keeping their local default up to date.

**PROCEDURE: Reconcile Memory ID & Branch (`<oldId>`, `<newId>`)**

Heals state that leaked under a provisional slug before the final `<ID>` was known (e.g. if the orchestrator drifted into the ticket-less path after a "Yes"). **Idempotent** — safe to call when nothing leaked. `<oldId>` is the deterministically-computed provisional slug; `<newId>` is the final ID.

1. **If `<oldId>` == `<newId>`** → return (no-op).
2. **Memory move:** if `.n1/memory/<oldId>/` exists AND `.n1/memory/<newId>/` does NOT → filesystem-move the directory `<oldId>/` → `<newId>/` (`.n1/` is gitignored, so a plain `mv` / `Move-Item`, NOT `git mv`). If `.n1/memory/<newId>/` already exists, skip the move and report — the `<newId>` memory is authoritative (resume/collision guard).
3. **Frontmatter fix:** if `.n1/memory/<newId>/overview.md` exists (true only when an overview was already written under the slug and just moved — in the clean path it does not exist yet), rewrite its `ticket: <oldId>` → `ticket: <newId>` and its `# <oldId>: <Title>` heading → `# <newId>: <Title>`.
4. **Branch rename:** compute `<oldBranch>` and `<newBranch>` from `git.branchPattern` (config). If a local branch `<oldBranch>` exists AND `<newBranch>` does NOT → `git branch -m <oldBranch> <newBranch>` (rename preserves commits; N1 has not pushed yet — push happens at PR time in `n1-pr`). If `<newBranch>` already exists, skip the rename — the subsequent Ensure Working Branch will check it out.
5. Report: "Migrated memory + branch `<oldId>` → `<newId>`."

## Memory Check (Resume Support)
```

- [ ] **Step 2: Verify the procedure is present and correctly placed**

Run: `Grep` for `PROCEDURE: Reconcile Memory ID & Branch` in `skills/n1-start/SKILL.md` with `output_mode: content`, `-n: true`.
Expected: one match, located after the Ensure Working Branch procedure and before `## Memory Check`.

- [ ] **Step 3: Verify idempotency + guards are spelled out**

Run: `Grep` for `Idempotent` and `resume/collision guard` and `git branch -m` in `skills/n1-start/SKILL.md`.
Expected: each pattern matches inside the new procedure (3 distinct lines).

- [ ] **Step 4: Commit**

```bash
git add skills/n1-start/SKILL.md
git commit -m "feat(n1-start): add Reconcile Memory ID & Branch procedure"
```

---

### Task 2: Add the ID-Final invariant before the ticket-creation block

**Files:**
- Modify: `skills/n1-start/SKILL.md` (immediately before `**Tracker ticket creation (brain dump and file modes):**`)

- [ ] **Step 1: Apply the edit**

Use `Edit` on `skills/n1-start/SKILL.md`.

`old_string`:
```
**Tracker ticket creation (brain dump and file modes):**

After product-analyst returns, if the input was a brain dump or file path, AND a tracker is configured (`tracker.mcp` is not null AND `tracker.operations.createIssue` exists):
```

`new_string`:
```
**ID-Final invariant.** No file may be written under `.n1/memory/` and no working branch may be created until `<ID>` is **final**: the ticket ID in ticket mode; the *created* ticket ID for brain-dump/file mode answered "Yes"; the slug only for brain-dump/file mode answered "No". Resolving the create-ticket decision (and, on "Yes", actually creating the ticket) therefore happens BEFORE the `ticket.md`/`overview.md` writes and branch creation below.

**Tracker ticket creation (brain dump and file modes):**

After product-analyst returns, if the input was a brain dump or file path, AND a tracker is configured (`tracker.mcp` is not null AND `tracker.operations.createIssue` exists):
```

- [ ] **Step 2: Verify the invariant is present**

Run: `Grep` for `ID-Final invariant` in `skills/n1-start/SKILL.md` with `output_mode: content`, `-n: true`.
Expected: one match, immediately preceding the `**Tracker ticket creation` line.

- [ ] **Step 3: Commit**

```bash
git add skills/n1-start/SKILL.md
git commit -m "docs(n1-start): add ID-Final invariant before ticket creation"
```

---

### Task 3: Add the "Yes" red-flag note and rewire item 4

**Files:**
- Modify: `skills/n1-start/SKILL.md` (the `**If 1 (Yes):**` block and its item 4)

- [ ] **Step 1: Add the red-flag note at the top of the "Yes" block**

Use `Edit` on `skills/n1-start/SKILL.md`.

`old_string`:
```
**If 1 (Yes):**
1. Extract the Title and structured content from the product-analyst output
```

`new_string`:
```
**If 1 (Yes):**

> ⚠ **Create the ticket now.** Creating the ticket via MCP is **mandatory and immediate** — it is the first action after the user answers "Yes". Do NOT proceed as if the run were ticket-less; the slug is adopted as `<ID>` ONLY on the explicit "No" path. (See the ID-Final invariant above.)

1. Extract the Title and structured content from the product-analyst output
```

- [ ] **Step 2: Rewire item 4 to compute slug → reconcile → adopt ticket ID**

Use `Edit` on `skills/n1-start/SKILL.md`.

`old_string`:
```
4. Use the returned ticket ID as the memory `<ID>` (replacing the slug). Now that the final `<ID>` is known, run **Ensure Working Branch(`<new ticket ID>`)** (see Working Branch above).
```

`new_string`:
```
4. The returned ticket ID is the final `<ID>`. Adopt it deterministically:
   1. Compute the provisional `<slug>` exactly as the "No" path would (description slug for brain dump, filename slug for file mode).
   2. Run **Reconcile Memory ID & Branch(`<slug>`, `<ticketID>`)** (see Working Branch above) — a no-op in the clean path; it moves any leaked slug memory folder into the ticket-ID folder and renames the slug branch if drift occurred.
   3. Set `<ID>` = `<ticketID>`, then run **Ensure Working Branch(`<ticketID>`)** (see Working Branch above).
```

- [ ] **Step 3: Verify both edits landed and the stale wording is gone**

Run: `Grep` for `Create the ticket now` and `Reconcile Memory ID & Branch\(` in `skills/n1-start/SKILL.md`.
Expected: red-flag note matches once; the `Reconcile Memory ID & Branch(` invocation matches once in item 4.

Run: `Grep` for `replacing the slug` in `skills/n1-start/SKILL.md`.
Expected: **no matches** (the stale instruction is fully removed).

- [ ] **Step 4: Commit**

```bash
git add skills/n1-start/SKILL.md
git commit -m "feat(n1-start): make ticket creation immediate on Yes and reconcile memory ID"
```

---

### Task 4: Add a traceability note to CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (Tracker Routing section, after the `assignToCreator` paragraph)

- [ ] **Step 1: Locate the anchor**

Run: `Grep` for `assignToCreator` in `CLAUDE.md` with `output_mode: content`, `-n: true`.
Expected: the paragraph beginning `When ` tracker.assignToCreator ` is not ` false ` … Configured by ` n1-init `.` — confirm its exact ending sentence before editing.

- [ ] **Step 2: Apply the edit**

Use `Edit` on `CLAUDE.md`.

`old_string`:
```
When `tracker.assignToCreator` is not `false` (default ON), `n1-start` assigns tickets it creates to the currently-authenticated tracker user via the `getCurrentUser` + `assign` operations. Creation only; non-fatal on failure; silently skipped when those operations are absent (legacy configs). Configured by `n1-init`.
```

`new_string`:
```
When `tracker.assignToCreator` is not `false` (default ON), `n1-start` assigns tickets it creates to the currently-authenticated tracker user via the `getCurrentUser` + `assign` operations. Creation only; non-fatal on failure; silently skipped when those operations are absent (legacy configs). Configured by `n1-init`.

On brain-dump/file runs where the user opts to create a ticket, `n1-start` adopts the **created ticket ID** as the per-ticket memory `<ID>` and branch name. An ID-Final invariant blocks any memory/branch write until that ID is known; if state was already written under the provisional slug, the idempotent `Reconcile Memory ID & Branch` procedure moves the memory folder and renames the branch (`git branch -m`) to the ticket-ID-based names.
```

- [ ] **Step 3: Verify**

Run: `Grep` for `adopts the \*\*created ticket ID\*\*` in `CLAUDE.md`.
Expected: one match in the Tracker Routing section.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(CLAUDE): document ticket-ID adoption and memory reconciliation"
```

---

### Task 5: End-to-end dogfood trace (verification)

No code to run — this task traces the edited instructions against the spec's scenarios to confirm they are internally consistent and unambiguous.

- [ ] **Step 1: Read the full edited Step 1 region**

`Read` `skills/n1-start/SKILL.md` from the `## Working Branch` heading through the end of `### 1. REQUIREMENTS ANALYSIS`.

- [ ] **Step 2: Trace the clean happy path**

Confirm by reading: brain-dump + "Yes" → ticket created immediately → `Reconcile(slug, ticketID)` is a no-op (no slug dir, no slug branch) → `<ID>` = ticketID → `Ensure Working Branch(ticketID)` creates the branch → `ticket.md`/`overview.md` written under `.n1/memory/<ticketID>/`.
Expected: every reference to `<ID>` after item 4 resolves to the ticket ID; no write occurs before item 4 completes.

- [ ] **Step 3: Trace the drift path**

Confirm by reading: if slug artifacts already exist when the ticket is created → `Reconcile` moves `.n1/memory/<slug>/` → `.n1/memory/<ticketID>/`, fixes `overview.md` frontmatter + heading, and runs `git branch -m <slugBranch> <ticketBranch>`.
Expected: the procedure's guards (target dir exists → skip; target branch exists → skip) are present and unambiguous.

- [ ] **Step 4: Trace the "No" path is unchanged**

Confirm by reading: brain-dump + "No" → slug adopted as `<ID>` → `Ensure Working Branch(slug)`; no Reconcile call; behavior identical to before this change.
Expected: the "No" block (lines around `**If 2 (No):**`) is untouched.

- [ ] **Step 5: Final spec-coverage check**

Re-read `docs/superpowers/specs/2026-06-01-n1-start-ticket-id-memory-path-design.md` sections 1-3 and the edge-case table. Confirm each row maps to text now present in `SKILL.md`.
Expected: no spec requirement without a corresponding instruction. If a gap is found, add the missing instruction and amend the relevant task's commit.

- [ ] **Step 6: Commit any trace-driven fixes (if needed)**

```bash
git add skills/n1-start/SKILL.md CLAUDE.md
git commit -m "fix(n1-start): tighten memory-ID reconciliation per dogfood trace"
```

(If the trace finds nothing to fix, skip this commit.)

---

## Self-Review

**Spec coverage:**
- §1 Prevention (invariant) → Task 2. ✓
- §1 Prevention ("Yes" hard gate) → Task 3 Step 1. ✓
- §2 Recovery (Reconcile procedure, 5 steps + guards) → Task 1. ✓
- §3 Wiring (slug → reconcile → adopt → ensure branch) → Task 3 Step 2. ✓
- Edge-case table → verified in Task 5 Steps 3-4; guards authored in Task 1. ✓
- Files touched (SKILL.md + CLAUDE.md) → Tasks 1-3 + Task 4. ✓
- Non-goal ("No → later Yes") → not implemented (correct). ✓

**Placeholder scan:** No "TBD"/"TODO"/"handle edge cases" — every edit gives exact `old_string`/`new_string`. ✓

**Type consistency:** The procedure name is `Reconcile Memory ID & Branch` in every reference (Task 1 definition, Task 3 invocation, Task 4 + Task 5 mentions). Parameters `(<oldId>, <newId>)` at definition; invoked as `(<slug>, <ticketID>)` — consistent role mapping (old=slug, new=ticketID). ✓
