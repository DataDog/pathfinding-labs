// Package aws provides AWS credential validation and service-linked role detection utilities
package aws

import (
	"fmt"
	"os/exec"
	"strings"
)

// ServiceLinkedRoleStatus tracks which service-linked roles already exist in an AWS account.
// Roles that already exist should not be created by Terraform to avoid deploy failures.
type ServiceLinkedRoleStatus struct {
	AutoScalingExists bool
	SpotExists        bool
	AppRunnerExists   bool
}

// slrStateAddresses maps each SLR to its canonical Terraform state resource address.
// These are the addresses used when Terraform created the SLR via the prod_environment module.
var slrStateAddresses = map[string]string{
	"autoscaling": "module.prod_environment[0].aws_iam_service_linked_role.autoscaling[0]",
	"spot":        "module.prod_environment[0].aws_iam_service_linked_role.spot[0]",
	"apprunner":   "module.prod_environment[0].aws_iam_service_linked_role.apprunner[0]",
}

// SLRInState returns which service-linked roles are currently in Terraform state
// (i.e. created and managed by Terraform). Uses the provided list of state resource addresses.
func SLRInState(stateResources []string) *ServiceLinkedRoleStatus {
	inState := make(map[string]bool, len(stateResources))
	for _, r := range stateResources {
		inState[r] = true
	}
	return &ServiceLinkedRoleStatus{
		AutoScalingExists: inState[slrStateAddresses["autoscaling"]],
		SpotExists:        inState[slrStateAddresses["spot"]],
		AppRunnerExists:   inState[slrStateAddresses["apprunner"]],
	}
}

// serviceLinkedRoleChecks maps our internal names to the AWS IAM role names
var serviceLinkedRoleChecks = map[string]string{
	"autoscaling": "AWSServiceRoleForAutoScaling",
	"spot":        "AWSServiceRoleForEC2Spot",
	"apprunner":   "AWSServiceRoleForAppRunner",
}

// DetectExistingServiceLinkedRoles checks which service-linked roles already exist
// in the AWS account associated with the given profile
func DetectExistingServiceLinkedRoles(profile string) (*ServiceLinkedRoleStatus, error) {
	if profile == "" {
		return nil, fmt.Errorf("profile name is empty")
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
		}
	}

	return status, nil
}

// roleExists checks if an IAM role exists in the account by calling aws iam get-role
func roleExists(profile, roleName string) (bool, error) {
	cmd := exec.Command("aws", "iam", "get-role",
		"--role-name", roleName,
		"--profile", profile,
		"--output", "text",
		"--query", "Role.RoleName")

	output, err := cmd.Output()
	if err != nil {
		// aws iam get-role returns exit code 254 / NoSuchEntity when the role doesn't exist
		// Any error here means the role doesn't exist or we can't check -- either way, let
		// Terraform attempt to create it
		exitErr, ok := err.(*exec.ExitError)
		if ok && strings.Contains(string(exitErr.Stderr), "NoSuchEntity") {
			return false, nil
		}
		// For other errors (e.g., access denied), assume the role doesn't exist and let
		// Terraform handle it -- worst case it fails with the same permission error
		return false, nil
	}

	return strings.TrimSpace(string(output)) == roleName, nil
}
