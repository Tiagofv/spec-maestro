# Feature: Feature Dashboard Command

**Spec ID:** 031-lets-add-agent-maestro-new-command-list
**Author:** User
**Created:** 2026-03-16
**Last Updated:** 2026-03-16
**Status:** Review

---

## 1. Problem Statement

As the number of features managed by maestro grows, there is no quick way to see all features at a glance with their current status. Users must manually browse state files or spec directories to piece together what exists, what stage each feature is in, and what action to take next.

This lack of visibility makes it hard to prioritize work, identify stalled features, and decide what to do next. A user returning to the project after a break has no single entry point to understand the current state of all features.

---

## 2. Proposed Solution

Add a new command (`maestro.list`) to agent-maestro that displays a consolidated view of all tracked features, their current stage/status, and a set of contextually suggested next actions for each feature. The command acts as a "feature dashboard" — a single command that answers "what do we have and what should I do next?"

---

## 3. User Stories

### Story 1: View All Features at a Glance

**As a** developer using maestro,
**I want** to run a single command that lists all features with their current status,
**so that** I can quickly understand the state of the project without browsing individual files.

**Acceptance Criteria:**

- [ ] Running the command displays a list of all tracked features
- [ ] Each feature shows its ID, a human-readable name, and its current stage (e.g., specify, clarify, plan, implement, review, complete)
- [ ] The list is sorted by feature ID in descending numeric order (newest first)
- [ ] Features with no state file but with a spec directory are shown with a warning indicator suggesting the user run `/maestro.specify` to create proper state
- [ ] Completed features are shown at the bottom of the list, visually separated from active features
- [ ] When no features exist, the command displays a helpful onboarding message: "No features found. Run `/maestro.specify` to create your first feature."

### Story 2: See Suggested Next Actions

**As a** developer using maestro,
**I want** each listed feature to show the recommended next action based on its current stage,
**so that** I know exactly what command to run next without having to remember the workflow.

**Acceptance Criteria:**

- [ ] Each feature displays one or more suggested next actions (e.g., "Run /maestro.clarify" for features in the specify stage with clarification markers)
- [ ] Suggestions are contextual — they change based on the feature's current stage and state
- [ ] The suggested action includes the actual command the user can run
- [ ] Features not updated for 14 or more days display a "stalled" warning indicator alongside the regular stage information

### Story 3: Filter and Focus

**As a** developer using maestro,
**I want** to filter the feature list by status or stage,
**so that** I can focus on only the features that need attention right now.

**Acceptance Criteria:**

- [ ] The command accepts an optional filter to show only features in a specific stage (e.g., only "in progress" or only "specify")
- [ ] The command can show only features that have pending clarifications
- [ ] Ownership-based filtering ("my features") is out of scope for this version

### Story 4: Quick Feature Summary

**As a** developer using maestro,
**I want** to see key metrics alongside each feature (number of user stories, tasks, clarification markers),
**so that** I can gauge the size and readiness of each feature at a glance.

**Acceptance Criteria:**

- [ ] Each feature shows the count of user stories (if available from state)
- [ ] Each feature shows the count of remaining clarification markers (if applicable)
- [ ] Each feature shows the count of tasks (if the feature has been planned)
- [ ] Features that have been completed show a completion indicator

---

## 4. Success Criteria

The feature is considered complete when:

1. A user can run a single command and see all tracked features with their current stage displayed in a readable format
2. Each feature in the output includes at least one contextually relevant suggested next action
3. The output is scannable — a user can identify which features need attention in under 10 seconds
4. Filtering by stage works and reduces the list to only matching features
5. The command handles edge cases gracefully: empty project (no features), features with missing state files, corrupted state files

---

## 5. Scope

### 5.1 In Scope

- Listing all features found in the specs directory and/or state directory
- Displaying current stage for each feature
- Showing contextual next-action suggestions per feature
- Basic filtering by stage
- Showing key metrics (user stories count, task count, clarification count)
- Graceful handling of missing or incomplete state data

### 5.2 Out of Scope

- Interactive mode (selecting a feature and running the action directly from the list)
- Integration with external issue trackers or project management tools
- Historical timeline or burndown views
- Modifying feature state from within this command (it is read-only)
- Rich TUI (terminal UI) with colors, boxes, or interactive elements beyond plain text output
- Feature archiving or deletion capabilities
- Ownership-based filtering ("my features" by author or branch)

### 5.3 Deferred

- Export to JSON or other machine-readable formats for scripting
- Compact single-line-per-feature output mode
- A web-based dashboard view of the same data
- Configurable stalled threshold (currently fixed at 14 days)
- Sorting options beyond the default feature-ID order
- Ownership-based filtering

---

## 6. Research

{No research conducted yet for this feature.}

### Linked Research Items

- None

### Research Summary

No research has been conducted. The feature is primarily an aggregation and display concern over existing state data that maestro already tracks.

---

## 7. Dependencies

- Existing maestro state files (`.maestro/state/*.json`) must follow the current schema
- Existing spec directories (`.maestro/specs/*/`) must exist for feature discovery
- The maestro command infrastructure must support registering a new command

---

## 8. Open Questions

All clarifications have been resolved:

- **Command name:** `maestro.list` — concise and consistent with existing command naming conventions
- **Output format:** Plain text table format only for v1. Compact/JSON modes are deferred
- **Orphan spec directories:** Auto-discovered and shown with a warning indicator suggesting the user create proper state via `/maestro.specify`

---

## 8. Risks

- If state files are inconsistent or have evolved across different versions of maestro, the command may display inaccurate stage information. A validation or migration mechanism may be needed.
- As the number of features grows into the hundreds, the default unfiltered output could become unwieldy. Pagination or limiting may need to be addressed sooner than deferred.

---

## Changelog

| Date       | Change                                             | Author |
| ---------- | -------------------------------------------------- | ------ |
| 2026-03-16 | Resolved 5 clarification markers + 3 implicit gaps | User   |
| 2026-03-16 | Initial spec created                               | User   |
