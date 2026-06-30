# Case 07 — Agent auto-selection (Node, seeded specialist agents)

**Stack** Node (TS) · **Shape** project with specialized agents in the inventory

Cases 1–5 run with no project agents, so every task falls back to `general` and the
plan's **agent auto-selection never gets exercised**. This case seeds two specialist
agents and a feature touching both their file patterns, so `plan` must discover the
inventory (`list-agents.sh`), score each task, and annotate the choice.

**Stresses:** `plan` agent auto-selection — inventory discovery, file-pattern scoring, and
the `[harness: …]` / `[no-match: …]` / `[tie-broken]` annotations on every `Assignee:` line.

## Domain
A tiny web app with a React UI and an Express API in one repo. The feature — "add a
counter widget backed by a count endpoint" — touches both a `.tsx` component and a `.ts`
server route.

## Seed
`package.json`/`tsconfig.json` · `src/ui/App.tsx` (stub component) · `src/server/routes.ts`
(stub route) · **two project agents**: `.claude/agents/react-ui-specialist.md` (frontmatter
says it handles `*.tsx`/frontend) and `.claude/agents/express-api-specialist.md` (handles
`src/server/*.ts`/backend).

## Specify (verbatim)
> Add a counter widget: a React component `Counter.tsx` that shows a number and an
> increment button, backed by a `GET /count` and `POST /count/increment` API in
> `src/server`. The component calls the API.

## Run protocol
`init` → `specify` → `clarify` → `plan` (**the focus**) → `tasks`.

## What good looks like
- **plan**: runs `list-agents.sh`, finds the two specialists; the `.tsx` task is assigned
  `react-ui-specialist`, the `src/server/*.ts` task `express-api-specialist`, each with a
  `[harness: claude]` annotation — **not** a blanket `general`.
- A task matching no specialist (e.g. shared types) falls back to `general` with a
  `[no-match: <reason>]` annotation (visible, not silent).
- **tasks**: the chosen assignees survive into the bd tasks.

## Watch for
plan routing everything to `general` despite the seeded agents (inventory not discovered) ·
missing/!wrong annotations · assigning the `.tsx` task to the API agent or vice-versa ·
inventing an agent name not in the inventory.
