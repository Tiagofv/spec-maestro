use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Issue {
    pub id: String,
    pub title: String,
    pub status: String,
    /// Priority as a JSON value — bd returns an integer (0-4), not a string.
    #[serde(default)]
    pub priority: Option<Value>,
    #[serde(default)]
    pub labels: Vec<String>,
    /// Dependencies can be string IDs (bd list) or full objects (bd show).
    /// Use `dependency_ids()` to get just the IDs.
    #[serde(default)]
    pub dependencies: Vec<Value>,
    /// bd may return "assignee", "owner", or both.
    #[serde(default)]
    pub assignee: Option<String>,
    /// bd "owner" field — separate from assignee. Use `effective_assignee()` to get the right one.
    #[serde(default)]
    pub owner: Option<String>,
    pub issue_type: Option<String>,
    #[serde(flatten)]
    pub extra: HashMap<String, Value>,
}

impl Issue {
    /// Returns the effective assignee — prefers `assignee`, falls back to `owner`.
    pub fn effective_assignee(&self) -> Option<&str> {
        self.assignee.as_deref().or(self.owner.as_deref())
    }

    /// Returns dependency IDs as strings (handles both string IDs and full objects).
    pub fn dependency_ids(&self) -> Vec<String> {
        self.dependencies
            .iter()
            .filter_map(|v| {
                if let Some(s) = v.as_str() {
                    Some(s.to_string())
                } else if let Some(obj) = v.as_object() {
                    obj.get("id").and_then(|id| id.as_str()).map(String::from)
                } else {
                    None
                }
            })
            .collect()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Gate {
    pub id: String,
    pub issue_id: String,
    pub gate_type: String,
    pub status: String,
    pub reason: Option<String>,
    #[serde(flatten)]
    pub extra: HashMap<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EpicStatus {
    pub id: String,
    pub title: String,
    pub total: u32,
    pub open: u32,
    pub closed: u32,
    pub in_progress: u32,
    pub blocked: u32,
    #[serde(flatten)]
    pub extra: HashMap<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentState {
    pub agent_id: String,
    pub status: String,
    pub current_issue: Option<String>,
    pub last_activity: Option<String>,
    #[serde(flatten)]
    pub extra: HashMap<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DaemonStatus {
    /// Whether the daemon is running.
    /// Populated from `running` bool field OR derived from `status == "running"`.
    #[serde(default)]
    pub running: bool,
    pub pid: Option<u32>,
    /// bd returns uptime as a float (seconds with sub-second precision).
    #[serde(default)]
    pub uptime_seconds: Option<f64>,
    pub port: Option<u16>,
    #[serde(flatten)]
    pub extra: HashMap<String, Value>,
}

impl DaemonStatus {
    /// Create from raw JSON, handling both old format (`running: bool`)
    /// and bd 0.47+ format (`status: "running"`).
    pub fn from_json(json: Value) -> Result<Self, serde_json::Error> {
        let mut status: DaemonStatus = serde_json::from_value(json.clone())?;
        // If `running` wasn't set but `status` field says "running", derive it
        if !status.running {
            if let Some(Value::String(s)) = json.get("status") {
                status.running = s == "running";
            }
        }
        Ok(status)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActivityEvent {
    pub event_type: String,
    pub issue_id: Option<String>,
    pub gate_id: Option<String>,
    pub timestamp: String,
    #[serde(flatten)]
    pub extra: HashMap<String, Value>,
}

/// Represents a registered bd workspace.
///
/// Discovered by parsing `~/.beads/registry.json`. Contains the workspace
/// path, name, and daemon status.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Workspace {
    /// Absolute path to the workspace directory.
    pub path: String,
    /// Display name for the workspace (derived from directory name).
    pub name: String,
    /// Whether the bd daemon is currently running for this workspace.
    pub daemon_running: bool,
    /// Additional workspace metadata from the registry.
    #[serde(flatten)]
    pub extra: HashMap<String, Value>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_issue(id: &str, title: &str, status: &str) -> Issue {
        let mut extra = HashMap::new();
        extra.insert(
            "custom_field".to_string(),
            serde_json::json!("custom_value"),
        );

        Issue {
            id: id.to_string(),
            title: title.to_string(),
            status: status.to_string(),
            priority: Some(serde_json::json!(2)),
            labels: vec!["bug".to_string(), "backend".to_string()],
            dependencies: vec![serde_json::json!("parent-1")],
            assignee: Some("test-user".to_string()),
            owner: None,
            issue_type: Some("Bug".to_string()),
            extra,
        }
    }

    #[test]
    fn test_issue_serialization_round_trip() {
        let issue = create_test_issue("TEST-1", "Test issue", "open");
        let json = serde_json::to_string(&issue).unwrap();
        let deserialized: Issue = serde_json::from_str(&json).unwrap();

        assert_eq!(deserialized.id, issue.id);
        assert_eq!(deserialized.title, issue.title);
        assert_eq!(deserialized.status, issue.status);
        assert_eq!(deserialized.priority, issue.priority);
        assert_eq!(deserialized.labels, issue.labels);
        assert_eq!(deserialized.dependencies, issue.dependencies);
        assert_eq!(deserialized.assignee, issue.assignee);
        assert_eq!(deserialized.issue_type, issue.issue_type);
    }

    #[test]
    fn test_issue_with_optional_fields() {
        let issue = Issue {
            id: "TEST-2".to_string(),
            title: "Minimal issue".to_string(),
            status: "closed".to_string(),
            priority: None,
            labels: vec![],
            dependencies: vec![],
            assignee: None,
            owner: None,
            issue_type: None,
            extra: HashMap::new(),
        };

        let json = serde_json::to_string(&issue).unwrap();
        let deserialized: Issue = serde_json::from_str(&json).unwrap();

        assert_eq!(deserialized.id, "TEST-2");
        assert!(deserialized.priority.is_none());
        assert!(deserialized.labels.is_empty());
        assert!(deserialized.assignee.is_none());
        assert!(deserialized.issue_type.is_none());
    }

    #[test]
    fn test_issue_with_extra_fields() {
        let mut extra = HashMap::new();
        extra.insert("custom_field".to_string(), serde_json::json!("value"));
        extra.insert("number_field".to_string(), serde_json::json!(42));

        let issue = Issue {
            id: "TEST-3".to_string(),
            title: "Issue with extra".to_string(),
            status: "open".to_string(),
            priority: None,
            labels: vec![],
            dependencies: vec![],
            assignee: None,
            owner: None,
            issue_type: None,
            extra,
        };

        let json = serde_json::to_string(&issue).unwrap();
        let deserialized: Issue = serde_json::from_str(&json).unwrap();

        assert_eq!(
            deserialized.extra.get("custom_field"),
            Some(&serde_json::json!("value"))
        );
        assert_eq!(
            deserialized.extra.get("number_field"),
            Some(&serde_json::json!(42))
        );
    }

    #[test]
    fn test_gate_serialization_round_trip() {
        let mut extra = HashMap::new();
        extra.insert(
            "metadata".to_string(),
            serde_json::json!({ "key": "value" }),
        );

        let gate = Gate {
            id: "GATE-1".to_string(),
            issue_id: "ISSUE-1".to_string(),
            gate_type: "compile".to_string(),
            status: "pending".to_string(),
            reason: Some("Compile check required".to_string()),
            extra,
        };

        let json = serde_json::to_string(&gate).unwrap();
        let deserialized: Gate = serde_json::from_str(&json).unwrap();

        assert_eq!(deserialized.id, gate.id);
        assert_eq!(deserialized.issue_id, gate.issue_id);
        assert_eq!(deserialized.gate_type, gate.gate_type);
        assert_eq!(deserialized.status, gate.status);
        assert_eq!(deserialized.reason, gate.reason);
    }

    #[test]
    fn test_gate_status_parsing() {
        let gate_json = r#"{
            "id": "GATE-1",
            "issue_id": "ISSUE-1",
            "gate_type": "pm-approval",
            "status": "approved",
            "reason": null
        }"#;

        let gate: Gate = serde_json::from_str(gate_json).unwrap();
        assert_eq!(gate.status, "approved");
        assert!(gate.reason.is_none());
    }

    #[test]
    fn test_epic_status_serialization() {
        let epic = EpicStatus {
            id: "EPIC-1".to_string(),
            title: "Test Epic".to_string(),
            total: 10,
            open: 3,
            closed: 5,
            in_progress: 2,
            blocked: 0,
            extra: HashMap::new(),
        };

        let json = serde_json::to_string(&epic).unwrap();
        let deserialized: EpicStatus = serde_json::from_str(&json).unwrap();

        assert_eq!(deserialized.total, 10);
        assert_eq!(deserialized.open, 3);
        assert_eq!(deserialized.closed, 5);
        assert_eq!(deserialized.in_progress, 2);
        assert_eq!(deserialized.blocked, 0);
    }

    #[test]
    fn test_agent_state_serialization() {
        let mut extra = HashMap::new();
        extra.insert("agent_version".to_string(), serde_json::json!("1.0.0"));

        let state = AgentState {
            agent_id: "agent-1".to_string(),
            status: "working".to_string(),
            current_issue: Some("TASK-1".to_string()),
            last_activity: Some("2024-01-01T00:00:00Z".to_string()),
            extra,
        };

        let json = serde_json::to_string(&state).unwrap();
        let deserialized: AgentState = serde_json::from_str(&json).unwrap();

        assert_eq!(deserialized.agent_id, "agent-1");
        assert_eq!(deserialized.current_issue, Some("TASK-1".to_string()));
    }

    #[test]
    fn test_daemon_status_serialization() {
        let status = DaemonStatus {
            running: true,
            pid: Some(12345),
            uptime_seconds: Some(3600.0),
            port: Some(8080),
            extra: HashMap::new(),
        };

        let json = serde_json::to_string(&status).unwrap();
        let deserialized: DaemonStatus = serde_json::from_str(&json).unwrap();

        assert_eq!(deserialized.running, true);
        assert_eq!(deserialized.pid, Some(12345));
        assert_eq!(deserialized.port, Some(8080));
    }

    #[test]
    fn test_daemon_status_from_bd_047_format() {
        // bd 0.47+ returns status:"running" instead of running:bool
        let json = serde_json::json!({
            "workspace": "/Users/test/project",
            "pid": 99268,
            "version": "0.47.1",
            "status": "running",
            "started": "2026-02-11T22:42:42-03:00",
            "uptime_seconds": 34999.408,
            "local_mode": true
        });

        let status = DaemonStatus::from_json(json).unwrap();
        assert!(status.running);
        assert_eq!(status.pid, Some(99268));
        assert!(status.uptime_seconds.unwrap() > 34999.0);
    }

    #[test]
    fn test_activity_event_serialization() {
        let mut extra = HashMap::new();
        extra.insert("details".to_string(), serde_json::json!("test details"));

        let event = ActivityEvent {
            event_type: "issue.updated".to_string(),
            issue_id: Some("ISSUE-1".to_string()),
            gate_id: None,
            timestamp: "2024-01-01T00:00:00Z".to_string(),
            extra,
        };

        let json = serde_json::to_string(&event).unwrap();
        let deserialized: ActivityEvent = serde_json::from_str(&json).unwrap();

        assert_eq!(deserialized.event_type, "issue.updated");
        assert_eq!(deserialized.issue_id, Some("ISSUE-1".to_string()));
        assert!(deserialized.gate_id.is_none());
    }

    #[test]
    fn test_workspace_serialization() {
        let mut extra = HashMap::new();
        extra.insert("registry_key".to_string(), serde_json::json!("value"));

        let workspace = Workspace {
            path: "/home/user/project".to_string(),
            name: "project".to_string(),
            daemon_running: true,
            extra,
        };

        let json = serde_json::to_string(&workspace).unwrap();
        let deserialized: Workspace = serde_json::from_str(&json).unwrap();

        assert_eq!(deserialized.path, "/home/user/project");
        assert_eq!(deserialized.daemon_running, true);
    }
}
