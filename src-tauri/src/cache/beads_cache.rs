use crate::bd::types::{ActivityEvent, EpicStatus, Gate, Issue};
use crate::cache::dag::DagBuilder;
use crate::cache::DagGraph;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

const STALE_DURATION: Duration = Duration::from_secs(30);
const CACHE_FILE_NAME: &str = "agent-maestro-cache.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheStats {
    pub total_issues: usize,
    pub open: usize,
    pub closed: usize,
    pub in_progress: usize,
    pub blocked: usize,
    pub pending_gates: usize,
    pub last_sync: String,
}

pub struct BeadsCache {
    pub issues: HashMap<String, Issue>,
    pub gates: HashMap<String, Gate>,
    pub epics: HashMap<String, EpicStatus>,
    pub last_full_sync: Instant,
    pub cache_file_path: PathBuf,
}

impl BeadsCache {
    /// Create a new instance, loading from disk if available
    pub fn new() -> Result<Arc<RwLock<Self>>, CacheError> {
        let cache_file_path = Self::get_cache_file_path()?;

        // Try to load from disk
        if let Ok(cached) = Self::load_from_disk(&cache_file_path) {
            info!("Loaded cache from disk: {} issues", cached.issues.len());
            let cache = Self {
                issues: cached.issues,
                gates: cached.gates,
                epics: cached.epics,
                last_full_sync: Instant::now(),
                cache_file_path,
            };
            return Ok(Arc::new(RwLock::new(cache)));
        }

        // Return empty cache if not found
        info!("No cache found, starting with empty cache");
        let cache = Self {
            issues: HashMap::new(),
            gates: HashMap::new(),
            epics: HashMap::new(),
            last_full_sync: Instant::now(),
            cache_file_path,
        };
        Ok(Arc::new(RwLock::new(cache)))
    }

    /// Rebuild entire cache from a full load of issues
    pub async fn full_refresh(
        &mut self,
        issues: Vec<Issue>,
        gates: Vec<Gate>,
        epics: Vec<EpicStatus>,
    ) -> Result<(), CacheError> {
        debug!(
            "Full refresh: {} issues, {} gates, {} epics",
            issues.len(),
            gates.len(),
            epics.len()
        );

        let issues_map: HashMap<String, Issue> = issues
            .into_iter()
            .map(|issue| (issue.id.clone(), issue))
            .collect();

        let gates_map: HashMap<String, Gate> = gates
            .into_iter()
            .map(|gate| (gate.id.clone(), gate))
            .collect();

        let epics_map: HashMap<String, EpicStatus> = epics
            .into_iter()
            .map(|epic| (epic.id.clone(), epic))
            .collect();

        self.issues = issues_map;
        self.gates = gates_map;
        self.epics = epics_map;
        self.last_full_sync = Instant::now();

        // Persist to disk
        self.save_to_disk().await?;

        info!("Cache fully refreshed and persisted");
        Ok(())
    }

    /// Apply a single event incrementally
    pub async fn apply_event(&mut self, event: &ActivityEvent) -> Result<(), CacheError> {
        debug!("Applying event: {} (issue: {:?}, gate: {:?})",
            event.event_type, event.issue_id, event.gate_id);

        match event.event_type.as_str() {
            "issue.created" | "issue.updated" => {
                if let Some(issue_id) = &event.issue_id {
                    if let Some(issue_data) = event.extra.get("issue") {
                        if let Ok(issue) = serde_json::from_value::<Issue>(issue_data.clone()) {
                            self.issues.insert(issue_id.clone(), issue);
                            debug!("Updated issue: {}", issue_id);
                        }
                    }
                }
            }
            "issue.deleted" => {
                if let Some(issue_id) = &event.issue_id {
                    self.issues.remove(issue_id);
                    debug!("Removed issue: {}", issue_id);
                }
            }
            "gate.created" | "gate.updated" => {
                if let Some(gate_id) = &event.gate_id {
                    if let Some(gate_data) = event.extra.get("gate") {
                        if let Ok(gate) = serde_json::from_value::<Gate>(gate_data.clone()) {
                            self.gates.insert(gate_id.clone(), gate);
                            debug!("Updated gate: {}", gate_id);
                        }
                    }
                }
            }
            "gate.deleted" => {
                if let Some(gate_id) = &event.gate_id {
                    self.gates.remove(gate_id);
                    debug!("Removed gate: {}", gate_id);
                }
            }
            _ => {
                warn!("Unknown event type: {}", event.event_type);
            }
        }

        Ok(())
    }

