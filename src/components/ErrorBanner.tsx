import { useCallback, useEffect, useState } from "react";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type ErrorSeverity = "error" | "warning";

export interface BannerError {
  id: string;
  message: string;
  severity: ErrorSeverity;
  retryFn?: () => void;
}

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

interface ErrorBannerProps {
  errors: BannerError[];
  onDismiss: (id: string) => void;
}

// ---------------------------------------------------------------------------
// Individual banner item
// ---------------------------------------------------------------------------

function BannerItem({
  error,
  onDismiss,
}: {
  error: BannerError;
  onDismiss: (id: string) => void;
}) {
  const isWarning = error.severity === "warning";

  // Auto-dismiss warnings after 10 seconds
  useEffect(() => {
    if (!isWarning) return;
    const timer = setTimeout(() => onDismiss(error.id), 10_000);
    return () => clearTimeout(timer);
  }, [isWarning, error.id, onDismiss]);

  return (
    <div
      role="alert"
      className="flex items-center gap-3 px-4 py-2 text-sm"
      style={{
        backgroundColor: isWarning
          ? "var(--color-warning-bg, #4a3800)"
          : "var(--color-error-bg, #4a0000)",
        color: isWarning
          ? "var(--color-warning-text, #ffd666)"
          : "var(--color-error-text, #ff8080)",
        borderBottom: "1px solid var(--color-border)",
      }}
    >
      {/* Icon */}
      <span className="shrink-0 text-base">
        {isWarning ? "\u26A0" : "\u26D4"}
      </span>

      {/* Message */}
      <span className="flex-1 truncate">{error.message}</span>

      {/* Retry button */}
      {error.retryFn && (
        <button
          onClick={error.retryFn}
          className="shrink-0 px-2 py-0.5 rounded text-xs font-medium hover:opacity-80 transition-opacity"
          style={{
            backgroundColor: isWarning
              ? "var(--color-warning-text, #ffd666)"
              : "var(--color-error-text, #ff8080)",
            color: isWarning
              ? "var(--color-warning-bg, #4a3800)"
              : "var(--color-error-bg, #4a0000)",
          }}
        >
          Retry
        </button>
      )}

      {/* Dismiss button */}
      <button
        onClick={() => onDismiss(error.id)}
        className="shrink-0 w-5 h-5 flex items-center justify-center rounded hover:opacity-80 transition-opacity text-current"
        aria-label="Dismiss"
      >
        {"\u2715"}
      </button>
    </div>
  );
}

// ---------------------------------------------------------------------------
// ErrorBanner — stacks multiple errors at the top of the app
// ---------------------------------------------------------------------------

export function ErrorBanner({ errors, onDismiss }: ErrorBannerProps) {
  if (errors.length === 0) return null;

  return (
    <div className="shrink-0">
      {errors.map((error) => (
        <BannerItem key={error.id} error={error} onDismiss={onDismiss} />
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Hook — manages error state for the ErrorBanner
// ---------------------------------------------------------------------------

let nextId = 0;

export function useErrorBanner() {
  const [errors, setErrors] = useState<BannerError[]>([]);

  const addError = useCallback(
    (
      message: string,
      severity: ErrorSeverity = "error",
      retryFn?: () => void,
    ) => {
      const id = `err-${++nextId}`;
      setErrors((prev) => [...prev, { id, message, severity, retryFn }]);
      return id;
    },
    [],
  );

  const dismissError = useCallback((id: string) => {
    setErrors((prev) => prev.filter((e) => e.id !== id));
  }, []);

  const clearAll = useCallback(() => {
    setErrors([]);
  }, []);

  return { errors, addError, dismissError, clearAll };
}
