# Case 01 — CLI task tracker (Go)

**Stack** Go · **Shape** greenfield, well-scoped · **Role** baseline / control

The simplest supported stack with an unambiguous spec. If a command scores low *here*,
the problem is the command, not the case. Every other case is read relative to this one.

**Stresses:** the full happy path — `specify → clarify → plan → tasks → implement → pm-validate → commit → analyze → list`.

## Domain
A single-binary CLI task tracker storing tasks as JSON in a local file. No network/DB/auth.

## Seed (greenfield)
`go.mod` (module `example.com/tasktracker`) + empty `main.go`.

## Specify (verbatim)
> Add a command-line task tracker. Users can add a task with a title, list all tasks, mark
> a task done by its id, and delete a task by its id. Tasks persist to a JSON file in the
> working directory. Each task has an id, title, done flag, and created timestamp.

## Run protocol
`init` → `specify "<above>"` → `clarify` → `plan` → `tasks` → `implement` → `pm-validate`
→ `commit` → `analyze` → `list` / `list --all`. One command at a time; score each.

## What good looks like
- **specify**: 4 op stories + persistence; **every acceptance criterion is EARS-shaped**
  (e.g. "When the user runs `add <title>`, the system shall append a task with a new id";
  "If the id is unknown on `done`/`delete`, then the system shall report an error and exit
  non-zero"). Each happy-path `When …` has a matching `If …, then …`. No free-prose criteria,
  and `validate-spec-format.sh` exits 0 on the written spec (EARS shapes valid, every `When`
  paired with an `If…then`, no vague terms).
- **clarify**: 3–6 *real* ambiguities (file name, id scheme, missing-id behavior), each
  written back into spec.md as an EARS criterion.
- **plan**: concrete files (store, cmd wiring), JSON encoding; no invented DB/HTTP layer.
- **tasks**: DAG with the store as root; review + pm tasks present.
- **implement**: compiling, vet-clean Go + smoke tests; never marks done on a red gate.
- **pm-validate**: each EARS acceptance criterion mapped 1:1 to evidence (incl. the `If …`
  failure paths, not just the happy paths).
- **commit**: layered (store / commands / CLI / tests); no "wip".
- **analyze**: proposals grounded in this run, not boilerplate.

## Watch for
specify emitting free-prose criteria instead of EARS, or `When …` paths with no matching
`If …, then …` · clarify asking cosmetics or not persisting answers · plan over-engineering
(DB/HTTP) · implement declaring done on a red/skipped gate · pm-validate passing while an
`If …` failure criterion is unhandled · analyze emitting generic advice · specify/clarify
proceeding while validate-spec-format.sh still reports violations (validator output ignored).
