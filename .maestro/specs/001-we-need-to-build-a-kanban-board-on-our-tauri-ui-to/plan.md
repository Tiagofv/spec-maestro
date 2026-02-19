# Implementation Plan: Kanban Board for Task Management

**Feature ID:** 001-we-need-to-build-a-kanban-board-on-our-tauri-ui-to
**Spec:** `.maestro/specs/001-we-need-to-build-a-kanban-board-on-our-tauri-ui-to/spec.md`
**Created:** 2026-02-19
**Status:** Draft

---

## 1. Architecture Overview

### 1.1 High-Level Design

The Kanban board will be a new view in the existing Tauri React application, leveraging the established patterns:

```
┌─────────────────────────────────────────────────────────┐
│                     App.tsx                             │
│  ┌─────────────────────────────────────────────────┐   │
│  │            KanbanBoard View                      │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌────────┐ │   │
│  │  │  Open   │ │ In Prog │ │ Blocked │ │ Closed │ │   │
│  │  │ ┌───┐   │ │ ┌───┐   │ │ ┌───┐   │ │ ┌───┐  │ │   │
│  │  │ │T1 │   │ │ │T2 │   │ │ │T3 │   │ │ │T4 │  │ │   │
│  │  │ └───┘   │ │ └───┘   │ │ └───┘   │ │ └───┘  │ │   │
│  │  │ ┌───┐   │ │ ┌───┐   │ │         │ │        │ │   │
│  │  │ │T5 │   │ │ │T6 │   │ │         │ │        │ │   │
│  │  │ └───┘   │ │ └───┘   │ │         │ │        │ │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └────────┘ │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────┐    ┌──────────────────┐
│   dashboard Store   │◄──►│   Tauri IPC      │
│  (Zustand)          │    │  (Rust Backend)  │
└─────────────────────┘    └──────────────────┘
         │                          │
         ▼                          ▼
┌─────────────────────┐    ┌──────────────────┐
│  TaskDetail Modal   │    │   bd Service     │
│  QuickCreate Modal  │    │  (Unix Socket)   │
└─────────────────────┘    └──────────────────┘
```

### 1.2 Component Interactions

**Drag-and-Drop Flow:**

1. User drags TaskCard from Column A to Column B
2. KanbanBoard handles drop event
3. Calls `tauri.updateIssueStatus(issueId, newStatus)`
4. Backend updates issue in bd
5. Backend emits `IssueUpdated` event
6. Frontend receives event via `useTauriEvents`
7. Dashboard store updates, UI re-renders

**Task Creation Flow:**

1. User clicks "Create Task" button
2. QuickCreate modal opens
3. User fills form (title, assignee, priority)
4. Calls `tauri.createIssue(issueData)`
5. Backend creates issue in bd
6. Backend emits `IssueUpdated` event
7. New task appears on board immediately

### 1.3 Key Design Decisions

| Decision               | Options Considered                       | Chosen                | Rationale                                               |
| ---------------------- | ---------------------------------------- | --------------------- | ------------------------------------------------------- |
| Drag library           | @dnd-kit, react-beautiful-dnd, HTML5 API | @dnd-kit              | Modern, accessible, lightweight, works with React 19    |
| Real-time updates      | WebSocket, SSE, polling                  | Events via Tauri      | Already in use in app, simpler than adding new protocol |
| Data fetching          | REST API, GraphQL, Tauri commands        | Tauri commands        | Existing pattern, type-safe IPC                         |
| Sorting within columns | Manual drag, auto-sort                   | Auto-sort by priority | Spec requirement, avoids complexity                     |
| Task detail view       | Inline expand, modal, sidebar            | Modal                 | Consistent with spec, avoids layout shifts              |

---

## 2. Component Design

### 2.1 New Components

#### Component: KanbanBoard

