# Review Output Schema

Reviews must output JSON in this exact format:

```json
{
  "verdict": "PASS | MINOR | CRITICAL",
  "issues": [
    {
      "severity": "CRITICAL | MINOR",
      "file": "path/to/file",
      "line": 42,
      "cause": "feature-regression | nil-pointer | wrong-error | missing-impl | etc",
      "description": "One sentence describing the issue"
    }
  ],
  "summary": "One sentence overall assessment"
}
```

## Verdict Definitions

- **PASS**: No issues found. Code is ready to merge.
- **MINOR**: Style, naming, or optimization suggestions. Does not block merge.
- **CRITICAL**: Must be fixed before merge. Includes: feature regression, security issues, data loss, incorrect logic.

## Cause Categories

| Cause              | Description                                         |
| ------------------ | --------------------------------------------------- |
| feature-regression | Removed existing functionality not required by task |
| nil-pointer        | Dereferencing potentially nil value                 |
| wrong-error        | Incorrect error comparison or handling              |
| missing-impl       | Required functionality not implemented              |
| missing-field      | Required field not included                         |
| security           | Security vulnerability                              |
| data-loss          | Potential data loss or corruption                   |
| breaking-change    | Unintended API breaking change                      |

## Issue Priority

When multiple issues exist:

1. List CRITICAL issues first
2. Within CRITICAL, list feature-regression first
3. Then list MINOR issues
