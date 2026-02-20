package github

import (
	"archive/tar"
	"compress/gzip"
	"encoding/base64"
	"fmt"
	"io"
	"net/http"
	"path"
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
	url := fmt.Sprintf("%s/repos/%s/%s/git/ref/heads/%s", c.baseURL, c.owner, c.repo, ref)
	var refResp RefResponse
	if err := c.doGet(url, &refResp); err != nil {
		return "", fmt.Errorf("fetching ref: %w", err)
	}

	commitSHA := refResp.Object.SHA

	// Get the commit to extract the tree SHA
	url = fmt.Sprintf("%s/repos/%s/%s/git/commits/%s", c.baseURL, c.owner, c.repo, commitSHA)
	var commitResp CommitResponse
	if err := c.doGet(url, &commitResp); err != nil {
		return "", fmt.Errorf("fetching commit: %w", err)
	}

	return commitResp.Tree.SHA, nil
}

// FetchTree fetches a git tree with all entries recursively.
func (c *Client) FetchTree(treeSHA string) (*TreeResponse, error) {
	url := fmt.Sprintf("%s/repos/%s/%s/git/trees/%s?recursive=1", c.baseURL, c.owner, c.repo, treeSHA)
	var treeResp TreeResponse
	if err := c.doGet(url, &treeResp); err != nil {
		return nil, fmt.Errorf("fetching tree: %w", err)
	}

	if treeResp.Truncated {
		return nil, fmt.Errorf("tree response truncated: repository too large. Authenticate with `gh auth login` or set GITHUB_TOKEN/GH_TOKEN for higher limits, or file an issue at https://github.com/anomalyco/agent-maestro")
	}

	return &treeResp, nil
}

// DownloadBlob downloads a git blob and decodes its content.
func (c *Client) DownloadBlob(sha string) ([]byte, error) {
	url := fmt.Sprintf("%s/repos/%s/%s/git/blobs/%s", c.baseURL, c.owner, c.repo, sha)
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
		if isRateLimitedError(err) {
			return c.fetchAgentDirFromArchive(dirName, ref)
		}
		return nil, fmt.Errorf("fetching agent dir: %w", err)
	}

	// Fetch the full tree
	tree, err := c.FetchTree(treeSHA)
	if err != nil {
		if isRateLimitedError(err) {
			return c.fetchAgentDirFromArchive(dirName, ref)
		}
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

func isRateLimitedError(err error) bool {
	if err == nil {
		return false
	}
	return strings.Contains(strings.ToLower(err.Error()), "rate limited")
}

func (c *Client) fetchAgentDirFromArchive(dirName string, ref string) (map[string][]byte, error) {
	archiveURL := fmt.Sprintf("%s/%s/%s/tar.gz/refs/heads/%s", c.codeloadURL, c.owner, c.repo, ref)
	req, err := http.NewRequest("GET", archiveURL, nil)
	if err != nil {
		return nil, fmt.Errorf("fetching agent dir: creating archive request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetching agent dir: downloading archive: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		archiveURL = fmt.Sprintf("%s/%s/%s/tar.gz/%s", c.codeloadURL, c.owner, c.repo, ref)
		req, err = http.NewRequest("GET", archiveURL, nil)
		if err != nil {
			return nil, fmt.Errorf("fetching agent dir: creating archive request: %w", err)
		}
		resp, err = c.httpClient.Do(req)
		if err != nil {
			return nil, fmt.Errorf("fetching agent dir: downloading archive: %w", err)
		}
		defer resp.Body.Close()
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("fetching agent dir: archive download failed: unexpected status: %d", resp.StatusCode)
	}

	gzReader, err := gzip.NewReader(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("fetching agent dir: reading archive: %w", err)
	}
	defer gzReader.Close()

	tarReader := tar.NewReader(gzReader)
	prefix := strings.TrimSuffix(dirName, "/") + "/"
	files := make(map[string][]byte)

	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("fetching agent dir: reading archive entry: %w", err)
		}

		if header.Typeflag != tar.TypeReg {
			continue
		}

		entryPath := header.Name
		slash := strings.Index(entryPath, "/")
		if slash == -1 || slash+1 >= len(entryPath) {
			continue
		}

		repoRelative := entryPath[slash+1:]
		if !strings.HasPrefix(repoRelative, prefix) {
			continue
		}

		rel := strings.TrimPrefix(repoRelative, prefix)
		if rel == "" || strings.Contains(rel, "..") {
			continue
		}
		rel = path.Clean(rel)

		content, err := io.ReadAll(tarReader)
		if err != nil {
			return nil, fmt.Errorf("fetching agent dir: reading file %s: %w", rel, err)
		}
		files[rel] = content
	}

	if len(files) == 0 {
		return nil, fmt.Errorf("fetching agent dir: no files found in directory %s", dirName)
	}

	return files, nil
}
