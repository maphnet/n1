# No-One (n1) — Design Document

> **Дата:** 2026-05-26
> **Статус:** Superseded by [Implementation Design](plans/2026-05-26-n1-plugin-design.md)
> **Автор:** Tech Lead + AI brainstorm session

---

## 1. Философия

**No-One** — toolkit где AI выступает полной командой разработки (PM, Developer, QA, Code Reviewer), а человек — Tech Lead, который вмешивается только при неуверенности AI.

"Кто написал этот код?" — "No one."

### Ключевые принципы

- **Автономность по умолчанию** — AI работает самостоятельно, эскалирует по confidence + blast radius
- **Качество через итерацию** — TDD + code review + verification на каждом шаге, не только в конце
- **Superpowers как движок** — не переизобретаем, а оркестрируем проверенные skills
- **MCP-first интеграции** — трекеры, сервисы подключаются через MCP, zero custom code per integration
- **CLAUDE.md = project source of truth** — tool-agnostic, полезен любому инструменту
- **Минимализм** — 4 skills вместо 37, каждый зарабатывает своё существование

### Отличия от Loop

| | Loop | No-One |
|---|---|---|
| **Человек** | Активный участник, подтверждает каждый шаг | Tech Lead на эскалации |
| **Skills** | 37 (монолитный toolkit) | 4 (оркестрация над superpowers) |
| **Трекер** | 10 кастомных программ для Jira | MCP-адаптеры, zero custom code |
| **Качество** | Self-review в конце | TDD + двойное review в implementation loop |
| **Flow** | 13 фиксированных шагов | Адаптивный — brainstorm сам решает нужен ли план |
| **Стек** | Кастомный config + stack rules | CLAUDE.md (tool-agnostic) |

---

## 2. Архитектура

```
┌─────────────────────────────────────────────┐
│           No-One (оркестрация)               │
│                                             │
│  n1.config.json   Memory    Escalation      │
│  Tracker MCP       Observability             │
│                                             │
│  /n1-start = клей:                           │
│    тикет/brain dump → brainstorming (SP) →   │
│    writing-plans (SP) → subagent-driven (SP) │
│    → review → PR → обновляет трекер          │
└──────────────┬──────────────────────────────┘
               │ вызывает as-is
               ▼
┌─────────────────────────────────────────────┐
│         Superpowers (движок)                 │
│                                             │
│  brainstorming          systematic-debugging │
│  writing-plans          requesting-code-rev  │
│  subagent-driven-dev    finishing-branch      │
│  executing-plans        dispatching-parallel  │
│  test-driven-dev        receiving-code-rev    │
│  verification-before-completion              │
└─────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│         Инфраструктура                       │
│                                             │
│  MCP Adapters          Programs (node CLI)   │
│  ├── Atlassian (Jira)  ├── git-*             │
│  ├── YouTrack          ├── gh-*              │
│  ├── Linear (future)   └── diff-*            │
│  └── configurable                            │
└─────────────────────────────────────────────┘
```

### Три слоя

**Слой 1 — No-One Skills (оркестрация).** 5 markdown skills, запускаемых через slash commands. Judgment-heavy: scoping, routing, escalation. Вызывают Superpowers skills и MCP tools.

**Слой 2 — Superpowers (движок).** Используются as-is, без модификации. Brainstorming, planning, implementation, review, debugging — вся тяжёлая работа.

**Слой 3 — Инфраструктура.** MCP-серверы для трекеров/сервисов + детерминированные Node.js programs для git/GitHub операций.

---

## 3. Каталог Skills

### `/n1-start` — Core Orchestrator

Единственная точка входа для работы над задачей.

**Входы:**
- Brain dump от Tech Lead: `/n1-start нужен CSV экспорт пользователей`
- Тикет из трекера: `/n1-start TRID-510`

**Адаптивный flow:**

```
/n1-start
  │
  ├── Вход: тикет? → читает через MCP tracker adapter
  │   Вход: brain dump? → как есть
  │
  ▼
Brainstorm (superpowers/brainstorming) ← ВСЕГДА
  │ Итеративный диалог с Tech Lead
  │ Может флагнуть: "задача сырая, нужен бизнес-анализ"
  │
  ├── Задача простая, всё понятно
  │     → сразу в Implementation Loop
  │
  └── Задача сложная / нужен research
        │
        ▼
      Plan + Research (superpowers/writing-plans)
        │ Code exploration (Grep/Read)
        │ Web research (WebSearch, context7 MCP)
        │ Альтернативы с обоснованием
        │
        ▼
      Tech Lead аппрувит план ← ФИКСИРОВАННЫЙ CHECKPOINT
        │
        ▼
Implementation Loop (superpowers/subagent-driven-development)
  │ Per task: implement → TDD → self-verify → next
  │ Цикл пока вся "команда" не подтвердит готовность
  │ Confidence-based эскалация при неуверенности
  │
  ▼
Full Code Review (superpowers/requesting-code-review)
  │ Глубокий архитектурный review всего scope
  │
  ├── fail → назад в Implementation Loop
  └── pass ↓
        │
        ▼
      /n1-pr → создание PR
        │
        ▼
      Tech Lead Review ← ФИКСИРОВАННЫЙ CHECKPOINT
        │
        ▼
      Обновление трекера через MCP (статус → Done)
        │
        ▼
      Сохранение memory (per-ticket context, learnings)
```

