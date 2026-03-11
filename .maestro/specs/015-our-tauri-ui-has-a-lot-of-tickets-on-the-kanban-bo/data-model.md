# Data Model: Epic-Grouped Kanban Board View

**Feature ID:** 015-our-tauri-ui-has-a-lot-of-tickets-on-the-kanban-bo
**Created:** 2026-02-19

---

## 1. Overview

This document defines the data models and schemas for the Epic-Grouped Kanban Board View feature. The feature requires **no backend changes** — all modifications are frontend-only, extending existing types and adding new derived data structures.

---

## 2. TypeScript Types

### 2.1 New Types

#### EpicStatus

Represents an epic with progress statistics.

```typescript
// src/types/index.ts

export interface EpicStatus {
  /** Unique epic identifier */
  id: string;

  /** Epic title (display name) */
  title: string;

  /** Total number of issues in epic */
  total: number;

  /** Number of open issues */
  open: number;

  /** Number of closed issues */
  closed: number;

  /** Number of in-progress issues */
  in_progress: number;

  /** Number of blocked issues */
  blocked: number;

  /** Additional fields from backend (serde flatten) */
  [key: string]: unknown;
}
```

**Source:** Mirrors Rust `EpicStatus` struct from `src-tauri/src/bd/types.rs` lines 65-75.

---

### 2.2 Modified Types

#### KanbanFilters (Extended)

```typescript
// src/types/index.ts

export interface KanbanFilters {
  /** Filter by status(es) */
  status?: string[];

  /** Filter by assignee(s) */
  assignee?: string[];

  /** Filter by priority level(s) */
  priority?: number[];

  /** Filter by label(s) */
  labels?: string[];

  /** Text search in title/ID */
  search?: string;

  /** NEW: Filter by epic ID(s) */
  epic?: string[];
}
```

**Validation Rules:**

- `epic` is optional
- Each string in `epic` must be a valid epic ID
- Empty array `[]` is equivalent to `undefined` (no filter)

---

#### Issue (Access Pattern)

**Note:** `Issue` type is unchanged, but access pattern for epic ID is documented:

```typescript
// src/types/index.ts

export interface Issue {
  // ... existing fields ...

  /**
   * Epic ID is stored in the flattened `extra` field via serde.
   * Access via: issue['epic_id'] or issue.extra?.epic_id
   */
  [key: string]: unknown;
}

// Access helper function
export function getIssueEpicId(issue: Issue): string | undefined {
  return issue["epic_id"] as string | undefined;
}
```

---

#### DashboardState (Zustand Store)

```typescript
// src/stores/dashboard.ts

export interface DashboardState {
  // === EXISTING FIELDS ===

  /** All issues loaded from backend */
  issues: Issue[];

  /** Current filter settings */
  kanbanFilters: KanbanFilters;

  /** Whether to show completed/closed issues */
  showCompleted: boolean;

  /** Currently selected workspace */
  workspace: string | null;

  /** Loading states */
  isLoading: boolean;
  isError: boolean;

  /**
   * Computed: Filtered and sorted issues for display.
   * Computed from: issues + kanbanFilters + showCompleted
   */
  filteredIssues: Issue[];

  // === NEW FIELDS ===

  /**
   * Current view mode: 'status' or 'epic'
   * Default: 'status'
   * Persisted in localStorage
   */
  viewMode: "status" | "epic";

  /**
   * All epics loaded from backend.
   * Populated when Epic View is first activated.
   * Used for filter dropdowns and swimlane headers.
   */
  epics: EpicStatus[];

  /**
   * Whether to show closed epics in Epic View.
   * Default: false (hidden by default)
   * Persisted in localStorage
   */
  showClosedEpics: boolean;

  /**
   * Collapse state for each epic.
   * Map<epicId, isCollapsed>
   * Default: all expanded
   * Persisted in localStorage (limited to 50 epics)
   */
  epicCollapseState: Map<string, boolean>;

  // === COMPUTED PROPERTIES ===

  /**
   * Computed: Epics filtered by showClosedEpics toggle.
   * If showClosedEpics is false, exclude epics with total == closed.
   */
  filteredEpics: EpicStatus[];

  // === ACTIONS ===

  // ... existing actions ...

  /** Set view mode and persist to localStorage */
  setViewMode: (mode: "status" | "epic") => void;

  /** Fetch epics from backend and populate epics array */
  fetchEpics: () => Promise<void>;

  /** Toggle collapse state for a single epic */
  toggleEpicCollapse: (epicId: string) => void;

  /** Collapse all visible epics */
  collapseAllEpics: () => void;

  /** Expand all visible epics */
  expandAllEpics: () => void;
}
```

