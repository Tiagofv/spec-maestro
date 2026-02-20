package github

import (
	"encoding/base64"
	"fmt"
	"strings"
)

// TreeResponse represents a GitHub git tree response.
type TreeResponse struct {
	SHA       string      `json:"sha"`
	URL       string      `json:"url"`
	Tree      []TreeEntry `json:"tree"`
	Truncated bool        `json:"truncated"`
}

// TreeEntry represents a single entry in a git tree.
type TreeEntry struct {
	Path string `json:"path"`
	Mode string `json:"mode"`
	Type string `json:"type"` // "blob" or "tree"
	SHA  string `json:"sha"`
	Size int    `json:"size"`
	URL  string `json:"url"`
}

// RefResponse represents a GitHub git ref response.
type RefResponse struct {
	Ref    string `json:"ref"`
	NodeID string `json:"node_id"`
	URL    string `json:"url"`
	Object struct {
		Type string `json:"type"`
		SHA  string `json:"sha"`
		URL  string `json:"url"`
	} `json:"object"`
}

// CommitResponse represents a GitHub git commit response.
type CommitResponse struct {
	SHA     string `json:"sha"`
	NodeID  string `json:"node_id"`
	URL     string `json:"url"`
	Message string `json:"message"`
	Tree    struct {
		SHA string `json:"sha"`
		URL string `json:"url"`
	} `json:"tree"`
}

// BlobResponse represents a GitHub git blob response.
type BlobResponse struct {
	SHA      string `json:"sha"`
	NodeID   string `json:"node_id"`
	Size     int    `json:"size"`
	URL      string `json:"url"`
	Content  string `json:"content"`
	Encoding string `json:"encoding"`
}

// FetchRef fetches a git reference and returns the tree SHA.
func (c *Client) FetchRef(ref string) (treeSHA string, err error) {
	// Get the ref (e.g., "main" -> full commit SHA)
	url := fmt.Sprintf("%s/repos/%s/%s/git/ref/heads/%s", baseURL, c.owner, c.repo, ref)
	var refResp RefResponse
	if err := c.doGet(url, &refResp); err != nil {
		return "", fmt.Errorf("fetching ref: %w", err)
	}

	commitSHA := refResp.Object.SHA

	// Get the commit to extract the tree SHA
	url = fmt.Sprintf("%s/repos/%s/%s/git/commits/%s", baseURL, c.owner, c.repo, commitSHA)
	var commitResp CommitResponse
	if err := c.doGet(url, &commitResp); err != nil {
		return "", fmt.Errorf("fetching commit: %w", err)
	}

	return commitResp.Tree.SHA, nil
}

// FetchTree fetches a git tree with all entries recursively.
func (c *Client) FetchTree(treeSHA string) (*TreeResponse, error) {
	url := fmt.Sprintf("%s/repos/%s/%s/git/trees/%s?recursive=1", baseURL, c.owner, c.repo, treeSHA)
	var treeResp TreeResponse
	if err := c.doGet(url, &treeResp); err != nil {
		return nil, fmt.Errorf("fetching tree: %w", err)
	}

	if treeResp.Truncated {
		return nil, fmt.Errorf("tree response truncated: repository too large. Set GITHUB_TOKEN environment variable for authenticated requests with higher limits, or file an issue at https://github.com/anomalyco/agent-maestro")
	}

	return &treeResp, nil
}

// DownloadBlob downloads a git blob and decodes its content.
func (c *Client) DownloadBlob(sha string) ([]byte, error) {
	url := fmt.Sprintf("%s/repos/%s/%s/git/blobs/%s", baseURL, c.owner, c.repo, sha)
	var blobResp BlobResponse
	if err := c.doGet(url, &blobResp); err != nil {
		return nil, fmt.Errorf("downloading blob: %w", err)
	}

	if blobResp.Encoding != "base64" {
		return nil, fmt.Errorf("unexpected blob encoding: %s (expected base64)", blobResp.Encoding)
	}

	// Decode base64 content
	decoded, err := base64.StdEncoding.DecodeString(blobResp.Content)
	if err != nil {
		return nil, fmt.Errorf("decoding blob content: %w", err)
	}

	return decoded, nil
}

// FetchAgentDir fetches all files from a specific directory in the repository.
// Returns a map of relative path (within dirName) to file content.
func (c *Client) FetchAgentDir(dirName string, ref string) (map[string][]byte, error) {
	// Get the tree SHA for the ref
	treeSHA, err := c.FetchRef(ref)
	if err != nil {
		return nil, fmt.Errorf("fetching agent dir: %w", err)
	}

	// Fetch the full tree
	tree, err := c.FetchTree(treeSHA)
	if err != nil {
		return nil, fmt.Errorf("fetching agent dir: %w", err)
	}

	// Normalize dirName to ensure it has a trailing slash
	prefix := dirName
	if !strings.HasSuffix(prefix, "/") {
		prefix += "/"
	}

	// Filter entries that start with the directory prefix and are blobs
	files := make(map[string][]byte)
	for _, entry := range tree.Tree {
		if entry.Type == "blob" && strings.HasPrefix(entry.Path, prefix) {
			// Download the blob
			content, err := c.DownloadBlob(entry.SHA)
			if err != nil {
				return nil, fmt.Errorf("fetching agent dir: downloading %s: %w", entry.Path, err)
			}

			// Store with relative path (remove prefix)
			relativePath := strings.TrimPrefix(entry.Path, prefix)
			files[relativePath] = content
		}
	}

	if len(files) == 0 {
		return nil, fmt.Errorf("fetching agent dir: no files found in directory %s", dirName)
	}

	return files, nil
}
