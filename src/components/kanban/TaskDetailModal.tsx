import { useEffect, useRef, useCallback, useState } from "react";
import type { Issue } from "../../types";
import { AssigneeSelector } from "./AssigneeSelector";
import * as tauri from "../../lib/tauri";

// ---------------------------------------------------------------------------
// Priority helpers (mirrored from TaskCard)
// ---------------------------------------------------------------------------

function getPriorityValue(priority: number | string | null): number {
  if (priority == null) return 999;
  const v = typeof priority === "number" ? priority : parseInt(priority, 10);
  if (Number.isNaN(v)) return 999;
  return v;
}

function priorityLabel(p: number | string | null): string {
  const v = getPriorityValue(p);
  if (v === 999) return "-";
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
    default:
      return String(v);
  }
}

function priorityColor(p: number | string | null): string {
  const v = getPriorityValue(p);
  switch (v) {
    case 1:
      return "bg-red-500 text-white";
    case 2:
      return "bg-orange-500 text-white";
    case 3:
      return "bg-yellow-500 text-black";
    case 4:
      return "bg-green-500 text-white";
    default:
      return "bg-[var(--color-border)] text-[var(--color-text-secondary)]";
  }
}

function priorityName(p: number | string | null): string {
  const v = getPriorityValue(p);
  switch (v) {
    case 1:
      return "Urgent";
    case 2:
      return "High";
    case 3:
      return "Normal";
    case 4:
      return "Low";
    default:
      return "None";
  }
}

// ---------------------------------------------------------------------------
// Status helpers
// ---------------------------------------------------------------------------

