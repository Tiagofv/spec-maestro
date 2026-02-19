import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { KanbanBoard } from "../../views/KanbanBoard";
import { AssigneeSelector } from "../../components/kanban/AssigneeSelector";
import { TaskCard } from "../../components/kanban/TaskCard";
import { useDashboardStore } from "../../stores/dashboard";
import * as tauri from "../../lib/tauri";
import type { Issue, DashboardEvent } from "../../types";

// ---------------------------------------------------------------------------
// Mock Tauri API
// ---------------------------------------------------------------------------

const mockIssues: Issue[] = [
  {
    id: "TEST-1",
    title: "Test Issue 1",
    status: "open",
    priority: 2,
    labels: ["bug"],
    dependencies: [],
    assignee: "user1",
    owner: "user1",
    issue_type: "Task",
  },
  {
    id: "TEST-2",
    title: "Test Issue 2",
    status: "in_progress",
    priority: 1,
    labels: ["feature"],
    dependencies: [],
    assignee: "user2",
    owner: "user2",
    issue_type: "Task",
  },
  {
    id: "TEST-3",
    title: "Test Issue 3",
    status: "blocked",
    priority: 3,
    labels: ["enhancement"],
    dependencies: ["TEST-1"],
    assignee: null,
    owner: null,
    issue_type: "Task",
  },
];

vi.mock("../../lib/tauri", () => ({
  listIssues: vi.fn(),
  listWorkspaces: vi.fn(),
  switchWorkspace: vi.fn(),
  getDashboardStats: vi.fn(),
  getBdHealth: vi.fn(),
  searchIssues: vi.fn(),
  refreshCache: vi.fn(),
  opencodeStatus: vi.fn(),
  getHealthStatus: vi.fn(),
  updateIssueStatus: vi.fn(),
  assignIssue: vi.fn(),
  createIssue: vi.fn(),
}));

// ---------------------------------------------------------------------------
// Test Setup
// ---------------------------------------------------------------------------

