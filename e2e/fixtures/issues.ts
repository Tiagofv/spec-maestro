import type { Issue } from "../../src/types";

/**
 * Test fixtures with sample issues for E2E testing
 */

export const sampleIssues: Issue[] = [
  {
    id: "TEST-001",
    title: "Implement user authentication flow",
    status: "in_progress",
    priority: 1,
    labels: ["feature", "auth"],
    dependencies: [],
    assignee: "john.doe",
    owner: "john.doe",
    issue_type: "Task",
    description: "Create login and signup forms with validation",
  },
  {
    id: "TEST-002",
    title: "Fix navigation bug on mobile devices",
    status: "open",
    priority: 2,
    labels: ["bug", "mobile"],
    dependencies: [],
    assignee: "jane.smith",
    owner: "jane.smith",
    issue_type: "Bug",
    description: "Menu doesn't collapse properly on screens < 768px",
  },
  {
    id: "TEST-003",
    title: "Update documentation for API v2",
    status: "closed",
    priority: 3,
    labels: ["docs"],
    dependencies: [],
    assignee: null,
    owner: "bob.wilson",
    issue_type: "Task",
    description: "Add examples for new endpoints",
  },
  {
    id: "TEST-004",
    title: "Database migration script",
    status: "blocked",
    priority: 1,
    labels: ["database", "migration"],
    dependencies: ["TEST-001"],
    assignee: "john.doe",
    owner: "john.doe",
    issue_type: "Task",
    description: "Migrate user data to new schema",
  },
  {
    id: "TEST-005",
    title: "Add unit tests for utility functions",
    status: "open",
    priority: 4,
    labels: ["testing"],
    dependencies: [],
    assignee: "jane.smith",
    owner: null,
    issue_type: "Task",
    description: "Achieve 80% coverage for utils folder",
  },
  {
    id: "TEST-006",
    title: "Optimize image loading performance",
    status: "open",
    priority: 2,
    labels: ["performance", "frontend"],
    dependencies: [],
    assignee: null,
    owner: null,
    issue_type: "Feature",
    description: "Implement lazy loading for images",
  },
  {
    id: "TEST-007",
    title: "Set up CI/CD pipeline",
    status: "in_progress",
    priority: 1,
    labels: ["devops", "ci-cd"],
    dependencies: [],
    assignee: "bob.wilson",
    owner: "bob.wilson",
    issue_type: "Epic",
    description: "Configure GitHub Actions for automated testing and deployment",
  },
  {
    id: "TEST-008",
    title: "Security audit findings",
    status: "open",
    priority: 1,
    labels: ["security"],
    dependencies: [],
    assignee: null,
    owner: "security.team",
    issue_type: "Bug",
    description: "Address vulnerabilities identified in security audit",
  },
];

/**
 * Get issues filtered by status
 */
export function getIssuesByStatus(status: string): Issue[] {
  return sampleIssues.filter((issue) => issue.status === status);
}

/**
 * Get issues filtered by assignee
 */
export function getIssuesByAssignee(assignee: string): Issue[] {
  return sampleIssues.filter((issue) => issue.assignee === assignee || issue.owner === assignee);
}

/**
 * Get issue by ID
 */
export function getIssueById(id: string): Issue | undefined {
  return sampleIssues.find((issue) => issue.id === id);
}

/**
 * Get unique assignees from sample issues
 */
export function getUniqueAssignees(): string[] {
  const assignees = new Set<string>();
  sampleIssues.forEach((issue) => {
    if (issue.assignee) assignees.add(issue.assignee);
    if (issue.owner) assignees.add(issue.owner);
  });
  return Array.from(assignees).sort();
}
