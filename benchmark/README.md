# Maestro Feature Benchmark

Runs 5 generic feature-building scenarios through the maestro pipeline with **Claude Code**
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

## The 5 cases

| # | Case | Stack | Shape | Stresses |
|---|------|-------|-------|----------|
| 1 | [CLI task tracker](cases/01-cli-task-tracker-go.md) | Go | greenfield, well-scoped | full happy-path baseline |
| 2 | [URL shortener](cases/02-url-shortener-node.md) | Node | design choices | `research`, `research.list/search` |
| 3 | [Static site gen](cases/03-static-site-generator-python.md) | Python | well-specified | Python gate, `clarify` restraint |
| 4 | [Notes pagination](cases/04-notes-api-pagination-node.md) | Node | **brownfield** | `fork`, editing existing code |
| 5 | [Rate limiter](cases/05-rate-limiter-go.md) | Go | **ambiguous** | `clarify` reach, `respond`, `analyze` |

Coverage (✅ = exercised, ✅✅ = primary stressor): every one of the 15 commands is hit by ≥1 case.

| | C1 | C2 | C3 | C4 | C5 |  | | C1 | C2 | C3 | C4 | C5 |
|--|--|--|--|--|--|--|--|--|--|--|--|--|
|`specify`|✅|✅|✅|✅|✅| |`pm-validate`|✅|–|✅|–|✅|
|`clarify`|✅|✅|–|✅|✅✅| |`commit`|✅|✅|✅|✅|✅|
|`research`|–|✅✅|–|–|✅| |`analyze`|✅|–|–|–|✅|
|`research.list/search`|–|✅✅|–|–|–| |`list`|✅|–|–|✅|–|
|`plan`|✅|✅|✅|✅|✅| |`fork`|–|–|–|✅✅|–|
|`tasks`|✅|✅|✅|✅|✅| |`respond`|–|–|–|–|✅✅|
|`implement`|✅|✅|✅|✅|✅| | | | | | | |

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
