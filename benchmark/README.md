# Maestro Feature Benchmark

Runs 10 generic feature-building scenarios through the maestro pipeline with **Claude Code**
and scores each command, so you can see **what works and what breaks** across stacks and
feature shapes. All cases are toy projects with **no proprietary code** (safe for a public repo).

## How it runs (the key idea)

Maestro commands are agent-driven, and the command markdown is large (~21K words total —
`research.md` alone is ~4K). Running a whole pipeline in one interactive session burns
context fast. So the runner drives **each stage as an isolated `claude -p` process**:
fresh context per stage, state shared on disk (`.maestro/specs`, bd db, git). A full run
costs a fraction of an interactive session, and the calling session stays clean.

```
benchmark/scripts/setup-case.sh 01 [dir]     # scaffold a disposable sandbox
benchmark/scripts/run-case.sh   01 [dir]     # headless run → .bench/report.tsv + PROBLEMS.md
benchmark/scripts/fix-loop.sh   01 plan [dir] # re-run ONE stage, diff status/turns/cost vs last
```

`run-case.sh` env: `STAGES="specify clarify plan"` (default slice), `MAX_TURNS`, `MODEL`.

## The 10 cases

Cases 1–5 cover the core pipeline across stacks and feature shapes. Cases 6–10 are
**complementary** — each targets a spec-maestro mechanism the first five never exercise.

| # | Case | Stack | Shape | Stresses |
|---|------|-------|-------|----------|
| 1 | [CLI task tracker](cases/01-cli-task-tracker-go.md) | Go | greenfield, well-scoped | full happy-path baseline |
| 2 | [URL shortener](cases/02-url-shortener-node.md) | Node | design choices | `research`, `research.list/search` |
| 3 | [Static site gen](cases/03-static-site-generator-python.md) | Python | well-specified | Python gate, `clarify` restraint |
| 4 | [Notes pagination](cases/04-notes-api-pagination-node.md) | Node | **brownfield** | `fork`, editing existing code |
| 5 | [Rate limiter](cases/05-rate-limiter-go.md) | Go | **ambiguous** | `clarify` reach, `analyze` |
| 6 | [Multi-repo feature](cases/06-multi-repo-go.md) | Go ×2 | **multi-repo** | `**Repos:**` header + per-task `**Repo:**` (feat-062) |
| 7 | [Agent auto-selection](cases/07-agent-routing-node.md) | Node | seeded agents | `plan` inventory scoring + assignee annotations |
| 8 | [Constitution + review](cases/08-constitution-review-go.md) | Go | strict constitution | constitution enforcement → **CRITICAL** → fix chain → `analyze` |
| 9 | [Gate failure + regression](cases/09-gate-failure-regression-node.md) | Node | brownfield trap | `implement` gate-loop + `pm-validate` regression scan |
| 10 | [Idempotency & resume](cases/10-idempotency-resume-go.md) | Go | re-run stages | `tasks` idempotency, `specify` refine, `implement` resume |

### Command coverage (13 commands; `commit`/`respond` were removed from maestro)

✅ = exercised, ✅✅ = primary stressor. Every command is hit by ≥1 case.

| Command | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---------|--|--|--|--|--|--|--|--|--|--|
|`init`|✅|✅|✅|✅|✅|✅|✅|✅|✅|✅|
|`specify`|✅|✅|✅|✅|✅|✅|✅|✅|✅|✅✅|
|`clarify`|✅|✅|–|✅|✅✅|✅|✅|✅|✅|✅|
|`research`|–|✅✅|–|–|✅|–|–|–|–|–|
|`research.list/search`|–|✅✅|–|–|–|–|–|–|–|–|
|`plan`|✅|✅|✅|✅|✅|✅|✅✅|✅|✅|✅|
|`tasks`|✅|✅|✅|✅|✅|✅✅|✅|✅|✅|✅✅|
|`implement`|✅|✅|✅|✅|✅|✅|–|✅|✅✅|✅|
|`pm-validate`|✅|–|✅|–|✅|–|–|✅|✅✅|–|
|`analyze`|✅|–|–|–|✅|–|–|✅✅|–|–|
|`list`|✅|–|–|✅|–|–|–|–|–|–|
|`fork`|–|–|–|✅✅|–|–|–|–|–|–|

### Mechanism coverage (what the complementary cases add)

| Mechanism | Case |
|-----------|------|
| Multi-repo `**Repos:**` header + per-task `**Repo:**` (feature 062) | 6 |
| `plan` agent auto-selection (inventory scoring + `[harness]`/`[no-match]` annotations) | 7 |
| Constitution enforcement → review **CRITICAL** → fix chain → `analyze` bug/fix metrics | 8 |
| `implement` compile-gate failure loop + `pm-validate` regression detection | 9 |
| Idempotency guards: `tasks` re-run, `specify` refine, `implement` resume / worktree guard | 10 |

## Scoring

Each invoked command is scored 0–3 on the dimensions that apply (mark others N/A):

- **Artifact** — output correct & well-shaped? (0 missing/wrong … 3 complete)
  - For `specify`/`clarify`, "well-shaped" **requires EARS acceptance criteria**: each
    criterion is one atomic When/While/If…then/Where/shall sentence, and every `When …`
    happy path has a matching `If …, then …` failure/edge path. Free-prose criteria, or
    happy paths with no failure criterion, cap the Artifact score at ≤2. See cases 01 & 05.
- **Faithfulness** — true to constitution + prior artifact, no drift/invention?
- **Autonomy** — proceeds without stalls, loops, or redundant questions?
- **Cost** — turns + wall-clock vs. the work? (the runner records this automatically)

Command score = mean of applicable dims; benchmark score = mean across cases that touch it.
**Always record the one-line observation** — that's where "what works best" lives.

Copy [`RESULTS-TEMPLATE.md`](RESULTS-TEMPLATE.md) → `results/<date>-caseNN.md`. The runner
pre-fills cost/turns/status into `.bench/report.tsv`; you add the qualitative scores.

## Reading the results

- **Works best**: ≥2.5 across every case that touches it — load-bearing, trustworthy.
- **Worst**: ≤1.5 in ≥2 cases — read the `PROBLEMS.md` failure mode; that's the fix target.
- **Stack-sensitive**: same command across Go (C1/C5) vs Node (C2/C4) vs Python (C3) →
  a gap that's stack-specific is a compile-gate/template issue, not logic.
- **Shape-sensitive**: greenfield (C1–C3) vs brownfield (C4) vs ambiguous (C5).

## Fix pipeline (local loop)

1. `run-case.sh` → read `.bench/PROBLEMS.md` (concise; no transcript dump).
2. Edit the offending file in **this repo's** `.maestro/` (command/skill/script/template).
3. `setup-case.sh` re-copies `.maestro/` into a fresh sandbox; `fix-loop.sh <id> <stage>`
   re-runs just that stage and prints status/turns/cost **before vs after** so you can
   confirm the fix without rerunning the whole pipeline.
4. Repeat until `PROBLEMS.md` is empty and cost trends down.

## Notes

- `ruff` is required for Case 3's Python gate; install it or expect that gate to be skipped.
- Sandboxes are disposable and default to `$TMPDIR` — never commit one back. Only the
  cases, scripts, rubric, and your `results/` belong in the repo.
