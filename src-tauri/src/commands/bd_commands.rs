use crate::bd::WorkspaceDiscovery;
use crate::cache::{DagGraph};
use crate::state::AppState;
use std::path::PathBuf;
use tauri::Emitter;
use tracing::info;

/// Lists all issues in the current workspace.
///
/// Returns a vector of Issue objects with their status, priority, labels, dependencies, etc.
#[tauri::command]
pub async fn list_issues(state: tauri::State<'_, AppState>) -> Result<Vec<crate::bd::types::Issue>, String> {
    let bd_client = state.bd_client.read().await;
    bd_client
        .list_issues()
        .await
        .map_err(|e| format!("Failed to list issues: {}", e))
}

/// Get details for a specific issue.
///
/// # Arguments
/// * `id` - The issue ID (e.g., "my-project-abc.1")
#[tauri::command]
pub async fn get_issue(
    state: tauri::State<'_, AppState>,
    id: String,
) -> Result<crate::bd::types::Issue, String> {
    let bd_client = state.bd_client.read().await;
    bd_client
        .get_issue(&id)
        .await
        .map_err(|e| format!("Failed to get issue {}: {}", id, e))
}

/// Lists all gates for the current issue.
///
/// Gates are quality checkpoints that must be resolved before proceeding.
#[tauri::command]
pub async fn list_gates(state: tauri::State<'_, AppState>) -> Result<Vec<crate::bd::types::Gate>, String> {
    let bd_client = state.bd_client.read().await;
    bd_client
        .list_gates()
        .await
        .map_err(|e| format!("Failed to list gates: {}", e))
}

/// Resolve a gate with a provided reason.
///
/// # Arguments
/// * `id` - The gate ID to resolve
/// * `reason` - The reason/justification for resolving the gate
#[tauri::command]
pub async fn resolve_gate(
    state: tauri::State<'_, AppState>,
    app: tauri::AppHandle,
    id: String,
    reason: String,
) -> Result<crate::bd::types::Gate, String> {
    use crate::tray::notify_new_approval;

    let bd_client = state.bd_client.read().await;
    let resolved_gate = bd_client
        .resolve_gate(&id, &reason)
        .await
        .map_err(|e| format!("Failed to resolve gate {}: {}", id, e))?;

    // Send notification that gate was resolved
    notify_new_approval(
        &app,
        "Gate Resolved",
        &format!("Gate {} has been resolved", id),
    );

    info!("Gate {} resolved with reason: {}", id, reason);

    Ok(resolved_gate)
}

/// Get the DAG (Directed Acyclic Graph) for an epic.
///
/// # Arguments
/// * `epic_id` - The epic ID to build the DAG for
///
/// Returns a graph representation with nodes (issues, gates) and edges (dependencies).
#[tauri::command]
pub async fn get_dag(
    state: tauri::State<'_, AppState>,
    epic_id: String,
) -> Result<DagGraph, String> {
    let cache = state.beads_cache.read().await;
    cache
        .get_dag(&epic_id)
        .await
        .map_err(|e| format!("Failed to get DAG for epic {}: {}", epic_id, e))?
        .ok_or_else(|| format!("No DAG found for epic {}", epic_id))
}

/// Lists all registered bd workspaces.
///
/// Discovers workspaces from `~/.beads/registry.json` and checks their daemon status.
#[tauri::command]
pub async fn list_workspaces(_state: tauri::State<'_, AppState>) -> Result<Vec<crate::bd::types::Workspace>, String> {
    WorkspaceDiscovery::discover()
        .await
        .map_err(|e| format!("Failed to list workspaces: {}", e))
}

