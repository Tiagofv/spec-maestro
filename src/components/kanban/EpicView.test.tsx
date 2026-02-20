import { describe, it, expect, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";
import { EpicView } from "./EpicView";
import type { EpicStatus, Issue } from "../../types";

const EPICS: EpicStatus[] = [
  { id: "E-1", title: "Payments", total: 2, open: 1, in_progress: 0, blocked: 0, closed: 1 },
  { id: "E-2", title: "Reports", total: 0, open: 0, in_progress: 0, blocked: 0, closed: 0 },
];

const ISSUES: Issue[] = [
  {
    id: "ISS-1",
    title: "Issue One",
    status: "open",
    priority: 1,
    labels: [],
    dependencies: [],
    assignee: null,
    owner: null,
    issue_type: null,
    epic_id: "E-1",
  },
  {
    id: "ISS-2",
    title: "Issue Two",
    status: "open",
    priority: 2,
    labels: [],
    dependencies: [],
    assignee: null,
    owner: null,
    issue_type: null,
  },
];

describe("EpicView", () => {
  it("renders epic swimlanes and no epic group", () => {
    render(
      <EpicView
        issues={ISSUES}
        epics={EPICS}
        collapseState={{}}
        onToggleCollapse={vi.fn()}
        onCollapseAll={vi.fn()}
        onExpandAll={vi.fn()}
      />,
    );

    expect(screen.getByTestId("epic-swimlane-E-1")).toBeInTheDocument();
    expect(screen.getByTestId("epic-swimlane-E-2")).toBeInTheDocument();
    expect(screen.getByTestId("epic-swimlane-no-epic")).toBeInTheDocument();
  });

  it("fires collapse all and expand all actions", () => {
    const onCollapseAll = vi.fn();
    const onExpandAll = vi.fn();
    render(
      <EpicView
        issues={ISSUES}
        epics={EPICS}
        collapseState={{}}
        onToggleCollapse={vi.fn()}
        onCollapseAll={onCollapseAll}
        onExpandAll={onExpandAll}
      />,
    );

    fireEvent.click(screen.getByTestId("epic-collapse-all"));
    fireEvent.click(screen.getByTestId("epic-expand-all"));

    expect(onCollapseAll).toHaveBeenCalledTimes(1);
    expect(onExpandAll).toHaveBeenCalledTimes(1);
  });

  it("renders 200+ tickets across 20+ epics under 2 seconds", () => {
    const manyEpics: EpicStatus[] = Array.from({ length: 20 }, (_, i) => ({
      id: `E-${i + 1}`,
      title: `Epic ${i + 1}`,
      total: 10,
      open: 5,
      in_progress: 3,
      blocked: 1,
      closed: 1,
    }));

    const statuses = ["open", "in_progress", "blocked", "closed"];
    const manyIssues: Issue[] = Array.from({ length: 220 }, (_, i) => ({
      id: `ISS-${i + 1}`,
      title: `Issue ${i + 1}`,
      status: statuses[i % statuses.length],
      priority: (i % 4) + 1,
      labels: [],
      dependencies: [],
      assignee: null,
      owner: null,
      issue_type: null,
      epic_id: `E-${(i % 20) + 1}`,
    }));

    const start = performance.now();
    render(
      <EpicView
        issues={manyIssues}
        epics={manyEpics}
        collapseState={{}}
        onToggleCollapse={vi.fn()}
        onCollapseAll={vi.fn()}
        onExpandAll={vi.fn()}
      />,
    );
    const duration = performance.now() - start;

    expect(duration).toBeLessThan(2000);
  });
});
