# Feature: Create a /maestro.research Command for Pre-Planning Research Phase

**Spec ID:** 003-create-a-maestro-research-command-that-adds-a-pre-
**Author:** opencode
**Created:** 2026-02-19
**Last Updated:** 2026-02-20
**Status:** Draft

---

## 1. Problem Statement

Currently, the maestro workflow transitions directly from specification (`/maestro.specify`) to technical planning (`/maestro.plan`) without a dedicated research phase. This creates several pain points:

1. **Uninformed architectural decisions** — Plans are made without systematic investigation of technology options, leading to suboptimal choices that are discovered late in implementation.

2. **Reinvention of solutions** — Teams often rebuild patterns that already exist in the ecosystem or within the organization because there's no structured way to discover them.

3. **Undiscovered pitfalls** — Common architectural mistakes, known limitations of libraries, and domain-specific gotchas are only encountered during implementation, causing rework.

4. **Inconsistent research depth** — When research happens, it's ad-hoc and not standardized, leading to varying quality and coverage across features.

5. **No competitive benchmarking** — Research lacks comparison against how other spec-driven tools handle similar challenges, missing opportunities to adopt best practices.

A dedicated research phase between specification and planning would ensure technical decisions are informed by thorough investigation, existing patterns, and collective knowledge.

Recent competitive analysis of OpenSpec, spec-kitty, get-shit-done, and spec-kit reveals patterns for effective research phases:

- **OpenSpec**: Explicit research command with technology investigation, pattern discovery, and artifact persistence
- **spec-kitty**: Optional research gate with synthesized decision support and clear completion criteria
- **get-shit-done**: Research integrated into planning with parallel investigation and competitive benchmarking
- **spec-kit**: No explicit research step, but strong emphasis on pattern reuse and knowledge building

The immediate need is to build a research phase that incorporates these competitive insights while maintaining Maestro's simplicity.

---

## 2. Proposed Solution

Introduce a `/maestro.research` command that executes after specification and before planning. This command will orchestrate parallel research agents to investigate multiple domains simultaneously, producing structured research artifacts that feed into the planning phase.

The research phase will:

- Run a fixed default set of specialized research agents in parallel, each focusing on a specific domain
- Generate structured research reports with findings, recommendations, and risk assessments
- Store research artifacts in a discoverable, versioned format
- Provide a synthesis that informs architectural decisions in the planning phase
- Track research completeness through state management
- Incorporate competitive analysis to ensure best-in-class research quality

This follows the pattern of parallel agent orchestration similar to GSD's discuss-phase, where multiple perspectives are gathered simultaneously before synthesis.

For MVP, the research workflow starts with 2 parallel agents by default and may expand up to a maximum of 5 parallel agents as needed.

### 2.1 Competitive Quality Baseline

Research outputs should meet these quality criteria observed in effective workflows:

- **Explicit phase ownership** — Research is a named step with clear boundaries, not implicit work
- **Structured artifacts** — Findings follow templates (technology matrix, pattern catalog, risk register)
- **Competitive comparison** — At least 3 external approaches are compared with trade-off analysis
- **Actionable synthesis** — Research distills into clear recommendations with rationale
- **Planning readiness signal** — Users can tell when research is complete enough
- **Clear scope boundaries** — Deferred items are explicit to avoid expectation gaps
- **Quality-first evaluation** — Competitor and workflow comparison prioritizes output quality over speed or breadth

Minimum quality signal for planning readiness:

- Each major recommendation includes Decision, Rationale, Alternatives, and Confidence
- All fixed research domains are covered without missing sections
- At least 3 external approaches are compared with trade-offs and one preferred direction
- Ambiguities are explicitly labeled as blocker or non-blocker
- Synthesis ends with a single ready/not-ready verdict and missing minimum items when not ready

---

## 3. User Stories

### Story 1: Technology Stack Investigation

**As a** technical lead,
**I want** to systematically research technology options before committing to them,
**so that** I can make evidence-based decisions about libraries, frameworks, and tools.

**Acceptance Criteria:**

- [ ] The research command identifies relevant technologies based on the specification
- [ ] Each technology is evaluated against criteria like maturity, community support, licensing, and compatibility
- [ ] A comparison matrix is generated showing trade-offs between options
- [ ] Recommendations include rationale and risk assessment

### Story 2: Pattern Discovery

**As a** developer,
**I want** to discover existing solutions and patterns in the ecosystem and within the organization,
**so that** I can leverage proven approaches rather than building from scratch.

**Acceptance Criteria:**

- [ ] Research investigates similar open-source implementations
- [ ] Internal codebases are searched for relevant patterns
- [ ] Research output includes links to reference implementations
- [ ] Patterns are categorized by applicability to the current feature

### Story 3: Pitfall Prevention

**As a** architect,
**I want** to identify architectural pitfalls and gotchas before they become problems,
**so that** the plan can include mitigations and avoid common mistakes.

**Acceptance Criteria:**

- [ ] Research identifies common failure modes for the proposed feature type
- [ ] Known limitations of chosen technologies are documented
- [ ] Domain-specific constraints are discovered and highlighted
- [ ] Risk assessment includes mitigation strategies

### Story 4: Research Artifact Persistence

**As a** team member,
**I want** research findings to be stored in a discoverable, versioned format,
**so that** future features can build upon this knowledge and avoid redundant research.

**Acceptance Criteria:**

