export interface EpicProgressProps {
  total: number;
  open: number;
  inProgress: number;
  blocked: number;
  closed: number;
}

export function EpicProgress({ total, open, inProgress, blocked, closed }: EpicProgressProps) {
  return (
    <div className="flex items-center gap-2 text-xs text-[var(--color-text-secondary)]" data-testid="epic-progress">
      <span>{total} total</span>
      <span>{open} open</span>
      <span>{inProgress} in progress</span>
      <span>{blocked} blocked</span>
      <span>{closed} closed</span>
    </div>
  );
}
