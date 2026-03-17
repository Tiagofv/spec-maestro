VERSION ?= dev
COMMIT  ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "none")
DATE    ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
PREFIX  ?= /usr/local
BINARY  := maestro

LDFLAGS := -X github.com/spec-maestro/maestro-cli/internal/version.Version=$(VERSION) \
           -X github.com/spec-maestro/maestro-cli/internal/version.Commit=$(COMMIT) \
           -X github.com/spec-maestro/maestro-cli/internal/version.Date=$(DATE)

REPO    := Tiagofv/spec-maestro
OS      := $(shell uname -s)
ARCH    := $(shell uname -m)

.PHONY: build test install uninstall clean generate upgrade download

generate:
	go generate ./...

build: generate
	go build -ldflags "$(LDFLAGS)" -o $(BINARY) .

test:
	go test ./...

install: build
	install -d $(PREFIX)/bin
	install -m 755 $(BINARY) $(PREFIX)/bin/$(BINARY)

uninstall:
	rm -f $(PREFIX)/bin/$(BINARY)

upgrade: build
	@echo "Installing $(BINARY) to $(PREFIX)/bin (requires sudo)..."
	sudo install -m 755 $(BINARY) $(PREFIX)/bin/$(BINARY)
	@echo "✓ $(shell $(PREFIX)/bin/$(BINARY) --version 2>/dev/null || echo $(BINARY) installed)"

download:
	@if [ -z "$(TAG)" ]; then \
		echo "Usage: make download TAG=v0.0.8"; \
		echo ""; \
		echo "Available tags:"; \
		gh release list --repo $(REPO) --limit 5; \
		exit 1; \
	fi
	@echo "Downloading $(TAG) from $(REPO)..."
	$(eval TMPDIR := $(shell mktemp -d))
	gh repo clone $(REPO) $(TMPDIR)/repo -- --branch $(TAG) --depth 1
	cd $(TMPDIR)/repo/cmd/maestro-cli && \
		go generate ./... && \
		go build -ldflags "-X github.com/spec-maestro/maestro-cli/internal/version.Version=$(TAG)" -o $(BINARY) .
	@echo "Installing $(BINARY) to $(PREFIX)/bin (requires sudo)..."
	sudo install -m 755 $(TMPDIR)/repo/cmd/maestro-cli/$(BINARY) $(PREFIX)/bin/$(BINARY)
	rm -rf $(TMPDIR)
	@echo "✓ Installed $(TAG):"
	@$(PREFIX)/bin/$(BINARY) --version

clean:
	rm -f $(BINARY)
