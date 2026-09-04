package terraform

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// tfStateResourceCount is the minimal shape needed to tell whether a
// terraform.tfstate file has any real resources in it.
type tfStateResourceCount struct {
	Resources []json.RawMessage `json:"resources"`
}

// hasResources reports whether the state file at path has one or more
// resources recorded in it. A missing file or one with zero resources
// (including a freshly-initialized empty state) both report false.
func hasResources(path string) (bool, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, err
	}

	var state tfStateResourceCount
	if err := json.Unmarshal(data, &state); err != nil {
		return false, fmt.Errorf("failed to parse %s: %w", path, err)
	}

	return len(state.Resources) > 0, nil
}

// MigrateStateToCanonicalPath performs the one-time move of an existing
// per-directory terraform.tfstate into statePath, so dev mode and normal
// mode share one state file instead of each tracking its own and orphaning
// resources when you switch between them.
//
// candidateDirs are the directories that may hold "the real" state under
// the old (pre-migration) implicit-local-backend behavior — typically the
// managed clone's RepoPath and, if dev mode has ever been configured, the
// dev checkout path. Empty and duplicate entries are ignored.
//
// If statePath already exists, this is a no-op (migration already ran).
// If no candidate holds a non-empty state, this is a no-op — there's
// nothing to migrate, and the next `terraform init` will create a fresh
// empty state at statePath. If more than one candidate holds a non-empty,
// distinct state, migration is refused with an error describing both
// paths so the conflict can be resolved by hand instead of silently
// discarding one side's tracked resources.
func MigrateStateToCanonicalPath(statePath string, candidateDirs []string) (migrated bool, err error) {
	if _, err := os.Stat(statePath); err == nil {
		return false, nil
	}

	seen := make(map[string]bool)
	var nonEmpty []string
	for _, dir := range candidateDirs {
		if dir == "" || seen[dir] {
			continue
		}
		seen[dir] = true

		candidate := filepath.Join(dir, "terraform.tfstate")
		ok, err := hasResources(candidate)
		if err != nil {
			return false, err
		}
		if ok {
			nonEmpty = append(nonEmpty, candidate)
		}
	}

	if len(nonEmpty) == 0 {
		return false, nil
	}

	if len(nonEmpty) > 1 {
		return false, fmt.Errorf(
			"cannot auto-migrate terraform state: found deployed resources in more than one location:\n  %s\n\n"+
				"These need to be reconciled by hand before dev mode and normal mode can share one state file.\n"+
				"Pick the one that reflects reality, then either:\n"+
				"  - destroy the resources tracked by the other one and delete its terraform.tfstate, or\n"+
				"  - `terraform state pull`/`push` to merge them into a single file at:\n"+
				"    %s",
			strings.Join(nonEmpty, "\n  "), statePath)
	}

	source := nonEmpty[0]

	if err := os.MkdirAll(filepath.Dir(statePath), 0755); err != nil {
		return false, fmt.Errorf("failed to create state directory: %w", err)
	}

	if err := copyFile(source, statePath); err != nil {
		return false, fmt.Errorf("failed to migrate state to %s: %w", statePath, err)
	}

	if err := os.Rename(source, source+".pre-migration.bak"); err != nil {
		return false, fmt.Errorf("state was copied to %s but failed to back up the original at %s: %w", statePath, source, err)
	}

	// Best-effort: carry over the .backup file too, but don't fail migration over it.
	if backup := source + ".backup"; fileExists(backup) {
		_ = copyFile(backup, statePath+".backup")
		_ = os.Rename(backup, backup+".pre-migration.bak")
	}

	return true, nil
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		return err
	}
	defer out.Close()

	if _, err := io.Copy(out, in); err != nil {
		return err
	}
	return out.Close()
}
