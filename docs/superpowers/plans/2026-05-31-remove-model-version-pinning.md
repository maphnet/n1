# Remove Model Version Pinning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop N1 from dictating Claude model *versions* by removing the model-version-pinning feature from `n1-init`, while keeping per-agent tier selection intact.

**Architecture:** Pure deletion within a single Markdown skill file (`skills/n1-init/SKILL.md`). Three coupled removals — the pinning prompt section, the `.claude/settings.json` env-var write block, and the confirm-summary line — land in one commit so the skill is never left internally inconsistent. No code, no tests, no other files. Existing user projects with pinned env vars are left completely untouched.

**Tech Stack:** Markdown (Claude Code skill file). Verification via Grep + Read. Git for commit.

**Spec:** `docs/superpowers/specs/2026-05-31-remove-model-version-pinning-design.md`

---

### Task 1: Remove model version pinning from n1-init

**Files:**
- Modify: `skills/n1-init/SKILL.md` (three deletions)

This is a Markdown skill file with no automated test harness. The "test" step is a Grep that must currently MATCH (proving the target text exists) and must return NOTHING after the edits (proving clean removal). Do the three deletions, then verify, then commit — all in this one task.

- [ ] **Step 1: Confirm the target text exists (test should currently find matches)**

Run:
```bash
grep -nE "ANTHROPIC_DEFAULT|Model Version Pinning|Model pinning:" skills/n1-init/SKILL.md
```
Expected: several matching lines — the `## Model Version Pinning` heading, the two `ANTHROPIC_DEFAULT_*_MODEL` references in both the pinning section and the settings.json write block, and the `Model pinning:` confirm-summary line. (This proves the feature is present before removal.)

- [ ] **Step 2: Read the file to anchor the three deletions**

Read `skills/n1-init/SKILL.md` and locate these three regions (line numbers approximate — match on text):

