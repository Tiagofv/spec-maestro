use super::error::{BdError, BdResult};
use super::types::ActivityEvent;
use std::path::Path;
use std::time::Duration;
use tokio::io::{BufReader, AsyncBufReadExt};
use tokio::process::Command;
use tokio::sync::mpsc::UnboundedSender;
use tokio::task::JoinHandle;
use tokio::time::sleep;
use tracing::{debug, error, info, warn};

const INITIAL_BACKOFF: Duration = Duration::from_secs(1);

const MAX_BACKOFF: Duration = Duration::from_secs(30);

const BACKOFF_MULTIPLIER: u32 = 2;

const MAX_PARSE_ERRORS: usize = 100;

#[cfg(test)]
const READ_LINE_TIMEOUT: Duration = Duration::from_secs(60);

const STARTUP_GRACE: Duration = Duration::from_secs(5);

/// Stream of bd activity events.
///
/// Spawns `bd activity --follow --json` as a long-running child process and
/// forwards events to the provided channel. Implements auto-restart with
/// exponential backoff on process crashes.
pub struct ActivityStream;

impl ActivityStream {
    /// Start streaming activity events from the bd daemon.
    ///
    /// Spawns a background task that reads `bd activity --follow --json` output
    /// line-by-line, parses each line as JSON, and forwards ActivityEvents to the
    /// provided sender.
    ///
    /// The child process is configured with `kill_on_drop(true)` for automatic
    /// cleanup when the task is dropped or cancelled.
    ///
    /// # Arguments
    ///
    /// * `bd_path` - Path to the bd CLI binary
    /// * `workspace` - Path to the workspace directory
    /// * `sender` - Channel to send parsed ActivityEvents to
    ///
    /// # Returns
    ///
    /// A `JoinHandle` for the background task. Dropping this handle will
    /// terminate the child process and stop the stream.
    ///
    /// # Auto-Restart Behavior
    ///
    /// On process crash, the stream automatically restarts with exponential
    /// backoff: 1s, 2s, 4s, 8s, 16s, 30s (max).
    ///
    /// # Example
    ///
    /// ```no_run
    /// # use std::path::PathBuf;
    /// # use tokio::sync::mpsc::unbounded_channel;
    /// let (tx, mut rx) = unbounded_channel();
    /// let bd_path = PathBuf::from("bd");
    /// let workspace = PathBuf::from("/path/to/workspace");
    ///
    /// let handle = ActivityStream::start(&bd_path, &workspace, tx)?;
    ///
    /// // Drop the handle to stop streaming
    /// drop(handle);
    /// # Ok::<(), Box<dyn std::error::Error>>(())
    /// ```
    pub fn start(
        bd_path: &Path,
        workspace: &Path,
        sender: UnboundedSender<ActivityEvent>,
    ) -> BdResult<JoinHandle<()>> {
        let bd_path = bd_path.to_path_buf();
        let workspace = workspace.to_path_buf();

        let handle = tokio::spawn(async move {
            let mut backoff = INITIAL_BACKOFF;
            let mut consecutive_errors = 0;

            loop {
                debug!("Starting activity stream with backoff: {:?}", backoff);

                if let Err(e) = Self::run_stream(&bd_path, &workspace, &sender).await {
                    error!("Activity stream error: {}, retrying in {:?}", e, backoff);
                    consecutive_errors += 1;

                    // Exponential backoff with max cap
                    sleep(backoff).await;
                    backoff = std::cmp::min(
                        backoff * BACKOFF_MULTIPLIER,
                        MAX_BACKOFF,
                    );

                    // Prevent infinite restart loops on persistent issues
                    if consecutive_errors > 10 {
                        error!(
                            "Too many consecutive activity stream errors ({}), stopping",
                            consecutive_errors
                        );
                        return;
                    }

                    continue;
                }

                // Stream ended normally (likely sender closed)
                info!("Activity stream ended normally");
                break;
            }
        });

        Ok(handle)
    }

    /// Run the activity stream until an error occurs.
    async fn run_stream(
        bd_path: &Path,
        workspace: &Path,
        sender: &UnboundedSender<ActivityEvent>,
    ) -> BdResult<()> {
        info!(" spawning bd activity --follow --json");

        let mut child = Command::new(bd_path)
            .args(["activity", "--follow", "--json"])
            .current_dir(workspace)
            .kill_on_drop(true)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .map_err(|e| BdError::DaemonError(format!("Failed to spawn activity command: {}", e)))?;

        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| BdError::DaemonError("Failed to capture stdout".to_string()))?;