**Между вызовами superpowers skills оркестратор делает:**
- Формирует контекст: тикет, project conventions, related code
- Передаёт результат предыдущего шага как вход следующего
- Управляет memory: читает per-ticket context, сохраняет findings
- Решает escalation: спрашивать Tech Lead или продолжать
- Обновляет трекер: статусы, комментарии через MCP

### `/n1-pr` — Создание Pull Request

Standalone skill для создания PR. Вызывается из `/n1-start` или отдельно.

**Что делает:**
- Собирает diff текущей ветки vs default branch
- Формирует PR title + description из контекста задачи
- Git commit → push → `gh pr create`
- Линкует PR к тикету в трекере

**Programs используемые:** git operations (commit, push), gh (pr create).

### `/n1-review` — Deep Code Review

Standalone skill для code review вне основного flow.

**Когда использовать:**
- Ревью чужого PR
- Повторный ревью после правок
- Ревью перед merge

**Что делает:**
- Читает diff PR (через `gh pr diff` или git diff)
- Запускает superpowers `requesting-code-review`
- Формирует structured отчёт: critical → important → minor
- Опционально: постит review comments в GitHub

### `/n1-init` — Первоначальная настройка

13 → 3 шага setup wizard:

```
Шаг 1: CLAUDE.md
  ├── Не существует → предложить /init (стандартный Claude Code)
  └── Существует → анализ репозитория:
        ├── Какой стек (package.json, composer.json, etc.)
        ├── Docker? → docker-обёртки для команд
        ├── Monorepo? → структура сервисов
        └── Чего не хватает в CLAUDE.md → предложить дополнения
              (команды test/build/lint, conventions)
              → Tech Lead аппрувит → дописать

Шаг 2: n1.config.json
  ├── Tracker: какой MCP, prefix тикетов, workflow statuses
  ├── Git: repo, default branch, branch naming pattern
  └── Hub: URL + token (опционально)

Шаг 3: Создать структуру
  ├── .n1/ directory
  ├── .n1/memory/ (per-ticket context)
  ├── docs/plans/ (если нет)
  └── .gitignore additions
```

---

## 4. Модель распределения AI-моделей

| Задача | Модель | Обоснование |
|---|---|---|
| Brainstorming, planning, architecture | **Opus** | Критичные решения, глубина рассуждений |
| Implementation (complex) | **Opus** | Качество кода — приоритет |
| Code review | **Opus** | Пропущенный баг дорого стоит |
| Research (important) | **Opus** | Глубокий анализ альтернатив |
| Debugging (complex) | **Opus** | Root cause analysis требует глубины |
| Ticket reading, distillation | **Sonnet** | Механическая работа — fetch + format |
| File classification, diff categorization | **Sonnet** | Простая классификация |
| Research (routine lookups) | **Sonnet** | Поиск документации, простые вопросы |
| UI verification, smoke checks | **Sonnet** | Perception + execution |
| Health checks, status polling | **Sonnet** | Простые проверки |

**Принцип:** Sonnet только там, где ошибка дёшева в исправлении. Если неправильно прочитал тикет — перечитаем. Если неправильно спланировал архитектуру — переделываем всё.

---

## 5. Система эскалации

### Фиксированные checkpoints (всегда)

| Момент | Что видит Tech Lead |
|---|---|
| После brainstorm → plan | Полный план с findings и альтернативами |
| После implementation → PR | Diff, description, test results |

### Confidence-based эскалация

AI оценивает каждое решение по двум осям:

```
                    High confidence
                         │
            Автономно    │    Автономно
                         │
  Low blast ─────────────┼──────────── High blast
     radius              │              radius
                         │
            Автономно    │   ЭСКАЛАЦИЯ
            (предупредить)│
                         │
                    Low confidence
```

