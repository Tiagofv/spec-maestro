# Feature: Git Diff Snapshots for Completed Beads Tasks

**Spec ID:** 009-i-want-to-build-a-git-diff-for-each-completed-bead
**Author:** System
**Created:** 2026-02-19
**Last Updated:** 2026-02-19
**Status:** Draft

---

## 1. Problem Statement

When a beads (bd) task is closed, the code changes associated with that task are only visible through standard git history. There is no direct link between a completed task and the specific code changes it produced. This makes it difficult to revisit what was actually changed for a given task — especially weeks or months later when context has faded.

Developers need a way to quickly see "what did this task actually change in the codebase?" without manually reconstructing commit ranges or searching through git logs. This is particularly valuable for post-mortems, knowledge transfer, onboarding, and understanding the evolution of a feature across multiple tasks.

---

## 2. Proposed Solution

When a beads task is completed (closed), the system captures a snapshot of the git diff associated with that task's work. This snapshot is stored alongside the task so it can be retrieved later for review. Users can browse and view these diff snapshots at any time to understand what code changes a specific task produced.

---

## 3. User Stories

### Story 1: Automatic Diff Capture on Task Completion

**As a** developer,
**I want** a git diff to be automatically captured when I close a beads task,
**so that** I have a permanent record of the code changes associated with that task.

**Acceptance Criteria:**

- [ ] When a task is closed via `bd close`, the git diff for that task's changes is captured and stored
- [ ] The captured diff includes all file changes (additions, modifications, deletions) attributable to the task
- [ ] The capture happens without requiring additional manual steps from the developer
- [ ] [NEEDS CLARIFICATION: How should the system determine which commits belong to a task? Options include: commits since task was marked in-progress, commits on the task's branch, or commits matching a naming convention]

### Story 2: Viewing a Task's Diff Snapshot

**As a** developer,
**I want** to view the diff snapshot for any previously completed task,
**so that** I can understand exactly what code changes were made without searching through git history.

**Acceptance Criteria:**

- [ ] A user can retrieve the diff snapshot for a completed task by referencing the task ID
- [ ] The diff output shows file paths, additions (lines added), and deletions (lines removed)
- [ ] The output is readable and clearly formatted
- [ ] [NEEDS CLARIFICATION: Should the diff be viewable only via CLI, or should it also be browsable through other interfaces (e.g., a web view, markdown export)?]

### Story 3: Listing Tasks with Available Diff Snapshots

**As a** developer,
**I want** to see which completed tasks have diff snapshots available,
**so that** I can browse past work and find the task I want to revisit.

**Acceptance Criteria:**

- [ ] A user can list completed tasks that have associated diff snapshots
- [ ] The list shows the task ID, title, completion date, and a summary of the diff (e.g., files changed count, lines added/removed)
- [ ] The list can be filtered or searched by task title or date range

---

## 4. Success Criteria

The feature is considered complete when:

1. Closing a beads task automatically produces a stored diff snapshot of the associated code changes
2. A developer can retrieve and view the diff for any previously completed task using its task ID
3. The stored diff accurately reflects the code changes made during that task's lifecycle
4. Diff snapshots persist across git operations and are available indefinitely (or until explicitly purged)

---

## 5. Scope

### 5.1 In Scope

- Capturing git diffs when a beads task is closed
- Storing diff snapshots in a durable, retrievable format
- Viewing a single task's diff snapshot by task ID
- Listing completed tasks with available diff snapshots
- Summary metadata (files changed, lines added/removed, date)

### 5.2 Out of Scope

- Diff comparison between two tasks
- Interactive diff browsing or side-by-side views
- Integration with external code review tools (GitHub PRs, GitLab MRs)
- Automatic tagging or categorization of diffs (e.g., "refactoring" vs "feature")
- Diff snapshots for tasks that were not closed through `bd close`
- Real-time diff preview while a task is in progress

### 5.3 Deferred

- Exporting diff snapshots to external formats (PDF, HTML)
- Aggregating diffs across multiple tasks into a combined "feature diff"
- Searching within diff content (e.g., "show me all tasks that changed file X")

---

## 6. Dependencies

- The beads (`bd`) CLI, specifically the `bd close` command and task lifecycle
- Git must be available and the working directory must be a git repository
- [NEEDS CLARIFICATION: Does the project always use branches per task, or can multiple tasks share a branch? This affects how diffs are scoped]

---

## 7. Open Questions

- [NEEDS CLARIFICATION: How should the system determine which commits belong to a task? Options include: commits since task was marked in-progress, commits on the task's branch, or commits matching a naming convention]
- [NEEDS CLARIFICATION: Should the diff be viewable only via CLI, or should it also be browsable through other interfaces (e.g., a web view, markdown export)?]
- [NEEDS CLARIFICATION: Does the project always use branches per task, or can multiple tasks share a branch? This affects how diffs are scoped]
- [NEEDS CLARIFICATION: Should diff snapshots be stored as plain text files, or within the beads database alongside the task record?]

---

## 8. Risks

- If commits are not clearly associated with tasks (e.g., no branch-per-task convention, no commit message convention), the captured diff may be inaccurate or incomplete.
- Large diffs from big tasks could consume significant storage space if stored as full text.
- If `bd close` is invoked with uncommitted changes in the working directory, the diff may not reflect the final state of the task's work.

---

## Changelog

| Date       | Change               | Author |
| ---------- | -------------------- | ------ |
| 2026-02-19 | Initial spec created | System |
