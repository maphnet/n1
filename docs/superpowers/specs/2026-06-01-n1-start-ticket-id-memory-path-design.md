# Design: Use the created ticket ID in the memory path (n1-start)

**Date:** 2026-06-01
**Status:** Approved
**Scope:** `skills/n1-start/SKILL.md` (behavioral); `CLAUDE.md` (one-line doc note)

## Problem

When a brain-dump or file-mode run creates a tracker ticket mid-flow (the user
answers **"Yes, create a ticket"**), the orchestrator does not reliably adopt the
new ticket ID as the per-ticket memory `<ID>`. Memory ends up written under the
**slug** directory (e.g. `.n1/memory/csv-export-users/`) instead of the
ticket-ID directory (e.g. `.n1/memory/TRID-510/`), and the working branch keeps
its slug-based name.

### Root cause

Confirmed from the observed failure: after the "create a ticket?" prompt returns
**"Yes"**, the ticket-creation path requires several MCP steps. The orchestrator
drifts into the **ticket-less path** instead of executing those steps
immediately — proceeding as if the run had no ticket. As a result `<ID>` is never
upgraded from the slug to the ticket ID.

Two structural weaknesses enable this:

1. **No hard gate on "Yes."** Ticket creation is not treated as a mandatory,
   immediate, atomic action, so the heavier MCP path is silently skipped.
2. **No recovery step.** The current instruction (line 178: *"Use the returned
   ticket ID as the memory `<ID>` (replacing the slug)"*) implies a slug was
   already bound but provides no procedure to **move** already-written files or
   **rename** the branch. Any slug artifacts are orphaned.

## Goals

- The happy path deterministically writes memory under the ticket ID and names
  the branch from the ticket ID.
- If state already leaked under a provisional slug, **move all files** into the
  ticket-ID folder and **rename the branch** to the ticket-ID-based name.

## Non-goals (YAGNI)

- Re-offering ticket creation on a *later* resume (a fresh "No → work a while →
  now make a ticket" entry point). That is a new feature, not this bug.

## Design

Two complementary halves: **prevention** (make the happy path correct) and
**recovery** (heal any residual drift). Defense in depth.

### 1. Prevention — one Final-ID point + a hard invariant

Add an explicit invariant near Memory Check and the ticket-creation block:

> No file may be written under `.n1/memory/` and no working branch may be created
> until `<ID>` is **final**.

`<ID>` is *final* when:

- **Ticket mode** → the ticket ID (known up front).
- **Brain-dump/file + "Yes"** → the **created** ticket ID (returned from MCP).
- **Brain-dump/file + "No"** → the slug.

Add a red-flag note on the "Yes" branch:

> ⚠ On "Yes," creating the ticket via MCP is **mandatory and immediate** — it is
> the first action after the user answers. Do NOT proceed as if the run were
> ticket-less; the slug is adopted as `<ID>` **only** on the explicit "No" path.

### 2. Recovery — `PROCEDURE: Reconcile Memory ID & Branch(<oldId>, <newId>)`

A new named, idempotent procedure placed alongside *Ensure Working Branch*.
`<oldId>` is the **deterministically-computed** provisional slug (the same rule
the "No" path uses), so the path to look for is always known.

1. If `<oldId>` == `<newId>` → return (no-op).
2. **Memory move:** if `.n1/memory/<oldId>/` exists **and** `.n1/memory/<newId>/`
   does **not** → filesystem-move the directory `<oldId>/ → <newId>/`. (`.n1/`
   is gitignored → plain move, not `git mv`.) If the target already exists, skip
   the move and report — the `<newId>` memory is authoritative
   (resume/collision guard).
3. **Frontmatter fix:** if `<newId>/overview.md` exists (i.e. it was already
   written under the slug and just moved — in the clean happy path it does not
   exist yet, so this is skipped), rewrite `ticket: <oldId>` → `ticket: <newId>`,
   and the `# <oldId>: <Title>` heading → `# <newId>: …`.
4. **Branch rename:** compute `<oldBranch>` and `<newBranch>` from
   `git.branchPattern`. If `<oldBranch>` exists and `<newBranch>` does not →
   `git branch -m <oldBranch> <newBranch>` (safe: rename preserves commits, and
   N1 has not pushed yet — push is at PR time in `n1-pr`). If `<newBranch>`
   already exists, skip the rename (Ensure Working Branch will check it out).
5. Report: `Migrated memory + branch <oldId> → <newId>.`

### 3. Wiring into Step 1

The current line 178 (*"Use the returned ticket ID … (replacing the slug)"*)
becomes:

1. Compute provisional `<slug>` (same rule as the "No" path).
2. Create the ticket via MCP → `<ticketID>`.
3. `Reconcile Memory ID & Branch(<slug>, <ticketID>)` — a no-op in the clean
   happy path; heals drift if it occurred.
4. Set `<ID>` = `<ticketID>`; then `Ensure Working Branch(<ticketID>)`.

In the clean path Reconcile does nothing (no slug artifacts exist). It performs
real work only when prevention was bypassed.

## Edge cases

| Case | Behavior |
|------|----------|
| Target memory dir already exists | Skip move; keep `<newId>` memory (authoritative). Report. |
| Target branch already exists | Skip rename; Ensure Working Branch checks it out. |
| Reconcile called twice | Idempotent no-op. |
| Branch not yet created at reconcile time | Rename condition false → Ensure Working Branch creates it fresh. |
| `<oldId>` == `<newId>` | Immediate no-op. |

## Files touched

- `skills/n1-start/SKILL.md` — the invariant, the "Yes" red-flag note, the new
  Reconcile procedure, and the Step 1 wiring change.
- `CLAUDE.md` — one-line note in the Tracker Routing section for traceability.
