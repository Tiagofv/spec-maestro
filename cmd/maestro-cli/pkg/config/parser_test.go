package config

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestLoadNonExistent(t *testing.T) {
	cfg, err := Load("/nonexistent/path/config.yaml")
	if err != nil {
		t.Fatalf("Load() should return empty config for nonexistent file, got error: %v", err)
	}
	if cfg == nil {
		t.Fatal("Load() returned nil for nonexistent file")
	}
}

func TestSaveAndLoad(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")

	cfg := &ProjectConfig{
		CLIVersion:    "v1.0.0",
		InitializedAt: time.Now().UTC().Truncate(time.Second),
	}

	if err := Save(cfg, path); err != nil {
		t.Fatalf("Save() error: %v", err)
	}

	loaded, err := Load(path)
	if err != nil {
		t.Fatalf("Load() error: %v", err)
	}

	if loaded.CLIVersion != cfg.CLIVersion {
		t.Errorf("CLIVersion: got %q, want %q", loaded.CLIVersion, cfg.CLIVersion)
	}
}

func TestUpdateCLIVersion(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")

	// Write initial config
	os.WriteFile(path, []byte("cli_version: v0.1.0\n"), 0644)

	if err := UpdateCLIVersion(path, "v0.2.0"); err != nil {
		t.Fatalf("UpdateCLIVersion() error: %v", err)
	}

	cfg, _ := Load(path)
	if cfg.CLIVersion != "v0.2.0" {
		t.Errorf("CLIVersion after update: got %q, want %q", cfg.CLIVersion, "v0.2.0")
	}
}
