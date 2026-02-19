# Feature: Enhanced Planning Phase with Detailed Code Examples

**Spec ID:** 007-we-need-to-customize-our-maestro-flow-on-the-plann
**Author:** Maestro
**Created:** 2026-02-19
**Last Updated:** 2026-02-19
**Status:** Draft

---

## 1. Problem Statement

When breaking down features into implementation tasks, developers often struggle with insufficient context. Current task specifications lack concrete code examples, requiring developers to infer implementation patterns from high-level descriptions. This creates friction and increases cognitive load, especially when using smaller models or less experienced developers who benefit from clear, concrete guidance.

The result is inconsistent implementations, increased back-and-forth clarification, and tasks that take longer to complete because the "what" and "how" are not clearly articulated upfront.

---

## 2. Proposed Solution

Enhance the maestro planning phase to automatically generate detailed, code-oriented task specifications. When breaking down a feature specification into individual tasks, the system should enrich each task with relevant code examples, file patterns, and implementation context. This enables smaller, focused changes that can be executed by smaller models or developers with less domain expertise.

---

## 3. User Stories

### Story 1: Task Consumer - Clear Implementation Guidance

**As a** developer or AI agent consuming a task,
**I want** each task to include relevant code examples and file patterns,
**so that** I can implement the change without guessing the approach or structure.

**Acceptance Criteria:**

- [ ] Each task references specific files that need to be modified or created
- [ ] Each task includes at least one concrete code example showing the expected pattern
- [ ] Tasks clearly indicate whether they require creating new code or modifying existing code
- [ ] Code examples should be a mix of actual working code and patterns, grounded in existing codebase patterns when available

### Story 2: Task Planner - Contextual Breakdown

**As a** maestro user planning a feature,
**I want** the planning command to analyze the codebase and generate contextual task details,
**so that** I don't have to manually research and document every implementation detail.

**Acceptance Criteria:**

- [ ] Planning phase is triggered manually by the user
- [ ] Planning phase automatically identifies relevant existing files and patterns
- [ ] Tasks are broken down with sufficient granularity (focused, single-responsibility)
- [ ] Each task includes context about where it fits in the overall feature
- [ ] Tasks should be sized XS or S only, balancing granularity to avoid both oversized and overly fragmented tasks
- [ ] If no patterns are found in the codebase, the system falls back to using the project constitution only
- [ ] Multi-file changes are split into linked tasks with explicit dependencies between them via task IDs

### Story 3: Code Reviewer - Consistent Implementation

**As a** code reviewer,
**I want** tasks to specify expected patterns and conventions upfront,
**so that** implementations are more consistent and require fewer review cycles.

**Acceptance Criteria:**

- [ ] Tasks reference existing code that follows project conventions
- [ ] Tasks explicitly mention any patterns or conventions to follow
- [ ] Generated tasks respect the project's architectural decisions

---

## 4. Success Criteria

The feature is considered complete when:

1. The `/maestro.plan` command produces tasks that each include at least one concrete code example
2. Each generated task references specific files or file patterns relevant to the implementation
3. Tasks can be executed independently by smaller models without requiring clarification
4. The planning phase analyzes the existing codebase to identify relevant patterns
5. Task descriptions are sufficiently detailed that an implementer can complete the task without reading the full feature spec

---

## 5. Scope

### 5.1 In Scope

- Enhance the `/maestro.plan` command to generate detailed task specifications
- Include code examples and file references in generated tasks
- Analyze existing codebase during planning to identify relevant patterns
- Support for multiple file types and languages
- Template customization for different types of tasks
- Ability to regenerate or update existing tasks when the specification changes

### 5.2 Out of Scope

- Automatic code generation (this is about task specification, not implementation)
- Integration with specific AI models or providers
- Real-time code execution or validation
- Code refactoring suggestions

### 5.3 Deferred

- Automatic test case generation for each task
- Integration with IDE plugins for in-editor task viewing
- Machine learning-based pattern recognition from commit history

---

## 6. Dependencies

- Existing maestro planning infrastructure
- Access to codebase for pattern analysis
- Beads task tracking system

---

## 7. Open Questions

**Resolved:**

- Task descriptions have no maximum length but should be detailed without redundancy or loss of context
- Tasks should always be as detailed as possible without excessive information or redundancy; no differentiation by developer experience level needed
- If codebase is empty or very new, the system uses constitution-only patterns
- No authentication or special permissions required for planning phase
- Multi-file tasks: split into linked tasks with explicit dependencies between them via task IDs, keeping each task focused and within XS/S size limits

---

## 8. Risks

- Overly detailed tasks may become brittle and hard to maintain as the codebase evolves
- Generating detailed examples may increase planning time significantly
- Code patterns identified automatically may not always be the best or most current patterns in the codebase

---

## Changelog

| Date       | Change                                                  | Author  |
| ---------- | ------------------------------------------------------- | ------- |
| 2026-02-19 | Initial spec created                                    | Maestro |
| 2026-02-19 | Resolved 5 clarification markers + 5 implicit questions | Maestro |
