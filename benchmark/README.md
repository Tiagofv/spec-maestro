# Maestro Feature Benchmark

A reproducible benchmark for the Maestro spec-driven pipeline driven by **Claude Code**.
It runs 5 self-contained feature-building scenarios through the maestro commands and
scores each command so you can see **what works well and what breaks** — per command,
across stacks, and across feature shapes.

> All cases are generic toy projects (CLI tools, small APIs, libraries). They contain
> **no proprietary or company-specific code** and are safe for a public repository.

## What it measures

Maestro is a chain of commands where each stage produces an artifact that feeds the next:

```
specify → clarify → research → plan → tasks → implement → pm-validate → commit → analyze
                                                  └── inline review
   list / fork / research.list / research.search / respond  (cross-cutting)
```

The benchmark answers, per command:

- **Does it produce a correct, well-shaped artifact?** (the spec is clear, the plan is
  buildable, tasks have real dependencies, etc.)
- **Is it faithful to the constitution and the prior-stage artifact?** (no drift, no
  inventing requirements, no skipping ahead)
- **Is it autonomous?** (does the agent proceed, or stall / loop / ask redundant questions)
- **Cost** (wall-clock + agent turns) as a secondary signal.

The aggregate output is a **per-command scorecard** across all 5 cases. A command that
scores low in multiple cases is a real weak point in the pipeline, not a one-off.

## The 5 cases

| # | Case | Stack | Shape | Primary commands stressed |
|---|------|-------|-------|---------------------------|
| 1 | [CLI task tracker](cases/01-cli-task-tracker-go.md) | Go | Greenfield, well-scoped | Full happy path: specify→…→analyze |
| 2 | [URL shortener API](cases/02-url-shortener-node.md) | Node | Greenfield, design choices | `research`, `research.list`, `research.search` |
| 3 | [Static site generator](cases/03-static-site-generator-python.md) | Python | Greenfield, file I/O | Python compile gate, multi-file `plan`/`tasks` |
| 4 | [Notes API pagination](cases/04-notes-api-pagination-node.md) | Node | **Brownfield** (seed code) | `fork`, editing existing code |
| 5 | [Rate limiter library](cases/05-rate-limiter-go.md) | Go | **Ambiguous** requirements | `clarify` (heavy), `respond`, `analyze` |

Coverage of the 15 maestro commands across the 5 cases:

| Command | C1 | C2 | C3 | C4 | C5 |
|---------|----|----|----|----|----|
| `init` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `specify` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `clarify` | ✅ | ✅ | – | ✅ | ✅✅ |
| `research` | – | ✅ | – | – | ✅ |
| `research.list` | – | ✅ | – | – | – |
| `research.search` | – | ✅ | – | – | – |
| `plan` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `tasks` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `implement` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `pm-validate` | ✅ | – | ✅ | – | ✅ |
| `commit` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `analyze` | ✅ | – | – | – | ✅ |
| `list` | ✅ | – | – | ✅ | – |
| `fork` | – | – | – | ✅ | – |
| `respond` | – | – | – | – | ✅ |

Every command is exercised by at least one case; the high-risk commands
(`clarify`, `research`, `implement`) are exercised by several so a weak score is corroborated.

## How to run

### Prerequisites

Same as maestro itself — `bd`, `jq`, `python3`, `git`, plus the toolchain for the case's
stack (`go`, or Node + `pnpm`, or `python3` + `ruff`). And of course **Claude Code**.

### 1. Scaffold an isolated sandbox for a case

```bash
benchmark/scripts/setup-case.sh 01            # uses a temp dir under $TMPDIR
benchmark/scripts/setup-case.sh 01 ~/bench-01 # or a path you choose
```

This creates a throwaway git repo, installs maestro into it (via the `maestro` binary if
on PATH, else by copying `.maestro/` + `.claude/` from this repo), writes a case-tailored
`config.yaml` (generic `bench-` bd prefix — never `altpay-`), and seeds any starting files
the case needs. It prints the exact command sequence to run.

### 2. Drive the pipeline in Claude Code

`cd` into the sandbox, open Claude Code, and run the command sequence printed by the setup
script (it mirrors the **Run protocol** section of the case file). Run one command at a
time; after each, fill in its row of the scorecard while the behavior is fresh.

### 3. Score it

Copy [`RESULTS-TEMPLATE.md`](RESULTS-TEMPLATE.md) to `benchmark/results/<date>-caseNN.md`
and fill it in. Each command gets a 0–3 score on each rubric dimension plus a one-line
observation. The template computes nothing magic — it's a structured place to record what
happened so runs are comparable over time.

### 4. Aggregate

After running multiple cases, roll the per-command scores into the aggregate table at the
bottom of each results file (or a combined `results/SUMMARY.md`). The pattern you're
hunting for: **which commands score low across multiple cases** — those are the real
pipeline weaknesses worth fixing.

## Scoring rubric

Each command invocation is scored 0–3 on up to four dimensions. Not every dimension
applies to every command (e.g. `list` has no "faithfulness" axis); mark N/A and skip.

| Dimension | 0 | 1 | 2 | 3 |
|-----------|---|---|---|---|
| **Artifact** — is the output correct & well-shaped? | missing / wrong | major gaps | minor gaps | correct & complete |
| **Faithfulness** — true to constitution + prior artifact, no drift/invention | contradicts | notable drift | small drift | faithful |
| **Autonomy** — proceeds without stalls, loops, or redundant questions | stuck / needed rescue | heavy hand-holding | a nudge or two | fully autonomous |
| **Cost** — turns + wall-clock vs. the work | runaway | high | acceptable | tight |

A command's score for a case = mean of its applicable dimensions. A command's benchmark
score = mean across the cases that exercise it. Record the **observation** even when the
score is 3 — the qualitative note is where "what works best" actually lives.

## Interpreting results — what "works best / worst" means here

- **Works best**: commands that score ≥2.5 across every case that touches them, with
  observations noting clean autonomous artifacts. These are the load-bearing,
  trustworthy parts of the pipeline.
- **Works worst**: commands scoring ≤1.5 in two or more cases. Look at the observations
  for the failure mode (stalls? drift? bad artifact shape?) — that's the fix target.
- **Stack-sensitive**: compare the same command's score across Go (C1/C5), Node (C2/C4),
  and Python (C3). A command that's fine in Go but breaks in Python is a compile-gate or
  template-coverage gap, not a logic gap.
- **Shape-sensitive**: greenfield (C1/C2/C3) vs brownfield (C4) vs ambiguous (C5). A
  command that only works greenfield tells you where the pipeline assumes a clean slate.

## Notes & limitations

- Maestro commands are **agent-driven** (Claude Code reads markdown and acts), so the
  benchmark is **operator-in-the-loop**, not a single `make bench`. The setup script and
  case protocols make each run deterministic and comparable; the scoring is human (or a
  driving agent) judging against the rubric.
- Cases are intentionally small (XS–M features) so a full pipeline run finishes in one
  sitting and the bottleneck is maestro's behavior, not the size of the feature.
- Keep sandboxes out of this repo (the setup script defaults to `$TMPDIR`). Never commit a
  sandbox back — only the case definitions, scripts, rubric, and your `results/` files
  belong here.