- **Purpose:** Main kanban board view displaying tasks in status columns
- **Location:** `/src/views/KanbanBoard.tsx`
- **Dependencies:** dashboard store, DndContext, TaskCard, KanbanColumn
- **Dependents:** App.tsx (route), Navigation component

#### Component: KanbanColumn

- **Purpose:** Vertical column representing a task status (open, in_progress, blocked, closed)
- **Location:** `/src/components/kanban/KanbanColumn.tsx`
- **Dependencies:** SortableContext, TaskCard, Droppable
- **Dependents:** KanbanBoard

#### Component: TaskCard

- **Purpose:** Individual task card showing title, assignee, priority
- **Location:** `/src/components/kanban/TaskCard.tsx`
- **Dependencies:** useSortable hook, draggable attributes
- **Dependents:** KanbanColumn

#### Component: TaskDetailModal

- **Purpose:** Modal showing full task details when card is clicked
- **Location:** `/src/components/kanban/TaskDetailModal.tsx`
- **Dependencies:** dashboard store, existing task detail components (if any)
- **Dependents:** TaskCard

#### Component: QuickCreateModal

- **Purpose:** Quick task creation interface accessible from board
- **Location:** `/src/components/kanban/QuickCreateModal.tsx`
- **Dependencies:** dashboard store, form validation
- **Dependents:** KanbanBoard

#### Component: AssigneeSelector

- **Purpose:** Dropdown for assigning/reassigning tasks
- **Location:** `/src/components/kanban/AssigneeSelector.tsx`
- **Dependencies:** dashboard store (workspaces/users), tauri commands
- **Dependents:** TaskCard, QuickCreateModal

#### Component: BoardFilters

- **Purpose:** Filter controls for assignee and completed tasks toggle
- **Location:** `/src/components/kanban/BoardFilters.tsx`
- **Dependencies:** dashboard store, local filter state
- **Dependents:** KanbanBoard

#### Component: ErrorState

- **Purpose:** Display error message when beads service is unavailable
- **Location:** `/src/components/kanban/ErrorState.tsx`
- **Dependencies:** dashboard store error state
- **Dependents:** KanbanBoard

### 2.2 Modified Components

#### Component: App.tsx

- **Current:** Routes to IssueList view only
- **Change:** Add route/navigation for KanbanBoard view
- **Risk:** Low - simple routing addition

#### Component: dashboard.ts (store)

- **Current:** Contains issues array and fetchIssues action
- **Change:**
  - Add `updateIssueStatus(issueId, status)` action
  - Add `assignIssue(issueId, assignee)` action
  - Add `createIssue(issueData)` action
  - Add filtering logic for assignee and completed tasks
- **Risk:** Medium - core data layer modifications

#### Component: tauri.ts (lib)

- **Current:** Contains listIssues, listWorkspaces commands
- **Change:** Add commands:
  - `updateIssueStatus(issueId: string, status: string)`
  - `assignIssue(issueId: string, assignee: string)`
  - `createIssue(issue: Partial<Issue>)`
- **Risk:** Low - additive changes

#### Component: bd_commands.rs (backend)

- **Current:** Contains list_issues, list_workspaces commands
- **Change:** Add Tauri commands:
  - `update_issue_status`
  - `assign_issue`
  - `create_issue`
- **Risk:** Low - additive changes, follows existing patterns

---

## 3. Data Model

### 3.1 New Entities

#### Entity: KanbanFilters

```typescript
interface KanbanFilters {
  assignee: string | null; // Filter by specific assignee
  showCompleted: boolean; // Show/hide closed tasks
}
```

#### Entity: CreateIssueRequest

```typescript
interface CreateIssueRequest {
  title: string;
  status: "open" | "in_progress" | "blocked" | "closed";
  priority?: number;
  assignee?: string | null;
  labels?: string[];
}
```

### 3.2 Modified Entities

#### Entity: DashboardState (Zustand store)

- **Current fields:** issues, workspaces, selectedWorkspace, daemonStatus, etc.
- **New fields:**
  - `kanbanFilters: KanbanFilters` - Current filter state
  - `filteredIssues: Issue[]` - Computed filtered list
