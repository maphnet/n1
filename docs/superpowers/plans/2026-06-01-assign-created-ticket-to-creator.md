# Auto-assign Created Tickets to the Creator — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When `n1-start` creates a tracker ticket from a brain dump or file, auto-assign it to the currently-authenticated tracker user, controlled by a config flag defaulting ON.

**Architecture:** Approach A — uniform "create then assign". Two new verbs are added to the tracker `operations` map (`getCurrentUser`, `assign`) so the skill body never hardcodes tracker tool names. `n1-start` gains a gated "Assign to creator" step after ticket creation; `n1-init` seeds the new operations and a new `assignToCreator` flag into both tracker presets and asks one wizard question. Failures are non-fatal; legacy configs missing the operations are silently skipped.

**Tech Stack:** Markdown skills (`skills/*/SKILL.md`), JSON config (`.n1/n1.config.json`), Bash plugin — no test runner. Verification is by grep assertions on edited files plus manual dogfooding (`claude --plugin-dir C:\Dev\n1`).

**Spec:** `docs/superpowers/specs/2026-06-01-assign-created-ticket-to-creator-design.md`

---

## File Structure

| File | Change | Responsibility |
|------|--------|----------------|
| `skills/n1-init/SKILL.md` | Modify | Seed `getCurrentUser`/`assign` ops + `assignToCreator` into Jira & YouTrack presets; add wizard prompt + reconfig flow; add flag to final assembly block |
| `skills/n1-start/SKILL.md` | Modify | Add gated "Assign to creator" step in the "If 1 (Yes)" ticket-creation branch; fold "(assigned to you)" into the report |
| `CLAUDE.md` | Modify | Document new operations + `assignToCreator` in Tracker Routing |
| `README.md` | Modify | One-line mention in tracker/config overview |

Order: config presets first (Task 1–2), then the consumer flow (Task 3), then docs (Task 4–5), then dogfood (Task 6). No code depends on another task's runtime output, but the `operations` keys defined in Task 1 are referenced verbatim in Task 3 — keep the names identical.

---

## Task 1: Seed new operations + flag into n1-init presets

**Files:**
- Modify: `skills/n1-init/SKILL.md` (Jira preset ~`148-162`, YouTrack preset ~`200-221`)

- [ ] **Step 1: Add the two operations and `assignToCreator` to the Jira preset**

Find the Jira `Set config:` JSON block (the one with `"mcp": "plugin_atlassian_atlassian"`). Replace its `operations` object and add `assignToCreator` so the `tracker` block reads:

```json
{
  "tracker": {
    "mcp": "plugin_atlassian_atlassian",
    "prefix": "<from project selection>",
    "projectKey": "<from project selection>",
    "assignToCreator": true,
    "operations": {
      "readTicket": "getJiraIssue",
      "getTransitions": "getTransitionsForJiraIssue",
      "moveStatus": "transitionJiraIssue",
      "addComment": "addCommentToJiraIssue",
      "search": "searchJiraIssuesUsingJql",
      "createIssue": "createJiraIssue",
      "getCurrentUser": "atlassianUserInfo",
      "assign": "editJiraIssue"
    },
    "statuses": {
      "todo": "<detected or manual>",
      "inProgress": "<detected or manual>",
      "codeReview": "<detected or inProgress fallback>"
    }
  }
}
```

- [ ] **Step 2: Add the two operations and `assignToCreator` to the YouTrack preset**

Find the YouTrack `Set config:` JSON block (the one with `"mcp": "youtrack"`). Replace its `operations` object and add `assignToCreator` so the `tracker` block reads:

```json
{
  "tracker": {
    "mcp": "youtrack",
    "prefix": "<from project selection>",
    "projectKey": "<from project selection>",
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
    "statuses": {
      "todo": "<detected or manual>",
      "inProgress": "<detected or manual>",
      "codeReview": "<detected or inProgress fallback>"
    }
  }
}
```

- [ ] **Step 3: Verify both presets carry the new keys**