---

## 3. localStorage Schema

### 3.1 Persistence Keys

```typescript
// Constants for localStorage keys

const STORAGE_KEYS = {
  /** View mode preference: 'status' | 'epic' */
  VIEW_MODE: "kanban-view-mode-v1",

  /** Epic collapse state: JSON string of Map<string, boolean> */
  EPIC_COLLAPSE: "kanban-epic-collapse-v1",

  /** Show closed epics: 'true' | 'false' */
  SHOW_CLOSED_EPICS: "kanban-show-closed-epics-v1",

  /** Epic filter: JSON string of string[] */
  EPIC_FILTER: "kanban-epic-filter-v1",
} as const;
```

### 3.2 Storage Format

#### View Mode

```typescript
// Stored as simple string
type ViewModeStorage = "status" | "epic";

localStorage.setItem("kanban-view-mode-v1", "epic");
```

#### Epic Collapse State

```typescript
// Stored as JSON string, limited to 50 epics
type EpicCollapseStorage = Array<[string, boolean]>;

const collapseState: EpicCollapseStorage = [
  ["epic-1", true], // epic-1 is collapsed
  ["epic-2", false], // epic-2 is expanded
  ["epic-3", true],
  // ... up to 50 entries
];

localStorage.setItem("kanban-epic-collapse-v1", JSON.stringify(collapseState));
```

**Migration logic:** If stored data exceeds 50 entries, keep only the 50 most recent (by last access time if available, otherwise truncate to first 50).

#### Show Closed Epics

```typescript
// Stored as boolean string
type ShowClosedStorage = "true" | "false";

localStorage.setItem("kanban-show-closed-epics-v1", "true");
```

#### Epic Filter

```typescript
// Stored as JSON string
type EpicFilterStorage = string[];

const filter: EpicFilterStorage = ["epic-1", "epic-3"];

localStorage.setItem("kanban-epic-filter-v1", JSON.stringify(filter));
```

### 3.3 Migration Strategy

**Versioned Keys:**

- All keys include version suffix (`-v1`)
- Future schema changes increment version
- On app load, check for legacy keys (without version)
- If legacy found, migrate data and delete legacy

**Migration function:**

```typescript
function migrateLocalStorage(): void {
  const legacyKey = "kanban-view-mode";
  const newKey = "kanban-view-mode-v1";

  if (localStorage.getItem(legacyKey) && !localStorage.getItem(newKey)) {
    localStorage.setItem(newKey, localStorage.getItem(legacyKey)!);
    localStorage.removeItem(legacyKey);
  }

  // Repeat for other keys...
}
```

---

## 4. Data Flow

### 4.1 Epic Data Fetching

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   UI Trigger    │────▶│  DashboardStore │────▶│   Rust Backend  │
│ (switch to      │     │  fetchEpics()    │     │  list_epics()   │
│  Epic View)     │     │                  │     │                 │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                        │
                                                        ▼
                                                 ┌─────────────────┐
                                                 │ EpicStatus[]    │
                                                 │ Response        │
                                                 └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   EpicView      │◀────│  DashboardStore │◀────│   Store State   │
│   Rendering     │     │  state.epics     │     │   state.epics   │
│                 │     │                  │     │   populated     │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

### 4.2 Issue Grouping by Epic