- **New actions:**
  - `updateIssueStatus(issueId, status)`
  - `assignIssue(issueId, assignee)`
  - `createIssue(issueData)`
  - `setKanbanFilters(filters)`
- **Migration notes:** None - additive only

### 3.3 Data Flow

```
User Action → Tauri IPC → bd HTTP API → bd Database
     │           │            │            │
     │           │            │            ▼
     │           │            │      Issue Updated
     │           │            │            │
     │           │            ▼            │
     │           │      Event Emitted ◄────┘
     │           │            │
     │           ▼            │
     │     Dashboard Store ◄──┘
     │            │
     ▼            ▼
  UI Updates (React re-renders)
```

---

## 4. API Contracts

### 4.1 New Endpoints/Methods

#### POST /issues/{id}/status

- **Purpose:** Update an issue's status
- **Input:** `{ status: string }`
- **Output:** `Issue` (updated)
- **Errors:** 404 (issue not found), 400 (invalid status), 503 (bd unavailable)

#### POST /issues/{id}/assign

- **Purpose:** Assign or reassign an issue
- **Input:** `{ assignee: string | null }`
- **Output:** `Issue` (updated)
- **Errors:** 404 (issue not found), 503 (bd unavailable)

#### POST /issues

- **Purpose:** Create a new issue
- **Input:** `CreateIssueRequest`
- **Output:** `Issue` (created)
- **Errors:** 400 (invalid data), 503 (bd unavailable)

### 4.2 Tauri Commands (Rust → Frontend)

#### `update_issue_status`

- **Purpose:** Tauri command wrapper for status update
- **Input:** `issue_id: String, status: String`
- **Output:** `Result<Issue, String>`
- **Side effects:** Emits `IssueUpdated` event

#### `assign_issue`

- **Purpose:** Tauri command wrapper for assignment
- **Input:** `issue_id: String, assignee: Option<String>`
- **Output:** `Result<Issue, String>`
- **Side effects:** Emits `IssueUpdated` event

#### `create_issue`

- **Purpose:** Tauri command wrapper for issue creation
- **Input:** `issue: CreateIssueRequest`
- **Output:** `Result<Issue, String>`
- **Side effects:** Emits `IssueUpdated` event

---

## 5. Implementation Phases

### Phase 1: Foundation

- **Goal:** Basic kanban board with read-only view
- **Tasks:**
  - Create KanbanBoard view component
  - Create KanbanColumn component
  - Create TaskCard component
  - Add board route to App.tsx
  - Style columns and cards with Tailwind
  - Group issues by status and sort by priority
- **Deliverable:** Static board displaying tasks in columns, no drag/drop or interaction

### Phase 2: Interactions

- **Goal:** Drag-and-drop and task detail viewing
- **Dependencies:** Phase 1
- **Tasks:**
  - Install @dnd-kit dependencies
  - Implement drag-and-drop for status changes
  - Create TaskDetailModal component
  - Connect card click to open modal
  - Implement backend `update_issue_status` command
  - Handle IssueUpdated events
- **Deliverable:** Users can drag tasks between columns and view task details

### Phase 3: Assignment & Filtering

- **Goal:** Task assignment and board filtering
- **Dependencies:** Phase 2
- **Tasks:**
  - Create AssigneeSelector component
  - Implement backend `assign_issue` command
  - Add assignee filter to BoardFilters component
  - Add "Show Completed" toggle filter
  - Implement filter logic in dashboard store
- **Deliverable:** Users can filter by assignee, toggle completed tasks, and reassign tasks

### Phase 4: Task Creation

- **Goal:** Create tasks directly from board
- **Dependencies:** Phase 3
- **Tasks:**
  - Create QuickCreateModal component
  - Implement backend `create_issue` command
  - Add "Create Task" button to board
  - Handle new task appearing in board immediately
