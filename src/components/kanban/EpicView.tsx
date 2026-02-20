import { useMemo } from "react";
import type { DragEndEvent } from "@dnd-kit/core";
import type { EpicStatus, Issue } from "../../types";
import { EpicSwimlane } from "./EpicSwimlane";

interface EpicGroup {
  id: string;
  epic: EpicStatus;
  issues: Issue[];
}

export interface EpicViewProps {
  issues: Issue[];
  epics: EpicStatus[];
  collapseState: Record<string, boolean>;
  onToggleCollapse: (epicId: string) => void;
  onCollapseAll: () => void;
  onExpandAll: () => void;
  onDragEnd?: (event: DragEndEvent) => void;
  onTaskClick?: (issue: Issue) => void;
}

function getIssueEpicId(issue: Issue): string | undefined {
  const epicId = issue.epic_id;
  if (typeof epicId === "string" && epicId.length > 0) {
    return epicId;
  }
  return undefined;
}

export function EpicView({
  issues,
  epics,
  collapseState,
  onToggleCollapse,
  onCollapseAll,
  onExpandAll,
  onDragEnd,
  onTaskClick,
}: EpicViewProps) {
  const groups = useMemo(() => {
    const byId = new Map<string, EpicGroup>();

    for (const epic of epics) {
      byId.set(epic.id, {
        id: epic.id,
        epic,
        issues: [],
      });
    }

    const noEpicIssues: Issue[] = [];
    for (const issue of issues) {
      const epicId = getIssueEpicId(issue);
      if (epicId && byId.has(epicId)) {
        byId.get(epicId)?.issues.push(issue);
      } else {
        noEpicIssues.push(issue);
      }
    }

    const ordered = Array.from(byId.values()).sort((a, b) => a.epic.title.localeCompare(b.epic.title));

    if (noEpicIssues.length > 0) {
      ordered.push({
        id: "no-epic",
        epic: {
          id: "no-epic",
          title: "No Epic",
          total: noEpicIssues.length,
          open: noEpicIssues.filter((issue) => issue.status === "open").length,
          in_progress: noEpicIssues.filter((issue) => issue.status === "in_progress").length,
          blocked: noEpicIssues.filter((issue) => issue.status === "blocked").length,
          closed: noEpicIssues.filter((issue) => issue.status === "closed").length,
        },
        issues: noEpicIssues,
      });
    }

    return ordered;
  }, [epics, issues]);

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-end gap-2">
        <button
          type="button"
          onClick={onCollapseAll}
          className="text-xs px-2 py-1 border border-[var(--color-border)] rounded hover:border-[var(--color-primary)]"
          data-testid="epic-collapse-all"
        >
          Collapse All
        </button>
        <button
          type="button"
          onClick={onExpandAll}
          className="text-xs px-2 py-1 border border-[var(--color-border)] rounded hover:border-[var(--color-primary)]"
          data-testid="epic-expand-all"
        >
          Expand All
        </button>
      </div>

      {groups.length === 0 ? (
        <div className="flex items-center justify-center h-36 text-[var(--color-text-secondary)] text-sm">
          No epics found
        </div>
      ) : (
        groups.map((group) => (
          <EpicSwimlane
            key={group.id}
            epic={group.epic}
            issues={group.issues}
            isCollapsed={Boolean(collapseState[group.id])}
            onToggleCollapse={() => onToggleCollapse(group.id)}
            onDragEnd={onDragEnd}
            onTaskClick={onTaskClick}
          />
        ))
      )}
    </div>
  );
}
