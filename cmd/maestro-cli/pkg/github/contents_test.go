package github

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestFetchRef(t *testing.T) {
	refResp := RefResponse{
		Ref: "refs/heads/main",
		Object: struct {
			Type string `json:"type"`
			SHA  string `json:"sha"`
			URL  string `json:"url"`
		}{
			Type: "commit",
			SHA:  "commit-sha-123",
			URL:  "https://api.github.com/repos/owner/repo/git/commits/commit-sha-123",
		},
	}

	commitResp := CommitResponse{
		SHA:     "commit-sha-123",
		Message: "Test commit",
		Tree: struct {
			SHA string `json:"sha"`
			URL string `json:"url"`
		}{
			SHA: "tree-sha-456",
			URL: "https://api.github.com/repos/owner/repo/git/trees/tree-sha-456",
		},
	}

	callCount := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		w.Header().Set("Content-Type", "application/json")

		if callCount == 1 {
			// First call: ref lookup
			if r.URL.Path != "/repos/owner/repo/git/ref/heads/main" {
				t.Errorf("unexpected path for ref: %s", r.URL.Path)
			}
			json.NewEncoder(w).Encode(refResp)
		} else if callCount == 2 {
			// Second call: commit lookup
			if r.URL.Path != "/repos/owner/repo/git/commits/commit-sha-123" {
				t.Errorf("unexpected path for commit: %s", r.URL.Path)
			}
			json.NewEncoder(w).Encode(commitResp)
		}
	}))
	defer server.Close()

	client := NewClient("owner", "repo", "")
	client.httpClient = server.Client()
	client.baseURL = server.URL

	treeSHA, err := client.FetchRef("main")
	if err != nil {
		t.Fatalf("FetchRef failed: %v", err)
	}

	if treeSHA != "tree-sha-456" {
		t.Errorf("expected tree SHA 'tree-sha-456', got '%s'", treeSHA)
	}

	if callCount != 2 {
		t.Errorf("expected 2 API calls, got %d", callCount)
	}
}

func TestFetchTree(t *testing.T) {
	treeResp := TreeResponse{
		SHA:       "tree-sha-456",
		URL:       "https://api.github.com/repos/owner/repo/git/trees/tree-sha-456",
		Truncated: false,
		Tree: []TreeEntry{
			{
				Path: ".claude/config.json",
				Mode: "100644",
				Type: "blob",
				SHA:  "blob-sha-1",
				Size: 100,
				URL:  "https://api.github.com/repos/owner/repo/git/blobs/blob-sha-1",
			},
			{
				Path: ".claude/skills",
				Mode: "040000",
				Type: "tree",
				SHA:  "tree-sha-2",
				Size: 0,
				URL:  "https://api.github.com/repos/owner/repo/git/trees/tree-sha-2",
			},
		},
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(treeResp)
	}))
	defer server.Close()

	client := NewClient("owner", "repo", "")
	client.httpClient = server.Client()
	client.baseURL = server.URL

	tree, err := client.FetchTree("tree-sha-456")
	if err != nil {
		t.Fatalf("FetchTree failed: %v", err)
	}

	if len(tree.Tree) != 2 {
		t.Errorf("expected 2 tree entries, got %d", len(tree.Tree))
	}

	if tree.Truncated {
		t.Error("expected truncated to be false")
	}
}

func TestFetchTree_Truncated(t *testing.T) {
	treeResp := TreeResponse{
		SHA:       "tree-sha-456",
		URL:       "https://api.github.com/repos/owner/repo/git/trees/tree-sha-456",
		Truncated: true,
		Tree:      []TreeEntry{},
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(treeResp)
	}))
	defer server.Close()

	client := NewClient("owner", "repo", "")
	client.httpClient = server.Client()
	client.baseURL = server.URL

	_, err := client.FetchTree("tree-sha-456")
	if err == nil {
		t.Fatal("expected truncation error, got nil")
	}

	expectedMsg := "tree response truncated"
	if !strings.Contains(err.Error(), expectedMsg) {
		t.Errorf("expected error containing '%s', got: %v", expectedMsg, err)
	}
}

func TestDownloadBlob(t *testing.T) {
	blobResp := BlobResponse{
		SHA:      "blob-sha-1",
		Size:     13,
		URL:      "https://api.github.com/repos/owner/repo/git/blobs/blob-sha-1",
		Content:  "SGVsbG8sIFdvcmxkIQ==", // "Hello, World!" in base64
		Encoding: "base64",
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(blobResp)
	}))
	defer server.Close()

	client := NewClient("owner", "repo", "")
	client.httpClient = server.Client()
	client.baseURL = server.URL

	content, err := client.DownloadBlob("blob-sha-1")
	if err != nil {
		t.Fatalf("DownloadBlob failed: %v", err)
	}

	expected := "Hello, World!"
	if string(content) != expected {
		t.Errorf("expected content '%s', got '%s'", expected, string(content))
	}
}

func TestTreeEntry_Structure(t *testing.T) {
	// Test that TreeEntry marshals/unmarshals correctly
	entry := TreeEntry{
		Path: ".claude/config.json",
		Mode: "100644",
		Type: "blob",
		SHA:  "abc123",
		Size: 42,
		URL:  "https://example.com",
	}

	data, err := json.Marshal(entry)
	if err != nil {
		t.Fatalf("failed to marshal: %v", err)
	}

	var decoded TreeEntry
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("failed to unmarshal: %v", err)
	}

	if decoded.Path != entry.Path || decoded.Type != entry.Type {
		t.Errorf("roundtrip failed: got %+v, want %+v", decoded, entry)
	}
}

func TestTreeResponse_Structure(t *testing.T) {
	// Test that TreeResponse marshals/unmarshals correctly
	resp := TreeResponse{
		SHA:       "tree123",
		URL:       "https://example.com",
		Truncated: false,
		Tree: []TreeEntry{
			{Path: "file1.txt", Type: "blob", SHA: "sha1"},
			{Path: "dir", Type: "tree", SHA: "sha2"},
		},
	}

	data, err := json.Marshal(resp)
	if err != nil {
		t.Fatalf("failed to marshal: %v", err)
	}

	var decoded TreeResponse
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("failed to unmarshal: %v", err)
	}

	if len(decoded.Tree) != 2 || decoded.Truncated != false {
		t.Errorf("roundtrip failed: got %+v, want %+v", decoded, resp)
	}
}