1. The entire section that begins with the heading `## Model Version Pinning` and ends immediately before the next heading `## Write Configuration and Structure`. (Includes the "Pin specific model versions…" 1/2/3 prompt, the `### If 1 (Pin to current):`, `### If 2 (Custom):`, `### If 3 (Skip):` branches, and the `### On reconfiguration (n1-init re-run):` block.)
2. Inside the `## Write Configuration and Structure` section, the block that begins with the line ``**`.claude/settings.json`** — model version pinning (only if user chose option 1 or 2 above):`` and ends with the closing fence of its example JSON (the `}` / ` ``` ` showing `ANTHROPIC_DEFAULT_OPUS_MODEL` / `ANTHROPIC_DEFAULT_SONNET_MODEL`), up to (but not including) the next block ``**`.gitignore`** — append `.n1/`…``.
3. In the `## Confirm` summary block, the single line:
   `Model pinning: claude-opus-4-6, claude-sonnet-4-6 / not configured`

- [ ] **Step 3: Delete region 1 — the "Model Version Pinning" section**

Remove everything from the `## Model Version Pinning` heading through the blank line just before `## Write Configuration and Structure`. After this edit, the `## Agent Model Configuration` section's defaults block must be followed directly (one blank line) by `## Write Configuration and Structure`.

Use an Edit whose `old_string` is the full `## Model Version Pinning` section text (read it verbatim in Step 2, including the nested fenced prompt blocks) and whose `new_string` is empty — i.e. collapse the two surrounding blank lines into one so no double blank line remains.

- [ ] **Step 4: Delete region 2 — the `.claude/settings.json` write block**

Remove the `**`.claude/settings.json`** — model version pinning…` paragraph, its numbered steps (1. Read existing… through 4. Write back…), the `Example result:` label, and the example JSON fenced block containing the two `ANTHROPIC_DEFAULT_*_MODEL` keys. After this edit, the `**Directory structure:**` block (ending in the `mkdir -p` fenced block) must be followed directly (one blank line) by the `**`.gitignore`** — append `.n1/`…` block.

- [ ] **Step 5: Delete region 3 — the confirm-summary line**

In the `## Confirm` summary fenced block, delete the single line:
```
Model pinning: claude-opus-4-6, claude-sonnet-4-6 / not configured
```
After this edit, the `Ticket tagging: …` line must be followed directly by the blank line and then `Created:` (no `Model pinning:` line between them).

- [ ] **Step 6: Verify clean removal (test should now find nothing)**

Run:
```bash
grep -nEi "ANTHROPIC_DEFAULT|Model Version Pinning|Model pinning:|pin (specific|to current|model)" skills/n1-init/SKILL.md
```
Expected: NO output (exit code 1). This confirms every pinning reference is gone.

- [ ] **Step 7: Verify the kept content is intact**

Run:
```bash
grep -nE "## Agent Model Configuration|## Write Configuration and Structure|\"models\":|## Confirm" skills/n1-init/SKILL.md
```
Expected: all four still present — the per-agent tier feature (`## Agent Model Configuration`, the `"models":` block in the `n1.config.json` example) and the structural sections are untouched.

- [ ] **Step 8: Verify no stray double blank lines were introduced**

Read the three edited regions in `skills/n1-init/SKILL.md` and confirm:
- `## Agent Model Configuration` defaults block → one blank line → `## Write Configuration and Structure`.
- `**Directory structure:**` `mkdir` fence → one blank line → `**`.gitignore`**` block.
- `Ticket tagging:` line → directly followed by blank line → `Created:` inside the Confirm summary.

Fix any double blank lines inline if present.

- [ ] **Step 9: Commit**

```bash
git add skills/n1-init/SKILL.md
git commit -m "feat(n1-init): remove model version pinning; defer model versions to Claude Code"
```

---

### Task 2: Repo-wide confirmation

**Files:**
- Read-only verification across the repo.

- [ ] **Step 1: Confirm n1-init is the only file that ever referenced pinning**

Run:
```bash
grep -rnEi "ANTHROPIC_DEFAULT|model version pinning|Model pinning:" --include="*.md" --include="*.json" .
```
Expected: NO output. (Per the spec verification step — confirms no README, CLAUDE.md, or config example still mentions version pinning. The design doc itself describes the *removed* feature in prose but must not reintroduce the literal env-var/pinning tokens that this grep targets; if the spec file matches, that is acceptable documentation of the change — note it and move on.)

- [ ] **Step 2: Confirm tier selection still works end-to-end in the docs**

Run:
```bash
grep -rnE "models\.<agent|Model Resolution|frontmatter default" skills/
```
Expected: the "Model Resolution" sections in `n1-start`, `n1-review`, `n1-pr`, `n1-ci` still present — proving the kept tier mechanism is intact and referenced.

---

## Self-Review

**Spec coverage:**
- "Delete the Model Version Pinning section" → Task 1, Step 3. ✓
- "Delete the `.claude/settings.json` env-var write block" → Task 1, Step 4. ✓
- "Remove the Model pinning: confirm-summary line" → Task 1, Step 5. ✓
- "Per-agent tier selection / Model Resolution stays untouched" → Task 1 Step 7 + Task 2 Step 2 verify it remains. ✓
- "Existing projects hands-off / no migration" → covered by omission: no step reads or writes user `.claude/settings.json`; the design's hands-off decision needs no code. ✓
- "Verification: grep finds none of the pinning tokens" → Task 1 Step 6, Task 2 Step 1. ✓

**Placeholder scan:** No TBD/TODO. Each deletion step names exact anchor text and the required post-edit adjacency. Verification steps give exact commands and expected output. ✓

**Type consistency:** N/A (no code symbols). Anchor strings (`## Model Version Pinning`, `ANTHROPIC_DEFAULT_OPUS_MODEL`, `Model pinning:`) are used identically across the plan and match the spec. ✓
