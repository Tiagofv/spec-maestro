import { useDashboardStore } from "../../stores/dashboard";

// ---------------------------------------------------------------------------
// BoardFilters
// ---------------------------------------------------------------------------

export interface BoardFiltersProps {
  assignees?: string[];
}

export function BoardFilters({ assignees = [] }: BoardFiltersProps) {
  const kanbanFilters = useDashboardStore((s) => s.kanbanFilters);
  const showCompleted = useDashboardStore((s) => s.showCompleted);
  const updateKanbanFilters = useDashboardStore((s) => s.updateKanbanFilters);
  const clearKanbanFilters = useDashboardStore((s) => s.clearKanbanFilters);
  const setShowCompleted = useDashboardStore((s) => s.setShowCompleted);

  const handleAssigneeChange = (assignee: string) => {
    const currentAssignees = kanbanFilters.assignee || [];
    if (currentAssignees.includes(assignee)) {
      updateKanbanFilters({
        assignee: currentAssignees.filter((a) => a !== assignee),
      });
    } else {
      updateKanbanFilters({
        assignee: [...currentAssignees, assignee],
      });
    }
  };

  const handleSearchChange = (search: string) => {
    updateKanbanFilters({ search });
  };

  const handleShowCompletedChange = (show: boolean) => {
    setShowCompleted(show);
  };

  const hasActiveFilters =
    (kanbanFilters.assignee && kanbanFilters.assignee.length > 0) ||
    (kanbanFilters.search && kanbanFilters.search.length > 0);

  return (
    <div className="flex items-center gap-4 p-4 border-b border-[var(--color-border)]">
      {/* Search input */}
      <div className="flex-1 max-w-md">
        <input
          type="text"
          placeholder="Search tasks..."
          value={kanbanFilters.search || ""}
          onChange={(e) => handleSearchChange(e.target.value)}
          className="w-full px-3 py-1.5 text-sm bg-[var(--color-surface)] border border-[var(--color-border)] rounded-md text-[var(--color-text)] placeholder:text-[var(--color-text-secondary)] focus:outline-none focus:border-[var(--color-primary)]"
          data-testid="search-input"
        />
      </div>

      {/* Assignee filters */}
      {assignees.length > 0 && (
        <div className="flex items-center gap-2">
          <span className="text-sm text-[var(--color-text-secondary)]">Assignee:</span>
          <div className="flex gap-1">
            {assignees.map((assignee) => (
              <button
                key={assignee}
                onClick={() => handleAssigneeChange(assignee)}
                className={`px-2 py-1 text-xs rounded-md border transition-colors ${
                  kanbanFilters.assignee?.includes(assignee)
                    ? "bg-[var(--color-primary)] text-white border-[var(--color-primary)]"
                    : "bg-[var(--color-surface)] text-[var(--color-text)] border-[var(--color-border)] hover:border-[var(--color-primary)]"
                }`}
                data-testid={`assignee-filter-${assignee}`}
              >
                {assignee}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Show completed toggle */}
      <label className="flex items-center gap-2 cursor-pointer">
        <input
          type="checkbox"
          checked={showCompleted}
          onChange={(e) => handleShowCompletedChange(e.target.checked)}
          className="w-4 h-4 rounded border-[var(--color-border)] text-[var(--color-primary)] focus:ring-[var(--color-primary)]"
          data-testid="show-completed-checkbox"
        />
        <span className="text-sm text-[var(--color-text-secondary)]">Show completed</span>
      </label>

      {/* Clear filters */}
      {hasActiveFilters && (
        <button
          onClick={clearKanbanFilters}
          className="text-xs px-2 py-1 text-[var(--color-text-secondary)] hover:text-[var(--color-text)] underline"
          data-testid="clear-filters-button"
        >
          Clear filters
        </button>
      )}
    </div>
  );
}
