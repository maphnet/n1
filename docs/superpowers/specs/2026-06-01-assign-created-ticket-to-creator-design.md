# Auto-assign created tickets to the creator

**Date:** 2026-06-01
**Status:** Approved (design)
**Scope:** `n1-start` ticket creation, `n1-init` config presets, `n1.config.json` schema, docs

## Problem

When `n1-start` creates a tracker ticket from a brain dump or a file (i.e. N1 generates
the ticket rather than reading an existing one), the ticket is left unassigned. The user
who triggered the run — the person whose MCP session authenticated against the tracker —
should automatically become the assignee.

This applies **only to the creation path**. When the user passes an existing ticket ID,
N1 did not create the ticket and must not change its assignee.

## Goals

- Tickets N1 creates are auto-assigned to the currently-authenticated tracker user.
- Behaviour is controlled by a config flag, **default ON**.
- Tracker tool names stay out of the skill body — resolved through the `operations` map,
  consistent with N1's existing tracker-agnostic routing.
- Assignment never jeopardizes ticket creation: failures are non-fatal.
- Legacy `n1.config.json` files (without the new operations) keep working — assignment is
  silently skipped, no error, no nag.

## Non-Goals

- Re-assigning existing tickets (creation only, mirroring the `ticketTagging` rule).
- Assigning to anyone other than the authenticated user (no "assign to X" configuration).
- Any change to QA / review / PR / CI steps.

## Design

### 1. Config schema (`n1.config.json`)

Two additions to the `tracker` block.

**`operations` map** gains two verbs:

| Operation | YouTrack | Jira |
|-----------|----------|------|
| `getCurrentUser` | `get_current_user` | `atlassianUserInfo` |
| `assign` | `change_issue_assignee` | `editJiraIssue` |

**`assignToCreator`** — boolean, sibling of `mcp`/`prefix`/`projectKey`/`operations`.
- Default semantics: **ON**. Absent, `null`, or non-boolean → treated as `true`.
- Only `false` disables the behaviour.

Example (YouTrack):

```json
"tracker": {
  "mcp": "youtrack",
  "prefix": "N1",
  "projectKey": "N1",
  "assignToCreator": true,
  "operations": {
    "readTicket": "get_issue",
    "getComments": "get_issue_comments",
    "moveStatus": "update_issue",
    "addComment": "add_issue_comment",
    "search": "search_issues",
    "createIssue": "create_issue",
    "getCurrentUser": "get_current_user",
    "assign": "change_issue_assignee"
  },
  "statuses": { "...": "..." }
}
```

### 2. `n1-start` flow change

In the **"If 1 (Yes)"** ticket-creation branch, insert an **"Assign to creator"** step
after step 4 (final `<ID>` known, working branch ensured) and before the success report.

**Gate.** Run the step only if ALL hold:
- `tracker.assignToCreator !== false`
- `tracker.operations.getCurrentUser` is present
- `tracker.operations.assign` is present

If any gate fails, skip the step silently (no message) and proceed to the report. This is
what makes legacy configs a graceful no-op.

**Procedure.**

1. **Resolve current user** — call `mcp__<tracker.mcp>__<operations.getCurrentUser>`.
   - YouTrack: read `login` from the response.
   - Jira: read the account id from the response (`account_id`). Reuse the `cloudId`
     already resolved during creation.
2. **Assign** — call `mcp__<tracker.mcp>__<operations.assign>`.
   - YouTrack: `change_issue_assignee(issueId: <ID>, assigneeLogin: <login>)`
   - Jira: `editJiraIssue(cloudId, issueIdOrKey: <ID>, assignee_account_id: <accountId>)`
3. On success, fold assignment into the existing report line:
   `Created ticket **[<ID>](<url>)** (assigned to you): <title>`

### 3. Failure handling (non-fatal)

If `getCurrentUser` or `assign` returns an error (insufficient permission, user not
resolvable, MCP error), **do not roll back creation**. Emit an inline warning and continue
the pipeline normally:

```
⚠ Ticket created but could not auto-assign (<reason>); assign it manually.
```

The success report still shows the created ticket; only the "(assigned to you)" suffix is
omitted. Distinction from the silent-skip case: silent skip = feature unavailable/disabled
(no ops, flag off); warning = feature attempted and failed.

### 4. `n1-init` changes

- Add `getCurrentUser` and `assign` to **both** the Jira and YouTrack preset operations
  maps (matching the table in §1).
- Add `"assignToCreator": true` to both presets.
- Add one wizard prompt:
  `Auto-assign tickets N1 creates to you? (Y/n)` → writes `tracker.assignToCreator`
  (Yes → `true`, No → `false`). Default Yes on empty input.

### 5. Documentation

- **CLAUDE.md** — Tracker Routing section: add `getCurrentUser` / `assign` to the key
  operations, and document `assignToCreator` (default ON, creation only) next to the
  existing `ticketTagging` description.
- **README.md** — brief mention in the tracker/config overview.

## Backward compatibility

Existing `n1.config.json` files lack `getCurrentUser`/`assign`. The §2 gate sees the
missing operations and silently skips assignment — no error, no behaviour change — until
the user re-runs `/n1:init`. The `assignToCreator` flag defaulting to ON has no effect
without the operations present, so there is no surprise activation on old projects.

## Testing

Dogfood on a scratch project per CLAUDE.md (`claude --plugin-dir C:\Dev\n1`):

1. **YouTrack, flag default** — brain-dump create → ticket assigned to current user;
   report shows "(assigned to you)".
2. **Jira, flag default** — brain-dump create → assignee set via `editJiraIssue`.
3. **Flag false** — set `assignToCreator: false` → ticket created, not assigned, no warning.
4. **Legacy config** — remove `getCurrentUser`/`assign` ops → ticket created, assignment
   silently skipped, no warning.
5. **Assign failure** — simulate a permission error → ticket created, ⚠ warning shown,
   pipeline continues.
6. **Existing-ticket-ID mode** — confirm assignment step never runs.
