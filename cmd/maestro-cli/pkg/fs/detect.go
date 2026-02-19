package fs

import (
	"fmt"
	"runtime"
)

// Platform represents the current operating system and architecture.
type Platform struct {
	OS   string // darwin, linux, windows
	Arch string // amd64, arm64
}

// DetectPlatform returns the current platform.
func DetectPlatform() (*Platform, error) {
	goos := runtime.GOOS
	goarch := runtime.GOARCH

	// Normalize OS
	switch goos {
	case "darwin", "linux", "windows":
		// supported
	default:
		return nil, fmt.Errorf("unsupported OS: %s", goos)
	}

	// Normalize Arch
	switch goarch {
	case "amd64", "arm64", "386":
		// supported
	default:
		return nil, fmt.Errorf("unsupported architecture: %s", goarch)
	}

	return &Platform{OS: goos, Arch: goarch}, nil
}

// String returns a human-readable platform string, e.g. "darwin_arm64".
func (p *Platform) String() string {
	return p.OS + "_" + p.Arch
}

// AssetSuffix returns the expected asset suffix for this platform.
// Used when looking up GitHub release assets.
func (p *Platform) AssetSuffix() string {
	ext := ".tar.gz"
	if p.OS == "windows" {
		ext = ".zip"
	}
	return fmt.Sprintf("%s_%s%s", p.OS, p.Arch, ext)
}
