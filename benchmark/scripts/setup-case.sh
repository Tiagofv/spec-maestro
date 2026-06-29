#!/usr/bin/env bash
# setup-case.sh — scaffold an isolated sandbox project for a maestro benchmark case.
#
# Usage:
#   benchmark/scripts/setup-case.sh <case-id> [target-dir]
#
#   <case-id>     01 | 02 | 03 | 04 | 05  (leading zero optional)
#   [target-dir]  where to create the sandbox (default: $TMPDIR/maestro-bench-<id>-<n>)
#
# What it does:
#   - creates a throwaway git repo
#   - installs maestro into it (the `maestro` binary if on PATH, else copies
#     .maestro/ + .claude/ from this repo)
#   - writes a case-tailored, generic .maestro/config.yaml (bd prefix `bench-`, never altpay-)
#   - seeds the case's starting files (greenfield stub or brownfield seed code)
#   - prints the exact command sequence to run in Claude Code
#
# The sandbox is self-contained and disposable. Never commit it back into this repo.
set -euo pipefail

# ---- resolve paths -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

die() { echo "error: $*" >&2; exit 1; }

# ---- args --------------------------------------------------------------------
[ $# -ge 1 ] || die "usage: setup-case.sh <case-id 01..05> [target-dir]"
RAW_ID="$1"
CASE_ID="$(printf '%02d' "$((10#${RAW_ID}))" 2>/dev/null)" || die "bad case id: $RAW_ID"

case "$CASE_ID" in
  01) SLUG="cli-task-tracker-go";       STACK="go" ;;
  02) SLUG="url-shortener-node";        STACK="node" ;;
  03) SLUG="static-site-generator-py";  STACK="python" ;;
  04) SLUG="notes-api-pagination-node"; STACK="node" ;;
  05) SLUG="rate-limiter-go";           STACK="go" ;;
  *)  die "unknown case id '$CASE_ID' (expected 01..05)" ;;
esac

TARGET="${2:-${TMPDIR:-/tmp}/maestro-bench-${CASE_ID}-$$}"
[ -e "$TARGET" ] && die "target already exists: $TARGET (pick another path)"

echo ">> Case $CASE_ID — $SLUG (stack: $STACK)"
echo ">> Sandbox: $TARGET"
mkdir -p "$TARGET"
cd "$TARGET"
git init -q
git config user.email "bench@example.com"
git config user.name "maestro-bench"

# ---- install maestro ---------------------------------------------------------
if command -v maestro >/dev/null 2>&1; then
  echo ">> Installing maestro via CLI (maestro init --with-claude)"
  maestro init --with-claude >/dev/null 2>&1 || maestro init >/dev/null 2>&1 || true
fi
if [ ! -d "$TARGET/.maestro" ]; then
  echo ">> Copying .maestro/ and .claude/ from $REPO_ROOT"
  [ -d "$REPO_ROOT/.maestro" ] || die "no maestro binary on PATH and no .maestro in repo root"
  cp -R "$REPO_ROOT/.maestro" "$TARGET/.maestro"
  [ -d "$REPO_ROOT/.claude" ] && cp -R "$REPO_ROOT/.claude" "$TARGET/.claude"
fi

# Always overlay the repo's CANONICAL maestro assets on top of whatever `maestro init`
# installed. The binary installs from EMBEDDED resources, which lag local edits — without
# this overlay the benchmark would silently test stale commands/scripts, not your changes.
echo ">> Overlaying canonical .maestro assets from $REPO_ROOT (so local edits are what's tested)"
for d in commands skills templates scripts cookbook reference; do
  if [ -d "$REPO_ROOT/.maestro/$d" ]; then
    rm -rf "$TARGET/.maestro/$d"; cp -R "$REPO_ROOT/.maestro/$d" "$TARGET/.maestro/$d"
  fi
done
[ -d "$REPO_ROOT/.claude/commands" ] && { rm -rf "$TARGET/.claude/commands"; cp -R "$REPO_ROOT/.claude/commands" "$TARGET/.claude/commands"; }
# start clean
rm -rf "$TARGET/.maestro/specs" "$TARGET/.maestro/state"
mkdir -p "$TARGET/.maestro/specs" "$TARGET/.maestro/state"

# ---- generic, AltPay-free config.yaml ---------------------------------------
mkdir -p "$TARGET/.maestro"
cat > "$TARGET/.maestro/config.yaml" <<YAML
# Maestro config — benchmark sandbox (generic; contains no proprietary code)
project:
  name: "bench-${SLUG}"
  description: "Maestro benchmark case ${CASE_ID}"
  base_branch: main

agent_routing:
  backend: general
  frontend: general
  test: general
  fix: general
  refactor: general
  review: general
  pm-validation: general

compile_gate:
  go: "go build ./... && go vet ./... && go test ./..."
  node: "pnpm run build && pnpm run test:run"
  python: "python -m py_compile \$(git ls-files '*.py') && ruff check ."
  stack: ${STACK}

size_mapping:
  XS: 120
  S: 360
  M: 720
  L: 1200

