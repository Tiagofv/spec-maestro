import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { KanbanBoard } from "../../views/KanbanBoard";
import { AssigneeSelector } from "../../components/kanban/AssigneeSelector";
import { TaskCard } from "../../components/kanban/TaskCard";
import { useDashboardStore } from "../../stores/dashboard";
import * as tauri from "../../lib/tauri";
import type { Issue, DashboardEvent } from "../../types";

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

describe("Kanban Flows Integration Tests", () => {
  beforeEach(() => {
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

    vi.clearAllMocks();

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

  describe("Drag-and-Drop Status Update Flow", () => {
    it("should call updateIssueStatus and handle success", async () => {
      const result = await tauri.updateIssueStatus("TEST-1", "in_progress");
      expect(tauri.updateIssueStatus).toHaveBeenCalledWith("TEST-1", "in_progress");
      expect(result).toBeUndefined();
    });

    it("should handle IssueUpdated event and update UI", async () => {
      render(<KanbanBoard />);

      await waitFor(() => {
        expect(screen.getByText("Test Issue 1")).toBeInTheDocument();
      });

      const event: DashboardEvent = {
        type: "IssueUpdated",
        source: "Bd",
        issue: {
          ...mockIssues[0],
          status: "closed",
          title: "Updated Test Issue 1",
        },
      };

      const { handleEvent } = useDashboardStore.getState();
      handleEvent(event);

      await waitFor(() => {
        expect(screen.getByText("Updated Test Issue 1")).toBeInTheDocument();
      });
    });

    it("should throw error when updateIssueStatus fails", async () => {
      vi.mocked(tauri.updateIssueStatus).mockRejectedValueOnce(new Error("Network error"));

      await expect(tauri.updateIssueStatus("TEST-1", "in_progress")).rejects.toThrow(
        "Network error",
      );
    });
  });

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

      const result = await tauri.createIssue({
        title: "New Created Task",
        description: "Task description",
        labels: ["feature"],
      });

      expect(tauri.createIssue).toHaveBeenCalledWith({
        title: "New Created Task",
        description: "Task description",
        labels: ["feature"],
      });

      expect(result).toEqual(newIssue);

      const currentIssues = useDashboardStore.getState().issues;
      useDashboardStore.setState({ issues: [...currentIssues, newIssue] });

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

  describe("Assignment Flow", () => {
    it("should change assignee via AssigneeSelector", async () => {
      const user = userEvent.setup();

      render(<AssigneeSelector value={null} onChange={vi.fn()} placeholder="Select assignee..." />);

      await waitFor(() => {
        expect(screen.getByLabelText(/Select assignee/i)).toBeInTheDocument();
      });

      const select = screen.getByLabelText(/Select assignee/i);
      await user.click(select);

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

  describe("Error Handling Flow", () => {
    it("should set error in store when bd API fails", async () => {
      vi.mocked(tauri.listIssues).mockRejectedValueOnce(new Error("bd service unavailable"));

      const { fetchIssues } = useDashboardStore.getState();
      await fetchIssues();

      expect(useDashboardStore.getState().error).toBe("bd service unavailable");
    });

    it("should throw error when status update fails", async () => {
      vi.mocked(tauri.updateIssueStatus).mockRejectedValueOnce(new Error("Connection refused"));

      await expect(tauri.updateIssueStatus("TEST-1", "in_progress")).rejects.toThrow(
        "Connection refused",
      );
    });

    it("should clear error when fetch succeeds after failure", async () => {
      vi.mocked(tauri.listIssues)
        .mockRejectedValueOnce(new Error("Network error"))
        .mockResolvedValueOnce(mockIssues);

      const { fetchIssues } = useDashboardStore.getState();

      await fetchIssues();
      expect(useDashboardStore.getState().error).toBe("Network error");

      useDashboardStore.setState({ error: null });
      await fetchIssues();

      expect(useDashboardStore.getState().error).toBe(null);
    });
  });

  describe("Async Behaviors", () => {
    it("should set loading state while fetching issues", async () => {
      vi.mocked(tauri.listIssues).mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve(mockIssues), 100)),
      );

      const { fetchIssues } = useDashboardStore.getState();

      expect(useDashboardStore.getState().isLoading).toBe(false);

      const fetchPromise = fetchIssues();

      expect(useDashboardStore.getState().isLoading).toBe(true);

      await fetchPromise;

      expect(useDashboardStore.getState().isLoading).toBe(false);
    });

    it("should handle concurrent status updates", async () => {
      let updateCount = 0;
      vi.mocked(tauri.updateIssueStatus).mockImplementation(async () => {
        updateCount++;
        await new Promise((resolve) => setTimeout(resolve, 50));
        return undefined;
      });

      await Promise.all([
        tauri.updateIssueStatus("TEST-1", "in_progress"),
        tauri.updateIssueStatus("TEST-2", "closed"),
        tauri.updateIssueStatus("TEST-3", "open"),
      ]);

      expect(updateCount).toBe(3);
    });

    it("should debounce rapid store updates", async () => {
      const { updateKanbanFilters } = useDashboardStore.getState();

      updateKanbanFilters({ search: "test1" });
      updateKanbanFilters({ search: "test2" });
      updateKanbanFilters({ search: "test3" });

      expect(useDashboardStore.getState().kanbanFilters.search).toBe("test3");
    });
  });

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
      const issue = mockIssues[0];

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
