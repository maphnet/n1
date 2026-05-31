# Service Name in Created Tickets — Implementation Plan

**Goal:** Optionally prefix N1-created tickets with a configured service name — `{service} | <Title>` in the summary and a `**Service:** <service>` line in the description — off by default, opted into at `n1-init`.

**Architecture:** Pure-markdown change to two skills plus docs. `n1-init` gains a step that asks the user and writes a `ticketTagging` block to `.n1/n1.config.json`. `n1-start`'s ticket-creation block reads that block and conditionally rewrites `summary`/`description` before the MCP create call. No code, no tests harness — N1 is Bash hooks + Markdown skills.

**Tech Stack:** Markdown skills (`skills/*/SKILL.md`), JSON config (`.n1/n1.config.json`), Git/YouTrack/Jira MCP (unchanged).

**Design reference:** `docs/plans/2026-05-31-service-name-in-ticket-design.md`

**Verification model:** There is no automated test runner for markdown skills. "Verify" steps are grep/read assertions that the intended text is present and any embedded JSON is well-formed (`python -c "import json"` on extracted snippets where practical). A final manual dogfood step exercises `n1-init` + `n1-start` via `--plugin-dir`.

**Conventions:** English only. Imperative commit messages. No `Co-Authored-By` trailers. Use `/writing-skills` conventions for skill edits (one concern per edit, match surrounding style).

---

## Task 1: Add the `ticketTagging` capture step to n1-init

**Files:**
- Modify: `skills/n1-init/SKILL.md` (new section after "Git Configuration", which ends at line 250)

**Step 1: Insert a new "Ticket Tagging Configuration" section**

