package fs

import (
	"testing"
)

func TestDetectPlatform(t *testing.T) {
	p, err := DetectPlatform()
	if err != nil {
		t.Fatalf("DetectPlatform() error = %v", err)
	}
	if p.OS == "" {
		t.Error("OS is empty")
	}
	if p.Arch == "" {
		t.Error("Arch is empty")
	}
	t.Logf("Detected platform: %s", p.String())
}
