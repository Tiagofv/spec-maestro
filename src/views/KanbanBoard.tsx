import { useMemo, useState, useCallback } from "react";
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
  type DragOverEvent,
} from "@dnd-kit/core";
import {
  SortableContext,
  sortableKeyboardCoordinates,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { useDashboardStore } from "../stores/dashboard";
import { TaskDetailModal } from "../components/kanban/TaskDetailModal";
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
  const isLoading = useDashboardStore((s) => s.isLoading);
  const error = useDashboardStore((s) => s.error);
  const fetchIssues = useDashboardStore((s) => s.fetchIssues);
  const setError = useDashboardStore((s) => s.setError);

  // Modal state
  const [selectedIssue, setSelectedIssue] = useState<Issue | null>(null);
  const [isModalOpen, setIsModalOpen] = useState(false);

  // Drag-and-drop state
  const [activeId, setActiveId] = useState<string | null>(null);
  const [localIssues, setLocalIssues] = useState<Issue[]>(issues);
  const [isDraggingOver, setIsDraggingOver] = useState<string | null>(null);

  // Sync local issues with store issues (when not dragging)
  if (issues !== localIssues && !activeId) {
    setLocalIssues(issues);
  }

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

  // Handle drag start
  const handleDragStart = useCallback((event: DragStartEvent) => {
    setActiveId(event.active.id as string);
    // Add lift effect to the dragged element
    const element = document.querySelector(`[data-id="${event.active.id}"]`);
    if (element) {
      element.classList.add("drag-lift");
    }
  }, []);

  // Handle drag over (for visual feedback)
  const handleDragOver = useCallback((event: DragOverEvent) => {
    const { over } = event;
    setIsDraggingOver(over ? (over.id as string) : null);
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
        setIsDraggingOver(null);
        return;
      }

      const issueId = active.id as string;
      const columnId = over.id as string;

      // Find the target column
      const targetColumn = COLUMNS.find((c) => c.id === columnId);
      if (!targetColumn) {
        setActiveId(null);
        setIsDraggingOver(null);
        return;
      }

      // Find the issue
      const issue = localIssues.find((i) => i.id === issueId);
      if (!issue) {
        setActiveId(null);
        setIsDraggingOver(null);
        return;
      }

      // Don't update if status is the same
      if (issue.status === targetColumn.statusFilter) {
        setActiveId(null);
        setIsDraggingOver(null);
        return;
      }

      setActiveId(null);
      setIsDraggingOver(null);

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
            onDragOver={handleDragOver}
            onDragEnd={handleDragEnd}
          >
            <div className="flex gap-4 h-full min-w-fit">
              {COLUMNS.map((column) => {
                const colIssues = columnsData.get(column.id) || [];
                return (
                  <div key={column.id} className="flex-1 min-w-[280px] max-w-[400px] flex flex-col">
                    {/* Column header */}
                    <div className={`px-3 py-2 rounded-t-lg border ${column.color} border-b-0`}>
                      <div className="flex items-center justify-between">
                        <span className="font-medium text-sm">{column.label}</span>
                        <span className="text-xs px-2 py-0.5 rounded-full bg-[var(--color-bg)]">
                          {colIssues.length}
                        </span>
                      </div>
                    </div>

                    {/* Column content - Droppable area */}
                    <SortableContext
                      items={colIssues.map((i) => i.id)}
                      strategy={verticalListSortingStrategy}
                    >
                      <KanbanColumnContent
                        columnId={column.id}
                        issues={colIssues}
                        isDraggingOver={isDraggingOver === column.id}
                        onTaskClick={handleTaskClick}
                      />
                    </SortableContext>
                  </div>
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
    </div>
  );
}

// ---------------------------------------------------------------------------
// KanbanColumnContent - Droppable column content with sortable items
// ---------------------------------------------------------------------------

import { useDroppable } from "@dnd-kit/core";
import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";

interface KanbanColumnContentProps {
  columnId: string;
  issues: Issue[];
  isDraggingOver: boolean;
  onTaskClick: (issue: Issue) => void;
}

function KanbanColumnContent({
  columnId,
  issues,
  isDraggingOver,
  onTaskClick,
}: KanbanColumnContentProps) {
  const { setNodeRef, isOver } = useDroppable({
    id: columnId,
  });

  const showDropIndicator = isOver || isDraggingOver;

  return (
    <div
      ref={setNodeRef}
      className={`relative flex-1 border border-[var(--color-border)] border-t-0 rounded-b-lg p-3 space-y-3 min-h-[200px] transition-all duration-300 ease-out ${
        showDropIndicator
          ? "bg-[var(--color-primary)]/10 border-[var(--color-primary)]/50 ring-2 ring-[var(--color-primary)]/20"
          : "bg-[var(--color-surface)]/50"
      }`}
    >
      {/* Drop zone indicator */}
      {showDropIndicator && (
        <div className="absolute inset-x-3 -top-1 h-1 bg-gradient-to-r from-transparent via-[var(--color-primary)] to-transparent rounded-full drop-indicator" />
      )}

      {issues.length === 0 ? (
        <div
          className={`flex flex-col items-center justify-center h-24 text-[var(--color-text-secondary)] text-xs transition-all duration-200 ${showDropIndicator ? "opacity-70 scale-105" : "opacity-100"}`}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            className={`h-8 w-8 mb-2 transition-all duration-300 ${showDropIndicator ? "text-[var(--color-primary)] scale-110" : ""}`}
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={1.5}
              d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
            />
          </svg>
          {showDropIndicator ? "Drop here" : "No tasks"}
        </div>
      ) : (
        <div className="space-y-3">
          {issues.map((issue, index) => (
            <div
              key={issue.id}
              className="animate-filter-enter gpu-accelerated"
              style={{ animationDelay: `${index * 30}ms` }}
            >
              <SortableTaskCard issue={issue} onClick={onTaskClick} />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// SortableTaskCard - Individual sortable task card
// ---------------------------------------------------------------------------

interface SortableTaskCardProps {
  issue: Issue;
  onClick: (issue: Issue) => void;
}

function SortableTaskCard({ issue, onClick }: SortableTaskCardProps) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: issue.id,
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition: transition || "transform 200ms cubic-bezier(0.2, 0, 0, 1)",
  };

  const handleClick = () => {
    onClick(issue);
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      data-id={issue.id}
      {...attributes}
      {...listeners}
      onClick={handleClick}
      className={`p-3 rounded-lg bg-[var(--color-bg)] border border-[var(--color-border)] 
        hover:border-[var(--color-primary)]/50 hover:shadow-md hover:bg-[var(--color-surface)] 
        hover:-translate-y-0.5 hover:scale-[1.02]
        active:scale-[0.98]
        transition-all duration-200 ease-out cursor-grab active:cursor-grabbing gpu-accelerated
        ${isDragging ? "ring-2 ring-[var(--color-primary)]/30 shadow-xl opacity-90 rotate-2 scale-105 z-50" : ""}
      `}
    >
      {/* Title */}
      <h3 className="text-sm font-medium text-[var(--color-text)] mb-2 line-clamp-2">
        {issue.title}
      </h3>

      {/* Meta info */}
      <div className="flex items-center justify-between">
        {/* Priority badge */}
        <span
          className={`inline-block px-2 py-0.5 rounded text-[10px] font-medium ${priorityColor(issue.priority)}`}
        >
          {priorityLabel(issue.priority)}
        </span>

        {/* Assignee */}
        <span className="text-xs text-[var(--color-text-secondary)] truncate max-w-[120px]">
          {issue.assignee ?? issue.owner ?? "Unassigned"}
        </span>
      </div>

      {/* ID */}
      <div className="mt-2 text-[10px] font-mono text-[var(--color-text-secondary)]">
        {issue.id}
      </div>
    </div>
  );
}
