// Type-safe wrappers around Tauri invoke() for all registered commands.
// Command names must exactly match those in src-tauri/src/lib.rs invoke_handler.

import { invoke } from "@tauri-apps/api/core";
import type {
  Issue,
  Workspace,
  CacheStats,
  OpencodeStatusResponse,
  HealthStatus,
  CreateIssueRequest,
} from "../types";

// ---------------------------------------------------------------------------
// bd commands
// ---------------------------------------------------------------------------

export function listIssues(): Promise<Issue[]> {
  return invoke<Issue[]>("list_issues");
}

export function listWorkspaces(): Promise<Workspace[]> {
  return invoke<Workspace[]>("list_workspaces");
}

export function switchWorkspace(path: string): Promise<void> {
  return invoke<void>("switch_workspace", { path });
}

export function getDashboardStats(): Promise<CacheStats> {
  return invoke<CacheStats>("get_dashboard_stats");
}

export function getBdHealth(): Promise<boolean> {
  return invoke<boolean>("get_bd_health");
}

export function searchIssues(query: string): Promise<Issue[]> {
  return invoke<Issue[]>("search_issues", { query });
}

export function refreshCache(): Promise<void> {
  return invoke<void>("refresh_cache");
}

// ---------------------------------------------------------------------------
// opencode commands
// ---------------------------------------------------------------------------

export function opencodeStatus(): Promise<OpencodeStatusResponse> {
  return invoke<OpencodeStatusResponse>("opencode_status");
}

// ---------------------------------------------------------------------------
// health commands
// ---------------------------------------------------------------------------

export function getHealthStatus(): Promise<HealthStatus> {
  return invoke<HealthStatus>("get_health_status");
}

// ---------------------------------------------------------------------------
// issue management commands
// ---------------------------------------------------------------------------

export function updateIssueStatus(issueId: string, status: string): Promise<void> {
  return invoke<void>("update_issue_status", { issueId, status });
}

export function assignIssue(issueId: string, assignee: string): Promise<void> {
  return invoke<void>("assign_issue", { issueId, assignee });
}

export function createIssue(issueData: CreateIssueRequest): Promise<Issue> {
  return invoke<Issue>("create_issue", issueData);
}