**Эскалация (стоп + вопрос Tech Lead):**
- Low confidence + High blast radius: "Не уверен как реализовать auth middleware, и это затрагивает все endpoints. Варианты: A, B, C. Рекомендую B потому что..."

**Автономно с предупреждением:**
- Low confidence + Low blast radius: "Выбрал формат даты ISO-8601, не уверен что подходит для UI, но это легко поменять"

**Полная автономия:**
- High confidence (любой blast radius): AI уверен и действует

### Категории решений и дефолтный уровень

| Категория | Blast radius | Дефолт |
|---|---|---|
| Архитектурное решение (новый паттерн, структура) | High | Checkpoint |
| Security-related (auth, permissions, secrets) | High | Checkpoint |
| API contract (public endpoints, response format) | High | Confidence-based |
| Implementation detail (internal logic, naming) | Low | Автономно |
| Test strategy (что тестировать, как) | Medium | Автономно |
| Dependency choice (новая библиотека) | Medium | Confidence-based |

---

## 6. Memory — Persistence между сессиями

### Файловая структура

```
project/
├── docs/
│   └── plans/                          # Дизайн-документы и планы
│       ├── 2026-05-26-csv-export-design.md    # brainstorming output
│       └── 2026-05-26-csv-export.md           # implementation plan
│
├── .n1/
│   ├── n1.config.json                  # n1-specific конфигурация
│   ├── memory/                         # Per-ticket контекст
│   │   ├── TRID-510.md                 # Findings, решения, rejected hypotheses
│   │   └── TRID-511.md
│   ├── decisions/                      # Architectural Decision Records
│   │   └── 001-auth-middleware.md      # Долгосрочная память проекта
│   └── telemetry/                      # Observability (gitignored)
│       ├── runs.jsonl                  # Skill execution logs
│       └── observations.jsonl          # Self-improvement observations
│
└── CLAUDE.md                           # Project source of truth (tool-agnostic)
```

### Per-ticket context (`.n1/memory/<KEY>.md`)

Создаётся автоматически при `/n1-start <KEY>`. Обновляется в процессе работы.

```markdown
# TRID-510: CSV Export Users

## Status
In Progress — implementation step 3/5

## Findings
- Export controller: app/Http/Controllers/ExportController.php
- Existing CSV logic: app/Services/CsvService.php (используется для отчётов)
- 50k+ users в production — нужен streaming, не загрузка в память

## Decisions
- Streaming через LazyCollection (не chunked array) — память O(1)
- Формат: RFC 4180 compliant CSV с BOM для Excel compatibility

## Rejected
- Queue-based export — overkill для текущего объёма
- XLSX формат — зависимость от PhpSpreadsheet, не оправдана

## Open Questions
- (resolved) Нужна ли фильтрация? → Да, по role и created_at
```

### Checkpoint recovery

Если сессия прервалась, `/n1-start TRID-510`:
1. Читает `.n1/memory/TRID-510.md`
2. Видит "Status: In Progress — step 3/5"
3. Читает план из `docs/plans/`
4. Проверяет git log — что уже сделано
5. Продолжает с места остановки, не с начала

### Architectural Decision Records (`.n1/decisions/`)

Для решений, которые переживают конкретную задачу:

```markdown
# ADR-001: Auth middleware pattern

## Context
Нужен единый auth middleware для всех API endpoints.

## Decision
Token-based auth через Laravel middleware с Redis cache для sessions.

## Alternatives considered
- Session-based (rejected: не подходит для API clients)
- JWT (rejected: revocation complexity)

## Consequences
- Все API endpoints требуют Bearer token
- Redis dependency для session store
```

---

## 7. Tracker Abstraction (MCP)

### Архитектура

```
n1-start / n1-pr
    │
    ▼
Tracker Adapter (в skill body)
    │ читает n1.config.json → tracker.mcp
    │
    ├── mcp == "plugin_atlassian_atlassian"
    │     → mcp__plugin_atlassian_atlassian__getJiraIssue
    │     → mcp__plugin_atlassian_atlassian__transitionJiraIssue
    │     → mcp__plugin_atlassian_atlassian__addCommentToJiraIssue
    │
    ├── mcp == "youtrack"
    │     → mcp__youtrack__get_issue
    │     → mcp__youtrack__update_issue
    │     → mcp__youtrack__add_issue_comment
    │
    └── mcp == null (no tracker)
          → skip tracker operations
```

### Unified operations

Skill body содержит branching logic по `tracker.mcp`:

| Operation | Jira MCP | YouTrack MCP |
|---|---|---|
| Read ticket | `getJiraIssue` | `get_issue` |
| Move status | `transitionJiraIssue` | `update_issue` |
| Add comment | `addCommentToJiraIssue` | `add_issue_comment` |
| Search | `searchJiraIssuesUsingJql` | `search_issues` |
| Create issue | `createJiraIssue` | `create_issue` |

