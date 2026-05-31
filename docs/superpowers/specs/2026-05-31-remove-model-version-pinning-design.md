# Remove Model Version Pinning from N1

**Date:** 2026-05-31
**Status:** Approved
**Scope:** `skills/n1-init/SKILL.md` only

## Problem

N1 currently has two independent model mechanisms:

1. **Per-agent tier selection** — the `models` section in `n1.config.json` plus
   agent frontmatter `model:` lines, choosing `opus`/`sonnet`/`haiku` per agent
   role (e.g. `developer` = opus, `qa-engineer` = sonnet).
2. **Model version pinning** — `n1-init` asks whether to pin exact model
   versions and writes `ANTHROPIC_DEFAULT_OPUS_MODEL` /
   `ANTHROPIC_DEFAULT_SONNET_MODEL` into `.claude/settings.json`.

Mechanism (2) is the problem. The pinned defaults (`claude-opus-4-6`,
`claude-sonnet-4-6`) are already stale relative to the current platform model
(`claude-opus-4-8`), so every fresh `n1-init` that accepts the "recommended"
option locks the project to an outdated model. N1 should not dictate model
*versions* at all — that decision belongs to the latest platform default or to
whatever the user has configured in Claude Code.

## Goal

N1 declares a model **tier** per agent and lets Claude Code resolve that tier to
whatever version is current or configured in the harness. N1 never writes
`ANTHROPIC_DEFAULT_*_MODEL`.

## Decisions

- **Scope:** Remove version pinning *only*. Per-agent tier selection stays.
  (Tiers are a capability/cost choice per role; versions are a platform concern.)
- **Existing projects:** Fully hands-off. If a project already has
  `ANTHROPIC_DEFAULT_*_MODEL` in `.claude/settings.json` from a previous N1
  version, N1 leaves it completely untouched — no read, no write, no warning, no
  migration. Those vars become purely the user's own setting.
- **Approach:** Clean deletion of the feature (not "keep but default to skip",
  not "actively clean up existing pins").

## Changes

All changes are in `skills/n1-init/SKILL.md`.

1. **Delete the "Model Version Pinning" section** — the `1/2/3` prompt
   (Pin to current / Custom / Skip), all three branches, and the "On
   reconfiguration (n1-init re-run)" handler that shows and offers to
   keep/update/remove current pins. (Currently ~lines 376–426.)

2. **Delete the `.claude/settings.json` model-pinning write block** in the
   "Write Configuration and Structure" section — the steps that read
   `.claude/settings.json`, set the two env vars in the `env` block, and the
   example result JSON. (Currently ~lines 476–491.) N1 no longer creates or
   touches `.claude/settings.json` for model purposes.

3. **Remove the "Model pinning:" line** from the final confirm summary.
   (Currently ~line 510.)

## What Stays Untouched

- Per-agent **tier** selection: the `models` section in `n1.config.json`, the
  "Agent Model Configuration" prompt in `n1-init`, and agent frontmatter
  `model:` lines.
- The "Model Resolution" logic in `n1-start`, `n1-review`, `n1-pr`, and `n1-ci`
  (reads `models.<agent>` tier, falls back to frontmatter default). Tiers are
  not versions.

## Net Effect

- Fresh `n1-init` runs produce no model-version env vars and never modify
  `.claude/settings.json` for model reasons.
- Tier aliases (`opus`/`sonnet`/`haiku`) resolve to the platform's
  latest/configured model automatically.
- One fewer prompt in the setup wizard.
- No more stale `claude-opus-4-6` pins shipped to new projects.

## Verification

- Grep the repo for `ANTHROPIC_DEFAULT`, `pinning`, `pin`, `model version`:
  after the change, `skills/n1-init/SKILL.md` should contain none of them.
- The `models` tier section and "Model Resolution" sections remain intact and
  referenced by the pipeline skills.
- A dry read of `n1-init` shows no remaining step that writes
  `.claude/settings.json`.

## Out of Scope

- No changes to agent frontmatter, the `models` config section, or any pipeline
  skill's Model Resolution.
- No automated migration or cleanup of existing pinned env vars in user projects.
