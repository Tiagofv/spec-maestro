// Type-safe wrappers around Tauri invoke() for all registered commands.
// Command names must exactly match those in src-tauri/src/lib.rs invoke_handler.

import { invoke } from "@tauri-apps/api/core";
import type {
  Issue,
  EpicStatus,
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

export function listEpics(): Promise<EpicStatus[]> {
  return invoke<EpicStatus[]>("list_epics");
}

export function getEpicStatus(epicId: string): Promise<EpicStatus> {
  return invoke<EpicStatus>("get_epic_status", { epicId });
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

export function updateIssueStatus(id: string, status: string): Promise<void> {
  return invoke<void>("update_issue_status", { id, status });
}

export function assignIssue(id: string, assignee: string): Promise<void> {
  return invoke<void>("assign_issue", { id, assignee });
}

export function createIssue(issueData: CreateIssueRequest): Promise<Issue> {
  return invoke<Issue>("create_issue", {
    title: issueData.title,
    description: issueData.description,
    labels: issueData.labels,
    parentId: issueData.parentId,
  });
}
