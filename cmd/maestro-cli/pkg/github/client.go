package github

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

const (
	baseURL    = "https://api.github.com"
	apiVersion = "2022-11-28"
)

// Release represents a GitHub release.
type Release struct {
	TagName     string    `json:"tag_name"`
	PublishedAt time.Time `json:"published_at"`
	Assets      []Asset   `json:"assets"`
	Body        string    `json:"body"`
}

// Asset represents a release asset.
type Asset struct {
	Name        string `json:"name"`
	DownloadURL string `json:"browser_download_url"`
	Size        int64  `json:"size"`
}

// Client is a GitHub API client.
type Client struct {
	httpClient *http.Client
	token      string
	owner      string
	repo       string
}

// NewClient creates a new GitHub client.
func NewClient(owner, repo, token string) *Client {
	return &Client{
		httpClient: &http.Client{Timeout: 30 * time.Second},
		token:      token,
		owner:      owner,
		repo:       repo,
	}
}

// FetchLatestRelease fetches the latest release from GitHub.
func (c *Client) FetchLatestRelease() (*Release, error) {
	url := fmt.Sprintf("%s/repos/%s/%s/releases/latest", baseURL, c.owner, c.repo)
	return c.fetchRelease(url)
}

// FetchReleaseByTag fetches a specific release by tag.
func (c *Client) FetchReleaseByTag(tag string) (*Release, error) {
	url := fmt.Sprintf("%s/repos/%s/%s/releases/tags/%s", baseURL, c.owner, c.repo, tag)
	return c.fetchRelease(url)
}

func (c *Client) fetchRelease(url string) (*Release, error) {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("creating request: %w", err)
	}

	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", apiVersion)
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetching release: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, fmt.Errorf("release not found")
	}
	if resp.StatusCode == http.StatusForbidden {
		remaining := resp.Header.Get("X-RateLimit-Remaining")
		return nil, fmt.Errorf("GitHub API rate limited (remaining: %s). Set GITHUB_TOKEN for higher limits", remaining)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	var release Release
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return nil, fmt.Errorf("decoding response: %w", err)
	}

	return &release, nil
}

// FindAssetForPlatform finds a release asset matching the given platform suffix.
func (r *Release) FindAssetForPlatform(suffix string) (*Asset, error) {
	for _, a := range r.Assets {
		if len(a.Name) >= len(suffix) && a.Name[len(a.Name)-len(suffix):] == suffix {
			return &a, nil
		}
	}
	return nil, fmt.Errorf("no asset found for platform: %s", suffix)
}
