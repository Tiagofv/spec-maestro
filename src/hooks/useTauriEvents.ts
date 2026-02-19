import { useEffect, useRef } from "react";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import type { DashboardEvent } from "../types";
import { useDashboardStore } from "../stores/dashboard";

/**
 * Subscribes to Tauri events emitted by the Rust backend.
 *
 * The Rust side emits DashboardEvent via `app_handle.emit("dashboard-event", &event)`.
 * This hook listens on that event name and dispatches each payload to the
 * Zustand store's handleEvent.
 */
export function useTauriEvents(): void {
  const handleDashboardEvent = useDashboardStore((s) => s.handleEvent);
  const unlistenRef = useRef<UnlistenFn | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function subscribe() {
      const unlisten = await listen<DashboardEvent>("dashboard-event", (event) => {
        if (!cancelled) {
          handleDashboardEvent(event.payload);
        }
      });
      if (cancelled) {
        unlisten();
      } else {
        unlistenRef.current = unlisten;
      }
    }

    subscribe();

    return () => {
      cancelled = true;
      unlistenRef.current?.();
    };
  }, [handleDashboardEvent]);
}
