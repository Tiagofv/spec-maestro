package config

import (
	"fmt"
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

const defaultConfigPath = ".maestro/config.yaml"

// ProjectConfig represents the .maestro/config.yaml structure.
type ProjectConfig struct {
	CLIVersion    string                 `yaml:"cli_version,omitempty"`
	InitializedAt time.Time              `yaml:"initialized_at,omitempty"`
	Project       ProjectSection         `yaml:"project,omitempty"`
	Custom        map[string]interface{} `yaml:"custom,omitempty"`
}

// ProjectSection holds project metadata.
type ProjectSection struct {
	Name        string `yaml:"name,omitempty"`
	Description string `yaml:"description,omitempty"`
	BaseBranch  string `yaml:"base_branch,omitempty"`
}

// Load reads and parses the config file at the given path.
func Load(path string) (*ProjectConfig, error) {
	if path == "" {
		path = defaultConfigPath
	}
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return &ProjectConfig{}, nil
		}
		return nil, fmt.Errorf("reading config: %w", err)
	}
	var cfg ProjectConfig
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parsing config: %w", err)
	}
	return &cfg, nil
}

// Save writes the config to disk, preserving existing content.
func Save(cfg *ProjectConfig, path string) error {
	if path == "" {
		path = defaultConfigPath
	}
	data, err := yaml.Marshal(cfg)
	if err != nil {
		return fmt.Errorf("marshaling config: %w", err)
	}
	return os.WriteFile(path, data, 0644)
}

// UpdateCLIVersion updates only the cli_version field in the config.
func UpdateCLIVersion(path, version string) error {
	cfg, err := Load(path)
	if err != nil {
		return err
	}
	cfg.CLIVersion = version
	return Save(cfg, path)
}
