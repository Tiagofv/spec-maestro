use super::error::{BdError, BdResult};
use super::types::DaemonStatus;
use crate::bd::BdClient;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tokio::time::sleep;
use tracing::{debug, info, warn};

const DAEMON_SOCKET_PATH: &str = ".beads/bd.sock";

const DAEMON_START_TIMEOUT: Duration = Duration::from_secs(30);

/// Manager for the bd daemon lifecycle.
///
/// Ensures the bd daemon is running for the current workspace and provides
/// methods to check status and stop the daemon. Uses the existing BdClient
/// for daemon operations.
pub struct DaemonManager {
    /// Workspace directory
    workspace: PathBuf,
    /// Path to the bd CLI binary
    bd_path: PathBuf,
}

impl DaemonManager {
    /// Create a new DaemonManager with auto-detected bd binary.
    ///
    /// # Errors
    ///
    /// Returns `BdError::CliNotFound` if bd cannot be found.
    pub fn new(workspace: PathBuf) -> BdResult<Self> {
        let bd_path = Self::find_bd_binary()?;
        Ok(Self { workspace, bd_path })
    }

    /// Auto-detect the bd binary path.
    fn find_bd_binary() -> BdResult<PathBuf> {
        let checked_paths = vec![
            "bd".to_string(),
            dirs::home_dir()
                .map(|h| h.join(".local/bin/bd"))
                .and_then(|p| p.to_str().map(|s| s.to_string()))
                .unwrap_or_else(|| "~/.local/bin/bd".to_string()),
        ];

        for path in &checked_paths {
            debug!("Searching for bd at: {}", path);

            if which::which(path).is_ok() {
                return Ok(PathBuf::from(path));
            }

            let abs_path = PathBuf::from(path);
            if abs_path.exists() && abs_path.is_file() {
                return Ok(abs_path);
            }
        }

        Err(BdError::CliNotFound { checked_paths })
    }

    /// Create a new DaemonManager with a custom bd binary path.
    pub fn with_bd_path(workspace: PathBuf, bd_path: PathBuf) -> Result<Self, BdError> {
        if !bd_path.exists() {
            return Err(BdError::CliNotFound {
                checked_paths: vec![bd_path.to_string_lossy().to_string()],
            });
        }

        Ok(Self { workspace, bd_path })
    }

    /// Ensure the bd daemon is running for the workspace.
    ///
    /// Checks the daemon status, and if not running, starts it with `--local` flag.
    /// Verifies that the daemon socket `.beads/bd.sock` exists after starting.
    ///
    /// # Arguments
    ///
    /// * `workspace` - Path to the workspace directory (redundant with constructor, kept for API flexibility)
    ///
    /// # Example
    ///
    /// ```no_run
    /// # use agent_maestro::bd::DaemonManager;
    /// # use std::path::PathBuf;
    /// # async fn demo() -> Result<(), Box<dyn std::error::Error>> {
    /// let workspace = PathBuf::from("/path/to/workspace");
    /// let manager = DaemonManager::new(workspace.clone())?;
    /// manager.ensure_running(&workspace).await?;
    /// # Ok(())
    /// # }
    /// ```
    pub async fn ensure_running(&self, _workspace: &Path) -> BdResult<()> {
        let client = BdClient::with_bd_path(self.workspace.clone(), self.bd_path.clone())?;

        let status = client.daemon_status().await?;
        debug!(
            "Daemon status check: running={}, pid={:?}",
            status.running, status.pid
        );

        if status.running {
            info!("Daemon is already running");
            return Ok(());
        }

        warn!("Daemon not running, starting...");
        let start_status = client.daemon_start().await?;

        if !start_status.running {
            return Err(BdError::DaemonError(format!(
                "Failed to start daemon: {:?}",
                start_status
            )));
        }

        // Wait for socket to appear with timeout
        let socket_path = self.workspace.join(DAEMON_SOCKET_PATH);
        let mut elapsed = Duration::ZERO;

        while elapsed < DAEMON_START_TIMEOUT {
            if socket_path.exists() {
                info!("Daemon started and socket is ready");
                return Ok(());
            }

            sleep(Duration::from_millis(100)).await;
            elapsed += Duration::from_millis(100);
        }

        Err(BdError::DaemonError(format!(
            "Daemon started but socket not found after {:?}: {}",
            DAEMON_START_TIMEOUT,
            socket_path.display()
        )))
    }

    /// Get the current daemon status.
    ///
    /// Returns detailed information about the running daemon including
    /// PID, uptime, and port.
    ///
    /// # Example
    ///
    /// ```no_run
    /// # use agent_maestro::bd::DaemonManager;
    /// # use std::path::PathBuf;
    /// # async fn demo() -> Result<(), Box<dyn std::error::Error>> {
    /// let workspace = PathBuf::from("/path/to/workspace");
    /// let manager = DaemonManager::new(workspace)?;
    /// let status = manager.status().await?;
    /// println!("Daemon running: {}", status.running);
    /// # Ok(())
    /// # }
    /// ```
    pub async fn status(&self) -> BdResult<DaemonStatus> {
        let client = BdClient::with_bd_path(self.workspace.clone(), self.bd_path.clone())?;
        client.daemon_status().await
    }

    /// Stop the bd daemon.
    ///
    /// Sends a stop signal to the daemon and waits for it to terminate.
    ///
    /// # Example
    ///
    /// ```no_run
    /// # use agent_maestro::bd::DaemonManager;
    /// # use std::path::PathBuf;
    /// # async fn demo() -> Result<(), Box<dyn std::error::Error>> {
    /// let workspace = PathBuf::from("/path/to/workspace");
    /// let manager = DaemonManager::new(workspace)?;
    /// manager.stop().await?;
    /// # Ok(())
    /// # }
    /// ```
    pub async fn stop(&self) -> BdResult<()> {
        // Validate bd path is accessible before stopping
        let _client = BdClient::with_bd_path(self.workspace.clone(), self.bd_path.clone())?;

        let mut cmd = tokio::process::Command::new(&self.bd_path);
        cmd.args(["daemon", "stop"]);
        cmd.current_dir(&self.workspace);

        let output = cmd.output().await.map_err(BdError::Io)?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();
            return Err(BdError::DaemonError(format!(
                "Failed to stop daemon: {}",
                stderr
            )));
        }

        info!("Daemon stopped successfully");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_daemon_manager_constants() {
        assert_eq!(DAEMON_SOCKET_PATH, ".beads/bd.sock");
        assert_eq!(DAEMON_START_TIMEOUT, Duration::from_secs(30));
    }

    #[tokio::test]
    async fn test_daemon_manager_workspace_path() {
        let workspace = PathBuf::from("/tmp/test-workspace");
        let manager = match DaemonManager::new(workspace.clone()) {
            Ok(m) => m,
            Err(_) => {
                // bd CLI not found in test environment, which is expected
                return;
            }
        };

        assert_eq!(manager.workspace, workspace);
    }
}
