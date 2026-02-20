package agents

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWriteAgentDir(t *testing.T) {
	// Create a temporary directory for testing
	tmpDir := t.TempDir()
	targetDir := filepath.Join(tmpDir, "test-agent")

	// Test data with nested files
	content := map[string][]byte{
		"README.md":              []byte("# Test Agent"),
		"skills/test.md":         []byte("Test skill"),
		"commands/nested/cmd.md": []byte("Test command"),
	}

	// Write the files
	err := WriteAgentDir(content, targetDir)
	if err != nil {
		t.Fatalf("WriteAgentDir failed: %v", err)
	}

	// Verify all files were created
	for relPath, expectedContent := range content {
		fullPath := filepath.Join(targetDir, relPath)
		actualContent, err := os.ReadFile(fullPath)
		if err != nil {
			t.Errorf("Failed to read %s: %v", relPath, err)
			continue
		}
		if string(actualContent) != string(expectedContent) {
			t.Errorf("Content mismatch for %s: got %q, want %q", relPath, actualContent, expectedContent)
		}
	}

	// Verify file permissions
	for relPath := range content {
		fullPath := filepath.Join(targetDir, relPath)
		info, err := os.Stat(fullPath)
		if err != nil {
			t.Errorf("Failed to stat %s: %v", relPath, err)
			continue
		}
		mode := info.Mode()
		if mode.Perm() != 0644 {
			t.Errorf("Wrong permissions for %s: got %o, want 0644", relPath, mode.Perm())
		}
	}
}

func TestWriteAgentDirEmpty(t *testing.T) {
	tmpDir := t.TempDir()
	targetDir := filepath.Join(tmpDir, "empty")

	err := WriteAgentDir(map[string][]byte{}, targetDir)
	if err == nil {
		t.Fatal("Expected error for empty content, got nil")
	}
}

func TestWriteAgentDirPathTraversal(t *testing.T) {
	tmpDir := t.TempDir()
	targetDir := filepath.Join(tmpDir, "test")

	// Test path traversal attack
	content := map[string][]byte{
		"../evil.txt": []byte("evil content"),
	}

	err := WriteAgentDir(content, targetDir)
	if err == nil {
		t.Fatal("Expected error for path traversal, got nil")
	}

	// Verify the file was NOT created outside targetDir
	evilPath := filepath.Join(tmpDir, "evil.txt")
	if _, err := os.Stat(evilPath); !os.IsNotExist(err) {
		t.Error("Path traversal attack succeeded - evil file was created")
	}
}

func TestBackupDir(t *testing.T) {
	tmpDir := t.TempDir()
	dirPath := filepath.Join(tmpDir, "test-dir")

	// Create a directory with some files
	if err := os.MkdirAll(dirPath, 0755); err != nil {
		t.Fatalf("Failed to create test dir: %v", err)
	}
	testFile := filepath.Join(dirPath, "test.txt")
	if err := os.WriteFile(testFile, []byte("test content"), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	// Backup the directory
	backupPath, err := BackupDir(dirPath)
	if err != nil {
		t.Fatalf("BackupDir failed: %v", err)
	}

	// Verify backup path format
	if backupPath == "" {
		t.Fatal("BackupDir returned empty path")
	}

	// Verify original directory no longer exists
	if _, err := os.Stat(dirPath); !os.IsNotExist(err) {
		t.Error("Original directory still exists after backup")
	}

	// Verify backup directory exists with content
	if _, err := os.Stat(backupPath); err != nil {
		t.Errorf("Backup directory doesn't exist: %v", err)
	}

	// Verify backup contains the original file
	backupFile := filepath.Join(backupPath, "test.txt")
	content, err := os.ReadFile(backupFile)
	if err != nil {
		t.Errorf("Failed to read backup file: %v", err)
	}
	if string(content) != "test content" {
		t.Errorf("Backup file content mismatch: got %q, want %q", content, "test content")
	}
}

func TestBackupDirNonExistent(t *testing.T) {
	tmpDir := t.TempDir()
	dirPath := filepath.Join(tmpDir, "nonexistent")

	_, err := BackupDir(dirPath)
	if err == nil {
		t.Fatal("Expected error for non-existent directory, got nil")
	}
}

func TestBackupDirNotDirectory(t *testing.T) {
	tmpDir := t.TempDir()
	filePath := filepath.Join(tmpDir, "file.txt")

	// Create a file, not a directory
	if err := os.WriteFile(filePath, []byte("test"), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	_, err := BackupDir(filePath)
	if err == nil {
		t.Fatal("Expected error for file path, got nil")
	}
}
