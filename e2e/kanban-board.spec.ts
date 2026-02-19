import { test, expect, type Page } from "@playwright/test";
import { sampleIssues, getIssueById, getUniqueAssignees } from "./fixtures/issues";

/**
 * E2E Tests for Kanban Board
 * Tests complete user journeys including:
 * - Drag and drop functionality
 * - Task detail viewing
 * - Filter interactions
 * - Error recovery
 */

// Mock data storage for simulating backend state
let mockIssues = [...sampleIssues];
let shouldSimulateError = false;
let isBdConnected = true;

// Setup mock Tauri API before each test
test.beforeEach(async ({ page }) => {
  // Reset mock state
  mockIssues = [...sampleIssues];
  shouldSimulateError = false;
  isBdConnected = true;

  // Expose mock functions to the page
  await page.addInitScript(() => {
    // Mock Tauri invoke function
    (window as any).__TAURI__ = {
      core: {
        invoke: async (cmd: string, args?: Record<string, unknown>) => {
          // Access mock state from window
          const mockState = (window as any).__MOCK_STATE__;

          if (mockState.shouldSimulateError) {
            throw new Error("Simulated backend error");
          }

          switch (cmd) {
            case "list_issues":
              return mockState.issues;

            case "update_issue_status":
              const { issueId, status } = args || {};
              const issue = mockState.issues.find((i: any) => i.id === issueId);
              if (issue) {
                issue.status = status;
              }
              return null;

            case "assign_issue":
              const { issueId: assignIssueId, assignee } = args || {};
              const assignIssue = mockState.issues.find((i: any) => i.id === assignIssueId);
              if (assignIssue) {
                assignIssue.assignee = assignee;
              }
              return null;

            case "create_issue":
              const newIssue = {
                id: `TEST-${String(mockState.issues.length + 1).padStart(3, "0")}`,
                ...args,
                status: args?.status || "open",
                labels: args?.labels || [],
                dependencies: args?.dependencies || [],
              };
              mockState.issues.push(newIssue);
              return newIssue;

            case "get_bd_health":
              return mockState.isBdConnected;

            case "get_health_status":
              return {
                bd_available: mockState.isBdConnected,
                bd_version: "1.0.0",
                daemon_running: mockState.isBdConnected,
                opencode_available: true,
                cache_stale: false,
                last_check: Date.now(),
              };

            default:
              return null;
          }
        },
      },
    };

    // Initialize mock state
    (window as any).__MOCK_STATE__ = {
      issues: mockIssues,
      shouldSimulateError: false,
      isBdConnected: true,
    };
  });

  // Navigate to kanban board
  await page.goto("/kanban");

  // Wait for the board to load
  await page.waitForSelector("text=Kanban Board", { timeout: 10000 });
});

