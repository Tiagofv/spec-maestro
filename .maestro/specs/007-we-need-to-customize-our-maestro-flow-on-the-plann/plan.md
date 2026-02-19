# Implementation Plan: Enhanced Planning Phase with Detailed Code Examples

**Feature ID:** 007-we-need-to-customize-our-maestro-flow-on-the-plann
**Spec:** .maestro/specs/007-we-need-to-customize-our-maestro-flow-on-the-plann/spec.md
**Created:** 2026-02-19
**Status:** Draft

---

## 1. Architecture Overview

### 1.1 High-Level Design

The enhanced planning phase introduces a new **Task Specification Generator** component that sits between the feature specification and task creation. This component:

1. Reads the feature specification
2. Analyzes the codebase for relevant patterns
3. Generates enriched task descriptions with code examples and file references
4. Creates linked tasks for multi-file changes
5. Outputs tasks ready for beads task tracking

```
┌─────────────────────┐
│  Feature Spec       │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  Task Spec          │
│  Generator          │
│  • Pattern Analysis │
│  • Code Examples    │
│  • File References  │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  Linked Tasks       │
│  with Dependencies  │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  Beads Tasks        │
└─────────────────────┘
```

### 1.2 Component Interactions

**Flow:**

1. User triggers `/maestro.plan` with feature ID
2. Planner reads the spec
3. Codebase Analyzer scans for relevant files and patterns
4. Pattern Matcher identifies conventions from constitution and existing code
5. Task Breakdown splits work into XS/S sized tasks
6. Task Enricher adds code examples and file references
7. Task Linker creates dependencies for multi-file changes
8. Tasks are created in beads with full context

### 1.3 Key Design Decisions

| Decision            | Options Considered                          | Chosen            | Rationale                                                            |
| ------------------- | ------------------------------------------- | ----------------- | -------------------------------------------------------------------- |
| Pattern Source      | Constitution only / Codebase only / Both    | Both              | Constitution provides base rules; codebase shows real usage patterns |
| Code Example Type   | Full code / Pseudocode / Hybrid             | Hybrid            | Balance between specificity and maintainability                      |
| Task Sizing         | XS/S only / XS/S/M/L                        | XS/S only         | Matches spec requirements for focused, manageable tasks              |
| Multi-file Handling | Single task / Linked tasks / Subtasks       | Linked tasks      | Keeps tasks focused while maintaining relationships                  |
| Fallback Strategy   | Fail / Generic patterns / Constitution-only | Constitution-only | Ensures planning can always proceed                                  |

---

## 2. Component Design

### 2.1 New Components

#### Component: CodebasePatternAnalyzer

- **Purpose:** Scans the codebase to identify relevant files and extract patterns
- **Location:** `.maestro/planner/pattern_analyzer.py`
- **Dependencies:**
  - File system access
  - Language-specific parsers (tree-sitter)
  - Project constitution
- **Dependents:**
  - TaskEnricher
  - TaskBreakdown

#### Component: PatternMatcher

- **Purpose:** Matches patterns found in code against constitutional rules
- **Location:** `.maestro/planner/pattern_matcher.py`
- **Dependencies:**
  - Project constitution
  - CodebasePatternAnalyzer results
- **Dependents:**
  - TaskEnricher

#### Component: TaskEnricher

- **Purpose:** Adds code examples and file references to task descriptions
- **Location:** `.maestro/planner/task_enricher.py`
- **Dependencies:**
  - PatternMatcher
  - Task specification
  - CodebasePatternAnalyzer
- **Dependents:**
  - TaskLinker

#### Component: TaskLinker

- **Purpose:** Creates explicit dependencies between related tasks
- **Location:** `.maestro/planner/task_linker.py`
- **Dependencies:**
  - TaskEnricher output
- **Dependents:**
  - Beads integration layer

#### Component: TaskSizingValidator

- **Purpose:** Ensures tasks are sized XS or S only
- **Location:** `.maestro/planner/task_sizing.py`
- **Dependencies:**
  - Task specification
- **Dependents:**
  - TaskBreakdown

### 2.2 Modified Components

#### Component: Plan Command Handler

- **Current:** Simple task breakdown with basic descriptions
- **Change:** Orchestrates the new pipeline (Pattern Analyzer → Matcher → Enricher → Linker)
- **Risk:** Medium — existing planning logic needs refactoring

