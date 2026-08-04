// Package aws provides AWS credential validation and service-linked role detection utilities
package aws

import (
	"bytes"
	"fmt"
	"os/exec"
	"strings"
)

// ServiceLinkedRoleStatus tracks which service-linked roles already exist in an AWS account.
// Roles that already exist should not be created by Terraform to avoid deploy failures.
type ServiceLinkedRoleStatus struct {
	AutoScalingExists       bool
	SpotExists              bool
	AppRunnerExists         bool
	EMRExists               bool
	EMRServerlessExists     bool
	ImageBuilderExists      bool
	BatchExists             bool
}

// slrStateAddresses maps each SLR to its canonical Terraform state resource address.
// These are the addresses used when Terraform created the SLR via the prod_environment module.
var slrStateAddresses = map[string]string{
	"autoscaling":   "module.prod_environment[0].aws_iam_service_linked_role.autoscaling[0]",
	"spot":          "module.prod_environment[0].aws_iam_service_linked_role.spot[0]",
	"apprunner":     "module.prod_environment[0].aws_iam_service_linked_role.apprunner[0]",
	"emr":           "module.prod_environment[0].aws_iam_service_linked_role.emr[0]",
	"emrserverless": "module.prod_environment[0].aws_iam_service_linked_role.emr_serverless[0]",
	"imagebuilder":  "module.prod_environment[0].aws_iam_service_linked_role.imagebuilder[0]",
	"batch":         "module.prod_environment[0].aws_iam_service_linked_role.batch[0]",
}

// SLRInState returns which service-linked roles are currently in Terraform state
// (i.e. created and managed by Terraform). Uses the provided list of state resource addresses.
func SLRInState(stateResources []string) *ServiceLinkedRoleStatus {
	inState := make(map[string]bool, len(stateResources))
	for _, r := range stateResources {
		inState[r] = true
	}
	return &ServiceLinkedRoleStatus{
		AutoScalingExists:   inState[slrStateAddresses["autoscaling"]],
		SpotExists:          inState[slrStateAddresses["spot"]],
		AppRunnerExists:     inState[slrStateAddresses["apprunner"]],
		EMRExists:           inState[slrStateAddresses["emr"]],
		EMRServerlessExists: inState[slrStateAddresses["emrserverless"]],
		ImageBuilderExists:  inState[slrStateAddresses["imagebuilder"]],
		BatchExists:         inState[slrStateAddresses["batch"]],
	}
}

// serviceLinkedRoleChecks maps our internal names to the AWS IAM role names
var serviceLinkedRoleChecks = map[string]string{
	"autoscaling":   "AWSServiceRoleForAutoScaling",
	"spot":          "AWSServiceRoleForEC2Spot",
	"apprunner":     "AWSServiceRoleForAppRunner",
	"emr":           "AWSServiceRoleForEMRCleanup",
	"emrserverless": "AWSServiceRoleForAmazonEMRServerless",
	"imagebuilder":  "AWSServiceRoleForImageBuilder",
	"batch":         "AWSServiceRoleForBatch",
}

// DetectExistingServiceLinkedRoles checks which service-linked roles already exist
// in the AWS account associated with the given profile.
// Profile must be non-empty — the prod environment must be configured before calling this.
//
// Detection shells out to the AWS CLI rather than the Go SDK. This is deliberate and
// mirrors ValidateProfile in credentials.go: the CLI resolves every credential mechanism
// (aws-vault, SSO, credential_process, static keys, env vars) automatically, whereas the
// SDK's shared-config loader does not invoke external helpers like aws-vault. Using the
// SDK here previously caused every GetRole to fail silently for aws-vault/SSO profiles,
// which made all SLRs look absent and led Terraform to try re-creating roles that already
// existed (e.g. the account-wide AWSServiceRoleForBatch).
func DetectExistingServiceLinkedRoles(profile string) (*ServiceLinkedRoleStatus, error) {
	if profile == "" {
		return nil, fmt.Errorf("no AWS profile configured for this environment — run 'plabs init' to set one up")
	}

	status := &ServiceLinkedRoleStatus{}

	for key, roleName := range serviceLinkedRoleChecks {
		exists, err := roleExists(profile, roleName)
		if err != nil {
			return nil, fmt.Errorf("failed to check service-linked role %s: %w", roleName, err)
		}

		switch key {
		case "autoscaling":
			status.AutoScalingExists = exists
		case "spot":
			status.SpotExists = exists
		case "apprunner":
			status.AppRunnerExists = exists
		case "emr":
			status.EMRExists = exists
		case "emrserverless":
			status.EMRServerlessExists = exists
		case "imagebuilder":
			status.ImageBuilderExists = exists
		case "batch":
			status.BatchExists = exists
		}
	}

	return status, nil
}

// roleExists checks whether an IAM role exists by running `aws iam get-role` under the
// given profile. IAM is global, so no region is required.
//
// It returns (false, nil) only for a genuine NoSuchEntity response — the role provably
// does not exist. Any other failure (expired credentials, throttling, access denied) is
// returned as an error so the caller can surface it rather than silently mistaking an
// unreachable API for an absent role, which would let Terraform attempt to create a role
// that may already exist.
func roleExists(profile, roleName string) (bool, error) {
	cmd := exec.Command("aws", "iam", "get-role",
		"--role-name", roleName,
		"--profile", profile,
		"--output", "json")

	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err == nil {
		return true, nil
	}

	// NoSuchEntity is the one case that definitively means "the role is absent".
	if strings.Contains(stderr.String(), "NoSuchEntity") {
		return false, nil
	}

	return false, fmt.Errorf("aws iam get-role failed for %q using profile %q: %s",
		roleName, profile, strings.TrimSpace(stderr.String()))
}
