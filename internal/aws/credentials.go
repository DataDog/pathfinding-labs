// Package aws provides AWS credential validation utilities
package aws

import (
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// ValidationResult contains the result of credential validation
type ValidationResult struct {
	Profile   string
	AccountID string
	Valid     bool
	Error     error
}

// ValidateProfile checks if the given AWS profile has valid credentials
// by running aws sts get-caller-identity
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
		result.Error = fmt.Errorf("AWS SSO session may have expired for profile '%s'. Run: aws sso login --profile %s", profile, profile)
		return result
	}

	accountID := strings.TrimSpace(string(output))
	if accountID == "" {
		result.Error = fmt.Errorf("could not retrieve account ID for profile '%s'", profile)
		return result
	}

	result.AccountID = accountID
	result.Valid = true
	return result
}

// ValidateProfiles validates multiple AWS profiles and returns results for each
// It validates profiles one at a time with a small delay to allow SSO browser auth to complete
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

// ValidatePrimaryProfile validates a single profile and returns a user-friendly error
// This is useful for triggering SSO auth before running terraform commands
func ValidatePrimaryProfile(profile string) error {
	if profile == "" {
		return fmt.Errorf("no AWS profile configured")
	}

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
