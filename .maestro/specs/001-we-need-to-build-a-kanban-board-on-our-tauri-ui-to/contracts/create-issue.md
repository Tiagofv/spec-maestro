# API Contract: Create Issue

## Endpoint

`POST /issues`

## Purpose

Create a new issue/task.

## Request

### Body

```json
{
  "title": "New task from kanban board",
  "status": "open",
  "priority": 2,
  "assignee": "john.doe",
  "labels": ["feature"]
}
```

### Body Fields

| Field    | Type     | Required | Default | Description                           |
| -------- | -------- | -------- | ------- | ------------------------------------- |
| title    | string   | Yes      | -       | Task title                            |
| status   | string   | No       | "open"  | Initial status                        |
| priority | number   | No       | 2       | Priority level (0-4, lower is higher) |
| assignee | string   | No       | null    | Username to assign                    |
| labels   | string[] | No       | []      | Array of label strings                |

## Response

### Success (201 Created)

```json
{
  "id": "001-task-456",
  "title": "New task from kanban board",
  "status": "open",
  "priority": 2,
  "labels": ["feature"],
  "dependencies": [],
  "assignee": "john.doe",
  "owner": "john.doe",
  "issue_type": "Task"
}
```

### Errors

| Status | Code                | Description                             |
| ------ | ------------------- | --------------------------------------- |
| 400    | invalid_data        | Missing required fields or invalid data |
| 503    | service_unavailable | bd service is unreachable               |

## Events

On successful creation, emits:

```json
{
  "type": "IssueUpdated",
  "source": "Bd",
  "issue": {
    /* created issue object */
  }
}
```

## Tauri Command

```rust
#[tauri::command]
async fn create_issue(
    issue: CreateIssueRequest,
    app: AppHandle,
) -> Result<Issue, String>

struct CreateIssueRequest {
    title: String,
    status: Option<String>,
    priority: Option<i32>,
    assignee: Option<String>,
    labels: Option<Vec<String>>,
}
```
