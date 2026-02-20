package agents

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// WriteAgentDir writes the given file content to the target directory.
// content maps relative paths to file content bytes.
// It creates nested directories as needed and writes files atomically.
// Returns an error if any write operation fails.
func WriteAgentDir(content map[string][]byte, targetDir string) error {
	if len(content) == 0 {
		return fmt.Errorf("no content to write")
	}

	// Validate targetDir to prevent path traversal
	cleanTarget, err := filepath.Abs(targetDir)
	if err != nil {
		return fmt.Errorf("resolving target directory: %w", err)
	}

	// Create the target directory if it doesn't exist
	if err := os.MkdirAll(cleanTarget, 0755); err != nil {
		return fmt.Errorf("creating target directory: %w", err)
	}

	// Write each file
	for relPath, data := range content {
		// Validate and clean the relative path to prevent path traversal attacks
		if strings.Contains(relPath, "..") {
			return fmt.Errorf("invalid path contains '..': %s", relPath)
		}

		// Build full path
		fullPath := filepath.Join(cleanTarget, relPath)

		// Ensure the file path is still under cleanTarget (defense in depth)
		cleanPath, err := filepath.Abs(fullPath)
		if err != nil {
			return fmt.Errorf("resolving path for %s: %w", relPath, err)
		}
		if !strings.HasPrefix(cleanPath, cleanTarget+string(filepath.Separator)) && cleanPath != cleanTarget {
			return fmt.Errorf("path traversal detected: %s", relPath)
		}

		// Check for symlink attacks - ensure parent directories are not symlinks
		if err := ensureNoSymlinks(filepath.Dir(cleanPath), cleanTarget); err != nil {
			return fmt.Errorf("symlink check failed for %s: %w", relPath, err)
		}

		// Create parent directories
		dir := filepath.Dir(fullPath)
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("creating directory for %s: %w", relPath, err)
		}

		// Write file atomically using temp file + rename
		if err := writeFileAtomic(fullPath, data); err != nil {
			return fmt.Errorf("writing %s: %w", relPath, err)
		}
	}

	return nil
}

// BackupDir creates a timestamped backup of the given directory.
// Returns the backup path or an error if the backup fails.
// The backup path follows the format: {dirPath}-backup-{timestamp}
func BackupDir(dirPath string) (string, error) {
	// Check if directory exists
	info, err := os.Stat(dirPath)
	if err != nil {
		return "", fmt.Errorf("checking directory: %w", err)
	}
	if !info.IsDir() {
		return "", fmt.Errorf("path is not a directory: %s", dirPath)
	}

	// Generate backup path using consistent naming pattern
	timestamp := time.Now().Format("20060102-150405")
	backupPath := fmt.Sprintf("%s-backup-%s", dirPath, timestamp)

	// Rename the directory to create the backup
	if err := os.Rename(dirPath, backupPath); err != nil {
		return "", fmt.Errorf("creating backup: %w", err)
	}

	return backupPath, nil
}

// writeFileAtomic writes data to a file atomically by writing to a temp file
// and then renaming it to the target path.
func writeFileAtomic(path string, data []byte) error {
	// Create temp file in the same directory to ensure same filesystem
	dir := filepath.Dir(path)
	tmpFile, err := os.CreateTemp(dir, ".tmp-*")
	if err != nil {
		return fmt.Errorf("creating temp file: %w", err)
	}
	tmpPath := tmpFile.Name()

	// Clean up temp file on error
	defer func() {
		if tmpFile != nil {
			tmpFile.Close()
			os.Remove(tmpPath)
		}
	}()

	// Write data to temp file
	if _, err := tmpFile.Write(data); err != nil {
		return fmt.Errorf("writing to temp file: %w", err)
	}

	// Sync to ensure data is written to disk
	if err := tmpFile.Sync(); err != nil {
		return fmt.Errorf("syncing temp file: %w", err)
	}

	// Close the temp file before rename
	if err := tmpFile.Close(); err != nil {
		return fmt.Errorf("closing temp file: %w", err)
	}

	// Set proper permissions (0644 for regular files)
	if err := os.Chmod(tmpPath, 0644); err != nil {
		return fmt.Errorf("setting file permissions: %w", err)
	}

	// Atomically rename temp file to target path
	if err := os.Rename(tmpPath, path); err != nil {
		return fmt.Errorf("renaming temp file: %w", err)
	}

	// Clear tmpFile to prevent cleanup in defer
	tmpFile = nil
	return nil
}

// ensureNoSymlinks checks that the path and all parent directories up to root
// do not contain symlinks. This prevents symlink attacks during file writes.
func ensureNoSymlinks(path string, root string) error {
	// Normalize paths
	cleanPath, err := filepath.Abs(path)
	if err != nil {
		return fmt.Errorf("resolving path: %w", err)
	}
	cleanRoot, err := filepath.Abs(root)
	if err != nil {
		return fmt.Errorf("resolving root: %w", err)
	}

	// Check each component from root to path
	current := cleanPath
	for {
		// Stop when we reach or go above the root
		if current == cleanRoot {
			break
		}
		if !strings.HasPrefix(current, cleanRoot+string(filepath.Separator)) && current != cleanRoot {
			break
		}

		// Check if current path component is a symlink
		info, err := os.Lstat(current)
		if err != nil {
			if os.IsNotExist(err) {
				// Path doesn't exist yet, move to parent
				parent := filepath.Dir(current)
				if parent == current {
					break // Reached filesystem root
				}
				current = parent
				continue
			}
			return fmt.Errorf("checking path %s: %w", current, err)
		}

		if info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("symlink detected at %s", current)
		}

		// Move to parent directory
		parent := filepath.Dir(current)
		if parent == current {
			break // Reached filesystem root
		}
		current = parent
	}

	return nil
}
