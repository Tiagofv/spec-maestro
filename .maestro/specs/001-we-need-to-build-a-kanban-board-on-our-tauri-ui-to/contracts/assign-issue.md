# API Contract: Assign Issue

## Endpoint

`POST /issues/{id}/assign`

## Purpose

Assign or reassign an issue to a user.

## Request

### Path Parameters

| Parameter | Type   | Required | Description |
| --------- | ------ | -------- | ----------- |
| id        | string | Yes      | Issue ID    |

### Body

```json
{
  "assignee": "jane.smith"
}
```

or to unassign:

```json
{
  "assignee": null
}
```

### Body Fields

| Field    | Type   | Required | Description                             |
| -------- | ------ | -------- | --------------------------------------- |
| assignee | string | No       | Username to assign, or null to unassign |

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
  "assignee": "jane.smith",
  "owner": "jane.smith",
  "issue_type": "Task"
}
```

### Errors

| Status | Code                | Description               |
| ------ | ------------------- | ------------------------- |
| 404    | issue_not_found     | Issue ID does not exist   |
| 503    | service_unavailable | bd service is unreachable |

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
async fn assign_issue(
    issue_id: String,
    assignee: Option<String>,
    app: AppHandle,
) -> Result<Issue, String>
```
