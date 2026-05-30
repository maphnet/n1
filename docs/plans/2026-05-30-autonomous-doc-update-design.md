# Autonomous Documentation Update

## Overview

Extend the tech-writer agent with a new Phase 1 that detects and updates stale in-repo documentation after the review/fix cycle, before PR creation. The agent analyzes the git diff against existing docs, surgically updates sections that reference changed code, and commits the changes as a separate atomic commit. Phase 2 (existing PR generation) then runs with the updated diff.

No new agents, skills, or hooks. Four files modified.

## Pipeline Placement

Steps 8-10 in n1-start become:

```
Step 8:  Fix cycle (existing, unchanged)
              ↓ code finalized
Step 9:  DOCS + PR (extended tech-writer, single agent spawn)
           Phase 1: Scan docs → update stale sections → commit
           Phase 2: Generate PR title + body (existing behavior)
Step 10: Finalize memory (existing, unchanged)
```

Phase 1 and Phase 2 share the same agent context — one spawn, one pass over the diff and memory files.

## Phase 1: Doc Discovery & Update

### Input

- Git diff: `git diff <base>...HEAD`
- Memory files: `implementation.md`, `review.md`
- Repo file tree
- Optional config: `docs.include`, `docs.exclude` from `n1.config.json`

### Smart Scan Algorithm

1. **Extract change footprint** — From the diff, collect all changed file paths and group by directory.
2. **Locate nearby docs** — For each changed directory, walk up to the repo root looking for `README.md` or `*.md` files in the same or parent directories.
3. **Always include root** — `README.md` at repo root is always checked.
4. **Apply config overrides** — If `docs.include` array exists, add those paths to the scan. If `docs.exclude` exists, remove matching paths from the scan.
5. **Cross-reference** — For each discovered doc, compare its content against the diff. Look for references to changed functions, flags, config keys, CLI commands, API endpoints, file paths, or module names that no longer match the code.

### Confidence-Based Action

| Confidence | Example | Action |
|-----------|---------|--------|
| High | Doc references a renamed flag, deleted endpoint, or moved file path | Update silently |
| Low | Doc describes a workflow that was partially changed | Update but flag in PR body under "Review Notes" |
| None | Doc section seems tangentially related but mapping is unclear | Skip, note in PR body as "may need manual update" |

### Commit

After all updates, stage changed doc files and commit:

```
docs: update documentation for <feature/ticket>
```

If no docs are stale, Phase 1 produces no commit and moves directly to Phase 2.

## Phase 2: PR Generation (Extended)

Existing behavior unchanged, with two additions:

1. **Updated diff context** — Doc changes are committed, so `git diff --stat` includes them in the PR file list.
2. **New "Documentation" section in PR body:**

```markdown
## Documentation
- **Updated:** README.md — updated CLI flags section (high confidence)
- **Updated:** docs/api.md — revised authentication endpoint (high confidence)
- **Flagged:** docs/architecture.md — deployment section may be affected (low confidence, updated with flag)
- **Needs review:** docs/migration.md — possibly stale but unclear mapping (skipped)
```

If Phase 1 found nothing to update, the Documentation section is omitted.

## Entry Point Behavior

| Entry Point | Phase 1 Behavior |
|-------------|-----------------|
| `n1-start` (full pipeline) | Fully autonomous — no user prompt |
| `n1-pr` (standalone) | Ask user before updating: "Found stale documentation — update these files? (yes/skip)" |
| `n1-pr` with explicit "update docs" instruction | Autonomous (skip prompt) |
| `n1-pr` with `docs.autoUpdate: true` in config | Autonomous (skip prompt) |

## Configuration

New optional `docs` section in `n1.config.json`:

```json
{
  "docs": {
    "include": ["docs/api.md", "CONTRIBUTING.md"],
    "exclude": ["CHANGELOG.md", "docs/legacy/**"],
    "autoUpdate": false
  }
}
```

All fields optional. If `docs` section is omitted entirely, smart scan runs with defaults (locality-based discovery, no overrides, prompt in standalone mode).

## Agent Changes: tech-writer.md

- **Tools:** Add `Edit, Write, Grep, Glob` to the existing `Read` tool list
- **Model:** Stays sonnet by default
- **Prompt:** Two-phase instructions with clear separator. Phase 1 runs first (scan, update, commit). Phase 2 runs second (PR content generation).

## Memory Changes

`overview.md` gains a `docs_updated` field at Step 10 finalization:

```yaml
docs_updated:
  - file: README.md
    confidence: high
    action: updated
  - file: docs/migration.md
    confidence: none
    action: skipped
```

## Files to Modify

1. `agents/tech-writer.md` — Add Phase 1 instructions, add Write/Edit/Grep/Glob tools
2. `skills/n1-start/SKILL.md` — Update Step 9 to include Phase 1 before Phase 2
3. `skills/n1-pr/SKILL.md` — Add Phase 1 with user confirmation gate
4. `CLAUDE.md` — Update architecture table and per-ticket memory docs

## Files Unchanged

No new agents, no new skills, no new hooks, no new memory files.
