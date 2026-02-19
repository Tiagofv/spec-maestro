import { useState, useMemo, useCallback } from "react";
import { useDashboardStore } from "../stores/dashboard";
import type { Issue, SortConfig, SortDirection } from "../types";

// ---------------------------------------------------------------------------
// Column definitions
// ---------------------------------------------------------------------------

interface Column {
  key: string;
  label: string;
  sortable: boolean;
  className?: string;
}

const COLUMNS: Column[] = [
  { key: "id", label: "ID", sortable: true, className: "w-40" },
  { key: "title", label: "Title", sortable: true },
  { key: "status", label: "Status", sortable: true, className: "w-28" },
  { key: "priority", label: "Pri", sortable: true, className: "w-20" },
  { key: "assignee", label: "Assignee", sortable: true, className: "w-28" },
];

// ---------------------------------------------------------------------------
// Sorting helpers
// ---------------------------------------------------------------------------

function getField(issue: Issue, key: string): string {
  if (key === "labels") return issue.labels.join(", ");
  if (key === "assignee") return issue.assignee ?? issue.owner ?? "";
  const val = issue[key];
  if (val == null) return "";
  return String(val);
}

function compareIssues(a: Issue, b: Issue, sort: SortConfig): number {
  const aVal = getField(a, sort.column);
  const bVal = getField(b, sort.column);
  const cmp = aVal.localeCompare(bVal, undefined, { numeric: true });
  return sort.direction === "asc" ? cmp : -cmp;
}

// ---------------------------------------------------------------------------
// Status badge colours
// ---------------------------------------------------------------------------

function statusColor(status: string): string {
  switch (status.toLowerCase()) {
    case "open":
      return "bg-blue-500/15 text-blue-400";
    case "in_progress":
      return "bg-amber-500/15 text-amber-400";
    case "closed":
      return "bg-[var(--color-success)]/15 text-[var(--color-success)]";
    default:
      return "bg-[var(--color-border)] text-[var(--color-text-secondary)]";
  }
}

