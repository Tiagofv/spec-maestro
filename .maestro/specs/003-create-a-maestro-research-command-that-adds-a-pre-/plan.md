# Implementation Plan: /maestro.research Pre-Planning Research Phase

**Feature ID:** 003-create-a-maestro-research-command-that-adds-a-pre-
**Spec:** .maestro/specs/003-create-a-maestro-research-command-that-adds-a-pre-/spec.md
**Created:** 2026-02-20
**Status:** Draft

---

## 1. Architecture Overview

### 1.1 High-Level Design

This feature introduces a first-class research stage between specification and planning by adding a new command prompt contract, research templates, and state transitions that make research outputs consumable by `/maestro.plan`.

The architecture remains a modular monolith and follows the project constitution layering:

- Presentation layer: `.maestro/commands/maestro.research.md` orchestrates user flow and gating behavior.
- Application workflow: `.maestro/scripts/check-prerequisites.sh` validates stage readiness and command preconditions.
- Persistence/artifacts: research outputs are written to `.maestro/specs/{feature_id}/research/` and indexed via `.maestro/state/{feature_id}.json`.
- Planning integration: `.maestro/commands/maestro.plan.md` reads synthesized research and enforces readiness/bypass acknowledgement.

Requirement mapping:

- Story 1 (technology investigation): `research/technology-options.md` generated from a standard template and synthesis rubric.
- Story 2 (pattern discovery): `research/pattern-catalog.md` with internal and external references.
- Story 3 (pitfall prevention): `research/risk-register.md` with mitigations.
- Story 4 (artifact persistence): state pointers and discoverable per-feature structure.
- Story 5 (planning readiness gate): readiness check + explicit user acknowledgement phrase before bypass.
- Story 6 (scope boundaries): bounded artifact set and completion checklist instead of timebox enforcement.

### 1.2 Component Interactions

1. User runs `/maestro.research [feature-id]`.
2. Prerequisite check validates `.maestro` structure and feature-state existence.
3. Command reads `spec.md`, `constitution.md` (if present), and feature state to determine required research domains.
4. Research starts with 2 parallel agent tracks by default and expands up to 5 tracks when additional coverage is needed.
5. Domain outputs are written under `.maestro/specs/{feature_id}/research/`.
6. `research/synthesis.md` is produced with recommendation ranking and planning-readiness signal.
7. State file is updated with `stage=research`, artifact paths, readiness flag, and history entry.
8. `/maestro.plan` consumes synthesis and either proceeds (ready) or requires explicit bypass acknowledgement string.

### 1.3 Key Design Decisions

| Decision                 | Options Considered                                                     | Chosen                                    | Rationale                                                                                      |
| ------------------------ | ---------------------------------------------------------------------- | ----------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Research command shape   | Add implicit planning sub-step vs explicit `/maestro.research` command | Explicit command                          | Satisfies explicit phase ownership and improves discoverability/readiness signaling.           |
| Research artifact format | Free-form notes vs structured templates per domain                     | Structured templates + synthesis file     | Ensures consistency, reuse, and direct plan consumption (Stories 1-4, Success 5).              |
| Research execution model | Sequential investigations vs bounded parallel tracks                   | Start at 2 tracks, scale up to max 5      | Aligns clarified scope: flexible throughput with explicit upper bound and predictable runtime. |
| Readiness gating         | Hard block planning vs bypass with acknowledgement                     | Soft gate with required explicit phrase   | Matches resolved clarification and preserves workflow flexibility (Story 5, Story 6).          |
| Cross-feature knowledge  | Build search index now vs per-feature storage only                     | Per-feature only, defer search            | Aligns resolved scope decision and avoids early indexing complexity.                           |
| Artifact mutability      | Read-only generated outputs vs editable markdown artifacts             | Human-editable markdown artifacts         | Matches clarified requirement and keeps research usable as living planning input.              |
| Quality gate definition  | Broad quality guidance vs enforceable minimum criteria                 | Enforce explicit synthesis quality signal | Aligns quality-first positioning and supports consistent planning readiness decisions.         |

