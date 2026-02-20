package agents

import (
	"fmt"
	"os"
	"path/filepath"
)

// AssetFetcher fetches file content for a target directory.
type AssetFetcher func(dir string) (map[string][]byte, error)

// InstallResult describes the outcome of required starter asset installation.
type InstallResult struct {
	Installed []string
	Backups   []string
}

type rollbackState struct {
	originalPath string
	backupPath   string
}

// InstallRequiredAssets installs all required directories as one transaction.
//
// Behavior:
//   - Fetch all required content before writing anything.
//   - Apply one global conflict action across all conflicting dirs.
//   - On any failure, rollback to the pre-install filesystem state for required dirs.
func InstallRequiredAssets(requiredDirs []string, action ConflictAction, fetch AssetFetcher) (*InstallResult, error) {
	if len(requiredDirs) == 0 {
		return &InstallResult{}, nil
	}

	if fetch == nil {
		return nil, fmt.Errorf("fetcher is required")
	}

	staged := make(map[string]map[string][]byte, len(requiredDirs))
	for _, dir := range requiredDirs {
		content, err := fetch(dir)
		if err != nil {
			return nil, fmt.Errorf("fetching required starter assets for %s: %w", dir, err)
		}
		staged[dir] = content
	}

	conflicting := detectConflictingDirs(requiredDirs)
	rollbackBackups, userBackups, err := prepareConflictAction(conflicting, action)
	if err != nil {
		return nil, err
	}

	installed := make([]string, 0, len(requiredDirs))
	for _, dir := range requiredDirs {
		if err := WriteAgentDir(staged[dir], dir); err != nil {
			if rollbackErr := rollbackRequiredInstall(requiredDirs, rollbackBackups); rollbackErr != nil {
				return nil, fmt.Errorf("writing required starter assets: %v (rollback failed: %w)", err, rollbackErr)
			}
			return nil, fmt.Errorf("writing required starter assets for %s: %w", dir, err)
		}
		installed = append(installed, dir)
	}

	if err := finalizeRollbackBackups(rollbackBackups, action); err != nil {
		if rollbackErr := rollbackRequiredInstall(requiredDirs, rollbackBackups); rollbackErr != nil {
			return nil, fmt.Errorf("finalizing required starter assets: %v (rollback failed: %w)", err, rollbackErr)
		}
		return nil, err
	}

	return &InstallResult{
		Installed: installed,
		Backups:   userBackups,
	}, nil
}

func detectConflictingDirs(requiredDirs []string) []string {
	conflicting := make([]string, 0, len(requiredDirs))
	for _, dir := range requiredDirs {
		if info, err := os.Stat(dir); err == nil && info.IsDir() {
			conflicting = append(conflicting, dir)
		}
	}
	return conflicting
}

func prepareConflictAction(conflicting []string, action ConflictAction) ([]rollbackState, []string, error) {
	if len(conflicting) == 0 {
		return nil, nil, nil
	}

	if action == ConflictCancel {
		return nil, nil, fmt.Errorf("required starter asset installation cancelled")
	}

	rollbackBackups := make([]rollbackState, 0, len(conflicting))
	userBackups := []string{}

	for _, dir := range conflicting {
		switch action {
		case ConflictBackup:
			backupPath, err := BackupDir(dir)
			if err != nil {
				if rollbackErr := restoreFromBackups(rollbackBackups); rollbackErr != nil {
					return nil, nil, fmt.Errorf("backing up %s: %v (restore failed: %w)", dir, err, rollbackErr)
				}
				return nil, nil, fmt.Errorf("backing up %s: %w", dir, err)
			}

			rollbackBackups = append(rollbackBackups, rollbackState{originalPath: dir, backupPath: backupPath})
			userBackups = append(userBackups, backupPath)
		case ConflictOverwrite:
			tempBackupPath, err := tempBackupPathFor(dir)
			if err != nil {
				return nil, nil, err
			}
			if err := os.Rename(dir, tempBackupPath); err != nil {
				if rollbackErr := restoreFromBackups(rollbackBackups); rollbackErr != nil {
					return nil, nil, fmt.Errorf("preparing overwrite for %s: %v (restore failed: %w)", dir, err, rollbackErr)
				}
				return nil, nil, fmt.Errorf("preparing overwrite for %s: %w", dir, err)
			}

			rollbackBackups = append(rollbackBackups, rollbackState{originalPath: dir, backupPath: tempBackupPath})
		default:
			return nil, nil, fmt.Errorf("unknown conflict action: %v", action)
		}
	}

	return rollbackBackups, userBackups, nil
}

func tempBackupPathFor(dir string) (string, error) {
	base := filepath.Base(dir)
	parent := filepath.Dir(dir)
	tmpDir, err := os.MkdirTemp(parent, ".maestro-overwrite-backup-")
	if err != nil {
		return "", fmt.Errorf("creating temporary backup for %s: %w", dir, err)
	}
	return filepath.Join(tmpDir, base), nil
}

func finalizeRollbackBackups(backups []rollbackState, action ConflictAction) error {
	if action != ConflictOverwrite {
		return nil
	}

	for _, state := range backups {
		if err := os.RemoveAll(filepath.Dir(state.backupPath)); err != nil {
			return fmt.Errorf("removing temporary backup %s: %w", state.backupPath, err)
		}
	}

	return nil
}

func rollbackRequiredInstall(requiredDirs []string, backups []rollbackState) error {
	for _, dir := range requiredDirs {
		if err := os.RemoveAll(dir); err != nil {
			return fmt.Errorf("removing partial required directory %s: %w", dir, err)
		}
	}

	return restoreFromBackups(backups)
}

func restoreFromBackups(backups []rollbackState) error {
	for _, state := range backups {
		if _, err := os.Stat(state.backupPath); os.IsNotExist(err) {
			continue
		}
		if _, err := os.Stat(state.originalPath); err == nil {
			if err := os.RemoveAll(state.originalPath); err != nil {
				return fmt.Errorf("clearing restore target %s: %w", state.originalPath, err)
			}
		}
		if err := os.Rename(state.backupPath, state.originalPath); err != nil {
			return fmt.Errorf("restoring %s from backup: %w", state.originalPath, err)
		}

		parent := filepath.Dir(state.backupPath)
		if filepath.Base(parent) == "." {
			continue
		}
		_ = os.Remove(parent)
	}

	return nil
}
