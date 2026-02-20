package agents

import "testing"

func TestRequiredStarterAssetDirs(t *testing.T) {
	dirs := RequiredStarterAssetDirs()
	if len(dirs) != 3 {
		t.Fatalf("expected 3 required starter dirs, got %d", len(dirs))
	}

	expected := map[string]bool{
		".maestro/scripts":   true,
		".maestro/skills":    true,
		".maestro/templates": true,
	}

	for _, dir := range dirs {
		if !expected[dir] {
			t.Fatalf("unexpected required dir: %s", dir)
		}
	}
}