Run:
```bash
grep -c "getCurrentUser" skills/n1-init/SKILL.md
grep -c "\"assign\":" skills/n1-init/SKILL.md
grep -c "assignToCreator" skills/n1-init/SKILL.md
```
Expected: first two print `2` (Jira + YouTrack); `assignToCreator` prints `2` now (will rise in Task 2).

- [ ] **Step 4: Commit**

```bash
git add skills/n1-init/SKILL.md
git commit -m "feat(n1-init): seed getCurrentUser/assign ops and assignToCreator into tracker presets"
```

---

## Task 2: Add the n1-init wizard prompt + reconfig flow + assembly entry

**Files:**
- Modify: `skills/n1-init/SKILL.md` (new section after "Ticket Tagging Configuration", ends ~`309`; assembly block ~`383-391`)

- [ ] **Step 1: Add a new "Assign to Creator Configuration" section**

Insert the following section immediately AFTER the Ticket Tagging Configuration section (right before `## Review Configuration`):

```markdown
## Assign to Creator Configuration

Ask whether N1 should auto-assign tickets it creates to the user running it. **Default is Yes.**

```
Auto-assign tickets N1 creates to you? 1 — Yes (default) / 2 — No
```

- **1 (Yes) or default:**
```json
{ "tracker": { "assignToCreator": true } }
```
- **2 (No):**
```json
{ "tracker": { "assignToCreator": false } }
```

Store the value on the `tracker` block (alongside `mcp`/`operations`). Skip this question entirely when `tracker.mcp` is `null` (no tracker configured).

### On reconfiguration (n1-init re-run):

If `assignToCreator` already exists on the `tracker` block, show it and offer:
```
Auto-assign created tickets to you: <true/false>
1 — Keep current
2 — Toggle
```
- **1** → leave unchanged.
- **2** → flip the boolean.
```

- [ ] **Step 2: Add `assignToCreator` note to the final assembly block**

The assembly block shows `"tracker": { ... }`. The flag lives inside the `tracker` block (seeded in Task 1), so no separate top-level key is needed. Confirm the assembly block's comment for `tracker` reflects it — locate:

```json
  "tracker": { ... },
```

Leave as-is (the `{ ... }` already encompasses `assignToCreator`). No edit required in this step beyond confirming; this step is a no-op guard to prevent adding a duplicate top-level key.

- [ ] **Step 3: Verify the section landed and `assignToCreator` count rose**

Run:
```bash
grep -c "Assign to Creator Configuration" skills/n1-init/SKILL.md
grep -c "assignToCreator" skills/n1-init/SKILL.md
```
Expected: `1` for the heading; `assignToCreator` now ≥ `4` (2 presets + 2 in the new section).

- [ ] **Step 4: Commit**

```bash
git add skills/n1-init/SKILL.md
git commit -m "feat(n1-init): add assignToCreator wizard prompt and reconfig flow"
```

---

## Task 3: Add the "Assign to creator" step in n1-start

**Files:**
- Modify: `skills/n1-start/SKILL.md` ("If 1 (Yes)" branch, steps `158-181`)

- [ ] **Step 1: Insert the assignment step between ticket creation and the report**

In the `**If 1 (Yes):**` block, the current steps 4–6 read:

```markdown
4. Use the returned ticket ID as the memory `<ID>` (replacing the slug). Now that the final `<ID>` is known, run **Ensure Working Branch(`<new ticket ID>`)** (see Working Branch above).
5. Extract the ticket URL from the MCP response (YouTrack returns it in the response body; for Jira construct it as `https://<cloud>/browse/<key>` from the response)
6. Report: "Created ticket **[<ID>](<ticket URL>)**: <title>"
```

Replace those three lines with:

```markdown
4. Use the returned ticket ID as the memory `<ID>` (replacing the slug). Now that the final `<ID>` is known, run **Ensure Working Branch(`<new ticket ID>`)** (see Working Branch above).
5. Extract the ticket URL from the MCP response (YouTrack returns it in the response body; for Jira construct it as `https://<cloud>/browse/<key>` from the response)
6. **Assign to creator.** Run this step ONLY if ALL of: `tracker.assignToCreator !== false`, `tracker.operations.getCurrentUser` exists, AND `tracker.operations.assign` exists. If any condition fails, skip this step silently (no message) and go to step 7.
   1. Resolve the current user: call `mcp__<tracker.mcp>__<tracker.operations.getCurrentUser>` (no arguments).
      - **YouTrack:** take `login` from the response.
      - **Jira:** take the account id (`account_id`) from the response; reuse the `cloudId` already resolved during creation.
   2. Assign the ticket: call `mcp__<tracker.mcp>__<tracker.operations.assign>`:
      - **YouTrack:** `change_issue_assignee` with `issueId`: `<ID>`, `assigneeLogin`: `<login>`.
      - **Jira:** `editJiraIssue` with `cloudId`: resolved cloud ID, `issueIdOrKey`: `<ID>`, `assignee_account_id`: `<account id>`.
   3. **On success:** set the report suffix to ` (assigned to you)`.
   4. **On failure** (either call errors — permission, unresolvable user, MCP error): do NOT roll back creation. Emit `⚠ Ticket created but could not auto-assign (<reason>); assign it manually.` and use an empty report suffix.
