import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { useDashboardStore, getFilteredIssues } from "./dashboard";
import type { Issue, KanbanFilters } from "../types";

// Mock tauri commands
vi.mock("../lib/tauri", () => ({
  listIssues: vi.fn(),
  listWorkspaces: vi.fn(),
  switchWorkspace: vi.fn(),
}));

describe("Dashboard Store", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe("initial state", () => {
    it("has empty issues array initially", () => {
      const state = useDashboardStore.getState();
      expect(state.issues).toEqual([]);
    });

    it("is not loading initially", () => {
      const state = useDashboardStore.getState();
      expect(state.isLoading).toBe(false);
    });

    it("has no error initially", () => {
      const state = useDashboardStore.getState();
      expect(state.error).toBeNull();
    });

    it("has empty kanban filters initially", () => {
      const state = useDashboardStore.getState();
      expect(state.kanbanFilters).toEqual({});
    });

    it("does not show completed tasks initially", () => {
      const state = useDashboardStore.getState();
      expect(state.showCompleted).toBe(false);
    });
  });

  describe("UI actions", () => {
    it("setError updates error state", () => {
      const store = useDashboardStore.getState();
      store.setError("Test error");
      expect(useDashboardStore.getState().error).toBe("Test error");
    });

    it("setError clears error when null", () => {
      const store = useDashboardStore.getState();
      store.setError("Test error");
      store.setError(null);
      expect(useDashboardStore.getState().error).toBeNull();
    });

    it("setLoading updates loading state", () => {
      const store = useDashboardStore.getState();
      store.setLoading(true);
      expect(useDashboardStore.getState().isLoading).toBe(true);
    });
  });

  describe("filter actions", () => {
    it("setKanbanFilters replaces all filters", () => {
      const store = useDashboardStore.getState();
      store.setKanbanFilters({ status: ["open"], assignee: ["user1"] });

      expect(useDashboardStore.getState().kanbanFilters).toEqual({
        status: ["open"],
        assignee: ["user1"],
      });
    });

    it("updateKanbanFilters merges with existing filters", () => {
      const store = useDashboardStore.getState();
      store.setKanbanFilters({ status: ["open"] });
      store.updateKanbanFilters({ assignee: ["user1"] });

      expect(useDashboardStore.getState().kanbanFilters).toEqual({
        status: ["open"],
        assignee: ["user1"],
      });
    });

    it("updateKanbanFilters overwrites existing filter values", () => {
      const store = useDashboardStore.getState();
      store.setKanbanFilters({ status: ["open"], assignee: ["user1"] });
      store.updateKanbanFilters({ status: ["closed"] });

      expect(useDashboardStore.getState().kanbanFilters).toEqual({
        status: ["closed"],
        assignee: ["user1"],
      });
    });

    it("clearKanbanFilters resets to empty filters", () => {
      const store = useDashboardStore.getState();
      store.setKanbanFilters({ status: ["open"], assignee: ["user1"] });
      store.clearKanbanFilters();

      expect(useDashboardStore.getState().kanbanFilters).toEqual({});
    });

    it("setShowCompleted updates showCompleted state", () => {
      const store = useDashboardStore.getState();
      store.setShowCompleted(true);
      expect(useDashboardStore.getState().showCompleted).toBe(true);
    });
  });

  describe("getFilteredIssues", () => {
    const createMockIssue = (overrides: Partial<Issue> = {}): Issue => ({
      id: "TEST-1",
      title: "Test Issue",
      status: "open",
      priority: 1,
      labels: [],
      dependencies: [],
      assignee: "user1",
      owner: null,
      issue_type: null,
      ...overrides,
    });

    it("returns all issues when no filters", () => {
      const issues = [createMockIssue({ id: "TEST-1" }), createMockIssue({ id: "TEST-2" })];
      const result = getFilteredIssues(issues, {}, false);
      expect(result).toHaveLength(2);
    });

    describe("status filtering", () => {
      it("filters by single status", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", status: "open" }),
          createMockIssue({ id: "TEST-2", status: "closed" }),
        ];
        const result = getFilteredIssues(issues, { status: ["open"] }, true);
        expect(result).toHaveLength(1);
        expect(result[0].id).toBe("TEST-1");
      });

      it("filters by multiple statuses", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", status: "open" }),
          createMockIssue({ id: "TEST-2", status: "in_progress" }),
          createMockIssue({ id: "TEST-3", status: "closed" }),
        ];
        const result = getFilteredIssues(issues, { status: ["open", "in_progress"] }, true);
        expect(result).toHaveLength(2);
      });

      it("excludes closed tasks when showCompleted is false", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", status: "open" }),
          createMockIssue({ id: "TEST-2", status: "closed" }),
        ];
        const result = getFilteredIssues(issues, {}, false);
        expect(result).toHaveLength(1);
        expect(result[0].id).toBe("TEST-1");
      });

      it("includes closed tasks when showCompleted is true", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", status: "open" }),
          createMockIssue({ id: "TEST-2", status: "closed" }),
        ];
        const result = getFilteredIssues(issues, {}, true);
        expect(result).toHaveLength(2);
      });
    });

    describe("assignee filtering", () => {
      it("filters by assignee", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", assignee: "user1" }),
          createMockIssue({ id: "TEST-2", assignee: "user2" }),
        ];
        const result = getFilteredIssues(issues, { assignee: ["user1"] }, true);
        expect(result).toHaveLength(1);
        expect(result[0].assignee).toBe("user1");
      });

      it("matches owner when assignee is null", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", assignee: null, owner: "user1" }),
          createMockIssue({ id: "TEST-2", assignee: "user2", owner: null }),
        ];
        const result = getFilteredIssues(issues, { assignee: ["user1"] }, true);
        expect(result).toHaveLength(1);
        expect(result[0].id).toBe("TEST-1");
      });

      it("handles multiple assignees", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", assignee: "user1" }),
          createMockIssue({ id: "TEST-2", assignee: "user2" }),
          createMockIssue({ id: "TEST-3", assignee: "user3" }),
        ];
        const result = getFilteredIssues(issues, { assignee: ["user1", "user2"] }, true);
        expect(result).toHaveLength(2);
      });

      it("returns empty array when no matching assignees", () => {
        const issues = [createMockIssue({ id: "TEST-1", assignee: "user1" })];
        const result = getFilteredIssues(issues, { assignee: ["nonexistent"] }, true);
        expect(result).toHaveLength(0);
      });
    });

    describe("priority filtering", () => {
      it("filters by priority", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", priority: 1 }),
          createMockIssue({ id: "TEST-2", priority: 2 }),
          createMockIssue({ id: "TEST-3", priority: 3 }),
        ];
        const result = getFilteredIssues(issues, { priority: [1, 2] }, true);
        expect(result).toHaveLength(2);
      });

      it("handles string priority values", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", priority: "1" }),
          createMockIssue({ id: "TEST-2", priority: 2 }),
        ];
        const result = getFilteredIssues(issues, { priority: [1] }, true);
        expect(result).toHaveLength(1);
      });

      it("excludes null priority when filtering", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", priority: 1 }),
          createMockIssue({ id: "TEST-2", priority: null }),
        ];
        const result = getFilteredIssues(issues, { priority: [1] }, true);
        expect(result).toHaveLength(1);
      });
    });

    describe("label filtering", () => {
      it("filters by single label", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", labels: ["bug", "urgent"] }),
          createMockIssue({ id: "TEST-2", labels: ["feature"] }),
        ];
        const result = getFilteredIssues(issues, { labels: ["bug"] }, true);
        expect(result).toHaveLength(1);
        expect(result[0].id).toBe("TEST-1");
      });

      it("filters by multiple labels", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", labels: ["bug"] }),
          createMockIssue({ id: "TEST-2", labels: ["feature"] }),
          createMockIssue({ id: "TEST-3", labels: ["docs"] }),
        ];
        const result = getFilteredIssues(issues, { labels: ["bug", "feature"] }, true);
        expect(result).toHaveLength(2);
      });

      it("returns empty when no matching labels", () => {
        const issues = [createMockIssue({ id: "TEST-1", labels: ["bug"] })];
        const result = getFilteredIssues(issues, { labels: ["feature"] }, true);
        expect(result).toHaveLength(0);
      });
    });

    describe("search filtering", () => {
      it("filters by title match", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", title: "Fix the login bug" }),
          createMockIssue({ id: "TEST-2", title: "Add new feature" }),
        ];
        const result = getFilteredIssues(issues, { search: "login" }, true);
        expect(result).toHaveLength(1);
        expect(result[0].title).toBe("Fix the login bug");
      });

      it("filters by ID match", () => {
        const issues = [
          createMockIssue({ id: "PROJ-123", title: "Test" }),
          createMockIssue({ id: "OTHER-456", title: "Test" }),
        ];
        const result = getFilteredIssues(issues, { search: "PROJ" }, true);
        expect(result).toHaveLength(1);
        expect(result[0].id).toBe("PROJ-123");
      });

      it("is case insensitive", () => {
        const issues = [createMockIssue({ id: "TEST-1", title: "BUG Fix" })];
        const result = getFilteredIssues(issues, { search: "bug" }, true);
        expect(result).toHaveLength(1);
      });
    });

    describe("sorting", () => {
      it("sorts by priority ascending", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", priority: 3 }),
          createMockIssue({ id: "TEST-2", priority: 1 }),
          createMockIssue({ id: "TEST-3", priority: 2 }),
        ];
        const result = getFilteredIssues(issues, {}, true);
        expect(result[0].priority).toBe(1);
        expect(result[1].priority).toBe(2);
        expect(result[2].priority).toBe(3);
      });

      it("handles null priorities", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", priority: 1 }),
          createMockIssue({ id: "TEST-2", priority: null }),
          createMockIssue({ id: "TEST-3", priority: 2 }),
        ];
        const result = getFilteredIssues(issues, {}, true);
        expect(result[0].priority).toBe(1);
        expect(result[1].priority).toBe(2);
        expect(result[2].priority).toBeNull();
      });

      it("handles string priorities", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", priority: "2" }),
          createMockIssue({ id: "TEST-2", priority: 1 }),
        ];
        const result = getFilteredIssues(issues, {}, true);
        expect(result[0].priority).toBe(1);
        expect(result[1].priority).toBe("2");
      });
    });

    describe("combined filters", () => {
      it("applies multiple filters together", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", status: "open", assignee: "user1", priority: 1 }),
          createMockIssue({ id: "TEST-2", status: "open", assignee: "user2", priority: 1 }),
          createMockIssue({ id: "TEST-3", status: "closed", assignee: "user1", priority: 1 }),
        ];
        const result = getFilteredIssues(issues, { status: ["open"], assignee: ["user1"] }, true);
        expect(result).toHaveLength(1);
        expect(result[0].id).toBe("TEST-1");
      });
    });

    describe("edge cases", () => {
      it("handles empty issues array", () => {
        const result = getFilteredIssues([], {}, false);
        expect(result).toEqual([]);
      });

      it("handles single issue", () => {
        const issues = [createMockIssue({ id: "TEST-1" })];
        const result = getFilteredIssues(issues, {}, false);
        expect(result).toHaveLength(1);
      });

      it("handles all issues same status", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", status: "open" }),
          createMockIssue({ id: "TEST-2", status: "open" }),
          createMockIssue({ id: "TEST-3", status: "open" }),
        ];
        const result = getFilteredIssues(issues, { status: ["open"] }, true);
        expect(result).toHaveLength(3);
      });

      it("handles all issues same priority", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", priority: 2 }),
          createMockIssue({ id: "TEST-2", priority: 2 }),
          createMockIssue({ id: "TEST-3", priority: 2 }),
        ];
        const result = getFilteredIssues(issues, { priority: [2] }, true);
        expect(result).toHaveLength(3);
      });

      it("handles all issues same assignee", () => {
        const issues = [
          createMockIssue({ id: "TEST-1", assignee: "user1" }),
          createMockIssue({ id: "TEST-2", assignee: "user1" }),
          createMockIssue({ id: "TEST-3", assignee: "user1" }),
        ];
        const result = getFilteredIssues(issues, { assignee: ["user1"] }, true);
        expect(result).toHaveLength(3);
      });

      it("handles issues with null fields", () => {
        const issues = [createMockIssue({ id: "TEST-1", priority: null, assignee: null })];
        const result = getFilteredIssues(issues, {}, false);
        expect(result).toHaveLength(1);
      });
    });
  });
});