```typescript
// Pseudocode for grouping logic

function groupIssuesByEpic(issues: Issue[], epics: EpicStatus[]): EpicGroups {
  const groups: EpicGroups = {};
  const noEpicIssues: Issue[] = [];

  // Create group for each epic
  for (const epic of epics) {
    groups[epic.id] = {
      epic,
      issues: [],
    };
  }

  // Distribute issues
  for (const issue of issues) {
    const epicId = getIssueEpicId(issue);

    if (epicId && groups[epicId]) {
      groups[epicId].issues.push(issue);
    } else {
      // Orphaned epic reference or no epic
      noEpicIssues.push(issue);
    }
  }

  // Sort epics alphabetically
  const sortedGroups = sortBy(Object.values(groups), (g) => g.epic.title);

  // Add No Epic group at bottom if needed
  if (noEpicIssues.length > 0) {
    sortedGroups.push({
      epic: {
        id: "no-epic",
        title: "No Epic",
        total: 0,
        open: 0,
        closed: 0,
        in_progress: 0,
        blocked: 0,
      },
      issues: noEpicIssues,
    });
  }

  return sortedGroups;
}
```

### 4.3 Filter Application

```
Original Issues
      │
      ▼
┌─────────────────┐
│ Status Filter │ (if active)
└─────────────────┘
      │
      ▼
┌─────────────────┐
│ Assignee Filter│ (if active)
└─────────────────┘
      │
      ▼
┌─────────────────┐
│ Priority Filter│ (if active)
└─────────────────┘
      │
      ▼
┌─────────────────┐
│ Labels Filter  │ (if active)
└─────────────────┘
      │
      ▼
┌─────────────────┐
│  Epic Filter   │ (if active) ◀── NEW
└─────────────────┘
      │
      ▼
┌─────────────────┐
│ Search Filter  │ (if active)
└─────────────────┘
      │
      ▼
┌─────────────────┐
│ Show Completed │ (if false, exclude closed)
└─────────────────┘
      │
      ▼
Filtered Issues
```

---

## 5. Rust Backend Types

### 5.1 Existing Types (No Changes)

**Issue struct:**

```rust
// src-tauri/src/bd/types.rs

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Issue {
    pub id: String,
    pub title: String,
    pub status: String,
    pub priority: Option<Value>,
    pub labels: Vec<String>,
    pub dependencies: Vec<Value>,
    pub assignee: Option<String>,
    pub owner: Option<String>,
    pub issue_type: Option<String>,
    #[serde(flatten)]
    pub extra: HashMap<String, Value>,  // epic_id stored here
}
```

**EpicStatus struct:**

```rust
// src-tauri/src/bd/types.rs

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EpicStatus {
    pub id: String,
    pub title: String,
    pub total: u32,
    pub open: u32,
    pub closed: u32,
    pub in_progress: u32,
    pub blocked: u32,
    #[serde(flatten)]
    pub extra: HashMap<String, Value>,
}
```

### 5.2 Available Commands

**list_epics():**

```rust
#[tauri::command]
pub async fn list_epics(state: tauri::State<'_, AppState>) -> Result<Vec<EpicStatus>, String> {
    // Returns all epics from cache
}
```

**get_epic_status(epic_id):**

```rust
#[tauri::command]
pub async fn get_epic_status(
    epic_id: String,
    state: tauri::State<'_, AppState>
) -> Result<EpicStatus, String> {
    // Returns single epic by ID
}
```

**get_cached_epic(id):**

```rust
#[tauri::command]
pub async fn get_cached_epic(
    id: String,
    state: tauri::State<'_, AppState>
) -> Result<Option<EpicStatus>, String> {
    // Returns epic from cache if exists
}
```

---

## 6. Validation Rules

### 6.1 Epic ID Validation

- Epic IDs must be non-empty strings
- Epic IDs from `epic_id` field must match an epic in the `epics` array
- Invalid/orphaned epic IDs are treated as "No Epic"

### 6.2 Filter Validation

- `epic` filter: each ID must exist in `epics` array
- Empty `epic` array: equivalent to no filter
- Duplicate IDs in `epic` array: deduplicate

### 6.3 State Validation

- `viewMode`: must be 'status' or 'epic'
- `showClosedEpics`: must be boolean
- `epicCollapseState`: Map keys must be valid epic IDs
- If invalid data loaded from localStorage, reset to defaults

---

## 7. Changelog

| Date       | Change                     | Author |
| ---------- | -------------------------- | ------ |
| 2026-02-19 | Initial data model created | System |