function priorityLabel(p: number | string | null): string {
  if (p == null) return "-";
  const v = typeof p === "number" ? p : parseInt(p, 10);
  if (!Number.isNaN(v)) {
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
    }
  }
  return String(p);
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function IssueList() {
  const issues = useDashboardStore((s) => s.issues);
  const isLoading = useDashboardStore((s) => s.isLoading);
  const error = useDashboardStore((s) => s.error);
  const fetchIssues = useDashboardStore((s) => s.fetchIssues);

  const [sort, setSort] = useState<SortConfig>({
    column: "id",
    direction: "asc",
  });

  const [filter, setFilter] = useState<"all" | "open" | "in_progress" | "closed">("all");

  const handleSort = useCallback((column: string) => {
    setSort((prev) => {
      if (prev.column === column) {
        const direction: SortDirection = prev.direction === "asc" ? "desc" : "asc";
        return { column, direction };
      }
      return { column, direction: "asc" };
    });
  }, []);

  const filtered = useMemo(() => {
    if (filter === "all") return issues;
    return issues.filter((i) => i.status.toLowerCase() === filter);
  }, [issues, filter]);

  const sorted = useMemo(
    () => [...filtered].sort((a, b) => compareIssues(a, b, sort)),
    [filtered, sort],
  );

  // Counts for filter tabs
  const counts = useMemo(() => {
    const open = issues.filter(
      (i) => !["closed", "in_progress"].includes(i.status.toLowerCase()),
    ).length;
    const inProgress = issues.filter((i) => i.status.toLowerCase() === "in_progress").length;
    const closed = issues.filter((i) => i.status.toLowerCase() === "closed").length;
    return { all: issues.length, open, inProgress, closed };
  }, [issues]);

  // -----------------------------------------------------------------------
  // Render
  // -----------------------------------------------------------------------

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
        <h2 className="text-lg font-semibold text-[var(--color-text)]">Issues</h2>
        <button
          onClick={() => fetchIssues()}
          disabled={isLoading}
          className="text-xs px-3 py-1.5 rounded-md border border-[var(--color-border)] text-[var(--color-text-secondary)] hover:bg-[var(--color-border)]/50 disabled:opacity-50 transition-colors"
        >
          {isLoading ? "Loading..." : "Refresh"}
        </button>
      </div>

      {/* Filter tabs */}
      <div className="flex items-center gap-1 px-6 py-2 border-b border-[var(--color-border)]">
        {(
          [
            ["all", `All (${counts.all})`],
            ["open", `Open (${counts.open})`],
            ["in_progress", `In Progress (${counts.inProgress})`],
            ["closed", `Closed (${counts.closed})`],
          ] as const
        ).map(([key, label]) => (
          <button
            key={key}
            onClick={() => setFilter(key)}
            className={`px-3 py-1 text-xs rounded-md transition-colors ${
              filter === key
                ? "bg-[var(--color-primary)]/15 text-[var(--color-primary)] font-medium"
                : "text-[var(--color-text-secondary)] hover:text-[var(--color-text)] hover:bg-[var(--color-border)]/50"
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      {/* Error banner */}
      {error && (
        <div className="mx-6 mt-3 p-3 bg-[var(--color-error)]/10 border border-[var(--color-error)]/30 rounded-md text-sm text-[var(--color-error)]">
          {error}
        </div>
      )}

      {/* Table */}
      <div className="flex-1 overflow-auto px-6 pb-4">
        {isLoading && issues.length === 0 ? (
          <div className="mt-3 space-y-2">
            {Array.from({ length: 8 }).map((_, i) => (
              <div key={i} className="flex items-center gap-4 py-2.5">
                <div className="skeleton h-4 w-32" />
                <div className="skeleton h-4 flex-1" />
                <div className="skeleton h-4 w-20" />
                <div className="skeleton h-4 w-16" />
                <div className="skeleton h-4 w-24" />
              </div>
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex items-center justify-center h-full text-[var(--color-text-secondary)] text-sm">
            {issues.length === 0
              ? "No issues found"
              : `No ${filter === "all" ? "" : filter} issues`}
          </div>
        ) : (
          <table className="w-full text-sm mt-3">
            <thead>
              <tr className="text-left text-xs uppercase text-[var(--color-text-secondary)] border-b border-[var(--color-border)]">
                {COLUMNS.map((col) => (
                  <th
                    key={col.key}
                    className={`py-2 pr-3 font-medium ${col.className ?? ""} ${
                      col.sortable
                        ? "cursor-pointer select-none hover:text-[var(--color-text)]"
                        : ""
                    }`}
                    onClick={col.sortable ? () => handleSort(col.key) : undefined}
                  >
                    <span className="inline-flex items-center gap-1">
                      {col.label}
                      {col.sortable && sort.column === col.key && (
                        <span>{sort.direction === "asc" ? "\u25B2" : "\u25BC"}</span>
                      )}
                    </span>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {sorted.map((issue) => (
                <tr
                  key={issue.id}
                  className="border-b border-[var(--color-border)]/50 hover:bg-[var(--color-surface)] transition-colors"
                >
                  <td className="py-2.5 pr-3 font-mono text-xs text-[var(--color-primary)]">
                    {issue.id}
                  </td>
                  <td className="py-2.5 pr-3 text-[var(--color-text)]">
                    <div>
                      <span>{issue.title}</span>
                      {issue.labels.length > 0 && (
                        <span className="ml-2 inline-flex gap-1">
                          {issue.labels.map((label) => (
                            <span
                              key={label}
                              className="inline-block px-1.5 py-0.5 bg-[var(--color-border)] rounded text-[10px] text-[var(--color-text-secondary)]"
                            >
                              {label}
                            </span>
                          ))}
                        </span>
                      )}
                    </div>
                  </td>
                  <td className="py-2.5 pr-3">
                    <span
                      className={`inline-block px-2 py-0.5 rounded text-xs font-medium ${statusColor(issue.status)}`}
                    >
                      {issue.status}
                    </span>
                  </td>
                  <td className="py-2.5 pr-3 text-[var(--color-text-secondary)]">
                    {priorityLabel(issue.priority)}
                  </td>
                  <td className="py-2.5 pr-3 text-[var(--color-text-secondary)] truncate">
                    {issue.assignee ?? issue.owner ?? "-"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
