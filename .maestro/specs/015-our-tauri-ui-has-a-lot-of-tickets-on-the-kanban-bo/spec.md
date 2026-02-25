# Feature: Epic-Grouped Kanban Board View

**Spec ID:** 015-our-tauri-ui-has-a-lot-of-tickets-on-the-kanban-bo
**Author:** System
**Created:** 2026-02-19
**Last Updated:** 2026-02-19
**Status:** Approved

---

## 1. Problem Statement

The Tauri UI kanban board currently displays all tickets in a flat, status-based view (Open, In Progress, Blocked, Closed). As the number of tickets grows across multiple epics and projects, users struggle to:

- **Find tickets related to a specific epic** — They must mentally filter through dozens of tickets or use text search, which is inefficient and error-prone.
- **Understand epic progress at a glance** — There's no visual indication of how many tickets within an epic are complete, blocked, or in progress.
- **Organize work by initiative** — Project managers and team leads cannot easily view all work grouped by strategic initiatives or features.

This affects product managers, team leads, and developers who need to track progress across multiple epics simultaneously. The backend already tracks epic relationships (`epic_id`, parent relationships, and epic status), but the frontend treats all issues as a flat list.

---

## 2. Proposed Solution

Add a **view mode toggle** to the kanban board that allows users to switch between:

1. **Status View** (current default) — Issues grouped by status columns (Open, In Progress, Blocked, Closed)
2. **Epic View** (new) — Issues grouped by epic, with status lanes within each epic group

In Epic View, each epic becomes a collapsible swimlane showing:

- Epic title and progress summary (e.g., "5 of 12 complete")
- Status columns within that epic (Open, In Progress, Blocked, Closed)
- Only the tickets belonging to that epic

Users can filter by specific epics using the existing filter panel, and drag-drop functionality remains available within epic boundaries (cross-epic drag-and-drop is blocked). Issues not assigned to any epic, or with invalid/orphaned epic references, are grouped under "No Epic" at the bottom of the view.

---

## 3. User Stories

### Story 1: Switch to Epic View

**As a** product manager,
**I want** to switch the kanban board to an epic-grouped view,
**so that** I can see all work organized by strategic initiatives instead of just status.

**Acceptance Criteria:**

- [ ] A view mode toggle appears in the main board header (e.g., radio buttons or tabs labeled "By Status" and "By Epic")
- [ ] When I select "By Epic," the board reorganizes to show epic swimlanes instead of status columns
- [ ] When I select "By Status," the board returns to the original status-column layout
- [ ] The selected view mode persists when I reload the page

### Story 2: View Tickets Grouped by Epic

**As a** team lead,
**I want** to see all tickets grouped by their parent epic,
**so that** I can track progress on each feature or initiative separately.

**Acceptance Criteria:**

- [ ] Each epic appears as a distinct group (swimlane or section) in the Epic View
- [ ] Within each epic group, tickets are organized into status lanes (Open, In Progress, Blocked, Closed)
- [ ] Epic groups show a progress summary (e.g., "3 open, 2 in progress, 1 blocked, 5 closed")
- [ ] Tickets without an epic assignment appear in a separate "No Epic" group at the bottom of the view
- [ ] Tickets with invalid or orphaned epic_id references are grouped into the "No Epic" group
- [ ] Epic groups are sorted alphabetically by epic title
- [ ] Closed epics are hidden by default
- [ ] A "Show closed epics" checkbox control allows users to reveal closed epics when needed
- [ ] Epics with zero tickets are shown in Epic View (not hidden automatically)

### Story 3: Collapse and Expand Epic Groups

**As a** developer,
**I want** to collapse epic groups I'm not currently working on,
**so that** I can focus on the relevant work without visual clutter.

**Acceptance Criteria:**

- [ ] Each epic group has a collapse/expand toggle (e.g., chevron icon)
- [ ] When collapsed, the epic shows only the header with progress summary
- [ ] When expanded, the epic shows all status lanes and tickets
- [ ] Collapsed/expanded state persists for each epic when I reload the page
- [ ] All epic groups are expanded by default on first use
- [ ] A "Collapse All" / "Expand All" action is available that affects only visible epics (after filters are applied)

### Story 4: Filter by Specific Epics

**As a** project manager,
**I want** to filter the Epic View to show only selected epics,
**so that** I can focus on specific initiatives without scrolling through all epics.

**Acceptance Criteria:**

- [ ] The existing filters panel includes an "Epic" filter option
- [ ] The epic filter is presented as a searchable list showing all available epics (loaded from backend)
- [ ] I can select one or more epics to display
- [ ] When epic filters are active, only the selected epic groups appear in Epic View
- [ ] The epic filter works in both Status View and Epic View
- [ ] When switching between Status View and Epic View, epic filters remain active
- [ ] Selected epic filters persist when I reload the page
- [ ] Clearing the epic filter shows all epics again

