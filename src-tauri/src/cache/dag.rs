use crate::bd::types::{EpicStatus, Gate, Issue};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DagGraph {
    pub nodes: Vec<DagNode>,
    pub edges: Vec<DagEdge>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DagNode {
    pub id: String,
    pub title: String,
    pub node_type: NodeType,
    pub status: String,
    pub assignee: Option<String>,
    /// Optional opencode session ID if this task has an active session
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    /// Optional task execution status from orchestrator
    #[serde(skip_serializing_if = "Option::is_none")]
    pub task_status: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum NodeType {
    Epic,
    Task,
    Review,
    Gate,
    PmValidation,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DagEdge {
    pub source: String,
    pub target: String,
    pub edge_type: EdgeType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EdgeType {
    Blocks,
    RelatesTo,
}

pub struct DagBuilder {
    issues: HashMap<String, Issue>,
    gates: HashMap<String, Gate>,
    epics: HashMap<String, EpicStatus>,
}

impl DagBuilder {
    pub fn new(
        issues: HashMap<String, Issue>,
        gates: HashMap<String, Gate>,
        epics: HashMap<String, EpicStatus>,
    ) -> Self {
        Self {
            issues,
            gates,
            epics,
        }
    }

    /// Builds a DAG graph for a given epic_id
    pub fn build_dag(&self, epic_id: &str) -> Result<DagGraph, String> {
        let mut nodes = Vec::new();
        let mut edges = Vec::new();

        // Find all issues belonging to this epic
        let epic_issues: Vec<_> = self
            .issues
            .values()
            .filter(|issue| {
                self.is_issue_in_epic(issue, epic_id)
                    || issue.issue_type.as_deref() == Some("Epic") && issue.id == epic_id
            })
            .collect();

        // Add epic node if it exists as an issue
        if let Some(epic_issue) = self.issues.get(epic_id) {
            nodes.push(DagNode {
                id: epic_issue.id.clone(),
                title: epic_issue.title.clone(),
                node_type: NodeType::Epic,
                status: epic_issue.status.clone(),
                assignee: epic_issue.effective_assignee().map(String::from),
                session_id: None,
                task_status: None,
            });
        }

        // Process all issues in the epic
        for issue in &epic_issues {
            let node_type = self.infer_node_type(issue);
            let dag_node = DagNode {
                id: issue.id.clone(),
                title: issue.title.clone(),
                node_type,
                status: issue.status.clone(),
                assignee: issue.effective_assignee().map(String::from),
                session_id: None,
                task_status: None,
            };
            nodes.push(dag_node);

            // Add dependency edges
            for dep_value in &issue.dependencies {
                // Extract string ID from Value (could be string or object with "id" field)
                let dep_id = if let Some(s) = dep_value.as_str() {
                    s.to_string()
                } else if let Some(obj) = dep_value.as_object() {
                    if let Some(id) = obj.get("id").and_then(|id| id.as_str()) {
                        id.to_string()
                    } else {
                        continue;
                    }
                } else {
                    continue;
                };

                if self.issues.contains_key(&dep_id) {
                    edges.push(DagEdge {
                        source: dep_id,
                        target: issue.id.clone(),
                        edge_type: EdgeType::Blocks,
                    });
                }
            }
        }

        // Add gate nodes and edges
        for gate in self.gates.values() {
            if self.is_issue_in_epic(
                self.issues.get(&gate.issue_id).unwrap_or(&Issue {
                    id: String::new(),
                    title: String::new(),
                    status: String::new(),
                    priority: None,
                    labels: vec![],
                    dependencies: vec![],
                    assignee: None,
                    owner: None,
                    issue_type: None,
                    extra: HashMap::new(),
                }),
                epic_id,
            ) {
                let gate_node = DagNode {
                    id: gate.id.clone(),
                    title: format!("Gate: {}", gate.gate_type),
                    node_type: NodeType::Gate,
                    status: gate.status.clone(),
                    assignee: None,
                    session_id: None,
                    task_status: None,
                };
                nodes.push(gate_node);

                // Gate depends on the issue
                if self.issues.contains_key(&gate.issue_id) {
                    edges.push(DagEdge {
                        source: gate.issue_id.clone(),
                        target: gate.id.clone(),
                        edge_type: EdgeType::Blocks,
                    });
                }
            }
        }

        Ok(DagGraph { nodes, edges })
    }

    /// Infers node type from issue labels and type
    fn infer_node_type(&self, issue: &Issue) -> NodeType {
        // Check labels first
        for label in &issue.labels {
            let label_lower = label.to_lowercase();
            if label_lower.contains("review") {
                return NodeType::Review;
            }
            if label_lower.contains("gate") {
                return NodeType::Gate;
            }
            if label_lower.contains("pm-validation") || label_lower.contains("pm validation") {
                return NodeType::PmValidation;
            }
        }

        // Fall back to issue_type
        match issue.issue_type.as_deref() {
            Some("Epic") => NodeType::Epic,
            Some("Gate") => NodeType::Gate,
            _ => NodeType::Task,
        }
    }

    /// Determines if an issue belongs to an epic
    fn is_issue_in_epic(&self, issue: &Issue, epic_id: &str) -> bool {
        // Check if issue's extra contains epic_id or parent_epic field
        if let Some(epic) = issue.extra.get("epic_id").and_then(|v| v.as_str()) {
            return epic == epic_id;
        }
        if let Some(epic) = issue.extra.get("parent").and_then(|v| v.as_str()) {
            return epic == epic_id;
        }
        // Check if issue is in the epic status data
        self.epics
            .get(epic_id)
            .is_some_and(|_epic| issue.extra.get("epic_id") == Some(&serde_json::json!(epic_id)))
    }

    /// Enriches DAG nodes with orchestrator session status information.
    ///
    /// # Arguments
    /// * `graph` - The DAG graph to enrich
    /// * `task_sessions` - Map of task ID to (session_id, task_status) pairs
    ///
    /// Returns an enriched graph with session status merged into each node.
    pub fn enrich_with_sessions(
        &self,
        mut graph: DagGraph,
        task_sessions: &std::collections::HashMap<String, (Option<String>, String)>,
    ) -> DagGraph {
        for node in &mut graph.nodes {
            if let Some((session_id, task_status)) = task_sessions.get(&node.id) {
                node.session_id = session_id.clone();
                node.task_status = Some(task_status.clone());
            }
        }
        graph
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn create_test_issue(
        id: &str,
        title: &str,
        status: &str,
        issue_type: &str,
        labels: Vec<&str>,
        deps: Vec<&str>,
    ) -> Issue {
        let mut extra = HashMap::new();
        extra.insert("epic_id".to_string(), serde_json::json!("EPIC-123"));

        Issue {
            id: id.to_string(),
            title: title.to_string(),
            status: status.to_string(),
            priority: None,
            labels: labels.into_iter().map(String::from).collect(),
            dependencies: deps.into_iter().map(|s| serde_json::json!(s)).collect(),
            assignee: None,
            owner: None,
            issue_type: Some(issue_type.to_string()),
            extra,
        }
    }

    #[test]
    fn test_infer_node_type_from_labels() {
        let builder = DagBuilder::new(HashMap::new(), HashMap::new(), HashMap::new());

        let task_issue = create_test_issue("TASK-1", "Task", "open", "Task", vec![], vec![]);
        assert!(matches!(
            builder.infer_node_type(&task_issue),
            NodeType::Task
        ));

        let review_issue =
            create_test_issue("TASK-2", "Task", "open", "Task", vec!["review"], vec![]);
        assert!(matches!(
            builder.infer_node_type(&review_issue),
            NodeType::Review
        ));

        let gate_issue = create_test_issue("TASK-3", "Task", "open", "Task", vec!["gate"], vec![]);
        assert!(matches!(
            builder.infer_node_type(&gate_issue),
            NodeType::Gate
        ));

        let pm_issue = create_test_issue(
            "TASK-4",
            "Task",
            "open",
            "Task",
            vec!["pm-validation"],
            vec![],
        );
        assert!(matches!(
            builder.infer_node_type(&pm_issue),
            NodeType::PmValidation
        ));
    }

    #[test]
    fn test_build_dag_simple() {
        let mut issues = HashMap::new();
        issues.insert(
            "TASK-1".to_string(),
            create_test_issue("TASK-1", "First Task", "open", "Task", vec![], vec![]),
        );

        let builder = DagBuilder::new(issues, HashMap::new(), HashMap::new());
        let dag = builder.build_dag("EPIC-123").unwrap();

        assert_eq!(dag.nodes.len(), 1);
        assert_eq!(dag.nodes[0].id, "TASK-1");
        assert!(matches!(dag.nodes[0].node_type, NodeType::Task));
        assert_eq!(dag.edges.len(), 0);
    }

    #[test]
    fn test_build_dag_with_dependencies() {
        let mut issues = HashMap::new();
        issues.insert(
            "TASK-1".to_string(),
            create_test_issue("TASK-1", "Task 1", "open", "Task", vec![], vec![]),
        );
        issues.insert(
            "TASK-2".to_string(),
            create_test_issue("TASK-2", "Task 2", "open", "Task", vec![], vec!["TASK-1"]),
        );

        let builder = DagBuilder::new(issues, HashMap::new(), HashMap::new());
        let dag = builder.build_dag("EPIC-123").unwrap();

        assert_eq!(dag.nodes.len(), 2);
        assert_eq!(dag.edges.len(), 1);
        assert_eq!(dag.edges[0].source, "TASK-1");
        assert_eq!(dag.edges[0].target, "TASK-2");
        assert!(matches!(dag.edges[0].edge_type, EdgeType::Blocks));
    }

    #[test]
    fn test_build_dag_empty_issue_list() {
        let issues = HashMap::new();
        let builder = DagBuilder::new(issues, HashMap::new(), HashMap::new());
        let dag = builder.build_dag("EPIC-123").unwrap();

        assert_eq!(dag.nodes.len(), 0);
        assert_eq!(dag.edges.len(), 0);
    }

    #[test]
    fn test_build_dag_linear_dependency_chain() {
        let mut issues = HashMap::new();
        issues.insert(
            "TASK-1".to_string(),
            create_test_issue("TASK-1", "Task 1", "open", "Task", vec![], vec![]),
        );
        issues.insert(
            "TASK-2".to_string(),
            create_test_issue("TASK-2", "Task 2", "open", "Task", vec![], vec!["TASK-1"]),
        );
        issues.insert(
            "TASK-3".to_string(),
            create_test_issue("TASK-3", "Task 3", "open", "Task", vec![], vec!["TASK-2"]),
        );
        issues.insert(
            "TASK-4".to_string(),
            create_test_issue("TASK-4", "Task 4", "open", "Task", vec![], vec!["TASK-3"]),
        );

        let builder = DagBuilder::new(issues, HashMap::new(), HashMap::new());
        let dag = builder.build_dag("EPIC-123").unwrap();

        assert_eq!(dag.nodes.len(), 4);
        assert_eq!(dag.edges.len(), 3);

        // Verify linear chain: TASK-1 -> TASK-2 -> TASK-3 -> TASK-4
        let edge_sources: Vec<_> = dag.edges.iter().map(|e| e.source.as_str()).collect();
        let edge_targets: Vec<_> = dag.edges.iter().map(|e| e.target.as_str()).collect();

        assert!(edge_sources.contains(&"TASK-1"));
        assert!(edge_targets.contains(&"TASK-2"));
        assert!(edge_sources.contains(&"TASK-2"));
        assert!(edge_targets.contains(&"TASK-3"));
    }

    #[test]
    fn test_build_dag_diamond_dependency_pattern() {
        // Diamond pattern: TASK-1 depends on both TASK-2 and TASK-3
        // TASK-2 and TASK-3 both depend on TASK-0
        let mut issues = HashMap::new();
        issues.insert(
            "TASK-0".to_string(),
            create_test_issue("TASK-0", "Base Task", "open", "Task", vec![], vec![]),
        );
        issues.insert(
            "TASK-2".to_string(),
            create_test_issue("TASK-2", "Task 2", "open", "Task", vec![], vec!["TASK-0"]),
        );
        issues.insert(
            "TASK-3".to_string(),
            create_test_issue("TASK-3", "Task 3", "open", "Task", vec![], vec!["TASK-0"]),
        );
        issues.insert(
            "TASK-1".to_string(),
            create_test_issue(
                "TASK-1",
                "Merge Task",
                "open",
                "Task",
                vec![],
                vec!["TASK-2", "TASK-3"],
            ),
        );

        let builder = DagBuilder::new(issues, HashMap::new(), HashMap::new());
        let dag = builder.build_dag("EPIC-123").unwrap();

        assert_eq!(dag.nodes.len(), 4);
        assert_eq!(dag.edges.len(), 4); // 0->2, 0->3, 2->1, 3->1

        // Verify TASK-1 has two incoming edges
        let task1_incoming: Vec<_> = dag
            .edges
            .iter()
            .filter(|e| e.target == "TASK-1")
            .map(|e| e.source.as_str())
            .collect();

        assert_eq!(task1_incoming.len(), 2);
        assert!(task1_incoming.contains(&"TASK-2"));
        assert!(task1_incoming.contains(&"TASK-3"));
    }

    #[test]
    fn test_build_dag_with_multiple_reviews() {
        let mut issues = HashMap::new();
        issues.insert(
            "TASK-1".to_string(),
            create_test_issue("TASK-1", "Implementation", "open", "Task", vec![], vec![]),
        );
        issues.insert(
            "REVIEW-1".to_string(),
            create_test_issue(
                "REVIEW-1",
                "Review 1",
                "open",
                "Task",
                vec!["review"],
                vec!["TASK-1"],
            ),
        );
        issues.insert(
            "REVIEW-2".to_string(),
            create_test_issue(
                "REVIEW-2",
                "Review 2",
                "open",
                "Task",
                vec!["review"],
                vec!["TASK-1"],
            ),
        );

        let builder = DagBuilder::new(issues, HashMap::new(), HashMap::new());
        let dag = builder.build_dag("EPIC-123").unwrap();

        assert_eq!(dag.nodes.len(), 3);

        // Verify review nodes are typed correctly
        let review_nodes: Vec<_> = dag
            .nodes
            .iter()
            .filter(|n| matches!(n.node_type, NodeType::Review))
            .collect();

        assert_eq!(review_nodes.len(), 2);
    }

    #[test]
    fn test_build_dag_with_gates() {
        let mut issues = HashMap::new();
        issues.insert(
            "TASK-1".to_string(),
            create_test_issue("TASK-1", "Task 1", "open", "Task", vec![], vec![]),
        );

        let mut gates = HashMap::new();
        gates.insert(
            "GATE-1".to_string(),
            Gate {
                id: "GATE-1".to_string(),
                issue_id: "TASK-1".to_string(),
                gate_type: "compile".to_string(),
                status: "pending".to_string(),
                reason: None,
                extra: HashMap::new(),
            },
        );

        let builder = DagBuilder::new(issues, gates, HashMap::new());
        let dag = builder.build_dag("EPIC-123").unwrap();

        // Should have 1 issue node + 1 gate node + 1 edge
        assert_eq!(dag.nodes.len(), 2);

        let gate_nodes: Vec<_> = dag
            .nodes
            .iter()
            .filter(|n| matches!(n.node_type, NodeType::Gate))
            .collect();

        assert_eq!(gate_nodes.len(), 1);
        assert!(gate_nodes[0].title.contains("Gate"));
    }

    #[test]
    fn test_dag_node_type_from_pm_validation_label() {
        let issue = create_test_issue(
            "PM-1",
            "PM Validation",
            "open",
            "Task",
            vec!["pm-validation"],
            vec![],
        );
        let builder = DagBuilder::new(HashMap::new(), HashMap::new(), HashMap::new());

        assert!(matches!(
            builder.infer_node_type(&issue),
            NodeType::PmValidation
        ));
    }

    #[test]
    fn test_dag_node_type_from_issue_type() {
        let mut extra = HashMap::new();
        extra.insert("epic_id".to_string(), serde_json::json!("EPIC-123"));

        let issue = Issue {
            id: "EPIC-1".to_string(),
            title: "Epic Title".to_string(),
            status: "open".to_string(),
            priority: None,
            labels: vec![],
            dependencies: vec![],
            assignee: None,
            owner: None,
            issue_type: Some("Epic".to_string()),
            extra,
        };

        let builder = DagBuilder::new(HashMap::new(), HashMap::new(), HashMap::new());
        assert!(matches!(builder.infer_node_type(&issue), NodeType::Epic));
    }

    #[test]
    fn test_is_issue_in_epic() {
        let mut extra = HashMap::new();
        extra.insert("epic_id".to_string(), serde_json::json!("EPIC-123"));

        let issue = Issue {
            id: "TASK-1".to_string(),
            title: "Test".to_string(),
            status: "open".to_string(),
            priority: None,
            labels: vec![],
            dependencies: vec![],
            assignee: None,
            owner: None,
            issue_type: None,
            extra,
        };

        let builder = DagBuilder::new(HashMap::new(), HashMap::new(), HashMap::new());
        assert!(builder.is_issue_in_epic(&issue, "EPIC-123"));
        assert!(!builder.is_issue_in_epic(&issue, "EPIC-456"));
    }

    #[test]
    fn test_enrich_with_sessions() {
        let mut issues = HashMap::new();
        issues.insert(
            "TASK-1".to_string(),
            create_test_issue("TASK-1", "Task 1", "open", "Task", vec![], vec![]),
        );

        let builder = DagBuilder::new(issues, HashMap::new(), HashMap::new());
        let dag = builder.build_dag("EPIC-123").unwrap();

        let mut task_sessions = HashMap::new();
        task_sessions.insert(
            "TASK-1".to_string(),
            (Some("session-123".to_string()), "running".to_string()),
        );

        let enriched = builder.enrich_with_sessions(dag, &task_sessions);

        assert_eq!(enriched.nodes.len(), 1);
        assert_eq!(
            enriched.nodes[0].session_id,
            Some("session-123".to_string())
        );
        assert_eq!(enriched.nodes[0].task_status, Some("running".to_string()));
    }
}
