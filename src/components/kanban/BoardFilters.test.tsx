import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { BoardFilters } from "./BoardFilters";
import type { EpicStatus, KanbanFilters } from "../../types";

// Mock the dashboard store
const mockStore: {
  kanbanFilters: KanbanFilters;
  showCompleted: boolean;
  filteredEpics: EpicStatus[];
  showClosedEpics: boolean;
  updateKanbanFilters: ReturnType<typeof vi.fn>;
  clearKanbanFilters: ReturnType<typeof vi.fn>;
  setShowCompleted: ReturnType<typeof vi.fn>;
  setShowClosedEpics: ReturnType<typeof vi.fn>;
} = {
  kanbanFilters: {},
  showCompleted: false,
  filteredEpics: [],
  showClosedEpics: false,
  updateKanbanFilters: vi.fn(),
  clearKanbanFilters: vi.fn(),
  setShowCompleted: vi.fn(),
  setShowClosedEpics: vi.fn(),
};

vi.mock("../../stores/dashboard", () => ({
  useDashboardStore: (selector: (state: typeof mockStore) => unknown) => selector(mockStore),
}));

describe("BoardFilters", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockStore.kanbanFilters = {};
    mockStore.showCompleted = false;
    mockStore.filteredEpics = [];
    mockStore.showClosedEpics = false;
  });

  describe("rendering", () => {
    it("renders search input", () => {
      render(<BoardFilters />);
      expect(screen.getByTestId("search-input")).toBeInTheDocument();
    });

    it("renders search input with correct placeholder", () => {
      render(<BoardFilters />);
      expect(screen.getByPlaceholderText("Search tasks...")).toBeInTheDocument();
    });

    it("renders show completed checkbox", () => {
      render(<BoardFilters />);
      expect(screen.getByTestId("show-completed-checkbox")).toBeInTheDocument();
    });

    it("renders 'Show completed' label", () => {
      render(<BoardFilters />);
      expect(screen.getByText("Show completed")).toBeInTheDocument();
    });

    it("does not render assignee filters when no assignees provided", () => {
      render(<BoardFilters />);
      expect(screen.queryByText("Assignee:")).not.toBeInTheDocument();
    });

    it("renders assignee filters when assignees provided", () => {
      render(<BoardFilters assignees={["user1", "user2"]} />);
      expect(screen.getByText("Assignee:")).toBeInTheDocument();
      expect(screen.getByTestId("assignee-filter-user1")).toBeInTheDocument();
      expect(screen.getByTestId("assignee-filter-user2")).toBeInTheDocument();
    });
  });

  describe("search functionality", () => {
    it("updates search filter when typing", () => {
      render(<BoardFilters />);
      const searchInput = screen.getByTestId("search-input");

      fireEvent.change(searchInput, { target: { value: "test query" } });

      expect(mockStore.updateKanbanFilters).toHaveBeenCalledWith({
        search: "test query",
      });
    });

    it("clears search when input is emptied", () => {
      mockStore.kanbanFilters = { search: "existing" };
      render(<BoardFilters />);
      const searchInput = screen.getByTestId("search-input");

      fireEvent.change(searchInput, { target: { value: "" } });

      expect(mockStore.updateKanbanFilters).toHaveBeenCalledWith({
        search: "",
      });
    });

    it("displays current search value from store", () => {
      mockStore.kanbanFilters = { search: "current search" };
      render(<BoardFilters />);
      const searchInput = screen.getByTestId("search-input") as HTMLInputElement;

      expect(searchInput.value).toBe("current search");
    });
  });

  describe("assignee filter functionality", () => {
    it("adds assignee when clicking unselected assignee", () => {
      mockStore.kanbanFilters = { assignee: [] };
      render(<BoardFilters assignees={["user1", "user2"]} />);

      fireEvent.click(screen.getByTestId("assignee-filter-user1"));

      expect(mockStore.updateKanbanFilters).toHaveBeenCalledWith({
        assignee: ["user1"],
      });
    });

    it("removes assignee when clicking selected assignee", () => {
      mockStore.kanbanFilters = { assignee: ["user1", "user2"] };
      render(<BoardFilters assignees={["user1", "user2"]} />);

      fireEvent.click(screen.getByTestId("assignee-filter-user1"));

      expect(mockStore.updateKanbanFilters).toHaveBeenCalledWith({
        assignee: ["user2"],
      });
    });

    it("handles single assignee removal", () => {
      mockStore.kanbanFilters = { assignee: ["user1"] };
      render(<BoardFilters assignees={["user1"]} />);

      fireEvent.click(screen.getByTestId("assignee-filter-user1"));

      expect(mockStore.updateKanbanFilters).toHaveBeenCalledWith({
        assignee: [],
      });
    });
  });

  describe("show completed toggle", () => {
    it("calls setShowCompleted when checkbox is clicked", () => {
      render(<BoardFilters />);
      const checkbox = screen.getByTestId("show-completed-checkbox");

      fireEvent.click(checkbox);

      expect(mockStore.setShowCompleted).toHaveBeenCalledWith(true);
    });

    it("reflects current showCompleted state", () => {
      mockStore.showCompleted = true;
      render(<BoardFilters />);
      const checkbox = screen.getByTestId("show-completed-checkbox") as HTMLInputElement;

      expect(checkbox.checked).toBe(true);
    });

    it("toggles off when clicked again", () => {
      mockStore.showCompleted = true;
      render(<BoardFilters />);
      const checkbox = screen.getByTestId("show-completed-checkbox");

      fireEvent.click(checkbox);

      expect(mockStore.setShowCompleted).toHaveBeenCalledWith(false);
    });
  });

  describe("clear filters", () => {
    it("does not render clear button when no filters active", () => {
      mockStore.kanbanFilters = {};
      render(<BoardFilters />);
      expect(screen.queryByTestId("clear-filters-button")).not.toBeInTheDocument();
    });

    it("renders clear button when search filter is active", () => {
      mockStore.kanbanFilters = { search: "test" };
      render(<BoardFilters />);
      expect(screen.getByTestId("clear-filters-button")).toBeInTheDocument();
    });

    it("renders clear button when assignee filter is active", () => {
      mockStore.kanbanFilters = { assignee: ["user1"] };
      render(<BoardFilters />);
      expect(screen.getByTestId("clear-filters-button")).toBeInTheDocument();
    });

    it("calls clearKanbanFilters when clear button is clicked", () => {
      mockStore.kanbanFilters = { search: "test" };
      render(<BoardFilters />);

      fireEvent.click(screen.getByTestId("clear-filters-button"));

      expect(mockStore.clearKanbanFilters).toHaveBeenCalled();
    });
  });

  describe("state changes", () => {
    it("handles multiple filter changes sequentially", () => {
      mockStore.kanbanFilters = {};
      render(<BoardFilters assignees={["user1", "user2"]} />);

      // Add search
      fireEvent.change(screen.getByTestId("search-input"), {
        target: { value: "query" },
      });
      expect(mockStore.updateKanbanFilters).toHaveBeenCalledWith({
        search: "query",
      });

      // Add assignee
      vi.clearAllMocks();
      mockStore.kanbanFilters = { search: "query" };
      fireEvent.click(screen.getByTestId("assignee-filter-user1"));
      expect(mockStore.updateKanbanFilters).toHaveBeenCalledWith({
        assignee: ["user1"],
      });

      // Toggle completed
      fireEvent.click(screen.getByTestId("show-completed-checkbox"));
      expect(mockStore.setShowCompleted).toHaveBeenCalledWith(true);
    });

    it("preserves other filters when updating one", () => {
      mockStore.kanbanFilters = {
        search: "existing",
        assignee: ["user1"],
      };
      render(<BoardFilters assignees={["user1", "user2"]} />);

      // Add another assignee
      fireEvent.click(screen.getByTestId("assignee-filter-user2"));

      // The component reads from store, so it should include existing filters
      expect(mockStore.updateKanbanFilters).toHaveBeenCalled();
    });
  });

  describe("edge cases", () => {
    it("handles empty assignees array", () => {
      render(<BoardFilters assignees={[]} />);
      expect(screen.queryByText("Assignee:")).not.toBeInTheDocument();
    });

    it("handles single assignee", () => {
      render(<BoardFilters assignees={["solo"]} />);
      expect(screen.getByTestId("assignee-filter-solo")).toBeInTheDocument();
    });

    it("handles many assignees", () => {
      const manyAssignees = Array.from({ length: 10 }, (_, i) => `user${i}`);
      render(<BoardFilters assignees={manyAssignees} />);

      manyAssignees.forEach((assignee) => {
        expect(screen.getByTestId(`assignee-filter-${assignee}`)).toBeInTheDocument();
      });
    });

    it("handles special characters in search", () => {
      render(<BoardFilters />);
      const searchInput = screen.getByTestId("search-input");

      fireEvent.change(searchInput, {
        target: { value: "test <special> & chars" },
      });

      expect(mockStore.updateKanbanFilters).toHaveBeenCalledWith({
        search: "test <special> & chars",
      });
    });

    it("handles special characters in assignee names", () => {
      render(<BoardFilters assignees={["user@example.com", "user.name"]} />);
      expect(screen.getByTestId("assignee-filter-user@example.com")).toBeInTheDocument();
      expect(screen.getByTestId("assignee-filter-user.name")).toBeInTheDocument();
    });

    it("handles null assignee array in filters", () => {
      mockStore.kanbanFilters = { assignee: undefined };
      render(<BoardFilters assignees={["user1"]} />);

      fireEvent.click(screen.getByTestId("assignee-filter-user1"));

      expect(mockStore.updateKanbanFilters).toHaveBeenCalledWith({
        assignee: ["user1"],
      });
    });
  });
});
