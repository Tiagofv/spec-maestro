---
description: >
  Run pre-planning technical research for a specified feature.
  Produces structured research artifacts and updates feature state
  with readiness metadata for /maestro.plan.
argument-hint: [feature-id] (optional, defaults to most recent)
---

# maestro.research

Generate pre-planning research artifacts for the feature.

## Step 1: Prerequisites Check

Run the prerequisite check:

```bash
bash .maestro/scripts/check-prerequisites.sh research
```

If it fails, show the error and suggestion, then stop.

## Step 2: Resolve Feature Context

If `$ARGUMENTS` contains a feature ID, use it. Otherwise, find the most recent feature in `.maestro/specs/`.

Read:

- The spec file: `.maestro/specs/{feature_id}/spec.md`
- The constitution: `.maestro/constitution.md` (if exists)
- The state file: `.maestro/state/{feature_id}.json`

If `spec.md` or state is missing, stop and tell the user exactly which file is missing.

## Step 3: Validate Inputs and Boundaries

Validate command boundaries before starting research:

1. Feature ID resolves to an existing directory under `.maestro/specs/`
2. Spec and state files are readable
3. Parallelism is within bounds:
   - default: `2`
   - max: `5`
   - reject values outside `2..5`
4. Never log credentials, tokens, or secret values in command output or state history

If validation fails, stop with corrective guidance.

## Step 4: Use Fixed Research Agent Set (MVP)

Use a fixed, non-configurable research agent set for MVP. Do not allow custom domain swapping in this command.

Fixed agent tracks:

1. **Technology Options** -> `research/technology-options.md`
2. **Pattern Catalog** -> `research/pattern-catalog.md`
3. **Pitfall Register** -> `research/pitfall-register.md`
4. **Competitive Analysis** -> `research/competitive-analysis.md`
5. **Synthesis and Readiness** -> `research/synthesis.md`

The first four tracks gather domain findings. The synthesis track consolidates all domain outputs and determines planning readiness.

## Step 5: Execute with Bounded Parallelism

Run research in parallel with bounded workers:

- Start with `2` parallel tracks by default
- Allow expansion up to `5` tracks when additional coverage is needed
- Never exceed `5` concurrent tracks

Execution expectations:

- Domain tracks may run in parallel
- Synthesis runs after domain outputs are available
- If a track fails to write its artifact, stop and report the failing path

## Step 6: Generate Artifact Outputs

Create or update `.maestro/specs/{feature_id}/research/` with:

- `technology-options.md`
- `pattern-catalog.md`
- `pitfall-register.md`
- `competitive-analysis.md`
- `synthesis.md`

Content minimums for each domain artifact:

1. Findings
2. Recommendations
3. Risks and mitigations
4. References

`synthesis.md` must include:

1. Decision-ready recommendations
2. Adopt-now vs defer split
3. Planning readiness verdict: `ready` or `not_ready`
4. Open questions carried into planning
5. Major recommendation fields: Decision, Rationale, Alternatives, Confidence
6. Ambiguities labeled as blocker vs non-blocker
7. Comparison of at least 3 external approaches with trade-offs and one preferred direction

If readiness is `not_ready`, list missing minimum items explicitly.

## Step 7: Update State (Additive Only)

Update `.maestro/state/{feature_id}.json` without removing existing fields.

Set or update:

- `stage`: `research`
- `research_path`
- `research_artifacts` (ordered relative paths for all generated files under `research/`)
- `research_artifact_pointers` object with keys:
  - `technology_options`
  - `pattern_catalog`
  - `pitfall_register`
  - `competitive_analysis`
  - `synthesis`
- `research_ready`
- `research_completed_at` (ISO-8601 UTC)
- `research_bypass_acknowledged`: `false` (reset after fresh research run)
- `research_parallel_agents_default`: `2`
- `research_parallel_agents_max`: `5`
- `research_parallel_agents_used` (integer in `1..5`)
- append history entry with stage transition and timestamp

State update expectations:

- Preserve existing history entries; append only
- Log stage transition in history every time this command runs
- Preserve all unknown/legacy state fields; never delete or rename existing keys
- Treat missing research fields as compatible legacy state and add only research-related keys
- Keep logs and history free from credentials and secrets

## Step 8: Report Results and Next Steps

Show the user:

1. Generated artifact paths
2. Parallelism profile used (`default=2`, `max=5`, `used=N`)
3. Planning readiness verdict from `synthesis.md`
4. If not ready, missing minimum items and suggested follow-up
5. Suggest next command: `/maestro.plan {feature_id}`

---

**Remember:** This command defines the explicit research phase between specification and planning. Keep outputs structured, human-editable, and state-tracked.