7. Report: "Created ticket **[<ID>](<ticket URL>)**<report suffix>: <title>"
```

- [ ] **Step 2: Renumber the trailing step**

The old step 7 (tracker status update) is now step 8. Locate:

```markdown
7. After writing ticket.md and overview.md, update tracker status to In Progress (same as ticket mode — call `mcp__<tracker.mcp>__<tracker.operations.moveStatus>`)
```

Change its leading `7.` to `8.`:

```markdown
8. After writing ticket.md and overview.md, update tracker status to In Progress (same as ticket mode — call `mcp__<tracker.mcp>__<tracker.operations.moveStatus>`)
```

- [ ] **Step 3: Verify the step and gate are present**

Run:
```bash
grep -n "Assign to creator" skills/n1-start/SKILL.md
grep -c "assignToCreator !== false" skills/n1-start/SKILL.md
grep -n "report suffix" skills/n1-start/SKILL.md
```
Expected: the "Assign to creator" line appears once; gate count is `1`; the report line references `<report suffix>`.

- [ ] **Step 4: Commit**

```bash
git add skills/n1-start/SKILL.md
git commit -m "feat(n1-start): auto-assign created tickets to the authenticated user"
```

---

## Task 4: Update CLAUDE.md Tracker Routing docs

**Files:**
- Modify: `CLAUDE.md` (Tracker Routing table `94-99`)

- [ ] **Step 1: Extend the key-operations table and add the flag note**

Locate the Tracker Routing table and the `ticketTagging` paragraph below it (lines ~94–99). Replace:

```markdown
| Tracker | mcp value | Key operations |
|---------|-----------|---------------|
| Jira | `plugin_atlassian_atlassian` | `getJiraIssue`, `transitionJiraIssue`, `addCommentToJiraIssue`, `getTransitionsForJiraIssue` |
| YouTrack | `youtrack` | `get_issue`, `update_issue`, `add_issue_comment`, `get_issue_comments` |

When `ticketTagging.enabled` is true, `n1-start` prefixes created tickets with `ticketTagging.service` (`{service} | title`) and adds a `**Service:**` line to the description. Off by default; configured by `n1-init`. Creation only — existing tickets are never re-tagged.
```

with:

```markdown
| Tracker | mcp value | Key operations |
|---------|-----------|---------------|
| Jira | `plugin_atlassian_atlassian` | `getJiraIssue`, `transitionJiraIssue`, `addCommentToJiraIssue`, `getTransitionsForJiraIssue`, `atlassianUserInfo` (getCurrentUser), `editJiraIssue` (assign) |
| YouTrack | `youtrack` | `get_issue`, `update_issue`, `add_issue_comment`, `get_issue_comments`, `get_current_user` (getCurrentUser), `change_issue_assignee` (assign) |

When `ticketTagging.enabled` is true, `n1-start` prefixes created tickets with `ticketTagging.service` (`{service} | title`) and adds a `**Service:**` line to the description. Off by default; configured by `n1-init`. Creation only — existing tickets are never re-tagged.

