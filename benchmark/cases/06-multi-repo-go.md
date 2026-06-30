# Case 06 — Multi-repo feature (Go, two modules)

**Stack** Go · **Shape** one feature spanning two repos/modules

The first 5 cases are all single-repo. This exercises the **feature-062 multi-repo
mechanism** nothing else touches: the spec/plan `**Repos:**` header, the per-task
`**Repo:**` field, and the validator rules that tie them together (header must be
non-empty; each task's `**Repo:**` must be a member of the header list).

**Stresses:** `**Repos:**` header, per-task `**Repo:**` routing, `tasks` validation of
both (and, with real worktrees, worktree-per-repo provisioning in `implement`).

## Domain
A small HTTP API split across two modules: `api/` (the HTTP handlers) and `store/` (an
in-memory data layer the API depends on). The feature — "add a health + items endpoint" —
touches both.

## Seed (two Go modules in one sandbox)
`api/go.mod` (module `example.com/api`) + `api/main.go` (empty server) ·
`store/go.mod` (module `example.com/store`) + `store/store.go` (empty package) ·
`.maestro/config.yaml` `repos:` maps `api` and `store`.

## Specify (verbatim)
> Add two endpoints to the API: `GET /health` returns `{"ok":true}`, and `GET /items`
> returns the list of items from the store. The store module gains an in-memory
> `Items() []Item` function the API calls. This work spans the `api` and `store` modules.

## Run protocol
`init` → `specify` (confirm `**Repos:** api, store`) → `clarify` → `plan` → `tasks` →
`implement`.

## What good looks like
- **specify/plan**: header is `**Repos:** api, store` (both, non-empty); plan assigns each
  task a `**Repo:**` of either `api` or `store`.
- **tasks**: passes validation — every task's `**Repo:**` is a member of the header list;
  store-layer tasks precede api-layer tasks in the DAG.
- **implement** (with worktrees): provisions a worktree per repo; store work lands in the
  `store` worktree, api work in the `api` worktree; both build.

## Watch for
plan emitting a single-repo header or omitting per-task `**Repo:**` (validator rejects) ·
a task whose `**Repo:**` isn't in the header (cross-repo leak) · the api task ordered
before the store function it depends on · worktree provisioning only one of the two repos.
