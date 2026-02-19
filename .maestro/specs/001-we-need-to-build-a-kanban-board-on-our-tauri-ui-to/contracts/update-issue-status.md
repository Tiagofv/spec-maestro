# API Contract: Update Issue Status

## Endpoint

`POST /issues/{id}/status`

## Purpose

Update the status of an existing issue/task.

## Request

### Path Parameters

| Parameter | Type   | Required | Description                     |
| --------- | ------ | -------- | ------------------------------- |
| id        | string | Yes      | Issue ID (e.g., "001-task-123") |

### Body

```json
{
  "status": "in_progress"
}
```

### Body Fields

| Field  | Type   | Required | Description                                            |
| ------ | ------ | -------- | ------------------------------------------------------ |
| status | string | Yes      | New status: "open", "in_progress", "blocked", "closed" |

## Response

### Success (200 OK)

```json
{
  "id": "001-task-123",
  "title": "Implement kanban board",
  "status": "in_progress",
  "priority": 2,
  "labels": ["feature", "ui"],
  "dependencies": [],
  "assignee": "john.doe",
  "owner": "john.doe",
  "issue_type": "Task"
}
```

### Errors

| Status | Code                | Description                 |
| ------ | ------------------- | --------------------------- |
| 400    | invalid_status      | Status value not recognized |
| 404    | issue_not_found     | Issue ID does not exist     |
| 503    | service_unavailable | bd service is unreachable   |

## Events

On successful update, emits:

```json
{
  "type": "IssueUpdated",
  "source": "Bd",
  "issue": {
    /* updated issue object */
  }
}
```

## Tauri Command

```rust
#[tauri::command]
async fn update_issue_status(
    issue_id: String,
    status: String,
    app: AppHandle,
) -> Result<Issue, String>
```
