# Contracts: /maestro.research and Planning Readiness Gate

**Feature ID:** 003-create-a-maestro-research-command-that-adds-a-pre-
**Last Updated:** 2026-02-20

## 1. Command Contract: `/maestro.research [feature-id]`

### Inputs

- Optional `feature-id` argument; defaults to most recent directory under `.maestro/specs/`.
- Required files:
  - `.maestro/specs/{feature_id}/spec.md`
  - `.maestro/state/{feature_id}.json`
- Optional file:
  - `.maestro/constitution.md`

### Preconditions

1. `bash .maestro/scripts/check-prerequisites.sh research` exits 0.
2. Feature spec exists and is readable.
3. Feature state exists and is readable.

### Execution Constraints

1. Research agent set is fixed for MVP.
2. Parallel execution starts at 2 agents by default.
3. Parallel execution may expand up to a maximum of 5 agents.

### Outputs

Creates/updates files under `.maestro/specs/{feature_id}/research/`:

- `technology-options.md`
- `pattern-catalog.md`
- `pitfall-register.md`
- `competitive-analysis.md`
- `synthesis.md`

Updates `.maestro/state/{feature_id}.json` with additive research fields:

- `research_path`
- `research_artifacts`
- `research_ready`
- `research_completed_at`
- `research_parallel_agents_default` (must be `2`)
- `research_parallel_agents_max` (must be `5`)
- `research_parallel_agents_used`
- history entry with `stage=research`

### Failure Modes

- Missing prerequisites -> stop with explicit missing file/dependency guidance.
- Write failure in any artifact -> stop and report failed file path.
- State update failure -> stop and report retry guidance.

## 2. Command Contract: `/maestro.plan [feature-id]` (modified)

### Added Preconditions

1. If `research_ready=true`, planning continues normally.
2. If `research_ready=false` or missing, planner must emit warning and request explicit acknowledgement phrase.

### Bypass Acknowledgement

Required literal phrase:

`I acknowledge proceeding without complete research`

Behavior:

- Exact phrase present -> planning may proceed.
- Missing/incorrect phrase -> planning stops with guidance to run `/maestro.research`.

### Added Outputs

- Plan includes assumptions section when bypassing incomplete research.
- State may record `research_bypass_acknowledged=true` when bypass path is used.

## 3. Artifact Content Minimums

Each domain file must include:

1. Findings
2. Recommendations
3. Risks and mitigations
4. References (internal and/or external)

`synthesis.md` must include:

1. Decision-ready recommendations
2. Adopt-now vs defer split
3. Planning readiness determination (`ready` or `not_ready`)
4. Open questions carried to planning
5. For each major recommendation: Decision, Rationale, Alternatives, Confidence (`high|medium|low`)
6. Ambiguity classification as blocker vs non-blocker
7. Comparison of at least 3 external approaches with trade-offs and a preferred direction

Readiness quality gate:

- `ready` is valid only when all synthesis minimums above are present and all fixed research domains are covered.
- If `not_ready`, synthesis must list missing minimum items explicitly.

## 4. Non-Goals (Contract Scope)

- No cross-feature search/index behavior in this feature.
- No automated external scraping integration.
- No immutable artifact locking requirement.
