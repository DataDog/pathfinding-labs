package config

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strings"
)

// Wizard runs the interactive setup wizard
type Wizard struct {
	reader *bufio.Reader
}

// NewWizard creates a new setup wizard
func NewWizard() *Wizard {
	return &Wizard{
		reader: bufio.NewReader(os.Stdin),
	}
}

// Run executes the setup wizard and returns the configuration
func (w *Wizard) Run() (*Config, error) {
	fmt.Println("\n╔════════════════════════════════════════════════════════════╗")
	fmt.Println("║         Pathfinding Labs Setup Wizard                      ║")
	fmt.Println("╚════════════════════════════════════════════════════════════╝")

	fmt.Println("\nThis wizard will help you configure plabs for your AWS environment.")
	fmt.Println("You'll need:")
	fmt.Println("  • At least one AWS account ID (12-digit number)")
	fmt.Println("  • AWS CLI profiles configured for your accounts")
	fmt.Println()

	cfg := &Config{}

	// Ask about account mode
	fmt.Println("How many AWS accounts do you want to use?")
	fmt.Println("  1) Single account (prod only) - For most scenarios")
	fmt.Println("  2) Multi-account (prod + dev/ops) - For cross-account scenarios")
	fmt.Print("\nEnter choice [1]: ")

	choice, err := w.readLine()
	if err != nil {
		return nil, err
	}
	choice = strings.TrimSpace(choice)
	if choice == "" {
		choice = "1"
	}

	multiAccount := choice == "2"

	// Get production account details
	fmt.Println("\n─── Production Account ───")

	prodID, err := w.promptAccountID("Production AWS Account ID")
	if err != nil {
		return nil, err
	}
	cfg.ProdAccountID = prodID

	prodProfile, err := w.promptString("Production AWS CLI Profile", "default")
	if err != nil {
		return nil, err
	}
	cfg.ProdProfile = prodProfile

	if multiAccount {
		// Get development account details
		fmt.Println("\n─── Development Account (optional) ───")
		fmt.Println("Press Enter to skip if you don't have a dev account.")

		devID, err := w.promptAccountID("Development AWS Account ID")
		if err != nil {
			return nil, err
		}
		if devID != "" {
			cfg.DevAccountID = devID

			devProfile, err := w.promptString("Development AWS CLI Profile", "")
			if err != nil {
				return nil, err
			}
			cfg.DevProfile = devProfile
		}

		// Get operations account details
		fmt.Println("\n─── Operations Account (optional) ───")
		fmt.Println("Press Enter to skip if you don't have an ops account.")

		opsID, err := w.promptAccountID("Operations AWS Account ID")
		if err != nil {
			return nil, err
		}
		if opsID != "" {
			cfg.OpsAccountID = opsID

			opsProfile, err := w.promptString("Operations AWS CLI Profile", "")
			if err != nil {
				return nil, err
			}
			cfg.OpsProfile = opsProfile
		}
	}

	cfg.Initialized = true

	// Summary
	fmt.Println("\n─── Configuration Summary ───")
	fmt.Printf("Production Account: %s (profile: %s)\n", cfg.ProdAccountID, cfg.ProdProfile)
	if cfg.DevAccountID != "" {
		fmt.Printf("Development Account: %s (profile: %s)\n", cfg.DevAccountID, cfg.DevProfile)
	}
	if cfg.OpsAccountID != "" {
		fmt.Printf("Operations Account: %s (profile: %s)\n", cfg.OpsAccountID, cfg.OpsProfile)
	}

	if cfg.IsSingleAccountMode() {
		fmt.Println("\nMode: Single-account (cross-account scenarios will be unavailable)")
	} else {
		fmt.Println("\nMode: Multi-account (all scenarios available)")
	}

	return cfg, nil
}

// promptString prompts for a string value with an optional default
func (w *Wizard) promptString(prompt, defaultVal string) (string, error) {
	if defaultVal != "" {
		fmt.Printf("%s [%s]: ", prompt, defaultVal)
	} else {
		fmt.Printf("%s: ", prompt)
	}

	input, err := w.readLine()
	if err != nil {
		return "", err
	}

	input = strings.TrimSpace(input)
	if input == "" {
		return defaultVal, nil
	}
	return input, nil
}

// promptAccountID prompts for an AWS account ID with validation
func (w *Wizard) promptAccountID(prompt string) (string, error) {
	for {
		input, err := w.promptString(prompt, "")
		if err != nil {
			return "", err
		}

		if input == "" {
			return "", nil
		}

		if !isValidAccountID(input) {
			fmt.Println("Invalid account ID. Must be a 12-digit number.")
			continue
		}

		return input, nil
	}
}

// readLine reads a line from stdin
func (w *Wizard) readLine() (string, error) {
	line, err := w.reader.ReadString('\n')
	if err != nil {
		return "", err
	}
	return strings.TrimSuffix(line, "\n"), nil
}

// isValidAccountID validates an AWS account ID
func isValidAccountID(id string) bool {
	matched, _ := regexp.MatchString(`^\d{12}$`, id)
	return matched
}
