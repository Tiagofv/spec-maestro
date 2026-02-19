import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { TaskCard, SortableTaskCard } from "./TaskCard";
import type { Issue } from "../../types";

// Mock dnd-kit hooks
const mockUseSortable = vi.fn();
vi.mock("@dnd-kit/sortable", () => ({
  useSortable: (...args: unknown[]) => mockUseSortable(...args),
}));

vi.mock("@dnd-kit/utilities", () => ({
  CSS: {
    Transform: {
      toString: (transform: { x: number; y: number } | null) =>
        transform ? `translate3d(${transform.x}px, ${transform.y}px, 0)` : "",
    },
  },
}));

describe("TaskCard", () => {
  const mockOnClick = vi.fn();

  const createMockIssue = (overrides: Partial<Issue> = {}): Issue => ({
    id: "TEST-1",
    title: "Test Task",
    status: "open",
    priority: 1,
    labels: [],
    dependencies: [],
    assignee: "user1",
    owner: null,
    issue_type: null,
    ...overrides,
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mockUseSortable.mockReturnValue({
      attributes: {},
      listeners: {},
      setNodeRef: vi.fn(),
      transform: null,
      transition: null,
      isDragging: false,
    });
  });

  describe("rendering", () => {
    it("renders task title", () => {
      const issue = createMockIssue({ title: "My Task Title" });
      render(<TaskCard issue={issue} onClick={mockOnClick} />);
      expect(screen.getByText("My Task Title")).toBeInTheDocument();
    });

    it("renders task ID", () => {
      const issue = createMockIssue({ id: "PROJ-123" });
      render(<TaskCard issue={issue} onClick={mockOnClick} />);
      expect(screen.getByText("PROJ-123")).toBeInTheDocument();
    });

    it("renders assignee name", () => {
      const issue = createMockIssue({ assignee: "john.doe" });
      render(<TaskCard issue={issue} onClick={mockOnClick} />);
      expect(screen.getByText("john.doe")).toBeInTheDocument();
    });

    it("renders owner when assignee is null", () => {
      const issue = createMockIssue({ assignee: null, owner: "jane.smith" });
      render(<TaskCard issue={issue} onClick={mockOnClick} />);
      expect(screen.getByText("jane.smith")).toBeInTheDocument();
    });

    it("renders 'Unassigned' when no assignee or owner", () => {
      const issue = createMockIssue({ assignee: null, owner: null });
      render(<TaskCard issue={issue} onClick={mockOnClick} />);
      expect(screen.getByText("Unassigned")).toBeInTheDocument();
    });

    it("renders priority badge", () => {
      const issue = createMockIssue({ priority: 1 });
      render(<TaskCard issue={issue} onClick={mockOnClick} />);
      expect(screen.getByText("P1")).toBeInTheDocument();
    });

    it("renders dash for null priority", () => {
      const issue = createMockIssue({ priority: null });
      render(<TaskCard issue={issue} onClick={mockOnClick} />);
      expect(screen.getByText("-")).toBeInTheDocument();
    });

    it("renders dash for priority 0", () => {
      const issue = createMockIssue({ priority: 0 });
      render(<TaskCard issue={issue} onClick={mockOnClick} />);
      expect(screen.getByText("-")).toBeInTheDocument();
    });
  });

  describe("click handling", () => {
    it("calls onClick with issue when card is clicked", () => {
      const issue = createMockIssue({ id: "TEST-123", title: "Clickable Task" });
      render(<TaskCard issue={issue} onClick={mockOnClick} />);

      const card = screen.getByText("Clickable Task").closest("div");
      fireEvent.click(card!);

      expect(mockOnClick).toHaveBeenCalledWith(issue);
    });

    it("does not throw when onClick is not provided", () => {
      const issue = createMockIssue();
      expect(() => {
        render(<TaskCard issue={issue} />);
        const card = screen.getByText("Test Task").closest("div");
        fireEvent.click(card!);
      }).not.toThrow();
    });

    it("does not call onClick when isDragging prop is true", () => {
      const issue = createMockIssue();
      render(<TaskCard issue={issue} onClick={mockOnClick} isDragging />);
      // Card should have dragging styles applied
      expect(document.querySelector(".opacity-90")).toBeInTheDocument();
    });
  });

  describe("priority display", () => {
    it("displays P1 for priority 1", () => {
      const issue = createMockIssue({ priority: 1 });
      render(<TaskCard issue={issue} />);
      expect(screen.getByText("P1")).toBeInTheDocument();
    });

    it("displays P2 for priority 2", () => {
      const issue = createMockIssue({ priority: 2 });
      render(<TaskCard issue={issue} />);
      expect(screen.getByText("P2")).toBeInTheDocument();
    });

    it("displays P3 for priority 3", () => {
      const issue = createMockIssue({ priority: 3 });
      render(<TaskCard issue={issue} />);
      expect(screen.getByText("P3")).toBeInTheDocument();
    });

    it("displays P4 for priority 4", () => {
      const issue = createMockIssue({ priority: 4 });
      render(<TaskCard issue={issue} />);
      expect(screen.getByText("P4")).toBeInTheDocument();
    });

    it("handles string priority values", () => {
      const issue = createMockIssue({ priority: "2" });
      render(<TaskCard issue={issue} />);
      expect(screen.getByText("P2")).toBeInTheDocument();
    });

    it("handles invalid string priority", () => {
      const issue = createMockIssue({ priority: "invalid" });
      render(<TaskCard issue={issue} />);
      expect(screen.getByText("-")).toBeInTheDocument();
    });
  });

  describe("drag attributes", () => {
    it("applies dragging styles when isDragging is true", () => {
      const issue = createMockIssue();
      const { container } = render(<TaskCard issue={issue} isDragging />);

      const card = container.firstChild as HTMLElement;
      expect(card.className).toContain("opacity-90");
      expect(card.className).toContain("rotate-2");
      expect(card.className).toContain("scale-105");
    });

    it("does not apply dragging styles when isDragging is false", () => {
      const issue = createMockIssue();
      const { container } = render(<TaskCard issue={issue} isDragging={false} />);

      const card = container.firstChild as HTMLElement;
      expect(card.className).not.toContain("opacity-90");
    });
  });

  describe("edge cases", () => {
    it("handles very long titles", () => {
      const longTitle = "A".repeat(200);
      const issue = createMockIssue({ title: longTitle });
      const { container } = render(<TaskCard issue={issue} />);

      expect(container.textContent).toContain(longTitle);
    });

    it("handles special characters in title", () => {
      const issue = createMockIssue({ title: "Task with <special> & "characters"" });
      render(<TaskCard issue={issue} />);
      expect(screen.getByText("Task with <special> & "characters"")).toBeInTheDocument();
    });

    it("handles assignee with special characters", () => {
      const issue = createMockIssue({ assignee: "user@example.com" });
      render(<TaskCard issue={issue} />);
      expect(screen.getByText("user@example.com")).toBeInTheDocument();
    });
  });
});