/// Switch to a different workspace.
///
/// # Arguments
/// * `path` - The path to the workspace directory
///
/// Creates a new BdClient for the given workspace path and updates AppState.
#[tauri::command]
pub async fn switch_workspace(
    state: tauri::State<'_, AppState>,
    path: String,
) -> Result<(), String> {
    let path_buf = PathBuf::from(&path);

    // Verify workspace exists
    if !path_buf.exists() || !path_buf.is_dir() {
        return Err(format!("Workspace path does not exist or is not a directory: {}", path));
    }

    info!("Switching to workspace: {}", path);
    state.switch_bd_client(path_buf).await
}

/// Get dashboard statistics from the cache.
///
/// Returns aggregated statistics about issues, gates, and cache sync status.
#[tauri::command]
pub async fn get_dashboard_stats(state: tauri::State<'_, AppState>) -> Result<crate::cache::CacheStats, String> {
    let cache = state.beads_cache.read().await;
    cache
        .get_stats()
        .await
        .map_err(|e| format!("Failed to get dashboard stats: {}", e))
}

/// Check the health of the bd daemon.
///
/// Returns true if the daemon is running and responding, false otherwise.
#[tauri::command]
pub async fn get_bd_health(state: tauri::State<'_, AppState>) -> Result<bool, String> {
    let bd_client = state.bd_client.read().await;
    bd_client
        .daemon_status()
        .await
        .map(|status| status.running)
        .map_err(|e| format!("Failed to check bd health: {}", e))
}

/// Lists all ready (available) issues.
///
/// Returns issues that are ready to be worked on (no unmet dependencies).
#[tauri::command]
pub async fn list_ready(state: tauri::State<'_, AppState>) -> Result<Vec<crate::bd::types::Issue>, String> {
    let bd_client = state.bd_client.read().await;
    bd_client
        .list_ready()
        .await
        .map_err(|e| format!("Failed to list ready issues: {}", e))
}

/// Get the status of an epic.
///
/// # Arguments
/// * `epic_id` - The epic ID to get status for
///
/// Returns statistics about total, open, closed, in-progress, and blocked issues in the epic.
#[tauri::command]
pub async fn get_epic_status(
    state: tauri::State<'_, AppState>,
    epic_id: String,
) -> Result<crate::bd::types::EpicStatus, String> {
    let bd_client = state.bd_client.read().await;
    bd_client
        .get_epic_status(&epic_id)
        .await
        .map_err(|e| format!("Failed to get epic status for {}: {}", epic_id, e))
}

/// Start the bd daemon for the current workspace.
#[tauri::command]
pub async fn start_bd_daemon(state: tauri::State<'_, AppState>) -> Result<crate::bd::types::DaemonStatus, String> {
    let bd_client = state.bd_client.read().await;
    let status = bd_client
        .daemon_start()
        .await
        .map_err(|e| format!("Failed to start bd daemon: {}", e))?;

    info!("Bd daemon started, running={}", status.running);
    Ok(status)
}

/// Search issues by title or status.
///
/// # Arguments
/// * `query` - The search query string
///
/// Returns issues matching the query in title or status field.
#[tauri::command]
pub async fn search_issues(
    state: tauri::State<'_, AppState>,
    query: String,
) -> Result<Vec<crate::bd::types::Issue>, String> {
    let cache = state.beads_cache.read().await;
    let results = cache.search_issues(&query).await;
    Ok(results)
}

/// Get an issue by ID from the cache.
///
/// # Arguments
/// * `id` - The issue ID to retrieve
#[tauri::command]
pub async fn get_cached_issue(
    state: tauri::State<'_, AppState>,
    id: String,
) -> Result<Option<crate::bd::types::Issue>, String> {
    let cache = state.beads_cache.read().await;
    let issue = cache.get_issue(&id).await;
    Ok(issue)
}

/// List all epics.
///
/// Returns all epics in the cache.
#[tauri::command]
pub async fn list_epics(state: tauri::State<'_, AppState>) -> Result<Vec<crate::bd::types::EpicStatus>, String> {
    let cache = state.beads_cache.read().await;
    let epics = cache.list_epics().await;
    Ok(epics)
}

