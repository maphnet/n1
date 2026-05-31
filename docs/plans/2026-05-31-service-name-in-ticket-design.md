# Service Name in Created Tickets

**Date:** 2026-05-31
**Status:** Designed

## Problem

When `n1-start` creates a tracker ticket from a brain dump or file input
(`skills/n1-start/SKILL.md:139-166`), the `summary` is just the analyst's Title
and the `description` carries only the Core Ask / Description / Acceptance
Criteria. In multi-service organisations the resulting tickets give no signal
about *which* service or repository they belong to, so they are hard to scan and
triage in the tracker backlog.

## Goal

Optionally tag newly-created tickets with the service (repo) name:

- **Title:** `{service} | <Title>` — e.g. `payments-api | Add CSV export for users`
- **Description:** a `**Service:** <service>` line prepended to the body

The feature is **off by default**. It is opted into at `n1-init` time, and the
service name is stored in `n1.config.json`. Only tickets that N1 *creates* are
affected — existing-ticket mode reads tickets and never writes a summary, so it
is untouched.

## Config

A new block in `.n1/n1.config.json`:

```json
"ticketTagging": {
  "enabled": false,
  "service": "payments-api"
}
```

- `enabled` defaults to `false`; the feature is inert unless the user opts in.
- `service` holds the label used in the title prefix and description line.
- **Defensive rule:** an empty/missing `service` is treated as disabled even if
  `enabled` is `true`.

## Design

### 1. n1-init — capture the setting

Add a step after **Git Configuration** in `skills/n1-init/SKILL.md`.

Fresh setup:

```
Tag created tickets with a service name?
(e.g. "payments-api | Add CSV export")
1 - Yes
2 - No (default)
```

- **No** -> write `"ticketTagging": { "enabled": false }`. Done.
- **Yes** -> derive a default service name and confirm:
  - Detect from the `origin` remote:
    `git remote get-url origin` -> take the last path segment, strip a trailing
    `.git`. Fall back to the project directory name if there is no remote.
  - Show and confirm:
    ```
    Detected service name: payments-api
    (from git remote origin)

    Use this? 1 - Yes / 2 - Enter a different name
    ```
  - Write `"ticketTagging": { "enabled": true, "service": "<confirmed>" }`.

Reconfiguration (n1-init re-run, when `ticketTagging` already exists): show the
current values and offer keep / update / disable, consistent with the other
reconfigure flows (tracker, model pinning).

Add the block to the assembled `n1.config.json` example in the
**Write Configuration and Structure** section, and to the **Confirm** summary.

### 2. n1-start — apply the tag at creation

Modify the **"If 1 (Yes)"** ticket-creation block in
`skills/n1-start/SKILL.md` (Step 1). After extracting the Title and structured
content, read `ticketTagging` from `.n1/n1.config.json`.

**Apply only when** `ticketTagging.enabled` is `true` **and** `ticketTagging.service`
is a non-empty string. Otherwise use the current values unchanged.

When applying, for **both** the YouTrack and Jira branches:

- `summary` -> `{service} | <Title>`
  - **Idempotency guard:** if `<Title>` already starts with `{service} |`, do not
    prefix again (covers resume / retry).
- `description` -> prepend `**Service:** <service>` as the first line, above the
  existing Core Ask / Description / Acceptance Criteria sections.

No other call sites change. Existing-ticket mode is unaffected (it never creates
a ticket). The "If 2 (No)" no-tracker path is unaffected (no ticket is created).

### 3. Docs

- README: document the `ticketTagging` block in the configuration section.
- CLAUDE.md: one-line note that created tickets can be tagged with the service
  name via `ticketTagging`.

## Scope boundary (YAGNI)

Not in scope:

- **Length-gating the title** — always prefix when enabled; no character budget.
- **Tagging existing tickets** — creation only.
- **Per-ticket override** — the config value applies to all created tickets.
- **Monorepo multi-service detection** — a single service name per project.
- **Description-only / title-only modes** — when enabled, both are tagged.
