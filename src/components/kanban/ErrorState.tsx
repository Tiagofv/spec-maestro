// ---------------------------------------------------------------------------
// ErrorState — displayed when the beads service is unavailable
// ---------------------------------------------------------------------------

export interface ErrorStateProps {
  message?: string;
  onRetry?: () => void;
}

export function ErrorState({
  message = "The beads service is currently unavailable.",
  onRetry,
}: ErrorStateProps) {
  return (
    <div className="flex flex-col items-center justify-center h-full px-6 py-12 text-center">
      {/* Error icon */}
      <div className="w-14 h-14 rounded-full bg-[var(--color-error)]/10 flex items-center justify-center mb-4">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          className="h-7 w-7 text-[var(--color-error)]"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          aria-hidden="true"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={1.5}
            d="M12 9v2m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"
          />
        </svg>
      </div>

      {/* Heading */}
      <h3 className="text-base font-semibold text-[var(--color-text)] mb-2">Service Unavailable</h3>

      {/* Message */}
      <p className="text-sm text-[var(--color-text-secondary)] max-w-xs mb-6">{message}</p>

      {/* Retry button */}
      {onRetry && (
        <button
          type="button"
          onClick={onRetry}
          className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-[var(--color-error)]/10 border border-[var(--color-error)]/30 text-sm font-medium text-[var(--color-error)] hover:bg-[var(--color-error)]/20 transition-colors focus:outline-none focus:ring-2 focus:ring-[var(--color-error)] focus:ring-offset-2"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            className="h-4 w-4"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            aria-hidden="true"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
            />
          </svg>
          Retry
        </button>
      )}
    </div>
  );
}
