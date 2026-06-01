# Trusted Web Research Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the N1 `solution-architect` and `planner` agents always-on, trusted-source web research (best practices / industry standards) across the analysis, planning, and plan-review touchpoints, with a fitness gate that prevents over-engineering.

**Architecture:** A single shared rubric file (`agents/research-standards.md`) is the source of truth for trusted tiers, a marketing reject-list, ≥2-source corroboration, mandatory citation, the Context7 boundary, graceful degradation, and a standards-over-soft-practices fitness gate. The two agents gain `WebSearch, WebFetch` in their runtime-enforced `tools` allowlist plus a compact inline summary so the rules hold even if the shared file isn't read. `n1-start`'s plan-review CCR prompt gains a standards-validation check, and `CLAUDE.md` is updated to document the capability.

**Tech Stack:** Markdown only (N1 agents/skills are Markdown; no code, no npm). Verification is manual/dogfooding via `claude --plugin-dir` — there is no automated test harness.

**Note on verification:** N1 has no unit-test framework. Each task's "verify" step is a `grep`/visual check or a `--plugin-dir` load, not an automated test. Keep commits small and per-task.

**Source spec:** `docs/superpowers/specs/2026-06-01-trusted-web-research-design.md`

---

### Task 1: Create the shared research-standards rubric

**Files:**
- Create: `agents/research-standards.md`

- [ ] **Step 1: Create the rubric file**

Create `agents/research-standards.md` with this exact content:

```markdown
# Research Standards (shared rubric)

Agents that perform web research (solution-architect, planner) MUST follow these
rules. Read this file before your first web search in a task. The two **Hard Rules**
and the **Fitness Gate** are restated inline in each agent so they hold even if this
file is not read.

## When to research

Use web research ONLY for architectural best practices, industry standards,
security/compliance guidance, and design patterns. Do NOT use it for
library/framework **API** docs — those go through Context7 MCP (project rule).

## Trusted tiers (prefer in this order)

1. Official vendor / project documentation and specifications.
2. Standards bodies: IETF (RFCs), W3C, ISO, OWASP, NIST, and official
   language/framework guides.
3. Established engineering organizations and peer-reviewed / widely-cited sources.

## Reject-list (never cite as authority)

- SEO listicles ("top 10…", "ultimate guide to…").
- Vendor marketing / product landing pages.
- Content farms and ad-driven aggregators.
- Undated or anonymous blog posts; AI-generated SEO filler.

## Hard Rules

1. **Corroborate** every claim across **≥2 independent trusted sources**.
2. **Cite the URL** for each web-sourced claim in your output.

## Fitness Gate (standards over soft practices)

Source credibility is necessary but not sufficient — a trustworthy source can still
give advice that does not fit this codebase or its scale.

- **Prefer decisive standards** (specs, security, protocol, compliance — canonical
  answers) over **contestable practices** (contextual, fashion-driven).
- Any web-sourced best practice must be justified against (a) the specific codebase
  context in `analysis.md` and (b) N1's core principles (Simplicity First, YAGNI,
  Minimal Impact) **before** it influences a decision.
- When a practice does not fit the task's scale, cite it and explicitly reject it —
  e.g. "Considered event sourcing (source: …) — rejected as over-engineering for
  this scope." A rejected-with-reason citation is more valuable than an unexamined
  "industry says X."

## Graceful degradation

If web tools are unavailable (offline / headless / cron), proceed with
codebase-only analysis and note "web research unavailable — skipped". Never fail the
step on a network error.
```

- [ ] **Step 2: Verify the file exists and contains the key anchors**

Run: `grep -c "Hard Rules\|Fitness Gate\|Reject-list\|Graceful degradation" agents/research-standards.md`
Expected: `4`

- [ ] **Step 3: Commit**

```bash
git add agents/research-standards.md
git commit -m "feat(agents): add shared trusted-research rubric"
```

---

### Task 2: Enable web research in solution-architect

**Files:**
- Modify: `agents/solution-architect.md`

- [ ] **Step 1: Add WebSearch/WebFetch to the tools allowlist**

In `agents/solution-architect.md`, change the frontmatter line:

```
tools: Read, Grep, Glob, Bash
```

to:

```
tools: Read, Grep, Glob, Bash, WebSearch, WebFetch
```

- [ ] **Step 2: Add the Web Research process step**

