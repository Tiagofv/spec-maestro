// TypeScript types mirroring Rust backend types
// All types use `serde(flatten)` for `extra` in Rust, which means
// unknown fields appear as top-level keys. We use Record<string, unknown>
// for forward compatibility but keep known fields explicit.

// ---------------------------------------------------------------------------
// bd types (from src-tauri/src/bd/types.rs)
// ---------------------------------------------------------------------------

export interface Issue {
  id: string;
  title: string;
  status: string; // "open" | "in_progress" | "closed"
  priority: number | string | null; // bd 0.47+ sends integer (0-4)
  labels: string[];
  dependencies: string[];
  assignee: string | null;
  owner: string | null; // bd may return "owner" instead of/alongside "assignee"
  issue_type: string | null; // "Task" | "Epic" | "Feature" | "Bug" etc.
  [key: string]: unknown; // serde(flatten) extra
}

export interface DaemonStatus {
  running: boolean;
  pid: number | null;
  uptime_seconds: number | null;
  port: number | null;
  [key: string]: unknown;
}

export interface Workspace {
  path: string;
  name: string;
  daemon_running: boolean;
  issue_count?: number; // Count of open issues in this workspace
  [key: string]: unknown;
}

// ---------------------------------------------------------------------------
// opencode types
// ---------------------------------------------------------------------------

export interface OpencodeStatusResponse {
  connected: boolean;
  session_count: number;
}

// ---------------------------------------------------------------------------
// cache types (from src-tauri/src/cache/)
// ---------------------------------------------------------------------------

export interface CacheStats {
  total_issues: number;
  open: number;
  closed: number;
  in_progress: number;
  blocked: number;
  pending_gates: number;
  last_sync: string;
}

// ---------------------------------------------------------------------------
// events (from src-tauri/src/events.rs)
// ---------------------------------------------------------------------------

export type EventSource = "Bd" | "Opencode";

export type DashboardEvent =
  | { type: "IssueUpdated"; source: EventSource; issue: Issue }
  | { type: "CacheRefreshed"; source: EventSource; stats: string }
  | { type: "ConnectionChanged"; source: EventSource; connected: boolean }
  | {
      type: "TaskSessionLaunched";
      source: EventSource;
      epic_id: string;
      task_id: string;
      session_id: string;
    }
  | {
      type: "TaskSessionCompleted";
      source: EventSource;
      epic_id: string;
      task_id: string;
      result: string;
    }
  | { type: "EpicCompleted"; source: EventSource; epic_id: string };

// ---------------------------------------------------------------------------
// App-level types
// ---------------------------------------------------------------------------

export interface BootState {
  step: number;
  totalSteps: number;
  currentLabel: string;
  completed: boolean;
  error?: string;
}

// ---------------------------------------------------------------------------
// Health types (from src-tauri/src/health.rs)
// ---------------------------------------------------------------------------

export interface HealthStatus {
  bd_available: boolean;
  bd_version?: string;
  daemon_running: boolean;
  opencode_available: boolean;
  opencode_url?: string;
  cache_age_secs?: number;
  cache_stale: boolean;
  last_check: number;
}

export type SortDirection = "asc" | "desc";

export interface SortConfig {
  column: string;
  direction: SortDirection;
}

// ---------------------------------------------------------------------------
// Kanban and Issue Management types
// ---------------------------------------------------------------------------

export interface KanbanFilters {
  status?: string[];
  assignee?: string[];
  priority?: number[];
  labels?: string[];
  search?: string;
}

export interface CreateIssueRequest {
  title: string;
  description?: string;
  labels?: string[];
  parentId?: string;
}

export interface UpdateIssueStatusRequest {
  issueId: string;
  status: string;
  [key: string]: unknown;
}
