#!/usr/bin/env bash
# Update maestro CLI from source
# Usage: ./scripts/update-maestro.sh
# Requires: sudo for installation to /usr/local/bin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_DIR="$SCRIPT_DIR/../cmd/maestro-cli"

echo "Building maestro CLI..."
cd "$CLI_DIR"
go build -o maestro .

echo "Installing to /usr/local/bin/maestro..."
echo "Enter your password if prompted..."
sudo cp maestro /usr/local/bin/maestro

echo "Verifying installation..."
maestro --version

echo ""
echo "✓ maestro CLI updated successfully!"
echo ""
echo "To update .maestro/ files in your project:"
echo "  cd your-project"
echo "  maestro update"