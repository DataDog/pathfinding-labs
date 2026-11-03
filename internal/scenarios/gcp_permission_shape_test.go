package scenarios

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// gcpLabs is the complete set of GCP scenarios, keyed by pathfinding-cloud ID.
var gcpLabs = map[string]string{
	"gcp-cloudfunctions-001": "single-account/privesc-one-hop/to-admin/gcp-cloudfunctions-001-iam-serviceaccountsactas+cloudfunctions-functionscreate/scenario.yaml",
	"gcp-cloudfunctions-002": "single-account/privesc-one-hop/to-admin/gcp-cloudfunctions-002-cloudfunctions-functionsupdate/scenario.yaml",
	"gcp-iam-001":            "single-account/privesc-one-hop/to-admin/gcp-iam-001-iam-serviceaccountsgetaccesstoken/scenario.yaml",
}

const gcpLabsBase = "../../modules/scenarios/gcp/"

// eliminatedGcloudMechanics are permissions that --build-service-account
// removes from the gcloud functions deploy flow. They must not be granted by
// Terraform NOR listed in scenario.yaml helpful.
var eliminatedGcloudMechanics = []string{
	"cloudbuild.builds.get",
	"resourcemanager.projects.getIamPolicy",
	"run.services.getIamPolicy",
	"run.services.setIamPolicy",
}

// loadGCPLab loads one GCP scenario by its pathfinding-cloud ID.
func loadGCPLab(t *testing.T, id string) *Scenario {
	t.Helper()
	s, err := LoadFromFile(gcpLabsBase + gcpLabs[id])
	if err != nil {
		t.Fatalf("%s: failed to load scenario.yaml: %v", id, err)
	}
	if s.Cloud != "gcp" {
		t.Errorf("%s: Cloud = %q, want \"gcp\"", id, s.Cloud)
	}
	return s
}

func requiredPerms(s *Scenario) map[string]string {
	out := map[string]string{}
	for _, pe := range s.Permissions.Required {
		for _, p := range pe.Permissions {
			out[p.Permission] = p.Purpose
		}
	}
	return out
}

func helpfulPerms(s *Scenario) map[string]string {
	out := map[string]string{}
	for _, pe := range s.Permissions.Helpful {
		for _, p := range pe.Permissions {
			out[p.Permission] = p.Purpose
		}
	}
	return out
}

// TestGCPLabsCloudDetection ensures every scenario under modules/scenarios/gcp
// is derived as cloud "gcp" and that no new GCP lab is added without being
// covered by this shape test.
func TestGCPLabsCloudDetection(t *testing.T) {
	for id := range gcpLabs {
		loadGCPLab(t, id)
	}
}

// TestGCPRequiredShape verifies the "required" set: permissions that are
// needed even with direct raw-API requests, no tooling overhead. For Cloud
// Functions gen2 scenarios this includes cloudfunctions.operations.get (the
// deploy/update calls return an async LRO that must be polled to know when
// the function is ACTIVE and to get its Cloud Run URI) — it must NOT appear
// under helpful as a gcloud-only mechanic.
func TestGCPRequiredShape(t *testing.T) {
	t.Run("cloudfunctions labs include operations.get in required", func(t *testing.T) {
		for _, id := range []string{"gcp-cloudfunctions-001", "gcp-cloudfunctions-002"} {
			req := requiredPerms(loadGCPLab(t, id))
			if _, ok := req["cloudfunctions.operations.get"]; !ok {
				t.Errorf("%s: cloudfunctions.operations.get missing from permissions.required (raw API LRO poll)", id)
			}
		}
	})

	t.Run("iam-001 requires only getAccessToken", func(t *testing.T) {
		req := requiredPerms(loadGCPLab(t, "gcp-iam-001"))
		if len(req) != 1 {
			t.Errorf("gcp-iam-001: got %d required permissions, want 1 (%v)", len(req), req)
		}
		if _, ok := req["iam.serviceAccounts.getAccessToken"]; !ok {
			t.Errorf("gcp-iam-001: iam.serviceAccounts.getAccessToken missing from permissions.required")
		}
	})
}