- **Deliverable:** Users can create new tasks from the board view

### Phase 5: Error Handling & Polish

- **Goal:** Robust error handling and UI polish
- **Dependencies:** Phase 4
- **Tasks:**
  - Create ErrorState component for beads unavailability
  - Implement retry mechanism
  - Add loading states for async operations
  - Add animations for drag-and-drop
  - Test with large task volumes
  - Performance optimization if needed
- **Deliverable:** Production-ready board with proper error handling and performance

---

## 6. Testing Strategy

### 6.1 Unit Tests

- **KanbanBoard:** Rendering with different issue sets, empty state
- **KanbanColumn:** Correct task grouping, sorting by priority
- **TaskCard:** Drag interaction setup, click handling
- **BoardFilters:** Filter logic, state changes
- **dashboard store:** Filter computation, action handlers

### 6.2 Integration Tests

- **Drag-and-drop:** Complete flow from UI to backend to event emission
- **Task creation:** Create task flow with modal and board update
- **Assignment:** Assign task and verify filter updates
- **Error handling:** Simulate bd unavailable and verify error state

### 6.3 End-to-End Tests

- **Full user journey:** Open board → drag task → view details → assign → create new task
- **Filter interactions:** Apply filters and verify correct tasks display
- **Error recovery:** Disconnect bd → see error → reconnect → board recovers

### 6.4 Test Data

- **Fixtures:** 20+ sample issues across all statuses with varying priorities
- **Edge cases:** Empty board, single task, all tasks in one status, no assignees
- **Performance test:** 500+ issues to test initial load and drag performance

---

## 7. Risks and Mitigations

| Risk                                      | Likelihood | Impact | Mitigation                                                                    |
| ----------------------------------------- | ---------- | ------ | ----------------------------------------------------------------------------- |
| Drag-and-drop performance with many tasks | Medium     | High   | Virtualize task cards if >100 visible; load all initially per spec            |
| Conflicts on concurrent updates           | Medium     | Medium | Implement optimistic updates with rollback; show conflict resolution UI       |
| bd API changes                            | Low        | Medium | Abstract bd client layer; handle both old/new field names (owner vs assignee) |
| Mobile/tablet drag interaction            | Medium     | Low    | Out of scope per spec; desktop-only for now                                   |
| Missing bd statuses                       | Low        | High   | Query bd for available statuses at startup; handle unknown gracefully         |
| Zustand store complexity                  | Medium     | Medium | Keep filter logic pure functions; test extensively                            |

---

## 8. Open Questions

1. **Existing task detail view:** Is there an existing task detail view/component we should reuse, or do we need to create one from scratch?
2. **User list for assignment:** Where do we get the list of available assignees from? bd users? Git contributors? Hardcoded?
3. **Priority values:** What are the valid priority values in bd? (0-4? P0-P4? High/Medium/Low?)
4. **Custom statuses:** How do we handle if bd has custom statuses beyond open/in_progress/closed/blocked?

---

## 9. File Structure

```
src/
├── views/
│   └── KanbanBoard.tsx              # Main board view
├── components/
│   └── kanban/
│       ├── KanbanColumn.tsx         # Status column
│       ├── TaskCard.tsx             # Draggable task card
│       ├── TaskDetailModal.tsx      # Task detail view
│       ├── QuickCreateModal.tsx     # Quick task creation
│       ├── AssigneeSelector.tsx     # Assignee dropdown
│       ├── BoardFilters.tsx         # Filter controls
│       └── ErrorState.tsx           # Error display
├── stores/
│   └── dashboard.ts                 # Modified: add kanban actions
├── lib/
│   └── tauri.ts                     # Modified: add new commands
└── types/
    └── index.ts                     # Modified: add new interfaces

src-tauri/src/
├── commands/
│   └── bd_commands.rs               # Modified: add new commands
└── bd/
    └── mod.rs                       # Modified: add new API methods
```