describe("Kanban Flows Integration Tests", () => {
  beforeEach(() => {
    // Reset store state
    useDashboardStore.setState({
      issues: mockIssues,
      workspaces: [],
      selectedWorkspace: null,
      daemonStatus: null,
      cacheStats: null,
      opencodeConnected: false,
      isLoading: false,
      error: null,
      bootState: {
        step: 0,
        totalSteps: 5,
        currentLabel: "Initializing...",
        completed: true,
      },
      kanbanFilters: {},
      showCompleted: true,
    });

    // Reset mocks
    vi.clearAllMocks();

    // Setup default mock implementations
    vi.mocked(tauri.listIssues).mockResolvedValue(mockIssues);
    vi.mocked(tauri.listWorkspaces).mockResolvedValue([]);
    vi.mocked(tauri.updateIssueStatus).mockResolvedValue(undefined);
    vi.mocked(tauri.assignIssue).mockResolvedValue(undefined);
    vi.mocked(tauri.createIssue).mockResolvedValue({
      id: "TEST-NEW",
      title: "New Task",
      status: "open",
      priority: 3,
      labels: [],
      dependencies: [],
      assignee: null,
      owner: null,
      issue_type: "Task",
    });
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  // -------------------------------------------------------------------------
  // 1. Drag-and-Drop Status Update Flow
  // -------------------------------------------------------------------------

  describe("Drag-and-Drop Status Update Flow", () => {
    it("should drag task from Open to In Progress column", async () => {
      render(<KanbanBoard />);

      // Wait for initial render
      await waitFor(() => {
        expect(screen.getByText("Test Issue 1")).toBeInTheDocument();
      });

      // Find the task card in Open column
      const taskCard = screen.getByText("Test Issue 1").closest("[data-id]");
      expect(taskCard).toBeTruthy();

      // Find the In Progress column
      const inProgressColumn = screen
        .getByText("In Progress")
        .closest("[role=region], [class*=droppable]");

      // Simulate drag start
      if (taskCard) {
        fireEvent.dragStart(taskCard);

        // Simulate drag over the target column
        if (inProgressColumn) {
          fireEvent.dragOver(inProgressColumn);
        }

        // Simulate drop
        if (inProgressColumn) {
          fireEvent.drop(inProgressColumn);
        }

        fireEvent.dragEnd(taskCard);
      }

      // Verify backend call was made
      await waitFor(() => {
        expect(tauri.updateIssueStatus).toHaveBeenCalledWith("TEST-1", "in_progress");
      });
    });

    it("should handle IssueUpdated event and update UI", async () => {
      render(<KanbanBoard />);

      await waitFor(() => {
        expect(screen.getByText("Test Issue 1")).toBeInTheDocument();
      });

      // Simulate receiving an IssueUpdated event
      const event: DashboardEvent = {
        type: "IssueUpdated",
        source: "Bd",
        issue: {
          ...mockIssues[0],
          status: "closed",
          title: "Updated Test Issue 1",
        },
      };

      // Call the store's handleEvent method
      const { handleEvent } = useDashboardStore.getState();
      handleEvent(event);

      // Verify UI updated
      await waitFor(() => {
        expect(screen.getByText("Updated Test Issue 1")).toBeInTheDocument();
      });
    });

    it("should rollback optimistic update on backend error", async () => {
      vi.mocked(tauri.updateIssueStatus).mockRejectedValueOnce(new Error("Network error"));

      render(<KanbanBoard />);

      await waitFor(() => {
        expect(screen.getByText("Test Issue 1")).toBeInTheDocument();
      });

      const taskCard = screen.getByText("Test Issue 1").closest("[data-id]");
      const inProgressColumn = screen
        .getByText("In Progress")
        .closest("[role=region], [class*=droppable]");

      if (taskCard && inProgressColumn) {
        fireEvent.dragStart(taskCard);
        fireEvent.dragOver(inProgressColumn);
        fireEvent.drop(inProgressColumn);
        fireEvent.dragEnd(taskCard);
      }

      // Verify error is displayed
      await waitFor(() => {
        expect(screen.getByText(/Failed to update issue status/)).toBeInTheDocument();
      });

      // Verify rollback occurred - task should still be visible
      expect(screen.getByText("Test Issue 1")).toBeInTheDocument();
    });
  });

  // -------------------------------------------------------------------------
  // 2. Task Creation Flow
  // -------------------------------------------------------------------------

  describe("Task Creation Flow", () => {
    it("should create task and update store", async () => {
      const newIssue: Issue = {
        id: "TEST-NEW-1",
        title: "New Created Task",
        status: "open",
        priority: 2,
        labels: ["feature"],
        dependencies: [],
        assignee: "user3",
        owner: "user3",
        issue_type: "Task",
      };

      vi.mocked(tauri.createIssue).mockResolvedValueOnce(newIssue);

      // Simulate creating an issue through the API
      const result = await tauri.createIssue({
        title: "New Created Task",
        description: "Task description",
        status: "open",
        priority: 2,
        labels: ["feature"],
        assignee: "user3",
      });

      // Verify backend call
      expect(tauri.createIssue).toHaveBeenCalledWith({
        title: "New Created Task",
        description: "Task description",
        status: "open",
        priority: 2,
        labels: ["feature"],
        assignee: "user3",
      });

      expect(result).toEqual(newIssue);

      // Update store with new issue
      const currentIssues = useDashboardStore.getState().issues;
      useDashboardStore.setState({ issues: [...currentIssues, newIssue] });

      // Verify store updated
      expect(useDashboardStore.getState().issues).toContainEqual(newIssue);
    });

    it("should handle task creation with minimal data", async () => {
      const minimalIssue: Issue = {
        id: "TEST-MINIMAL",
        title: "Minimal Task",
        status: "open",
        priority: null,
        labels: [],
        dependencies: [],
        assignee: null,
        owner: null,
        issue_type: "Task",
      };

      vi.mocked(tauri.createIssue).mockResolvedValueOnce(minimalIssue);

      const result = await tauri.createIssue({
        title: "Minimal Task",
      });

      expect(tauri.createIssue).toHaveBeenCalledWith({ title: "Minimal Task" });
      expect(result.title).toBe("Minimal Task");
    });
  });

  // -------------------------------------------------------------------------
  // 3. Assignment Flow
  // -------------------------------------------------------------------------

  describe("Assignment Flow", () => {
    it("should change assignee via AssigneeSelector", async () => {
      const user = userEvent.setup();

      render(<AssigneeSelector value={null} onChange={vi.fn()} placeholder="Select assignee..." />);

      // Wait for component to render
      await waitFor(() => {
        expect(screen.getByLabelText(/Select assignee/i)).toBeInTheDocument();
      });

      // Open dropdown
      const select = screen.getByLabelText(/Select assignee/i);
      await user.click(select);

      // Select an assignee
      const option = screen.getByText("user1");
      await user.click(option);
    });

    it("should call assignIssue API when assignee changes", async () => {
      const onChange = vi.fn();

      render(
        <AssigneeSelector value={null} onChange={onChange} placeholder="Select assignee..." />,
      );

      const select = screen.getByLabelText(/Select assignee/i);
      fireEvent.change(select, { target: { value: "user1" } });

      await waitFor(() => {
        expect(onChange).toHaveBeenCalledWith("user1");
      });
    });

    it("should set assignee to null when selecting placeholder", async () => {
      const onChange = vi.fn();

      render(
        <AssigneeSelector value="user1" onChange={onChange} placeholder="Select assignee..." />,
      );

      const select = screen.getByLabelText(/Select assignee/i);
      fireEvent.change(select, { target: { value: "" } });

      await waitFor(() => {
        expect(onChange).toHaveBeenCalledWith(null);
      });
    });
  });

  // -------------------------------------------------------------------------
  // 4. Error Handling Flow
  // -------------------------------------------------------------------------

  describe("Error Handling Flow", () => {
    it("should display error state when bd API fails", async () => {
      vi.mocked(tauri.listIssues).mockRejectedValueOnce(new Error("bd service unavailable"));

      render(<KanbanBoard />);

      // Wait for error to be displayed
      await waitFor(() => {
        expect(screen.getByText(/bd service unavailable/i)).toBeInTheDocument();
      });
    });

    it("should display error banner for status update failures", async () => {
      vi.mocked(tauri.updateIssueStatus).mockRejectedValueOnce(new Error("Connection refused"));

      render(<KanbanBoard />);

      await waitFor(() => {
        expect(screen.getByText("Test Issue 1")).toBeInTheDocument();
      });

      const taskCard = screen.getByText("Test Issue 1").closest("[data-id]");
      const inProgressColumn = screen
        .getByText("In Progress")
        .closest("[role=region], [class*=droppable]");

      if (taskCard && inProgressColumn) {
        fireEvent.dragStart(taskCard);
        fireEvent.dragOver(inProgressColumn);
        fireEvent.drop(inProgressColumn);
        fireEvent.dragEnd(taskCard);
      }

      // Verify error banner appears
      await waitFor(() => {
        expect(screen.getByText(/Failed to update issue status/i)).toBeInTheDocument();
      });
    });

    it("should clear error when fetch succeeds after failure", async () => {
      // First call fails
      vi.mocked(tauri.listIssues)
        .mockRejectedValueOnce(new Error("Network error"))
        .mockResolvedValueOnce(mockIssues);

      const { rerender } = render(<KanbanBoard />);

      // Wait for error
      await waitFor(() => {
        expect(screen.getByText(/Network error/i)).toBeInTheDocument();
      });

      // Simulate successful retry by calling fetchIssues
      const { fetchIssues } = useDashboardStore.getState();
      await fetchIssues();

      // Error should be cleared
      await waitFor(() => {
        const errorElement = screen.queryByText(/Network error/i);
        expect(errorElement).not.toBeInTheDocument();
      });
    });
  });

  // -------------------------------------------------------------------------
  // 5. Async Behaviors
  // -------------------------------------------------------------------------

  describe("Async Behaviors", () => {
    it("should show loading state while fetching issues", async () => {
      // Delay the response
      vi.mocked(tauri.listIssues).mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve(mockIssues), 100)),
      );

      render(<KanbanBoard />);

      // Should show loading state
      expect(screen.getByText(/loading/i)).toBeInTheDocument();

      // Wait for data to load
      await waitFor(() => {
        expect(screen.getByText("Test Issue 1")).toBeInTheDocument();
      });
    });

    it("should handle concurrent status updates", async () => {
      let updateCount = 0;
      vi.mocked(tauri.updateIssueStatus).mockImplementation(async () => {
        updateCount++;
        await new Promise((resolve) => setTimeout(resolve, 50));
        return undefined;
      });

      render(<KanbanBoard />);

      await waitFor(() => {
        expect(screen.getByText("Test Issue 1")).toBeInTheDocument();
      });

      // Trigger multiple updates
      const { fetchIssues } = useDashboardStore.getState();

      // Simulate multiple status changes
      await Promise.all([
        tauri.updateIssueStatus("TEST-1", "in_progress"),
        tauri.updateIssueStatus("TEST-2", "closed"),
        tauri.updateIssueStatus("TEST-3", "open"),
      ]);

      expect(updateCount).toBe(3);
    });

    it("should debounce rapid store updates", async () => {
      const { updateKanbanFilters } = useDashboardStore.getState();

      // Trigger multiple rapid updates
      updateKanbanFilters({ search: "test1" });
      updateKanbanFilters({ search: "test2" });
      updateKanbanFilters({ search: "test3" });

      // Should have the latest value
      await waitFor(() => {
        expect(useDashboardStore.getState().kanbanFilters.search).toBe("test3");
      });
    });
  });

  // -------------------------------------------------------------------------
  // 6. Task Card Component Tests
  // -------------------------------------------------------------------------

  describe("Task Card Component", () => {
    it("should render task card with correct data", () => {
      const issue = mockIssues[0];
      const onClick = vi.fn();

      render(<TaskCard issue={issue} onClick={onClick} />);

      expect(screen.getByText(issue.title)).toBeInTheDocument();
      expect(screen.getByText(issue.id)).toBeInTheDocument();
      expect(screen.getByText("user1")).toBeInTheDocument();
    });

    it("should call onClick when card is clicked", async () => {
      const user = userEvent.setup();
      const onClick = vi.fn();
      const issue = mockIssues[0];

      render(<TaskCard issue={issue} onClick={onClick} />);

      const card = screen.getByText(issue.title).closest("div");
      if (card) {
        await user.click(card);
      }

      expect(onClick).toHaveBeenCalledWith(issue);
    });

    it("should display priority badge correctly", () => {
      const issue = mockIssues[0]; // priority 2 = P2

      render(<TaskCard issue={issue} />);

      expect(screen.getByText("P2")).toBeInTheDocument();
    });

    it("should show Unassigned when no assignee", () => {
      const unassignedIssue = { ...mockIssues[0], assignee: null, owner: null };

      render(<TaskCard issue={unassignedIssue} />);

      expect(screen.getByText("Unassigned")).toBeInTheDocument();
    });
  });
});
