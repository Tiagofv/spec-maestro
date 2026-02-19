#!/usr/bin/env bash
# Instructions for setting up the Homebrew tap repository.
# Run these commands in a separate repository: homebrew-maestro

echo "To set up the Homebrew tap:"
echo "1. Create a new GitHub repo: spec-maestro/homebrew-maestro"
echo "2. Copy Formula/maestro.rb to that repo"
echo "3. Update SHA256 checksums after each release"
echo "4. GoReleaser handles this automatically via .goreleaser.yml brews section"
