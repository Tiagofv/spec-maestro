// Package embedded provides access to the maestro resources that are compiled
// into the binary via go:embed.
//
// Binary size impact (measured 2026-03-17):
//
//	Baseline (no embed):  ~11.4 MB  (11,916,290 bytes)
//	With embed resources: ~11.7 MB  (12,302,930 bytes)
//	Delta:                ~378 KB   (resources on disk: ~660 KB)
//
// The embedded resources include .maestro/ configs (commands, scripts,
// templates, skills, cookbook, reference, constitution) and agent configs
// (.claude/, .opencode/). Total binary remains well under the 50 MB
// threshold.
package embedded

import (
	"embed"
	"fmt"
	"io/fs"
	"path"
	"strings"
)

//go:embed all:resources
var resources embed.FS

const embeddedRoot = "resources"

// knownAgentDirs lists the agent configuration directories that may be
// present in the embedded resources.
var knownAgentDirs = []string{".claude", ".opencode"}

// NewAssetFetcher returns a function that walks a directory inside the
// embedded FS and returns its file contents as a map.
//
// The returned function signature matches agents.AssetFetcher:
//
//	func(dir string) (map[string][]byte, error)
//
// Callers pass logical paths such as ".maestro/commands"; the fetcher
// transparently maps them to the embedded "resources/.maestro/commands"
// subtree.  Map keys use the original caller-relative paths (e.g.
// ".maestro/commands/maestro.init.md").
func NewAssetFetcher() func(dir string) (map[string][]byte, error) {
	return func(dir string) (map[string][]byte, error) {
		embeddedDir := path.Join(embeddedRoot, dir)

		// Verify the directory exists in the embedded FS.
		entry, err := fs.Stat(resources, embeddedDir)
		if err != nil {
			return nil, fmt.Errorf("embedded directory %q not found: %w", dir, err)
		}
		if !entry.IsDir() {
			return nil, fmt.Errorf("embedded path %q is not a directory", dir)
		}

		result := make(map[string][]byte)

		walkErr := fs.WalkDir(resources, embeddedDir, func(filePath string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if d.IsDir() {
				return nil
			}

			content, readErr := resources.ReadFile(filePath)
			if readErr != nil {
				return fmt.Errorf("reading embedded file %s: %w", filePath, readErr)
			}

			// Strip the "resources/<dir>/" prefix so the key is relative to
			// the requested directory (e.g. "maestro.init.md" not
			// ".maestro/commands/maestro.init.md").  This matches the
			// contract expected by agents.WriteAgentDir which joins the
			// key with the target directory.
			rel := strings.TrimPrefix(filePath, embeddedDir+"/")

			result[rel] = content
			return nil
		})
		if walkErr != nil {
			return nil, fmt.Errorf("walking embedded directory %q: %w", dir, walkErr)
		}

		return result, nil
	}
}

// FetchFile reads a single file from the embedded FS.
//
// The path should be the logical path as used by callers (e.g.
// ".maestro/constitution.md"); the function transparently prepends the
// embedded root prefix.
func FetchFile(filePath string) ([]byte, error) {
	embeddedPath := path.Join(embeddedRoot, filePath)

	content, err := resources.ReadFile(embeddedPath)
	if err != nil {
		return nil, fmt.Errorf("reading embedded file %q: %w", filePath, err)
	}

	return content, nil
}

// ListAgentDirs returns the agent configuration directory names (e.g.
// ".claude", ".opencode") that are present in the embedded resources.
func ListAgentDirs() []string {
	var dirs []string
	for _, name := range knownAgentDirs {
		embeddedPath := path.Join(embeddedRoot, name)
		info, err := fs.Stat(resources, embeddedPath)
		if err == nil && info.IsDir() {
			dirs = append(dirs, name)
		}
	}
	return dirs
}
