import { useDashboardStore } from "../stores/dashboard";

const STEP_LABELS = [
  "Initializing...",
  "Discovering workspaces",
  "Selecting workspace",
  "Checking daemon",
  "Loading cache",
  "Loading issues",
  "Loading epics",
  "Probing opencode",
];

export function BootSplash() {
  const bootState = useDashboardStore((s) => s.bootState);
  const pct = Math.round((bootState.step / bootState.totalSteps) * 100);

  return (
    <div className="flex items-center justify-center h-screen bg-[var(--color-bg)]">
      <div className="w-80 text-center">
        <h1 className="text-3xl font-bold mb-6 text-[var(--color-text)]">
          AgentMaestro
        </h1>

        {/* Progress bar */}
        <div className="w-full h-2 bg-[var(--color-border)] rounded-full overflow-hidden mb-4">
          <div
            className="h-full bg-[var(--color-primary)] transition-all duration-300 ease-out rounded-full"
            style={{ width: `${pct}%` }}
          />
        </div>

        {/* Step label */}
        <p className="text-sm text-[var(--color-text-secondary)] mb-1">
          {bootState.currentLabel}
        </p>
        <p className="text-xs text-[var(--color-text-secondary)]">
          Step {bootState.step} / {bootState.totalSteps}
        </p>

        {/* Error */}
        {bootState.error && (
          <div className="mt-4 p-3 bg-[var(--color-error)]/10 border border-[var(--color-error)]/30 rounded-md">
            <p className="text-sm text-[var(--color-error)]">
              {bootState.error}
            </p>
          </div>
        )}

        {/* Steplist */}
        <div className="mt-6 text-left text-xs space-y-1">
          {STEP_LABELS.slice(1).map((label, idx) => {
            const stepNum = idx + 1;
            const isDone = bootState.step > stepNum;
            const isCurrent = bootState.step === stepNum;
            return (
              <div
                key={stepNum}
                className={`flex items-center gap-2 ${
                  isDone
                    ? "text-[var(--color-success)]"
                    : isCurrent
                      ? "text-[var(--color-primary)]"
                      : "text-[var(--color-text-secondary)]/50"
                }`}
              >
                <span className="w-4 text-center">
                  {isDone ? "\u2713" : isCurrent ? "\u25CF" : "\u25CB"}
                </span>
                <span>{label}</span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
