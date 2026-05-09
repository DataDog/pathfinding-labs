package updater

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const (
	githubRepo  = "DataDog/pathfinding-labs"
	cacheTTL    = 24 * time.Hour
	httpTimeout = 3 * time.Second
)

// InstallMethod is set via ldflags at build time: "source", "release", or "unknown".
// Brew installs are detected at runtime via the executable path.
var InstallMethod = "unknown"

// UpdateCache stores the result of the last GitHub release check.
type UpdateCache struct {
	CheckedAt     time.Time `json:"checked_at"`
	LatestVersion string    `json:"latest_version"`
}

// ShouldCheck returns true when the version looks like a tagged release build.
// Skips dev builds, dirty builds (contain "-"), and the default placeholder.
func ShouldCheck(version string) bool {
	if version == "" || version == "dev" || version == "unknown" || version == "0.0.1" {
		return false
	}
	// Versions like "v1.2.3-5-gabcdef" or "v1.2.3-dirty" are untagged/dirty builds.
	v := strings.TrimPrefix(version, "v")
	return !strings.Contains(v, "-")
}

// GetInstallMethod returns the effective install method. Brew installs are identified
// by the executable path containing "/Cellar/plabs/", which covers all Homebrew
// prefixes (/usr/local, /opt/homebrew, /home/linuxbrew/.linuxbrew).
func GetInstallMethod() string {
	exe, err := os.Executable()
	if err == nil && strings.Contains(exe, "/Cellar/plabs/") {
		return "brew"
	}
	return InstallMethod
}

// cacheFilePath returns the path to the on-disk update cache.
func cacheFilePath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".plabs", "update_check.json"), nil
}

// LoadCache reads the update cache from disk.
func LoadCache() (UpdateCache, error) {
	path, err := cacheFilePath()
	if err != nil {
		return UpdateCache{}, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return UpdateCache{}, err
	}
	var cache UpdateCache
	if err := json.Unmarshal(data, &cache); err != nil {
		return UpdateCache{}, err
	}
	return cache, nil
}

// SaveCache writes the update cache to disk.
func SaveCache(cache UpdateCache) error {
	path, err := cacheFilePath()
	if err != nil {
		return err
	}
	data, err := json.Marshal(cache)
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}

// CheckLatest fetches the latest release tag from GitHub. Uses ctx for timeout control.
func CheckLatest(ctx context.Context, currentVersion string) (string, error) {
	url := fmt.Sprintf("https://api.github.com/repos/%s/releases/latest", githubRepo)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Accept", "application/vnd.github.v3+json")
	req.Header.Set("User-Agent", fmt.Sprintf("plabs/%s update-check", currentVersion))

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("GitHub API returned %d", resp.StatusCode)
	}

	var result struct {
		TagName string `json:"tag_name"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", err
	}
	if result.TagName == "" {
		return "", fmt.Errorf("no tag_name in GitHub response")
	}
	return result.TagName, nil
}

// isNewer returns true if latest is strictly newer than current (semver comparison).
func isNewer(current, latest string) bool {
	c := strings.Split(strings.TrimPrefix(current, "v"), ".")
	l := strings.Split(strings.TrimPrefix(latest, "v"), ".")

	for len(c) < 3 {
		c = append(c, "0")
	}
	for len(l) < 3 {
		l = append(l, "0")
	}

	for i := 0; i < 3; i++ {
		cv, _ := strconv.Atoi(c[i])
		lv, _ := strconv.Atoi(l[i])
		if lv > cv {
			return true
		}
		if lv < cv {
			return false
		}
	}
	return false
}

// FormatNotice returns the update notice string for the given install method.
func FormatNotice(currentVersion, latestVersion, method string) string {
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("A new version of plabs is available: %s (you have %s)\n", latestVersion, currentVersion))
	switch method {
	case "brew":
		sb.WriteString("  Upgrade:  brew upgrade plabs\n")
	case "source":
		sb.WriteString("  Run:      git pull && make build\n")
	default:
		sb.WriteString(fmt.Sprintf("  Download: https://github.com/%s/releases/latest\n", githubRepo))
	}
	sb.WriteString("  Then run: plabs update  (to pull the latest scenarios)")
	return sb.String()
}

// Check performs the update check and returns a formatted notice string, or "" if
// no update is needed or the check should be skipped. Never returns an error —
// network failures are silently suppressed so callers are never blocked.
func Check(currentVersion string) string {
	if !ShouldCheck(currentVersion) {
		return ""
	}

	// Use cached result if fresh.
	cache, err := LoadCache()
	if err == nil && time.Since(cache.CheckedAt) < cacheTTL {
		if cache.LatestVersion != "" && isNewer(currentVersion, cache.LatestVersion) {
			return FormatNotice(currentVersion, cache.LatestVersion, GetInstallMethod())
		}
		return ""
	}

	// Cache is expired or missing — fetch from GitHub with a short timeout.
	ctx, cancel := context.WithTimeout(context.Background(), httpTimeout)
	defer cancel()

	latestVersion, err := CheckLatest(ctx, currentVersion)
	if err != nil {
		// Network failure, rate limit, etc. — silently skip.
		return ""
	}

	_ = SaveCache(UpdateCache{
		CheckedAt:     time.Now(),
		LatestVersion: latestVersion,
	})

	if isNewer(currentVersion, latestVersion) {
		return FormatNotice(currentVersion, latestVersion, GetInstallMethod())
	}
	return ""
}
