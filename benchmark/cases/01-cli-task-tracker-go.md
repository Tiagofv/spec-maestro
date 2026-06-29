# Case 01 — CLI task tracker (Go)

| | |
|---|---|
| **Stack** | Go |
| **Shape** | Greenfield, well-scoped |
| **Difficulty** | Baseline (XS–S feature) |
| **Goal** | Exercise the full happy path end-to-end with no traps, to establish a baseline for every command. |
| **Primary commands stressed** | `specify` → `clarify` → `plan` → `tasks` → `implement` → `pm-validate` → `commit` → `analyze` → `list` |

## Why this case

This is the control. A small, unambiguous greenfield feature in the simplest supported
stack. If a command scores low *here*, the problem is the command itself, not the
difficulty of the case. Every other case is read relative to this one.

## Domain (generic — no proprietary code)

A single-binary command-line task tracker that stores tasks as JSON in a local file. No
network, no database, no auth — just a CLI over a JSON file.

## Starting state

Greenfield. The setup script seeds only an empty Go module:

```
go.mod          // module example.com/tasktracker, go 1.21
main.go         // package main; func main() { } — empty entrypoint
```

## The feature to specify

Feed this verbatim to `/maestro.specify`:

> Add a command-line task tracker. Users can add a task with a title, list all tasks,
> mark a task done by its id, and delete a task by its id. Tasks persist to a JSON file
> in the working directory. Each task has an id, title, done flag, and created timestamp.

This is deliberately concrete so `clarify` has only a few real ambiguities to find
(e.g. file path/name, id scheme, behavior on missing id, output format).

## Run protocol

Run these in Claude Code from the sandbox, one at a time. Score each against the rubric
in the benchmark README before moving on.

1. `/maestro.init` — confirm config + constitution + harness mirror created.
2. `/maestro.specify "<the feature text above>"` — one numbered spec dir + branch.
3. `/maestro.clarify` — should surface a handful of `[NEEDS CLARIFICATION]` markers and
   resolve them. Answer them tersely and consistently.
4. `/maestro.plan` — a buildable plan: commands (`add`/`list`/`done`/`delete`), the JSON
   store, the task struct. Check `Assignee:` annotations are present and sane.
5. `/maestro.tasks` — a bd epic + impl tasks + review tasks + a pm-validation task, with
   real dependencies (store before commands, commands before CLI wiring).
6. `/maestro.implement` — loops ready tasks, inline-reviews, runs the Go compile gate
   (`go build ./... && go vet ./... && go test ./...`). Should end green.
7. `/maestro.pm-validate` — acceptance criteria + regression scan.
8. `/maestro.commit` — layer-separated atomic commits.
9. `/maestro.analyze` — post-epic metrics + improvement proposals (presented, not applied).
10. `/maestro.list` and `/maestro.list --all` — feature shows as active, then completed.

## What good looks like (checkpoints)

- **specify**: spec.md has user stories for all four operations + persistence, and
  acceptance criteria that assert literal behavior (e.g. "listing with no tasks prints
  `no tasks`").
- **clarify**: 3–6 markers, each a *real* ambiguity, each resolved in spec.md (not just
  asked and dropped).
- **plan**: names concrete files (`internal/store`, `cmd` wiring), picks a JSON encoding
  approach, doesn't invent a DB or a web server.
- **tasks**: dependency graph is a DAG with the store as a root; review + pm tasks exist.
- **implement**: produces compiling, vet-clean Go with at least smoke tests; the agent
  never marks a task done while the gate is red.
- **pm-validate**: maps each acceptance criterion to evidence; flags anything unmet.
- **commit**: commits grouped by layer (store, commands, CLI, tests), no "wip" blobs.
- **analyze**: concrete, actionable proposals tied to what actually happened in the run.

## Known failure modes to watch for

- `clarify` asking cosmetic questions instead of the real ambiguities, or asking and then
  not writing the answers back into spec.md.
- `plan` over-engineering (introducing a DB, an HTTP layer, or interfaces the spec
  doesn't need).
- `implement` declaring done with a red or skipped compile gate.
- `analyze` emitting generic advice not grounded in this run.
