# Feature: Create a /maestro.research Command for Pre-Planning Research Phase

**Spec ID:** 003-create-a-maestro-research-command-that-adds-a-pre-
**Author:** opencode
**Created:** 2026-02-19
**Last Updated:** 2026-02-19
**Status:** Draft

---

## 1. Problem Statement

Currently, the maestro workflow transitions directly from specification (`/maestro.specify`) to technical planning (`/maestro.plan`) without a dedicated research phase. This creates several pain points:

1. **Uninformed architectural decisions** — Plans are made without systematic investigation of technology options, leading to suboptimal choices that are discovered late in implementation.

2. **Reinvention of solutions** — Teams often rebuild patterns that already exist in the ecosystem or within the organization because there's no structured way to discover them.

3. **Undiscovered pitfalls** — Common architectural mistakes, known limitations of libraries, and domain-specific gotchas are only encountered during implementation, causing rework.

4. **Inconsistent research depth** — When research happens, it's ad-hoc and not standardized, leading to varying quality and coverage across features.

A dedicated research phase between specification and planning would ensure technical decisions are informed by thorough investigation, existing patterns, and collective knowledge.

---

## 2. Proposed Solution

Introduce a `/maestro.research` command that executes after specification and before planning. This command will orchestrate parallel research agents to investigate multiple domains simultaneously, producing structured research artifacts that feed into the planning phase.

The research phase will:

- Run multiple specialized research agents in parallel, each focusing on a specific domain
- Generate structured research reports with findings, recommendations, and risk assessments
- Store research artifacts in a discoverable, versioned format
- Provide a synthesis that informs architectural decisions in the planning phase
- Track research completeness through state management

This follows the pattern of parallel agent orchestration similar to GSD's discuss-phase, where multiple perspectives are gathered simultaneously before synthesis.

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

---

## 4. Success Criteria

The `/maestro.research` command is considered complete when:

1. Running `/maestro.research` after a specification produces structured research artifacts
2. At least 4 parallel research agents execute simultaneously (technology, patterns, pitfalls, best practices)
3. Research output feeds into planning phase with clear recommendations
4. State tracking records research completion and artifact locations
5. Research templates exist and are used for consistent output
6. Research artifacts are discoverable by future features through the knowledge base

---

## 5. Scope

### 5.1 In Scope

- Creation of `/maestro.research` command file
- Research agent definitions and orchestration patterns
- Research templates for structured output
- State tracking integration for research artifacts
- Parallel execution of research agents
- Synthesis of research findings into planning input
- Integration with existing `/maestro.specify` and `/maestro.plan` commands

### 5.2 Out of Scope

- Automated web scraping or external data sources (manual research only)
- Long-running research processes (assumes research completes within session)
- Integration with external knowledge management systems
- Machine learning-based research assistance

### 5.3 Deferred

- Research caching across features
- Collaborative research editing
- Research result validation through external review
- Automated research quality scoring

---

## 6. Dependencies

- `/maestro.specify` command must exist and create specifications
- `/maestro.plan` command must consume research output
- `.maestro/templates/` directory structure must exist
- State management system for tracking research artifacts

---

## 7. Open Questions

- [NEEDS CLARIFICATION: Should research agents be hardcoded or configurable per project?]
- [NEEDS CLARIFICATION: What is the maximum number of parallel agents that should run?]
- [NEEDS CLARIFICATION: Should research output be editable by humans or read-only?]
- [NEEDS CLARIFICATION: How should research findings be weighted when they conflict?]

---

## 8. Risks

1. **Research scope creep** — Research could become unbounded, delaying planning indefinitely. Mitigation: Set time limits per research area and require explicit scoping.

2. **Information overload** — Too much research could overwhelm planners. Mitigation: Include synthesis step that distills findings into actionable recommendations.

3. **Stale research** — Research conducted early may become outdated by planning time. Mitigation: Timestamp research and flag areas that may need refresh.

---

## Changelog

| Date       | Change               | Author   |
| ---------- | -------------------- | -------- |
| 2026-02-19 | Initial spec created | opencode |
