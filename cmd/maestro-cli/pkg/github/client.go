package github

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

const (
	defaultBaseURL     = "https://api.github.com"
	defaultCodeloadURL = "https://codeload.github.com"
	apiVersion         = "2022-11-28"
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
	httpClient  *http.Client
	baseURL     string
	codeloadURL string
	token       string
	owner       string
	repo        string
}

// NewClient creates a new GitHub client.
func NewClient(owner, repo, token string) *Client {
	return &Client{
		httpClient:  &http.Client{Timeout: 30 * time.Second},
		baseURL:     defaultBaseURL,
		codeloadURL: defaultCodeloadURL,
		token:       token,
		owner:       owner,
		repo:        repo,
	}
}

// ResolveToken resolves a GitHub token from explicit input, environment,
// or the local gh CLI auth session.
func ResolveToken(explicit string) string {
	if token := strings.TrimSpace(explicit); token != "" {
		return token
	}

	for _, envKey := range []string{"GITHUB_TOKEN", "GH_TOKEN"} {
		if token := strings.TrimSpace(os.Getenv(envKey)); token != "" {
			return token
		}
	}

	if token, err := lookupTokenWithGHCLI(); err == nil {
		return token
	}

	return ""
}

var ghTokenCommand = func() ([]byte, error) {
	return exec.Command("gh", "auth", "token").Output()
}

func lookupTokenWithGHCLI() (string, error) {
	output, err := ghTokenCommand()
	if err != nil {
		return "", err
	}
	token := strings.TrimSpace(string(output))
	if token == "" {
		return "", fmt.Errorf("empty token from gh auth token")
	}
	return token, nil
}

// FetchLatestRelease fetches the latest release from GitHub.
func (c *Client) FetchLatestRelease() (*Release, error) {
	url := fmt.Sprintf("%s/repos/%s/%s/releases/latest", c.baseURL, c.owner, c.repo)
	return c.fetchRelease(url)
}

// FetchReleaseByTag fetches a specific release by tag.
func (c *Client) FetchReleaseByTag(tag string) (*Release, error) {
	url := fmt.Sprintf("%s/repos/%s/%s/releases/tags/%s", c.baseURL, c.owner, c.repo, tag)
	return c.fetchRelease(url)
}

// doGet performs a GET request and decodes the JSON response.
func (c *Client) doGet(url string, target interface{}) error {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return fmt.Errorf("creating request: %w", err)
	}

	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", apiVersion)
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("executing request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return fmt.Errorf("resource not found")
	}
	if resp.StatusCode == http.StatusForbidden {
		remaining := resp.Header.Get("X-RateLimit-Remaining")
		return fmt.Errorf("GitHub API rate limited (remaining: %s). Authenticate with `gh auth login` or set GITHUB_TOKEN/GH_TOKEN for higher limits", remaining)
	}
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	if err := json.NewDecoder(resp.Body).Decode(target); err != nil {
		return fmt.Errorf("decoding response: %w", err)
	}

	return nil
}

func (c *Client) fetchRelease(url string) (*Release, error) {
	var release Release
	if err := c.doGet(url, &release); err != nil {
		return nil, fmt.Errorf("fetching release: %w", err)
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