In the `## Process` section, insert a new numbered step immediately after step 4
("Deep-read key files…") and before the bug-investigation step. Renumber the
following steps accordingly (bug investigation becomes 6, synthesize becomes 7):

```markdown
5. **Research standards (web):** When the task touches a domain with established
   industry standards or best practices (security, auth, protocols, data handling,
   compliance, well-known design patterns), research them per
   `agents/research-standards.md`: search → fetch the authoritative source → read it
   → corroborate. **Hard rules:** corroborate every claim across ≥2 independent
   trusted sources, and cite the URL. **Fitness gate:** prefer decisive standards
   over contestable practices, and justify any practice against the codebase context
   and N1's Simplicity/YAGNI/Minimal-Impact principles before applying it; cite and
   explicitly reject practices that don't fit the scope. Use Context7 (not web) for
   library API docs. If web tools are unavailable, skip and note it — never fail.
```

- [ ] **Step 3: Add the output section for cited standards**

In the `## Output Format` code block, insert this section immediately before the
`### Risks & Considerations` section:

```markdown
### Industry Standards & Best Practices
<cited bullets — each: claim — source URL — fitness note; or "None applicable">
**Considered & rejected:** <practice — source URL — why it doesn't fit this scope; or "None">
```

- [ ] **Step 4: Verify the edits**

Run: `grep -c "WebSearch, WebFetch\|Research standards (web)\|Industry Standards & Best Practices" agents/solution-architect.md`
Expected: `3`

Then visually confirm the `## Process` steps are sequentially numbered 1–7 with no
duplicate or skipped numbers.

- [ ] **Step 5: Commit**

```bash
git add agents/solution-architect.md
git commit -m "feat(solution-architect): add trusted web research for standards"
```

---

### Task 3: Enable web research in planner

**Files:**
- Modify: `agents/planner.md`

- [ ] **Step 1: Add WebSearch/WebFetch to the tools allowlist**

In `agents/planner.md`, change the frontmatter line:

```
tools: Read, Grep, Glob, Write, Edit, Skill
```

to:

```
tools: Read, Grep, Glob, Write, Edit, Skill, WebSearch, WebFetch
```

- [ ] **Step 2: Add a Web Research directive to the Process**

In `agents/planner.md`, in the `## Process` section, insert a new step between the
current step 1 (invoke `superpowers:writing-plans`) and step 2 (write the plan):

```markdown
2. **Ground decisions in standards (web):** Where a plan decision depends on an
   industry standard or best practice, research it per `agents/research-standards.md`
   and record the citation in the plan rationale. **Hard rules:** corroborate across
   ≥2 independent trusted sources and cite the URL. **Fitness gate:** prefer decisive
   standards over contestable practices; justify any practice against the codebase
   analysis and N1's Simplicity/YAGNI/Minimal-Impact principles before planning
   around it, and cite-and-reject practices that over-engineer the scope. Use
   Context7 (not web) for library API docs. If web tools are unavailable, skip and
   note it — never fail.
```

Renumber the subsequent Process steps accordingly (write the plan becomes 3, return
the summary becomes 4).

- [ ] **Step 3: Verify the edits**

Run: `grep -c "WebSearch, WebFetch\|Ground decisions in standards (web)" agents/planner.md`
Expected: `2`

Then visually confirm the `## Process` steps are sequentially numbered 1–4.

- [ ] **Step 4: Commit**

```bash
git add agents/planner.md
git commit -m "feat(planner): ground plan decisions in trusted web research"
```

---

### Task 4: Add standards validation to the plan-review CCR

**Files:**
- Modify: `skills/n1-start/SKILL.md`

- [ ] **Step 1: Add the 6th CCR check**

In `skills/n1-start/SKILL.md`, inside the plan-review CCR prompt (the block listing
checks 1–5 BLAST RADIUS), add a 6th check immediately after the BLAST RADIUS item
and before the "If you find issues:" line:

```
6. STANDARDS VALIDATION — Does the plan align with established industry standards
   and best practices for this domain? Research per agents/research-standards.md:
   corroborate across ≥2 independent trusted sources and cite the URL for any
   deviation you flag. Apply the fitness gate — prefer decisive standards over
   contestable practices, and do not flag a "best practice" the plan correctly
   omitted as over-engineering for this scope. If web tools are unavailable, skip
   this check and note it.
```

