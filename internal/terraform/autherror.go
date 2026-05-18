package terraform

import (
	"fmt"
	"regexp"
	"strings"
)

var (
	// providerAliasPattern matches the provider alias in terraform error context lines like:
	//   with provider["registry.terraform.io/hashicorp/aws"].attacker,
	providerAliasPattern = regexp.MustCompile(`provider\["registry\.terraform\.io/hashicorp/aws"\]\.(\w+)`)

	// authErrorPhrases are substrings terraform prints when AWS credentials are invalid/expired.
	authErrorPhrases = []string{
		"No valid credential sources found",
		"SSO session has expired or is invalid",
		"failed to refresh cached credentials",
		"ExpiredTokenException",
		"InvalidClientTokenId",
		"AuthFailure",
	}
)

// AuthError represents a credential failure for a specific AWS provider alias.
type AuthError struct {
	// ProviderAlias is the terraform provider alias (e.g. "prod", "attacker").
	// Empty when the error couldn't be tied to a specific provider.
	ProviderAlias string
}

// ParseAuthErrors scans terraform output for credential/SSO errors and returns
// one AuthError per distinct provider alias that failed. Order matches first
// occurrence in the output.
func ParseAuthErrors(output string) []AuthError {
	lines := strings.Split(output, "\n")
	var errors []AuthError
	seen := map[string]bool{}

	for i, line := range lines {
		if !isAuthErrorLine(line) {
			continue
		}

		// Search the surrounding ±5 lines for a provider alias.
		alias := ""
		start := i - 5
		if start < 0 {
			start = 0
		}
		end := i + 5
		if end >= len(lines) {
			end = len(lines) - 1
		}
		for j := start; j <= end; j++ {
			if m := providerAliasPattern.FindStringSubmatch(lines[j]); len(m) == 2 {
				alias = m[1]
				break
			}
		}

		key := alias // deduplicate by alias (empty string de-dupes all alias-less errors)
		if !seen[key] {
			seen[key] = true
			errors = append(errors, AuthError{ProviderAlias: alias})
		}
	}

	return errors
}

func isAuthErrorLine(line string) bool {
	for _, phrase := range authErrorPhrases {
		if strings.Contains(line, phrase) {
			return true
		}
	}
	return false
}

// FormatAuthErrorMessage formats detected auth errors into a human-readable
// message. profileForAlias maps a provider alias to the configured AWS profile
// name; it may return "" if a profile isn't configured for that alias.
func FormatAuthErrorMessage(errors []AuthError, profileForAlias func(alias string) string) string {
	if len(errors) == 0 {
		return ""
	}

	var sb strings.Builder
	sb.WriteString("Authentication failed. Re-authenticate and retry:\n\n")

	shown := map[string]bool{}
	for _, e := range errors {
		profile := profileForAlias(e.ProviderAlias)
		if profile == "" {
			profile = e.ProviderAlias // fall back to alias if profile unknown
		}
		if profile == "" {
			continue
		}
		if shown[profile] {
			continue
		}
		shown[profile] = true
		sb.WriteString(fmt.Sprintf("  aws sso login --profile %s\n", profile))
	}

	return strings.TrimRight(sb.String(), "\n")
}