review_sizing:
  XS: 120
  S: 120
  M: 360
  L: 360

# Generic bd prefix for the benchmark — deliberately NOT a company prefix.
bd_stable_prefix: bench-
bd_label_template: "feature:{feature_num}"
YAML

# ---- per-case seed files -----------------------------------------------------
seed_go_module() { # $1 = module, $2 = root file, $3 = root file contents
  cat > go.mod <<EOF
module $1

go 1.21
EOF
  printf '%s\n' "$3" > "$2"
}

case "$CASE_ID" in
  01)
    seed_go_module "example.com/tasktracker" "main.go" \
'package main

func main() {}'
    ;;

  02)
    cat > package.json <<'EOF'
{
  "name": "bench-url-shortener",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "test:run": "node --test"
  },
  "dependencies": { "express": "^4.19.2" },
  "devDependencies": { "typescript": "^5.4.0", "@types/express": "^4.17.21", "@types/node": "^20.0.0" }
}
EOF
    cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022", "module": "NodeNext", "moduleResolution": "NodeNext",
    "strict": true, "outDir": "dist", "rootDir": "src", "esModuleInterop": true
  },
  "include": ["src"]
}
EOF
    mkdir -p src
    cat > src/index.ts <<'EOF'
import express from "express";

const app = express();
app.use(express.json());

// Routes added by the benchmarked feature.

const port = Number(process.env.PORT ?? 3000);
app.listen(port, () => console.log(`listening on ${port}`));

export { app };
EOF
    ;;

  03)
    cat > pyproject.toml <<'EOF'
[project]
name = "bench-ssg"
version = "0.0.0"

[tool.ruff]
line-length = 100
EOF
    mkdir -p ssg content templates
    : > ssg/__init__.py
    printf '# Hello\n\nWorld.\n' > content/hello.md
    printf '<html><body>{{content}}</body></html>\n' > templates/base.html
    ;;

  04)
    cat > package.json <<'EOF'
{
  "name": "bench-notes-api",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "test:run": "node --test"
  },
  "dependencies": { "express": "^4.19.2" },
  "devDependencies": { "typescript": "^5.4.0", "@types/express": "^4.17.21", "@types/node": "^20.0.0" }
}
EOF
    cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022", "module": "NodeNext", "moduleResolution": "NodeNext",
    "strict": true, "outDir": "dist", "rootDir": "src", "esModuleInterop": true
  },
  "include": ["src"]
}
EOF
    mkdir -p src
    cat > src/notes.ts <<'EOF'
export interface Note {
  id: number;
  text: string;
}

const notes: Note[] = [];
let nextId = 1;

export function add(text: string): Note {
  const note: Note = { id: nextId++, text };
  notes.push(note);
  return note;
}

export function all(): Note[] {
  return notes.slice();
}
EOF
    cat > src/index.ts <<'EOF'
import express from "express";
import { add, all } from "./notes.js";

const app = express();
app.use(express.json());

app.get("/notes", (_req, res) => {
  res.json(all());
});

app.post("/notes", (req, res) => {
  const text = String(req.body?.text ?? "");
  if (!text) return res.status(400).json({ error: "text required" });
  res.status(201).json(add(text));
});

const port = Number(process.env.PORT ?? 3000);
if (process.env.NODE_ENV !== "test") {
  app.listen(port, () => console.log(`listening on ${port}`));
}

export { app };
EOF
    cat > src/notes.test.ts <<'EOF'
import { test } from "node:test";
import assert from "node:assert/strict";
import { add, all } from "./notes.js";

test("add returns a note with an id", () => {
  const n = add("first");
  assert.equal(n.text, "first");
  assert.ok(n.id >= 1);
});

test("all returns previously added notes", () => {
  const before = all().length;
  add("second");
  assert.equal(all().length, before + 1);
});
EOF
    ;;

  05)
    seed_go_module "example.com/ratelimit" "ratelimit.go" \
'package ratelimit'
    ;;
esac

# ---- initial commit so the pipeline has a clean base -------------------------
git add -A
git commit -q -m "chore: benchmark sandbox for case ${CASE_ID} (${SLUG})"

# ---- instructions ------------------------------------------------------------
cat <<EOF

================================================================================
Sandbox ready: $TARGET   (stack: $STACK, branch: $(git branch --show-current))
Case definition: benchmark/cases/${CASE_ID}-${SLUG}.md  (in the spec-maestro repo)
================================================================================

Next:
  1. cd "$TARGET"
  2. Open Claude Code here.
  3. Follow the "Run protocol" in the case file, one command at a time.
  4. Score each command into a copy of benchmark/RESULTS-TEMPLATE.md
     -> results/$(date +%Y%m%d)-case${CASE_ID}.md

Tip: set compile_gate.stack is already '${STACK}'. Verify the toolchain is installed:
  go:     go version
  node:   node --version && pnpm --version   (run 'pnpm install' before /maestro.implement)
  python: python --version && ruff --version

When done, just delete the sandbox: rm -rf "$TARGET"
================================================================================
EOF
