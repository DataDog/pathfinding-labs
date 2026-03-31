package cmd

import "testing"

func TestMergeAddonOutputs_empty(t *testing.T) {
	block := map[string]any{"starting_user_access_key_id": "AKIA123"}
	result := mergeAddonOutputs(block, nil)
	if _, ok := result["addon"]; ok {
		t.Error("expected no 'addon' key when addonVals is nil")
	}
	if result["starting_user_access_key_id"] != "AKIA123" {
		t.Error("original fields should be preserved")
	}
}

func TestMergeAddonOutputs_emptyMap(t *testing.T) {
	block := map[string]any{"attack_path": "a→b"}
	result := mergeAddonOutputs(block, map[string]any{})
	if _, ok := result["addon"]; ok {
		t.Error("expected no 'addon' key when addonVals is empty map")
	}
}

func TestMergeAddonOutputs_withValues(t *testing.T) {
	block := map[string]any{
		"starting_user_access_key_id": "AKIA123",
		"attack_path":                 "a→b",
	}
	addonVals := map[string]any{
		"audit_user_access_key_id":     "AKIA_AUDIT",
		"audit_user_secret_access_key": "SECRET_AUDIT",
	}
	result := mergeAddonOutputs(block, addonVals)

	// Original fields preserved
	if result["starting_user_access_key_id"] != "AKIA123" {
		t.Error("original field missing after merge")
	}

	// Addon nested under "addon" key
	nested, ok := result["addon"].(map[string]any)
	if !ok {
		t.Fatalf("expected 'addon' key to be map[string]any, got %T", result["addon"])
	}
	if nested["audit_user_access_key_id"] != "AKIA_AUDIT" {
		t.Errorf("addon field missing: %v", nested)
	}
}

func TestMergeAddonOutputs_doesNotMutateOriginal(t *testing.T) {
	block := map[string]any{"k": "v"}
	addonVals := map[string]any{"x": "y"}

	result := mergeAddonOutputs(block, addonVals)

	// Original block must not be mutated
	if _, ok := block["addon"]; ok {
		t.Error("original block was mutated by mergeAddonOutputs")
	}
	// Result has the addon key
	if _, ok := result["addon"]; !ok {
		t.Error("result missing 'addon' key")
	}
}
