package cmd

import (
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

var addonCmd = &cobra.Command{
	Use:   "addon",
	Short: "Manage plabs addons (user-supplied Terraform extensions)",
	Long: `Addons are user-supplied Terraform roots that provision account-level
resources alongside pathfinding-labs scenarios.

Examples:
  plabs addon init --template audit-user
  plabs addon apply
  plabs addon destroy`,
}

var addonInitTemplate string

var addonInitCmd = &cobra.Command{
	Use:   "init [path]",
	Short: "Initialise an addon from a built-in template",
	Long: `Copy a built-in addon template to a local directory and register it in
~/.plabs/plabs.yaml so that 'plabs apply' and 'plabs output' pick it up.

Available templates:
  audit-user   Read-only IAM user for agent reconnaissance
               (iam:Get*, iam:List*, sts:GetCallerIdentity)

The destination path defaults to ~/.plabs/addons/<template>.

Examples:
  plabs addon init --template audit-user
  plabs addon init --template audit-user /path/to/my-addon`,
	Args: cobra.MaximumNArgs(1),
	RunE: runAddonInit,
}

var addonApplyCmd = &cobra.Command{
	Use:   "apply",
	Short: "Apply the configured addon",
	Long: `Run terraform init + apply in the addon directory configured in
~/.plabs/plabs.yaml.`,
	RunE: runAddonApply,
}

var addonDestroyCmd = &cobra.Command{
	Use:   "destroy",
	Short: "Destroy the configured addon",
	Long:  `Run terraform destroy in the addon directory configured in ~/.plabs/plabs.yaml.`,
	RunE:  runAddonDestroy,
}

func init() {
	addonInitCmd.Flags().StringVar(&addonInitTemplate, "template", "", "Template name (e.g., audit-user)")
	_ = addonInitCmd.MarkFlagRequired("template")

	addonCmd.AddCommand(addonInitCmd)
	addonCmd.AddCommand(addonApplyCmd)
	addonCmd.AddCommand(addonDestroyCmd)
}

// buildAddon creates and returns an Addon for the current config, or nil if
// no addon is configured. It does NOT initialise terraform.
func buildAddon(cfg *config.Config) *terraform.Addon {
	if !cfg.HasAddon() {
		return nil
	}
	paths, err := getWorkingPaths()
	if err != nil {
		return nil
	}
	return terraform.NewAddon(paths.BinPath, cfg.Addon.Path, cfg.GetAddonTFVarEnv())
}

// ---- command handlers ----

func runAddonInit(cmd *cobra.Command, args []string) error {
	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	// Template source: <repo>/examples/addons/<template>/
	templateSrc := filepath.Join(paths.TerraformDir, "examples", "addons", addonInitTemplate)
	if _, err := os.Stat(templateSrc); os.IsNotExist(err) {
		return fmt.Errorf("template %q not found at %s", addonInitTemplate, templateSrc)
	}

	// Destination: first positional arg, or ~/.plabs/addons/<template>
	dest := filepath.Join(paths.PlabsRoot, "addons", addonInitTemplate)
	if len(args) > 0 {
		dest = args[0]
	}
	dest, err = filepath.Abs(dest)
	if err != nil {
		return fmt.Errorf("failed to resolve destination path: %w", err)
	}

	cyan := color.New(color.FgCyan).SprintFunc()
	green := color.New(color.FgGreen).SprintFunc()

	fmt.Printf("Copying template %s → %s\n", cyan(addonInitTemplate), cyan(dest))

	if err := copyDir(templateSrc, dest); err != nil {
		return fmt.Errorf("failed to copy template: %w", err)
	}

	// Persist the addon path in config
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}
	cfg.Addon = &config.AddonConfig{Path: dest}
	if err := cfg.Save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	fmt.Println()
	fmt.Println(green("Addon initialised!"))
	fmt.Printf("Addon directory : %s\n", dest)
	fmt.Println()
	fmt.Printf("Next steps:\n")
	fmt.Printf("  1. Review %s\n", cyan(filepath.Join(dest, "main.tf")))
	fmt.Printf("  2. Run %s to provision the addon\n", cyan("plabs addon apply"))
	fmt.Printf("  3. The addon outputs will appear under the %s key in %s\n",
		cyan(`"addon"`), cyan("plabs output --raw <scenario-id>"))
	fmt.Println()

	return nil
}

func runAddonApply(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}
	if !cfg.HasAddon() {
		return fmt.Errorf("no addon configured — run 'plabs addon init --template <name>' first")
	}

	cyan := color.New(color.FgCyan).SprintFunc()
	green := color.New(color.FgGreen).SprintFunc()

	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	addon := terraform.NewAddon(paths.BinPath, cfg.Addon.Path, cfg.GetAddonTFVarEnv())

	fmt.Println()
	fmt.Printf("%s Applying addon: %s\n", cyan("→"), cfg.Addon.Path)
	fmt.Println()

	if !addon.IsInitialized() {
		fmt.Println("Running terraform init...")
		if err := addon.Init(); err != nil {
			return fmt.Errorf("addon init failed: %w", err)
		}
		fmt.Println()
	}

	if err := addon.Apply(); err != nil {
		return fmt.Errorf("addon apply failed: %w", err)
	}

	fmt.Println()
	fmt.Println(green("Addon applied successfully."))
	fmt.Println()

	return nil
}

func runAddonDestroy(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}
	if !cfg.HasAddon() {
		return fmt.Errorf("no addon configured")
	}

	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	yellow := color.New(color.FgYellow).SprintFunc()
	green := color.New(color.FgGreen).SprintFunc()

	addon := terraform.NewAddon(paths.BinPath, cfg.Addon.Path, cfg.GetAddonTFVarEnv())
	if !addon.IsInitialized() {
		fmt.Println(yellow("Addon is not initialised — nothing to destroy."))
		return nil
	}

	fmt.Println()
	fmt.Printf("%s Destroying addon: %s\n", yellow("!"), cfg.Addon.Path)
	fmt.Println()

	if err := addon.Destroy(); err != nil {
		return fmt.Errorf("addon destroy failed: %w", err)
	}

	fmt.Println()
	fmt.Println(green("Addon destroyed."))
	fmt.Println()

	return nil
}

// copyDir recursively copies src to dst, creating dst if it does not exist.
func copyDir(src, dst string) error {
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)

		if info.IsDir() {
			return os.MkdirAll(target, info.Mode())
		}
		return copyFile(path, target, info.Mode())
	})
}

func copyFile(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}

	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	return err
}
