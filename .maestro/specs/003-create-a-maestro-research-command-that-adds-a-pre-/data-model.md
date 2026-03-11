# Data Model: /maestro.research

**Feature ID:** 003-create-a-maestro-research-command-that-adds-a-pre-
**Related Plan:** .maestro/specs/003-create-a-maestro-research-command-that-adds-a-pre-/plan.md
**Last Updated:** 2026-02-20

## 1. Purpose

Define persisted and generated data structures for the new research phase so `/maestro.plan` can consume research outputs deterministically.

## 2. Entities

### 2.1 ResearchDomain

```text
ResearchDomain {
  key: "technology" | "patterns" | "pitfalls" | "competitive"
  title: string
  required: boolean
  output_path: string
}
```

Notes:

- Domain set is fixed for MVP.
- Research execution starts with 2 parallel agents by default and can expand to a maximum of 5.

### 2.2 ResearchArtifact

```text
ResearchArtifact {
  domain: ResearchDomain.key
  path: string
  generated_at: datetime
  status: "complete" | "partial" | "missing"
  findings_count: integer
  recommendations_count: integer
  risks_count: integer
}
```

### 2.3 ResearchSynthesis

```text
ResearchSynthesis {
  path: string
  generated_at: datetime
  recommendation_summary: string
  recommendation_entries: {
    decision: string
    rationale: string
    alternatives: string[]
    confidence: "high" | "medium" | "low"
  }[]
  adopt_now: string[]
  defer: string[]
  open_risks: string[]
  ambiguities: {
    blocker: string[]
    non_blocker: string[]
  }
  external_comparison_count: integer
  preferred_direction: string
  readiness: {
    is_ready: boolean
    missing_domains: string[]
    missing_minimum_items: string[]
    notes: string
  }
}
```

### 2.4 FeatureStateExtension (additive fields)

```text
FeatureStateExtension {
  research_path?: string
  research_ready?: boolean
  research_artifacts?: string[]
  research_completed_at?: datetime
  research_bypass_acknowledged?: boolean
  research_parallel_agents_default?: integer
  research_parallel_agents_max?: integer
  research_parallel_agents_used?: integer
}
```

## 3. File-Level Schema Expectations

### 3.1 Research Directory

Path: `.maestro/specs/{feature_id}/research/`

Required files for "ready" status:

- `technology-options.md`
- `pattern-catalog.md`
- `pitfall-register.md`
- `competitive-analysis.md`
- `synthesis.md`

### 3.2 State File Update Rules

Path: `.maestro/state/{feature_id}.json`

Rules:

1. Preserve all existing fields.
2. Add research fields only when research command runs.
3. `research_ready` is true only when all required domain files and synthesis exist.
4. Append history entries; never overwrite existing history.
5. Persist execution profile metadata with `research_parallel_agents_default=2` and `research_parallel_agents_max=5`.

## 4. Validation Rules

1. Every `research_artifacts` entry must resolve under `.maestro/specs/{feature_id}/research/`.
2. `research_ready=true` requires all required artifact files and synthesis.
3. `research_ready=true` requires synthesis minimum quality signal fields:
   - recommendation entries with decision/rationale/alternatives/confidence
   - ambiguity classification (blocker vs non-blocker)
   - at least 3 external approach comparisons
   - preferred direction
   - explicit readiness verdict with missing minimum items when not ready
4. `research_parallel_agents_default` must equal `2`; `research_parallel_agents_max` must equal `5`; and `research_parallel_agents_used` must be between 1 and 5.
5. If planning proceeds with `research_ready=false`, `research_bypass_acknowledged=true` must be present in the state update from planning.
6. State updates must be timestamped in ISO-8601 UTC.

## 5. Migration Notes

- Existing features without research fields remain valid.
- Planning logic should treat missing research fields as equivalent to `research_ready=false`.
- No destructive migration is required; this is an additive schema extension.
