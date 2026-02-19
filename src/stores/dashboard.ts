import { create } from "zustand";
import type {
  Issue,
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