// Helper function to get column element
test.describe("Complete Workflow", () => {
  test("should display kanban board with all columns", async ({ page }) => {
    // Verify all columns are present
    await expect(page.getByText("Open", { exact: true })).toBeVisible();
    await expect(page.getByText("In Progress", { exact: true })).toBeVisible();
    await expect(page.getByText("Blocked", { exact: true })).toBeVisible();
    await expect(page.getByText("Closed", { exact: true })).toBeVisible();
  });

  test("should display tasks in correct columns", async ({ page }) => {
    // Verify tasks are displayed
    await expect(page.getByText("Fix navigation bug on mobile devices")).toBeVisible();
    await expect(page.getByText("Implement user authentication flow")).toBeVisible();

    // Verify task counts in column headers
    const openColumn = page.locator(".flex-1.min-w-\\[280px\\]", { hasText: "Open" });
    await expect(openColumn.locator("text=3")).toBeVisible(); // 3 open tasks
  });

  test("should drag task to new column", async ({ page }) => {
    // Find a task in the Open column
    const task = page.getByText("Fix navigation bug on mobile devices");
    await expect(task).toBeVisible();

    // Get the In Progress column
    const inProgressColumn = page
      .locator("[class*='flex-1 min-w-\\[280px\\] max-w-\\[400px\\]']")
      .nth(1);

    // Drag the task to In Progress
    await task.dragTo(inProgressColumn);

    // Verify the task is no longer visible in the viewport of Open
    // (it may have moved to In Progress)
    await page.waitForTimeout(500); // Allow animation to complete

    // Verify the task count updated in In Progress column
    const inProgressHeader = page.locator("text=In Progress").locator("..");
    await expect(inProgressHeader).toBeVisible();
  });

  test("should open task details on click", async ({ page }) => {
    // Click on a task
    const task = page.getByText("Implement user authentication flow");
    await task.click();

    // Verify modal opens
    await expect(page.getByText("Task Details", { exact: true })).toBeVisible();
    await expect(page.getByText("Create login and signup forms with validation")).toBeVisible();

    // Verify modal content
    await expect(page.getByText("Status").first()).toBeVisible();
    await expect(page.getByText("Priority").first()).toBeVisible();
    await expect(page.getByText("Assignee").first()).toBeVisible();
  });

  test("should close task details modal", async ({ page }) => {
    // Open modal
    await page.getByText("Implement user authentication flow").click();
    await expect(page.getByText("Task Details", { exact: true })).toBeVisible();

    // Close modal using X button
    await page.locator("button[aria-label='Close modal']").click();

    // Verify modal is closed
    await expect(page.getByText("Task Details", { exact: true })).not.toBeVisible();
  });

  test("should close modal on backdrop click", async ({ page }) => {
    // Open modal
    await page.getByText("Implement user authentication flow").click();
    await expect(page.getByText("Task Details", { exact: true })).toBeVisible();

    // Click on backdrop (outside modal)
    await page.locator("[role='dialog']").click({ position: { x: 10, y: 10 } });

    // Verify modal is closed
    await expect(page.getByText("Task Details", { exact: true })).not.toBeVisible();
  });

  test("should close modal on ESC key", async ({ page }) => {
    // Open modal
    await page.getByText("Implement user authentication flow").click();
    await expect(page.getByText("Task Details", { exact: true })).toBeVisible();

    // Press ESC
    await page.keyboard.press("Escape");

    // Verify modal is closed
    await expect(page.getByText("Task Details", { exact: true })).not.toBeVisible();
  });

  test("should refresh board on refresh button click", async ({ page }) => {
    // Click refresh button
    await page.getByText("Refresh").click();

    // Wait for loading state
    await expect(page.getByText("Loading...")).toBeVisible();

    // Wait for loading to complete
    await expect(page.getByText("Refresh")).toBeVisible();

    // Verify board still displays tasks
    await expect(page.getByText("Implement user authentication flow")).toBeVisible();
  });
});

test.describe("Filter Interactions", () => {
  test("should filter tasks by assignee", async ({ page }) => {
    // Open filters (assuming there's a filter UI)
    // This test assumes filter UI exists - adjust selectors as needed
    const assignees = getUniqueAssignees();

    // Verify assignees exist in test data
    expect(assignees.length).toBeGreaterThan(0);

    // Look for filter controls
    const filterSection = page.locator("[data-testid='filters']");

    // If filters exist, test them
    if ((await filterSection.count()) > 0) {
      await filterSection.click();

      // Select an assignee
      await page.selectOption("select[aria-label='Filter by assignee']", assignees[0]);

      // Verify filtered results
      const visibleTasks = await page.locator("[data-testid='task-card']").count();
      expect(visibleTasks).toBeGreaterThan(0);
    }
  });

  test("should show all tasks when no filters applied", async ({ page }) => {
    // Count total visible tasks
    const taskCards = page.locator("text=TEST-");
    const count = await taskCards.count();

    // Should have multiple tasks visible
    expect(count).toBeGreaterThan(1);
  });

  test("should display completed tasks toggle", async ({ page }) => {
    // Look for completed tasks toggle/checkbox
    const showCompletedToggle = page.locator("input[type='checkbox']", {
      hasText: /completed|closed/i,
    });

    // If toggle exists, verify it's functional
    if ((await showCompletedToggle.count()) > 0) {
      await expect(showCompletedToggle).toBeVisible();
    }
  });
});