    /// Build DAG for an epic
    pub async fn get_dag(&self, epic_id: &str) -> Result<Option<DagGraph>, CacheError> {
        let builder = DagBuilder::new(
            self.issues.clone(),
            self.gates.clone(),
            self.epics.clone(),
        );

        match builder.build_dag(epic_id) {
            Ok(dag) => {
                if dag.nodes.is_empty() {
                    Ok(None)
                } else {
                    Ok(Some(dag))
                }
            }
            Err(e) => Err(CacheError::DagBuildError(e)),
        }
    }

    /// Get gates needing human approval
    pub async fn get_pending_gates(&self) -> Result<Vec<Gate>, CacheError> {
        let pending_gates: Vec<Gate> = self
            .gates
            .values()
            .filter(|gate| gate.status == "pending" || gate.status == "blocked")
            .cloned()
            .collect();

        Ok(pending_gates)
    }

    /// Get cache statistics
    pub async fn get_stats(&self) -> Result<CacheStats, CacheError> {
        let mut open = 0;
        let mut closed = 0;
        let mut in_progress = 0;
        let mut blocked = 0;

        for issue in self.issues.values() {
            match issue.status.to_lowercase().as_str() {
                "open" | "todo" | "backlog" => open += 1,
                "in progress" | "in_progress" | "doing" => in_progress += 1,
                "closed" | "done" | "completed" => closed += 1,
                "blocked" => blocked += 1,
                _ => {}
            }
        }

        let pending_gates = self
            .gates
            .values()
            .filter(|gate| gate.status == "pending" || gate.status == "blocked")
            .count();

        let stats = CacheStats {
            total_issues: self.issues.len(),
            open,
            closed,
            in_progress,
            blocked,
            pending_gates,
            last_sync: format!("{:?}", self.last_full_sync.elapsed()),
        };

        Ok(stats)
    }

    /// Check if cache is stale (older than 30 seconds)
    pub async fn is_stale(&self) -> bool {
        self.last_full_sync.elapsed() > STALE_DURATION
    }

    /// Get cache file path
    fn get_cache_file_path() -> Result<PathBuf, CacheError> {
        let cache_dir = dirs::cache_dir()
            .ok_or_else(|| CacheError::IoError("Failed to get cache directory".to_string()))?;

        let cache_dir = cache_dir.join("agent-maestro");
        Ok(cache_dir.join(CACHE_FILE_NAME))
    }

    /// Save cache to disk
    async fn save_to_disk(&self) -> Result<(), CacheError> {
        let cache_data = SerializedCache {
            issues: self.issues.clone(),
            gates: self.gates.clone(),
            epics: self.epics.clone(),
            last_full_sync: Utc::now(),
        };

        let json = serde_json::to_string_pretty(&cache_data)
            .map_err(|e| CacheError::SerializationError(e.to_string()))?;

        // Ensure parent directory exists
        if let Some(parent) = self.cache_file_path.parent() {
            tokio::fs::create_dir_all(parent).await
                .map_err(|e| CacheError::IoError(format!("Failed to create cache dir: {}", e)))?;
        }

        tokio::fs::write(&self.cache_file_path, json)
            .await
            .map_err(|e| CacheError::IoError(format!("Failed to write cache: {}", e)))?;

        debug!("Cache saved to: {:?}", self.cache_file_path);
        Ok(())
    }

