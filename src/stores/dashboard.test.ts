import { describe, it, expect } from "vitest";
import type { Issue, KanbanFilters } from "../types";
import { getFilteredIssues, useDashboardStore } from "./dashboard";

function makeIssue(overrides: Partial<Issue> = {}): Issue {
  return {
    id: "ISS-1",
    title: "Issue",
    status: "open",
    priority: 1,
    labels: [],
    dependencies: [],
    assignee: null,
    owner: null,
    issue_type: null,
    ...overrides,
  };
}

describe("dashboard store filtering", () => {
  it("filters by epic ids", () => {
    const issues: Issue[] = [
      makeIssue({ id: "A", epic_id: "E-1" }),
      makeIssue({ id: "B", epic_id: "E-2" }),
      makeIssue({ id: "C" }),
    ];
    const filters: KanbanFilters = { epic: ["E-1"] };

    const result = getFilteredIssues(issues, filters, true);
    expect(result.map((issue) => issue.id)).toEqual(["A"]);
  });

  it("excludes closed issues when showCompleted is false", () => {
    const issues: Issue[] = [makeIssue({ id: "A", status: "open" }), makeIssue({ id: "B", status: "closed" })];

    const result = getFilteredIssues(issues, {}, false);
    expect(result.map((issue) => issue.id)).toEqual(["A"]);
  });

  it("persists view mode to localStorage", () => {
    window.localStorage.removeItem("kanban-view-mode");
    useDashboardStore.getState().setViewMode("epic");

    expect(useDashboardStore.getState().viewMode).toBe("epic");
    expect(window.localStorage.getItem("kanban-view-mode")).toBe("epic");
  });
});
