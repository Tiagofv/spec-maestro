# Implementation Plan: Remove Planner Module and Simplify to Markdown-Only Workflow

**Feature ID:** 008-can-we-remove-the-planner-folder-i-believe-it-adds
**Spec:** .maestro/specs/008-can-we-remove-the-planner-folder-i-believe-it-adds/spec.md
**Created:** 2026-02-19
**Status:** Draft

---

## 1. Architecture Overview

### 1.1 High-Level Design

This is a **removal and cleanup** feature, not a construction one. The goal is to delete the `.maestro/planner/` Python module (7 files, ~2200 lines), remove its configuration block from `config.yaml`, update the constitution, and migrate valuable task sizing guidance into the plan template markdown.

After this change, the `.maestro/` directory will contain only:

- **Markdown files** (`.md`) — specs, plans, commands, templates, skills, cookbook
- **Shell scripts** (`.sh`) — automation helpers
- **Configuration** (`config.yaml`) — project settings
- **State** (`.json`) — feature tracking

No Python files, no runtime dependencies, no `__pycache__` directories.

### 1.2 Component Interactions

This change does not introduce new components. It simplifies existing interactions:

```
BEFORE:                              AFTER:
┌──────────────┐                     ┌──────────────┐
│ /maestro.plan│                     │ /maestro.plan│
│  (markdown)  │                     │  (markdown)  │
└──────┬───────┘                     └──────┬───────┘
       │                                    │
       ▼                                    ▼
┌──────────────┐  ← unused           ┌──────────────┐
│   planner/   │                     │ plan-template│
│  (Python)    │                     │  (markdown)  │
└──────────────┘                     │ + sizing     │
                                     │   guidance   │
                                     └──────────────┘
```

The `/maestro.plan` command already works entirely through its markdown instructions. The Python planner module was never invoked by it. This plan simply removes the dead module and enriches the markdown template with the useful concepts from the planner code.

### 1.3 Key Design Decisions

| Decision         | Options Considered                                        | Chosen                   | Rationale                                                              |
| ---------------- | --------------------------------------------------------- | ------------------------ | ---------------------------------------------------------------------- |
| Config cleanup   | Keep task_sizing / Flatten to top-level / Remove entirely | Remove entirely          | Existing `size_mapping` and `review_sizing` already cover sizing needs |
| Feature 007 docs | Archive / Annotate / Leave as-is                          | Leave as-is              | Git history is the record; no need to modify historical artifacts      |
| Sizing guidance  | Discard / Migrate to template / Migrate to constitution   | Migrate to plan template | Template is where the AI agent reads planning instructions             |
| Python artifacts | Remove planner only / Remove all .py                      | Remove all .py           | `.maestro/__init__.py` only exists to support the planner              |

---

## 2. Component Design

### 2.1 New Components

None. This feature only removes and modifies existing components.

### 2.2 Modified Components

#### Component: Plan Template

- **Current:** `.maestro/templates/plan-template.md` — generic plan structure with placeholder sections
- **Change:** Add a "Task Sizing Guidance" section extracted from the planner's task_sizing.py logic. This includes XS/S size constraints, complexity indicators, and splitting strategies — expressed as markdown instructions for the AI agent.
- **Risk:** Low — additive change to an existing template

#### Component: Config File

- **Current:** `.maestro/config.yaml` — contains a 75-line `planner:` block (lines 46-121) with analyzer scope, pattern detection, caching, performance tuning, and task sizing config
- **Change:** Remove the entire `planner:` block (lines 46-121). The remaining config (`project`, `agent_routing`, `compile_gate`, `size_mapping`, `review_sizing`) stays untouched.
- **Risk:** Low — the planner block is not read by any active code

#### Component: Constitution

- **Current:** `.maestro/constitution.md` — Section 1.1 lists "Planner: Task analysis and pattern matching" as a core architectural component
- **Change:** Remove the "Planner" bullet point from Section 1.1. Also remove "Pattern matches must have confidence scores" from Section 4.1 (this is planner-specific logic).
- **Risk:** Low — constitution is a guiding document, not executable code

#### Component: Root **init**.py

- **Current:** `.maestro/__init__.py` — 3-line file with module docstring only
- **Change:** Delete the file entirely
- **Risk:** None — no imports depend on it

---

## 3. Data Model

### 3.1 New Entities

None.

### 3.2 Modified Entities

None.

### 3.3 Data Flow

No changes to data flow. The maestro workflow remains:

1. `/maestro.specify` → writes `spec.md`
2. `/maestro.clarify` → updates `spec.md`
3. `/maestro.plan` → reads `spec.md` + `plan-template.md` → writes `plan.md`
4. `/maestro.tasks` → reads `plan.md` → creates bd issues

---

## 4. API Contracts

### 4.1 New Endpoints/Methods

None.

### 4.2 Modified Endpoints

None. The `/maestro.plan` command is a markdown instruction file, not an API endpoint. Its behavior does not change — it already ignores the planner module.

---

## 5. Implementation Phases

### Phase 1: Extract and Migrate Valuable Knowledge

- **Goal:** Capture the useful concepts from the planner code before deletion
- **Tasks:**
  - Read `task_sizing.py` and extract the task sizing guidance:
    - XS = 0-120 minutes (0-2 hours), S = 121-360 minutes (2-6 hours)
    - Complexity indicators: high-complexity keywords (refactor, architecture, redesign, migrate, rewrite), medium (implement, create, build, design, integrate), low (fix, update, add, remove)
    - Splitting strategies: split by file, split by operation, split setup from implementation, split by "and" clauses
    - Ambiguity indicators that signal oversized scope: "etc", "various", "multiple", "several", "and more"
  - Add a "Task Sizing Guidance" section to `.maestro/templates/plan-template.md` with this knowledge expressed as markdown instructions
