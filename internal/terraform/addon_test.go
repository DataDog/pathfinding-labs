package terraform

import (
	"testing"
)

func TestAddonOutputValues(t *testing.T) {
	// Build a minimal terraform output JSON the way OutputJSON would return it.
	outputJSON := `{
		"audit_user_access_key_id": {
			"sensitive": true,
			"type": "string",
			"value": "AKIAIOSFODNN7EXAMPLE"
		},
		"audit_user_secret_access_key": {
			"sensitive": true,
			"type": "string",
			"value": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
		},
		"audit_user_name": {
			"sensitive": false,
			"type": "string",
			"value": "pl-addon-audit-user"
		}
	}`

	outputs, err := ParseOutputs(outputJSON)
	if err != nil {
		t.Fatalf("ParseOutputs: %v", err)
	}

	// Simulate what OutputValues does internally
	result := make(map[string]any, len(outputs))
	for k, v := range outputs {
		result[k] = v.Value
	}

	if len(result) != 3 {
		t.Fatalf("expected 3 values, got %d", len(result))
	}
	if result["audit_user_access_key_id"] != "AKIAIOSFODNN7EXAMPLE" {
		t.Errorf("unexpected access key: %v", result["audit_user_access_key_id"])
	}
	if result["audit_user_name"] != "pl-addon-audit-user" {
		t.Errorf("unexpected name: %v", result["audit_user_name"])
	}
}

func TestWithEnv(t *testing.T) {
	r := NewRunner("/tmp/bin", "/tmp/work",
		WithEnv([]string{"TF_VAR_foo=bar"}),
		WithEnv([]string{"TF_VAR_baz=qux"}),
	)

	env := r.commandEnv()

	// commandEnv builds from cleanEnv() + extraEnv, so just verify our vars are there
	hasBar := false
	hasQux := false
	for _, e := range env {
		if e == "TF_VAR_foo=bar" {
			hasBar = true
		}
		if e == "TF_VAR_baz=qux" {
			hasQux = true
		}
	}
	if !hasBar {
		t.Error("TF_VAR_foo=bar not found in commandEnv()")
	}
	if !hasQux {
		t.Error("TF_VAR_baz=qux not found in commandEnv()")
	}
}

func TestWithEnvOtelStripped(t *testing.T) {
	// Verify that OTEL variables in the parent env are stripped by cleanEnv
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")

	r := NewRunner("/tmp/bin", "/tmp/work")
	env := r.commandEnv()

	for _, e := range env {
		if len(e) >= 5 && e[:5] == "OTEL_" {
			t.Errorf("OTEL variable leaked into commandEnv(): %s", e)
		}
	}
}

func TestNewAddon(t *testing.T) {
	extra := []string{"TF_VAR_prod_account_aws_profile=myprofile", "TF_VAR_aws_region=us-east-1"}
	addon := NewAddon("/tmp/bin", "/tmp/addon", extra)
	if addon == nil {
		t.Fatal("NewAddon returned nil")
	}
	// IsInitialized should be false for a non-existent directory
	if addon.IsInitialized() {
		t.Error("expected IsInitialized() to be false for /tmp/addon")
	}
}