### Story 5: Drag and Drop Within Epic Boundaries

**As a** developer,
**I want** to drag tickets between status lanes within the same epic,
**so that** I can update ticket status without changing epic assignments.

**Acceptance Criteria:**

- [ ] I can drag a ticket from one status lane to another within the same epic group
- [ ] The ticket's status updates in the backend when dropped in a new status lane
- [ ] Dragging a ticket to a different epic group is blocked entirely (not allowed)
- [ ] Visual feedback shows valid drop zones (same epic) vs invalid drop zones (different epic)

---

## 4. Success Criteria

The feature is considered complete when:

1. **View toggle is functional** — Users can switch between Status View and Epic View, and the selection persists across sessions.
2. **Epic grouping displays correctly** — All tickets are grouped by epic with status lanes within each epic, and progress summaries are accurate.
3. **Collapse/expand works reliably** — Epic groups can be collapsed and expanded, with state persisting across page reloads.
4. **Epic filter integrates seamlessly** — Users can filter by specific epics using the existing filters panel, and filtered results update in real-time.
5. **Drag-and-drop respects epic boundaries** — Tickets can be dragged within an epic to change status, and cross-epic moves are handled according to clarified requirements.
6. **Performance is acceptable** — The Epic View loads and renders within 2 seconds for boards with up to 200 tickets across 20 epics.

---

## 5. Scope

### 5.1 In Scope

- View mode toggle between Status View and Epic View in main board header
- Epic swimlane/group rendering with status lanes within each epic
- Progress summary display for each epic (open, in progress, blocked, closed counts)
- Collapse/expand functionality for individual epic groups
- "Collapse All" / "Expand All" action affecting only visible epics
- Epic filter (searchable list) in the existing filters panel
- "Show closed epics" checkbox control
- Drag-and-drop within epic boundaries for status changes (cross-epic moves blocked)
- "No Epic" group at bottom of view for unassigned or orphaned tickets
- View mode, collapse state, and epic filter persistence in local storage
- Display of empty epics (epics with zero tickets)

### 5.2 Out of Scope

- Creating, editing, or deleting epics from the kanban board (use existing bd CLI tools)
- Nested epic hierarchies (epic of epics) — only one level of epic grouping
- Re-assigning tickets to different epics via drag-and-drop (cross-epic moves are blocked)
- Gantt chart or timeline view for epics
- Epic-level metrics beyond basic counts (velocity, burndown, etc.)
- Epic sorting or reordering (alphabetical sort only)
- Bulk operations on epic groups (e.g., "close all tickets in epic")
- Automatic hiding of empty epics (epics with zero tickets are shown)

### 5.3 Deferred

- Custom epic color coding or icons
- Epic descriptions or metadata in the board view
- Dependency visualization between epics
- Epic progress charts or visualizations
- Advanced epic filters (by date range, owner, labels)

---

## 6. Dependencies

- Backend epic commands: `list_epics()`, `get_epic_status(epic_id)` (already implemented)
- Epic relationship tracking: `issue.extra.epic_id`, `issue.extra.parent` (already tracked in backend)
- Existing filter infrastructure: `KanbanFilters`, `getFilteredIssues()` (extends existing logic)
- Drag-and-drop library: `@dnd-kit` (already integrated)
- State management: Zustand store (`stores/dashboard.ts`) (extends existing store)

---

## 7. Open Questions

None — all clarifications resolved.

---

## 8. Risks

**Known Risks:**

1. **Performance degradation with many epics** — Rendering 20+ swimlanes with nested status columns could slow down the UI. Mitigation: virtualization or lazy loading of collapsed epic groups.

2. **UX confusion around drag boundaries** — Users may expect to be able to drag tickets between epics, but cross-epic moves are blocked entirely. Mitigation: clear visual feedback showing invalid drop zones when hovering over different epic groups.

3. **State persistence complexity** — Storing collapse state for many epics in local storage could become unwieldy. Mitigation: limit persistence to 50 most recently viewed epics.

4. **Filter interaction complexity** — Combining epic filters with other filters (assignee, priority, labels) could produce empty results or confusing states. Mitigation: clear filter UI and "no results" messaging.

---

## Changelog

| Date       | Change                                         | Author |
| ---------- | ---------------------------------------------- | ------ |
| 2026-02-19 | Initial spec created                           | System |
| 2026-02-19 | Resolved 12 clarification markers via /clarify | System |