---

## 2. Component Design

### 2.1 New Components

#### Component: Research Command Contract

- **Purpose:** Define the `/maestro.research` execution workflow, outputs, and bypass semantics.
- **Location:** `.maestro/commands/maestro.research.md`
- **Dependencies:** `.maestro/scripts/check-prerequisites.sh`, `.maestro/templates/research-template.md`, `.maestro/state/{feature_id}.json`
- **Dependents:** `/maestro.plan`, operator workflow, future `/maestro.research search` enhancement

#### Component: Research Output Template

- **Purpose:** Standardize domain artifacts (technology matrix, pattern catalog, pitfalls, competitive analysis, synthesis) and enforce minimum synthesis quality signals.
- **Location:** `.maestro/templates/research-template.md`
- **Dependencies:** Spec sections, constitution constraints
- **Dependents:** `.maestro/commands/maestro.research.md`, research artifact generation, `/maestro.plan` readiness gate

#### Component: Feature Research Directory Structure

- **Purpose:** Persist structured research outputs under each feature.
- **Location:** `.maestro/specs/{feature_id}/research/`
- **Dependencies:** feature spec directory, template contract
- **Dependents:** `/maestro.plan`, future knowledge reuse workflows

#### Component: Research State Extension

- **Purpose:** Track research completeness, artifact paths, and readiness metadata.
- **Location:** `.maestro/state/{feature_id}.json` (schema extension)
- **Dependencies:** research command execution
- **Dependents:** `/maestro.plan`, `/maestro.tasks`, operational reporting

### 2.2 Modified Components

#### Component: Plan Command Workflow

- **Current:** Consumes `spec.md` and state, then generates implementation plan.
- **Change:** Read research synthesis and readiness state; if incomplete, require explicit user acknowledgement phrase before planning.
- **Risk:** Medium - planning entrypoint behavior changes can impact existing feature flow.
- **Location:** `.maestro/commands/maestro.plan.md`

#### Component: Prerequisite Validation Script

- **Current:** Supports stage validation for existing commands.
- **Change:** Add `plan` dependency awareness for research artifacts and add `research` stage checks.
- **Risk:** Medium - incorrect checks can block legitimate workflows.
- **Location:** `.maestro/scripts/check-prerequisites.sh`

#### Component: Command Documentation Index

- **Current:** Documents specify -> clarify -> plan progression.
- **Change:** Document recommended sequence including research phase and bypass behavior.
- **Risk:** Low - documentation mismatch risk only.
- **Location:** `README.md`, `.maestro/commands/maestro.specify.md`, `.maestro/commands/maestro.plan.md`

#### Component: Command-Level Tests

- **Current:** Tests cover command assets and CLI command workflows.
- **Change:** Add/extend tests for research command presence, template validity, and readiness gate semantics.
- **Risk:** Medium - broad behavioral assertions may become brittle if not contract-focused.
- **Location:** `cmd/maestro-cli/cmd/commands_test.go`, `cmd/maestro-cli/test/e2e/e2e_test.go`

---

## 3. Data Model

Detailed schema is defined in `.maestro/specs/003-create-a-maestro-research-command-that-adds-a-pre-/data-model.md`.

### 3.1 New Entities

#### Entity: ResearchArtifactIndex

```text
ResearchArtifactIndex {
  feature_id: string
  generated_at: datetime
  execution_profile: {
    default_parallel_agents: 2
    max_parallel_agents: 5
    agents_used: integer
  }
  artifacts: {
    technology_options_path: string
    pattern_catalog_path: string
    pitfall_register_path: string
    competitive_analysis_path: string
    synthesis_path: string
  }
  completeness: {
    technology: boolean
    patterns: boolean
    pitfalls: boolean
    competitive: boolean
    synthesis: boolean
  }
  ready_for_planning: boolean
}
```

