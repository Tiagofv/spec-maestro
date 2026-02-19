import { useCallback } from "react";
import { useDashboardStore } from "../stores/dashboard";

/**
 * Dropdown in the header bar showing the active workspace.
 * Switching triggers a backend workspace switch + data re-fetch.
 */
export function WorkspaceSelector() {
  const workspaces = useDashboardStore((s) => s.workspaces);
  const selected = useDashboardStore((s) => s.selectedWorkspace);
  const selectWorkspace = useDashboardStore((s) => s.selectWorkspace);

  const handleChange = useCallback(
    async (e: React.ChangeEvent<HTMLSelectElement>) => {
      const ws = workspaces.find((w) => w.path === e.target.value);
      if (ws) {
        await selectWorkspace(ws);
      }
    },
    [workspaces, selectWorkspace],
  );

  if (workspaces.length === 0) {
    return <span className="text-sm text-[var(--color-text-secondary)]">No workspaces</span>;
  }

  return (
    <div className="flex items-center gap-2">
      <select
        value={selected?.path ?? ""}
        onChange={handleChange}
        className="bg-[var(--color-surface)] text-[var(--color-text)] text-sm border border-[var(--color-border)] rounded-md px-3 py-1.5 focus:outline-none focus:ring-1 focus:ring-[var(--color-primary)] cursor-pointer"
      >
        {workspaces.map((ws) => (
          <option key={ws.path} value={ws.path}>
            {ws.name}
            {(ws.issue_count ?? 0) > 0 ? ` (${ws.issue_count})` : ""}
            {ws.daemon_running ? "" : " [offline]"}
          </option>
        ))}
      </select>
      {selected?.daemon_running ? (
        <span
          className="inline-block w-2 h-2 rounded-full bg-[var(--color-success)]"
          title="Daemon running"
        />
      ) : (
        <span
          className="inline-block w-2 h-2 rounded-full bg-[var(--color-text-secondary)]"
          title="Daemon offline"
        />
      )}
    </div>
  );
}