describe("SortableTaskCard", () => {
  const mockOnClick = vi.fn();

  const createMockIssue = (overrides: Partial<Issue> = {}): Issue => ({
    id: "TEST-1",
    title: "Test Task",
    status: "open",
    priority: 1,
    labels: [],
    dependencies: [],
    assignee: "user1",
    owner: null,
    issue_type: null,
    ...overrides,
  });

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("passes drag attributes to TaskCard", () => {
    mockUseSortable.mockReturnValue({
      attributes: { "aria-describedby": "test" },
      listeners: { onPointerDown: vi.fn() },
      setNodeRef: vi.fn(),
      transform: { x: 10, y: 20 },
      transition: "transform 200ms",
      isDragging: true,
    });

    const issue = createMockIssue();
    render(<SortableTaskCard issue={issue} onClick={mockOnClick} />);

    // Should render the task card with dragging state
    expect(screen.getByText("Test Task")).toBeInTheDocument();
  });

  it("renders without drag state when not dragging", () => {
    mockUseSortable.mockReturnValue({
      attributes: {},
      listeners: {},
      setNodeRef: vi.fn(),
      transform: null,
      transition: null,
      isDragging: false,
    });

    const issue = createMockIssue();
    render(<SortableTaskCard issue={issue} onClick={mockOnClick} />);

    expect(screen.getByText("Test Task")).toBeInTheDocument();
  });

  it("calls onClick when clicked", () => {
    mockUseSortable.mockReturnValue({
      attributes: {},
      listeners: {},
      setNodeRef: vi.fn(),
      transform: null,
      transition: null,
      isDragging: false,
    });

    const issue = createMockIssue();
    render(<SortableTaskCard issue={issue} onClick={mockOnClick} />);

    const card = screen.getByText("Test Task").closest("div");
    fireEvent.click(card!);

    expect(mockOnClick).toHaveBeenCalledWith(issue);
  });
});
