# Benchmark result — Case <NN> <case name>

- **Date:** YYYY-MM-DD
- **Operator / driving agent:**
- **maestro version:** `maestro --version` →
- **Claude Code model:**
- **Sandbox path:**
- **Toolchain versions:** (go / node+pnpm / python+ruff as relevant)

## Per-command scorecard

Score each invoked command 0–3 per dimension (see rubric in `benchmark/README.md`). Use
`–` for N/A. The **Score** column is the mean of the applicable dimensions.

| Command | Artifact | Faithful | Autonomy | Cost | Score | Observation (1 line — required) |
|---------|:--------:|:--------:|:--------:|:----:|:-----:|---------------------------------|
| `init` | | | | | | |
| `specify` | | | | | | |
| `clarify` | | | | | | |
| `research` | | | | | | |
| `research.list` | | | | | | |
| `research.search` | | | | | | |
| `plan` | | | | | | |
| `tasks` | | | | | | |
| `implement` | | | | | | |
| `pm-validate` | | | | | | |
| `commit` | | | | | | |
| `analyze` | | | | | | |
| `list` | | | | | | |
| `fork` | | | | | | |
| `respond` | | | | | | |

## Run notes

- **Total wall-clock:**
- **Compile gate:** passed / failed / skipped — details:
- **Stalls / rescues needed:** (which command, what was needed)
- **Surprises:** (anything the case file didn't anticipate)

## Verdict for this case

- **Worked best:** (commands ≥2.5 + why)
- **Worked worst:** (commands ≤1.5 + the failure mode)
- **Pipeline drift:** (did any stage contradict or ignore a prior artifact?)

---

## Aggregate across cases (fill in `results/SUMMARY.md` once ≥2 cases are run)

For each command, average its Score across every case that exercised it. Flag any command
averaging ≤1.5 (weak point) or ≥2.5 (load-bearing).

| Command | C1 | C2 | C3 | C4 | C5 | Mean | Flag |
|---------|:--:|:--:|:--:|:--:|:--:|:----:|------|
| `specify` | | | | | | | |
| `clarify` | | | | | | | |
| `research` | | | | | | | |
| `plan` | | | | | | | |
| `tasks` | | | | | | | |
| `implement` | | | | | | | |
| `pm-validate` | | | | | | | |
| `commit` | | | | | | | |
| `analyze` | | | | | | | |
| `fork` | | | | | | | |
| `respond` | | | | | | | |
| `list` | | | | | | | |
| `research.list` | | | | | | | |
| `research.search` | | | | | | | |
