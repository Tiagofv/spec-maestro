package assets

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

// CacheManager manages locally cached assets.
type CacheManager struct {
	dir string
}

// NewCacheManager creates a CacheManager using ~/.cache/maestro.
func NewCacheManager() (*CacheManager, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("getting home directory: %w", err)
	}
	dir := filepath.Join(home, ".cache", "maestro")
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("creating cache directory: %w", err)
	}
	return &CacheManager{dir: dir}, nil
}

// CachePath returns the local path for a given URL's cached file.
func (c *CacheManager) CachePath(url string) string {
	h := sha256.Sum256([]byte(url))
	key := hex.EncodeToString(h[:])[:16]
	// Preserve extension
	ext := ""
	for _, candidate := range []string{".tar.gz", ".tgz", ".zip"} {
		if len(url) >= len(candidate) && url[len(url)-len(candidate):] == candidate {
			ext = candidate
			break
		}
	}
	return filepath.Join(c.dir, key+ext)
}

// IsCached returns true if the asset is in cache and not expired.
func (c *CacheManager) IsCached(url string, maxAge time.Duration) bool {
	path := c.CachePath(url)
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	if maxAge > 0 && time.Since(info.ModTime()) > maxAge {
		return false
	}
	return true
}

// Get returns the cached file path, downloading if necessary.
func (c *CacheManager) Get(url string, maxAge time.Duration) (string, error) {
	if c.IsCached(url, maxAge) {
		return c.CachePath(url), nil
	}
	path := c.CachePath(url)
	if err := DownloadAsset(url, path); err != nil {
		return "", fmt.Errorf("caching asset: %w", err)
	}
	return path, nil
}

// Invalidate removes a specific cached asset.
func (c *CacheManager) Invalidate(url string) error {
	path := c.CachePath(url)
	err := os.Remove(path)
	if os.IsNotExist(err) {
		return nil
	}
	return err
}

// Clear removes all cached assets.
func (c *CacheManager) Clear() error {
	entries, err := os.ReadDir(c.dir)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		os.Remove(filepath.Join(c.dir, entry.Name()))
	}
	return nil
}

// FileHash returns the SHA256 hash of a file.
func FileHash(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