// TestGCPHelpfulGrantedInTerraform verifies the Terraform side of the shape:
// the starting SA holds exactly two project-level custom roles — `_required`
// (mirroring permissions.required 1:1) and `_help` (mirroring permissions.helpful
// 1:1: gcloud mechanics + recon). Every permission declared in scenario.yaml
// required/helpful must appear in the module's main.tf, and the helpful role
// must use the _help suffix (not the pre-2026-11 _mech/_gcloud_mechanic form).
func TestGCPHelpfulGrantedInTerraform(t *testing.T) {
	for id := range gcpLabs {
		s := loadGCPLab(t, id)

		mainTf := filepath.Join(filepath.Dir(gcpLabsBase+gcpLabs[id]), "main.tf")
		tfBytes, err := os.ReadFile(mainTf)
		if err != nil {
			t.Fatalf("%s: failed to read main.tf: %v", id, err)
		}
		tf := string(tfBytes)

		for perm := range requiredPerms(s) {
			if !strings.Contains(tf, fmt.Sprintf("%q", perm)) {
				t.Errorf("%s: required permission %s declared in scenario.yaml but absent from main.tf", id, perm)
			}
		}
		for perm := range helpfulPerms(s) {
			if !strings.Contains(tf, fmt.Sprintf("%q", perm)) {
				t.Errorf("%s: helpful permission %s declared in scenario.yaml but NOT granted in main.tf — helpful (gcloud mechanics + recon) must be granted via the _help role", id, perm)
			}
		}

		if strings.Contains(tf, "_mech\"") || strings.Contains(tf, "_gcloud_mechanic\"") {
			t.Errorf("%s: main.tf still uses the pre-2026-11 _mech/_gcloud_mechanic role — rename to _help and fold in the recon permissions", id)
		}
	}
}
// TestGCPGcloudMechanicShape verifies the gcloud-mechanic set: permissions
// needed only when the demo runs via `gcloud` (default mode) but not with the
// raw API. They live in permissions.helpful with a purpose that explicitly
// identifies them as gcloud-only ("gcloud", "only", "not needed with the raw
// API") so validators and readers can distinguish them from recon permissions.
func TestGCPGcloudMechanicShape(t *testing.T) {
	for _, id := range []string{"gcp-cloudfunctions-001", "gcp-cloudfunctions-002"} {
		s := loadGCPLab(t, id)
		helpful := helpfulPerms(s)

		for _, perm := range []string{"cloudfunctions.functions.get", "resourcemanager.projects.get"} {
			purpose, ok := helpful[perm]
			if !ok {
				t.Errorf("%s: gcloud-mechanic %s missing from permissions.helpful", id, perm)
				continue
			}
			lower := strings.ToLower(purpose)
			// Marker wording per SCHEMA.md: "gcloud" + "only" + "not needed
			// with the raw API" (or equivalent, e.g. "raw PATCH API").
			for _, marker := range []string{"gcloud", "only", "not needed with the raw"} {
				if !strings.Contains(lower, marker) {
					t.Errorf("%s: purpose of %s must contain %q (got: %s)", id, perm, marker, purpose)
				}
			}
		}

		for _, perm := range eliminatedGcloudMechanics {
			if _, ok := helpful[perm]; ok {
				t.Errorf("%s: eliminated gcloud mechanic %s still listed in helpful (--build-service-account removes it; the lab does not grant it)", id, perm)
			}
		}
	}

	// gcp-iam-001 uses only lightweight gcloud calls (print-access-token) that
	// make no extra permissioned API calls, so it has no gcloud mechanics:
	// none of its helpful purposes may read as gcloud-only overhead.
	t.Run("iam-001 has no gcloud mechanics", func(t *testing.T) {
		for perm, purpose := range helpfulPerms(loadGCPLab(t, "gcp-iam-001")) {
			lower := strings.ToLower(purpose)
			if strings.Contains(lower, "gcloud") && strings.Contains(lower, "only") {
				t.Errorf("gcp-iam-001: %s purpose reads as gcloud-only mechanic (got: %s) — print-access-token makes no extra permissioned calls", perm, purpose)
			}
		}
	})
}