#### Component: Task Template System

- **Current:** Generic task templates
- **Change:** Support for code-example-aware templates
- **Risk:** Low — backward compatible enhancement

---

## 3. Data Model

### 3.1 New Entities

#### Entity: CodePattern

```
{
  "id": "uuid",
  "file_path": "string",
  "language": "string",
  "pattern_type": "enum(function|class|import|error_handling|etc)",
  "signature": "string",
  "example_code": "string",
  "context": "string",
  "confidence": "float (0-1)",
  "tags": ["string"]
}
```

#### Entity: EnrichedTask

```
{
  "id": "string",
  "title": "string",
  "description": "string",
  "size": "enum(XS|S)",
  "files_to_modify": [
    {
      "path": "string",
      "change_type": "enum(create|modify|delete)",
      "code_example": "string",
      "pattern_reference": "string"
    }
  ],
  "dependencies": ["task_id"],
  "blocked_by": ["task_id"],
  "constitution_rules": ["string"],
  "estimated_effort": "string",
  "acceptance_criteria": ["string"]
}
```

#### Entity: TaskChain

```
{
  "id": "uuid",
  "feature_id": "string",
  "tasks": ["task_id"],
  "dependency_graph": {
    "nodes": ["task_id"],
    "edges": [{"from": "task_id", "to": "task_id"}]
  },
  "created_at": "timestamp",
  "updated_at": "timestamp"
}
```

### 3.2 Modified Entities

#### Entity: Plan Output

- **Current fields:** task list with basic descriptions
- **New fields:**
  - `enriched_tasks`: List of EnrichedTask objects
  - `pattern_analysis_summary`: Summary of patterns found
  - `constitution_fallback_used`: Boolean
  - `multi_file_chains`: List of TaskChain objects
- **Migration notes:** Add new optional fields; maintain backward compatibility

### 3.3 Data Flow

1. **Input:** Feature spec → Pattern Analyzer
2. **Pattern Discovery:** Files scanned → CodePattern entities created
3. **Enrichment:** Raw tasks + CodePatterns → EnrichedTask entities
4. **Linking:** EnrichedTasks analyzed → Dependencies added → TaskChain created
5. **Output:** TaskChain + EnrichedTasks → Beads task creation

---

## 4. API Contracts

### 4.1 New Endpoints/Methods

#### METHOD: analyze_codebase

- **Purpose:** Scan codebase and return relevant patterns
- **Input:**
  ```json
  {
    "feature_id": "string",
    "scope": {
      "directories": ["string"],
      "exclude_patterns": ["string"]
    },
    "focus_areas": ["string"]
  }
  ```
- **Output:**
  ```json
  {
    "patterns": [CodePattern],
    "files_analyzed": "integer",
    "confidence_score": "float",
    "fallback_used": "boolean"
  }
  ```
- **Errors:**
  - `404`: Feature not found
  - `422`: Invalid scope parameters

#### METHOD: enrich_task

- **Purpose:** Add code examples and references to a task
- **Input:**
  ```json
  {
    "task": {
      "title": "string",
      "description": "string"
    },
    "patterns": [CodePattern],
    "constitution_rules": ["string"]
  }
  ```
- **Output:** EnrichedTask
- **Errors:**
  - `400`: Task too large (exceeds XS/S sizing)
  - `422`: Missing required fields

#### METHOD: create_task_chain

- **Purpose:** Create linked tasks with dependencies
- **Input:**
  ```json
  {
    "feature_id": "string",
    "tasks": [EnrichedTask],
    "dependency_strategy": "enum(automatic|manual)"
  }
  ```
- **Output:** TaskChain
- **Errors:**
  - `400`: Circular dependency detected
  - `422`: Invalid task structure

### 4.2 Modified Endpoints

#### METHOD: /maestro.plan

- **Current behavior:** Generates basic task list from spec
- **New behavior:**
  - Triggers codebase analysis
  - Enriches tasks with code examples
  - Creates linked task chains
  - Validates task sizing (XS/S only)
- **Breaking:** No — enhanced output is additive

---

## 5. Implementation Phases

### Phase 1: Foundation

- **Goal:** Establish the core analysis and enrichment infrastructure
- **Tasks:**
  - Create CodebasePatternAnalyzer with basic file scanning
  - Implement PatternMatcher for constitution integration
  - Build TaskSizingValidator
  - Add configuration for analyzer scope and patterns
