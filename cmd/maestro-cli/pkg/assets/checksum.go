package assets

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// VerifyChecksum verifies a file's SHA256 hash against an expected value.
func VerifyChecksum(filePath, expectedHash string) error {
	actual, err := FileHash(filePath)
	if err != nil {
		return fmt.Errorf("computing checksum: %w", err)
	}
	if !strings.EqualFold(actual, expectedHash) {
		return fmt.Errorf("checksum mismatch for %s: expected %s, got %s", filePath, expectedHash, actual)
	}
	return nil
}

// ParseChecksumFile parses a checksums.txt file (GitHub release format).
// Format: <hash>  <filename>
func ParseChecksumFile(checksumPath string) (map[string]string, error) {
	f, err := os.Open(checksumPath)
	if err != nil {
		return nil, fmt.Errorf("opening checksum file: %w", err)
	}
	defer f.Close()

	checksums := make(map[string]string)
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.Fields(line)
		if len(parts) < 2 {
			continue
		}
		hash := parts[0]
		name := parts[len(parts)-1]
		// Remove leading ./ or path separators
		name = strings.TrimPrefix(name, "./")
		checksums[name] = hash
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("reading checksum file: %w", err)
	}
	return checksums, nil
}

// VerifyAssetChecksum verifies a downloaded asset against a parsed checksum map.
func VerifyAssetChecksum(filePath, fileName string, checksums map[string]string) error {
	expected, ok := checksums[fileName]
	if !ok {
		// Not in checksums file — skip verification
		return nil
	}
	return VerifyChecksum(filePath, expected)
}