        let stderr = child
            .stderr
            .take()
            .ok_or_else(|| BdError::DaemonError("Failed to capture stderr".to_string()))?;

        let reader = BufReader::new(stdout);
        let mut lines = reader.lines();

        // Spawn a task to monitor stderr for errors
        let stderr_reader = BufReader::new(stderr);
        let stderr_handle = tokio::spawn(async move {
            let mut stderr_lines = stderr_reader.lines();
            while let Ok(Some(line)) = stderr_lines.next_line().await {
                if !line.is_empty() {
                    warn!("Activity stream stderr: {}", line);
                }
            }
        });

        let mut parse_errors = 0;

        while let Ok(Some(line)) = lines.next_line().await {
            // Skip empty lines
            let line = line.trim();
            if line.is_empty() {
                continue;
            }

            // Parse JSON (synchronous operation)
            let event = match Self::parse_event(line) {
                Ok(event) => event,
                Err(e) => {
                    parse_errors += 1;
                    if parse_errors > MAX_PARSE_ERRORS {
                        return Err(BdError::DaemonError(format!(
                            "Too many parse errors ({}), stopping stream",
                            parse_errors
                        )));
                    }
                    warn!("Failed to parse activity event (error {}/{}): {}",
                          parse_errors, MAX_PARSE_ERRORS, e);
                    continue;
                }
            };

            // Forward event to sender
            if let Err(e) = sender.send(event) {
                debug!("Activity event send failed (receiver likely dropped): {}", e);
                return Err(BdError::DaemonError(
                    "Activity event channel closed".to_string()
                ));
            }

            // Reset parse error counter on success
            parse_errors = 0;
        }

        // Wait for stderr monitor to complete
        let _ = tokio::time::timeout(STARTUP_GRACE, stderr_handle).await;

        // Check child exit status
        let exit_status = tokio::time::timeout(
            STARTUP_GRACE,
            child.wait()
        )
        .await
        .map_err(|_| BdError::DaemonError(
            "Timeout waiting for child process to exit".to_string()
        ))?
        .map_err(|e| BdError::DaemonError(format!("Failed to wait for child: {}", e)))?;

        if let Some(exit_code) = exit_status.code() {
            if exit_code != 0 {
                return Err(BdError::DaemonError(format!(
                    "Activity process exited with code: {}",
                    exit_code
                )));
            }
        }

        Ok(())
    }

    /// Parse a single activity event from JSON.
    fn parse_event(line: &str) -> BdResult<ActivityEvent> {
        serde_json::from_str::<ActivityEvent>(line).map_err(|e| {
            BdError::ParseError(format!(
                "Failed to parse activity event: {}\nInput: {}",
                e, line
            ))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_activity_stream_constants() {
        assert_eq!(INITIAL_BACKOFF, Duration::from_secs(1));
        assert_eq!(MAX_BACKOFF, Duration::from_secs(30));
        assert_eq!(BACKOFF_MULTIPLIER, 2);
        assert_eq!(MAX_PARSE_ERRORS, 100);
        assert_eq!(READ_LINE_TIMEOUT, Duration::from_secs(60));
        assert_eq!(STARTUP_GRACE, Duration::from_secs(5));
    }

    #[test]
    fn test_parse_event_valid() {
        let json = r#"{
            "event_type": "issue_created",
            "issue_id": "ISSUE-001",
            "timestamp": "2024-01-01T00:00:00Z"
        }"#;

        let event = ActivityStream::parse_event(json).unwrap();
        assert_eq!(event.event_type, "issue_created");
        assert_eq!(event.issue_id, Some("ISSUE-001".to_string()));
    }

    #[test]
    fn test_parse_event_invalid() {
        let json = r#"invalid json"#;
        assert!(ActivityStream::parse_event(json).is_err());
    }

    #[test]
    fn test_parse_event_empty_issue_id() {
        let json = r#"{
            "event_type": "daemon_started",
            "timestamp": "2024-01-01T00:00:00Z"
        }"#;

        let event = ActivityStream::parse_event(json).unwrap();
        assert_eq!(event.event_type, "daemon_started");
        assert_eq!(event.issue_id, None);
    }
}
