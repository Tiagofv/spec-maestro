# Global Review Conventions

These conventions apply to all code reviews. Local conventions in project `CLAUDE.md` take precedence.

## Error Handling

- All errors must be wrapped with context (no bare `return err`)
- Use structured error types where possible
- Log errors at the point of handling, not creation
- Never swallow errors silently

## Naming

- Functions: verb + noun (GetUser, CreateOrder, HandlePayment)
- Variables: descriptive, no single-letter except loop counters
- Packages/modules: singular nouns, lowercase
- Constants: UPPER_SNAKE_CASE or PascalCase (language-dependent)

## Testing

- Test names describe behavior: TestGetUser_WhenNotFound_ReturnsError
- Table-driven tests for multiple scenarios
- Mock external dependencies, not internal logic
- Assert on behavior, not implementation

## Security

- Never log PII (emails, SSNs, payment info)
- Use parameterized queries (no string concatenation for SQL)
- Validate all input at boundaries
- Use constant-time comparison for secrets

## Performance

- Avoid N+1 queries
- Use pagination for list endpoints
- Consider caching for read-heavy paths
- Profile before optimizing
