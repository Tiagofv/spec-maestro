import { useEffect, useRef } from "react";
import { useDashboardStore } from "../stores/dashboard";
import * as tauri from "../lib/tauri";
import type { Workspace } from "../types";

/**
 * 5-step startup orchestration.
 *
 * Steps:
 *  1. Discover workspaces
 *  2. Count issues per workspace (switch + list for each)
 *  3. Select best workspace (first alphabetically with open issues > 0)
 *  4. Fetch issues for selected workspace
 *  5. Probe daemon + opencode connectivity
 *
 * Non-critical steps degrade gracefully — the app still boots.
 */
export function useBootSequence(): void {
  const ran = useRef(false);

  const setBootStep = useDashboardStore((s) => s.setBootStep);
  const setBootCompleted = useDashboardStore((s) => s.setBootCompleted);
  const setBootError = useDashboardStore((s) => s.setBootError);
  const fetchWorkspaces = useDashboardStore((s) => s.fetchWorkspaces);
  const setSelectedWorkspace = useDashboardStore((s) => s.setSelectedWorkspace);
  const setWorkspaces = useDashboardStore((s) => s.setWorkspaces);
  const fetchIssues = useDashboardStore((s) => s.fetchIssues);
  const setDaemonStatus = useDashboardStore((s) => s.setDaemonStatus);
  const setOpencodeConnected = useDashboardStore((s) => s.setOpencodeConnected);

  useEffect(() => {
    // StrictMode double-invocation guard
    if (ran.current) return;
    ran.current = true;

    async function boot() {
      try {
        // Step 1: Discover workspaces
        setBootStep(1, "Discovering workspaces...");
        const rawWorkspaces = await fetchWorkspaces();
        if (rawWorkspaces.length === 0) {
          setBootError("No workspaces found. Run `bd init` in a project.");
          return;
        }

        // Step 2: Count issues per workspace
        setBootStep(2, "Counting issues...");
        const enriched: Workspace[] = [];
        for (const ws of rawWorkspaces) {
          let issueCount = 0;
          try {
            await tauri.switchWorkspace(ws.path);
            const issues = await tauri.listIssues();
            issueCount = issues.filter((i) => i.status !== "closed" && i.status !== "done").length;
          } catch {
            // Can't reach this workspace — count stays 0
          }
          enriched.push({ ...ws, issue_count: issueCount });
        }

        // Sort alphabetically by name
        enriched.sort((a, b) => a.name.localeCompare(b.name));
        setWorkspaces(enriched);

        // Step 3: Select best workspace
        setBootStep(3, "Selecting workspace...");
        const best = enriched.find((w) => (w.issue_count ?? 0) > 0) ?? enriched[0];

        // Switch backend to the selected workspace
        try {
          await tauri.switchWorkspace(best.path);
        } catch {
          // Fall through — we'll try to fetch issues anyway
        }
        setSelectedWorkspace(best);

        // Step 4: Fetch issues for selected workspace
        setBootStep(4, "Loading issues...");
        await fetchIssues();

        // Step 5: Probe daemon + opencode (non-critical)
        setBootStep(5, "Checking services...");
        try {
          const health = await tauri.getBdHealth();
          setDaemonStatus({
            running: health,
            pid: null,
            uptime_seconds: null,
            port: null,
          });
        } catch {
          setDaemonStatus({
            running: false,
            pid: null,
            uptime_seconds: null,
            port: null,
          });
        }

        try {
          const ocStatus = await tauri.opencodeStatus();
          setOpencodeConnected(ocStatus.connected);
        } catch {
          setOpencodeConnected(false);
        }

        // Done
        setBootCompleted();
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        setBootError(message);
      }
    }

    boot();
    // Stable references — intentionally run once
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
}
