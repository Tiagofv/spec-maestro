use super::error::{BdError, BdResult};
use super::types::{Issue, Gate, EpicStatus, DaemonStatus};
use serde_json::Value;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Semaphore;
use tracing::{debug, warn};

/// Client for interacting with the bd CLI tool.
///
/// All read operations use `bd <cmd> --json` and parse stdout.
/// Write operations are serialized through a semaphore to prevent
/// concurrent modifications.
#[derive(Clone)]
pub struct BdClient {
    /// Path to the bd CLI binary
    bd_path: Arc<PathBuf>,
    /// Workspace directory to run bd commands in
    workspace: Arc<PathBuf>,
    /// Semaphore to serialize write operations
    write_semaphore: Arc<Semaphore>,
    /// Default timeout for CLI commands
    default_timeout: Duration,
}

impl BdClient {
    /// Create a new BdClient by auto-detecting the bd binary.
    ///
    /// Searches for bd in:
    /// 1. System PATH
    /// 2. ~/.local/bin/bd
    ///
    /// # Errors
    ///
    /// Returns `BdError::CliNotFound` if bd cannot be found.
    pub fn new(workspace: PathBuf) -> BdResult<Self> {
        let bd_path = Self::find_bd_binary()?;
        Ok(Self {
            bd_path: Arc::new(bd_path),
            workspace: Arc::new(workspace),
            write_semaphore: Arc::new(Semaphore::new(1)),
            default_timeout: Duration::from_secs(10),
        })
    }

    /// Create a new BdClient with a custom bd binary path.
    pub fn with_bd_path(
        workspace: PathBuf,
        bd_path: PathBuf,
    ) -> Result<Self, BdError> {
        if !bd_path.exists() {
            return Err(BdError::CliNotFound {
                checked_paths: vec![bd_path.to_string_lossy().to_string()],
            });
        }

        Ok(Self {
            bd_path: Arc::new(bd_path),
            workspace: Arc::new(workspace),
            write_semaphore: Arc::new(Semaphore::new(1)),
            default_timeout: Duration::from_secs(10),
        })
    }

    /// Create a new BdClient with a custom timeout.
    pub fn with_timeout(
        workspace: PathBuf,
        timeout: Duration,
    ) -> BdResult<Self> {
        let bd_path = Self::find_bd_binary()?;
        Ok(Self {
            bd_path: Arc::new(bd_path),
            workspace: Arc::new(workspace),
            write_semaphore: Arc::new(Semaphore::new(1)),
            default_timeout: timeout,
        })
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

            // First try as-is (for PATH lookup)
            if which::which(path).is_ok() {
                return Ok(PathBuf::from(path));
            }

            // Then try as absolute path
            let abs_path = PathBuf::from(path);
            if abs_path.exists() && abs_path.is_file() {
                return Ok(abs_path);
            }
        }