function formatStatus(status: string): string {
  return status
    .split("_")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

function statusColor(status: string): string {
  switch (status.toLowerCase()) {
    case "open":
      return "bg-blue-500 text-white";
    case "in_progress":
      return "bg-yellow-500 text-black";
    case "closed":
      return "bg-green-500 text-white";
    default:
      return "bg-[var(--color-border)] text-[var(--color-text-secondary)]";
  }
}

// ---------------------------------------------------------------------------
// TaskDetailModal
// ---------------------------------------------------------------------------

export interface TaskDetailModalProps {
  issue: Issue | null;
  isOpen: boolean;
  onClose: () => void;
  onAssigned?: (issueId: string, assignee: string | null) => void;
}

export function TaskDetailModal({ issue, isOpen, onClose, onAssigned }: TaskDetailModalProps) {
  const modalRef = useRef<HTMLDivElement>(null);
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const previouslyFocusedElement = useRef<HTMLElement | null>(null);
  const [isClosing, setIsClosing] = useState(false);
  const [isRendered, setIsRendered] = useState(false);
  const [assignee, setAssignee] = useState<string | null>(null);
  const [isAssigning, setIsAssigning] = useState(false);
  const [assignError, setAssignError] = useState<string | null>(null);

  // Sync local assignee state when issue changes
  useEffect(() => {
    setAssignee(issue?.assignee ?? issue?.owner ?? null);
    setAssignError(null);
  }, [issue]);

  const handleAssigneeChange = useCallback(
    async (newAssignee: string | null) => {
      if (!issue) return;
      setIsAssigning(true);
      setAssignError(null);
      try {
        if (newAssignee) {
          await tauri.assignIssue(issue.id, newAssignee);
        }
        setAssignee(newAssignee);
        onAssigned?.(issue.id, newAssignee);
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        setAssignError(`Failed to assign: ${message}`);
      } finally {
        setIsAssigning(false);
      }
    },
    [issue, onAssigned],
  );

  // Store the previously focused element when modal opens
  useEffect(() => {
    if (isOpen) {
      setIsRendered(true);
      setIsClosing(false);
      previouslyFocusedElement.current = document.activeElement as HTMLElement;
      // Focus the close button when modal opens
      setTimeout(() => {
        closeButtonRef.current?.focus();
      }, 50);
    } else if (isRendered) {
      setIsClosing(true);
      const timer = setTimeout(() => {
        setIsRendered(false);
        if (previouslyFocusedElement.current) {
          previouslyFocusedElement.current.focus();
        }
      }, 150);
      return () => clearTimeout(timer);
    }
  }, [isOpen, isRendered]);

  // Handle ESC key to close modal
  const handleKeyDown = useCallback(
    (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        onClose();
      }
    },
    [onClose],
  );

  useEffect(() => {
    if (isOpen) {
      document.addEventListener("keydown", handleKeyDown);
      // Prevent body scroll when modal is open
      document.body.style.overflow = "hidden";
    }

    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = "";
    };
  }, [isOpen, handleKeyDown]);

  // Handle backdrop click
  const handleBackdropClick = (event: React.MouseEvent<HTMLDivElement>) => {
    if (event.target === event.currentTarget) {
      onClose();
    }
  };

  // Handle close button click
  const handleCloseClick = () => {
    setIsClosing(true);
    setTimeout(() => {
      onClose();
    }, 150);
  };

  if (!isRendered || !issue) {
    return null;
  }

  const displayDescription =
    typeof issue.description === "string" ? issue.description : "No description provided";

  return (
    <div
      className={`fixed inset-0 z-50 flex items-center justify-center ${isClosing ? "animate-backdrop-exit" : "animate-backdrop-enter"}`}
      onClick={handleBackdropClick}
      role="dialog"
      aria-modal="true"
      aria-labelledby="modal-title"
      aria-describedby="modal-description"
    >
      {/* Backdrop */}
      <div
        className={`absolute inset-0 bg-black/50 ${isClosing ? "animate-backdrop-exit" : "animate-backdrop-enter"}`}
        aria-hidden="true"
      />

      {/* Modal */}
      <div
        ref={modalRef}
        className={`relative z-10 w-full max-w-2xl max-h-[90vh] overflow-y-auto mx-4 rounded-lg bg-[var(--color-bg)] border border-[var(--color-border)] shadow-2xl ${isClosing ? "animate-modal-exit" : "animate-modal-enter"}`}
      >
        {/* Header */}
        <div className="sticky top-0 z-10 flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)] bg-[var(--color-bg)]">
          <h2 id="modal-title" className="text-lg font-semibold text-[var(--color-text)] pr-4">
            Task Details
          </h2>
          <button
            ref={closeButtonRef}
            onClick={handleCloseClick}
            className="p-2 rounded-lg text-[var(--color-text-secondary)] hover:text-[var(--color-text)] hover:bg-[var(--color-surface)] transition-colors focus:outline-none focus:ring-2 focus:ring-[var(--color-primary)] focus:ring-offset-2"
            aria-label="Close modal"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              className="h-5 w-5"
              viewBox="0 0 20 20"
              fill="currentColor"
              aria-hidden="true"
            >
              <path
                fillRule="evenodd"
                d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
                clipRule="evenodd"
              />
            </svg>
          </button>
        </div>

        {/* Content */}
        <div className="px-6 py-6 space-y-6">
          {/* Title */}
          <div>
            <h3 className="text-sm font-medium text-[var(--color-text-secondary)] mb-2">Title</h3>
            <p className="text-lg font-medium text-[var(--color-text)]">{issue.title}</p>
          </div>

          {/* Status and Priority row */}
          <div className="grid grid-cols-2 gap-4">
            {/* Status */}
            <div>
              <h3 className="text-sm font-medium text-[var(--color-text-secondary)] mb-2">
                Status
              </h3>
              <span
                className={`inline-block px-3 py-1.5 rounded-md text-sm font-medium ${statusColor(issue.status)}`}
              >
                {formatStatus(issue.status)}
              </span>
            </div>

            {/* Priority */}
            <div>
              <h3 className="text-sm font-medium text-[var(--color-text-secondary)] mb-2">
                Priority
              </h3>
              <div className="flex items-center gap-2">
                <span
                  className={`inline-block px-3 py-1.5 rounded-md text-sm font-medium ${priorityColor(issue.priority)}`}
                >
                  {priorityLabel(issue.priority)}
                </span>
                <span className="text-sm text-[var(--color-text-secondary)]">
                  {priorityName(issue.priority)}
                </span>
              </div>
            </div>
          </div>

          {/* Assignee */}
          <div>
            <h3 className="text-sm font-medium text-[var(--color-text-secondary)] mb-2">
              Assignee
            </h3>
            <div className="flex items-center gap-2">
              <AssigneeSelector
                value={assignee}
                onChange={handleAssigneeChange}
                disabled={isAssigning}
                aria-label="Change assignee"
              />
              {isAssigning && (
                <span className="text-xs text-[var(--color-text-secondary)]">Saving...</span>
              )}
            </div>
            {assignError && <p className="mt-1 text-xs text-[var(--color-error)]">{assignError}</p>}
          </div>

          {/* Labels */}
          {issue.labels && issue.labels.length > 0 && (
            <div>
              <h3 className="text-sm font-medium text-[var(--color-text-secondary)] mb-2">
                Labels
              </h3>
              <div className="flex flex-wrap gap-2">
                {issue.labels.map((label) => (
                  <span
                    key={label}
                    className="inline-block px-2 py-1 rounded-md text-xs font-medium bg-[var(--color-surface)] border border-[var(--color-border)] text-[var(--color-text)]"
                  >
                    {label}
                  </span>
                ))}
              </div>
            </div>
          )}

          {/* Dependencies */}
          {issue.dependencies && issue.dependencies.length > 0 && (
            <div>
              <h3 className="text-sm font-medium text-[var(--color-text-secondary)] mb-2">
                Dependencies
              </h3>
              <ul className="space-y-1">
                {issue.dependencies.map((dep) => (
                  <li
                    key={dep}
                    className="flex items-center gap-2 text-sm text-[var(--color-text)]"
                  >
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      className="h-4 w-4 text-[var(--color-text-secondary)]"
                      viewBox="0 0 20 20"
                      fill="currentColor"
                    >
                      <path
                        fillRule="evenodd"
                        d="M12.586 4.586a2 2 0 112.828 2.828l-3 3a2 2 0 01-2.828 0 1 1 0 00-1.414 1.414 4 4 0 005.656 0l3-3a4 4 0 00-5.656-5.656l-1.5 1.5a1 1 0 101.414 1.414l1.5-1.5zm-5 5a2 2 0 012.828 0 1 1 0 101.414-1.414 4 4 0 00-5.656 0l-3 3a4 4 0 105.656 5.656l1.5-1.5a1 1 0 10-1.414-1.414l-1.5 1.5a2 2 0 11-2.828-2.828l3-3z"
                        clipRule="evenodd"
                      />
                    </svg>
                    <span className="font-mono text-xs">{dep}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {/* Description */}
          <div>
            <h3 className="text-sm font-medium text-[var(--color-text-secondary)] mb-2">
              Description
            </h3>
            <div
              id="modal-description"
              className="p-4 rounded-lg bg-[var(--color-surface)] border border-[var(--color-border)] text-sm text-[var(--color-text)] whitespace-pre-wrap"
            >
              {displayDescription}
            </div>
          </div>

          {/* ID */}
          <div>
            <h3 className="text-sm font-medium text-[var(--color-text-secondary)] mb-2">ID</h3>
            <code className="px-2 py-1 rounded bg-[var(--color-surface)] border border-[var(--color-border)] text-xs font-mono text-[var(--color-text-secondary)]">
              {issue.id}
            </code>
          </div>
        </div>

        {/* Footer */}
        <div className="sticky bottom-0 px-6 py-4 border-t border-[var(--color-border)] bg-[var(--color-bg)] flex justify-end">
          <button
            onClick={handleCloseClick}
            className="px-4 py-2 rounded-lg bg-[var(--color-primary)] text-white text-sm font-medium hover:bg-[var(--color-primary)]/90 transition-colors focus:outline-none focus:ring-2 focus:ring-[var(--color-primary)] focus:ring-offset-2"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