- **Deliverable:** `/maestro.plan` can analyze codebase and identify patterns

### Phase 2: Task Enrichment

- **Goal:** Generate enriched tasks with code examples and file references
- **Dependencies:** Phase 1 complete
- **Tasks:**
  - Implement TaskEnricher with code example generation
  - Create hybrid code example strategy (working code + patterns)
  - Build file reference extraction from patterns
  - Update task templates to support enriched descriptions
- **Deliverable:** Tasks include code examples and file references

### Phase 3: Task Linking and Chains

- **Goal:** Support multi-file changes through linked tasks
- **Dependencies:** Phase 2 complete
- **Tasks:**
  - Implement TaskLinker with dependency detection
  - Create TaskChain data model and persistence
  - Build automatic dependency strategy for multi-file scenarios
  - Add validation for circular dependencies
- **Deliverable:** Multi-file features split into linked XS/S tasks

### Phase 4: CLI Integration and Optimization

- **Goal:** Integrate with maestro CLI and optimize performance
- **Dependencies:** Phase 3 complete
- **Tasks:**
  - Integrate enhanced planning into `/maestro.plan` command
  - Implement constitution fallback when no patterns found
  - Add caching for pattern analysis results
  - Create monitoring for planning performance
  - Write documentation and usage examples
  - Add CLI flags for planning options (e.g., --no-enrich, --quick)
- **Deliverable:** Production-ready enhanced planning via CLI

---

## 6. Testing Strategy

### 6.1 Unit Tests

- **CodebasePatternAnalyzer:**
  - File scanning for multiple languages
  - Pattern extraction accuracy
  - Exclusion pattern handling
  - Empty codebase handling
- **PatternMatcher:**
  - Constitution rule matching
  - Confidence scoring
  - Fallback to constitution-only
- **TaskEnricher:**
  - Code example generation
  - File reference extraction
  - Hybrid example strategy
- **TaskLinker:**
  - Dependency detection
  - Circular dependency prevention
  - Task chain creation
- **TaskSizingValidator:**
  - XS/S boundary detection
  - Oversized task splitting suggestions

### 6.2 Integration Tests

- **End-to-end planning flow:**
  - Feature spec → Enriched tasks
  - Multi-file feature → Linked tasks
  - Empty codebase → Constitution fallback
- **CLI integration:**
  - Command execution with enriched output
  - Configuration handling
  - Error reporting

### 6.3 End-to-End Tests

- **Real-world feature planning:**
  - Plan a sample feature
  - Verify task independence
  - Validate smaller models can complete tasks
  - Check code example usefulness

### 6.4 Test Data

- Sample codebase with known patterns
- Features of varying complexity (simple, multi-file, cross-cutting)
- Constitution with defined rules
- Expected enriched task outputs for validation

---

## 7. Risks and Mitigations

| Risk                                        | Likelihood | Impact | Mitigation                                                                            |
| ------------------------------------------- | ---------- | ------ | ------------------------------------------------------------------------------------- |
| Pattern analysis too slow                   | Medium     | Medium | Implement caching; parallelize scanning; limit scope                                  |
| Generated code examples become outdated     | High       | Medium | Version examples with commit hash; flag for refresh on significant codebase changes   |
| Tasks too fragmented                        | Medium     | High   | TaskSizingValidator with upper bounds; manual review of chain complexity              |
| Constitution and codebase patterns conflict | Low        | Medium | PatternMatcher precedence rules; flag conflicts for human review                      |
| CLI argument parsing conflicts              | Low        | Medium | Comprehensive CLI tests; backward compatibility checks                                |
| Planning time increases significantly       | Medium     | Medium | Performance benchmarks; progressive enhancement (basic plan → enriched plan); caching |

---

## 8. Open Questions

- Should we implement incremental pattern analysis (only scan changed files) for faster re-planning?
- What's the expected volume of tasks per feature? Should we add pagination/limiting?
- Should enriched tasks include estimated review effort as well as implementation effort?
- How should we handle generated code examples when the codebase pattern is deprecated or being phased out?

---

## Changelog

| Date       | Change               | Author  |
| ---------- | -------------------- | ------- |
| 2026-02-19 | Initial plan created | Maestro |
