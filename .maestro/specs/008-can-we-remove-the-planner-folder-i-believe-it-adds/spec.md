# Feature: Remove Planner Module and Simplify to Markdown-Only Workflow

**Spec ID:** 008-can-we-remove-the-planner-folder-i-believe-it-adds
**Author:** Maestro
**Created:** 2026-02-19
**Last Updated:** 2026-02-19
**Status:** Draft

---

## 1. Problem Statement

The maestro workflow is designed around markdown files as the primary artifacts: specs, plans, tasks, and reviews are all `.md` files interpreted by AI agents. However, a `.maestro/planner/` folder was introduced containing a full programmatic module (pattern analysis, task sizing, task enrichment, task linking) along with its own configuration block in `config.yaml`.

This creates several problems:

- **Unnecessary complexity.** The planner module introduces runtime dependencies and executable code into what should be a declarative, markdown-driven workflow. The maestro commands (e.g., `/maestro.plan`) already operate via markdown instructions interpreted by AI agents — they do not invoke the planner module.
- **Dependency burden.** The planner module requires a working runtime environment, cache directories, and configuration tuning (parallel workers, timeouts, confidence scores). This is overhead that provides no value when the AI agent itself performs pattern analysis and task breakdown from markdown instructions.
- **Philosophical misalignment.** Maestro's core value proposition is that specs, plans, and tasks are plain markdown — portable, reviewable, version-controlled, and agent-agnostic. A programmatic planner contradicts this principle by moving intelligence into code rather than keeping it in the workflow instructions.

---

## 2. Proposed Solution

Remove the `.maestro/planner/` directory entirely and clean up all references to it. Any useful concepts from the planner (such as task sizing constraints or pattern analysis guidance) should be preserved as markdown content within the existing workflow files — either in the plan template, the constitution, or the config file. The goal is to return to a fully markdown-driven workflow with zero runtime dependencies for planning.

---

## 3. User Stories

### Story 1: Maestro User — Simplified Setup

**As a** maestro user setting up a new project,
**I want** the `.maestro/` directory to contain only markdown files, shell scripts, and configuration,
**so that** I don't need to install or manage any runtime dependencies to use the full maestro workflow.

**Acceptance Criteria:**

- [ ] The `.maestro/planner/` directory no longer exists
- [ ] No `.py` files exist under `.maestro/` (including `__init__.py` — all Python artifacts are removed)
- [ ] Running `/maestro.plan` works correctly without the planner module present
- [ ] No error messages or warnings reference missing planner components

### Story 2: Maestro User — Preserved Planning Guidance

**As a** maestro user running `/maestro.plan`,
**I want** the planning phase to still produce high-quality, detailed task breakdowns with sizing guidance,
**so that** removing the planner module does not reduce the quality of generated plans.

**Acceptance Criteria:**

- [ ] Task sizing guidance (XS/S constraints, minute limits) is available to the AI agent through markdown or configuration
- [ ] The plan template or planning command instructions include guidance on pattern analysis and code examples
- [ ] Plans generated after removal are at least as detailed as before
- [ ] The entire `planner` configuration block in `config.yaml` is removed (the existing top-level `size_mapping` and `review_sizing` sections already provide the sizing guidance the AI agent needs)

### Story 3: Contributor — Clean Codebase

**As a** contributor to the maestro project,
**I want** there to be no dead code or orphaned configuration,
**so that** I can understand the project structure without encountering unused modules.

**Acceptance Criteria:**

- [ ] All references to the planner module are removed from documentation and configuration
- [ ] The `__pycache__` directory under `.maestro/planner/` is removed
- [ ] The `.maestro/__init__.py` file is removed (it only exists to support the planner module)
- [ ] The constitution is updated to remove "Planner" from the core architectural components (Section 1.1)

---

## 4. Success Criteria

The feature is considered complete when:

1. The `.maestro/planner/` directory and all its contents are fully removed from the repository
2. The `config.yaml` planner section is fully removed (existing `size_mapping` and `review_sizing` remain)
3. The `/maestro.plan` command continues to produce detailed plans successfully without the planner module
4. The constitution is updated to remove "Planner" from core architecture (Section 1.1)
5. Task sizing guidance is migrated from planner code into the plan template
6. No broken references to planner files remain anywhere in the project

---

## 5. Scope

### 5.1 In Scope

- Deleting the `.maestro/planner/` directory and all its contents
- Removing or simplifying the `planner` configuration block in `config.yaml`
- Updating the constitution to remove planner as an architectural component
- Migrating task sizing guidance (XS/S constraints, complexity considerations) from planner code into the plan template markdown
- Removing the `.maestro/__init__.py` (it only serves the planner module)
- Cleaning up any references to the planner in existing specs, plans, or command files

### 5.2 Out of Scope

- Rewriting the `/maestro.plan` command — it already works via markdown instructions
- Changing the task sizing values in `config.yaml` (only the planner-specific structure around them)
- Modifying the beads (bd) integration or task creation workflow
- Rearchitecting any other part of the maestro workflow

### 5.3 Deferred

- Evaluating whether other non-markdown artifacts in `.maestro/` should also be simplified
- Creating a "maestro lint" command to validate that `.maestro/` stays markdown-pure

---

## 6. Dependencies

- The `/maestro.plan` command must continue to function — this removal must be verified against the planning workflow
- Feature 007 (Enhanced Planning Phase) created the planner module — that feature's plan.md references planner files that will no longer exist

---

## 7. Open Questions

**Resolved:**

- The entire `planner` section in `config.yaml` should be removed. The existing top-level `size_mapping` and `review_sizing` sections already provide sufficient sizing guidance for the AI agent.
- Feature 007's spec and plan should be left as-is. They serve as historical records; git history tells the story of what was tried and why it was reversed.
- There are no downstream consumers that import from `.maestro/planner/`. It is self-contained and unused.
- All Python artifacts under `.maestro/` (including `__init__.py`) should be removed — maestro should have zero Python files.
- The "Planner" entry in the constitution's core architecture section (1.1) should be simply removed — the AI agent handles task analysis implicitly through the workflow.
- Task sizing guidance from the planner code should be migrated into the plan template markdown so it remains available to the AI agent during planning.

---

## 8. Risks

- **Loss of institutional knowledge.** The planner code captures specific pattern-matching and task-sizing logic that may be non-obvious. Before deletion, the valuable concepts should be extracted into markdown documentation.
- **Feature 007 conflict.** Feature 007 explicitly created the planner module. This feature effectively reverses that decision, which may cause confusion in the project history. Clear documentation of why is important.

---

## Changelog

| Date       | Change                                             | Author  |
| ---------- | -------------------------------------------------- | ------- |
| 2026-02-19 | Initial spec created                               | Maestro |
| 2026-02-19 | Resolved 4 clarification markers + 3 implicit gaps | Maestro |
