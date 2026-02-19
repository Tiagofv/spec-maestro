# E2E Tests for Kanban Board

This directory contains end-to-end tests for the Kanban Board feature using Playwright.

## Structure

```
e2e/
├── fixtures/
│   └── issues.ts          # Test data and fixtures
├── kanban-board.spec.ts  # Main E2E test file
├── tsconfig.json         # TypeScript configuration for E2E tests
└── README.md            # This file
```

## Running Tests

```bash
# Run all E2E tests
pnpm test:e2e

# Run tests in UI mode (interactive)
pnpm test:e2e:ui

# Run tests in debug mode
pnpm test:e2e:debug

# Run specific test file
pnpm exec playwright test e2e/kanban-board.spec.ts
```

## Test Scenarios

### Complete Workflow

- Display kanban board with all columns
- Display tasks in correct columns
- Drag task to new column
- Open task details on click
- Close task details modal
- Refresh board

### Filter Interactions

- Filter by assignee
- Show/hide completed tasks
- Clear filters

### Error Recovery

- Handle backend errors
- Recover after error
- Handle bd disconnection
- Recover after reconnection

### UI & Accessibility

- Responsive design
- Empty state handling
- Keyboard navigation
- ARIA labels

## Test Fixtures

Sample issues are defined in `fixtures/issues.ts` and include:

- Various statuses (open, in_progress, blocked, closed)
- Different priorities (P1-P4)
- Multiple assignees
- Labels and dependencies

## Mocking

The tests mock the Tauri backend API using `page.addInitScript()` to:

- Simulate different backend states
- Test error conditions
- Control data responses
- Test disconnection scenarios
