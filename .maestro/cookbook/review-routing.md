# Review Routing — Risk Classification

Use this table to classify files by risk level when reviewing.

## Risk Levels

### HIGH RISK — Always review thoroughly

- Business logic files (commands, handlers, use cases)
- Data access layer (repositories, queries)
- Event handlers and consumers
- Authentication/authorization code
- Payment/financial processing
- API endpoint handlers
- Database migrations

### MEDIUM RISK — Review if >50 lines changed

- Service wiring/configuration
- Middleware
- DTO/request mapping code
- Integration adapters
- Build and deployment scripts

### LOW RISK — Skip review (close as SKIPPED)

- Auto-generated code (protobuf, openapi, mocks)
- Pure data structs with no methods
- Type definitions and interfaces (no logic)
- Constants and enums
- Test fixtures and test data files
- Documentation-only changes
- Import-only changes

## Classification Rules

1. **When in doubt, classify UP** — If unsure between MEDIUM and HIGH, choose HIGH
2. **Modified files are riskier** — A modified file with existing functionality is riskier than a new file
3. **Diff size matters for MEDIUM** — Only review MEDIUM files if the diff exceeds 50 lines
4. **Context matters** — A LOW RISK struct that is central to business logic should be classified MEDIUM
