import { useMemo, useState } from "react";
import type { EpicStatus } from "../../types";

export interface EpicFilterProps {
  epics: EpicStatus[];
  selectedEpics: string[];
  showClosed: boolean;
  onEpicSelect: (epicId: string) => void;
  onShowClosedChange: (show: boolean) => void;
}

export function EpicFilter({
  epics,
  selectedEpics,
  showClosed,
  onEpicSelect,
  onShowClosedChange,
}: EpicFilterProps) {
  const [query, setQuery] = useState("");

  const visibleEpics = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return epics;
    return epics.filter(
      (epic) => epic.title.toLowerCase().includes(q) || epic.id.toLowerCase().includes(q),
    );
  }, [epics, query]);

  return (
    <div className="flex items-center gap-2" data-testid="epic-filter">
      <span className="text-sm text-[var(--color-text-secondary)]">Epic:</span>
      <input
        type="text"
        placeholder="Search epics..."
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        className="w-44 px-2 py-1 text-xs bg-[var(--color-surface)] border border-[var(--color-border)] rounded-md text-[var(--color-text)] placeholder:text-[var(--color-text-secondary)] focus:outline-none focus:border-[var(--color-primary)]"
        data-testid="epic-filter-search"
      />
      <div className="max-h-28 overflow-y-auto border border-[var(--color-border)] rounded-md bg-[var(--color-surface)] p-2 min-w-[220px]">
        {visibleEpics.length === 0 ? (
          <div className="text-xs text-[var(--color-text-secondary)]">No matching epics</div>
        ) : (
          visibleEpics.map((epic) => {
            const checked = selectedEpics.includes(epic.id);
            return (
              <label key={epic.id} className="flex items-center gap-2 py-0.5 text-xs cursor-pointer">
                <input
                  type="checkbox"
                  checked={checked}
                  onChange={() => onEpicSelect(epic.id)}
                  data-testid={`epic-option-${epic.id}`}
                />
                <span className="truncate">{epic.title}</span>
              </label>
            );
          })
        )}
      </div>
      <label className="flex items-center gap-1 text-xs text-[var(--color-text-secondary)] cursor-pointer">
        <input
          type="checkbox"
          checked={showClosed}
          onChange={(e) => onShowClosedChange(e.target.checked)}
          data-testid="show-closed-epics-checkbox"
        />
        Show closed epics
      </label>
    </div>
  );
}