/// Get an epic by ID from the cache.
///
/// # Arguments
/// * `id` - The epic ID to retrieve
#[tauri::command]
pub async fn get_cached_epic(
    state: tauri::State<'_, AppState>,
    id: String,
) -> Result<Option<crate::bd::types::EpicStatus>, String> {
    let cache = state.beads_cache.read().await;
    let epic = cache.get_epic(&id).await;
    Ok(epic)
}

/// Get pending gates (gates requiring human approval).
#[tauri::command]
pub async fn get_pending_gates(state: tauri::State<'_, AppState>) -> Result<Vec<crate::bd::types::Gate>, String> {
    let cache = state.beads_cache.read().await;
    cache
        .get_pending_gates()
        .await
        .map_err(|e| format!("Failed to get pending gates: {}", e))
}

/// Test helper/integration function: Lists issues directly from cache without Tauri State wrapper.
pub async fn list_issues_from_cache(state: &AppState) -> Result<Vec<crate::bd::types::Issue>, String> {
    let cache = state.beads_cache.read().await;
    Ok(cache.list_issues().await)
}

/// Test helper/integration function: Gets an issue directly from cache without Tauri State wrapper.
pub async fn get_issue_from_cache(state: &AppState, id: &str) -> Result<Option<crate::bd::types::Issue>, String> {
    let cache = state.beads_cache.read().await;
    Ok(cache.get_issue(id).await)
}

/// Test helper/integration function: Gets DAG from cache without Tauri State wrapper.
pub async fn get_dag_from_cache(state: &AppState, epic_id: &str) -> Result<Option<DagGraph>, String> {
    let cache = state.beads_cache.read().await;
    cache
        .get_dag(epic_id)
        .await
        .map_err(|e| format!("Failed to get DAG: {}", e))
}

/// Test helper/integration function: Gets pending gates from cache without Tauri State wrapper.
pub async fn get_pending_gates_from_cache(state: &AppState) -> Result<Vec<crate::bd::types::Gate>, String> {
    let cache = state.beads_cache.read().await;
    cache
        .get_pending_gates()
        .await
        .map_err(|e| format!("Failed to get pending gates: {}", e))
}

/// Test helper/integration function: Gets epic status from cache without Tauri State wrapper.
pub async fn get_epic_status_from_cache(state: &AppState, epic_id: &str) -> Result<Option<crate::bd::types::EpicStatus>, String> {
    let cache = state.beads_cache.read().await;
    Ok(cache.get_epic(epic_id).await)
}

/// Test helper/integration function: Gets dashboard stats from cache without Tauri State wrapper.
pub async fn get_dashboard_stats_from_cache(state: &AppState) -> Result<crate::cache::CacheStats, String> {
    let cache = state.beads_cache.read().await;
    cache
        .get_stats()
        .await
        .map_err(|e| format!("Failed to get stats: {}", e))
}

/// Test helper/integration function: Searches issues from cache without Tauri State wrapper.
pub async fn search_issues_from_cache(state: &AppState, query: &str) -> Result<Vec<crate::bd::types::Issue>, String> {
    let cache = state.beads_cache.read().await;
    Ok(cache.search_issues(query).await)
}

/// Update an issue's status.
///
/// # Arguments
/// * `id` - The issue ID to update
/// * `status` - The new status value
///
/// Emits an IssueUpdated event on success.
#[tauri::command]
pub async fn update_issue_status(
    state: tauri::State<'_, AppState>,
    app: tauri::AppHandle,
    id: String,
    status: String,
) -> Result<crate::bd::types::Issue, String> {
    use crate::events::{DashboardEvent, EventSource};

    let bd_client = state.bd_client.read().await;
    let issue = bd_client
        .update_issue_status(&id, &status)
        .await
        .map_err(|e| format!("Failed to update issue {} status: {}", id, e))?;

    // Emit IssueUpdated event
    let event = DashboardEvent::IssueUpdated {
        source: EventSource::Bd,
        issue: issue.clone(),
    };
    if let Err(e) = app.emit("dashboard-event", event) {
        tracing::warn!("Failed to emit IssueUpdated event: {}", e);
    }

    info!("Updated issue {} status to {}", id, status);
    Ok(issue)
}

