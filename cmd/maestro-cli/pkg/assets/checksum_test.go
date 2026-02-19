package assets

import (
	"os"
	"path/filepath"
	"testing"
)

func TestVerifyChecksum(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "test.txt")
	os.WriteFile(path, []byte("hello world"), 0644)

	// SHA256 of "hello world"
	expected := "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"

	// Verify with correct hash
	if err := VerifyChecksum(path, expected); err != nil {
		t.Errorf("VerifyChecksum() with correct hash: %v", err)
	}

	// Verify with wrong hash
	if err := VerifyChecksum(path, "deadbeef"); err == nil {
		t.Error("VerifyChecksum() should fail with wrong hash")
	}
}

func TestParseChecksumFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "checksums.txt")
	content := "abc123  maestro_Darwin_arm64.tar.gz\ndef456  maestro_Linux_amd64.tar.gz\n"
	os.WriteFile(path, []byte(content), 0644)

	checksums, err := ParseChecksumFile(path)
	if err != nil {
		t.Fatalf("ParseChecksumFile() error: %v", err)
	}

	if checksums["maestro_Darwin_arm64.tar.gz"] != "abc123" {
		t.Errorf("Expected abc123, got %q", checksums["maestro_Darwin_arm64.tar.gz"])
	}
	if checksums["maestro_Linux_amd64.tar.gz"] != "def456" {
		t.Errorf("Expected def456, got %q", checksums["maestro_Linux_amd64.tar.gz"])
	}
}
