package github

import (
	"testing"
)

func TestFindAssetForPlatform(t *testing.T) {
	release := &Release{
		TagName: "v1.0.0",
		Assets: []Asset{
			{Name: "maestro_Darwin_arm64.tar.gz", DownloadURL: "https://example.com/arm64"},
			{Name: "maestro_Linux_amd64.tar.gz", DownloadURL: "https://example.com/amd64"},
		},
	}

	// Find darwin/arm64
	asset, err := release.FindAssetForPlatform("Darwin_arm64.tar.gz")
	if err != nil {
		t.Fatalf("FindAssetForPlatform() error: %v", err)
	}
	if asset.DownloadURL != "https://example.com/arm64" {
		t.Errorf("Wrong asset: %v", asset)
	}

	// Platform not found
	_, err = release.FindAssetForPlatform("windows_amd64.zip")
	if err == nil {
		t.Error("Expected error for missing platform")
	}
}
