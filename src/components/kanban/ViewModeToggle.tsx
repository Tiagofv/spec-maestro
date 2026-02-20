export interface ViewModeToggleProps {
  viewMode: "status" | "epic";
  onChange: (mode: "status" | "epic") => void;
}

export function ViewModeToggle({ viewMode, onChange }: ViewModeToggleProps) {
  return (
    <div className="inline-flex items-center rounded-md border border-[var(--color-border)] bg-[var(--color-surface)] p-1">
      <button
        type="button"
        onClick={() => onChange("status")}
        className={`px-3 py-1 text-sm rounded transition-colors ${
          viewMode === "status"
            ? "bg-[var(--color-primary)] text-white"
            : "text-[var(--color-text-secondary)] hover:text-[var(--color-text)]"
        }`}
        data-testid="view-mode-status"
      >
        By Status
      </button>
      <button
        type="button"
        onClick={() => onChange("epic")}
        className={`px-3 py-1 text-sm rounded transition-colors ${
          viewMode === "epic"
            ? "bg-[var(--color-primary)] text-white"
            : "text-[var(--color-text-secondary)] hover:text-[var(--color-text)]"
        }`}
        data-testid="view-mode-epic"
      >
        By Epic
      </button>
    </div>
  );
}
