use thiserror::Error;

#[derive(Debug, Error)]
pub enum BdError {
    #[error("bd CLI not found. Checked: {checked_paths:?}")]
    CliNotFound { checked_paths: Vec<String> },

    #[error("bd command failed: {cmd} (exit code: {exit_code})\nstderr: {stderr}")]
    CommandFailed {
        cmd: String,
        stderr: String,
        exit_code: i32,
    },

    #[error("Failed to parse bd output: {0}")]
    ParseError(String),

    #[error("bd command timed out after {duration:?}: {cmd}")]
    Timeout {
        cmd: String,
        duration: std::time::Duration,
    },

    #[error("bd daemon error: {0}")]
    DaemonError(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}

pub type BdResult<T> = Result<T, BdError>;
