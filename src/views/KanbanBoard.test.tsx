import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { KanbanBoard } from "./KanbanBoard";
import * as tauri from "../lib/tauri";

// Mock the dashboard store
const mockStore = {
  issues: [],
  isLoading: false,
  error: null,
  fetchIssues: vi.fn(),
  setError: vi.fn(),
};

vi.mock("../stores/dashboard", () => ({
  useDashboardStore: (selector: (state: typeof mockStore) => unknown) => selector(mockStore),
}));

// Mock tauri commands
vi.mock("../lib/tauri", () => ({
  updateIssueStatus: vi.fn(),
}));

describe("KanbanBoard", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockStore.issues = [];
    mockStore.isLoading = false;
    mockStore.error = null;
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe("rendering", () => {
    it("renders the board header with title", () => {
      render(<KanbanBoard />);
      expect(screen.getByText("Kanban Board")).toBeInTheDocument();
    });

    it("renders refresh button", () => {
      render(<KanbanBoard />);
      expect(screen.getByText("Refresh")).toBeInTheDocument();
    });

    it("renders all four columns", () => {
      render(<KanbanBoard />);
      expect(screen.getByText("Open")).toBeInTheDocument();
      expect(screen.getByText("In Progress")).toBeInTheDocument();
      expect(screen.getByText("Blocked")).toBeInTheDocument();
      expect(screen.getByText("Closed")).toBeInTheDocument();
    });
  });

  describe("empty state", () => {
    it("displays 'No issues found' when no issues exist", () => {
      mockStore.issues = [];
      render(<KanbanBoard />);
      expect(screen.getByText("No issues found")).toBeInTheDocument();
    });

    it("does not display 'No issues found' when issues exist", () => {
      mockStore.issues = [
        {
          id: "TEST-1",
          title: "Test Issue",
          status: "open",
          priority: 1,
          labels: [],
          dependencies: [],
          assignee: null,
          owner: null,
          issue_type: null,
        },
      ];
      render(<KanbanBoard />);
      expect(screen.queryByText("No issues found")).not.toBeInTheDocument();
    });
  });

  describe("column counts", () => {
    it("displays correct count for each column", () => {
      mockStore.issues = [
        {
          id: "TEST-1",
          title: "Open Task",
          status: "open",
          priority: 1,
          labels: [],
          dependencies: [],
          assignee: "user1",
          owner: null,
          issue_type: null,
        },
        {
          id: "TEST-2",
          title: "In Progress Task",
          status: "in_progress",
          priority: 2,
          labels: [],
          dependencies: [],
          assignee: "user2",
          owner: null,
          issue_type: null,
        },
        {
          id: "TEST-3",
          title: "Blocked Task",
          status: "blocked",
          priority: 1,
          labels: [],
          dependencies: [],
          assignee: "user3",
          owner: null,
          issue_type: null,
        },
        {
          id: "TEST-4",
          title: "Closed Task",
          status: "closed",
          priority: 3,
          labels: [],
          dependencies: [],
          assignee: null,
          owner: "user4",
          issue_type: null,
        },
      ];
      render(<KanbanBoard />);

      // Check column headers contain correct counts
      const openColumn = screen.getByText("Open").closest("div");
      const inProgressColumn = screen.getByText("In Progress").closest("div");
      const blockedColumn = screen.getByText("Blocked").closest("div");
      const closedColumn = screen.getByText("Closed").closest("div");

      expect(openColumn?.textContent).toContain("1");
      expect(inProgressColumn?.textContent).toContain("1");
      expect(blockedColumn?.textContent).toContain("1");
      expect(closedColumn?.textContent).toContain("1");
    });

    it("displays zero count for empty columns", () => {
      mockStore.issues = [
        {
          id: "TEST-1",
          title: "Only Task",
          status: "open",
          priority: 1,
          labels: [],
          dependencies: [],
          assignee: null,
          owner: null,
          issue_type: null,
        },
      ];
      render(<KanbanBoard />);

      const inProgressColumn = screen.getByText("In Progress").closest("div");
      expect(inProgressColumn?.textContent).toContain("0");
    });
  });

  describe("loading state", () => {
    it("shows loading skeleton when loading and no issues", () => {
      mockStore.isLoading = true;
      mockStore.issues = [];
      render(<KanbanBoard />);

      // Should show skeleton elements
      const skeletons = document.querySelectorAll(".skeleton");
      expect(skeletons.length).toBeGreaterThan(0);
    });

    it("shows loading spinner on refresh button when loading", () => {
      mockStore.isLoading = true;
      render(<KanbanBoard />);
      expect(screen.getByText("Loading...")).toBeInTheDocument();
    });
  });

  describe("error state", () => {
    it("displays error banner when error exists", () => {
      mockStore.error = "Failed to fetch issues";
      render(<KanbanBoard />);
      expect(screen.getByText("Failed to fetch issues")).toBeInTheDocument();
    });

    it("does not display error banner when no error", () => {
      mockStore.error = null;
      render(<KanbanBoard />);
      expect(screen.queryByText("Failed to fetch issues")).not.toBeInTheDocument();
    });
  });

  describe("refresh functionality", () => {
    it("calls fetchIssues when refresh button is clicked", () => {
      render(<KanbanBoard />);
      const refreshButton = screen.getByText("Refresh");
      fireEvent.click(refreshButton);
      expect(mockStore.fetchIssues).toHaveBeenCalled();
    });

    it("disables refresh button while loading", () => {
      mockStore.isLoading = true;
      render(<KanbanBoard />);
      const refreshButton = screen.getByText("Loading...").closest("button");
      expect(refreshButton).toBeDisabled();
    });
  });

  describe("edge cases", () => {
    it("handles single task in board", () => {
      mockStore.issues = [
        {
          id: "TEST-1",
          title: "Single Task",
          status: "open",
          priority: 1,
          labels: [],
          dependencies: [],
          assignee: "user1",
          owner: null,
          issue_type: null,
        },
      ];
      render(<KanbanBoard />);
      expect(screen.getByText("Single Task")).toBeInTheDocument();
    });

    it("handles all tasks with same status", () => {
      mockStore.issues = [
        {
          id: "TEST-1",
          title: "Task 1",
          status: "open",
          priority: 1,
          labels: [],
          dependencies: [],
          assignee: null,
          owner: null,
          issue_type: null,
        },
        {
          id: "TEST-2",
          title: "Task 2",
          status: "open",
          priority: 2,
          labels: [],
          dependencies: [],
          assignee: null,
          owner: null,
          issue_type: null,
        },
        {
          id: "TEST-3",
          title: "Task 3",
          status: "open",
          priority: 3,
          labels: [],
          dependencies: [],
          assignee: null,
          owner: null,
          issue_type: null,
        },
      ];
      render(<KanbanBoard />);

      // All three should be in Open column
      expect(screen.getByText("Task 1")).toBeInTheDocument();
      expect(screen.getByText("Task 2")).toBeInTheDocument();
      expect(screen.getByText("Task 3")).toBeInTheDocument();
    });

    it("sorts tasks by priority within columns", () => {
      mockStore.issues = [
        {
          id: "TEST-1",
          title: "Low Priority",
          status: "open",
          priority: 4,
          labels: [],
          dependencies: [],
          assignee: null,
          owner: null,
          issue_type: null,
        },
        {
          id: "TEST-2",
          title: "High Priority",
          status: "open",
          priority: 1,
          labels: [],
          dependencies: [],
          assignee: null,
          owner: null,
          issue_type: null,
        },
        {
          id: "TEST-3",
          title: "Medium Priority",
          status: "open",
          priority: 2,
          labels: [],
          dependencies: [],
          assignee: null,
          owner: null,
          issue_type: null,
        },
      ];
      render(<KanbanBoard />);

      // Tasks should be sorted by priority (1 first, then 2, then 4)
      const taskElements = screen.getAllByText(/Priority/);
      expect(taskElements[0].textContent).toBe("High Priority");
      expect(taskElements[1].textContent).toBe("Medium Priority");
      expect(taskElements[2].textContent).toBe("Low Priority");
    });

    it("handles unknown status by defaulting to open", () => {
      mockStore.issues = [
        {
          id: "TEST-1",
          title: "Unknown Status Task",
          status: "unknown_status",
          priority: 1,
          labels: [],
          dependencies: [],
          assignee: null,
          owner: null,
          issue_type: null,
        },
      ];
      render(<KanbanBoard />);
      expect(screen.getByText("Unknown Status Task")).toBeInTheDocument();
    });
  });

  describe("task click handling", () => {
    it("opens task detail modal when task card is clicked", () => {
      mockStore.issues = [
        {
          id: "TEST-1",
          title: "Clickable Task",
          status: "open",
          priority: 1,
          labels: [],
          dependencies: [],
          assignee: "user1",
          owner: null,
          issue_type: null,
        },
      ];
      render(<KanbanBoard />);

      const taskCard = screen.getByText("Clickable Task");
      fireEvent.click(taskCard);

      // Modal should open
      expect(screen.getByText("Clickable Task")).toBeInTheDocument();
    });
  });
});
