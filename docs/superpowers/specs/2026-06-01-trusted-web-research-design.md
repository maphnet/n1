# Trusted Web Research for Architecture & Planning

**Date:** 2026-06-01
**Status:** Approved (design) — pending implementation plan
**Scope:** N1 plugin — `solution-architect` and `planner` agents, `n1-start` skill, project docs

## Problem

N1's design and planning steps reason only from the local codebase. They have no
way to ground decisions in external industry standards or best practices. We want
the solution architect (during analysis and design), the planner (during plan
writing), and the plan review (CCR) to research the web for standards and best
practices — but **only trusted, authoritative material**, never marketing content.

## Goals

1. Give `solution-architect` and `planner` web-research capability across all five
   design/planning touchpoints in `n1-start`.
2. Constrain research to **trusted sources** and reject marketing/SEO content.
3. Distinguish **decisive standards/specs** (authoritative) from **soft, contestable
   "best practices"** (contextual) — and prevent the latter from becoming a
   cargo-culting / over-engineering vector.
4. Make every web-sourced claim **auditable** via citations carried through the
   `.n1/` artifacts.

## Non-Goals

- No configuration toggle — the capability is **always on** (with graceful
  degradation when the network is unavailable).
- No change to library/framework **API-doc** lookups — those continue to use
  Context7 MCP (existing global rule).
- No change to the interactive `brainstorming` step — it inherits the cited
  standards via `analysis.md`.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Trust mechanism | Hybrid: trusted tiers + reject-list + ≥2-source corroboration + mandatory URL citation | Allowlist alone is brittle; rubric alone is too soft against polished marketing. Hybrid gives strong priors **and** hard guardrails. |
| Always-on vs. toggle | Always-on, no toggle | User preference; simplest surface. Mitigated by graceful degradation. |
| Tools | `WebSearch` **and** `WebFetch` on both agents | Search to discover, fetch to read the full standard/doc before citing. |
| Rubric location | Single shared file `agents/research-standards.md` + compact inline summary in each agent | DRY for the full rubric; inline core rules guarantee enforcement even if the shared read is skipped. |
| Standards vs. soft practices | **Fitness gate** + standards-over-practices priority | Web research is decisive for specs/security/compliance but risky for contested practices; the gate stops over-engineering from hiding behind a citation. |

## Touchpoints

| Touchpoint | Agent | Research role |
|---|---|---|
| Analysis (1st pass) | solution-architect | Surface industry standards / best practices relevant to the task domain |
| Deeper analysis (pre-plan) | solution-architect | Validate the chosen direction against established patterns |
| Plan writing | planner (drives `writing-plans`) | Ground plan decisions in best practices |
| Plan review (CCR) | solution-architect | Validate the plan against standards; flag and cite deviations |

`brainstorming` needs no change — it consumes `analysis.md`, which will now carry a
cited standards section.

## The Trust Mechanism

A new shared reference file **`agents/research-standards.md`** is the single source
of truth. It defines:

### Trusted tiers (prefer in this order)
1. Official vendor / project documentation and specifications.
2. Standards bodies: IETF (RFCs), W3C, ISO, OWASP, NIST, and official
   language/framework guides.
3. Established engineering organizations and peer-reviewed / widely-cited sources.

### Reject-list (never cite as authority)
- SEO listicles ("top 10…", "ultimate guide to…").
- Vendor marketing / product landing pages.
- Content farms and ad-driven aggregators.
- Undated or anonymous blog posts; AI-generated SEO filler.

### Hard rules
- **Corroborate** every claim across **≥2 independent trusted sources**.
- **Cite the URL** for each web-sourced claim in the artifact.

### Context7 boundary
Library/framework **API** docs → Context7 MCP. Web research is **only** for
architectural best practices, industry standards, security/compliance guidance, and
design patterns.

### Graceful degradation
If web tools are unavailable (offline / headless / cron), proceed with
codebase-only analysis and note **"web research unavailable — skipped"**. Never fail
the step on a network error.

## The Fitness Gate (standards over soft practices)

Source credibility is necessary but **not sufficient**. A trustworthy source can
still give advice that does not fit this codebase or scale. Therefore:

- **Prefer decisive standards** (specs, security, protocol, compliance — which have a
  canonical answer) over **contestable practices** (which are contextual and
  fashion-driven).
- **Fitness rule:** any web-sourced best practice must be justified against (a) the
  specific codebase context in `analysis.md` and (b) N1's core principles
  (Simplicity First, YAGNI, Minimal Impact) **before** it influences a decision.
- **Considered-and-rejected output:** when a practice does not fit the task's scale,
  cite it and explicitly reject it — e.g. *"Considered event sourcing
  (source: …) — rejected as over-engineering for this scope."* A rejected-with-reason
  citation is more valuable at plan review than an unexamined "industry says X."

This guards against the three failure modes of soft best-practice research:
popularity bias (consensus ≠ correctness at this scale), context mismatch /
over-engineering, and staleness.

## Per-File Changes

### `agents/research-standards.md` (new)
The shared rubric above: trusted tiers, reject-list, hard rules, Context7 boundary,
graceful degradation, and the fitness gate.

### `agents/solution-architect.md`
- Add `WebSearch, WebFetch` to the `tools` frontmatter list.
- Add a **Web Research** process step: when standards/best-practices are relevant,
  search → fetch → corroborate → apply fitness gate, per `agents/research-standards.md`.
- Add a compact inline summary of the two hard rules + degradation + fitness gate
  (so enforcement holds even if the shared file isn't read).
- Add an output section **`### Industry Standards & Best Practices`** with cited
  bullets (each: claim — source URL — fitness note), or "None applicable." Include a
  "Considered & rejected" sub-list where relevant.

### `agents/planner.md`
- Add `WebSearch, WebFetch` to the `tools` frontmatter list.
- Add a **Web Research** directive: ground plan decisions in cited best practices via
  the same rubric and fitness gate; record the citation in the plan rationale.

### `skills/n1-start/SKILL.md`
- Plan-review CCR prompt: add a 6th check — **"STANDARDS VALIDATION — does the plan
  align with established best practices? Cite sources for any deviation flagged."**
- Extend the CCR output's *Verified assumptions* to also cover *verified standards*.
- Add a one-line research nudge to the analysis and plan dispatch directives.

### `CLAUDE.md`
- Update the Agent Personas table `Tools` column for `solution-architect`
  (`Read, Grep, Glob, Bash, WebSearch, WebFetch`) and `planner`
  (`Read, Grep, Glob, Write, Edit, Skill, WebSearch, WebFetch`).
- One line documenting the always-on trusted web-research capability and its
  `agents/research-standards.md` rubric.

## Citation Flow (traceability)

Cited sources land in `analysis.md` (standards section) → carried into
`brainstorm.md` and `plan.md` rationale → re-verified at plan review. Every
web-sourced claim is auditable in the `.n1/` artifacts.

## Testing / Verification

Per N1's dogfooding model (no automated test harness):
- Load via `claude --plugin-dir C:\Dev\n1` from a test project; `/reload-plugins`.
- Confirm `solution-architect` and `planner` can invoke `WebSearch`/`WebFetch`
  (frontmatter allowlist is runtime-enforced).
- Run `n1-start` on a task with a standards-relevant dimension (e.g. auth/token
  handling) and confirm `analysis.md` gains a cited `### Industry Standards & Best
  Practices` section with corroborated sources and at least one fitness note.
- Confirm graceful degradation by running with the network disabled — the step
  completes and notes research was skipped.
