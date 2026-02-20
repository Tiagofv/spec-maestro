package agents

import (
	"os"
	"path/filepath"
)

// KnownAgentDirs returns the complete list of agent config directories
// that maestro can manage. This is the single source of truth.
func KnownAgentDirs() []string {
	return []string{".opencode", ".claude"}
}

// DetectInstalled returns the subset of KnownAgentDirs that exist
// as directories under projectRoot.
func DetectInstalled(projectRoot string) []string {
	var installed []string
	for _, dir := range KnownAgentDirs() {
		path := filepath.Join(projectRoot, dir)
		if info, err := os.Stat(path); err == nil && info.IsDir() {
			installed = append(installed, dir)
		}
	}
	return installed
}
