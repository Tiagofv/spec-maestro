import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { KanbanColumn } from "./KanbanColumn";
import type { Issue } from "../../types";

// Mock dnd-kit hooks
vi.mock("@dnd-kit/core", () => ({
  useDroppable: () => ({
    isOver: false,
    setNodeRef: vi.fn(),
  }),
}));

vi.mock("./TaskCard", () => ({
  SortableTaskCard: ({ issue, onClick }: { issue: Issue; onClick?: (issue: Issue) => void }) => (
    <div
      data-testid={`task-card-${issue.id}`}
      onClick={() => onClick?.(issue)}
      role="button"
      tabIndex={0}
    >
      {issue.title}
    </div>
  ),
}));

describe("KanbanColumn", () => {
  const mockOnTaskClick = vi.fn();

  const createMockIssue = (
    id: string,
    title: string,
    status: string,
    priority: number | null,
  ): Issue => ({
    id,
    title,
    status,
    priority,
    labels: [],
    dependencies: [],
    assignee: null,
    owner: null,
    issue_type: null,
  });

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe("rendering", () => {
    it("renders column with label", () => {
      render(
        <KanbanColumn
          id="open"
          label="Open"
          color="bg-blue-500/15 text-blue-400"
          issues={[]}
          onTaskClick={mockOnTaskClick}
        />,
      );
      expect(screen.getByText("Open")).toBeInTheDocument();
    });

    it("displays task count in header", () => {
      const issues = [
        createMockIssue("TEST-1", "Task 1", "open", 1),
        createMockIssue("TEST-2", "Task 2", "open", 2),
      ];
      render(
        <KanbanColumn
          id="open"
          label="Open"
          color="bg-blue-500/15 text-blue-400"
          issues={issues}
          onTaskClick={mockOnTaskClick}
        />,
      );
      expect(screen.getByText("2")).toBeInTheDocument();
    });

    it("displays zero count when no tasks", () => {
      render(
        <KanbanColumn
          id="open"
          label="Open"
          color="bg-blue-500/15 text-blue-400"
          issues={[]}
          onTaskClick={mockOnTaskClick}
        />,
      );
      expect(screen.getByText("0")).toBeInTheDocument();
    });
  });

  describe("task grouping", () => {
    it("renders all tasks in the column", () => {
      const issues = [
        createMockIssue("TEST-1", "Task 1", "open", 1),
        createMockIssue("TEST-2", "Task 2", "open", 2),
        createMockIssue("TEST-3", "Task 3", "open", 3),
      ];
      render(
        <KanbanColumn
          id="open"
          label="Open"
          color="bg-blue-500/15 text-blue-400"
          issues={issues}
          onTaskClick={mockOnTaskClick}
        />,
      );

      expect(screen.getByTestId("task-card-TEST-1")).toBeInTheDocument();
      expect(screen.getByTestId("task-card-TEST-2")).toBeInTheDocument();
      expect(screen.getByTestId("task-card-TEST-3")).toBeInTheDocument();
    });

    it("renders tasks in order provided", () => {
      const issues = [
        createMockIssue("TEST-1", "First Task", "open", 1),
        createMockIssue("TEST-2", "Second Task", "open", 2),
        createMockIssue("TEST-3", "Third Task", "open", 3),
      ];
      const { container } = render(
        <KanbanColumn
          id="open"
          label="Open"
          color="bg-blue-500/15 text-blue-400"
          issues={issues}
          onTaskClick={mockOnTaskClick}
        />,
      );

      const taskCards = container.querySelectorAll("[data-testid^='task-card-']");
      expect(taskCards).toHaveLength(3);
      expect(taskCards[0].textContent).toBe("First Task");
      expect(taskCards[1].textContent).toBe("Second Task");
      expect(taskCards[2].textContent).toBe("Third Task");
    });
  });

  describe("empty state", () => {
    it("displays 'No tasks' message when column is empty", () => {
      render(
        <KanbanColumn
          id="open"
          label="Open"
          color="bg-blue-500/15 text-blue-400"
          issues={[]}
          onTaskClick={mockOnTaskClick}
        />,
      );
      expect(screen.getByText("No tasks")).toBeInTheDocument();
    });

    it("does not display 'No tasks' when column has tasks", () => {
      const issues = [createMockIssue("TEST-1", "Task 1", "open", 1)];
      render(
        <KanbanColumn
          id="open"
          label="Open"
          color="bg-blue-500/15 text-blue-400"
          issues={issues}
          onTaskClick={mockOnTaskClick}
        />,
      );
      expect(screen.queryByText("No tasks")).not.toBeInTheDocument();
    });
  });

  describe("click handling", () => {
    it("calls onTaskClick when task card is clicked", () => {
      const issues = [createMockIssue("TEST-1", "Task 1", "open", 1)];
      render(
        <KanbanColumn
          id="open"
          label="Open"
          color="bg-blue-500/15 text-blue-400"
          issues={issues}
          onTaskClick={mockOnTaskClick}
        />,
      );

      const taskCard = screen.getByTestId("task-card-TEST-1");
      fireEvent.click(taskCard);

      expect(mockOnTaskClick).toHaveBeenCalledWith(issues[0]);
    });

    it("does not throw when onTaskClick is not provided", () => {
      const issues = [createMockIssue("TEST-1", "Task 1", "open", 1)];
      expect(() => {
        render(
          <KanbanColumn
            id="open"
            label="Open"
            color="bg-blue-500/15 text-blue-400"
            issues={issues}
          />,
        );
        const taskCard = screen.getByTestId("task-card-TEST-1");
        fireEvent.click(taskCard);
      }).not.toThrow();
    });
  });

  describe("edge cases", () => {
    it("handles single task in column", () => {
      const issues = [createMockIssue("TEST-1", "Only Task", "open", 1)];
      render(
        <KanbanColumn
          id="open"
          label="Open"
          color="bg-blue-500/15 text-blue-400"
          issues={issues}
          onTaskClick={mockOnTaskClick}
        />,
      );

      expect(screen.getByTestId("task-card-TEST-1")).toBeInTheDocument();
      expect(screen.getByText("1")).toBeInTheDocument();
    });

    it("handles tasks with null priority", () => {
      const issues = [
        createMockIssue("TEST-1", "Task 1", "open", null),
        createMockIssue("TEST-2", "Task 2", "open", null),
      ];
      render(
        <KanbanColumn
          id="open"
          label="Open"
          color="bg-blue-500/15 text-blue-400"
          issues={issues}
          onTaskClick={mockOnTaskClick}
        />,
      );

      expect(screen.getByTestId("task-card-TEST-1")).toBeInTheDocument();
      expect(screen.getByTestId("task-card-TEST-2")).toBeInTheDocument();
    });

    it("handles tasks with string priority", () => {
      const issues = [
        {
          ...createMockIssue("TEST-1", "Task 1", "open", 1),
          priority: "1",
        },
      ];
      render(
        <KanbanColumn
          id="open"
          label="Open"
          color="bg-blue-500/15 text-blue-400"
          issues={issues}
          onTaskClick={mockOnTaskClick}
        />,
      );

      expect(screen.getByTestId("task-card-TEST-1")).toBeInTheDocument();
    });

    it("preserves issue data structure", () => {
      const issues: Issue[] = [
        {
          id: "TEST-1",
          title: "Full Task",
          status: "open",
          priority: 1,
          labels: ["bug", "urgent"],
          dependencies: ["TEST-0"],
          assignee: "user1",
          owner: "user2",
          issue_type: "Bug",
        },
      ];
      render(
        <KanbanColumn
          id="open"
          label="Open"
          color="bg-blue-500/15 text-blue-400"
          issues={issues}
          onTaskClick={mockOnTaskClick}
        />,
      );

      fireEvent.click(screen.getByTestId("task-card-TEST-1"));
      expect(mockOnTaskClick).toHaveBeenCalledWith(
        expect.objectContaining({
          id: "TEST-1",
          title: "Full Task",
          labels: ["bug", "urgent"],
          assignee: "user1",
          owner: "user2",
        }),
      );
    });
  });
});
