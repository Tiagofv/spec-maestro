import { useCallback } from "react";
import { Route, Router, Switch, Link, useLocation } from "wouter";
import { useDashboardStore } from "./stores/dashboard";
import { useBootSequence } from "./hooks/useBootSequence";
import { useTauriEvents } from "./hooks/useTauriEvents";
import { useTheme } from "./hooks/useTheme";
import { BootSplash } from "./components/BootSplash";
import { WorkspaceSelector } from "./components/WorkspaceSelector";
import { ErrorBanner, useErrorBanner } from "./components/ErrorBanner";
import { ConnectionStatus } from "./components/ConnectionStatus";
import { IssueList } from "./views/IssueList";
import { KanbanBoard } from "./views/KanbanBoard";

function Navigation() {
  const [location] = useLocation();

  const navItems = [
    { path: "/", label: "List" },
    { path: "/kanban", label: "Board" },
  ];

  return (
    <nav className="flex items-center gap-1 ml-4">
      {navItems.map((item) => (
        <Link
          key={item.path}
          href={item.path}
          className={`px-3 py-1 text-xs rounded-md transition-colors ${
            location === item.path
              ? "bg-[var(--color-primary)]/15 text-[var(--color-primary)] font-medium"
              : "text-[var(--color-text-secondary)] hover:text-[var(--color-text)] hover:bg-[var(--color-border)]/50"
          }`}
        >
          {item.label}
        </Link>
      ))}
    </nav>
  );
}

function AppContent() {
  const { errors, addError, dismissError } = useErrorBanner();
  const { isDark, toggleTheme } = useTheme();

  const storeError = useDashboardStore((s) => s.error);

  // Surface store-level errors in the banner
  const storeErrors = storeError
    ? [{ id: "store", message: storeError, severity: "error" as const }]
    : [];
  const allErrors = [...storeErrors, ...errors];

  // Callback for ConnectionStatus health check failures
  const onHealthError = useCallback(
    (message: string) => {
      addError(`Health check failed: ${message}`, "warning");
    },
    [addError],
  );

  return (
    <div className="h-screen flex flex-col bg-[var(--color-bg)] text-[var(--color-text)]">
      {/* Error banners */}
      <ErrorBanner errors={allErrors} onDismiss={dismissError} />

      {/* Header */}
      <header className="h-12 shrink-0 flex items-center justify-between px-4 border-b border-[var(--color-border)] bg-[var(--color-surface)]">
        <div className="flex items-center gap-3">
          <span className="text-sm font-bold tracking-tight">AgentMaestro</span>
          <Navigation />
        </div>
        <div className="flex items-center gap-4">
          <ConnectionStatus onHealthError={onHealthError} />
          <WorkspaceSelector />
          <button
            onClick={toggleTheme}
            className="px-2 py-1 rounded-md border border-[var(--color-border)] text-xs text-[var(--color-text-secondary)] hover:bg-[var(--color-border)]/50 transition-colors duration-150"
            title={isDark ? "Switch to light mode" : "Switch to dark mode"}
          >
            {isDark ? "\u2600" : "\u263D"}
          </button>
        </div>
      </header>

      {/* Body - routed views */}
      <main className="flex-1 overflow-hidden">
        <Switch>
          <Route path="/" component={IssueList} />
          <Route path="/kanban" component={KanbanBoard} />
        </Switch>
      </main>
    </div>
  );
}

function App() {
  useBootSequence();
  useTauriEvents();

  const bootState = useDashboardStore((s) => s.bootState);

  // Show boot splash until completed (or if there's a fatal error without completion)
  if (!bootState.completed && !bootState.error) {
    return <BootSplash />;
  }

  // Boot error with no completion — show splash with error state
  if (bootState.error && !bootState.completed) {
    return <BootSplash />;
  }

  return (
    <Router>
      <AppContent />
    </Router>
  );
}

export default App;
