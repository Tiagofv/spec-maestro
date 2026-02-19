import { useMemo } from "react";
import { useDashboardStore } from "../../stores/dashboard";

// ---------------------------------------------------------------------------
// AssigneeSelector
// ---------------------------------------------------------------------------

export interface AssigneeSelectorProps {
  value: string | null;
  onChange: (assignee: string | null) => void;
  placeholder?: string;
  disabled?: boolean;
  className?: string;
  id?: string;
  "aria-label"?: string;
}

export function AssigneeSelector({
  value,
  onChange,
  placeholder = "Select assignee...",
  disabled = false,
  className = "",
  id,
  "aria-label": ariaLabel,
}: AssigneeSelectorProps) {
  const issues = useDashboardStore((s) => s.issues);

  // Extract unique assignees from issues
  const availableAssignees = useMemo(() => {
    const assigneeSet = new Set<string>();

    for (const issue of issues) {
      if (issue.assignee) {
        assigneeSet.add(issue.assignee);
      }
      if (issue.owner) {
        assigneeSet.add(issue.owner);
      }
    }

    return Array.from(assigneeSet).sort();
  }, [issues]);

  const handleChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    const newValue = e.target.value;
    onChange(newValue === "" ? null : newValue);
  };

  return (
    <select
      id={id}
      value={value ?? ""}
      onChange={handleChange}
      disabled={disabled}
      aria-label={ariaLabel ?? placeholder}
      className={`
        bg-[var(--color-surface)]
        text-[var(--color-text)]
        text-sm
        border
        border-[var(--color-border)]
        rounded-md
        px-3
        py-1.5
        focus:outline-none
        focus:ring-1
        focus:ring-[var(--color-primary)]
        focus:border-[var(--color-primary)]
        disabled:opacity-50
        disabled:cursor-not-allowed
        cursor-pointer
        min-w-[120px]
        max-w-full
        truncate
        ${className}
      `}
    >
      <option value="">{placeholder}</option>
      {availableAssignees.map((assignee) => (
        <option key={assignee} value={assignee}>
          {assignee}
        </option>
      ))}
    </select>
  );
}

// ---------------------------------------------------------------------------
// InlineAssigneeSelector - Compact version for inline use in TaskCard
// ---------------------------------------------------------------------------

export interface InlineAssigneeSelectorProps {
  value: string | null;
  onChange: (assignee: string | null) => void;
  disabled?: boolean;
  className?: string;
}

export function InlineAssigneeSelector({
  value,
  onChange,
  disabled = false,
  className = "",
}: InlineAssigneeSelectorProps) {
  return (
    <AssigneeSelector
      value={value}
      onChange={onChange}
      placeholder="Unassigned"
      disabled={disabled}
      className={`text-xs py-0.5 px-2 ${className}`}
      aria-label="Change assignee"
    />
  );
}
