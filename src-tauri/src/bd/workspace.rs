use super::error::{BdError, BdResult};
use super::types::Workspace;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use tracing::{debug, info, warn};

/// Entry in the beads registry for a single workspace.
///
/// The registry at `~/.beads/registry.json` is a JSON array of these entries.
/// Each entry contains the workspace path and daemon metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct RegistryEntry {
    /// Absolute path to the workspace directory.
    pub workspace_path: String,
    /// Additional metadata (socket_path, database_path, pid, version, started_at).
    #[serde(flatten)]
    pub extra: HashMap<String, Value>,
}

/// Discovers and manages registered bd workspaces.
///
/// Reads `~/.beads/registry.json` to find registered workspaces and provides
/// utilities to check their daemon status.
pub struct WorkspaceDiscovery;

impl WorkspaceDiscovery {
    /// Path to the beads registry file.
    const REGISTRY_FILE: &'static str = ".beads/registry.json";

    /// Discover all registered workspaces.
    ///
    /// Reads `~/.beads/registry.json` and returns a list of workspaces with
    /// their daemon status checked.
    ///
    /// # Errors
    ///
    /// Returns `BdError::IoError` if the registry file cannot be read or
    /// `BdError::ParseError` if the file is not valid JSON.
    pub async fn discover() -> BdResult<Vec<Workspace>> {
        let registry_path = Self::get_registry_path()?;
        info!("Reading workspace registry from: {:?}", registry_path);

        let entries = Self::load_registry(&registry_path)?;
        let mut workspaces = Vec::new();

        for entry in entries {
            debug!("Discovered workspace: {}", entry.workspace_path);

            // Extract workspace name from directory path
            let workspace_name = Self::extract_name(&entry.workspace_path);

            // Check daemon status (best effort - continue on failure)
            let daemon_running = Self::check_daemon_status(&entry.workspace_path).await.unwrap_or(false);

            workspaces.push(Workspace {
                path: entry.workspace_path.clone(),
                name: workspace_name,
                daemon_running,
                extra: entry.extra,
            });
        }

        info!("Discovered {} workspaces, {} with daemon running",
              workspaces.len(),
              workspaces.iter().filter(|w| w.daemon_running).count());

        Ok(workspaces)
    }

    /// Get the absolute path to the registry file.
    fn get_registry_path() -> BdResult<PathBuf> {
        let home = dirs::home_dir()
            .ok_or_else(|| BdError::DaemonError("Failed to determine home directory".to_string()))?;

        Ok(home.join(Self::REGISTRY_FILE))
    }

    /// Load and parse the registry file.
    ///
    /// The registry is a JSON array of workspace entries (bd 0.47+).
    fn load_registry(path: &Path) -> BdResult<Vec<RegistryEntry>> {
        let json = std::fs::read_to_string(path).map_err(|e| {
            BdError::ParseError(format!("Failed to read registry file: {}", e))
        })?;

        let entries: Vec<RegistryEntry> = serde_json::from_str(&json).map_err(|e| {
            BdError::ParseError(format!("Failed to parse registry: {}", e))
        })?;

        Ok(entries)
    }

    /// Extract workspace name from path.
    ///
    /// Uses the directory name as the workspace display name.
    fn extract_name(path: &str) -> String {
        let path_buf = PathBuf::from(path);
        path_buf
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or(path)
            .to_string()
    }

    /// Check if the bd daemon is running for a workspace.
    ///
    /// Creates a temporary BdClient and checks daemon status.
    /// Returns `false` on any error (including workspace not found).
    async fn check_daemon_status(path: &str) -> BdResult<bool> {
        let path_buf = PathBuf::from(path);

        // Verify workspace exists
        if !path_buf.exists() || !path_buf.is_dir() {
            warn!("Workspace path does not exist or is not a directory: {}", path);
            return Ok(false);
        }

        // Try to create BdClient and check daemon status
        match super::client::BdClient::new(path_buf) {
            Ok(client) => {
                // The daemon_status() method is async, so we await it directly
                match client.daemon_status().await {
                    Ok(status) => Ok(status.running),
                    Err(e) => {
                        debug!("Failed to check daemon status for {}: {:?}", path, e);
                        Ok(false)
                    }
                }
            }
            Err(e) => {
                debug!("Failed to create BdClient for {}: {:?}", path, e);
                Ok(false)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn test_extract_name() {
        assert_eq!(
            WorkspaceDiscovery::extract_name("/home/user/projects/my-project"),
            "my-project"
        );
        assert_eq!(
            WorkspaceDiscovery::extract_name("/tmp/my-project"),
            "my-project"
        );
    }

    #[tokio::test]
    async fn test_load_registry() {
        let dir = tempdir().unwrap();
        let registry_path = dir.path().join("registry.json");

        let registry_data = json!([
            {
                "workspace_path": "/home/user/project1",
                "socket_path": "/home/user/project1/.beads/bd.sock",
                "database_path": "/home/user/project1/.beads/beads.db",
                "pid": 1234,
                "version": "0.47.1",
                "started_at": "2026-01-01T00:00:00Z"
            },
            {
                "workspace_path": "/home/user/project2",
                "socket_path": "/home/user/project2/.beads/bd.sock",
                "database_path": "/home/user/project2/.beads/beads.db",
                "pid": 5678,
                "version": "0.47.1",
                "started_at": "2026-01-01T00:00:00Z"
            }
        ]);

        fs::write(&registry_path, registry_data.to_string()).unwrap();

        let entries = WorkspaceDiscovery::load_registry(&registry_path).unwrap();
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].workspace_path, "/home/user/project1");
        assert_eq!(entries[1].workspace_path, "/home/user/project2");
    }

    #[tokio::test]
    async fn test_discover_missing_registry() {
        let home = dirs::home_dir().unwrap();
        let test_registry_path = home.join(".beads/test-registry.json");

        // Ensure file doesn't exist
        let _ = std::fs::remove_file(&test_registry_path);

        // Try to load non-existent registry
        let result = WorkspaceDiscovery::load_registry(&test_registry_path);
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_check_daemon_status_nonexistent_path() {
        let result = WorkspaceDiscovery::check_daemon_status("/nonexistent/path/12345").await;
        assert!(result.is_ok());
        assert!(!result.unwrap());
    }
}
