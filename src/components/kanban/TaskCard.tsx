import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import type { Issue } from "../../types";

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
// TaskCard
// ---------------------------------------------------------------------------

export interface TaskCardProps {
  issue: Issue;
  onClick?: (issue: Issue) => void;
  isDragging?: boolean;
}

export function TaskCard({ issue, onClick, isDragging: isDraggingProp }: TaskCardProps) {
  const handleClick = () => {
    onClick?.(issue);
  };

  const displayAssignee = issue.assignee ?? issue.owner ?? "Unassigned";

  return (
    <div
      onClick={handleClick}
      className={`
        p-3 rounded-lg bg-[var(--color-bg)] border border-[var(--color-border)]
        cursor-pointer
        transition-all duration-200 ease-out
        hover:border-[var(--color-primary)]/50 hover:shadow-md hover:bg-[var(--color-surface)]
        hover:-translate-y-0.5 hover:scale-[1.02]
        active:scale-[0.98]
        ${isDraggingProp ? "opacity-90 rotate-2 scale-105 shadow-xl ring-2 ring-[var(--color-primary)]/30" : ""}
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
          {displayAssignee}
        </span>
      </div>

      {/* ID */}
      <div className="mt-2 text-[10px] font-mono text-[var(--color-text-secondary)]">
        {issue.id}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// SortableTaskCard - Wrapper with drag-and-drop functionality
// ---------------------------------------------------------------------------

export interface SortableTaskCardProps {
  issue: Issue;
  onClick?: (issue: Issue) => void;
}

export function SortableTaskCard({ issue, onClick }: SortableTaskCardProps) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: issue.id,
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  };

  return (
    <div ref={setNodeRef} style={style} {...attributes} {...listeners}>
      <TaskCard issue={issue} onClick={onClick} isDragging={isDragging} />
    </div>
  );
}
