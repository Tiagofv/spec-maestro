# Feature: Create a New Modal on the Frontend to Create Tasks

**Spec ID:** 010-create-a-new-modal-on-the-frontend-to-create-tasks
**Author:** Maestro
**Created:** 2026-02-19
**Last Updated:** 2026-02-19
**Status:** Draft

---

## 1. Problem Statement

The current task creation experience (the "Quick Create" modal) only allows users to set a title, status, priority, and assignee. Users cannot provide a description, attach labels, set dependencies, or choose a task type when creating a new task. This forces them to create tasks with incomplete information and then update them through other means outside the application.

For teams managing complex workflows with multiple task types (Task, Epic, Feature, Bug), meaningful descriptions, and label-based organization, the inability to set these fields at creation time slows down work intake and leads to tasks missing critical context from the start.

---

## 2. Proposed Solution

Replace or supplement the existing quick-create experience with a full-featured task creation modal that exposes all relevant task fields. The modal should allow users to fill in all task properties in a single interaction, while keeping the experience fast for users who only need to set a title and submit.

The modal should follow the established modal patterns already present in the application (overlay, keyboard shortcuts, accessibility, animations) so it feels native and consistent.

---

## 3. User Stories

### Story 1: Create a Task with Full Details

**As a** project team member,
**I want** to create a new task with a title, description, status, priority, assignee, labels, and task type from a single modal,
**so that** new tasks are complete and actionable from the moment they are created.

**Acceptance Criteria:**

- [ ] The modal displays input fields for: title (required), description (optional), status (optional, defaults to "open"), priority (optional), assignee (optional), labels (optional), and task type (optional)
- [ ] Submitting the modal with only a title creates the task successfully
- [ ] Submitting with all fields populated creates the task with all properties set correctly
- [ ] The newly created task appears on the board or list without requiring a manual refresh
- [ ] [NEEDS CLARIFICATION: Should the description field support markdown formatting, or is plain text sufficient?]

### Story 2: Quick Task Creation

**As a** user in a hurry,
**I want** to create a task by just typing a title and pressing a keyboard shortcut or submit button,
**so that** the full form does not slow me down when I only need to capture a quick item.

**Acceptance Criteria:**

- [ ] The title field is focused automatically when the modal opens
- [ ] Pressing a keyboard shortcut (e.g., Cmd/Ctrl+Enter) submits the form
- [ ] A task can be created by entering only a title — no other fields are required
- [ ] After successful creation, the modal either closes or clears the form for creating another task
- [ ] [NEEDS CLARIFICATION: After creating a task, should the modal close automatically, stay open for batch creation, or offer the user a choice?]

### Story 3: Validation and Error Feedback

**As a** user filling out the task creation form,
**I want** to see clear error messages when something is wrong,
**so that** I can correct issues before losing my input.

**Acceptance Criteria:**

- [ ] If the title is empty and the user attempts to submit, an inline error message is displayed
- [ ] If the backend rejects the creation (e.g., service unavailable), the error is shown in the modal without losing the user's input
- [ ] The submit button is disabled while a submission is in progress to prevent duplicates

### Story 4: Access the Modal from Multiple Entry Points

**As a** user viewing the kanban board or the issue list,
**I want** to open the task creation modal from wherever I am in the application,
**so that** I do not have to navigate away to create a new task.

**Acceptance Criteria:**

- [ ] The modal can be opened from a button on the kanban board view
- [ ] The modal can be opened from a button on the issue list view
- [ ] [NEEDS CLARIFICATION: Should a global keyboard shortcut (e.g., "N" or Cmd/Ctrl+N) open the modal from anywhere in the application?]

---

## 4. Success Criteria

The feature is considered complete when:

1. A user can open the task creation modal and create a task with all supported fields (title, description, status, priority, assignee, labels, task type) in a single interaction
2. Creating a task with only a title takes no more than 3 interactions (open modal, type title, submit)
3. Validation errors are displayed inline without clearing the form
4. The modal follows the existing accessibility patterns: keyboard dismissal (Escape), focus trapping, screen reader labels, and backdrop click to close
5. The newly created task appears in the board or list within 2 seconds of successful submission

---

## 5. Scope

### 5.1 In Scope

- A modal form with fields for all supported task properties (title, description, status, priority, assignee, labels, task type)
- Input validation with inline error messages
- Loading and error states during submission
- Keyboard accessibility (focus management, Escape to close, submit shortcut)
- Entry points from both the kanban board and issue list views
- Consistent styling with the existing modal design system

### 5.2 Out of Scope

- Editing existing tasks from a modal (read-only detail view already exists)
- File attachments or image uploads on tasks
- Sub-task creation or parent-task linking from within the modal
- Bulk task creation (creating multiple tasks at once from a single form)
- Custom field definitions or dynamic form fields
- Drag-and-drop reordering of labels or dependencies within the modal

### 5.3 Deferred

- Pre-populating fields based on the current kanban column context (e.g., auto-setting status when opening from a specific column)
- Task templates for common task types
- Dependency selection within the creation modal
- Auto-save drafts if the modal is closed accidentally

---

## 6. Dependencies

- The existing task creation backend command (`createIssue`) must support the fields exposed in the modal. Currently, `CreateIssueRequest` supports `title`, `description`, `labels`, and `parentId`. [NEEDS CLARIFICATION: Does the backend need to be extended to support `status`, `priority`, `assignee`, and `issue_type` at creation time, or are those set via separate update calls?]
- The existing modal animation and accessibility patterns (overlay, focus management, body scroll lock) should be reused

---

## 7. Open Questions

- [NEEDS CLARIFICATION: Should the new modal replace the existing Quick Create modal entirely, or coexist alongside it as a separate "full create" option?]
- [NEEDS CLARIFICATION: What are the available label values — are they predefined, freeform text, or fetched from the backend?]
- [NEEDS CLARIFICATION: Should the task type field ("Task", "Epic", "Feature", "Bug") be a required selection or default to "Task"?]

---

## 8. Risks

- **Field support gap:** The current `CreateIssueRequest` type only includes `title`, `description`, `labels`, and `parentId`. If the backend does not support setting priority, status, assignee, or task type at creation time, additional backend work will be required before this feature can be fully delivered.
- **Scope creep into editing:** Adding a full-featured creation form may create user expectations for a similar editing experience, which is explicitly out of scope for this feature.

---

## Changelog

| Date       | Change               | Author  |
| ---------- | -------------------- | ------- |
| 2026-02-19 | Initial spec created | Maestro |
