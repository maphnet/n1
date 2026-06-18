# Design: n1-init .gitignore Configuration Step

## Problem

`n1-init` unconditionally appends `.n1/` to the project's `.gitignore` on every run. This has two issues:

1. **No global option** — users running N1 across multiple repos must gitignore `.n1/` in each one individually.
2. **No duplicate check** — re-running the wizard appends duplicate entries.
3. **No transparency** — if `.n1/` is already gitignored (globally or locally), the user isn't informed.

## Solution

Replace the unconditional `.gitignore` append in Step 15 (Write Files) with a detection-first flow that checks existing coverage and offers the user a choice.

## Detection Logic

Three-phase check, executed in order:

1. **Global check:** Run `git config --global core.excludesFile`. If set, read that file and check for a `.n1` pattern (`.n1/` or `.n1`).
2. **Project check:** Read `.gitignore` in project root, check for a `.n1` pattern.
3. **Branch on result:**
   - Found globally → inform: `.n1/ is already gitignored globally via <path>.` → skip
   - Found in project → inform: `.n1/ is already gitignored in this project's .gitignore.` → skip
   - Not found anywhere → prompt user

## User Prompt (when not found)

Standard wizard question format:

```
.n1/ directory is not gitignored. Where would you like to add it?
1 — Globally (user-scoped ~/.gitignore_global, applies to all repos)
2 — Project-level (.gitignore in this repo)
```

### Path 1: Global

1. Check `git config --global core.excludesFile`.
2. **If set** → append `.n1/` to that file (with duplicate check and comment header), inform user.
3. **If not set** → sub-prompt:

```
No global gitignore is configured (core.excludesFile is unset).
Want me to create ~/.gitignore_global and configure git to use it?
1 — Yes
2 — No (fall back to project-level)
```

   - **Yes** → create `~/.gitignore_global`, run `git config --global core.excludesFile ~/.gitignore_global`, append `.n1/` entry.
   - **No** → fall back to project-level append.

### Path 2: Project-level

Append `.n1/` to `.gitignore` in project root (same as current behavior, but with duplicate check).

## File Write Format

Both paths use the same append pattern:

```
<blank line>
# N1 plugin state
.n1/
```

Idempotent: check if `.n1/` or `.n1` entry already exists before writing. Skip if present.

## Scope of Changes

- **Modified:** `skills/n1-init/SKILL.md` — replace the unconditional `.gitignore` append block in Step 15 with the new detection + prompt flow.
- **No config changes** — this is a git-level concern, not stored in `n1.config.json`.
- **No new files** — logic lives inline in the existing skill.

## Edge Cases

| Case | Behavior |
|------|----------|
| `.gitignore` doesn't exist in project | Create it if project-level is chosen |
| Global excludes file doesn't exist but `core.excludesFile` is set | Create the file, append entry |
| `.n1/` already in both global and project | Report global match (checked first), skip |
| Re-running wizard after prior setup | Detection finds existing entry, informs, skips |
| User has `.n1` (no trailing slash) in gitignore | Treated as covered — pattern check matches both forms |
