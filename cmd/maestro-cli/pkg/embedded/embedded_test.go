package embedded

import (
	"strings"
	"testing"
)

func TestNewAssetFetcher_MaestroSubdirectories(t *testing.T) {
	fetch := NewAssetFetcher()

	tests := []struct {
		name     string
		dir      string
		wantFile string // a known file that must be present
		minFiles int    // minimum number of files expected
	}{
		{
			name:     "commands",
			dir:      ".maestro/commands",
			wantFile: ".maestro/commands/maestro.init.md",
			minFiles: 1,
		},
		{
			name:     "scripts",
			dir:      ".maestro/scripts",
			wantFile: ".maestro/scripts/init.sh",
			minFiles: 1,
		},
		{
			name:     "templates",
			dir:      ".maestro/templates",
			wantFile: ".maestro/templates/spec-template.md",
			minFiles: 1,
		},
		{
			name:     "skills",
			dir:      ".maestro/skills",
			wantFile: ".maestro/skills/constitution/SKILL.md",
			minFiles: 1,
		},
		{
			name:     "cookbook",
			dir:      ".maestro/cookbook",
			wantFile: ".maestro/cookbook/post-epic-analysis.md",
			minFiles: 1,
		},
		{
			name:     "reference",
			dir:      ".maestro/reference",
			wantFile: ".maestro/reference/conventions.md",
			minFiles: 1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			files, err := fetch(tt.dir)
			if err != nil {
				t.Fatalf("fetch(%q) returned error: %v", tt.dir, err)
			}
			if len(files) < tt.minFiles {
				t.Errorf("fetch(%q) returned %d files, want at least %d", tt.dir, len(files), tt.minFiles)
			}
			if _, ok := files[tt.wantFile]; !ok {
				t.Errorf("fetch(%q) missing expected file %q; got keys: %v", tt.dir, tt.wantFile, mapKeys(files))
			}
		})
	}
}

func TestNewAssetFetcher_AgentDirs(t *testing.T) {
	fetch := NewAssetFetcher()

	tests := []struct {
		name     string
		dir      string
		wantFile string
		minFiles int
	}{
		{
			name:     "claude",
			dir:      ".claude",
			wantFile: ".claude/commands/maestro.init.md",
			minFiles: 1,
		},
		{
			name:     "opencode",
			dir:      ".opencode",
			wantFile: ".opencode/commands/maestro.init.md",
			minFiles: 1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			files, err := fetch(tt.dir)
			if err != nil {
				t.Fatalf("fetch(%q) returned error: %v", tt.dir, err)
			}
			if len(files) < tt.minFiles {
				t.Errorf("fetch(%q) returned %d files, want at least %d", tt.dir, len(files), tt.minFiles)
			}
			if _, ok := files[tt.wantFile]; !ok {
				t.Errorf("fetch(%q) missing expected file %q; got keys: %v", tt.dir, tt.wantFile, mapKeys(files))
			}
		})
	}
}

func TestNewAssetFetcher_NonExistentDir(t *testing.T) {
	fetch := NewAssetFetcher()

	tests := []struct {
		name    string
		dir     string
		wantMsg string // substring expected in the error message
	}{
		{
			name:    "completely bogus path",
			dir:     "does/not/exist",
			wantMsg: "not found",
		},
		{
			name:    "missing maestro subdir",
			dir:     ".maestro/nonexistent",
			wantMsg: "not found",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			files, err := fetch(tt.dir)
			if err == nil {
				t.Fatalf("fetch(%q) expected error, got %d files", tt.dir, len(files))
			}
			if !strings.Contains(err.Error(), tt.wantMsg) {
				t.Errorf("fetch(%q) error = %q, want substring %q", tt.dir, err.Error(), tt.wantMsg)
			}
		})
	}
}

func TestNewAssetFetcher_FileContentsNonEmpty(t *testing.T) {
	fetch := NewAssetFetcher()
	files, err := fetch(".maestro/commands")
	if err != nil {
		t.Fatalf("fetch(.maestro/commands) returned error: %v", err)
	}

	for key, content := range files {
		if len(content) == 0 {
			t.Errorf("file %q has empty content", key)
		}
	}
}

func TestFetchFile(t *testing.T) {
	tests := []struct {
		name        string
		path        string
		wantErr     bool
		wantContain string // substring the content must contain
	}{
		{
			name:        "constitution exists and has content",
			path:        ".maestro/constitution.md",
			wantErr:     false,
			wantContain: "", // just assert non-empty
		},
		{
			name:    "non-existent file",
			path:    ".maestro/does-not-exist.md",
			wantErr: true,
		},
		{
			name:    "non-existent nested path",
			path:    "bogus/path/file.txt",
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			content, err := FetchFile(tt.path)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("FetchFile(%q) expected error, got %d bytes", tt.path, len(content))
				}
				return
			}
			if err != nil {
				t.Fatalf("FetchFile(%q) returned error: %v", tt.path, err)
			}
			if len(content) == 0 {
				t.Errorf("FetchFile(%q) returned empty content", tt.path)
			}
			if tt.wantContain != "" && !strings.Contains(string(content), tt.wantContain) {
				t.Errorf("FetchFile(%q) content does not contain %q", tt.path, tt.wantContain)
			}
		})
	}
}

func TestListAgentDirs(t *testing.T) {
	dirs := ListAgentDirs()

	if len(dirs) == 0 {
		t.Fatal("ListAgentDirs() returned empty slice")
	}

	want := map[string]bool{
		".claude":   false,
		".opencode": false,
	}

	for _, d := range dirs {
		if _, ok := want[d]; ok {
			want[d] = true
		}
	}

	for name, found := range want {
		if !found {
			t.Errorf("ListAgentDirs() missing expected directory %q; got %v", name, dirs)
		}
	}
}

// mapKeys returns the keys of a map for diagnostic output.
func mapKeys(m map[string][]byte) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	return keys
}
