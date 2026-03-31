package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestHasAddon(t *testing.T) {
	tests := []struct {
		name  string
		cfg   Config
		want  bool
	}{
		{
			name: "no addon configured",
			cfg:  Config{},
			want: false,
		},
		{
			name: "addon config with empty path",
			cfg:  Config{Addon: &AddonConfig{Path: ""}},
			want: false,
		},
		{
			name: "addon config with path set",
			cfg:  Config{Addon: &AddonConfig{Path: "/some/path"}},
			want: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.cfg.HasAddon(); got != tt.want {
				t.Errorf("HasAddon() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestGetAddonTFVarEnv(t *testing.T) {
	t.Run("returns nil when no addon configured", func(t *testing.T) {
		cfg := Config{AWS: AWSConfig{Prod: AccountConfig{Profile: "my-profile"}}}
		if got := cfg.GetAddonTFVarEnv(); got != nil {
			t.Errorf("expected nil, got %v", got)
		}
	})

	t.Run("returns TF_VAR entries with explicit region", func(t *testing.T) {
		cfg := Config{
			AWS:   AWSConfig{Prod: AccountConfig{Profile: "my-profile", Region: "eu-west-1"}},
			Addon: &AddonConfig{Path: "/some/addon"},
		}
		env := cfg.GetAddonTFVarEnv()
		if len(env) != 2 {
			t.Fatalf("expected 2 env vars, got %d: %v", len(env), env)
		}
		assertContains(t, env, "TF_VAR_prod_account_aws_profile=my-profile")
		assertContains(t, env, "TF_VAR_aws_region=eu-west-1")
	})

	t.Run("defaults region to us-east-1 when not set", func(t *testing.T) {
		cfg := Config{
			AWS:   AWSConfig{Prod: AccountConfig{Profile: "my-profile"}},
			Addon: &AddonConfig{Path: "/some/addon"},
		}
		env := cfg.GetAddonTFVarEnv()
		assertContains(t, env, "TF_VAR_aws_region=us-east-1")
	})
}

func TestAddonConfigRoundTrip(t *testing.T) {
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "plabs.yaml")

	original := &Config{
		AWS:         AWSConfig{Prod: AccountConfig{Profile: "test-profile", Region: "us-west-2"}},
		Addon:       &AddonConfig{Path: "/my/addon"},
		Initialized: true,
	}

	if err := original.SaveToPath(cfgPath); err != nil {
		t.Fatalf("SaveToPath: %v", err)
	}

	loaded, err := LoadFromPath(cfgPath)
	if err != nil {
		t.Fatalf("LoadFromPath: %v", err)
	}

	if !loaded.HasAddon() {
		t.Error("expected HasAddon() to be true after round-trip")
	}
	if loaded.Addon.Path != "/my/addon" {
		t.Errorf("Addon.Path = %q, want %q", loaded.Addon.Path, "/my/addon")
	}
}

func TestAddonConfigNilAfterLoad(t *testing.T) {
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "plabs.yaml")

	original := &Config{
		AWS:         AWSConfig{Prod: AccountConfig{Profile: "test-profile"}},
		Initialized: true,
	}
	if err := original.SaveToPath(cfgPath); err != nil {
		t.Fatalf("SaveToPath: %v", err)
	}

	// Ensure the file doesn't contain addon key
	data, err := os.ReadFile(cfgPath)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	content := string(data)
	if contains(content, "addon:") {
		t.Errorf("expected no addon key in YAML, got:\n%s", content)
	}

	loaded, err := LoadFromPath(cfgPath)
	if err != nil {
		t.Fatalf("LoadFromPath: %v", err)
	}
	if loaded.HasAddon() {
		t.Error("expected HasAddon() to be false when not configured")
	}
}

// helpers

func assertContains(t *testing.T, slice []string, want string) {
	t.Helper()
	for _, s := range slice {
		if s == want {
			return
		}
	}
	t.Errorf("expected %q in %v", want, slice)
}

func contains(s, substr string) bool {
	return len(s) > 0 && len(substr) > 0 &&
		func() bool {
			for i := 0; i <= len(s)-len(substr); i++ {
				if s[i:i+len(substr)] == substr {
					return true
				}
			}
			return false
		}()
}
