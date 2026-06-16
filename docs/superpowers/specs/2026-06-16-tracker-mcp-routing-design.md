# Tracker MCP Routing Fix

## Problem

Two distinct failure modes in tracker MCP routing during N1 skill execution:

1. **Wrong tracker type** — orchestrator uses YouTrack operations when Jira is configured (or vice versa). Root cause: the skill spec uses natural language cues ("For Jira only") without explicit conditions, forcing the model to infer the branch logic.

2. **Wrong MCP server instance** — orchestrator picks the first available Jira MCP server from the tool list (e.g., `jira-ideomllc`) instead of the one specified in `tracker.mcp` (e.g., `jira-velosity`). Root cause: the model reads the config value early in skill execution but loses track of it by the time it constructs the actual MCP tool call — then falls back to pattern-matching against whatever server names it sees in its tool list.

## Approach

Three coordinated changes that address both root causes:

1. **Config schema** — add `tracker.type` field for unambiguous conditional branching
2. **Session context injection** — session-start hook injects tracker routing into session context so the correct MCP server name is always in the model's attention window
3. **Explicit conditionals** — replace all ambiguous "For Jira only" / "For YouTrack" in skill specs with testable `tracker.type` conditions

## Design

### 1. Config Schema: Add `tracker.type`

Add a `type` field to the `tracker` block in `n1.config.json`:

```json
{
  "tracker": {
    "type": "jira",
    "mcp": "jira-velosity",
    "prefix": "PROJ",
    "projectKey": "PROJ",
    "operations": { ... }
  }
}
```

- `type` is `"jira"` or `"youtrack"` — set by n1-init during setup.
- Separates "which tracker kind" (for conditional branching) from "which MCP server name" (for tool call construction).
- When `tracker.mcp` is `null` (no tracker), `type` is absent.

### 2. Session-Start Hook Enhancement

**File:** `hooks/session-start.sh`

Current behavior: outputs a one-liner ("N1 is configured for this project...").

New behavior: when configured, reads `n1.config.json` and injects a concise routing directive into session context.

**Output format:**

```
N1 is configured for this project. For task work, PR creation, and code review — always prefer N1 skills (/n1:n1-start, /n1:n1-pr, /n1:n1-review, /n1:n1-ci) over alternatives.

TRACKER ROUTING (from .n1/n1.config.json — authoritative, do not override):
- Type: jira
- MCP server: jira-velosity
- All tracker MCP tool calls MUST use prefix: mcp__jira-velosity__
- NEVER use any other MCP server (e.g. jira-ideomllc, plugin_atlassian_atlassian, youtrack) for tracker operations
- Operations: readTicket=jira_get, moveStatus=jira_put, addComment=jira_post, ...
```

**Design choices:**

- **Operations map included** — model doesn't need to read the config file to know tool names. Reduces context distance.
- **Negative instruction** — explicitly names other available MCP servers to NOT use. An explicit "never use X" is stronger than just "use Y" when the model can see all servers in its tool list.
- **"Authoritative, do not override"** — prevents the model from second-guessing the config.
- Uses `jq` for JSON extraction, with grep/sed fallback. If config parse fails entirely, falls back to the current one-liner behavior.
- When `tracker.mcp` is `null`, only the first line is output (no routing block).
- Error tracking routing is also included if configured — same pattern.

**Negative instruction:** A generic "NEVER use any other MCP server for tracker operations, even if other tracker-like servers are visible in the tool list" line. No hardcoded server names — MCP server names are user-configured and should not be baked into the hook.

### 3. Explicit Conditionals in n1-start Skill Spec

Six locations in `skills/n1-start/SKILL.md` need fixing. Every "For Jira only" / "**YouTrack:**" / "**Jira:**" is replaced with an explicit condition on `tracker.type`.

**3a. Step 1, Ticket mode (line 151)** — cloudId resolution

Before: `"For Jira only: if enrichmentEnabled is true, resolve cloudId via..."`
After: `"If tracker.type == "jira" AND enrichmentEnabled is true: resolve cloudId via mcp__<tracker.mcp>__getAccessibleAtlassianResources. Use exactly mcp__<tracker.mcp>__ as the tool prefix — the value from config, not from the tool list."`

**3b. Ticket creation (lines 211-220)** — create paths

Before: `"**YouTrack:** Call..." / "**Jira:** First resolve cloudId..."`
After: `"If tracker.type == "jira": ... Else (tracker.type == "youtrack"): ..."`

**3c. getCurrentUser response parsing (lines 228-229)**

Before: `"**YouTrack:** take login..." / "**Jira:** take account_id..."`
After: `"If tracker.type == "jira": take account_id... Else: take login..."`

**3d. Assign call (lines 230-232)**

Same pattern — explicit `tracker.type` condition on parameter shapes.

**3e. Post-brainstorm enrichment editTicket (lines 393-395)**

Before: `"**Jira:** with cloudId..." / "**YouTrack:** with issueId..."`
After: `"If tracker.type == "jira": with cloudId, issueIdOrKey... Else: with issueId..."`

**3f. Post-brainstorm addComment (lines 410-412)**

Same pattern — `tracker.type` condition on `body` vs `text` parameter name.

**Additionally**, at each MCP call site, add a one-line reinforcement: `"Use exactly mcp__<tracker.mcp>__ as the tool prefix — the value from config, not from the tool list."` Low-cost instruction that combats context-distance drift.

**No changes needed** to `agents/product-analyst.md` — it already receives `trackerMcp` and `operations` as explicit parameters and constructs calls correctly.

### 4. n1-init Changes

**4a. Set `tracker.type` in config templates**

- Jira path: add `"type": "jira"` to the tracker block
- YouTrack path: add `"type": "youtrack"` to the tracker block
- None path: no change

**4b. Session reload instruction**

After the final "N1 is ready" summary, add:

```
To activate tracker routing, reload the session now: type /clear or restart Claude Code.
(This lets N1's session hook inject the tracker config into context.)
```

`/clear` is the lightest-weight trigger — it resets conversation but fires all SessionStart hooks, so the new config gets picked up immediately. This is a one-time cost at setup. On reconfiguration, the same instruction appears if tracker settings changed.

## Files Changed

| File | Change |
|------|--------|
| `hooks/session-start.sh` | Read config, inject tracker routing directive into session context |
| `skills/n1-start/SKILL.md` | Replace 6 ambiguous conditionals with explicit `tracker.type` checks; add MCP prefix reinforcements |
| `skills/n1-init/SKILL.md` | Add `tracker.type` to Jira/YouTrack config templates; add session reload instruction |

## Not In Scope

- **n1-init MCP server discovery** — currently n1-init hardcodes `mcp__plugin_atlassian_atlassian__*` for Jira. Users with non-standard Jira MCP server names (like `jira-velosity`) may need manual config editing. This is a separate improvement.
- **n1-pr and n1-ci skill specs** — these also have tracker MCP calls but inherit the same patterns. They should be audited in a follow-up pass using the same explicit-conditional pattern.
- **Runtime validation** — the hook could validate that the configured MCP server actually exists in the session's tool list. Deferred to avoid complexity.