- **Deliverable:** Plan template enriched with sizing guidance; planner knowledge preserved in markdown

### Phase 2: Delete Planner Module

- **Goal:** Remove all planner Python files and artifacts
- **Tasks:**
  - Delete the entire `.maestro/planner/` directory (7 files + `__pycache__/`):
    - `__init__.py`
    - `config.py`
    - `pattern_analyzer.py`
    - `pattern_matcher.py`
    - `planner_cli.py`
    - `task_enricher.py`
    - `task_linker.py`
    - `task_sizing.py`
    - `__pycache__/` (contains `task_sizing.cpython-313.pyc`)
  - Delete `.maestro/__init__.py`
- **Deliverable:** Zero Python files under `.maestro/`

### Phase 3: Clean Up Configuration and Documentation

- **Goal:** Remove all orphaned references to the planner
- **Tasks:**
  - Remove the `planner:` block from `.maestro/config.yaml` (lines 46-121)
  - Update `.maestro/constitution.md`:
    - Remove "Planner: Task analysis and pattern matching" from Section 1.1
    - Remove "Pattern matches must have confidence scores" from Section 4.1
    - Update changelog
  - Scan all `.maestro/` markdown files for remaining references to "planner" and clean up any that reference the deleted module (note: feature 007's spec/plan are left as-is per clarification decision)
- **Deliverable:** No broken references; clean configuration

### Phase 4: Verification

- **Goal:** Confirm the workflow still works end-to-end
- **Tasks:**
  - Verify no `.py` files exist under `.maestro/`
  - Verify `/maestro.plan` command instructions still reference valid files
  - Verify `config.yaml` is valid YAML after the planner block removal
  - Verify no shell scripts or commands reference the planner module
  - Run a test planning cycle to confirm output quality is maintained
- **Deliverable:** Verified working workflow with zero regressions

---

## 6. Testing Strategy

### 6.1 Unit Tests

Not applicable — this feature deletes code rather than creating it. No new logic is introduced.

### 6.2 Integration Tests

- **YAML validation:** Confirm `config.yaml` remains valid after planner block removal
- **File inventory:** Confirm zero `.py` files exist under `.maestro/`
- **Reference integrity:** Confirm no markdown files reference `.maestro/planner/` paths (excluding historical feature 007 documents)

### 6.3 End-to-End Tests

- **Planning workflow:** Run `/maestro.plan` on an existing spec to confirm it still produces quality output
- **Template verification:** Confirm the plan template renders correctly with the new "Task Sizing Guidance" section

### 6.4 Test Data

No test data or fixtures needed. Verification is file-system-level (does the file exist? is the YAML valid? are there broken references?).

---

## 7. Risks and Mitigations

| Risk                                            | Likelihood | Impact | Mitigation                                                                              |
| ----------------------------------------------- | ---------- | ------ | --------------------------------------------------------------------------------------- |
| Loss of useful sizing knowledge                 | Low        | Medium | Phase 1 explicitly extracts and migrates concepts before deletion                       |
| Feature 007 plan references become confusing    | Low        | Low    | Left as historical record per clarification; git history explains the arc               |
| Config.yaml becomes invalid after block removal | Low        | High   | Validate YAML in Phase 4; removal is a clean block deletion                             |
| Something silently imports planner module       | Very Low   | Medium | Grep entire project for `planner` imports in Phase 3; no downstream consumers confirmed |

---

## 8. Open Questions

None — all questions were resolved during the clarification phase.

---

## Files Inventory

### Files to Delete (10 files)

| File                                                       | Lines | Purpose                            |
| ---------------------------------------------------------- | ----- | ---------------------------------- |
| `.maestro/planner/__init__.py`                             | 19    | Module exports                     |
| `.maestro/planner/config.py`                               | 182   | YAML config loader                 |
| `.maestro/planner/pattern_analyzer.py`                     | 398   | Codebase pattern extraction        |
| `.maestro/planner/pattern_matcher.py`                      | 435   | Constitution matching              |
| `.maestro/planner/planner_cli.py`                          | 324   | CLI orchestration                  |
| `.maestro/planner/task_enricher.py`                        | 418   | Task enrichment with code examples |
| `.maestro/planner/task_linker.py`                          | 496   | Task dependency linking            |
| `.maestro/planner/task_sizing.py`                          | 331   | XS/S size validation               |
| `.maestro/planner/__pycache__/task_sizing.cpython-313.pyc` | —     | Bytecode cache                     |
| `.maestro/__init__.py`                                     | 3     | Root module init                   |

**Total: ~2,606 lines of Python removed**

### Files to Modify (3 files)

| File                                  | Change                                                                           |
| ------------------------------------- | -------------------------------------------------------------------------------- |
| `.maestro/templates/plan-template.md` | Add "Task Sizing Guidance" section                                               |
| `.maestro/config.yaml`                | Remove `planner:` block (lines 46-121)                                           |
| `.maestro/constitution.md`            | Remove "Planner" from Section 1.1; remove planner-specific rule from Section 4.1 |

---

## Changelog

| Date       | Change               | Author  |
| ---------- | -------------------- | ------- |
| 2026-02-19 | Initial plan created | Maestro |
