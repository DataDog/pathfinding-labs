package config

import (
	"os"
	"strings"
	"testing"
)

func TestGetScenarioConfig_NilMap(t *testing.T) {
	ws := &WorkspaceConfig{}
	val, ok := ws.GetScenarioConfig("my-scenario", "github_repo")
	if ok {
		t.Error("expected false for nil ScenarioConfigs")
	}
	if val != "" {
		t.Errorf("expected empty string, got %q", val)
	}
}

func TestGetScenarioConfig_UnknownScenario(t *testing.T) {
	ws := &WorkspaceConfig{
		ScenarioConfigs: map[string]map[string]string{
			"other-scenario": {"key": "value"},
		},
	}
	val, ok := ws.GetScenarioConfig("my-scenario", "key")
	if ok {
		t.Error("expected false for unknown scenario")
	}
	if val != "" {
		t.Errorf("expected empty string, got %q", val)
	}
}

func TestGetScenarioConfig_UnknownKey(t *testing.T) {
	ws := &WorkspaceConfig{
		ScenarioConfigs: map[string]map[string]string{
			"my-scenario": {"other_key": "value"},
		},
	}
	val, ok := ws.GetScenarioConfig("my-scenario", "missing_key")
	if ok {
		t.Error("expected false for unknown key")
	}
	if val != "" {
		t.Errorf("expected empty string, got %q", val)
	}
}

func TestGetScenarioConfig_Found(t *testing.T) {
	ws := &WorkspaceConfig{
		ScenarioConfigs: map[string]map[string]string{
			"github-oidc-cross-account-pivot": {"github_repo": "my-org/my-repo"},
		},
	}
	val, ok := ws.GetScenarioConfig("github-oidc-cross-account-pivot", "github_repo")
	if !ok {
		t.Error("expected true for known key")
	}
	if val != "my-org/my-repo" {
		t.Errorf("expected %q, got %q", "my-org/my-repo", val)
	}
}

func TestSetScenarioConfig_InitializesNilMap(t *testing.T) {
	ws := &WorkspaceConfig{}
	ws.SetScenarioConfig("my-scenario", "my_key", "my-value")
	if ws.ScenarioConfigs == nil {
		t.Fatal("expected ScenarioConfigs to be initialized")
	}
	if ws.ScenarioConfigs["my-scenario"] == nil {
		t.Fatal("expected inner map to be initialized")
	}
	if ws.ScenarioConfigs["my-scenario"]["my_key"] != "my-value" {
		t.Errorf("expected %q, got %q", "my-value", ws.ScenarioConfigs["my-scenario"]["my_key"])
	}
}

func TestSetScenarioConfig_OverwritesExistingValue(t *testing.T) {
	ws := &WorkspaceConfig{
		ScenarioConfigs: map[string]map[string]string{
			"my-scenario": {"my_key": "old-value"},
		},
	}
	ws.SetScenarioConfig("my-scenario", "my_key", "new-value")
	if ws.ScenarioConfigs["my-scenario"]["my_key"] != "new-value" {
		t.Errorf("expected %q, got %q", "new-value", ws.ScenarioConfigs["my-scenario"]["my_key"])
	}
}

func TestSetScenarioConfig_MultipleScenarios(t *testing.T) {
	ws := &WorkspaceConfig{}
	ws.SetScenarioConfig("scenario-a", "key1", "val1")
	ws.SetScenarioConfig("scenario-b", "key2", "val2")

	v1, ok1 := ws.GetScenarioConfig("scenario-a", "key1")
	v2, ok2 := ws.GetScenarioConfig("scenario-b", "key2")

	if !ok1 || v1 != "val1" {
		t.Errorf("scenario-a/key1: got (%q, %v), want (%q, true)", v1, ok1, "val1")
	}
	if !ok2 || v2 != "val2" {
		t.Errorf("scenario-b/key2: got (%q, %v), want (%q, true)", v2, ok2, "val2")
	}
}

func TestGetAllScenarioConfigs_Nil(t *testing.T) {
	ws := &WorkspaceConfig{}
	if ws.GetAllScenarioConfigs("any") != nil {
		t.Error("expected nil for nil ScenarioConfigs")
	}
}

func TestGetAllScenarioConfigs_UnknownScenario(t *testing.T) {
	ws := &WorkspaceConfig{
		ScenarioConfigs: map[string]map[string]string{
			"other": {"k": "v"},
		},
	}
	if ws.GetAllScenarioConfigs("unknown") != nil {
		t.Error("expected nil for unknown scenario")
	}
}

