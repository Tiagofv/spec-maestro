use crate::bd::types::{Gate, Issue};
use crate::health::HealthStatus;
use serde::{Deserialize, Serialize};

/// Source of a dashboard event.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum EventSource {
    /// Event from bd (issue tracker)
    Bd,
}

/// Unified event type for the dashboard.
///
/// All events from bd are normalized into this enum
/// for consistent handling across the application.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum DashboardEvent {
    /// An issue was updated (status change, metadata update, etc.)
    IssueUpdated {
        /// Source of the event
        source: EventSource,
        /// The issue that was updated
        issue: Issue,
    },

    /// A gate was created (requiring approval before proceeding)
    GateCreated {
        /// Source of the event
        source: EventSource,
        /// The gate that was created
        gate: Gate,
    },

    /// A gate was resolved (approved or rejected)
    GateResolved {
        /// Source of the event
        source: EventSource,
        /// The gate that was resolved
        gate: Gate,
    },

    /// A cache was refreshed (bd cache, etc.)
    CacheRefreshed {
        /// Source of the event
        source: EventSource,
        /// Statistics about the cache (e.g., "items: 42, duration: 123ms")
        stats: String,
    },

    /// Connection status changed (connected/disconnected to service)
    ConnectionChanged {
        /// Source of the event
        source: EventSource,
        /// Whether the connection is active
        connected: bool,
    },

    /// Health status changed for AgentMaestro services
    HealthChanged {
        /// Source of the event
        source: EventSource,
        /// The new health status
        health: HealthStatus,
    },
}

impl DashboardEvent {
    /// Returns the event source.
    pub fn source(&self) -> EventSource {
        match self {
            Self::IssueUpdated { source, .. } => source.clone(),
            Self::GateCreated { source, .. } => source.clone(),
            Self::GateResolved { source, .. } => source.clone(),
            Self::CacheRefreshed { source, .. } => source.clone(),
            Self::ConnectionChanged { source, .. } => source.clone(),
            Self::HealthChanged { source, .. } => source.clone(),
        }
    }

    /// Returns a human-readable event type name.
    pub fn event_type_name(&self) -> &str {
        match self {
            Self::IssueUpdated { .. } => "issue_updated",
            Self::GateCreated { .. } => "gate_created",
            Self::GateResolved { .. } => "gate_resolved",
            Self::CacheRefreshed { .. } => "cache_refreshed",
            Self::ConnectionChanged { .. } => "connection_changed",
            Self::HealthChanged { .. } => "health_changed",
        }
    }

    /// Checks if the event is user-actionable (requires attention).
    pub fn is_actionable(&self) -> bool {
        match self {
            Self::GateResolved { gate, .. } if gate.status == "pending" => true,
            _ => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_event_equality() {
        assert_eq!(EventSource::Bd, EventSource::Bd);
    }

    #[test]
    fn test_dashboard_event_source() {
        let event = DashboardEvent::IssueUpdated {
            source: EventSource::Bd,
            issue: Issue {
                id: "test-1".to_string(),
                title: "Test Issue".to_string(),
                status: "open".to_string(),
                priority: None,
                labels: vec![],
                dependencies: vec![],
                assignee: None,
                owner: None,
                issue_type: None,
                extra: Default::default(),
            },
        };

        assert_eq!(event.source(), EventSource::Bd);
    }

    #[test]
    fn test_dashboard_event_type_name() {
        assert_eq!(
            DashboardEvent::IssueUpdated {
                source: EventSource::Bd,
                issue: Issue {
                    id: "test".to_string(),
                    title: "Test".to_string(),
                    status: "open".to_string(),
                    priority: None,
                    labels: vec![],
                    dependencies: vec![],
                    assignee: None,
                    owner: None,
                    issue_type: None,
                    extra: Default::default(),
                },
            }
            .event_type_name(),
            "issue_updated"
        );

        assert_eq!(
            DashboardEvent::ConnectionChanged {
                source: EventSource::Bd,
                connected: true,
            }
            .event_type_name(),
            "connection_changed"
        );
    }

    #[test]
    fn test_is_actionable() {
        // Cache refresh is not actionable
        let cache_event = DashboardEvent::CacheRefreshed {
            source: EventSource::Bd,
            stats: "items: 10".to_string(),
        };
        assert!(!cache_event.is_actionable());
    }

    #[test]
    fn test_serialize_deserialize() {
        let event = DashboardEvent::IssueUpdated {
            source: EventSource::Bd,
            issue: Issue {
                id: "test-1".to_string(),
                title: "Test".to_string(),
                status: "open".to_string(),
                priority: None,
                labels: vec![],
                dependencies: vec![],
                assignee: None,
                owner: None,
                issue_type: None,
                extra: Default::default(),
            },
        };

        let json = serde_json::to_string(&event).unwrap();
        let deserialized: DashboardEvent = serde_json::from_str(&json).unwrap();

        match deserialized {
            DashboardEvent::IssueUpdated { issue, source, .. } => {
                assert_eq!(issue.id, "test-1");
                assert_eq!(source, EventSource::Bd);
            }
            _ => panic!("Wrong variant after deserialization"),
        }
    }
}
