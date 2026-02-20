import { create } from "zustand";
import type {
  Issue,
  EpicStatus,
  Workspace,
  DaemonStatus,
  BootState,
  DashboardEvent,
  CacheStats,
  KanbanFilters,
} from "../types";
import * as tauri from "../lib/tauri";

// ---------------------------------------------------------------------------
// Store shape
// ---------------------------------------------------------------------------

export interface DashboardState {
  // Data
  issues: Issue[];
  workspaces: Workspace[];
  selectedWorkspace: Workspace | null;
  daemonStatus: DaemonStatus | null;
  cacheStats: CacheStats | null;
  opencodeConnected: boolean;

  // UI
  isLoading: boolean;
  error: string | null;
  bootState: BootState;

  // Filters
  kanbanFilters: KanbanFilters;
  showCompleted: boolean;
  showClosedEpics: boolean;
  viewMode: "status" | "epic";
  epics: EpicStatus[];
  filteredEpics: EpicStatus[];
  epicCollapseState: Record<string, boolean>;

  // Computed
  filteredIssues: Issue[];

  // Actions
  setError: (error: string | null) => void;
  setLoading: (loading: boolean) => void;

  // Boot
  setBootStep: (step: number, label: string) => void;
  setBootCompleted: () => void;
  setBootError: (error: string) => void;

  // Data fetching
  fetchIssues: () => Promise<void>;
  fetchWorkspaces: () => Promise<Workspace[]>;
  selectWorkspace: (workspace: Workspace) => Promise<void>;
  setSelectedWorkspace: (workspace: Workspace) => void;
  setWorkspaces: (workspaces: Workspace[]) => void;
  setDaemonStatus: (status: DaemonStatus) => void;
  setCacheStats: (stats: CacheStats) => void;
  setOpencodeConnected: (connected: boolean) => void;

  // Filter actions
  setKanbanFilters: (filters: KanbanFilters) => void;
  updateKanbanFilters: (partial: Partial<KanbanFilters>) => void;
  clearKanbanFilters: () => void;
  setShowCompleted: (show: boolean) => void;
  setShowClosedEpics: (show: boolean) => void;
  setViewMode: (mode: "status" | "epic") => void;
  fetchEpics: () => Promise<void>;
  toggleEpicCollapse: (epicId: string) => void;
  collapseAllEpics: () => void;
  expandAllEpics: () => void;

  // Event handling
  handleEvent: (event: DashboardEvent) => void;
}

// ---------------------------------------------------------------------------
// Initial boot state
// ---------------------------------------------------------------------------

const INITIAL_BOOT_STATE: BootState = {
  step: 0,
  totalSteps: 5,
  currentLabel: "Initializing...",
  completed: false,
};

const VIEW_MODE_KEY = "kanban-view-mode";
const EPIC_COLLAPSE_KEY = "kanban-epic-collapse";
const SHOW_CLOSED_EPICS_KEY = "kanban-show-closed-epics";

function readViewMode(): "status" | "epic" {
  if (typeof window === "undefined") return "status";
  const saved = window.localStorage.getItem(VIEW_MODE_KEY);
  return saved === "epic" ? "epic" : "status";
}

function readShowClosedEpics(): boolean {
  if (typeof window === "undefined") return false;
  return window.localStorage.getItem(SHOW_CLOSED_EPICS_KEY) === "true";
}

