pub mod activity;
pub mod client;
pub mod daemon;
pub mod error;
pub mod types;
pub mod workspace;

// Re-export commonly used types
pub use activity::ActivityStream;
pub use client::BdClient;
pub use daemon::DaemonManager;
pub use error::{BdError, BdResult};
pub use types::{ActivityEvent, Issue, Gate, EpicStatus, AgentState, DaemonStatus, Workspace};
pub use workspace::WorkspaceDiscovery;