func TestGetAllScenarioConfigs_Known(t *testing.T) {
	ws := &WorkspaceConfig{
		ScenarioConfigs: map[string]map[string]string{
			"my-scenario": {"key1": "val1", "key2": "val2"},
		},
	}
	vals := ws.GetAllScenarioConfigs("my-scenario")
	if vals == nil {
		t.Fatal("expected non-nil map")
	}
	if vals["key1"] != "val1" || vals["key2"] != "val2" {
		t.Errorf("unexpected values: %v", vals)
	}
}

func TestGenerateTFVars_ScenarioConfigs(t *testing.T) {
	ws := &WorkspaceConfig{
		AWS: AWSConfig{
			Prod: AccountConfig{Profile: "test-profile"},
		},
		ScenarioConfigs: map[string]map[string]string{
			"github-oidc-cross-account-pivot": {"github_repo": "my-org/my-repo"},
		},
	}

	tfvars := ws.GenerateTFVars()

	wantLine := `github_oidc_cross_account_pivot_github_repo = "my-org/my-repo"`
	if !strings.Contains(tfvars, wantLine) {
		t.Errorf("expected tfvars to contain %q\n\nGot:\n%s", wantLine, tfvars)
	}
	if !strings.Contains(tfvars, "# Scenario specific configurations") {
		t.Error("expected tfvars to contain the scenario specific configurations comment")
	}
}

func TestGenerateTFVars_NoScenarioConfigs(t *testing.T) {
	ws := &WorkspaceConfig{
		AWS: AWSConfig{
			Prod: AccountConfig{Profile: "test-profile"},
		},
	}

	tfvars := ws.GenerateTFVars()

	if strings.Contains(tfvars, "# Scenario specific configurations") {
		t.Error("expected no scenario configs section when ScenarioConfigs is empty")
	}
}

func TestGenerateTFVars_ScenarioConfigsSortedDeterministically(t *testing.T) {
	ws := &WorkspaceConfig{
		AWS: AWSConfig{
			Prod: AccountConfig{Profile: "test-profile"},
		},
		ScenarioConfigs: map[string]map[string]string{
			"scenario-b": {"zkey": "zval", "akey": "aval"},
			"scenario-a": {"mkey": "mval"},
		},
	}

	tfvars := ws.GenerateTFVars()

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
	ws := &WorkspaceConfig{
		AWS: AWSConfig{
			Prod: AccountConfig{Profile: "test-profile"},
		},
		Flags: map[string]string{
			"glue-003-to-admin":                   "flag{g3}",
			"iam-002-iam-createaccesskey-to-admin": "flag{iam2}",
		},
	}

	tfvars := ws.GenerateTFVars()

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
	ws := &WorkspaceConfig{
		AWS: AWSConfig{
			Prod: AccountConfig{Profile: "test-profile"},
		},
	}
	tfvars := ws.GenerateTFVars()
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

	ws := &WorkspaceConfig{}
	if err := ws.LoadFlagsFromFile(path); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(ws.Flags) != 2 {
		t.Errorf("expected 2 flags, got %d", len(ws.Flags))
	}
	if ws.Flags["glue-003-to-admin"] != "flag{abc}" {
		t.Errorf("expected flag{abc}, got %q", ws.Flags["glue-003-to-admin"])
	}
}

func TestLoadFlagsFromFile_Missing(t *testing.T) {
	ws := &WorkspaceConfig{}
	err := ws.LoadFlagsFromFile("/nonexistent/flags.yaml")
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
	ws := &WorkspaceConfig{}
	err := ws.LoadFlagsFromFile(path)
	if err == nil {
		t.Fatal("expected error for file without flags: key")
	}
}

func TestWorkspaceNames_DefaultFirst(t *testing.T) {
	cfg := &Config{
		ActiveWorkspace: "default",
		Workspaces: map[string]*WorkspaceConfig{
			"zzz":     {},
			"aaa":     {},
			"default": {},
		},
	}
	names := cfg.WorkspaceNames()
	if names[0] != "default" {
		t.Errorf("expected default first, got %v", names)
	}
	if names[1] != "aaa" || names[2] != "zzz" {
		t.Errorf("expected alphabetical after default, got %v", names)
	}
}

func TestNewDefaultConfig(t *testing.T) {
	cfg := NewDefaultConfig()
	if cfg.ActiveName() != "default" {
		t.Errorf("expected default workspace, got %q", cfg.ActiveName())
	}
	if cfg.Active() == nil {
		t.Error("expected non-nil active workspace")
	}
}