function readEpicCollapseState(): Record<string, boolean> {
  if (typeof window === "undefined") return {};
  const saved = window.localStorage.getItem(EPIC_COLLAPSE_KEY);
  if (!saved) return {};
  try {
    const parsed = JSON.parse(saved) as Record<string, boolean>;
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

function persist(key: string, value: string): void {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(key, value);
}

function filterClosedEpics(epics: EpicStatus[], showClosedEpics: boolean): EpicStatus[] {
  if (showClosedEpics) return epics;
  return epics.filter((epic) => epic.total !== epic.closed);
}

function getIssueEpicId(issue: Issue): string | undefined {
  const epicId = issue.epic_id;
  if (typeof epicId === "string" && epicId.length > 0) {
    return epicId;
  }
  return undefined;
}

// ---------------------------------------------------------------------------
// Store
// ---------------------------------------------------------------------------

const INITIAL_KANBAN_FILTERS: KanbanFilters = {};

export const useDashboardStore = create<DashboardState>((set, get) => ({
  // Data
  issues: [],
  workspaces: [],
  selectedWorkspace: null,
  daemonStatus: null,
  cacheStats: null,
  opencodeConnected: false,

  // UI
  isLoading: false,
  error: null,
  bootState: INITIAL_BOOT_STATE,

  // Filters
  kanbanFilters: INITIAL_KANBAN_FILTERS,
  showCompleted: false,
  showClosedEpics: readShowClosedEpics(),
  viewMode: readViewMode(),
  epics: [],
  filteredEpics: [],
  epicCollapseState: readEpicCollapseState(),

  // Computed — derived from issues + active filters
  filteredIssues: [],

  // -----------------------------------------------------------------------
  // UI Actions
  // -----------------------------------------------------------------------
  setError: (error) => set({ error }),
  setLoading: (isLoading) => set({ isLoading }),

  // -----------------------------------------------------------------------
  // Boot Actions
  // -----------------------------------------------------------------------
  setBootStep: (step, currentLabel) =>
    set((state) => ({
      bootState: { ...state.bootState, step, currentLabel },
    })),

  setBootCompleted: () =>
    set((state) => ({
      bootState: {
        ...state.bootState,
        completed: true,
        currentLabel: "Ready",
      },
    })),

  setBootError: (error) =>
    set((state) => ({
      bootState: { ...state.bootState, error },
    })),

  // -----------------------------------------------------------------------
  // Data Actions
  // -----------------------------------------------------------------------
  fetchIssues: async () => {
    try {
      set({ isLoading: true, error: null });
      const issues = await tauri.listIssues();
      const { kanbanFilters, showCompleted } = get();
      set({
        issues,
        isLoading: false,
        filteredIssues: getFilteredIssues(issues, kanbanFilters, showCompleted),
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      set({ error: message, isLoading: false });
    }
  },

  fetchEpics: async () => {
    try {
      const epics = await tauri.listEpics();
      const showClosedEpics = get().showClosedEpics;
      set({
        epics,
        filteredEpics: filterClosedEpics(epics, showClosedEpics),
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      set({ error: message });
    }
  },

  fetchWorkspaces: async () => {
    try {
      const workspaces = await tauri.listWorkspaces();
      set({ workspaces });
      return workspaces;
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      set({ error: message });
      return [];
    }
  },

  selectWorkspace: async (workspace) => {
    try {
      await tauri.switchWorkspace(workspace.path);
      set({ selectedWorkspace: workspace, error: null });
      // Fetch issues for the newly selected workspace
      const issues = await tauri.listIssues();
      const { kanbanFilters, showCompleted } = get();
      set({ issues, filteredIssues: getFilteredIssues(issues, kanbanFilters, showCompleted) });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      set({ selectedWorkspace: workspace, error: message });
    }
  },

  setSelectedWorkspace: (workspace) => set({ selectedWorkspace: workspace }),
  setWorkspaces: (workspaces) => set({ workspaces }),

  setDaemonStatus: (daemonStatus) => set({ daemonStatus }),

  setCacheStats: (cacheStats) => set({ cacheStats }),

  setOpencodeConnected: (opencodeConnected) => set({ opencodeConnected }),

  // -----------------------------------------------------------------------
  // Filter Actions
  // -----------------------------------------------------------------------
  setKanbanFilters: (kanbanFilters) =>
    set((state) => ({
      kanbanFilters,
      filteredIssues: getFilteredIssues(state.issues, kanbanFilters, state.showCompleted),
    })),

  updateKanbanFilters: (partial) =>
    set((state) => {
      const kanbanFilters = { ...state.kanbanFilters, ...partial };
      return {
        kanbanFilters,
        filteredIssues: getFilteredIssues(state.issues, kanbanFilters, state.showCompleted),
      };
    }),

  clearKanbanFilters: () =>
    set((state) => ({
      kanbanFilters: INITIAL_KANBAN_FILTERS,
      filteredIssues: getFilteredIssues(state.issues, INITIAL_KANBAN_FILTERS, state.showCompleted),
    })),

  setShowCompleted: (showCompleted) =>
    set((state) => ({
      showCompleted,
      filteredIssues: getFilteredIssues(state.issues, state.kanbanFilters, showCompleted),
    })),

  setShowClosedEpics: (showClosedEpics) =>
    set((state) => {
      persist(SHOW_CLOSED_EPICS_KEY, String(showClosedEpics));
      return {
        showClosedEpics,
        filteredEpics: filterClosedEpics(state.epics, showClosedEpics),
      };
    }),

  setViewMode: (viewMode) => {
    persist(VIEW_MODE_KEY, viewMode);
    set({ viewMode });
  },

  toggleEpicCollapse: (epicId) =>
    set((state) => {
      const epicCollapseState = {
        ...state.epicCollapseState,
        [epicId]: !state.epicCollapseState[epicId],
      };
      persist(EPIC_COLLAPSE_KEY, JSON.stringify(epicCollapseState));
      return { epicCollapseState };
    }),

  collapseAllEpics: () =>
    set((state) => {
      const epicCollapseState = state.filteredEpics.reduce<Record<string, boolean>>((acc, epic) => {
        acc[epic.id] = true;
        return acc;
      }, { ...state.epicCollapseState });
      persist(EPIC_COLLAPSE_KEY, JSON.stringify(epicCollapseState));
      return { epicCollapseState };
    }),

  expandAllEpics: () =>
    set((state) => {
      const epicCollapseState = state.filteredEpics.reduce<Record<string, boolean>>((acc, epic) => {
        acc[epic.id] = false;
        return acc;
      }, { ...state.epicCollapseState });
      persist(EPIC_COLLAPSE_KEY, JSON.stringify(epicCollapseState));
      return { epicCollapseState };
    }),

  // -----------------------------------------------------------------------
  // Event handler — dispatches DashboardEvent from Tauri Channel
  // -----------------------------------------------------------------------
  handleEvent: (event) => {
    switch (event.type) {
      case "IssueUpdated": {
        // Handles all issue mutations: status changes, assignee changes, etc.
        const updated = event.issue;
        set((state) => {
          const idx = state.issues.findIndex((i) => i.id === updated.id);
          const issues =
            idx >= 0
              ? state.issues.map((i, j) => (j === idx ? updated : i))
              : [...state.issues, updated];
          return {
            issues,
            filteredIssues: getFilteredIssues(issues, state.kanbanFilters, state.showCompleted),
          };
        });
        break;
      }

      case "CacheRefreshed": {
        // Re-fetch issues when the cache is refreshed
        get().fetchIssues();
        break;
      }

      case "ConnectionChanged": {
        if (event.source === "Opencode") {
          set({ opencodeConnected: event.connected });
        }
        break;
      }

      // Orchestrator events — refresh issues when tasks change status
      case "TaskSessionLaunched":
      case "TaskSessionCompleted":
      case "EpicCompleted":
        get().fetchIssues();
        break;

      default:
        break;
    }
  },
}));

// ---------------------------------------------------------------------------
// Filtered Issues Selector
// ---------------------------------------------------------------------------

export function getFilteredIssues(
  issues: Issue[],
  filters: KanbanFilters,
  showCompleted: boolean,
): Issue[] {
  return issues
    .filter((issue) => {
      // Filter by assignee if set
      if (filters.assignee && filters.assignee.length > 0) {
        const assigneeMatch = issue.assignee && filters.assignee.includes(issue.assignee);
        const ownerMatch = issue.owner && filters.assignee.includes(issue.owner);
        if (!assigneeMatch && !ownerMatch) {
          return false;
        }
      }

      // Filter out closed tasks if showCompleted is false
      if (!showCompleted && issue.status === "closed") {
        return false;
      }

      // Filter by status if set
      if (filters.status && filters.status.length > 0) {
        if (!filters.status.includes(issue.status)) {
          return false;
        }
      }

      // Filter by priority if set
      if (filters.priority && filters.priority.length > 0) {
        const issuePriority =
          typeof issue.priority === "string" ? parseInt(issue.priority, 10) : issue.priority;
        if (issuePriority === null || !filters.priority.includes(issuePriority)) {
          return false;
        }
      }

      // Filter by labels if set
      if (filters.labels && filters.labels.length > 0) {
        const hasMatchingLabel = filters.labels.some((label) => issue.labels.includes(label));
        if (!hasMatchingLabel) {
          return false;
        }
      }

      // Filter by epic if set
      if (filters.epic && filters.epic.length > 0) {
        const epicId = getIssueEpicId(issue);
        if (!epicId || !filters.epic.includes(epicId)) {
          return false;
        }
      }

      // Filter by search term if set
      if (filters.search) {
        const searchLower = filters.search.toLowerCase();
        const titleMatch = issue.title.toLowerCase().includes(searchLower);
        const idMatch = issue.id.toLowerCase().includes(searchLower);
        if (!titleMatch && !idMatch) {
          return false;
        }
      }

      return true;
    })
    .sort((a, b) => {
      // Sort by priority (lower number = higher priority)
      const priorityA = typeof a.priority === "string" ? parseInt(a.priority, 10) : a.priority;
      const priorityB = typeof b.priority === "string" ? parseInt(b.priority, 10) : b.priority;

      if (priorityA === null && priorityB === null) return 0;
      if (priorityA === null) return 1;
      if (priorityB === null) return -1;

      return priorityA - priorityB;
    });
}
