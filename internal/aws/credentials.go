// Package aws provides AWS credential validation utilities
package aws

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"

	awssdk "github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
)

// ValidationResult contains the result of credential validation
type ValidationResult struct {
	Profile   string
	AccountID string
	Valid     bool
	Error     error
}

// LoadAWSConfig returns an AWS SDK config for the given profile.
// Profile must be non-empty; call sites are responsible for checking whether an
// environment is configured before calling this. This function never falls back to
// the SDK default credential chain — if the profile is wrong, it fails loudly.
func LoadAWSConfig(ctx context.Context, profile string) (awssdk.Config, error) {
	if profile == "" {
		return awssdk.Config{}, fmt.Errorf("no AWS profile configured for this environment — run 'plabs init' to set one up")
	}
	return config.LoadDefaultConfig(ctx, config.WithSharedConfigProfile(profile))
}

// ValidateProfile checks if the given AWS profile has valid credentials
// by running `aws sts get-caller-identity`. Delegating to the AWS CLI means
// every credential mechanism works automatically — SSO (browser auth),
// credential_process (aws-vault, etc.), static keys, env vars — without
// plabs needing to know anything about how the profile is configured.
func ValidateProfile(profile string) ValidationResult {
	result := ValidationResult{
		Profile: profile,
	}

	if profile == "" {
		result.Error = fmt.Errorf("profile name is empty")
		return result
	}

	cmd := exec.Command("aws", "sts", "get-caller-identity",
		"--profile", profile,
		"--query", "Account",
		"--output", "text")

	output, err := cmd.Output()
	if err != nil {
		result.Error = fmt.Errorf("AWS credentials invalid or expired for profile %q — re-authenticate and try again", profile)
		return result
	}

	accountID := strings.TrimSpace(string(output))
	if accountID == "" {
		result.Error = fmt.Errorf("could not retrieve account ID for profile %q", profile)
		return result
	}

	result.AccountID = accountID
	result.Valid = true
	return result
}

// ValidateProfiles validates multiple AWS profiles and returns results for each.
// It validates profiles one at a time with a small delay to allow SSO browser auth to complete.
// Empty profile strings are skipped — callers use GetUniqueProfiles to deduplicate before calling.
func ValidateProfiles(profiles []string) ([]ValidationResult, error) {
	var results []ValidationResult
	var invalidProfiles []string

	for i, profile := range profiles {
		if profile == "" {
			continue
		}

		result := ValidateProfile(profile)
		results = append(results, result)

		if !result.Valid {
			invalidProfiles = append(invalidProfiles, profile)
		}

		// Small delay between profile checks to allow SSO auth to settle
		if i < len(profiles)-1 && result.Valid {
			time.Sleep(500 * time.Millisecond)
		}
	}

	if len(invalidProfiles) > 0 {
		return results, fmt.Errorf("invalid credentials for profiles: %s", strings.Join(invalidProfiles, ", "))
	}

	return results, nil
}

// ValidatePrimaryProfile validates a single profile and returns a user-friendly error.
func ValidatePrimaryProfile(profile string) error {
	result := ValidateProfile(profile)
	if !result.Valid {
		return result.Error
	}
	return nil
}

// GetUniqueProfiles returns a deduplicated list of non-empty profiles
func GetUniqueProfiles(profiles ...string) []string {
	seen := make(map[string]bool)
	var unique []string

	for _, p := range profiles {
		if p != "" && !seen[p] {
			seen[p] = true
			unique = append(unique, p)
		}
	}

	return unique
}