Insert immediately **after** the Git Configuration section (after its closing ```` ``` ```` fence at line 250) and **before** `## Review Configuration` (line 252):

````markdown
## Ticket Tagging Configuration

Ask whether to tag N1-created tickets with a service (repo) name. **Default is No** — do not enable unless the user opts in.

```
Tag created tickets with a service name? (e.g. "payments-api | Add CSV export")
1 — Yes
2 — No (default)
```

**If 2 (No) or default:**
```json
{
  "ticketTagging": {
    "enabled": false
  }
}
```

**If 1 (Yes):**

Derive a default service name, then confirm it:
1. Run `git remote get-url origin 2>/dev/null`. If it succeeds, take the last path segment and strip a trailing `.git` (e.g. `git@github.com:org/payments-api.git` → `payments-api`, `https://github.com/org/payments-api` → `payments-api`).
2. If there is no `origin` remote, fall back to the current directory's base name.
3. Show and confirm:
   ```
   Detected service name: <detected>
   (from git remote origin)

   Use this? 1 — Yes / 2 — Enter a different name
   ```
   - **1** → use `<detected>`.
   - **2** → ask: "Service name:" and use the entered value (trimmed).

```json
{
  "ticketTagging": {
    "enabled": true,
    "service": "<confirmed name>"
  }
}
```

### On reconfiguration (n1-init re-run):

If `ticketTagging` already exists in the current config, show it and offer:
```
Current ticket tagging:
  enabled → <true/false>
  service → <value or "(none)">

1 — Keep current
2 — Update service name
3 — Disable tagging
```
- **1** → leave unchanged.
- **2** → run the derive+confirm flow above, set `enabled: true`.
- **3** → set `{ "enabled": false }`.
````

**Step 2: Add `ticketTagging` to the assembled config example**

In the **Write Configuration and Structure** section, the `.n1/n1.config.json` example (lines 374-407) lists config blocks. Add the `ticketTagging` block. Insert it after the `"git": { ... },` line (line 378):

```json
  "git": { ... },
  "ticketTagging": { ... },
```

**Step 3: Add tagging to the Confirm summary**

In the **Confirm** section's summary block (lines 443-449), add a line after `Branch pattern: {prefix}-{id}`:

```
Ticket tagging: payments-api / disabled
```

**Step 4: Verify the edits are present and JSON snippets parse**

Run:
```bash
grep -n "Ticket Tagging Configuration\|ticketTagging\|Ticket tagging:" skills/n1-init/SKILL.md
```
Expected: matches for the new section heading, the `ticketTagging` config keys, and the Confirm summary line.

Validate the two new JSON snippets are well-formed by extracting and parsing them manually (copy each `{ "ticketTagging": ... }` object and run):
```bash
python -c "import json,sys; json.loads(sys.stdin.read())"
```
Expected: no error for `{"ticketTagging":{"enabled":false}}` and `{"ticketTagging":{"enabled":true,"service":"payments-api"}}`.

**Step 5: Commit**

```bash
git add skills/n1-init/SKILL.md
git commit -m "feat(n1-init): capture optional ticketTagging service name"
```

---

## Task 2: Apply the tag in n1-start ticket creation

**Files:**
- Modify: `skills/n1-start/SKILL.md` — the "If 1 (Yes)" ticket-creation block (lines 150-166)

**Step 1: Add a tagging-resolution preamble to the "If 1 (Yes)" block**

The current block (lines 150-162) reads:

```markdown
**If 1 (Yes):**
1. Extract the Title and structured content from the product-analyst output
2. Create the ticket via MCP:
   - **YouTrack:** Call `mcp__<tracker.mcp>__<tracker.operations.createIssue>` with:
     - `project`: `tracker.projectKey`
     - `summary`: the Title from product-analyst output
     - `description`: the Core Ask + Description + Acceptance Criteria sections
   - **Jira:** First resolve `cloudId` via `mcp__<tracker.mcp>__getAccessibleAtlassianResources`, then call `mcp__<tracker.mcp>__<tracker.operations.createIssue>` with:
     - `cloudId`: resolved cloud ID
     - `projectKey`: `tracker.projectKey`
     - `issueTypeName`: "Task"
     - `summary`: the Title from product-analyst output
     - `description`: the Core Ask + Description + Acceptance Criteria sections
```

Replace it with a version that resolves the tag once, then references the computed values in both branches:

```markdown
**If 1 (Yes):**
1. Extract the Title and structured content from the product-analyst output
2. **Resolve ticket tagging.** Read `ticketTagging` from `.n1/n1.config.json`.
   - **If `ticketTagging.enabled` is `true` AND `ticketTagging.service` is a non-empty string** → tagging is ON:
     - `<summary>` = `<service> | <Title>` — but if `<Title>` already begins with `<service> |`, use `<Title>` unchanged (idempotency guard for resume/retry).
     - `<description>` = `**Service:** <service>` as the first line, a blank line, then the Core Ask + Description + Acceptance Criteria sections.
   - **Otherwise** (block missing, `enabled` false, or `service` empty) → tagging is OFF:
     - `<summary>` = the Title from product-analyst output.
     - `<description>` = the Core Ask + Description + Acceptance Criteria sections.
3. Create the ticket via MCP:
   - **YouTrack:** Call `mcp__<tracker.mcp>__<tracker.operations.createIssue>` with:
     - `project`: `tracker.projectKey`
     - `summary`: `<summary>`
     - `description`: `<description>`
   - **Jira:** First resolve `cloudId` via `mcp__<tracker.mcp>__getAccessibleAtlassianResources`, then call `mcp__<tracker.mcp>__<tracker.operations.createIssue>` with:
     - `cloudId`: resolved cloud ID
     - `projectKey`: `tracker.projectKey`
     - `issueTypeName`: "Task"
     - `summary`: `<summary>`
     - `description`: `<description>`
```

**Step 2: Renumber the trailing steps in the block**

The block currently continues with steps `3.`–`6.` (lines 163-166: "Use the returned ticket ID…", "Extract the ticket URL…", "Report…", "After writing ticket.md…"). Because a new step was inserted at position 2, renumber these to `4.`–`7.` so the list stays sequential. Do not change their wording.

**Step 3: Verify**

Run:
```bash
grep -n "Resolve ticket tagging\|ticketTagging\|Service:\|idempotency guard" skills/n1-start/SKILL.md
```
Expected: matches inside the "If 1 (Yes)" block.

Confirm the existing-ticket path and the "If 2 (No)" path are untouched:
```bash
grep -n "If 2 (No)\|Ticket mode" skills/n1-start/SKILL.md
```
Expected: those sections still present and unchanged.

**Step 4: Commit**

```bash
git add skills/n1-start/SKILL.md
git commit -m "feat(n1-start): tag created tickets with service name when enabled"
```

---

## Task 3: Document the new config in README and CLAUDE.md

**Files:**
- Modify: `README.md` — `## Tracker Support` section (config note at line 102)
- Modify: `CLAUDE.md` — after the Tracker Routing table (ends line 97)

**Step 1: Add a README note**

In `README.md`, directly after line 102 (`Tracker routing is config-driven via ...`), add a new paragraph:

```markdown
Created tickets can optionally be tagged with a service name. When `ticketTagging.enabled` is set (off by default; configured by `n1-init`), N1-created tickets get a `{service} | <title>` summary prefix and a `**Service:** <service>` line in the description.
```

**Step 2: Add a CLAUDE.md note**

In `CLAUDE.md`, immediately after the Tracker Routing table (after line 97), add:

```markdown
When `ticketTagging.enabled` is true, `n1-start` prefixes created tickets with `ticketTagging.service` (`{service} | title`) and adds a `**Service:**` line to the description. Off by default; configured by `n1-init`. Creation only — existing tickets are never re-tagged.
```

**Step 3: Verify**

Run:
```bash
grep -n "Ticket tagging\|ticketTagging" README.md CLAUDE.md
```
Expected: one match in each file.

**Step 4: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: document ticketTagging config"
```

---

## Task 4: Manual dogfood verification

**Files:** none (manual run)

**Step 1: Reconfigure with tagging enabled**

From a scratch test repo (or this repo with a throwaway config), run `claude --plugin-dir C:\Dev\n1`, then `/n1:n1-init`, choose **Yes** for ticket tagging, accept the detected service name. Confirm `.n1/n1.config.json` now contains:
```json
"ticketTagging": { "enabled": true, "service": "<name>" }
```

**Step 2: Create a ticket from a brain dump**

Run `/n1:n1-start add a throwaway test note`, proceed to the "create a tracker ticket?" prompt, choose **Yes**. Confirm the created ticket's summary is `<name> | <Title>` and its description starts with `**Service:** <name>`.

**Step 3: Verify the off path**

Re-run `/n1:n1-init`, choose **3 — Disable tagging** (reconfigure). Create another brain-dump ticket and confirm the summary has **no** prefix and the description has **no** Service line.

**Step 4: Verify idempotency guard (optional)**

With tagging on, manually re-trigger creation where the Title already starts with `<name> |` and confirm the summary is not double-prefixed.

No commit — this is verification only.
