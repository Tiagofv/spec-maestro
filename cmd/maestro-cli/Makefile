VERSION ?= dev
COMMIT  ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "none")
DATE    ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

LDFLAGS := -X github.com/spec-maestro/maestro-cli/internal/version.Version=$(VERSION) \
           -X github.com/spec-maestro/maestro-cli/internal/version.Commit=$(COMMIT) \
           -X github.com/spec-maestro/maestro-cli/internal/version.Date=$(DATE)

.PHONY: build
build:
	go build -ldflags "$(LDFLAGS)" -o maestro .

.PHONY: test
test:
	go test ./...