No custom programs needed — MCP covers all CRUD operations natively.

---

## 8. Observability

### Локальный уровень (MVP)

JSONL-файлы в `.n1/telemetry/` (gitignored):

**`runs.jsonl`** — каждый запуск skill'а:
```json
{
  "ts": "2026-05-26T14:30:00Z",
  "skill": "n1-start",
  "input": "TRID-510",
  "duration_ms": 180000,
  "success": true,
  "steps": ["brainstorm", "plan", "implement", "review", "pr"],
  "tokens_estimate": { "opus": 45000, "sonnet": 12000 },
  "escalations": 1,
  "outcome": "PR #340 created"
}
```

**`observations.jsonl`** — self-improvement:
```json
{
  "ts": "2026-05-26T14:30:00Z",
  "severity": "med",
  "category": "gap",
  "skill": "n1-start",
  "text": "Brainstorm не предложил web research для выбора CSV библиотеки"
}
```

### Hub API (future — отдельный документ)

См. `docs/plans/n1-hub-api-spec.md` (TODO).

Endpoints (draft):
- `POST /api/runs` — skill execution telemetry
- `POST /api/observations` — self-improvement observations
- `GET /api/runs?project=<id>` — dashboard data
- `GET /api/observations?status=new` — admin review

---

## 9. Система ролей в AI-команде

Роли не реализуются отдельными агентами — они встроены в superpowers pipeline:

| Роль | Реализация | Модель |
|---|---|---|
| **PM** | `brainstorming` — итеративный дизайн, scope, AC | Opus |
| **Senior Developer** | `writing-plans` — детальный план + research | Opus |
| **Developer** | `subagent-driven-development` implementer | Opus |
| **QA** | `test-driven-development` + `verification-before-completion` | Opus |
| **Code Reviewer** | `requesting-code-review` — spec + quality review | Opus |
| **DevOps** | `finishing-a-development-branch` + `n1-pr` | Opus |
| **Debugger** | `systematic-debugging` (при багах в implementation loop) | Opus |
| **Ticket Reader** | Sonnet subagent — fetch + distill ticket | Sonnet |

Tech Lead (человек) вмешивается на checkpoints и при эскалации.

---

## 10. Конфигурация

### `n1.config.json`

```json
{
  "version": "0.1.0",
  "tracker": {
    "mcp": "plugin_atlassian_atlassian",
    "prefix": "TRID",
    "projectKey": "TRID",
    "statuses": {
      "todo": "To Do",
      "inProgress": "In Progress",
      "review": "In Review",
      "done": "Done"
    }
  },
  "git": {
    "repo": "Ideom/tridentweb",
    "defaultBranch": "main",
    "branchPattern": "{prefix}-{id}"
  },
  "escalation": {
    "checkpoints": ["plan", "pr"],
    "confidenceThreshold": "medium",
    "alwaysAskOn": ["security", "architecture", "public-api"]
  },
  "hub": {
    "enabled": false,
    "url": null,
    "token": null
  },
  "memory": {
    "ticketContext": true,
    "decisions": true
  }
}
```

### CLAUDE.md (enriched by n1-init)

n1-init добавляет **только tool-agnostic** информацию:

```markdown
## Stack
- **Framework:** Laravel 5.6
- **Runtime:** PHP 7.2, Node.js (frontend assets)
- **Database:** MySQL 8.4
- **Containerization:** Docker Compose

## Commands
docker compose exec app php artisan migrate
docker compose exec app ./vendor/bin/phpunit
npm run dev
npm run prod

## Project Structure
- app/Http/Controllers/ — HTTP controllers
- app/Services/ — business logic services
- resources/views/ — Blade templates
- ...
```

---

## 11. File Layout

### Plugin (distributed)

Структура совместима с Claude Code plugin convention (аналогично Superpowers):