/// Assign an issue to a user.
///
/// # Arguments
/// * `id` - The issue ID to assign
/// * `assignee` - The user to assign the issue to
///
/// Emits an IssueUpdated event on success.
#[tauri::command]
pub async fn assign_issue(
    state: tauri::State<'_, AppState>,
    app: tauri::AppHandle,
    id: String,
    assignee: String,
) -> Result<crate::bd::types::Issue, String> {
    use crate::events::{DashboardEvent, EventSource};

    let bd_client = state.bd_client.read().await;
    let issue = bd_client
        .assign_issue(&id, &assignee)
        .await
        .map_err(|e| format!("Failed to assign issue {}: {}", id, e))?;

    // Emit IssueUpdated event
    let event = DashboardEvent::IssueUpdated {
        source: EventSource::Bd,
        issue: issue.clone(),
    };
    if let Err(e) = app.emit("dashboard-event", event) {
        tracing::warn!("Failed to emit IssueUpdated event: {}", e);
    }

    info!("Assigned issue {} to {}", id, assignee);
    Ok(issue)
}

/// Create a new issue.
///
/// # Arguments
/// * `title` - The issue title
/// * `description` - Optional issue description
/// * `labels` - Optional list of labels
/// * `parent_id` - Optional parent issue ID
///
/// Emits an IssueUpdated event on success.
#[tauri::command]
pub async fn create_issue(
    state: tauri::State<'_, AppState>,
    app: tauri::AppHandle,
    title: String,
    description: Option<String>,
    labels: Option<Vec<String>>,
    parent_id: Option<String>,
) -> Result<crate::bd::types::Issue, String> {
    use crate::events::{DashboardEvent, EventSource};

    let bd_client = state.bd_client.read().await;

    // Convert labels Vec<String> to &[&str] for the client method
    let labels_ref: Option<Vec<&str>> = labels.as_ref().map(|v| {
        v.iter().map(|s| s.as_str()).collect()
    });
    let labels_slice = labels_ref.as_deref();

    let issue = bd_client
        .create_issue(&title, description.as_deref(), labels_slice, parent_id.as_deref(), None)
        .await
        .map_err(|e| format!("Failed to create issue: {}", e))?;

    // Emit IssueUpdated event
    let event = DashboardEvent::IssueUpdated {
        source: EventSource::Bd,
        issue: issue.clone(),
    };
    if let Err(e) = app.emit("dashboard-event", event) {
        tracing::warn!("Failed to emit IssueUpdated event: {}", e);
    }

    info!("Created issue: {}", issue.id);
    Ok(issue)
}

#[cfg(test)]
mod tests {
    use crate::cache::CacheStats;

    #[test]
    fn test_cache_stats_serialization() {
        let stats = CacheStats {
            total_issues: 10,
            open: 3,
            closed: 5,
            in_progress: 1,
            blocked: 1,
            pending_gates: 2,
            last_sync: "5s".to_string(),
        };
        let json = serde_json::to_string(&stats).unwrap();
        assert!(json.contains("total_issues"));
        assert!(json.contains("10"));
    }

    #[test]
    fn test_workspace_serialization() {
        use std::collections::HashMap;
        let mut extra = HashMap::new();
        extra.insert("description".to_string(), serde_json::json!("My project"));

        let workspace = crate::bd::types::Workspace {
            path: "/home/user/project".to_string(),
            name: "project".to_string(),
            daemon_running: true,
            extra,
        };
        let json = serde_json::to_string(&workspace).unwrap();
        assert!(json.contains("path"));
        assert!(json.contains("project"));
        assert!(json.contains("daemon_running"));
    }
}