When `tracker.assignToCreator` is not `false` (default ON), `n1-start` assigns tickets it creates to the currently-authenticated tracker user via the `getCurrentUser` + `assign` operations. Creation only; non-fatal on failure; silently skipped when those operations are absent (legacy configs). Configured by `n1-init`.
```

- [ ] **Step 2: Verify**

Run:
```bash
grep -c "assignToCreator" CLAUDE.md
grep -c "change_issue_assignee" CLAUDE.md
```
Expected: each prints `1`.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(CLAUDE): document assignToCreator and getCurrentUser/assign operations"
```

---

## Task 5: Update README.md

**Files:**
- Modify: `README.md` (tracker/config overview, ~`102-104`)

- [ ] **Step 1: Add a one-line mention after the ticket-tagging sentence**

Locate the ticketTagging sentence (line ~104):

```markdown
Created tickets can optionally be tagged with a service name. When `ticketTagging.enabled` is set (off by default; configured by `n1-init`), N1-created tickets get a `{service} | <title>` summary prefix and a `**Service:** <service>` line in the description.
```

Immediately after it, add a new paragraph:

```markdown
Tickets N1 creates are auto-assigned to you (the authenticated tracker user) by default. Set `tracker.assignToCreator` to `false` (or answer No during `n1-init`) to disable. Applies to created tickets only; never changes the assignee of existing tickets.
```

- [ ] **Step 2: Verify**

Run:
```bash
grep -c "assignToCreator" README.md
```
Expected: `1`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(README): document auto-assign of created tickets"
```

---

## Task 6: Dogfood verification

No test runner exists; verify behaviour by running N1 against a scratch project per CLAUDE.md. This task is manual — record observed results.

**Files:** none (verification only)

- [ ] **Step 1: Launch N1 against a scratch repo**

Run (from a separate test project, not the N1 repo):
```bash
claude --plugin-dir C:\Dev\n1
```
Inside, run `/reload-plugins` if already open.

- [ ] **Step 2: YouTrack default-on path**

With a YouTrack-configured `.n1/n1.config.json` (containing the Task 1 operations), run `/n1:start` with a brain-dump description, choose "Yes, create a ticket".
Expected: ticket is created, `change_issue_assignee` is called with your login, and the report reads `Created ticket [<ID>](url) (assigned to you): <title>`.

- [ ] **Step 3: Jira default-on path**

Repeat Step 2 with a Jira-configured config.
Expected: `editJiraIssue` sets `assignee_account_id` to your account; report shows "(assigned to you)".

- [ ] **Step 4: Flag-off path**

Set `tracker.assignToCreator` to `false`, re-run brain-dump create.
Expected: ticket created, NO assign call, NO warning, report has no "(assigned to you)" suffix.

- [ ] **Step 5: Legacy-config path**

Remove `getCurrentUser` and `assign` from `operations`, re-run brain-dump create.
Expected: ticket created, assignment silently skipped, NO warning.

- [ ] **Step 6: Failure path**

Force an assign error (e.g. point `assign` at a user lacking permission, or temporarily break the op). 
Expected: ticket still created, `⚠ Ticket created but could not auto-assign (...)` shown, pipeline continues to status update.

- [ ] **Step 7: Existing-ticket-ID path**

Run `/n1:start <existing ticket ID>`.
Expected: assignment step never runs (N1 didn't create the ticket).

---

## Self-Review Notes

- **Spec coverage:** §1 schema → Task 1; §2 n1-start flow + gate + report → Task 3; §3 non-fatal failure → Task 3 step 1.4; §4 n1-init presets + prompt → Tasks 1–2; §5 docs → Tasks 4–5; backward compat (silent skip) → Task 3 step 1.6 gate + Task 6 Step 5; testing matrix → Task 6.
- **Operation-name consistency:** `getCurrentUser`/`assign` keys defined in Task 1 are referenced verbatim in Task 3 and documented in Task 4. YouTrack→`get_current_user`/`change_issue_assignee`, Jira→`atlassianUserInfo`/`editJiraIssue` are identical across Tasks 1, 3, 4.
- **No placeholders:** all edits show exact before/after content; the one "confirm only" step (Task 2 Step 2) is explicitly a guard, not deferred work.