```
n1/
├── .claude-plugin/
│   └── plugin.json             # Plugin manifest (name, version, author)
├── commands/                   # Slash-command thin wrappers
│   ├── start.md                # /start → delegates to n1:n1-start skill
│   ├── pr.md                   # /pr → delegates to n1:n1-pr skill
│   ├── review.md               # /review → delegates to n1:n1-review skill
│   └── init.md                 # /init → delegates to n1:n1-init skill
├── skills/
│   ├── n1-start/SKILL.md       # Core orchestrator
│   ├── n1-pr/SKILL.md          # PR creation
│   ├── n1-review/SKILL.md      # Code review
│   └── n1-init/SKILL.md        # Project setup + reconfigure
├── agents/                     # Subagent templates
│   └── ticket-reader.md        # Sonnet — ticket distillation
├── hooks/
│   ├── hooks.json              # Hook declarations (SessionStart)
│   └── session-start.sh        # Auto-load n1 context into session
├── programs/                   # Deterministic CLI tools
│   ├── git-commit/
│   │   ├── program.mjs
│   │   └── schema.json
│   ├── git-push/
│   │   ├── program.mjs
│   │   └── schema.json
│   └── gh-pr-create/
│       ├── program.mjs
│       └── schema.json
└── lib/                        # Shared helpers
    └── tracker-adapter.mjs     # MCP routing logic
```

**Ключевые convention (из ресерча Superpowers):**
- `.claude-plugin/plugin.json` — единственный обязательный файл, без `files[]` или `skills[]` — всё discoverable по convention (директории `skills/`, `commands/`, `agents/`, `hooks/`)
- `commands/*.md` — thin wrappers с `disable-model-invocation: true`, тело: одна строка `Invoke the n1:<skill> skill`
- `skills/<name>/SKILL.md` — frontmatter: `name:` + `description:`, регистрируется автоматически
- `agents/*.md` — frontmatter: `name:`, `description:`, `model: sonnet|inherit`
- Кросс-ссылки между skills — текстовые `n1:<name>` или `superpowers:<name>` в теле SKILL.md

### Project (after n1-init)

```
project/
├── CLAUDE.md                   # Tool-agnostic project info (enriched)
├── .n1/
│   ├── n1.config.json          # n1-specific config
│   ├── memory/                 # Per-ticket context (committed)
│   │   └── .gitkeep
│   ├── decisions/              # ADRs (committed)
│   │   └── .gitkeep
│   └── telemetry/              # Logs (gitignored)
│       └── .gitkeep
├── docs/
│   └── plans/                  # Design docs & plans (committed)
└── .gitignore                  # Updated with .n1/telemetry/
```

---

## 12. Портируемость

### Claude Code (primary)

Полная функциональность: skills, subagents, MCP, hooks, slash commands.

### Cursor (secondary, architectural compatibility)

| Компонент | Совместимость | Адаптация |
|---|---|---|
| Skills → Commands | 70-80% | Переименование dirs, frontmatter |
| Subagents | Нативная | `.cursor/agents/*.md` формат почти идентичен |
| MCP | Нативная | Конфиг формат совместим |
| Hooks | 90% | JSON формат похож |
| Programs | 100% | Node.js CLI — platform-independent |

### Другие IDE

Windsurf, Cline — деградация до "rules + programs" без субагентной оркестрации. Не приоритет.

---

## 13. Зависимости и ограничения

### Обязательные зависимости

| Зависимость | Зачем |
|---|---|
| Claude Code | Платформа для skills, agents, slash commands |
| Superpowers plugin | Движок (brainstorming, subagent-driven-dev, etc.) |
| Node.js | Programs (git-*, gh-*) |
| Git + GitHub CLI (gh) | VCS операции, PR creation |

### Опциональные

| Зависимость | Зачем |
|---|---|
| MCP tracker server | Интеграция с трекером задач |
| Hub server | Централизованная observability |

### Zero external npm dependencies

Programs и lib — только стандартные Node.js модули (`node:fs`, `node:path`, `node:https`, `node:crypto`). Никаких npm packages.

---

## 14. MVP Scope

### Phase 1 — Минимальный рабочий flow

1. **`/n1-init`** — setup wizard (CLAUDE.md enrichment + n1.config.json)
2. **`/n1-start`** — core orchestrator (brainstorm → plan → implement → review → PR)
3. **`/n1-pr`** — PR creation
4. Per-ticket memory (`.n1/memory/`)

### Phase 2 — Полировка

5. **`/n1-review`** — standalone code review
6. Checkpoint recovery (resume interrupted sessions)
7. ADR system (`.n1/decisions/`)
8. Local telemetry (`.n1/telemetry/`)

### Phase 3 — Scale

9. Hub API spec
10. Cursor compatibility layer
11. Self-improvement loop (observations → patterns → fixes)

---

## 15. Open Questions

1. **Programs scope** — какие git/gh programs нужны для MVP, или достаточно inline bash в skills?
2. **Ticket reader subagent** — нужен ли отдельный Sonnet subagent для ticket distillation, или MCP + inline processing достаточно?
3. **Session-start hook** — что инжектировать в контекст при старте сессии?
4. **Self-improvement** — переиспользовать Loop'овскую модель observations или упростить?
5. **Plugin distribution** — marketplace или приватный git repo?