        Err(BdError::CliNotFound { checked_paths })
    }

    /// Run a bd command and capture its stdout as a JSON value.
    ///
    /// This is a helper method that handles:
    /// - Command spawning in the workspace directory
    /// - Adding `--json` flag
    /// - Timeout enforcement
    /// - stdout/stderr capture
    async fn run_bd_json(
        &self,
        args: &[&str],
        additional_args: &[&str],
    ) -> BdResult<Value> {
        let cmd_str = format!("bd {} --json {}", args.join(" "), additional_args.join(" "));
        debug!("Running bd command: {}", cmd_str);

        let mut cmd = tokio::process::Command::new(&*self.bd_path);
        cmd.args(args);
        cmd.arg("--json");
        cmd.args(additional_args);
        cmd.current_dir(&*self.workspace);

        let output = tokio::time::timeout(
            self.default_timeout,
            cmd.output(),
        )
        .await
        .map_err(|_| BdError::Timeout {
            cmd: cmd_str.clone(),
            duration: self.default_timeout,
        })?
        .map_err(BdError::Io)?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();
            warn!(
                "bd command failed: cmd={}, exit_code={}, stderr={}",
                cmd_str,
                output.status.code().unwrap_or(-1),
                stderr
            );
            return Err(BdError::CommandFailed {
                cmd: cmd_str,
                stderr,
                exit_code: output.status.code().unwrap_or(-1),
            });
        }

        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        let json: Value = serde_json::from_str(&stdout).map_err(|e| {
            BdError::ParseError(format!(
                "Failed to parse JSON output from '{}': {}\nRaw output: {}",
                cmd_str, e, stdout
            ))
        })?;

        Ok(json)
    }

    /// Run a bd write command (acquires semaphore).
    ///
    /// Used for commands that modify state.
    async fn run_bd_write(
        &self,
        args: &[&str],
        additional_args: &[&str],
    ) -> BdResult<Value> {
        // Acquire semaphore permit
        let _permit = self.write_semaphore
            .acquire()
            .await
            .map_err(|e| BdError::DaemonError(format!("Failed to acquire write permit: {}", e)))?;

        self.run_bd_json(args, additional_args).await
    }

    /// List all issues in the workspace.
    ///
    /// Corresponds to `bd list --json`.
    pub async fn list_issues(&self) -> BdResult<Vec<Issue>> {
        let json = self.run_bd_json(&["list"], &[]).await?;

        // Handle both array and wrapped responses
        let issues = if json.as_array().is_some() {
            serde_json::from_value::<Vec<Issue>>(json.clone())
                .map_err(|e| BdError::ParseError(format!("Failed to parse issues array: {}", e)))?
        } else if let Some(issues_array) = json.get("issues").and_then(|v| v.as_array()) {
            serde_json::from_value::<Vec<Issue>>(Value::Array(issues_array.clone()))
                .map_err(|e| BdError::ParseError(format!("Failed to parse issues from wrapped response: {}", e)))?
        } else {
            return Err(BdError::ParseError(format!(
                "Unexpected response format for list_issues: {}",
                json
            )));
        };

        debug!("Listed {} issues", issues.len());
        Ok(issues)
    }

    /// Get details for a specific issue.
    ///
    /// Corresponds to `bd show <id> --json`.
    /// Note: bd returns an array `[{issue}]` with nested dependencies/dependents.
    pub async fn get_issue(&self, id: &str) -> BdResult<Issue> {
        let json = self.run_bd_json(&["show", id], &[]).await?;

        // bd show --json returns an array with the issue as first element
        let issue_value = if let Some(array) = json.as_array() {
            array.first().cloned().ok_or_else(|| {
                BdError::ParseError("bd show returned empty array".to_string())
            })?
        } else if json.is_object() {
            json.clone()
        } else {
            return Err(BdError::ParseError(format!(
                "Unexpected response format for get_issue: {}",
                json
            )));
        };

        let issue: Issue = serde_json::from_value(issue_value)
            .map_err(|e| BdError::ParseError(format!("Failed to parse issue: {}", e)))?;

        debug!("Retrieved issue: {}", issue.id);
        Ok(issue)
    }

    /// List ready (available) issues.
    ///
    /// Corresponds to `bd ready --json`.
    pub async fn list_ready(&self) -> BdResult<Vec<Issue>> {
        let json = self.run_bd_json(&["ready"], &[]).await?;

        let issues = if json.as_array().is_some() {
            serde_json::from_value::<Vec<Issue>>(json.clone())
                .map_err(|e| BdError::ParseError(format!("Failed to parse ready issues: {}", e)))?
        } else if let Some(issues_array) = json.get("issues").and_then(|v| v.as_array()) {
            serde_json::from_value::<Vec<Issue>>(Value::Array(issues_array.clone()))
                .map_err(|e| BdError::ParseError(format!("Failed to parse ready issues from wrapped response: {}", e)))?
        } else {
            return Err(BdError::ParseError(format!(
                "Unexpected response format for list_ready: {}",
                json
            )));
        };

        debug!("Listed {} ready issues", issues.len());
        Ok(issues)
    }

    /// List gates for the current issue.
    ///
    /// Corresponds to `bd gates --json`.
    pub async fn list_gates(&self) -> BdResult<Vec<Gate>> {
        let json = self.run_bd_json(&["gates"], &[]).await?;

        let gates = if json.as_array().is_some() {
            serde_json::from_value::<Vec<Gate>>(json.clone())
                .map_err(|e| BdError::ParseError(format!("Failed to parse gates: {}", e)))?
        } else if let Some(gates_array) = json.get("gates").and_then(|v| v.as_array()) {
            serde_json::from_value::<Vec<Gate>>(Value::Array(gates_array.clone()))
                .map_err(|e| BdError::ParseError(format!("Failed to parse gates from wrapped response: {}", e)))?
        } else {
            return Err(BdError::ParseError(format!(
                "Unexpected response format for list_gates: {}",
                json
            )));
        };

        debug!("Listed {} gates", gates.len());
        Ok(gates)
    }

    /// Resolve a gate (write operation).
    ///
    /// Corresponds to `bd resolve-gate <id> --reason <reason> --json`.
    /// This operation is serialized through the write semaphore.
    pub async fn resolve_gate(&self, gate_id: &str, reason: &str) -> BdResult<Gate> {
        let json = self
            .run_bd_write(
                &["resolve-gate", gate_id],
                &["--reason", reason],
            )
            .await?;

        let gate = if json.is_object() {
            serde_json::from_value::<Gate>(json.clone())
                .map_err(|e| BdError::ParseError(format!("Failed to parse resolved gate: {}", e)))?
        } else if let Some(gate_obj) = json.get("gate").and_then(|v| v.as_object()) {
            serde_json::from_value::<Gate>(Value::Object(gate_obj.clone()))
                .map_err(|e| BdError::ParseError(format!("Failed to parse resolved gate from wrapped response: {}", e)))?
        } else {
            return Err(BdError::ParseError(format!(
                "Unexpected response format for resolve_gate: {}",
                json
            )));
        };

        debug!("Resolved gate: {}", gate.id);
        Ok(gate)
    }

    /// Get the status of an epic.
    ///
    /// Corresponds to `bd epic-status <id> --json`.
    pub async fn get_epic_status(&self, epic_id: &str) -> BdResult<EpicStatus> {
        let json = self
            .run_bd_json(&["epic-status", epic_id], &[])
            .await?;

        let status = if json.is_object() {
            serde_json::from_value::<EpicStatus>(json.clone())
                .map_err(|e| BdError::ParseError(format!("Failed to parse epic status: {}", e)))?
        } else if let Some(status_obj) = json.get("epic_status").and_then(|v| v.as_object()) {
            serde_json::from_value::<EpicStatus>(Value::Object(status_obj.clone()))
                .map_err(|e| BdError::ParseError(format!("Failed to parse epic status from wrapped response: {}", e)))?
        } else {
            return Err(BdError::ParseError(format!(
                "Unexpected response format for get_epic_status: {}",
                json
            )));
        };

        debug!("Retrieved epic status for: {}", status.id);
        Ok(status)
    }

    /// Check if the bd daemon is running.
    ///
    /// Corresponds to `bd daemon status --json`.
    pub async fn daemon_status(&self) -> BdResult<DaemonStatus> {
        let json = self
            .run_bd_json(&["daemon", "status"], &[])
            .await?;

        let status = if json.is_object() {
            DaemonStatus::from_json(json.clone())
                .map_err(|e| BdError::ParseError(format!("Failed to parse daemon status: {}", e)))?
        } else if let Some(status_obj) = json.get("daemon").and_then(|v| v.as_object()) {
            DaemonStatus::from_json(Value::Object(status_obj.clone()))
                .map_err(|e| BdError::ParseError(format!("Failed to parse daemon status from wrapped response: {}", e)))?
        } else {
            return Err(BdError::ParseError(format!(
                "Unexpected response format for daemon_status: {}",
                json
            )));
        };

        debug!("Retrieved daemon status, running={}", status.running);
        Ok(status)
    }

    /// Start the bd daemon.
    ///
    /// Corresponds to `bd daemon start --json`.
    /// This operation is serialized through the write semaphore.
    pub async fn daemon_start(&self) -> BdResult<DaemonStatus> {
        let json = self
            .run_bd_write(&["daemon", "start"], &[])
            .await?;

        let status = if json.is_object() {
            DaemonStatus::from_json(json.clone())
                .map_err(|e| BdError::ParseError(format!("Failed to parse daemon start status: {}", e)))?
        } else if let Some(status_obj) = json.get("daemon").and_then(|v| v.as_object()) {
            DaemonStatus::from_json(Value::Object(status_obj.clone()))
                .map_err(|e| BdError::ParseError(format!("Failed to parse daemon start status from wrapped response: {}", e)))?
        } else {
            return Err(BdError::ParseError(format!(
                "Unexpected response format for daemon_start: {}",
                json
            )));
        };

        debug!("Started daemon, running={}", status.running);
        Ok(status)
    }

    /// Update issue status (write operation).
    ///
    /// Corresponds to `bd update <id> --status <status> --json`.
    /// This operation is serialized through the write semaphore.
    pub async fn update_issue_status(&self, id: &str, status: &str) -> BdResult<Issue> {
        let json = self
            .run_bd_write(&["update", id], &["--status", status])
            .await?;

        // Handle array, object, or wrapped response
        let issue = if let Some(array) = json.as_array() {
            if array.is_empty() {
                return Err(BdError::ParseError(
                    "update_issue_status returned empty array".to_string()
                ));
            }
            serde_json::from_value::<Issue>(array[0].clone())
                .map_err(|e| BdError::ParseError(format!("Failed to parse issue from array: {}", e)))?
        } else if json.is_object() {
            serde_json::from_value::<Issue>(json.clone())
                .map_err(|e| BdError::ParseError(format!("Failed to parse issue: {}", e)))?
        } else if let Some(issue_obj) = json.get("issue").and_then(|v| v.as_object()) {
            serde_json::from_value::<Issue>(Value::Object(issue_obj.clone()))
                .map_err(|e| BdError::ParseError(format!("Failed to parse issue from wrapped response: {}", e)))?
        } else {
            return Err(BdError::ParseError(format!(
                "Unexpected response format for update_issue_status: {}",
                json
            )));
        };

        debug!("Updated issue {} status to {}", id, status);
        Ok(issue)
    }

    /// Close an issue (write operation).
    ///
    /// Corresponds to `bd close <id> --json` (with optional `--reason <reason>`).
    /// This operation is serialized through the write semaphore.
    ///
    /// Returns raw Value since the close output format is not well-known.
    pub async fn close_issue(&self, id: &str, reason: Option<&str>) -> BdResult<Value> {
        let mut additional_args = Vec::new();
        if let Some(r) = reason {
            additional_args.push("--reason");
            additional_args.push(r);
        }

        let json = self
            .run_bd_write(&["close", id], &additional_args)
            .await?;

        debug!("Closed issue {} with reason: {:?}", id, reason);
        Ok(json)
    }

    /// Create a new issue (write operation).
    ///
    /// Corresponds to `bd create <title> --json` with optional flags.
    /// This operation is serialized through the write semaphore.
    pub async fn create_issue(
        &self,
        title: &str,
        description: Option<&str>,
        labels: Option<&[&str]>,
        parent_id: Option<&str>,
        deps: Option<&[&str]>,
    ) -> BdResult<Issue> {
        let mut additional_args = Vec::new();
        
        // Create owned strings for joined values to extend their lifetime
        let labels_str;
        let deps_str;

        if let Some(desc) = description {
            additional_args.push("--description");
            additional_args.push(desc);
        }

        if let Some(label_list) = labels {
            if !label_list.is_empty() {
                labels_str = label_list.join(",");
                additional_args.push("--labels");
                additional_args.push(&labels_str);
            }
        }

        if let Some(parent) = parent_id {
            additional_args.push("--parent");
            additional_args.push(parent);
        }

        if let Some(dep_list) = deps {
            if !dep_list.is_empty() {
                deps_str = dep_list.join(",");
                additional_args.push("--deps");
                additional_args.push(&deps_str);
            }
        }

        let json = self
            .run_bd_write(&["create", title], &additional_args)
            .await?;

        // Handle array, object, or wrapped response
        let issue = if let Some(array) = json.as_array() {
            if array.is_empty() {
                return Err(BdError::ParseError(
                    "create_issue returned empty array".to_string()
                ));
            }
            serde_json::from_value::<Issue>(array[0].clone())
                .map_err(|e| BdError::ParseError(format!("Failed to parse created issue from array: {}", e)))?
        } else if json.is_object() {
            serde_json::from_value::<Issue>(json.clone())
                .map_err(|e| BdError::ParseError(format!("Failed to parse created issue: {}", e)))?
        } else if let Some(issue_obj) = json.get("issue").and_then(|v| v.as_object()) {
            serde_json::from_value::<Issue>(Value::Object(issue_obj.clone()))
                .map_err(|e| BdError::ParseError(format!("Failed to parse created issue from wrapped response: {}", e)))?
        } else {
            return Err(BdError::ParseError(format!(
                "Unexpected response format for create_issue: {}",
                json
            )));
        };

        debug!("Created issue: {}", issue.id);
        Ok(issue)
    }

    /// Claim an issue (write operation).
    ///
    /// Corresponds to `bd update <id> --claim --json`.
    /// This atomically sets assignee and status to in_progress.
    /// This operation is serialized through the write semaphore.
    pub async fn claim_issue(&self, id: &str) -> BdResult<Issue> {
        let json = self
            .run_bd_write(&["update", id], &["--claim"])
            .await?;

        // Handle array, object, or wrapped response
        let issue = if let Some(array) = json.as_array() {
            if array.is_empty() {
                return Err(BdError::ParseError(
                    "claim_issue returned empty array".to_string()
                ));
            }
            serde_json::from_value::<Issue>(array[0].clone())
                .map_err(|e| BdError::ParseError(format!("Failed to parse claimed issue from array: {}", e)))?
        } else if json.is_object() {
            serde_json::from_value::<Issue>(json.clone())
                .map_err(|e| BdError::ParseError(format!("Failed to parse claimed issue: {}", e)))?
        } else if let Some(issue_obj) = json.get("issue").and_then(|v| v.as_object()) {
            serde_json::from_value::<Issue>(Value::Object(issue_obj.clone()))
                .map_err(|e| BdError::ParseError(format!("Failed to parse claimed issue from wrapped response: {}", e)))?
        } else {
            return Err(BdError::ParseError(format!(
                "Unexpected response format for claim_issue: {}",
                json
            )));
        };

        debug!("Claimed issue: {}", id);
        Ok(issue)
    }

    /// Assign an issue to a user (write operation).
    ///
    /// Corresponds to `bd update <id> --assignee <assignee> --json`.
    /// This operation is serialized through the write semaphore.
    pub async fn assign_issue(&self, id: &str, assignee: &str) -> BdResult<Issue> {
        let json = self
            .run_bd_write(&["update", id], &["--assignee", assignee])
            .await?;

        // Handle array, object, or wrapped response
        let issue = if let Some(array) = json.as_array() {
            if array.is_empty() {
                return Err(BdError::ParseError(
                    "assign_issue returned empty array".to_string()
                ));
            }
            serde_json::from_value::<Issue>(array[0].clone())
                .map_err(|e| BdError::ParseError(format!("Failed to parse assigned issue from array: {}", e)))?
        } else if json.is_object() {
            serde_json::from_value::<Issue>(json.clone())
                .map_err(|e| BdError::ParseError(format!("Failed to parse assigned issue: {}", e)))?
        } else if let Some(issue_obj) = json.get("issue").and_then(|v| v.as_object()) {
            serde_json::from_value::<Issue>(Value::Object(issue_obj.clone()))
                .map_err(|e| BdError::ParseError(format!("Failed to parse assigned issue from wrapped response: {}", e)))?
        } else {
            return Err(BdError::ParseError(format!(
                "Unexpected response format for assign_issue: {}",
                json
            )));
        };

        debug!("Assigned issue {} to {}", id, assignee);
        Ok(issue)
    }
}
