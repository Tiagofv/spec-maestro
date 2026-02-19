import { useEffect, useRef, useCallback, useState } from "react";
import * as tauri from "../../lib/tauri";
import type { CreateIssueRequest, Issue } from "../../types";

// ---------------------------------------------------------------------------
// QuickCreateModal
// ---------------------------------------------------------------------------

export interface QuickCreateModalProps {
  isOpen: boolean;
  onClose: () => void;
  onCreated?: (issue: Issue) => void;
}

interface FormState {
  title: string;
  status: string;
  priority: number;
  assignee: string;
}

const INITIAL_FORM: FormState = {
  title: "",
  status: "open",
  priority: 2,
  assignee: "",
};

export function QuickCreateModal({ isOpen, onClose, onCreated }: QuickCreateModalProps) {
  const modalRef = useRef<HTMLDivElement>(null);
  const titleInputRef = useRef<HTMLInputElement>(null);
  const previouslyFocusedElement = useRef<HTMLElement | null>(null);

  const [isRendered, setIsRendered] = useState(false);
  const [isClosing, setIsClosing] = useState(false);
  const [form, setForm] = useState<FormState>(INITIAL_FORM);
  const [titleError, setTitleError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);

  // Mount / unmount with animation
  useEffect(() => {
    if (isOpen) {
      setIsRendered(true);
      setIsClosing(false);
      setForm(INITIAL_FORM);
      setTitleError(null);
      setSubmitError(null);
      previouslyFocusedElement.current = document.activeElement as HTMLElement;
      // Focus title input when modal opens
      setTimeout(() => {
        titleInputRef.current?.focus();
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

  // Prevent body scroll and handle ESC key
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
      document.body.style.overflow = "hidden";
    }
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = "";
    };
  }, [isOpen, handleKeyDown]);

  // Backdrop click closes modal
  const handleBackdropClick = (event: React.MouseEvent<HTMLDivElement>) => {
    if (event.target === event.currentTarget) {
      onClose();
    }
  };

  const handleClose = () => {
    setIsClosing(true);
    setTimeout(() => {
      onClose();
    }, 150);
  };

  // Form change handlers
  const handleTitleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setForm((prev) => ({ ...prev, title: e.target.value }));
    if (e.target.value.trim()) {
      setTitleError(null);
    }
  };

  const handleStatusChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    setForm((prev) => ({ ...prev, status: e.target.value }));
  };

  const handlePriorityChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    setForm((prev) => ({ ...prev, priority: parseInt(e.target.value, 10) }));
  };

  const handleAssigneeChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setForm((prev) => ({ ...prev, assignee: e.target.value }));
  };

  // Submit handler
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    // Validate title
    if (!form.title.trim()) {
      setTitleError("Title is required");
      titleInputRef.current?.focus();
      return;
    }

    setIsSubmitting(true);
    setSubmitError(null);

    const request: CreateIssueRequest = {
      title: form.title.trim(),
    };

    try {
      let created = await tauri.createIssue(request);

      // Apply status if not the default "open"
      if (form.status && form.status !== "open") {
        try {
          await tauri.updateIssueStatus(created.id, form.status);
          created = { ...created, status: form.status };
        } catch {
          // Non-fatal: issue was created, status update failed
        }
      }

      // Apply assignee if provided
      if (form.assignee.trim()) {
        try {
          await tauri.assignIssue(created.id, form.assignee.trim());
          created = { ...created, assignee: form.assignee.trim() };
        } catch {
          // Non-fatal: issue was created, assignee update failed
        }
      }

      onCreated?.(created);
      onClose();
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setSubmitError(`Failed to create task: ${message}`);
    } finally {
      setIsSubmitting(false);
    }
  };

  if (!isRendered) {
    return null;
  }

  return (
    <div
      className={`fixed inset-0 z-50 flex items-center justify-center ${isClosing ? "animate-backdrop-exit" : "animate-backdrop-enter"}`}
      onClick={handleBackdropClick}
      role="dialog"
      aria-modal="true"
      aria-labelledby="quick-create-title"
    >
      {/* Backdrop */}
      <div
        className={`absolute inset-0 bg-black/50 ${isClosing ? "animate-backdrop-exit" : "animate-backdrop-enter"}`}
        aria-hidden="true"
      />

      {/* Modal */}
      <div
        ref={modalRef}
        className={`relative z-10 w-full max-w-md mx-4 rounded-lg bg-[var(--color-bg)] border border-[var(--color-border)] shadow-2xl ${isClosing ? "animate-modal-exit" : "animate-modal-enter"}`}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 id="quick-create-title" className="text-base font-semibold text-[var(--color-text)]">
            Create Task
          </h2>
          <button
            type="button"
            onClick={handleClose}
            className="p-2 rounded-lg text-[var(--color-text-secondary)] hover:text-[var(--color-text)] hover:bg-[var(--color-surface)] transition-colors focus:outline-none focus:ring-2 focus:ring-[var(--color-primary)] focus:ring-offset-2"
            aria-label="Close modal"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              className="h-4 w-4"
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

        {/* Form */}
        <form onSubmit={handleSubmit} noValidate>
          <div className="px-6 py-5 space-y-4">
            {/* Submit error */}
            {submitError && (
              <div className="p-3 rounded-md bg-[var(--color-error)]/10 border border-[var(--color-error)]/30 text-sm text-[var(--color-error)]">
                {submitError}
              </div>
            )}

            {/* Title field */}
            <div>
              <label
                htmlFor="task-title"
                className="block text-sm font-medium text-[var(--color-text)] mb-1.5"
              >
                Title{" "}
                <span className="text-[var(--color-error)]" aria-hidden="true">
                  *
                </span>
              </label>
              <input
                ref={titleInputRef}
                id="task-title"
                type="text"
                value={form.title}
                onChange={handleTitleChange}
                placeholder="Enter task title"
                required
                aria-required="true"
                aria-invalid={titleError ? "true" : "false"}
                aria-describedby={titleError ? "title-error" : undefined}
                className={`w-full px-3 py-2 rounded-md bg-[var(--color-surface)] border text-sm text-[var(--color-text)] placeholder:text-[var(--color-text-secondary)] transition-colors focus:outline-none focus:ring-2 focus:ring-[var(--color-primary)] focus:ring-offset-1 ${
                  titleError
                    ? "border-[var(--color-error)] focus:ring-[var(--color-error)]"
                    : "border-[var(--color-border)] hover:border-[var(--color-primary)]/50"
                }`}
              />
              {titleError && (
                <p id="title-error" className="mt-1 text-xs text-[var(--color-error)]" role="alert">
                  {titleError}
                </p>
              )}
            </div>

            {/* Status and Priority row */}
            <div className="grid grid-cols-2 gap-3">
              {/* Status */}
              <div>
                <label
                  htmlFor="task-status"
                  className="block text-sm font-medium text-[var(--color-text)] mb-1.5"
                >
                  Status
                </label>
                <select
                  id="task-status"
                  value={form.status}
                  onChange={handleStatusChange}
                  className="w-full px-3 py-2 rounded-md bg-[var(--color-surface)] border border-[var(--color-border)] text-sm text-[var(--color-text)] transition-colors focus:outline-none focus:ring-2 focus:ring-[var(--color-primary)] focus:ring-offset-1 hover:border-[var(--color-primary)]/50 cursor-pointer"
                >
                  <option value="open">Open</option>
                  <option value="in_progress">In Progress</option>
                  <option value="blocked">Blocked</option>
                  <option value="closed">Closed</option>
                </select>
              </div>

              {/* Priority */}
              <div>
                <label
                  htmlFor="task-priority"
                  className="block text-sm font-medium text-[var(--color-text)] mb-1.5"
                >
                  Priority
                </label>
                <select
                  id="task-priority"
                  value={form.priority}
                  onChange={handlePriorityChange}
                  className="w-full px-3 py-2 rounded-md bg-[var(--color-surface)] border border-[var(--color-border)] text-sm text-[var(--color-text)] transition-colors focus:outline-none focus:ring-2 focus:ring-[var(--color-primary)] focus:ring-offset-1 hover:border-[var(--color-primary)]/50 cursor-pointer"
                >
                  <option value={1}>P1 - Urgent</option>
                  <option value={2}>P2 - High</option>
                  <option value={3}>P3 - Normal</option>
                  <option value={4}>P4 - Low</option>
                </select>
              </div>
            </div>

            {/* Assignee */}
            <div>
              <label
                htmlFor="task-assignee"
                className="block text-sm font-medium text-[var(--color-text)] mb-1.5"
              >
                Assignee{" "}
                <span className="text-[var(--color-text-secondary)] font-normal">(optional)</span>
              </label>
              <input
                id="task-assignee"
                type="text"
                value={form.assignee}
                onChange={handleAssigneeChange}
                placeholder="e.g. @username"
                className="w-full px-3 py-2 rounded-md bg-[var(--color-surface)] border border-[var(--color-border)] text-sm text-[var(--color-text)] placeholder:text-[var(--color-text-secondary)] transition-colors focus:outline-none focus:ring-2 focus:ring-[var(--color-primary)] focus:ring-offset-1 hover:border-[var(--color-primary)]/50"
              />
            </div>
          </div>

          {/* Footer */}
          <div className="flex items-center justify-end gap-3 px-6 py-4 border-t border-[var(--color-border)]">
            <button
              type="button"
              onClick={handleClose}
              disabled={isSubmitting}
              className="px-4 py-2 rounded-lg border border-[var(--color-border)] text-sm font-medium text-[var(--color-text-secondary)] hover:text-[var(--color-text)] hover:bg-[var(--color-surface)] transition-colors focus:outline-none focus:ring-2 focus:ring-[var(--color-primary)] focus:ring-offset-2 disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting}
              className="px-4 py-2 rounded-lg bg-[var(--color-primary)] text-white text-sm font-medium hover:bg-[var(--color-primary)]/90 transition-colors focus:outline-none focus:ring-2 focus:ring-[var(--color-primary)] focus:ring-offset-2 disabled:opacity-50 flex items-center gap-2"
            >
              {isSubmitting ? (
                <>
                  <svg
                    className="spinner h-3.5 w-3.5"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    aria-hidden="true"
                  >
                    <circle
                      className="opacity-25"
                      cx="12"
                      cy="12"
                      r="10"
                      stroke="currentColor"
                      strokeWidth="4"
                    />
                    <path
                      className="opacity-75"
                      fill="currentColor"
                      d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                    />
                  </svg>
                  <span>Creating...</span>
                </>
              ) : (
                "Create Task"
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