    /// Load cache from disk
    fn load_from_disk(path: &PathBuf) -> Result<SerializedCache, CacheError> {
        let json = std::fs::read_to_string(path)
            .map_err(|e| CacheError::IoError(format!("Failed to read cache: {}", e)))?;

        let cache_data: SerializedCache = serde_json::from_str(&json)
            .map_err(|e| CacheError::DeserializationError(e.to_string()))?;

        // Check if cache is too old
        if cache_data.last_full_sync + chrono::Duration::seconds(60) < Utc::now() {
            return Err(CacheError::StaleCache("Cache is too old".to_string()));
        }

        Ok(cache_data)
    }

    /// Get an issue by ID
    pub async fn get_issue(&self, id: &str) -> Option<Issue> {
        self.issues.get(id).cloned()
    }

    /// Get all issues
    pub async fn list_issues(&self) -> Vec<Issue> {
        self.issues.values().cloned().collect()
    }

    /// Get an epic by ID
    pub async fn get_epic(&self, id: &str) -> Option<EpicStatus> {
        self.epics.get(id).cloned()
    }

    /// Get all epics
    pub async fn list_epics(&self) -> Vec<EpicStatus> {
        self.epics.values().cloned().collect()
    }

    /// Search issues by title or status
    pub async fn search_issues(&self, query: &str) -> Vec<Issue> {
        let query_lower = query.to_lowercase();
        self.issues
            .values()
            .filter(|issue| {
                issue.title.to_lowercase().contains(&query_lower)
                    || issue.status.to_lowercase().contains(&query_lower)
            })
            .cloned()
            .collect()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SerializedCache {
    issues: HashMap<String, Issue>,
    gates: HashMap<String, Gate>,
    epics: HashMap<String, EpicStatus>,
    last_full_sync: DateTime<Utc>,
}

#[derive(Debug, thiserror::Error)]
pub enum CacheError {
    #[error("IO error: {0}")]
    IoError(String),

    #[error("Serialization error: {0}")]
    SerializationError(String),

    #[error("Deserialization error: {0}")]
    DeserializationError(String),

    #[error("Cache is stale: {0}")]
    StaleCache(String),

    #[error("DAG build error: {0}")]
    DagBuildError(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_issue(id: &str, title: &str, status: &str) -> Issue {
        Issue {
            id: id.to_string(),
            title: title.to_string(),
            status: status.to_string(),
            priority: None,
            labels: vec![],
            dependencies: vec![],
            assignee: None,
            owner: None,
            issue_type: Some("Task".to_string()),
            extra: HashMap::new(),
        }
    }

    #[tokio::test]
    async fn test_full_refresh() {
        let cache_dir = tempfile::tempdir().unwrap();
        let issues = vec![create_test_issue("TASK-1", "Test Task", "open")];

        let mut cache = BeadsCache {
            issues: HashMap::new(),
            gates: HashMap::new(),
            epics: HashMap::new(),
            last_full_sync: Instant::now(),
            cache_file_path: cache_dir.path().join("cache.json"),
        };

        cache.full_refresh(issues, vec![], vec![]).await.unwrap();

        assert_eq!(cache.issues.len(), 1);
        assert_eq!(cache.issues.get("TASK-1").unwrap().title, "Test Task");
    }

    #[tokio::test]
    async fn test_get_stats() {
        let cache = BeadsCache {
            issues: HashMap::from([
                ("TASK-1".to_string(), create_test_issue("TASK-1", "Task 1", "open")),
                ("TASK-2".to_string(), create_test_issue("TASK-2", "Task 2", "in_progress")),
                ("TASK-3".to_string(), create_test_issue("TASK-3", "Task 3", "closed")),
            ]),
            gates: HashMap::new(),
            epics: HashMap::new(),
            last_full_sync: Instant::now(),
            cache_file_path: PathBuf::from("/tmp/test-cache.json"),
        };

        let stats = cache.get_stats().await.unwrap();

        assert_eq!(stats.total_issues, 3);
        assert_eq!(stats.open, 1);
        assert_eq!(stats.in_progress, 1);
        assert_eq!(stats.closed, 1);
    }

    #[tokio::test]
    async fn test_search_issues() {
        let cache = BeadsCache {
            issues: HashMap::from([
                ("TASK-1".to_string(), create_test_issue("TASK-1", "Fix bug", "open")),
                ("TASK-2".to_string(), create_test_issue("TASK-2", "Add feature", "open")),
                ("TASK-3".to_string(), create_test_issue("TASK-3", "Test code", "closed")),
            ]),
            gates: HashMap::new(),
            epics: HashMap::new(),
            last_full_sync: Instant::now(),
            cache_file_path: PathBuf::from("/tmp/test-cache.json"),
        };

        let results = cache.search_issues("bug").await;

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, "TASK-1");
    }

    #[tokio::test]
    async fn test_is_stale() {
        let mut cache = BeadsCache {
            issues: HashMap::new(),
            gates: HashMap::new(),
            epics: HashMap::new(),
            last_full_sync: Instant::now(),
            cache_file_path: PathBuf::from("/tmp/test-cache.json"),
        };

        assert!(!cache.is_stale().await);

        // Simulate old cache
        cache.last_full_sync = Instant::now() - Duration::from_secs(35);
        assert!(cache.is_stale().await);
    }

    #[tokio::test]
    async fn test_apply_event_issue_updated() {
        let mut cache = BeadsCache {
            issues: HashMap::new(),
            gates: HashMap::new(),
            epics: HashMap::new(),
            last_full_sync: Instant::now(),
            cache_file_path: PathBuf::from("/tmp/test-cache.json"),
        };

        let mut extra = HashMap::new();
        extra.insert("issue".to_string(), serde_json::json!({
            "id": "TASK-1",
            "title": "Updated Title",
            "status": "in_progress",
            "priority": null,
            "labels": [],
            "dependencies": [],
            "assignee": null,
            "issue_type": null,
            "extra": {}
        }));

        let event = ActivityEvent {
            event_type: "issue.updated".to_string(),
            issue_id: Some("TASK-1".to_string()),
            gate_id: None,
            timestamp: "2024-01-01T00:00:00Z".to_string(),
            extra,
        };

        cache.apply_event(&event).await.unwrap();

        assert_eq!(cache.issues.len(), 1);
        assert_eq!(cache.issues.get("TASK-1").unwrap().title, "Updated Title");
    }

    #[tokio::test]
    async fn test_apply_event_issue_deleted() {
        let cache_dir = tempfile::tempdir().unwrap();

        let mut cache = BeadsCache {
            issues: HashMap::from([(
                "TASK-1".to_string(),
                create_test_issue("TASK-1", "Task 1", "open"),
            )]),
            gates: HashMap::new(),
            epics: HashMap::new(),
            last_full_sync: Instant::now(),
            cache_file_path: cache_dir.path().join("cache.json"),
        };

        assert_eq!(cache.issues.len(), 1);

        let event = ActivityEvent {
            event_type: "issue.deleted".to_string(),
            issue_id: Some("TASK-1".to_string()),
            gate_id: None,
            timestamp: "2024-01-01T00:00:00Z".to_string(),
            extra: HashMap::new(),
        };

        cache.apply_event(&event).await.unwrap();

        assert_eq!(cache.issues.len(), 0);
    }

    #[tokio::test]
    async fn test_apply_event_gate_updated() {
        let mut cache = BeadsCache {
            issues: HashMap::new(),
            gates: HashMap::new(),
            epics: HashMap::new(),
            last_full_sync: Instant::now(),
            cache_file_path: PathBuf::from("/tmp/test-cache.json"),
        };

        let mut extra = HashMap::new();
        extra.insert("gate".to_string(), serde_json::json!({
            "id": "GATE-1",
            "issue_id": "TASK-1",
            "gate_type": "compile",
            "status": "approved",
            "reason": "Looks good",
            "extra": {}
        }));

        let event = ActivityEvent {
            event_type: "gate.updated".to_string(),
            issue_id: None,
            gate_id: Some("GATE-1".to_string()),
            timestamp: "2024-01-01T00:00:00Z".to_string(),
            extra,
        };

        cache.apply_event(&event).await.unwrap();

        assert_eq!(cache.gates.len(), 1);
        assert_eq!(cache.gates.get("GATE-1").unwrap().status, "approved");
    }

    #[tokio::test]
    async fn test_get_pending_gates() {
        let extra = HashMap::new();
        let cache = BeadsCache {
            issues: HashMap::new(),
            gates: HashMap::from([
                (
                    "GATE-1".to_string(),
                    Gate {
                        id: "GATE-1".to_string(),
                        issue_id: "TASK-1".to_string(),
                        gate_type: "compile".to_string(),
                        status: "pending".to_string(),
                        reason: None,
                        extra: extra.clone(),
                    },
                ),
                (
                    "GATE-2".to_string(),
                    Gate {
                        id: "GATE-2".to_string(),
                        issue_id: "TASK-2".to_string(),
                        gate_type: "pm-approval".to_string(),
                        status: "approved".to_string(),
                        reason: None,
                        extra: extra.clone(),
                    },
                ),
                (
                    "GATE-3".to_string(),
                    Gate {
                        id: "GATE-3".to_string(),
                        issue_id: "TASK-3".to_string(),
                        gate_type: "compile".to_string(),
                        status: "blocked".to_string(),
                        reason: None,
                        extra,
                    },
                ),
            ]),
            epics: HashMap::new(),
            last_full_sync: Instant::now(),
            cache_file_path: PathBuf::from("/tmp/test-cache.json"),
        };

        let pending = cache.get_pending_gates().await.unwrap();

        assert_eq!(pending.len(), 2); // pending and blocked
        assert!(pending.iter().any(|g| g.id == "GATE-1"));
        assert!(pending.iter().any(|g| g.id == "GATE-3"));
    }

    #[tokio::test]
    async fn test_get_issue_and_list_issues() {
        let cache = BeadsCache {
            issues: HashMap::from([
                ("TASK-1".to_string(), create_test_issue("TASK-1", "Task 1", "open")),
                ("TASK-2".to_string(), create_test_issue("TASK-2", "Task 2", "closed")),
            ]),
            gates: HashMap::new(),
            epics: HashMap::new(),
            last_full_sync: Instant::now(),
            cache_file_path: PathBuf::from("/tmp/test-cache.json"),
        };

        // Test get_issue
        let issue = cache.get_issue("TASK-1").await;
        assert!(issue.is_some());
        assert_eq!(issue.unwrap().title, "Task 1");

        let nonexistent = cache.get_issue("TASK-999").await;
        assert!(nonexistent.is_none());

        // Test list_issues
        let all_issues = cache.list_issues().await;
        assert_eq!(all_issues.len(), 2);
    }

    #[tokio::test]
    async fn test_get_epic_and_list_epics() {
        let cache = BeadsCache {
            issues: HashMap::new(),
            gates: HashMap::new(),
            epics: HashMap::from([
                (
                    "EPIC-1".to_string(),
                    EpicStatus {
                        id: "EPIC-1".to_string(),
                        title: "Epic 1".to_string(),
                        total: 10,
                        open: 5,
                        closed: 3,
                        in_progress: 2,
                        blocked: 0,
                        extra: HashMap::new(),
                    },
                ),
                (
                    "EPIC-2".to_string(),
                    EpicStatus {
                        id: "EPIC-2".to_string(),
                        title: "Epic 2".to_string(),
                        total: 5,
                        open: 2,
                        closed: 2,
                        in_progress: 1,
                        blocked: 0,
                        extra: HashMap::new(),
                    },
                ),
            ]),
            last_full_sync: Instant::now(),
            cache_file_path: PathBuf::from("/tmp/test-cache.json"),
        };

        let epic = cache.get_epic("EPIC-1").await;
        assert!(epic.is_some());
        assert_eq!(epic.unwrap().total, 10);

        let all_epics = cache.list_epics().await;
        assert_eq!(all_epics.len(), 2);
    }
}
