import { useCallback, useEffect, useRef, useState } from "react";
import type { HealthStatus } from "../types";
import * as tauri from "../lib/tauri";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Poll interval in milliseconds */
const POLL_INTERVAL_MS = 30_000;

// ---------------------------------------------------------------------------
// Status dot colors
// ---------------------------------------------------------------------------

type DotColor = "green" | "yellow" | "red";

function StatusDot({ color, label, tooltip }: { color: DotColor; label: string; tooltip: string }) {
  const colorClass =
    color === "green"
      ? "bg-[var(--color-success,#22c55e)]"
      : color === "yellow"
        ? "bg-[var(--color-warning,#eab308)]"
        : "bg-[var(--color-error,#ef4444)]";

  return (
    <div className="relative group flex items-center gap-1.5" title={tooltip}>
      <span className={`inline-block w-2 h-2 rounded-full ${colorClass}`} />
      <span className="text-xs text-[var(--color-text-secondary)]">{label}</span>
    </div>
  );
}

// ---------------------------------------------------------------------------
// ConnectionStatus
// ---------------------------------------------------------------------------

interface ConnectionStatusProps {
  onHealthError?: (message: string) => void;
}

export function ConnectionStatus({ onHealthError }: ConnectionStatusProps) {
  const [health, setHealth] = useState<HealthStatus | null>(null);
  const [checking, setChecking] = useState(false);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const checkHealth = useCallback(async () => {
    if (checking) return;
    setChecking(true);
    try {
      const status = await tauri.getHealthStatus();
      setHealth(status);
    } catch (err) {
      // Health endpoint not available — show degraded status
      const message = err instanceof Error ? err.message : String(err);
      onHealthError?.(message);
    } finally {
      setChecking(false);
    }
  }, [checking, onHealthError]);

  // Initial check + polling
  useEffect(() => {
    checkHealth();
    intervalRef.current = setInterval(checkHealth, POLL_INTERVAL_MS);
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
    // Run once on mount, poll on interval
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Derive statuses
  const bdColor: DotColor = health ? (health.bd_available ? "green" : "red") : "red";

  const bdTooltip = health
    ? health.bd_available
      ? `bd ${health.bd_version ?? "available"}${health.daemon_running ? " (daemon running)" : " (daemon stopped)"}`
      : "bd not found"
    : "Checking...";

  const ocColor: DotColor = health ? (health.opencode_available ? "green" : "red") : "red";

  const ocTooltip = health
    ? health.opencode_available
      ? `opencode connected${health.opencode_url ? ` (${health.opencode_url})` : ""}`
      : "opencode disconnected"
    : "Checking...";

  return (
    <div className="flex items-center gap-3">
      <StatusDot color={bdColor} label="bd" tooltip={bdTooltip} />
      <StatusDot color={ocColor} label="oc" tooltip={ocTooltip} />
    </div>
  );
}
