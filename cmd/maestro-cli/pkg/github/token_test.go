package github

import (
	"errors"
	"os"
	"testing"
)

func TestResolveToken_UsesExplicitToken(t *testing.T) {
	origGHToken := os.Getenv("GH_TOKEN")
	origGitHubToken := os.Getenv("GITHUB_TOKEN")
	defer func() {
		_ = os.Setenv("GH_TOKEN", origGHToken)
		_ = os.Setenv("GITHUB_TOKEN", origGitHubToken)
	}()

	_ = os.Unsetenv("GH_TOKEN")
	_ = os.Unsetenv("GITHUB_TOKEN")

	got := ResolveToken("explicit-token")
	if got != "explicit-token" {
		t.Fatalf("expected explicit-token, got %q", got)
	}
}

func TestResolveToken_UsesEnvironmentToken(t *testing.T) {
	origGHToken := os.Getenv("GH_TOKEN")
	origGitHubToken := os.Getenv("GITHUB_TOKEN")
	defer func() {
		_ = os.Setenv("GH_TOKEN", origGHToken)
		_ = os.Setenv("GITHUB_TOKEN", origGitHubToken)
	}()

	_ = os.Setenv("GITHUB_TOKEN", "env-token")
	_ = os.Unsetenv("GH_TOKEN")

	got := ResolveToken("")
	if got != "env-token" {
		t.Fatalf("expected env-token, got %q", got)
	}
}

func TestResolveToken_UsesGHCLIToken(t *testing.T) {
	origGHToken := os.Getenv("GH_TOKEN")
	origGitHubToken := os.Getenv("GITHUB_TOKEN")
	origCmd := ghTokenCommand
	defer func() {
		ghTokenCommand = origCmd
		_ = os.Setenv("GH_TOKEN", origGHToken)
		_ = os.Setenv("GITHUB_TOKEN", origGitHubToken)
	}()

	_ = os.Unsetenv("GH_TOKEN")
	_ = os.Unsetenv("GITHUB_TOKEN")
	ghTokenCommand = func() ([]byte, error) {
		return []byte("gh-token\n"), nil
	}

	got := ResolveToken("")
	if got != "gh-token" {
		t.Fatalf("expected gh-token, got %q", got)
	}
}

func TestResolveToken_ReturnsEmptyWithoutAnySource(t *testing.T) {
	origGHToken := os.Getenv("GH_TOKEN")
	origGitHubToken := os.Getenv("GITHUB_TOKEN")
	origCmd := ghTokenCommand
	defer func() {
		ghTokenCommand = origCmd
		_ = os.Setenv("GH_TOKEN", origGHToken)
		_ = os.Setenv("GITHUB_TOKEN", origGitHubToken)
	}()

	_ = os.Unsetenv("GH_TOKEN")
	_ = os.Unsetenv("GITHUB_TOKEN")
	ghTokenCommand = func() ([]byte, error) {
		return nil, errors.New("gh not installed")
	}

	got := ResolveToken("")
	if got != "" {
		t.Fatalf("expected empty token, got %q", got)
	}
}