- [ ] Research outputs are stored in the feature directory
- [ ] State tracking records research completion and artifacts
- [ ] Research is linked to the specification and plan
- [ ] Artifacts follow a standardized template for consistency
- [x] **RESOLVED**: Cross-feature research search is DEFERRED based on competitive analysis. All major competitors (OpenSpec, Spec Kitty, GSD, spec-kit) use file-based per-feature storage without cross-feature search. Recommendation: Implement per-feature research storage in `.maestro/specs/{feature}/research/` with standardized structure. Future enhancement may add `/maestro.research search` command when user demand justifies the indexing complexity.

### Story 5: Planning Readiness Gate

**As a** planner,
**I want** a clear signal that research is complete enough for planning,
**so that** I can avoid starting plan work with missing context.

**Acceptance Criteria:**

- [ ] The workflow indicates whether research requirements are satisfied before planning
- [ ] If research completeness is not met, the user receives clear guidance on what is missing
- [x] **RESOLVED**: Users should be allowed to bypass incomplete research with an explicit acknowledgment. The system will require users to type "I acknowledge proceeding without complete research" before allowing them to continue to planning.

### Story 6: Research Scope Boundaries

**As a** product owner,
**I want** research scope to be explicitly bounded,
**so that** the research phase doesn't delay planning indefinitely.

**Acceptance Criteria:**

- [ ] Research phase has clear entry and exit criteria
- [ ] Time limits are suggested for research activities
- [ ] Research output focuses on actionable findings, not exhaustive analysis
- [x] **RESOLVED**: No minimum timebox required. Research can be as brief as needed, or bypassed entirely with explicit user acknowledgment. The system focuses on flexibility rather than enforcing duration minimums.

---

## 4. Success Criteria

The `/maestro.research` command is considered complete when:

1. Running `/maestro.research` after a specification produces structured research artifacts
2. Research runs with 2 parallel agents by default and can scale up to 5 parallel agents when needed
3. Research output feeds into planning phase with clear recommendations
4. State tracking records research completion and artifact locations
5. Research templates exist and are used for consistent output
6. Research artifacts are discoverable by future features through the knowledge base
7. Research outputs meet competitive quality baseline (comparison, synthesis, readiness signal)
8. Users can bypass incomplete research with explicit acknowledgment
9. Research artifacts are editable by humans after generation

---

## 5. Scope

### 5.1 In Scope

- Creation of `/maestro.research` command file
- Research agent definitions and orchestration patterns
- Research templates for structured output
- State tracking integration for research artifacts
- Parallel execution of research agents
- Fixed default research-agent set (MVP)
- Synthesis of research findings into planning input
- Integration with existing `/maestro.specify` and `/maestro.plan` commands
- Planning readiness gate with bypass option
- Per-feature research artifact storage
- Human-editable research artifacts

### 5.2 Out of Scope

- Automated web scraping or external data sources (manual research only)
- Long-running research processes (assumes research completes within session)
- Integration with external knowledge management systems
- Machine learning-based research assistance
- Cross-feature research search and discovery

### 5.3 Deferred

- Research caching across features
- Collaborative research editing
- Research result validation through external review
- Automated research quality scoring
- Cross-feature research search and discovery
- Research caching and reuse across projects

---

## 6. Dependencies

- `/maestro.specify` command must exist and create specifications
- `/maestro.plan` command must consume research output
- `.maestro/templates/` directory structure must exist
- State management system for tracking research artifacts
- Access to competitor documentation and repositories for competitive analysis

---

## 7. Open Questions

- [x] **RESOLVED**: Use a fixed default research-agent set for MVP. Project-level configurability is deferred.
- [x] **RESOLVED**: Default parallelism is 2 research agents, expandable up to a maximum of 5.
- [x] **RESOLVED**: Research outputs are human-editable artifacts, not read-only generated output.
- [NEEDS CLARIFICATION: How should research findings be weighted when they conflict?]
- [x] **RESOLVED**: Competitor evaluation prioritizes quality. `/maestro.research` is planning-ready only when each major recommendation records Decision, Rationale, Alternatives, and Confidence; all fixed research domains are covered; at least three external approaches are compared with a preferred direction; ambiguities are labeled blocker/non-blocker; and synthesis ends with a single ready/not-ready verdict and missing minimum items.

---

## 8. Risks

1. **Research scope creep** — Research could become unbounded, delaying planning indefinitely. Mitigation: Set time limits per research area and require explicit scoping; allow bypass with acknowledgment.

2. **Information overload** — Too much research could overwhelm planners. Mitigation: Include synthesis step that distills findings into actionable recommendations.

3. **Stale research** — Research conducted early may become outdated by planning time. Mitigation: Timestamp research and flag areas that may need refresh.

4. **Analysis paralysis** — Competitive analysis could expand beyond scope. Mitigation: Focus on the 4 specified competitors and define clear evaluation criteria upfront.

5. **Feature creep** — Trying to adopt too many patterns from competitors. Mitigation: Prioritize recommendations and clearly mark what to adopt now vs. defer.

6. **Knowledge silos** — Research findings not discoverable by other teams. Mitigation: Standardize artifact format and location from the start.

---

## Changelog

| Date       | Change                                                                        | Author   |
| ---------- | ----------------------------------------------------------------------------- | -------- |
| 2026-02-19 | Initial spec created                                                          | opencode |
| 2026-02-20 | Incremented with competitive analysis insights from Feature 018               | Maestro  |
| 2026-02-20 | Added planning readiness gate, bypass option, and scope boundary stories      | Maestro  |
| 2026-02-20 | Added competitive quality baseline and cross-feature search deferral          | Maestro  |
| 2026-02-20 | Resolved 4 clarification markers; retained 1 open conflict-weighting question | Maestro  |
