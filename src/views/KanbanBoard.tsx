import { useMemo, useState, useCallback, useEffect } from "react";
import {
  DndContext,
  DragOverlay,
  closestCorners,
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
  type DragStartEvent,
} from "@dnd-kit/core";
import {
  SortableContext,
  sortableKeyboardCoordinates,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { useDashboardStore } from "../stores/dashboard";
import { TaskDetailModal } from "../components/kanban/TaskDetailModal";
import { QuickCreateModal } from "../components/kanban/QuickCreateModal";
import { KanbanColumn } from "../components/kanban/KanbanColumn";
import { BoardFilters } from "../components/kanban/BoardFilters";
import * as tauri from "../lib/tauri";
import type { Issue } from "../types";

// ---------------------------------------------------------------------------
// Column definitions
// ---------------------------------------------------------------------------

interface KanbanColumn {
  id: string;
  label: string;
  statusFilter: string;
  color: string;
}

const COLUMNS: KanbanColumn[] = [
  {
    id: "open",
    label: "Open",
    statusFilter: "open",
    color: "bg-blue-500/15 text-blue-400 border-blue-500/30",
  },
  {
    id: "in_progress",
    label: "In Progress",
    statusFilter: "in_progress",
    color: "bg-amber-500/15 text-amber-400 border-amber-500/30",
  },
  {
    id: "blocked",
    label: "Blocked",
    statusFilter: "blocked",
    color: "bg-red-500/15 text-red-400 border-red-500/30",
  },
  {
    id: "closed",
    label: "Closed",
    statusFilter: "closed",
    color:
      "bg-[var(--color-success)]/15 text-[var(--color-success)] border-[var(--color-success)]/30",
  },
];

// ---------------------------------------------------------------------------
// Priority helpers
// ---------------------------------------------------------------------------

function getPriorityValue(priority: number | string | null): number {
  if (priority == null) return 999;
  const v = typeof priority === "number" ? priority : parseInt(priority, 10);
  if (Number.isNaN(v)) return 999;
  return v;
}

function priorityLabel(p: number | string | null): string {
  const v = getPriorityValue(p);
  if (v === 999) return "-";
  switch (v) {
    case 0:
      return "-";
    case 1:
      return "P1";
    case 2:
      return "P2";
    case 3:
      return "P3";
    case 4:
      return "P4";
    default:
      return String(v);
  }
}

function priorityColor(p: number | string | null): string {
  const v = getPriorityValue(p);
  switch (v) {
    case 1:
      return "bg-red-500 text-white";
    case 2:
      return "bg-orange-500 text-white";
    case 3:
      return "bg-yellow-500 text-black";
    case 4:
      return "bg-green-500 text-white";
    default:
      return "bg-[var(--color-border)] text-[var(--color-text-secondary)]";
  }
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function KanbanBoard() {
  const issues = useDashboardStore((s) => s.issues);
  const filteredIssues = useDashboardStore((s) => s.filteredIssues);
  const isLoading = useDashboardStore((s) => s.isLoading);
  const error = useDashboardStore((s) => s.error);
  const fetchIssues = useDashboardStore((s) => s.fetchIssues);
  const setError = useDashboardStore((s) => s.setError);

  // Derive unique assignees from all issues for the filter bar
  const allAssignees = useMemo(() => {
    const set = new Set<string>();
    for (const issue of issues) {
      if (issue.assignee) set.add(issue.assignee);
      if (issue.owner) set.add(issue.owner);
    }
    return Array.from(set).sort();
  }, [issues]);

  // Task detail modal state
  const [selectedIssue, setSelectedIssue] = useState<Issue | null>(null);
  const [isModalOpen, setIsModalOpen] = useState(false);

  // Quick create modal state
  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false);

  // Drag-and-drop state
  const [activeId, setActiveId] = useState<string | null>(null);
  const [localIssues, setLocalIssues] = useState<Issue[]>(filteredIssues);

  // Sync local issues with filtered issues from store (when not dragging)
  useEffect(() => {
    if (!activeId) setLocalIssues(filteredIssues);
  }, [filteredIssues, activeId]);

  // Sensors for drag-and-drop
  const sensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: {
        distance: 8,
      },
    }),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    }),
  );

  // Get the active issue for drag overlay
  const activeIssue = useMemo(() => {
    return activeId ? localIssues.find((i) => i.id === activeId) : null;
  }, [activeId, localIssues]);

  const handleTaskClick = useCallback((issue: Issue) => {
    setSelectedIssue(issue);
    setIsModalOpen(true);
  }, []);

  const handleCloseModal = useCallback(() => {
    setIsModalOpen(false);
    setSelectedIssue(null);
  }, []);

  // Group issues by status and sort by priority (highest first = lowest number)
  const columnsData = useMemo(() => {
    const grouped = new Map<string, Issue[]>();

    // Initialize empty arrays for each column
    COLUMNS.forEach((col) => {
      grouped.set(col.id, []);
    });

    // Group issues by status
    localIssues.forEach((issue) => {
      const status = issue.status.toLowerCase();
      const column = COLUMNS.find((c) => c.statusFilter === status);
      if (column) {
        const current = grouped.get(column.id) || [];
        current.push(issue);
        grouped.set(column.id, current);
      } else {
        // Default to open for unknown statuses
        const current = grouped.get("open") || [];
        current.push(issue);
        grouped.set("open", current);
      }
    });

    // Sort each column by priority (highest first = lowest priority number)
    COLUMNS.forEach((col) => {
      const colIssues = grouped.get(col.id) || [];
      colIssues.sort((a, b) => getPriorityValue(a.priority) - getPriorityValue(b.priority));
      grouped.set(col.id, colIssues);
    });

    return grouped;
  }, [localIssues]);

  // Memoize per-column item ID arrays to stabilize SortableContext items prop
  const columnItemIds = useMemo(
    () => new Map(COLUMNS.map((col) => [col.id, (columnsData.get(col.id) || []).map((i) => i.id)])),
    [columnsData],
  );

  // Handle drag start
  const handleDragStart = useCallback((event: DragStartEvent) => {
    setActiveId(event.active.id as string);
    // Add lift effect to the dragged element
    const element = document.querySelector(`[data-id="${event.active.id}"]`);
    if (element) {
      element.classList.add("drag-lift");
    }
  }, []);

  // Handle drag end - update issue status
  const handleDragEnd = useCallback(
    async (event: DragEndEvent) => {
      const { active, over } = event;

      // Remove lift effect
      const element = document.querySelector(`[data-id="${active.id}"]`);
      if (element) {
        element.classList.remove("drag-lift");
      }

      if (!over) {
        // Return animation on cancel
        if (element) {
          element.classList.add("drag-return");
          setTimeout(() => {
            element.classList.remove("drag-return");
          }, 200);
        }
        setActiveId(null);
        return;
      }

      const issueId = active.id as string;
      const columnId = over.id as string;

      // Find the target column
      const targetColumn = COLUMNS.find((c) => c.id === columnId);
      if (!targetColumn) {
        setActiveId(null);
        return;
      }

      // Find the issue
      const issue = localIssues.find((i) => i.id === issueId);
      if (!issue) {
        setActiveId(null);
        return;
      }

      // Don't update if status is the same
      if (issue.status === targetColumn.statusFilter) {
        setActiveId(null);
        return;
      }

      setActiveId(null);

      // Optimistic update
      const originalIssues = [...localIssues];
      setLocalIssues((prev) =>
        prev.map((i) => (i.id === issueId ? { ...i, status: targetColumn.statusFilter } : i)),
      );

      // Call backend to update status
      try {
        await tauri.updateIssueStatus(issueId, targetColumn.statusFilter);
      } catch (err) {
        // Rollback on error
        setLocalIssues(originalIssues);
        const message = err instanceof Error ? err.message : String(err);
        setError(`Failed to update issue status: ${message}`);
      }
    },
    [localIssues, setError],
  );

  // -----------------------------------------------------------------------
  // Render
  // -----------------------------------------------------------------------

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
        <h2 className="text-lg font-semibold text-[var(--color-text)]">Kanban Board</h2>
        <div className="flex items-center gap-2">
          {/* Create Task button */}
          <button
            onClick={() => setIsCreateModalOpen(true)}
            className="text-xs px-3 py-1.5 rounded-md bg-[var(--color-primary)] text-white hover:bg-[var(--color-primary)]/90 transition-all duration-200 flex items-center gap-1.5 font-medium"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              className="h-3.5 w-3.5"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              aria-hidden="true"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M12 4v16m8-8H4"
              />
            </svg>
            Create Task
          </button>

          {/* Refresh button */}
          <button
            onClick={() => fetchIssues()}
            disabled={isLoading}
            className="text-xs px-3 py-1.5 rounded-md border border-[var(--color-border)] text-[var(--color-text-secondary)] hover:bg-[var(--color-border)]/50 disabled:opacity-50 transition-all duration-200 flex items-center gap-2"
          >
            {isLoading ? (
              <>
                <svg
                  className="spinner h-3.5 w-3.5"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <circle
                    className="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    strokeWidth="4"
                  ></circle>
                  <path
                    className="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  ></path>
                </svg>
                <span>Loading...</span>
              </>
            ) : (
              <>
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  className="h-3.5 w-3.5"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                  />
                </svg>
                <span>Refresh</span>
              </>
            )}
          </button>
        </div>
      </div>

      {/* Filters */}
      <BoardFilters assignees={allAssignees} />

      {/* Error banner */}
      {error && (
        <div className="mx-6 mt-3 p-3 bg-[var(--color-error)]/10 border border-[var(--color-error)]/30 rounded-md text-sm text-[var(--color-error)]">
          {error}
        </div>
      )}

      {/* Kanban Board */}
      <div className="flex-1 overflow-auto p-6">
        {isLoading && localIssues.length === 0 ? (
          <div className="flex gap-4 h-full animate-view-enter">
            {COLUMNS.map((col, colIndex) => (
              <div
                key={col.id}
                className="flex-1 min-w-[280px]"
                style={{ animationDelay: `${colIndex * 100}ms` }}
              >
                <div className="skeleton h-6 w-24 mb-3 rounded" />
                <div className="space-y-3">
                  {Array.from({ length: 3 }).map((_, i) => (
                    <div
                      key={i}
                      className="skeleton h-24 rounded-lg"
                      style={{ animationDelay: `${(colIndex * 3 + i) * 50}ms` }}
                    />
                  ))}
                </div>
              </div>
            ))}
          </div>
        ) : localIssues.length === 0 ? (
          <div className="flex items-center justify-center h-full text-[var(--color-text-secondary)] text-sm">
            No issues found
          </div>
        ) : (
          <DndContext
            sensors={sensors}
            collisionDetection={closestCorners}
            onDragStart={handleDragStart}
            onDragEnd={handleDragEnd}
          >
            <div className="flex gap-4 h-full min-w-fit">
              {COLUMNS.map((column) => {
                const colIssues = columnsData.get(column.id) || [];
                return (
                  <SortableContext
                    key={column.id}
                    items={columnItemIds.get(column.id) || []}
                    strategy={verticalListSortingStrategy}
                  >
                    <KanbanColumn
                      id={column.id}
                      label={column.label}
                      color={column.color}
                      issues={colIssues}
                      onTaskClick={handleTaskClick}
                    />
                  </SortableContext>
                );
              })}
            </div>

            {/* Drag overlay - shows the item being dragged */}
            <DragOverlay>
              {activeIssue ? (
                <div className="p-3 rounded-lg bg-[var(--color-bg)] border-2 border-[var(--color-primary)] shadow-xl rotate-2 scale-105">
                  {/* Title */}
                  <h3 className="text-sm font-medium text-[var(--color-text)] mb-2 line-clamp-2">
                    {activeIssue.title}
                  </h3>

                  {/* Meta info */}
                  <div className="flex items-center justify-between">
                    {/* Priority badge */}
                    <span
                      className={`inline-block px-2 py-0.5 rounded text-[10px] font-medium ${priorityColor(activeIssue.priority)}`}
                    >
                      {priorityLabel(activeIssue.priority)}
                    </span>

                    {/* Assignee */}
                    <span className="text-xs text-[var(--color-text-secondary)] truncate max-w-[120px]">
                      {activeIssue.assignee ?? activeIssue.owner ?? "Unassigned"}
                    </span>
                  </div>

                  {/* ID */}
                  <div className="mt-2 text-[10px] font-mono text-[var(--color-text-secondary)]">
                    {activeIssue.id}
                  </div>
                </div>
              ) : null}
            </DragOverlay>
          </DndContext>
        )}
      </div>

      {/* Task Detail Modal */}
      <TaskDetailModal issue={selectedIssue} isOpen={isModalOpen} onClose={handleCloseModal} />

      {/* Quick Create Modal */}
      <QuickCreateModal
        isOpen={isCreateModalOpen}
        onClose={() => setIsCreateModalOpen(false)}
        onCreated={() => fetchIssues()}
      />
    </div>
  );
}
