VERSION ?= dev
COMMIT  ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "none")
DATE    ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
PREFIX  ?= /usr/local
BINARY  := maestro

LDFLAGS := -X github.com/spec-maestro/maestro-cli/internal/version.Version=$(VERSION) \
           -X github.com/spec-maestro/maestro-cli/internal/version.Commit=$(COMMIT) \
           -X github.com/spec-maestro/maestro-cli/internal/version.Date=$(DATE)

.PHONY: build test install uninstall clean

build:
	go build -ldflags "$(LDFLAGS)" -o $(BINARY) .

test:
	go test ./...

install: build
	install -d $(PREFIX)/bin
	install -m 755 $(BINARY) $(PREFIX)/bin/$(BINARY)

uninstall:
	rm -f $(PREFIX)/bin/$(BINARY)

clean:
	rm -f $(BINARY)
