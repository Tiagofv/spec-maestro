package assets

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

// DownloadAsset downloads a file from a URL to a local path, showing progress.
func DownloadAsset(url, destPath string) error {
	resp, err := http.Get(url)
	if err != nil {
		return fmt.Errorf("downloading asset: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status downloading asset: %d", resp.StatusCode)
	}

	if err := os.MkdirAll(filepath.Dir(destPath), 0755); err != nil {
		return fmt.Errorf("creating destination directory: %w", err)
	}

	out, err := os.Create(destPath)
	if err != nil {
		return fmt.Errorf("creating destination file: %w", err)
	}
	defer out.Close()

	total := resp.ContentLength
	var downloaded int64

	buf := make([]byte, 32*1024)
	for {
		n, err := resp.Body.Read(buf)
		if n > 0 {
			if _, werr := out.Write(buf[:n]); werr != nil {
				return fmt.Errorf("writing to file: %w", werr)
			}
			downloaded += int64(n)
			if total > 0 {
				pct := float64(downloaded) / float64(total) * 100
				fmt.Fprintf(os.Stderr, "\rDownloading... %.0f%%", pct)
			}
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("reading response: %w", err)
		}
	}
	if total > 0 {
		fmt.Fprintf(os.Stderr, "\rDownloading... 100%%\n")
	}

	return nil
}

// ExtractAsset extracts a downloaded asset (tar.gz or zip) to destDir.
func ExtractAsset(srcPath, destDir string) error {
	if err := os.MkdirAll(destDir, 0755); err != nil {
		return fmt.Errorf("creating destination directory: %w", err)
	}

	switch {
	case strings.HasSuffix(srcPath, ".tar.gz") || strings.HasSuffix(srcPath, ".tgz"):
		return extractTarGz(srcPath, destDir)
	case strings.HasSuffix(srcPath, ".zip"):
		return extractZip(srcPath, destDir)
	default:
		return fmt.Errorf("unsupported archive format: %s", srcPath)
	}
}

func extractTarGz(srcPath, destDir string) error {
	f, err := os.Open(srcPath)
	if err != nil {
		return err
	}
	defer f.Close()

	gz, err := gzip.NewReader(f)
	if err != nil {
		return err
	}
	defer gz.Close()

	tr := tar.NewReader(gz)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}

		target := filepath.Join(destDir, filepath.Clean(hdr.Name))
		if !strings.HasPrefix(target, filepath.Clean(destDir)+string(os.PathSeparator)) {
			return fmt.Errorf("invalid path in archive: %s", hdr.Name)
		}

		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0755); err != nil {
				return err
			}
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
				return err
			}
			out, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, os.FileMode(hdr.Mode))
			if err != nil {
				return err
			}
			if _, err := io.Copy(out, tr); err != nil {
				out.Close()
				return err
			}
			out.Close()
		}
	}
	return nil
}

// CleanupTemp removes a temporary file, ignoring errors.
func CleanupTemp(path string) {
	os.Remove(path)
}

// DownloadAndExtract downloads an asset and extracts it to destDir.
// The temp download file is cleaned up after extraction.
func DownloadAndExtract(url, destDir string) error {
	// Create temp file for download
	tmpFile, err := os.CreateTemp("", "maestro-asset-*")
	if err != nil {
		return fmt.Errorf("creating temp file: %w", err)
	}
	tmpPath := tmpFile.Name()
	tmpFile.Close()

	// Determine extension from URL and rename temp file accordingly
	ext := ".tar.gz"
	if strings.HasSuffix(url, ".zip") {
		ext = ".zip"
	}
	newPath := tmpPath + ext
	if err := os.Rename(tmpPath, newPath); err != nil {
		CleanupTemp(tmpPath)
		return fmt.Errorf("renaming temp file: %w", err)
	}
	tmpPath = newPath
	defer CleanupTemp(tmpPath)

	if err := DownloadAsset(url, tmpPath); err != nil {
		return err
	}

	return ExtractAsset(tmpPath, destDir)
}

func extractZip(srcPath, destDir string) error {
	r, err := zip.OpenReader(srcPath)
	if err != nil {
		return err
	}
	defer r.Close()

	for _, f := range r.File {
		target := filepath.Join(destDir, filepath.Clean(f.Name))
		if !strings.HasPrefix(target, filepath.Clean(destDir)+string(os.PathSeparator)) {
			return fmt.Errorf("invalid path in archive: %s", f.Name)
		}

		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(target, 0755); err != nil {
				return err
			}
			continue
		}

		if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
			return err
		}

		out, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, f.Mode())
		if err != nil {
			return err
		}
		rc, err := f.Open()
		if err != nil {
			out.Close()
			return err
		}
		_, err = io.Copy(out, rc)
		rc.Close()
		out.Close()
		if err != nil {
			return err
		}
	}
	return nil
}