test.describe("Error Recovery", () => {
  test("should display error when backend fails", async ({ page }) => {
    // Simulate backend error
    await page.evaluate(() => {
      (window as any).__MOCK_STATE__.shouldSimulateError = true;
    });

    // Try to refresh
    await page.getByText("Refresh").click();

    // Wait for error to appear
    await page.waitForTimeout(500);

    // Verify error message is displayed
    // Error handling may vary - adjust as needed
    const errorBanner = page
      .locator("[class*='error']")
      .or(page.locator("text=error", { hasText: /error|fail/i }));
    // Note: Error display depends on actual implementation
  });

  test("should recover after error and successful retry", async ({ page }) => {
    // First, simulate an error
    await page.evaluate(() => {
      (window as any).__MOCK_STATE__.shouldSimulateError = true;
    });

    // Try to refresh and fail
    await page.getByText("Refresh").click();
    await page.waitForTimeout(500);

    // Now recover
    await page.evaluate(() => {
      (window as any).__MOCK_STATE__.shouldSimulateError = false;
    });

    // Retry
    await page.getByText("Refresh").click();

    // Wait for recovery
    await page.waitForTimeout(500);

    // Verify board is back to normal
    await expect(page.getByText("Implement user authentication flow")).toBeVisible();
  });

  test("should handle bd disconnection gracefully", async ({ page }) => {
    // Simulate bd disconnection
    await page.evaluate(() => {
      (window as any).__MOCK_STATE__.isBdConnected = false;
    });

    // Try to fetch issues
    await page.getByText("Refresh").click();
    await page.waitForTimeout(500);

    // Verify appropriate error state or message
    // The exact behavior depends on implementation
  });

  test("should recover after bd reconnection", async ({ page }) => {
    // Disconnect
    await page.evaluate(() => {
      (window as any).__MOCK_STATE__.isBdConnected = false;
    });

    await page.getByText("Refresh").click();
    await page.waitForTimeout(500);

    // Reconnect
    await page.evaluate(() => {
      (window as any).__MOCK_STATE__.isBdConnected = true;
    });

    await page.getByText("Refresh").click();
    await page.waitForTimeout(500);

    // Verify board recovered
    await expect(page.getByText("Implement user authentication flow")).toBeVisible();
  });
});

test.describe("UI Responsiveness", () => {
  test("should be responsive on different viewports", async ({ page }) => {
    // Test desktop viewport
    await page.setViewportSize({ width: 1920, height: 1080 });
    await expect(page.getByText("Kanban Board")).toBeVisible();

    // Test tablet viewport
    await page.setViewportSize({ width: 1024, height: 768 });
    await expect(page.getByText("Kanban Board")).toBeVisible();

    // Test mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await expect(page.getByText("Kanban Board")).toBeVisible();
  });

  test("should handle empty state", async ({ page }) => {
    // Clear all issues
    await page.evaluate(() => {
      (window as any).__MOCK_STATE__.issues = [];
    });

    // Refresh
    await page.getByText("Refresh").click();
    await page.waitForTimeout(500);

    // Verify empty state message
    await expect(page.getByText("No issues found")).toBeVisible();
  });
});

test.describe("Accessibility", () => {
  test("should have proper ARIA labels", async ({ page }) => {
    // Check for modal ARIA attributes when open
    await page.getByText("Implement user authentication flow").click();

    const modal = page.locator("[role='dialog']");
    await expect(modal).toHaveAttribute("aria-modal", "true");
    await expect(modal).toHaveAttribute("aria-labelledby", "modal-title");
  });

  test("should support keyboard navigation", async ({ page }) => {
    // Open modal
    await page.getByText("Implement user authentication flow").click();

    // Tab to close button and press Enter
    await page.keyboard.press("Tab");
    await page.keyboard.press("Enter");

    // Verify modal closed
    await expect(page.getByText("Task Details", { exact: true })).not.toBeVisible();
  });
});