- [ ] **Step 2: Extend the CCR output format to cover verified standards**

In the same prompt's `Output format` block, change the line:

```
**Verified assumptions:** (list of codebase claims you confirmed via Grep/Read)
```

to:

```
**Verified assumptions:** (list of codebase claims you confirmed via Grep/Read)
**Verified standards:** (list of best-practice/standard claims confirmed via web, with cited URLs; or "None")
```

- [ ] **Step 3: Add a research nudge to the analysis and plan dispatch directives**

In Step 2 (ANALYSIS) dispatch list, append a bullet after the Type-field bullet:

```
- Directive: "Research relevant industry standards/best practices per agents/research-standards.md and include the cited Industry Standards & Best Practices section."
```

In Step 4 (PLAN) deeper-analysis directive, append to the existing directive string:
` Also research applicable industry standards/best practices per agents/research-standards.md and cite them.`

- [ ] **Step 4: Verify the edits**

Run: `grep -c "STANDARDS VALIDATION\|Verified standards\|research relevant industry standards\|Research relevant industry standards" skills/n1-start/SKILL.md`
Expected: `3` (the CCR check, the output line, and the analysis directive)

- [ ] **Step 5: Commit**

```bash
git add skills/n1-start/SKILL.md
git commit -m "feat(n1-start): add standards validation to plan-review CCR"
```

---

### Task 5: Document the capability in CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update the agent persona table Tools column**

In `CLAUDE.md`, change the `solution-architect` row:

```
| solution-architect | opus | Read, Grep, Glob, Bash | Analysis, Bug investigation, Plan review (CCR) |
```

to:

```
| solution-architect | opus | Read, Grep, Glob, Bash, WebSearch, WebFetch | Analysis, Bug investigation, Plan review (CCR) |
```

And change the `planner` row:

```
| planner | opus | Read, Grep, Glob, Write, Edit, Skill | Plan writing |
```

to:

```
| planner | opus | Read, Grep, Glob, Write, Edit, Skill, WebSearch, WebFetch | Plan writing |
```

- [ ] **Step 2: Add a capability note under the persona table**

In `CLAUDE.md`, immediately after the line
`Models default to agent frontmatter values, overridable via `models` section in `n1.config.json`.`
add a new paragraph:

```markdown
**Trusted web research (always on).** `solution-architect` and `planner` carry
`WebSearch, WebFetch` to research industry standards and best practices during
analysis, planning, and plan-review. Research is constrained by the shared rubric in
`agents/research-standards.md`: trusted source tiers, a marketing reject-list,
≥2-source corroboration, mandatory URL citation, a standards-over-soft-practices
fitness gate (guards against over-engineering), and graceful degradation when the
network is unavailable. Library API docs still go through Context7, not web search.
```

- [ ] **Step 3: Verify the edits**

Run: `grep -c "WebSearch, WebFetch\|Trusted web research (always on)" CLAUDE.md`
Expected: `3` (two table rows + the note heading)

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(CLAUDE): document trusted web research capability"
```

---

### Task 6: Dogfood verification

**Files:** none (manual verification)

- [ ] **Step 1: Load the plugin from the working tree**

From a separate test project:

Run: `claude --plugin-dir C:\Dev\n1`
Then in-session: `/reload-plugins`
Expected: no load errors; N1 skills available.

- [ ] **Step 2: Confirm the tools allowlist is honored**

Trigger `n1-start` (or directly dispatch the `solution-architect` agent) on a
standards-relevant task — e.g. "add token-based auth to endpoint X".
Expected: the agent is able to call `WebSearch`/`WebFetch` (no "tool not permitted"
error), and the resulting `analysis.md` contains a populated
`### Industry Standards & Best Practices` section with at least one corroborated,
cited source and a fitness note (or an explicit "None applicable").

- [ ] **Step 3: Confirm graceful degradation**

Re-run the same dispatch with the network disabled.
Expected: the step completes and the analysis notes "web research unavailable —
skipped" rather than erroring out.

- [ ] **Step 4: Confirm the plan-review check**

On a complex task that reaches PLAN REVIEW, confirm the CCR output includes a
`**Verified standards:**` line.

- [ ] **Step 5: Final commit (if any cleanup was needed)**

```bash
git add -A
git commit -m "chore: trusted web research dogfooding fixups"
```

(Skip if no changes were required.)
