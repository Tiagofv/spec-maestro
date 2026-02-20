import { useDndContext, useDroppable } from "@dnd-kit/core";
import type { Issue } from "../../types";
import { SortableTaskCard } from "./TaskCard";

// ---------------------------------------------------------------------------
// KanbanColumn
// ---------------------------------------------------------------------------

export interface KanbanColumnProps {
  id: string;
  label: string;
  color: string;
  issues: Issue[];
  onTaskClick?: (issue: Issue) => void;
}

export function KanbanColumn({ id, label, color, issues, onTaskClick }: KanbanColumnProps) {
  const { isOver, setNodeRef } = useDroppable({
    id: id,
  });
  const { active } = useDndContext();

  const targetEpicId = id.includes(":") ? id.split(":")[0] : null;
  const activeEpicId = active
    ? document.querySelector(`[data-id="${String(active.id)}"]`)?.getAttribute("data-epic-id")
    : null;
  const invalidDrop = Boolean(isOver && targetEpicId && activeEpicId && targetEpicId !== activeEpicId);

  return (
    <div
      role="region"
      aria-label={`${label} column, ${issues.length} task${issues.length !== 1 ? "s" : ""}`}
      className={`flex-1 min-w-[280px] max-w-[400px] flex flex-col transition-all duration-300 ease-out ${isOver ? "scale-[1.01]" : ""}`}
    >
      {/* Column header */}
      <div
        className={`px-3 py-2 rounded-t-lg border ${color} border-b-0 transition-all duration-200 ${isOver ? "ring-2 ring-[var(--color-primary)]/30 ring-offset-1" : ""}`}
      >
        <div className="flex items-center justify-between">
          <span className="font-medium text-sm">{label}</span>
          <span
            aria-label={`${issues.length} task${issues.length !== 1 ? "s" : ""}`}
            className={`text-xs px-2 py-0.5 rounded-full bg-[var(--color-bg)] transition-transform duration-200 ${isOver ? "scale-110" : ""}`}
          >
            {issues.length}
          </span>
        </div>
      </div>

      {/* Column content */}
      <div
        ref={setNodeRef}
        aria-live="polite"
        aria-atomic="false"
        aria-relevant="additions removals"
        className={`flex-1 border border-[var(--color-border)] border-t-0 rounded-b-lg p-3 space-y-3 min-h-[200px] transition-all duration-200 ease-out relative ${
          invalidDrop
            ? "bg-red-500/10 border-red-500/50"
            : isOver
              ? "bg-[var(--color-primary)]/10 border-[var(--color-primary)]/50 column-active"
              : "bg-[var(--color-surface)]/50"
        }`}
      >
        {/* Drop indicator line */}
        {isOver && (
          <div className="absolute inset-x-3 top-0 h-0.5 bg-gradient-to-r from-transparent via-[var(--color-primary)] to-transparent drop-indicator" />
        )}

        {issues.length === 0 ? (
          <div
            className={`flex items-center justify-center h-24 text-[var(--color-text-secondary)] text-xs transition-opacity duration-200 ${isOver ? "opacity-50" : "opacity-100"}`}
          >
            {isOver ? "Drop here" : "No tasks"}
          </div>
        ) : (
          issues.map((issue, index) => (
            <div
              key={issue.id}
              className="animate-filter-enter gpu-accelerated"
              style={{ animationDelay: `${index * 30}ms` }}
            >
              <SortableTaskCard issue={issue} onClick={onTaskClick} />
            </div>
          ))
        )}
      </div>
    </div>
  );
}