### 3.2 Modified Entities

#### Entity: FeatureState

- **Current fields:** `feature_id`, timestamps, `stage`, `spec_path`, branch/worktree metadata, story/clarification counters, history.
- **New fields:** `research_path`, `research_ready`, `research_artifacts[]`, `research_bypass_acknowledged` (optional), `research_parallel_agents_default`, `research_parallel_agents_max`, planning provenance from synthesis.
- **Migration notes:** Backward compatible additive fields; missing fields default to not-researched state.

### 3.3 Data Flow

`spec.md` + constitution constraints -> domain research artifacts -> synthesis + readiness decision -> state metadata update -> `/maestro.plan` reads readiness and either proceeds directly or requires acknowledgement override.

---

## 4. API Contracts

Detailed command contracts are defined in `.maestro/specs/003-create-a-maestro-research-command-that-adds-a-pre-/contracts/research-command-contracts.md`.

### 4.1 New Endpoints/Methods

#### Command: `/maestro.research [feature-id]`

- **Purpose:** Produce structured research artifacts that inform implementation planning.
- **Input:** optional feature id, current feature spec, current state file
- **Output:** populated `research/` artifact files plus updated state with readiness
- **Errors:** missing spec/state, template not found, unresolved prerequisite failures

### 4.2 Modified Endpoints

#### Command: `/maestro.plan [feature-id]`

- **Current behavior:** generates plan directly from spec + constitution + state.
- **New behavior:** consumes research synthesis and readiness flag; requires explicit bypass acknowledgement phrase when research is incomplete.
- **Breaking:** No (backward compatible via bypass path)

---

## 5. Implementation Phases

### Phase 1: Research Contracts and Templates

- **Goal:** Introduce explicit research phase contract and standardized output structure.
- **Tasks:**
  - Create `.maestro/commands/maestro.research.md` with prerequisite checks, fixed default agent-set behavior, and state update flow - Assignee: general
  - Create `.maestro/templates/research-template.md` covering technology matrix, pattern catalog, risk register, competitive benchmark, and synthesis quality checklist - Assignee: general
  - Add command documentation references in `README.md` and lifecycle docs - Assignee: general
- **Deliverable:** A runnable, documented research command contract with deterministic artifact structure.

### Phase 2: State and Prerequisite Integration

- **Goal:** Persist research metadata and wire readiness checks into workflow preconditions.
- **Dependencies:** Phase 1
- **Tasks:**
  - Extend `.maestro/scripts/check-prerequisites.sh` for research-stage checks and plan-stage readiness validation - Assignee: general
  - Define and apply research-related state fields in `.maestro/state/{feature_id}.json` updates from research execution, including parallelism metadata - Assignee: general
  - Add migration-safe handling for pre-research features in command logic docs/tests - Assignee: general
- **Deliverable:** State transitions can represent researched vs not-researched features without breaking existing flow.

### Phase 3: Plan Gate and Bypass Enforcement

- **Goal:** Ensure planning phase reliably consumes research and enforces explicit bypass acknowledgement.
- **Dependencies:** Phase 2
- **Tasks:**
  - Update `.maestro/commands/maestro.plan.md` to read `research/synthesis.md` and readiness metadata before generating plan - Assignee: general
  - Implement explicit acknowledgement contract (`I acknowledge proceeding without complete research`) for bypass cases - Assignee: general
  - Enforce minimum synthesis quality signal checks (Decision/Rationale/Alternatives/Confidence + ready/not_ready verdict) before marking research ready - Assignee: general
  - Add assumption/warning language when unresolved clarification markers remain in spec - Assignee: general
- **Deliverable:** `/maestro.plan` provides a clear readiness signal and compliant bypass behavior.

### Phase 4: Test Coverage and Quality Verification

