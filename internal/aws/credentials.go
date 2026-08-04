// Package aws provides AWS credential validation utilities
package aws

import (
	"fmt"
	"os/exec"
	"strings"
)

// ValidationResult contains the result of credential validation
type ValidationResult struct {
	Profile   string
	AccountID string
	Valid     bool
	Error     error
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

// ValidateProfiles validates AWS profiles strictly one at a time, stopping at the
// first failure. This is intentional: profiles that share the same SSO service will
// all gain valid tokens once the user authenticates the first failing profile, so
// there is no point triggering additional auth flows for the remaining profiles.
// Empty profile strings are skipped — callers use GetUniqueProfiles to deduplicate.
func ValidateProfiles(profiles []string) ([]ValidationResult, error) {
	var results []ValidationResult

	for _, profile := range profiles {
		if profile == "" {
			continue
		}

		result := ValidateProfile(profile)
		results = append(results, result)

		if !result.Valid {
			return results, fmt.Errorf("invalid credentials for profile %q", profile)
		}
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
