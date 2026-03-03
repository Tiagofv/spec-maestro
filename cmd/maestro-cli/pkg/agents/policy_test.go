package agents

import "testing"

func TestRequiredStarterAssetDirs(t *testing.T) {
	dirs := RequiredStarterAssetDirs()
	if len(dirs) != 6 {
		t.Fatalf("expected 6 required starter dirs, got %d", len(dirs))
	}

	expected := map[string]bool{
		".maestro/commands":  true,
		".maestro/cookbook":  true,
		".maestro/reference": true,
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