- **Goal:** Lock behavior with tests and ensure research output quality baseline is verifiable.
- **Dependencies:** Phase 3
- **Tasks:**
  - Add command contract tests in `cmd/maestro-cli/cmd/commands_test.go` for command asset availability and expected references - Assignee: general
  - Extend workflow tests in `cmd/maestro-cli/test/e2e/e2e_test.go` for specify -> research -> plan and bypass branch - Assignee: general
  - Add fixture-based validation for generated research artifact headings, required sections, and synthesis quality minimums - Assignee: general
- **Deliverable:** Automated checks verify happy path and bypass path with stable artifact contracts.

---

## 6. Task Sizing Guidance

Split work into XS/S tasks by separating:

- command contract creation (`maestro.research.md`)
- template creation (`research-template.md`)
- prerequisite script updates (`check-prerequisites.sh`)
- plan gate updates (`maestro.plan.md`)
- tests and docs updates

Avoid combining script, template, and test changes in one task unless tightly coupled to keep each task under 360 minutes.

---

## 7. Testing Strategy

### 7.1 Unit Tests

- Validate prerequisite script stage checks for `research` and `plan` modes with mocked file-state scenarios.
- Validate parsing/validation of readiness metadata and bypass acknowledgement phrase handling.
- Validate artifact template completeness (required sections present).
- Validate execution profile constraints (`default=2`, `max=5`) and rejection of invalid parallelism values.
- Validate synthesis quality minimum fields are present before readiness can be true.

### 7.2 Integration Tests

- Run command sequence on a fixture feature and assert research artifacts are created under `.maestro/specs/{feature_id}/research/`.
- Assert state transitions: `clarify/specify -> research -> plan` with correct history entries and metadata.
- Assert plan command consumes synthesis recommendations and emits warning when readiness is false.
- Assert research artifacts remain editable markdown and can be revised without breaking plan consumption.

### 7.3 End-to-End Tests

- Full lifecycle: `/maestro.specify` -> `/maestro.research` -> `/maestro.plan` produces plan with research-informed decisions.
- Bypass lifecycle: incomplete research + required explicit acknowledgement phrase allows planning.

### 7.4 Test Data

- Fixture specs with and without `[NEEDS CLARIFICATION]` markers.
- Fixture research directories with complete and partial artifact sets.
- Fixture state files representing legacy and migrated schema shapes.
- Fixture synthesis files with missing quality fields to verify readiness rejection paths.

---

## 8. Risks and Mitigations

| Risk                                                                       | Likelihood | Impact | Mitigation                                                                                                               |
| -------------------------------------------------------------------------- | ---------- | ------ | ------------------------------------------------------------------------------------------------------------------------ |
| Research artifacts become verbose and low-signal, reducing plan usefulness | M          | H      | Enforce synthesis-first format plus quality minimums (Decision, Rationale, Alternatives, Confidence, readiness verdict). |
| Readiness gate blocks teams due to strict checks                           | M          | M      | Keep bypass path explicit and documented; provide precise missing-artifact messages.                                     |
| Parallel tracks produce conflicting recommendations                        | H          | M      | Use synthesis rubric prioritizing constitution compliance, evidence quality, and risk profile.                           |
| State schema drift breaks older features                                   | M          | H      | Make all research fields additive/optional and default-safe in command logic.                                            |
| Competitive analysis scope creep extends lead time                         | M          | M      | Restrict benchmark set to named competitors and require explicit defer list in output.                                   |

---

## 9. Open Questions

- How should synthesis weight conflicting findings when sources disagree (e.g., internal pattern vs competitor guidance)?

Assumptions used to proceed with this plan:

- Use a fixed default research-agent set for MVP, with project-level configurability deferred.
- Start research at 2 parallel agents by default, and allow expansion up to 5 agents.
- Treat artifacts as human-editable markdown files tracked in git.
- Prioritize competitor evaluation on output quality, enforced through minimum synthesis quality signals.
- Conflict-weighting policy remains unresolved and is tracked as an open question.
