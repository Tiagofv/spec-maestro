import { useMemo } from "react";
import type { DragEndEvent } from "@dnd-kit/core";
import type { EpicStatus, Issue } from "../../types";
import { KanbanColumn } from "./KanbanColumn";
import { EpicProgress } from "./EpicProgress";

const COLUMNS = [
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

export interface EpicSwimlaneProps {
  epic: EpicStatus;
  issues: Issue[];
  isCollapsed: boolean;
  onToggleCollapse: () => void;
  onDragEnd?: (event: DragEndEvent) => void;
  onTaskClick?: (issue: Issue) => void;
}

export function EpicSwimlane({
  epic,
  issues,
  isCollapsed,
  onToggleCollapse,
  onTaskClick,
}: EpicSwimlaneProps) {
  const grouped = useMemo(() => {
    const map: Record<string, Issue[]> = {
      open: [],
      in_progress: [],
      blocked: [],
      closed: [],
    };
    for (const issue of issues) {
      if (map[issue.status]) {
        map[issue.status].push(issue);
      }
    }
    return map;
  }, [issues]);

  return (
    <section className="rounded-lg border border-[var(--color-border)] bg-[var(--color-bg)] p-3" data-testid={`epic-swimlane-${epic.id}`}>
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <h3 className="text-sm font-semibold truncate">{epic.title}</h3>
          <EpicProgress
            total={epic.total}
            open={epic.open}
            inProgress={epic.in_progress}
            blocked={epic.blocked}
            closed={epic.closed}
          />
        </div>
        <button
          type="button"
          onClick={onToggleCollapse}
          className="text-xs px-2 py-1 border border-[var(--color-border)] rounded hover:border-[var(--color-primary)]"
          data-testid={`epic-toggle-${epic.id}`}
        >
          {isCollapsed ? "Expand" : "Collapse"}
        </button>
      </div>

      {!isCollapsed && (
        <div className="mt-3 flex gap-3 overflow-x-auto pb-1">
          {COLUMNS.map((column) => (
            <KanbanColumn
              key={`${epic.id}-${column.id}`}
              id={`${epic.id}:${column.id}`}
              label={column.label}
              color={column.color}
              issues={grouped[column.statusFilter] ?? []}
              onTaskClick={onTaskClick}
            />
          ))}
        </div>
      )}
    </section>
  );
}
