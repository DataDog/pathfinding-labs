package config

import (
	"os"
	"strings"
	"testing"
)

func TestGetScenarioConfig_NilMap(t *testing.T) {
	c := &Config{}
	val, ok := c.GetScenarioConfig("my-scenario", "github_repo")
	if ok {
		t.Error("expected false for nil ScenarioConfigs")
	}
	if val != "" {
		t.Errorf("expected empty string, got %q", val)
	}
}

func TestGetScenarioConfig_UnknownScenario(t *testing.T) {
	c := &Config{
		ScenarioConfigs: map[string]map[string]string{
			"other-scenario": {"key": "value"},
		},
	}
	val, ok := c.GetScenarioConfig("my-scenario", "key")
	if ok {
		t.Error("expected false for unknown scenario")
	}
	if val != "" {
		t.Errorf("expected empty string, got %q", val)
	}
}

func TestGetScenarioConfig_UnknownKey(t *testing.T) {
	c := &Config{
		ScenarioConfigs: map[string]map[string]string{
			"my-scenario": {"other_key": "value"},
		},
	}
	val, ok := c.GetScenarioConfig("my-scenario", "missing_key")
	if ok {
		t.Error("expected false for unknown key")
	}
	if val != "" {
		t.Errorf("expected empty string, got %q", val)
	}
}

func TestGetScenarioConfig_Found(t *testing.T) {
	c := &Config{
		ScenarioConfigs: map[string]map[string]string{
			"github-oidc-cross-account-pivot": {"github_repo": "my-org/my-repo"},
		},
	}
	val, ok := c.GetScenarioConfig("github-oidc-cross-account-pivot", "github_repo")
	if !ok {
		t.Error("expected true for known key")
	}
	if val != "my-org/my-repo" {
		t.Errorf("expected %q, got %q", "my-org/my-repo", val)
	}
}

func TestSetScenarioConfig_InitializesNilMap(t *testing.T) {
	c := &Config{}
	c.SetScenarioConfig("my-scenario", "my_key", "my-value")
	if c.ScenarioConfigs == nil {
		t.Fatal("expected ScenarioConfigs to be initialized")
	}
	if c.ScenarioConfigs["my-scenario"] == nil {
		t.Fatal("expected inner map to be initialized")
	}
	if c.ScenarioConfigs["my-scenario"]["my_key"] != "my-value" {
		t.Errorf("expected %q, got %q", "my-value", c.ScenarioConfigs["my-scenario"]["my_key"])
	}
}

func TestSetScenarioConfig_OverwritesExistingValue(t *testing.T) {
	c := &Config{
		ScenarioConfigs: map[string]map[string]string{
			"my-scenario": {"my_key": "old-value"},
		},
	}
	c.SetScenarioConfig("my-scenario", "my_key", "new-value")
	if c.ScenarioConfigs["my-scenario"]["my_key"] != "new-value" {
		t.Errorf("expected %q, got %q", "new-value", c.ScenarioConfigs["my-scenario"]["my_key"])
	}
}

func TestSetScenarioConfig_MultipleScenarios(t *testing.T) {
	c := &Config{}
	c.SetScenarioConfig("scenario-a", "key1", "val1")
	c.SetScenarioConfig("scenario-b", "key2", "val2")

	v1, ok1 := c.GetScenarioConfig("scenario-a", "key1")
	v2, ok2 := c.GetScenarioConfig("scenario-b", "key2")

	if !ok1 || v1 != "val1" {
		t.Errorf("scenario-a/key1: got (%q, %v), want (%q, true)", v1, ok1, "val1")
	}
	if !ok2 || v2 != "val2" {
		t.Errorf("scenario-b/key2: got (%q, %v), want (%q, true)", v2, ok2, "val2")
	}
}

func TestGetAllScenarioConfigs_Nil(t *testing.T) {
	c := &Config{}
	if c.GetAllScenarioConfigs("any") != nil {
		t.Error("expected nil for nil ScenarioConfigs")
	}
}

func TestGetAllScenarioConfigs_UnknownScenario(t *testing.T) {
	c := &Config{
		ScenarioConfigs: map[string]map[string]string{
			"other": {"k": "v"},
		},
	}
	if c.GetAllScenarioConfigs("unknown") != nil {
		t.Error("expected nil for unknown scenario")
	}
}

func TestGetAllScenarioConfigs_Known(t *testing.T) {
	c := &Config{
		ScenarioConfigs: map[string]map[string]string{
			"my-scenario": {"key1": "val1", "key2": "val2"},
		},
	}
	vals := c.GetAllScenarioConfigs("my-scenario")
	if vals == nil {
		t.Fatal("expected non-nil map")
	}
	if vals["key1"] != "val1" || vals["key2"] != "val2" {
		t.Errorf("unexpected values: %v", vals)
	}
}

