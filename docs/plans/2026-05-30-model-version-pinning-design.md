# Model Version Pinning via Environment Variables

## Problem

When N1 skills spawn agents with `model: "opus"` or `model: "sonnet"`, Claude Code resolves these tier aliases to the latest available version for the user's provider. This means model versions change under you without notice — an agent that ran on Opus 4.6 yesterday may run on Opus 4.7 today, with different behavior characteristics.

For a development orchestration plugin that delegates critical work (analysis, review, implementation) to subagents, unpredictable model changes introduce risk: different reasoning patterns, different output formats, different failure modes.

## Research Basis

Key constraints discovered through Claude Code documentation and GitHub issue analysis:

- **Agent tool `model` parameter is enum-restricted** to `["sonnet", "opus", "haiku"]`. Full model IDs like `claude-opus-4-6` cannot be passed through it (Issue #34821, closed "not planned").
- **Agent frontmatter `model:` field** officially accepts full model IDs, but multiple issues report it being ignored in practice (Issues #44385, #5456). Unreliable as sole pinning mechanism.
- **Environment variables are the most reliable mechanism.** `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`, and `ANTHROPIC_DEFAULT_HAIKU_MODEL` remap what tier aliases resolve to. These are officially documented and recommended for deployments that need version control.
- **`CLAUDE_CODE_SUBAGENT_MODEL`** exists but is too broad — it overrides ALL subagents including non-N1 agents.

## Decision

Use `ANTHROPIC_DEFAULT_*_MODEL` environment variables in `.claude/settings.json` to pin model versions. This is the only mechanism that is both reliable and scoped correctly.

### What changes

| Component | Change |
|-----------|--------|
| `n1-init` skill | New "Model Version Pinning" step after agent model configuration |
| `.claude/settings.json` (target project) | `env.ANTHROPIC_DEFAULT_OPUS_MODEL` and `env.ANTHROPIC_DEFAULT_SONNET_MODEL` added |
| Agent frontmatter | No change — stays as tier aliases |
| Skills | No change — keep passing tier aliases via Agent tool |
| `n1.config.json` | No change |

### How it works

1. `n1-init` presents three options:
   - **(A) Pin to current versions** (recommended) — writes the model IDs that "opus" and "sonnet" currently resolve to
   - **(B) Custom versions** — user provides full model IDs per tier
   - **(C) Skip** — no env vars, aliases resolve to latest (default behavior)
2. Writes to `.claude/settings.json` in the target project, merging into existing `env` block without clobbering other keys.
3. On re-run, shows current pinned versions and offers to update or remove.

### Fallback

Automatic. If env vars are absent (not configured, or removed), tier aliases resolve to the platform default — latest version. No error handling needed in skills.

If a pinned version is retired by Anthropic, the API errors at subagent spawn time. Recovery: re-run `n1-init` or manually update `.claude/settings.json`.

### Validation

For custom input (option B), accept only model IDs matching `claude-{opus|sonnet|haiku}-*`. Reject bare tier names or invalid strings.

### Scope limits

- No haiku pinning — N1 doesn't use haiku-tier agents. Extends trivially if needed.
- No `CLAUDE_CODE_SUBAGENT_MODEL` — too broad, would affect non-N1 agents.
- No changes to agent frontmatter — frontmatter `model:` is unreliable per known bugs.
- No changes to `n1.config.json` — version pinning is a Claude Code concern, not an N1 config concern.

## Alternatives Considered

**Dual-layer config (N1 + env vars):** Store versions in `n1.config.json`, sync to `.claude/settings.json` via init. Rejected — two sources of truth with sync complexity, no benefit over direct env vars.

**Belt-and-suspenders (frontmatter + config + env vars):** Pin in all three places. Rejected — most complex, frontmatter is unreliable anyway, marginal benefit.

**Full model IDs in Agent tool:** Not possible — enum restriction, closed as "not planned."