func TestGenerateTFVars_ScenarioConfigs(t *testing.T) {
	c := &Config{
		AWS: AWSConfig{
			Prod: AccountConfig{Profile: "test-profile"},
		},
		ScenarioConfigs: map[string]map[string]string{
			"github-oidc-cross-account-pivot": {"github_repo": "my-org/my-repo"},
		},
	}

	tfvars := c.GenerateTFVars()

	wantLine := `github-oidc-cross-account-pivot-github_repo = "my-org/my-repo"`
	if !strings.Contains(tfvars, wantLine) {
		t.Errorf("expected tfvars to contain %q\n\nGot:\n%s", wantLine, tfvars)
	}
	if !strings.Contains(tfvars, "# Scenario specific configurations") {
		t.Error("expected tfvars to contain the scenario specific configurations comment")
	}
}

func TestGenerateTFVars_NoScenarioConfigs(t *testing.T) {
	c := &Config{
		AWS: AWSConfig{
			Prod: AccountConfig{Profile: "test-profile"},
		},
	}

	tfvars := c.GenerateTFVars()

	if strings.Contains(tfvars, "# Scenario specific configurations") {
		t.Error("expected no scenario configs section when ScenarioConfigs is empty")
	}
}

func TestGenerateTFVars_ScenarioConfigsSortedDeterministically(t *testing.T) {
	c := &Config{
		AWS: AWSConfig{
			Prod: AccountConfig{Profile: "test-profile"},
		},
		ScenarioConfigs: map[string]map[string]string{
			"scenario-b": {"zkey": "zval", "akey": "aval"},
			"scenario-a": {"mkey": "mval"},
		},
	}

	tfvars := c.GenerateTFVars()

	aPos := strings.Index(tfvars, "scenario-a-")
	bPos := strings.Index(tfvars, "scenario-b-")
	if aPos > bPos {
		t.Error("expected scenario-a to appear before scenario-b (sorted order)")
	}

	akeyPos := strings.Index(tfvars, "scenario-b-akey")
	zkeyPos := strings.Index(tfvars, "scenario-b-zkey")
	if akeyPos > zkeyPos {
		t.Error("expected akey to appear before zkey within scenario-b (sorted order)")
	}
}

func TestGenerateTFVars_ScenarioFlags(t *testing.T) {
	c := &Config{
		AWS: AWSConfig{
			Prod: AccountConfig{Profile: "test-profile"},
		},
		Flags: map[string]string{
			"glue-003-to-admin":              "flag{g3}",
			"iam-002-iam-createaccesskey-to-admin": "flag{iam2}",
		},
	}

	tfvars := c.GenerateTFVars()

	if !strings.Contains(tfvars, "scenario_flags = {") {
		t.Error("expected scenario_flags block in tfvars")
	}
	if !strings.Contains(tfvars, `"glue-003-to-admin" = "flag{g3}"`) {
		t.Errorf("expected glue-003 flag line; got:\n%s", tfvars)
	}
	if !strings.Contains(tfvars, `"iam-002-iam-createaccesskey-to-admin" = "flag{iam2}"`) {
		t.Errorf("expected iam-002 flag line; got:\n%s", tfvars)
	}

	// Keys must appear in sorted order so the generated tfvars is stable across runs.
	gluePos := strings.Index(tfvars, `"glue-003-to-admin"`)
	iamPos := strings.Index(tfvars, `"iam-002-iam-createaccesskey-to-admin"`)
	if gluePos > iamPos {
		t.Errorf("expected alphabetical flag order (g-* before i-*); gluePos=%d iamPos=%d", gluePos, iamPos)
	}
}

func TestGenerateTFVars_ScenarioFlags_Empty(t *testing.T) {
	c := &Config{
		AWS: AWSConfig{
			Prod: AccountConfig{Profile: "test-profile"},
		},
	}
	tfvars := c.GenerateTFVars()
	if strings.Contains(tfvars, "scenario_flags = {") {
		t.Error("expected no scenario_flags block when Flags is empty")
	}
}

func TestLoadFlagsFromFile(t *testing.T) {
	dir := t.TempDir()
	path := dir + "/test-flags.yaml"
	content := "flags:\n  glue-003-to-admin: \"flag{abc}\"\n  iam-002-iam-createaccesskey-to-admin: \"flag{def}\"\n"
	if err := os.WriteFile(path, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}

	c := &Config{}
	if err := c.LoadFlagsFromFile(path); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(c.Flags) != 2 {
		t.Errorf("expected 2 flags, got %d", len(c.Flags))
	}
	if c.Flags["glue-003-to-admin"] != "flag{abc}" {
		t.Errorf("expected flag{abc}, got %q", c.Flags["glue-003-to-admin"])
	}
}

func TestLoadFlagsFromFile_Missing(t *testing.T) {
	c := &Config{}
	err := c.LoadFlagsFromFile("/nonexistent/flags.yaml")
	if err == nil {
		t.Fatal("expected error for nonexistent file")
	}
}

func TestLoadFlagsFromFile_NoFlagsKey(t *testing.T) {
	dir := t.TempDir()
	path := dir + "/bad.yaml"
	if err := os.WriteFile(path, []byte("other_key: foo\n"), 0600); err != nil {
		t.Fatal(err)
	}
	c := &Config{}
	err := c.LoadFlagsFromFile(path)
	if err == nil {
		t.Fatal("expected error for file without flags: key")
	}
}
