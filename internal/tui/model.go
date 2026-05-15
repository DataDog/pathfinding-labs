package tui

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/atotto/clipboard"
	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/DataDog/pathfinding-labs/internal/aws"
	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/repo"
	"github.com/DataDog/pathfinding-labs/internal/scenarios"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

// Pane represents which pane is focused
type Pane int

const (
	PaneEnvironment Pane = iota
	PaneScenarios
	PaneDetails
)

// Model is the main Bubble Tea model for the TUI
type Model struct {
	// Core data
	paths           *repo.Paths
	config          *config.Config
	tfvars          *terraform.TFVars
	tfRunner        *terraform.Runner
	discovery       *scenarios.Discovery
	allScenarios    []*scenarios.Scenario
	cachedOutputs   terraform.Outputs   // Cached terraform outputs for credentials
	cachedResources map[string][]string // Cached module name -> ARNs

	// UI components
	styles        *Styles
	keys          *KeyMap
	info          *InfoPane
	environment   *EnvironmentPane
	scenariosPane *ScenariosPane
	details       *DetailsPane
	actions       *ActionsPane
	overlay       *Overlay
	filterInput   textinput.Model

	// State
	currentPane Pane
	filtering   bool
	termWidth   int
	termHeight  int
	ready       bool
	loading     bool // true while loading scenarios
	err         error

	// Destroy operation state
	choosingDestroyType bool   // true when showing destroy type choice
	confirmingDestroy   bool   // true when waiting for "destroy" confirmation
	destroyType         string // "scenarios" or "all"
	confirmInput        textinput.Model

	// Enable operation state
	choosingEnableType bool            // true when showing enable type choice
	enteringPattern    bool            // true when entering a pattern
	patternInput       textinput.Model // input for pattern entry

	// Disable operation state
	choosingDisableType    bool            // true when showing disable type choice
	enteringDisablePattern bool            // true when entering a disable pattern
	disablePatternInput    textinput.Model // input for disable pattern entry

	// Per-scenario config editing state
	editingScenarioConfig     bool            // true while user is editing a config key
	editingConfigKeyIndex     int             // index into scenario.Config slice
	editingConfigScenarioName string          // name of the scenario being configured
	scenarioConfigInput       textinput.Model // input widget for the config value

	// Simple action confirmation state (for deploy, demo, cleanup, plan)
	pendingAction      string // action awaiting confirmation: "deploy", "plan", "demo", "cleanup", "cleanupAll", "deployWarning"
	pendingScenarioID  string // scenario ID for demo/cleanup actions

	// Cleanup queue state (for cleanup all)
	cleanupQueue       []string // scenario IDs to clean up sequentially
	cleanupQueueAction string   // action after queue drains: "" or "deploy"

	// Deploy warning state (for demo-active disabled scenarios)
	deployWarningIDs []string // scenario IDs being disabled with active demos

	// Credential validation state
	validatingCredentials bool   // true while checking AWS credentials
	validatingForAction   string // the action we're validating for
	validatingScenarioID  string // scenario ID for demo/cleanup during validation

	// Running command (for cancellation and streaming)
	runningCmd  *exec.Cmd
	cmdScanner  *bufio.Scanner
	cmdWaitDone chan error

	// Transient status bar message shown after clipboard copy
	copyToast string
}

// Message types for async operations
type scenariosLoadedMsg struct {
	scenarios []*scenarios.Scenario
	enabled   map[string]bool
	deployed  map[string]bool
	outputs   terraform.Outputs
}

type resourcesLoadedMsg struct {
	resources map[string][]string // module name -> ARNs
}

type credentialsValidatedMsg struct {
	valid   bool
	profile string
	err     error
}

type cmdOutputMsg struct {
	line string
}

type cmdDoneMsg struct {
	err error
}

type errMsg struct {
	err error
}

type interactiveDemoDoneMsg struct {
	err         error
	scenarioDir string // directory of the scenario that ran
	isCleanup   bool   // true when this is a cleanup run, not a demo run
}

type shellExitMsg struct {
	err error
}

type clearCopyToastMsg struct{}

// interactiveDemoCmd wraps a bash command for tea.Exec
type interactiveDemoCmd struct {
	cmd *exec.Cmd
}

func (c *interactiveDemoCmd) Run() error {
	return c.cmd.Run()
}

func (c *interactiveDemoCmd) SetStdin(r io.Reader) {
	c.cmd.Stdin = r
}

func (c *interactiveDemoCmd) SetStdout(w io.Writer) {
	c.cmd.Stdout = w
}

func (c *interactiveDemoCmd) SetStderr(w io.Writer) {
	c.cmd.Stderr = w
}

// NewModel creates a new TUI model
func NewModel(paths *repo.Paths, version string, updateNotice string) *Model {
	styles := DefaultStyles(lipgloss.HasDarkBackground())
	keys := DefaultKeyMap()

	// Filter input
	ti := textinput.New()
	ti.Placeholder = "Filter scenarios..."
	ti.CharLimit = 50

	// Confirm input for destroy operations
	ci := textinput.New()
	ci.Placeholder = "Type 'destroy' to confirm"
	ci.CharLimit = 10

	// Pattern input for enable operations
	pi := textinput.New()
	pi.Placeholder = "e.g., iam-*, lambda-001, one-hop/*"
	pi.CharLimit = 50

	// Pattern input for disable operations
	di := textinput.New()
	di.Placeholder = "e.g., iam-*, lambda-001, one-hop/*"
	di.CharLimit = 50

	// Input for per-scenario config editing
	sci := textinput.New()
	sci.Placeholder = "Enter value..."
	sci.CharLimit = 200

	infoPane := NewInfoPane(styles)
	infoPane.SetVersion(version)
	infoPane.SetUpdateNotice(updateNotice)

	m := &Model{
		paths:               paths,
		styles:              styles,
		keys:                keys,
		info:                infoPane,
		environment:         NewEnvironmentPane(styles),
		scenariosPane:       NewScenariosPane(styles),
		details:             NewDetailsPane(styles),
		actions:             NewActionsPane(styles),
		overlay:             NewOverlay(styles),
		filterInput:         ti,
		confirmInput:        ci,
		patternInput:        pi,
		disablePatternInput: di,
		scenarioConfigInput: sci,
		currentPane:         PaneScenarios,
		loading:             true,
	}

	return m
}

// Init initializes the model
func (m *Model) Init() tea.Cmd {
	return tea.Batch(
		tea.EnterAltScreen,
		m.loadScenarios,
	)
}

// loadScenarios loads scenarios from the filesystem
func (m *Model) loadScenarios() tea.Msg {
	// Load config from canonical location
	cfg, err := config.Load()
	if err != nil {
		return errMsg{err}
	}

	// Create terraform components
	runner := terraform.NewRunner(m.paths.BinPath, m.paths.TerraformDir)

	// Discover scenarios
	discovery := scenarios.NewDiscovery(m.paths.ScenariosPath()).WithIncludeBeta(cfg.IncludeBeta)
	allScenarios, err := discovery.DiscoverAll()
	if err != nil {
		return errMsg{err}
	}

	// Get enabled status from config (single source of truth)
	enabled := cfg.Active().GetEnabledScenarioVars()

	// Get deployed status
	deployed := make(map[string]bool)
	var outputs terraform.Outputs

	if runner.IsInitialized() {
		// Run state list and output json concurrently
		var deployedModules map[string]bool
		var outputJSON string
		var outputErr error

		done := make(chan struct{}, 2)

		go func() {
			deployedModules = runner.GetDeployedModules()
			done <- struct{}{}
		}()

		go func() {
			outputJSON, outputErr = runner.OutputJSON()
			done <- struct{}{}
		}()

		// Wait for both to complete
		<-done
		<-done

		for _, s := range allScenarios {
			outputName := strings.TrimPrefix(s.Terraform.VariableName, "enable_")
			if deployedModules[outputName] {
				deployed[s.Terraform.VariableName] = true
			}
		}

		if outputErr == nil && outputJSON != "" {
			outputs, _ = terraform.ParseOutputs(outputJSON)
		}
	}

	return scenariosLoadedMsg{
		scenarios: allScenarios,
		enabled:   enabled,
		deployed:  deployed,
		outputs:   outputs,
	}
}

// loadResources loads resource ARNs in the background
func (m *Model) loadResources() tea.Msg {
	if m.tfRunner == nil || !m.tfRunner.IsInitialized() {
		return resourcesLoadedMsg{resources: nil}
	}

	resources, _ := m.tfRunner.GetAllModuleResources()
	return resourcesLoadedMsg{resources: resources}
}

// Update handles messages and updates the model
func (m *Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.termWidth = msg.Width
		m.termHeight = msg.Height
		m.updateLayout()
		m.ready = true
		return m, nil

	case scenariosLoadedMsg:
		cfg, _ := config.Load()
		m.config = cfg
		m.tfvars = terraform.NewTFVars(m.paths.TFVarsPath)
		m.tfRunner = terraform.NewRunner(m.paths.BinPath, m.paths.TerraformDir)
		m.discovery = scenarios.NewDiscovery(m.paths.ScenariosPath()).WithIncludeBeta(cfg.IncludeBeta)
		m.allScenarios = msg.scenarios

		// Recalculate layout now that config is available
		m.updateLayout()

		// Update environment pane
		m.environment.SetConfig(cfg)

		// Load enabled states for environments
		var attackerEnabled bool
		if m.tfvars != nil {
			var prodEnabled, devEnabled, opsEnabled bool
			prodEnabled, devEnabled, opsEnabled, attackerEnabled, _ = m.tfvars.GetEnabledEnvironments()
			m.environment.SetEnabledStatus(prodEnabled, devEnabled, opsEnabled, attackerEnabled)
		}

		// Load deployed states for environments
		if m.tfRunner != nil && m.tfRunner.IsInitialized() {
			deployed := m.tfRunner.GetDeployedModules()
			// Attacker module has no resources in state (it's a pass-through),
			// so treat it as deployed when enabled and terraform is initialized
			attackerDeployed := deployed["attacker_environment"] || attackerEnabled
			m.environment.SetDeploymentStatus(
				deployed["prod_environment"],
				deployed["dev_environment"],
				deployed["ops_environment"],
				attackerDeployed,
			)
		}

		// Build scenario items
		var items []ScenarioItem
		for _, s := range msg.scenarios {
			items = append(items, ScenarioItem{
				Scenario:   s,
				Enabled:    msg.enabled[s.Terraform.VariableName],
				Deployed:   msg.deployed[s.Terraform.VariableName],
				DemoActive: s.HasDemoActive(),
			})
		}
		m.scenariosPane.SetScenarios(items)

		// Update info pane
		m.info.SetConfig(cfg)
		m.info.SetWorkspace(cfg.ActiveName(), cfg.WorkspaceCount())
		m.info.SetTotalScenarios(len(msg.scenarios))
		if m.tfRunner != nil {
			m.info.SetTerraformInitialized(m.tfRunner.IsInitialized())
		}

		// Calculate deployment counts
		enabledCount := 0
		deployedCount := 0
		for _, s := range msg.scenarios {
			if msg.enabled[s.Terraform.VariableName] {
				enabledCount++
			}
			if msg.deployed[s.Terraform.VariableName] {
				deployedCount++
			}
		}
		m.info.SetDeploymentCounts(enabledCount, deployedCount)

		// Calculate running cost of deployed scenarios
		m.updateRunningCost()

		// Calculate demo-active count
		m.updateDemoActiveCount()

		// Cache outputs, then update details for initially selected scenario
		m.cachedOutputs = msg.outputs
		m.cachedResources = nil // Will be populated async
		m.updateDetails()

		// Set derived account IDs from terraform outputs
		if msg.outputs != nil {
			prodID, devID, opsID, attackerID := msg.outputs.GetAccountIDs()
			m.environment.SetDerivedAccountIDs(prodID, devID, opsID, attackerID)
		}

		// Done loading (UI is ready, resources will load in background)
		m.loading = false
		m.scenariosPane.SetLoading(false)
		m.environment.SetLoading(false)

		// Continue cleanup queue if active
		if len(m.cleanupQueue) > 0 || m.cleanupQueueAction != "" {
			return m, m.executeCleanupQueue()
		}

		// Start async resource loading if terraform is initialized
		if m.tfRunner != nil && m.tfRunner.IsInitialized() {
			return m, m.loadResources
		}
		return m, nil

	case resourcesLoadedMsg:
		// Resources loaded in background - update cache and refresh details
		m.cachedResources = msg.resources
		m.updateDetails()
		return m, nil

	case credentialsValidatedMsg:
		m.validatingCredentials = false
		if !msg.valid {
			// Show error and reset state
			if msg.profile == "" {
				m.overlay.Show(OverlayError, "AWS Credentials", "No AWS profile configured.\n\nRun 'plabs init' to configure.")
			} else {
				m.overlay.Show(OverlayError, "AWS Credentials",
					fmt.Sprintf("AWS SSO session expired or invalid.\n\nProfile: %s\n\nRun this command to authenticate:\n\n  aws sso login --profile %s\n\nThen try again.", msg.profile, msg.profile))
			}
			m.validatingForAction = ""
			m.validatingScenarioID = ""
			return m, nil
		}
		// Credentials valid - proceed with the action
		action := m.validatingForAction
		m.validatingForAction = ""
		scenarioID := m.validatingScenarioID
		m.validatingScenarioID = ""
		switch action {
		case "deploy":
			return m, m.executeDeploy()
		case "plan":
			return m, m.executePlan()
		case "demo":
			return m, m.executeDemo(scenarioID)
		case "cleanup":
			return m, m.executeCleanup(scenarioID, false)
		case "cleanupAll":
			return m, m.executeCleanupQueue()
		}
		return m, nil

	case cmdOutputMsg:
		// Append output line to overlay (skip empty lines from polling)
		if msg.line != "" {
			m.overlay.AppendContent(msg.line)
		}
		// Continue reading more output
		return m, func() tea.Msg { return m.readNextLine() }

	case cmdDoneMsg:
		// Command finished
		m.runningCmd = nil
		m.cmdScanner = nil
		m.cmdWaitDone = nil
		m.overlay.SetComplete()
		if msg.err != nil {
			m.overlay.AppendContent(fmt.Sprintf("\n[Error: %v]", msg.err))
		}
		// Ensure the done message is visible
		m.overlay.ScrollToBottom()
		// Reload scenarios to refresh deployment state
		return m, m.loadScenarios

	case interactiveDemoDoneMsg:
		if msg.scenarioDir != "" {
			markerPath := filepath.Join(msg.scenarioDir, ".demo_active")
			if msg.isCleanup {
				// Cleanup completed: remove the demo-active marker (best effort)
				_ = os.Remove(markerPath)
			} else if msg.err == nil {
				// Demo completed successfully: create the marker so the TUI shows the
				// "demos active" warning for scripts that don't do their own touch.
				_ = os.WriteFile(markerPath, []byte{}, 0644)
			}
		}
		// Reload scenarios to refresh deployment state
		return m, m.loadScenarios

	case shellExitMsg:
		if msg.err != nil {
			m.overlay.Show(OverlayError, "Shell Error", msg.err.Error())
		}
		return m, nil

	case clearCopyToastMsg:
		m.copyToast = ""
		return m, nil

	case errMsg:
		m.err = msg.err
		return m, nil

	case profileWizardMsg:
		if msg.err != nil {
			m.overlay.Show(OverlayError, "Profile Change", fmt.Sprintf("Error: %v", msg.err))
			return m, nil
		}

		// Validate and save the profile change
		if err := m.validateAndSetProfile(msg.envName, msg.newProfile); err != nil {
			m.overlay.Show(OverlayError, "Profile Change", err.Error())
			return m, nil
		}

		// Success - reload to refresh state
		return m, m.loadScenarios

	case budgetWizardMsg:
		if msg.err != nil {
			m.overlay.Show(OverlayError, "Budget Configuration", fmt.Sprintf("Error: %v", msg.err))
			return m, nil
		}

		// Apply budget changes
		if msg.result != nil {
			m.config.Active().Budget.Enabled = msg.result.Enabled
			m.config.Active().Budget.Email = msg.result.Email
			m.config.Active().Budget.LimitUSD = msg.result.LimitUSD

			// Save config
			if err := m.config.Save(); err != nil {
				m.overlay.Show(OverlayError, "Budget Configuration", fmt.Sprintf("Failed to save config: %v", err))
				return m, nil
			}

			// Update tfvars
			if err := m.config.Active().SyncTFVars(m.paths.TerraformDir); err != nil {
				m.overlay.Show(OverlayError, "Budget Configuration", fmt.Sprintf("Failed to update tfvars: %v", err))
				return m, nil
			}

			// Show success message
			var statusMsg string
			if msg.result.Enabled {
				statusMsg = fmt.Sprintf("Budget alerts enabled!\nEmail: %s\nLimit: $%d/month", msg.result.Email, msg.result.LimitUSD)
			} else {
				statusMsg = "Budget alerts disabled"
			}
			m.overlay.Show(OverlayInfo, "Budget Configuration", statusMsg+"\n\nRun 'deploy' to apply changes to AWS.")
		}
		return m, nil

	case tea.KeyMsg:
		return m.handleKeyPress(msg)
	}

	// Update filter input if filtering
	if m.filtering {
		var cmd tea.Cmd
		m.filterInput, cmd = m.filterInput.Update(msg)
		cmds = append(cmds, cmd)
	}

	return m, tea.Batch(cmds...)
}

func (m *Model) handleKeyPress(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Handle overlay
	if m.overlay.IsVisible() {
		// Special handling for settings overlay
		if m.overlay.Type() == OverlayConfig {
			return m.handleSettingsKeys(msg)
		}

		// Standard overlay handling
		if key.Matches(msg, m.keys.Esc) {
			// If command is running, kill it
			if m.runningCmd != nil && m.runningCmd.Process != nil {
				_ = m.runningCmd.Process.Kill()
				m.runningCmd = nil
			}
			m.overlay.Hide()
			return m, nil
		}
		// Enter also closes overlay when command is complete (not running)
		if msg.String() == "enter" && m.runningCmd == nil {
			m.overlay.Hide()
			return m, nil
		}
		// Allow scrolling in overlay
		if key.Matches(msg, m.keys.Down) {
			m.overlay.ScrollDown()
			return m, nil
		}
		if key.Matches(msg, m.keys.Up) {
			m.overlay.ScrollUp()
			return m, nil
		}
		// Block other keys while overlay is visible
		return m, nil
	}

	// Handle destroy type choice
	if m.choosingDestroyType {
		switch msg.String() {
		case "s", "S", "1":
			// Validate scenarios exist
			if len(m.config.Active().Scenarios.Enabled) == 0 {
				m.choosingDestroyType = false
				m.overlay.Show(OverlayError, "Destroy Scenarios", "No scenarios are currently enabled.")
				return m, nil
			}
			m.choosingDestroyType = false
			m.destroyType = "scenarios"
			m.confirmingDestroy = true
			m.confirmInput.SetValue("")
			m.confirmInput.Focus()
			return m, textinput.Blink
		case "a", "A", "2":
			// Validate resources exist
			if m.tfRunner == nil || !m.tfRunner.IsInitialized() {
				m.choosingDestroyType = false
				m.overlay.Show(OverlayError, "Destroy All", "Terraform is not initialized. Nothing to destroy.")
				return m, nil
			}
			resources, err := m.tfRunner.StateList()
			if err != nil || len(resources) == 0 {
				m.choosingDestroyType = false
				m.overlay.Show(OverlayError, "Destroy All", "No resources found. Nothing to destroy.")
				return m, nil
			}
			m.choosingDestroyType = false
			m.destroyType = "all"
			m.confirmingDestroy = true
			m.confirmInput.SetValue("")
			m.confirmInput.Focus()
			return m, textinput.Blink
		case "esc", "q":
			m.choosingDestroyType = false
			return m, nil
		}
		// Ignore other keys while choosing
		return m, nil
	}

	// Handle destroy confirmation mode
	if m.confirmingDestroy {
		switch {
		case key.Matches(msg, m.keys.Esc):
			m.confirmingDestroy = false
			m.confirmInput.Blur()
			m.confirmInput.SetValue("")
			m.destroyType = ""
			return m, nil
		case msg.Type == tea.KeyEnter:
			if m.confirmInput.Value() == "destroy" {
				m.confirmingDestroy = false
				m.confirmInput.Blur()
				m.confirmInput.SetValue("")
				destroyType := m.destroyType
				m.destroyType = ""
				if destroyType == "scenarios" {
					return m, m.executeDestroyScenarios()
				} else if destroyType == "all" {
					return m, m.executeDestroyAll()
				}
			}
			return m, nil
		default:
			var cmd tea.Cmd
			m.confirmInput, cmd = m.confirmInput.Update(msg)
			return m, cmd
		}
	}

	// Handle deploy warning (demo-active scenarios being disabled)
	if m.pendingAction == "deployWarning" {
		switch {
		case key.Matches(msg, m.keys.Esc):
			m.pendingAction = ""
			m.deployWarningIDs = nil
			return m, nil
		case msg.String() == "c" || msg.String() == "C":
			// Cleanup first, then deploy
			m.cleanupQueue = m.deployWarningIDs
			m.cleanupQueueAction = "deploy"
			m.deployWarningIDs = nil
			m.pendingAction = ""
			// Start credential validation for cleanupAll
			m.validatingForAction = "cleanupAll"
			m.validatingCredentials = true
			return m, m.validateCredentialsAsync()
		case msg.Type == tea.KeyEnter:
			// Deploy anyway without cleanup
			m.deployWarningIDs = nil
			m.pendingAction = ""
			m.validatingForAction = "deploy"
			m.validatingCredentials = true
			return m, m.validateCredentialsAsync()
		}
		// Ignore other keys while warning
		return m, nil
	}

	// Handle simple action confirmation (deploy, plan, demo, cleanup, cleanupAll)
	if m.pendingAction != "" {
		switch {
		case key.Matches(msg, m.keys.Esc):
			m.pendingAction = ""
			m.pendingScenarioID = ""
			return m, nil
		case msg.Type == tea.KeyEnter:
			// Start async credential validation
			m.validatingForAction = m.pendingAction
			m.validatingScenarioID = m.pendingScenarioID
			m.validatingCredentials = true
			m.pendingAction = ""
			m.pendingScenarioID = ""
			return m, m.validateCredentialsAsync()
		}
		// Ignore other keys while confirming
		return m, nil
	}

	// Handle credential validation in progress (ignore all keys except Esc)
	if m.validatingCredentials {
		if key.Matches(msg, m.keys.Esc) {
			m.validatingCredentials = false
			m.validatingForAction = ""
			m.validatingScenarioID = ""
		}
		return m, nil
	}

	// Handle enable type choice
	if m.choosingEnableType {
		switch msg.String() {
		case "a", "A", "1":
			m.choosingEnableType = false
			return m, m.executeEnableAll()
		case "p", "P", "2":
			m.choosingEnableType = false
			m.enteringPattern = true
			m.patternInput.SetValue("")
			m.patternInput.Focus()
			return m, textinput.Blink
		case "esc", "q":
			m.choosingEnableType = false
			return m, nil
		}
		// Ignore other keys while choosing
		return m, nil
	}

	// Handle enable pattern entry
	if m.enteringPattern {
		switch {
		case key.Matches(msg, m.keys.Esc):
			m.enteringPattern = false
			m.patternInput.Blur()
			m.patternInput.SetValue("")
			return m, nil
		case msg.Type == tea.KeyEnter:
			pattern := m.patternInput.Value()
			m.enteringPattern = false
			m.patternInput.Blur()
			m.patternInput.SetValue("")
			if pattern != "" {
				return m, m.executeEnablePattern(pattern)
			}
			return m, nil
		default:
			var cmd tea.Cmd
			m.patternInput, cmd = m.patternInput.Update(msg)
			return m, cmd
		}
	}

	// Handle disable type choice
	if m.choosingDisableType {
		switch msg.String() {
		case "a", "A", "1":
			m.choosingDisableType = false
			return m, m.executeDisableAll()
		case "p", "P", "2":
			m.choosingDisableType = false
			m.enteringDisablePattern = true
			m.disablePatternInput.SetValue("")
			m.disablePatternInput.Focus()
			return m, textinput.Blink
		case "esc", "q":
			m.choosingDisableType = false
			return m, nil
		}
		// Ignore other keys while choosing
		return m, nil
	}

	// Handle disable pattern entry
	if m.enteringDisablePattern {
		switch {
		case key.Matches(msg, m.keys.Esc):
			m.enteringDisablePattern = false
			m.disablePatternInput.Blur()
			m.disablePatternInput.SetValue("")
			return m, nil
		case msg.Type == tea.KeyEnter:
			pattern := m.disablePatternInput.Value()
			m.enteringDisablePattern = false
			m.disablePatternInput.Blur()
			m.disablePatternInput.SetValue("")
			if pattern != "" {
				return m, m.executeDisablePattern(pattern)
			}
			return m, nil
		default:
			var cmd tea.Cmd
			m.disablePatternInput, cmd = m.disablePatternInput.Update(msg)
			return m, cmd
		}
	}

	// Handle per-scenario config editing
	if m.editingScenarioConfig {
		switch {
		case key.Matches(msg, m.keys.Esc):
			m.editingScenarioConfig = false
			m.scenarioConfigInput.Blur()
			return m, nil
		case msg.Type == tea.KeyEnter:
			return m.saveScenarioConfigValue()
		default:
			var cmd tea.Cmd
			m.scenarioConfigInput, cmd = m.scenarioConfigInput.Update(msg)
			return m, cmd
		}
	}

	// Handle filter mode
	if m.filtering {
		switch {
		case key.Matches(msg, m.keys.Esc):
			m.filtering = false
			m.filterInput.Blur()
			m.filterInput.SetValue("")
			m.scenariosPane.SetFilter("")
			return m, nil
		case msg.Type == tea.KeyEnter:
			m.filtering = false
			m.filterInput.Blur()
			m.scenariosPane.SetFilter(m.filterInput.Value())
			return m, nil
		default:
			var cmd tea.Cmd
			m.filterInput, cmd = m.filterInput.Update(msg)
			// Live filter as typing
			m.scenariosPane.SetFilter(m.filterInput.Value())
			return m, cmd
		}
	}

	// Global keys
	switch {
	case key.Matches(msg, m.keys.Quit):
		return m, tea.Quit

	case key.Matches(msg, m.keys.Help):
		if m.overlay.IsVisible() {
			m.overlay.Hide()
		} else {
			m.overlay.Show(OverlayHelp, "Help", m.overlay.RenderHelpOverlay())
		}
		return m, nil

	case key.Matches(msg, m.keys.Filter):
		m.filtering = true
		m.filterInput.Focus()
		return m, textinput.Blink

	case key.Matches(msg, m.keys.ToggleEnabledOnly):
		m.scenariosPane.ToggleShowOnlyEnabled()
		m.actions.SetShowOnlyEnabled(m.scenariosPane.IsShowingOnlyEnabled())
		m.updateDetailsForSelected()
		return m, nil

	case key.Matches(msg, m.keys.ToggleDemoActive):
		m.scenariosPane.ToggleShowOnlyDemoActive()
		m.actions.SetShowOnlyDemoActive(m.scenariosPane.IsShowingOnlyDemoActive())
		m.updateDetailsForSelected()
		return m, nil

	case key.Matches(msg, m.keys.ToggleCosts):
		m.scenariosPane.ToggleShowCosts()
		return m, nil

	case key.Matches(msg, m.keys.ToggleCollapseAll):
		m.scenariosPane.ToggleCollapseAll()
		return m, nil

	case key.Matches(msg, m.keys.Tab):
		m.nextPane()
		return m, nil

	case key.Matches(msg, m.keys.ShiftTab):
		m.prevPane()
		return m, nil

	case key.Matches(msg, m.keys.Deploy):
		return m, m.runDeploy()

	case key.Matches(msg, m.keys.Plan):
		return m, m.runPlan()

	case key.Matches(msg, m.keys.RunDemo):
		return m, m.runDemo()

	case key.Matches(msg, m.keys.Cleanup):
		return m, m.runCleanup()

	case key.Matches(msg, m.keys.CleanupAll):
		return m, m.runCleanupAll()

	case key.Matches(msg, m.keys.Destroy):
		return m, m.showDestroyTypeChoice()

	case key.Matches(msg, m.keys.Enable):
		// In the details pane, 'e' edits per-scenario config when the scenario has config keys
		if m.currentPane == PaneDetails {
			if selected := m.scenariosPane.Selected(); selected != nil && selected.Scenario.HasConfig() {
				return m.startEditScenarioConfig(selected.Scenario)
			}
		}
		return m, m.showEnableTypeChoice()

	case key.Matches(msg, m.keys.Disable):
		return m, m.showDisableTypeChoice()

	case key.Matches(msg, m.keys.Config):
		m.showConfig()
		return m, nil

	case key.Matches(msg, m.keys.CopyCredentials):
		if m.details.HasCreds() {
			return m, m.copyCredentials()
		}

	case key.Matches(msg, m.keys.CopyCredentialsProfile):
		if m.details.HasCreds() {
			return m, m.copyCredentialsProfile()
		}

	case key.Matches(msg, m.keys.SpawnShell):
		if m.details.HasCreds() {
			return m.spawnShell()
		}
	}

	// Pane-specific keys
	switch m.currentPane {
	case PaneEnvironment:
		switch {
		case key.Matches(msg, m.keys.Up):
			m.environment.MoveUp()
			m.updateEnvironmentActions()
		case key.Matches(msg, m.keys.Down):
			m.environment.MoveDown()
			m.updateEnvironmentActions()
		case key.Matches(msg, m.keys.Toggle):
			return m, m.toggleEnvironment()
		}

	case PaneScenarios:
		switch {
		case key.Matches(msg, m.keys.Up):
			m.scenariosPane.MoveUp()
			m.updateDetailsForSelected()
		case key.Matches(msg, m.keys.Down):
			m.scenariosPane.MoveDown()
			m.updateDetailsForSelected()
		case key.Matches(msg, m.keys.Left):
			m.scenariosPane.Collapse()
		case key.Matches(msg, m.keys.Right):
			m.scenariosPane.Expand()
		case key.Matches(msg, m.keys.PageUp):
			m.scenariosPane.PageUp()
			m.updateDetailsForSelected()
		case key.Matches(msg, m.keys.PageDown):
			m.scenariosPane.PageDown()
			m.updateDetailsForSelected()
		case key.Matches(msg, m.keys.Home):
			m.scenariosPane.GoToFirst()
			m.updateDetailsForSelected()
		case key.Matches(msg, m.keys.End):
			m.scenariosPane.GoToLast()
			m.updateDetailsForSelected()
		case key.Matches(msg, m.keys.Toggle):
			return m, m.toggleSelected()
		}

	case PaneDetails:
		switch {
		case key.Matches(msg, m.keys.Up):
			m.details.ScrollUp()
		case key.Matches(msg, m.keys.Down):
			m.details.ScrollDown()
		case key.Matches(msg, m.keys.PageUp):
			m.details.PageUp()
		case key.Matches(msg, m.keys.PageDown):
			m.details.PageDown()
		case key.Matches(msg, m.keys.Home):
			m.details.GoToTop()
		case key.Matches(msg, m.keys.End):
			m.details.GoToBottom()
		}
	}

	return m, nil
}

// toggleEnvironment toggles the enabled state of the selected environment
// Note: Environment toggling is not supported via config - environments are
// enabled/disabled based on whether a profile is configured.
func (m *Model) toggleEnvironment() tea.Cmd {
	// Environment toggling through tfvars is deprecated.
	// Environments are now enabled based on profile configuration.
	// Show a message explaining this.
	m.overlay.Show(OverlayError, "Environment Toggle",
		"Environment enable/disable is now managed through profile configuration.\n\n"+
			"Use 'plabs config set <env>-profile <profile>' to configure an environment,\n"+
			"or press 's' to open settings and change profiles.")
	return nil
}

// updateEnvironmentActions syncs the actions pane with the selected environment
func (m *Model) updateEnvironmentActions() {
	env := m.environment.Selected()
	if env != nil {
		m.actions.SetEnvironment(env.Enabled, env.Deployed)
	}
}

func (m *Model) nextPane() {
	m.currentPane = (m.currentPane + 1) % 3
	m.updatePaneFocus()
}

func (m *Model) prevPane() {
	m.currentPane = (m.currentPane + 2) % 3
	m.updatePaneFocus()
}

func (m *Model) updatePaneFocus() {
	m.environment.SetFocused(m.currentPane == PaneEnvironment)
	m.scenariosPane.SetFocused(m.currentPane == PaneScenarios)
	m.details.SetFocused(m.currentPane == PaneDetails)
	m.actions.SetFocusedPane(m.currentPane)

	// Update actions pane with environment state when environment pane is focused
	if m.currentPane == PaneEnvironment {
		env := m.environment.Selected()
		if env != nil {
			m.actions.SetEnvironment(env.Enabled, env.Deployed)
		}
	}
}

func (m *Model) updateDetails() {
	selected := m.scenariosPane.Selected()
	if selected == nil {
		m.details.SetScenario(nil, false, false, false)
		m.details.ClearCredentials()
		m.details.ClearResources()
		m.actions.SetScenario(nil, false, false, false)
		return
	}

	m.details.SetScenario(selected.Scenario, selected.Enabled, selected.Deployed, selected.DemoActive)
	m.actions.SetScenario(selected.Scenario, selected.Enabled, selected.Deployed, selected.DemoActive)

	// Pass per-scenario config values to the details pane.
	// Re-read config from disk to pick up changes made via the CLI while the TUI is open.
	if selected.Scenario.HasConfig() {
		if !m.editingScenarioConfig {
			if freshCfg, err := config.Load(); err == nil {
				m.config = freshCfg
			}
		}
		if m.config != nil {
			m.details.SetConfigValues(m.config.Active().GetAllScenarioConfigs(selected.Scenario.Name))
		} else {
			m.details.SetConfigValues(nil)
		}
	} else {
		m.details.SetConfigValues(nil)
	}

	// Get credentials if deployed (using cached outputs)
	if selected.Deployed && m.cachedOutputs != nil {
		outputName := strings.TrimPrefix(selected.Scenario.Terraform.VariableName, "enable_")
		creds, _ := m.cachedOutputs.GetStartingCredentials(outputName)
		m.details.SetCredentials(creds)
	} else {
		m.details.ClearCredentials()
	}

	// Get resources if deployed (using cached resources)
	if selected.Deployed && m.cachedResources != nil {
		outputName := strings.TrimPrefix(selected.Scenario.Terraform.VariableName, "enable_")
		resources := m.cachedResources[outputName]
		m.details.SetResources(resources)
	} else {
		m.details.ClearResources()
	}

	m.actions.SetHasCreds(m.details.HasCreds())
}

func (m *Model) updateDetailsForSelected() {
	// Use cached outputs - no need to re-fetch on every navigation
	m.updateDetails()
}

func (m *Model) copyCredentials() tea.Cmd {
	creds := m.details.Creds()
	region := ""
	if m.config != nil {
		region = m.config.Active().AWS.Prod.Region
	}

	var lines []string
	lines = append(lines, "export AWS_ACCESS_KEY_ID="+creds.AccessKeyID)
	lines = append(lines, "export AWS_SECRET_ACCESS_KEY="+creds.SecretAccessKey)
	if region != "" {
		lines = append(lines, "export AWS_DEFAULT_REGION="+region)
	}
	if creds.SessionToken != "" {
		lines = append(lines, "export AWS_SESSION_TOKEN="+creds.SessionToken)
	}

	if err := clipboard.WriteAll(strings.Join(lines, "\n")); err != nil {
		m.overlay.Show(OverlayError, "Copy Failed", err.Error())
		return nil
	}

	m.copyToast = "Credentials copied as environment variables"
	return tea.Tick(2*time.Second, func(_ time.Time) tea.Msg {
		return clearCopyToastMsg{}
	})
}

func (m *Model) copyCredentialsProfile() tea.Cmd {
	creds := m.details.Creds()
	profileName := ""
	if selected := m.scenariosPane.Selected(); selected != nil {
		profileName = selected.Scenario.UniqueID()
	}
	if profileName == "" {
		profileName = "pathfinding-lab"
	}

	var lines []string
	lines = append(lines, "["+profileName+"]")
	lines = append(lines, "aws_access_key_id = "+creds.AccessKeyID)
	lines = append(lines, "aws_secret_access_key = "+creds.SecretAccessKey)
	if creds.SessionToken != "" {
		lines = append(lines, "aws_session_token = "+creds.SessionToken)
	}
	if m.config != nil && m.config.Active().AWS.Prod.Region != "" {
		lines = append(lines, "region = "+m.config.Active().AWS.Prod.Region)
	}

	if err := clipboard.WriteAll(strings.Join(lines, "\n")); err != nil {
		m.overlay.Show(OverlayError, "Copy Failed", err.Error())
		return nil
	}

	m.copyToast = "Credentials copied as ~/.aws/credentials block"
	return tea.Tick(2*time.Second, func(_ time.Time) tea.Msg {
		return clearCopyToastMsg{}
	})
}

func (m *Model) spawnShell() (tea.Model, tea.Cmd) {
	creds := m.details.Creds()
	shell := os.Getenv("SHELL")
	if shell == "" {
		shell = "/bin/bash"
	}

	cmd := exec.Command(shell)
	cmd.Env = append(os.Environ(),
		"AWS_ACCESS_KEY_ID="+creds.AccessKeyID,
		"AWS_SECRET_ACCESS_KEY="+creds.SecretAccessKey,
	)
	if m.config != nil && m.config.Active().AWS.Prod.Region != "" {
		cmd.Env = append(cmd.Env, "AWS_DEFAULT_REGION="+m.config.Active().AWS.Prod.Region)
	}
	if creds.SessionToken != "" {
		cmd.Env = append(cmd.Env, "AWS_SESSION_TOKEN="+creds.SessionToken)
	}

	return m, tea.ExecProcess(cmd, func(err error) tea.Msg {
		return shellExitMsg{err: err}
	})
}

func (m *Model) toggleSelected() tea.Cmd {
	// Check BEFORE toggling: if about to enable, validate required config keys are set
	current := m.scenariosPane.Selected()
	if current != nil && m.config != nil && !current.Enabled && current.Scenario.HasConfig() {
		var missingKeys []string
		for _, cfgKey := range current.Scenario.Config {
			if cfgKey.Required {
				val, _ := m.config.Active().GetScenarioConfig(current.Scenario.Name, cfgKey.Key)
				if val == "" {
					missingKeys = append(missingKeys, cfgKey.Key)
				}
			}
		}
		if len(missingKeys) > 0 {
			m.overlay.Show(OverlayError, "Config Required",
				fmt.Sprintf("Cannot enable %s\n\nMissing required config:\n  %s\n\nSwitch to the Details pane (Tab) and press 'e' to set these values.",
					current.Scenario.Name, strings.Join(missingKeys, "\n  ")))
			return nil
		}
	}

	scenario := m.scenariosPane.Toggle()
	if scenario == nil || m.config == nil {
		return nil
	}

	// Get the new enabled state
	selected := m.scenariosPane.Selected()
	if selected == nil {
		return nil
	}

	// Update config (single source of truth)
	if selected.Enabled {
		m.config.Active().EnableScenario(scenario.Terraform.VariableName)
	} else {
		m.config.Active().DisableScenario(scenario.Terraform.VariableName)
	}

	// Save config and sync tfvars
	if err := m.config.Save(); err != nil {
		m.err = err
		return nil
	}

	if err := m.config.Active().SyncTFVars(m.paths.TerraformDir); err != nil {
		m.err = err
	}

	// Update info pane counts
	m.updateInfoCounts()

	return nil
}

// updateInfoCounts updates the enabled/deployed counts in the info pane
func (m *Model) updateInfoCounts() {
	items := m.scenariosPane.GetItems()
	enabledCount := 0
	deployedCount := 0
	for _, item := range items {
		if item.Enabled {
			enabledCount++
		}
		if item.Deployed {
			deployedCount++
		}
	}
	m.info.SetDeploymentCounts(enabledCount, deployedCount)
	m.updateDemoActiveCount()
}

func (m *Model) runDeploy() tea.Cmd {
	// Block deploy if any enabled scenario is missing required config
	if missing := m.getMissingRequiredConfigs(); len(missing) > 0 {
		var sb strings.Builder
		sb.WriteString("Cannot deploy — required configuration is missing:\n\n")
		for _, msg := range missing {
			sb.WriteString("  " + msg + "\n")
		}
		sb.WriteString("\nSwitch to the Details pane (Tab) and press 'e' to set config values.")
		m.overlay.Show(OverlayError, "Config Required", sb.String())
		return nil
	}

	// Check for disabled scenarios with active demos
	warningIDs := m.scenariosPane.GetDisabledDemoActiveScenarioIDs()
	if len(warningIDs) > 0 {
		m.deployWarningIDs = warningIDs
		m.pendingAction = "deployWarning"
		return nil
	}

	// Show confirmation prompt
	m.pendingAction = "deploy"
	return nil
}

func (m *Model) executeDeploy() tea.Cmd {
	// Re-read config from disk and sync tfvars before running terraform.
	// This picks up any changes made via the CLI while the TUI was open,
	// mirroring what 'plabs apply' does.
	if freshCfg, err := config.Load(); err == nil {
		m.config = freshCfg
	}
	if m.config != nil {
		// Detect which service-linked roles already exist so Terraform doesn't
		// try to create duplicates (mirrors CLI deploy behavior).
		//
		// Rule: create=true UNLESS the SLR exists in AWS AND is NOT in Terraform state.
		// If Terraform already owns the SLR in state, keep create=true — flipping it to
		// false would make count=0 and cause Terraform to destroy the SLR.
		if slrStatus, err := aws.DetectExistingServiceLinkedRoles(m.config.Active().AWS.Prod.Profile); err == nil {
			inState := &aws.ServiceLinkedRoleStatus{}
			if m.tfRunner != nil && m.tfRunner.IsInitialized() {
				if stateResources, stateErr := m.tfRunner.StateList(); stateErr == nil {
					inState = aws.SLRInState(stateResources)
				}
			}
			m.config.Active().SLRFlags = &config.ServiceLinkedRoleFlags{
				CreateAutoScaling: !slrStatus.AutoScalingExists || inState.AutoScalingExists,
				CreateSpot:        !slrStatus.SpotExists || inState.SpotExists,
				CreateAppRunner:   !slrStatus.AppRunnerExists || inState.AppRunnerExists,
			}
		}
		_ = m.config.Active().SyncTFVars(m.paths.TerraformDir)
	}
	m.overlay.ShowRunning(OverlayTerraform, "Apply")
	cmd := exec.Command("bash", "-c", fmt.Sprintf("cd %s && terraform init && terraform apply -auto-approve", m.paths.TerraformDir))
	cmd.Env = m.buildTerraformEnv()
	return m.runCommandStreaming(cmd)
}

func (m *Model) runPlan() tea.Cmd {
	// Show confirmation prompt
	m.pendingAction = "plan"
	return nil
}

func (m *Model) executePlan() tea.Cmd {
	// Re-read config, detect SLRs, and sync tfvars — same as executeDeploy.
	if freshCfg, err := config.Load(); err == nil {
		m.config = freshCfg
	}
	if m.config != nil {
		if slrStatus, err := aws.DetectExistingServiceLinkedRoles(m.config.Active().AWS.Prod.Profile); err == nil {
			inState := &aws.ServiceLinkedRoleStatus{}
			if m.tfRunner != nil && m.tfRunner.IsInitialized() {
				if stateResources, stateErr := m.tfRunner.StateList(); stateErr == nil {
					inState = aws.SLRInState(stateResources)
				}
			}
			m.config.Active().SLRFlags = &config.ServiceLinkedRoleFlags{
				CreateAutoScaling: !slrStatus.AutoScalingExists || inState.AutoScalingExists,
				CreateSpot:        !slrStatus.SpotExists || inState.SpotExists,
				CreateAppRunner:   !slrStatus.AppRunnerExists || inState.AppRunnerExists,
			}
		}
		_ = m.config.Active().SyncTFVars(m.paths.TerraformDir)
	}
	m.overlay.ShowRunning(OverlayTerraform, "Plan")
	cmd := exec.Command("bash", "-c", fmt.Sprintf("cd %s && terraform init && terraform plan", m.paths.TerraformDir))
	cmd.Env = m.buildTerraformEnv()
	return m.runCommandStreaming(cmd)
}

func (m *Model) runDemo() tea.Cmd {
	selected := m.scenariosPane.Selected()
	if selected == nil || !selected.Deployed {
		m.overlay.Show(OverlayError, "Run Demo", "Scenario must be deployed first.\n\nUse [a] to apply enabled scenarios.")
		return nil
	}

	if !selected.Scenario.HasDemo() {
		m.overlay.Show(OverlayError, "Run Demo", "No demo script available for this scenario.")
		return nil
	}

	// Show confirmation prompt
	m.pendingAction = "demo"
	m.pendingScenarioID = selected.Scenario.UniqueID()
	return nil
}

func (m *Model) executeDemo(scenarioID string) tea.Cmd {
	// Find scenario by ID
	var scenario *scenarios.Scenario
	for _, s := range m.allScenarios {
		if s.UniqueID() == scenarioID {
			scenario = s
			break
		}
	}
	if scenario == nil {
		return nil
	}

	demoPath := scenario.DemoPath()
	demoDir := filepath.Dir(demoPath)

	// Wrap the script to pause before returning to TUI so users can see output
	// This captures the exit code, shows a message, waits for Enter, then exits
	wrapperScript := fmt.Sprintf(`
		bash %q
		exit_code=$?
		echo ""
		if [ $exit_code -eq 0 ]; then
			echo -e "\033[0;32m[Demo completed successfully]\033[0m"
		else
			echo -e "\033[0;31m[Demo failed with exit code $exit_code]\033[0m"
		fi
		echo ""
		echo "Press Enter to return to TUI..."
		read
		exit $exit_code
	`, demoPath)

	cmd := exec.Command("bash", "-c", wrapperScript)
	cmd.Dir = demoDir

	// Use tea.Exec to suspend TUI and give full terminal control to the script
	interactiveCmd := &interactiveDemoCmd{cmd: cmd}
	scenarioDir := scenario.DirPath
	return tea.Exec(interactiveCmd, func(err error) tea.Msg {
		return interactiveDemoDoneMsg{err: err, scenarioDir: scenarioDir}
	})
}

func (m *Model) runCleanup() tea.Cmd {
	selected := m.scenariosPane.Selected()
	if selected == nil || !selected.Deployed {
		m.overlay.Show(OverlayError, "Cleanup", "Scenario must be deployed first.")
		return nil
	}

	if !selected.Scenario.HasCleanup() {
		m.overlay.Show(OverlayError, "Cleanup", "No cleanup script available for this scenario.")
		return nil
	}

	// Show confirmation prompt
	m.pendingAction = "cleanup"
	m.pendingScenarioID = selected.Scenario.UniqueID()
	return nil
}

func (m *Model) runCleanupAll() tea.Cmd {
	ids := m.scenariosPane.GetDemoActiveScenarioIDs()
	if len(ids) == 0 {
		m.overlay.Show(OverlayError, "Cleanup All", "No scenarios have active demos to clean up.")
		return nil
	}

	m.cleanupQueue = ids
	m.pendingAction = "cleanupAll"
	return nil
}

func (m *Model) executeCleanupQueue() tea.Cmd {
	if len(m.cleanupQueue) == 0 {
		if m.cleanupQueueAction == "deploy" {
			m.cleanupQueueAction = ""
			return m.executeDeploy()
		}
		m.cleanupQueueAction = ""
		return nil
	}

	// Pop the first ID from the queue
	nextID := m.cleanupQueue[0]
	m.cleanupQueue = m.cleanupQueue[1:]
	return m.executeCleanup(nextID, true)
}

func (m *Model) executeCleanup(scenarioID string, skipPause bool) tea.Cmd {
	// Find scenario by ID
	var scenario *scenarios.Scenario
	for _, s := range m.allScenarios {
		if s.UniqueID() == scenarioID {
			scenario = s
			break
		}
	}
	if scenario == nil {
		return nil
	}

	cleanupPath := scenario.CleanupPath()
	cleanupDir := filepath.Dir(cleanupPath)

	// Wrap the script to pause before returning to TUI so users can see output
	pauseSnippet := `echo "Press Enter to return to TUI..."; read`
	if skipPause {
		pauseSnippet = ""
	}
	wrapperScript := fmt.Sprintf(`
		bash %q
		exit_code=$?
		echo ""
		if [ $exit_code -eq 0 ]; then
			echo -e "\033[0;32m[Cleanup completed successfully]\033[0m"
		else
			echo -e "\033[0;31m[Cleanup failed with exit code $exit_code]\033[0m"
		fi
		echo ""
		%s
		exit $exit_code
	`, cleanupPath, pauseSnippet)

	cmd := exec.Command("bash", "-c", wrapperScript)
	cmd.Dir = cleanupDir

	// Use tea.Exec to suspend TUI and give full terminal control to the script
	interactiveCmd := &interactiveDemoCmd{cmd: cmd}
	scenarioDir := scenario.DirPath
	return tea.Exec(interactiveCmd, func(err error) tea.Msg {
		return interactiveDemoDoneMsg{err: err, scenarioDir: scenarioDir, isCleanup: true}
	})
}

func (m *Model) showDestroyTypeChoice() tea.Cmd {
	// Check if there's anything to destroy
	hasEnabledScenarios := len(m.config.Active().Scenarios.Enabled) > 0
	hasDeployedResources := false
	if m.tfRunner != nil && m.tfRunner.IsInitialized() {
		resources, err := m.tfRunner.StateList()
		hasDeployedResources = err == nil && len(resources) > 0
	}

	if !hasEnabledScenarios && !hasDeployedResources {
		m.overlay.Show(OverlayError, "Destroy", "Nothing to destroy. No scenarios enabled and no resources deployed.")
		return nil
	}

	m.choosingDestroyType = true
	return nil
}


func (m *Model) executeDestroyScenarios() tea.Cmd {
	// Disable all enabled scenarios in config
	m.config.Active().Scenarios.Enabled = nil

	// Save config and sync tfvars
	if err := m.config.Save(); err != nil {
		m.err = err
		return nil
	}
	if err := m.config.Active().SyncTFVars(m.paths.TerraformDir); err != nil {
		m.err = err
		return nil
	}

	// Refresh the scenarios pane to show disabled state
	items := m.scenariosPane.GetItems()
	for i := range items {
		items[i].Enabled = false
	}
	m.scenariosPane.SetScenarios(items)

	m.overlay.ShowRunning(OverlayTerraform, "Destroy Scenarios")
	cmd := exec.Command("bash", "-c", fmt.Sprintf("cd %s && terraform apply -auto-approve", m.paths.TerraformDir))
	cmd.Env = m.buildTerraformEnv()
	return m.runCommandStreaming(cmd)
}

func (m *Model) executeDestroyAll() tea.Cmd {
	m.overlay.ShowRunning(OverlayTerraform, "Destroy All")
	cmd := exec.Command("bash", "-c", fmt.Sprintf("cd %s && terraform destroy -auto-approve", m.paths.TerraformDir))
	cmd.Env = m.buildTerraformEnv()
	return m.runCommandStreaming(cmd)
}

func (m *Model) showEnableTypeChoice() tea.Cmd {
	m.choosingEnableType = true
	return nil
}

func (m *Model) executeEnableAll() tea.Cmd {
	if m.config == nil {
		m.overlay.Show(OverlayError, "Enable All", "Configuration not loaded.")
		return nil
	}

	singleAccountMode := m.config.Active().IsSingleAccountMode()
	enabledCount := 0
	skippedCrossAccount := 0
	skippedMissingConfig := 0

	for _, s := range m.allScenarios {
		// Skip cross-account scenarios in single-account mode
		if singleAccountMode && s.RequiresMultiAccount() {
			skippedCrossAccount++
			continue
		}
		// Skip scenarios with missing required config
		if s.HasConfig() {
			missingRequired := false
			for _, cfgKey := range s.Config {
				if cfgKey.Required {
					val, _ := m.config.Active().GetScenarioConfig(s.Name, cfgKey.Key)
					if val == "" {
						missingRequired = true
						break
					}
				}
			}
			if missingRequired {
				skippedMissingConfig++
				continue
			}
		}
		m.config.Active().EnableScenario(s.Terraform.VariableName)
		enabledCount++
	}

	// Save config and sync tfvars
	if err := m.config.Save(); err != nil {
		m.err = err
		return nil
	}
	if err := m.config.Active().SyncTFVars(m.paths.TerraformDir); err != nil {
		m.err = err
		return nil
	}

	// Refresh the scenarios pane
	items := m.scenariosPane.GetItems()
	enabledVars := m.config.Active().GetEnabledScenarioVars()
	for i := range items {
		items[i].Enabled = enabledVars[items[i].Scenario.Terraform.VariableName]
	}
	m.scenariosPane.SetScenarios(items)
	m.updateDetails()
	m.updateInfoCounts()

	// Show result
	msg := fmt.Sprintf("Enabled %d scenario(s).", enabledCount)
	if skippedCrossAccount > 0 {
		msg += fmt.Sprintf("\n\nSkipped %d cross-account scenario(s) (single-account mode).", skippedCrossAccount)
	}
	if skippedMissingConfig > 0 {
		msg += fmt.Sprintf("\n\nSkipped %d scenario(s) with missing required config. Set values via the Details pane (Tab → e).", skippedMissingConfig)
	}
	msg += "\n\nPress [a] to apply."
	m.overlay.Show(OverlayInfo, "Enable All", msg)
	return nil
}

func (m *Model) executeEnablePattern(pattern string) tea.Cmd {
	if m.config == nil {
		m.overlay.Show(OverlayError, "Enable Pattern", "Configuration not loaded.")
		return nil
	}

	singleAccountMode := m.config.Active().IsSingleAccountMode()
	enabledCount := 0
	skippedCrossAccount := 0
	skippedMissingConfigPattern := 0
	var enabledNames []string

	for _, s := range m.allScenarios {
		// Check if matches pattern (against UniqueID or base ID)
		if !m.matchesPattern(s.UniqueID(), pattern) && !m.matchesPattern(s.ID(), pattern) {
			continue
		}

		// Skip cross-account scenarios in single-account mode
		if singleAccountMode && s.RequiresMultiAccount() {
			skippedCrossAccount++
			continue
		}

		// Skip scenarios with missing required config
		if s.HasConfig() {
			missingRequired := false
			for _, cfgKey := range s.Config {
				if cfgKey.Required {
					val, _ := m.config.Active().GetScenarioConfig(s.Name, cfgKey.Key)
					if val == "" {
						missingRequired = true
						break
					}
				}
			}
			if missingRequired {
				skippedMissingConfigPattern++
				continue
			}
		}

		m.config.Active().EnableScenario(s.Terraform.VariableName)
		enabledCount++
		enabledNames = append(enabledNames, s.UniqueID())
	}

	if enabledCount == 0 && skippedCrossAccount == 0 && skippedMissingConfigPattern == 0 {
		m.overlay.Show(OverlayError, "Enable Pattern", fmt.Sprintf("No scenarios match pattern: %s", pattern))
		return nil
	}

	// Save config and sync tfvars
	if err := m.config.Save(); err != nil {
		m.err = err
		return nil
	}
	if err := m.config.Active().SyncTFVars(m.paths.TerraformDir); err != nil {
		m.err = err
		return nil
	}

	// Refresh the scenarios pane
	items := m.scenariosPane.GetItems()
	enabledVars := m.config.Active().GetEnabledScenarioVars()
	for i := range items {
		items[i].Enabled = enabledVars[items[i].Scenario.Terraform.VariableName]
	}
	m.scenariosPane.SetScenarios(items)
	m.updateDetails()
	m.updateInfoCounts()

	// Show result
	msg := fmt.Sprintf("Pattern: %s\n\nEnabled %d scenario(s):", pattern, enabledCount)
	// Show up to 10 enabled scenarios
	for i, name := range enabledNames {
		if i >= 10 {
			msg += fmt.Sprintf("\n  ... and %d more", len(enabledNames)-10)
			break
		}
		msg += fmt.Sprintf("\n  - %s", name)
	}
	if skippedCrossAccount > 0 {
		msg += fmt.Sprintf("\n\nSkipped %d cross-account scenario(s) (single-account mode).", skippedCrossAccount)
	}
	if skippedMissingConfigPattern > 0 {
		msg += fmt.Sprintf("\n\nSkipped %d scenario(s) with missing required config. Set values via the Details pane (Tab → e).", skippedMissingConfigPattern)
	}
	if enabledCount > 0 {
		msg += "\n\nPress [a] to apply."
	}
	m.overlay.Show(OverlayInfo, "Enable Pattern", msg)
	return nil
}

func (m *Model) showDisableTypeChoice() tea.Cmd {
	m.choosingDisableType = true
	return nil
}

func (m *Model) executeDisableAll() tea.Cmd {
	if m.config == nil {
		m.overlay.Show(OverlayError, "Disable All", "Configuration not loaded.")
		return nil
	}

	disabledCount := 0
	for _, s := range m.allScenarios {
		if m.config.Active().IsScenarioEnabled(s.Terraform.VariableName) {
			m.config.Active().DisableScenario(s.Terraform.VariableName)
			disabledCount++
		}
	}

	// Save config and sync tfvars
	if err := m.config.Save(); err != nil {
		m.err = err
		return nil
	}
	if err := m.config.Active().SyncTFVars(m.paths.TerraformDir); err != nil {
		m.err = err
		return nil
	}

	// Refresh the scenarios pane
	items := m.scenariosPane.GetItems()
	enabledVars := m.config.Active().GetEnabledScenarioVars()
	for i := range items {
		items[i].Enabled = enabledVars[items[i].Scenario.Terraform.VariableName]
	}
	m.scenariosPane.SetScenarios(items)
	m.updateDetails()
	m.updateInfoCounts()

	msg := fmt.Sprintf("Disabled %d scenario(s).", disabledCount)
	m.overlay.Show(OverlayInfo, "Disable All", msg)
	return nil
}

func (m *Model) executeDisablePattern(pattern string) tea.Cmd {
	if m.config == nil {
		m.overlay.Show(OverlayError, "Disable Pattern", "Configuration not loaded.")
		return nil
	}

	disabledCount := 0
	var disabledNames []string

	for _, s := range m.allScenarios {
		if !m.matchesPattern(s.UniqueID(), pattern) && !m.matchesPattern(s.ID(), pattern) {
			continue
		}
		if m.config.Active().IsScenarioEnabled(s.Terraform.VariableName) {
			m.config.Active().DisableScenario(s.Terraform.VariableName)
			disabledCount++
			disabledNames = append(disabledNames, s.UniqueID())
		}
	}

	if disabledCount == 0 {
		m.overlay.Show(OverlayError, "Disable Pattern", fmt.Sprintf("No enabled scenarios match pattern: %s", pattern))
		return nil
	}

	// Save config and sync tfvars
	if err := m.config.Save(); err != nil {
		m.err = err
		return nil
	}
	if err := m.config.Active().SyncTFVars(m.paths.TerraformDir); err != nil {
		m.err = err
		return nil
	}

	// Refresh the scenarios pane
	items := m.scenariosPane.GetItems()
	enabledVars := m.config.Active().GetEnabledScenarioVars()
	for i := range items {
		items[i].Enabled = enabledVars[items[i].Scenario.Terraform.VariableName]
	}
	m.scenariosPane.SetScenarios(items)
	m.updateDetails()
	m.updateInfoCounts()

	// Show result
	msg := fmt.Sprintf("Pattern: %s\n\nDisabled %d scenario(s):", pattern, disabledCount)
	for i, name := range disabledNames {
		if i >= 10 {
			msg += fmt.Sprintf("\n  ... and %d more", len(disabledNames)-10)
			break
		}
		msg += fmt.Sprintf("\n  - %s", name)
	}
	m.overlay.Show(OverlayInfo, "Disable Pattern", msg)
	return nil
}

// matchesPattern checks if a string matches a glob pattern
func (m *Model) matchesPattern(s, pattern string) bool {
	matched, err := filepath.Match(pattern, s)
	if err != nil {
		return false
	}
	return matched
}

func (m *Model) showConfig() {
	m.overlay.Show(OverlayConfig, "Settings", m.renderSettingsMenu())
}

func (m *Model) renderSettingsMenu() string {
	var sb strings.Builder

	// Get environment states
	prodEnabled, devEnabled, opsEnabled, attackerEnabled, _ := m.tfvars.GetEnabledEnvironments()
	deployed := make(map[string]bool)
	if m.tfRunner != nil && m.tfRunner.IsInitialized() {
		deployed = m.tfRunner.GetDeployedModules()
	}
	prodDeployed := deployed["prod_environment"]
	devDeployed := deployed["dev_environment"]
	opsDeployed := deployed["ops_environment"]
	// Attacker module has no resources in state (it's a pass-through),
	// so treat it as deployed when enabled and terraform is initialized
	attackerDeployed := deployed["attacker_environment"] || attackerEnabled

	sb.WriteString("AWS Profiles\n")
	sb.WriteString("----------------------------------------\n\n")

	// Prod
	sb.WriteString(fmt.Sprintf("  [1] prod:      %s", m.valueOrNotSet(m.config.Active().AWS.Prod.Profile)))
	sb.WriteString(m.envStatusSuffix(prodEnabled, prodDeployed))
	sb.WriteString("\n")

	// Dev
	sb.WriteString(fmt.Sprintf("  [2] dev:       %s", m.valueOrNotSet(m.config.Active().AWS.Dev.Profile)))
	sb.WriteString(m.envStatusSuffix(devEnabled, devDeployed))
	sb.WriteString("\n")

	// Ops
	sb.WriteString(fmt.Sprintf("  [3] ops:       %s", m.valueOrNotSet(m.config.Active().AWS.Ops.Profile)))
	sb.WriteString(m.envStatusSuffix(opsEnabled, opsDeployed))
	sb.WriteString("\n")

	// Attacker
	sb.WriteString(fmt.Sprintf("  [4] attacker:  %s", m.valueOrNotSet(m.config.Active().AWS.Attacker.Profile)))
	if m.config.Active().AWS.Attacker.Profile == "" {
		sb.WriteString("  (optional, for adversary-side infrastructure)")
	} else {
		sb.WriteString(m.envStatusSuffix(attackerEnabled, attackerDeployed))
	}
	sb.WriteString("\n")

	// Budget Alerts section
	sb.WriteString("\n\nBudget Alerts (Cost Protection)\n")
	sb.WriteString("----------------------------------------\n\n")

	if m.config.Active().Budget.Enabled {
		sb.WriteString("  [b] Status:  Enabled\n")
		sb.WriteString(fmt.Sprintf("      Email:   %s\n", m.config.Active().Budget.Email))
		sb.WriteString(fmt.Sprintf("      Limit:   $%d/month\n", m.config.Active().Budget.LimitUSD))
	} else {
		sb.WriteString("  [b] Status:  Disabled\n")
		sb.WriteString("      (alerts at 50%, 80%, 100% spend)\n")
	}

	sb.WriteString("\n----------------------------------------\n")
	sb.WriteString("Press 1/2/3/4 to change a profile\n")
	sb.WriteString("Press b to configure budget alerts\n")
	sb.WriteString("Press Esc to close\n")

	return sb.String()
}

func (m *Model) envStatusSuffix(enabled, deployed bool) string {
	if deployed {
		return "  (deployed)"
	} else if enabled {
		return "  (enabled)"
	}
	return ""
}

func (m *Model) valueOrNotSet(v string) string {
	if v == "" {
		return "(not set)"
	}
	return v
}

// handleSettingsKeys handles key presses in the settings overlay
func (m *Model) handleSettingsKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "1":
		m.overlay.Hide()
		return m, m.runProfileWizard("prod")
	case "2":
		m.overlay.Hide()
		return m, m.runProfileWizard("dev")
	case "3":
		m.overlay.Hide()
		return m, m.runProfileWizard("ops")
	case "4":
		m.overlay.Hide()
		return m, m.runProfileWizard("attacker")
	case "b", "B":
		m.overlay.Hide()
		return m, m.runBudgetWizard()
	case "esc":
		m.overlay.Hide()
		return m, nil
	}
	return m, nil
}

// profileWizardMsg is sent when the profile wizard completes
type profileWizardMsg struct {
	envName    string
	newProfile string
	err        error
}

// wizardCmd wraps the wizard execution for tea.Exec
type wizardCmd struct {
	envName        string
	currentProfile string
	result         chan profileWizardMsg
}

func (w *wizardCmd) Run() error {
	wizard := config.NewWizard()
	newProfile, err := wizard.RunForEnvironment(w.envName, w.currentProfile)
	w.result <- profileWizardMsg{envName: w.envName, newProfile: newProfile, err: err}
	return nil
}

func (w *wizardCmd) SetStdin(r io.Reader)   {}
func (w *wizardCmd) SetStdout(wr io.Writer) {}
func (w *wizardCmd) SetStderr(wr io.Writer) {}

// runProfileWizard runs the wizard for a single environment
func (m *Model) runProfileWizard(envName string) tea.Cmd {
	// Get current profile
	var currentProfile string
	switch envName {
	case "prod":
		currentProfile = m.config.Active().AWS.Prod.Profile
	case "dev":
		currentProfile = m.config.Active().AWS.Dev.Profile
	case "ops":
		currentProfile = m.config.Active().AWS.Ops.Profile
	case "attacker":
		currentProfile = m.config.Active().AWS.Attacker.Profile
	}

	resultChan := make(chan profileWizardMsg, 1)
	cmd := &wizardCmd{
		envName:        envName,
		currentProfile: currentProfile,
		result:         resultChan,
	}

	return tea.Exec(cmd, func(err error) tea.Msg {
		select {
		case msg := <-resultChan:
			return msg
		default:
			if err != nil {
				return profileWizardMsg{envName: envName, err: err}
			}
			return profileWizardMsg{envName: envName, err: fmt.Errorf("wizard cancelled")}
		}
	})
}

// budgetWizardMsg is sent when the budget wizard completes
type budgetWizardMsg struct {
	result *config.BudgetResult
	err    error
}

// budgetWizardCmd wraps the budget wizard execution for tea.Exec
type budgetWizardCmd struct {
	currentBudget config.BudgetConfig
	result        chan budgetWizardMsg
}

func (b *budgetWizardCmd) Run() error {
	wizard := config.NewWizard()
	result, err := wizard.RunForBudget(b.currentBudget)
	b.result <- budgetWizardMsg{result: result, err: err}
	return nil
}

func (b *budgetWizardCmd) SetStdin(r io.Reader)   {}
func (b *budgetWizardCmd) SetStdout(wr io.Writer) {}
func (b *budgetWizardCmd) SetStderr(wr io.Writer) {}

// runBudgetWizard runs the wizard for budget configuration
func (m *Model) runBudgetWizard() tea.Cmd {
	resultChan := make(chan budgetWizardMsg, 1)
	cmd := &budgetWizardCmd{
		currentBudget: m.config.Active().Budget,
		result:        resultChan,
	}

	return tea.Exec(cmd, func(err error) tea.Msg {
		select {
		case msg := <-resultChan:
			return msg
		default:
			if err != nil {
				return budgetWizardMsg{err: err}
			}
			return budgetWizardMsg{err: fmt.Errorf("wizard cancelled")}
		}
	})
}

// validateAndSetProfile validates the new profile and sets it if allowed
func (m *Model) validateAndSetProfile(envName, newProfile string) error {
	if newProfile == "" {
		return fmt.Errorf("profile name cannot be empty")
	}

	// Get current state
	var currentProfile string
	var isEnabled bool

	prodEnabled, devEnabled, opsEnabled, attackerEnabled, _ := m.tfvars.GetEnabledEnvironments()

	switch envName {
	case "prod":
		currentProfile = m.config.Active().AWS.Prod.Profile
		isEnabled = prodEnabled
	case "dev":
		currentProfile = m.config.Active().AWS.Dev.Profile
		isEnabled = devEnabled
	case "ops":
		currentProfile = m.config.Active().AWS.Ops.Profile
		isEnabled = opsEnabled
	case "attacker":
		currentProfile = m.config.Active().AWS.Attacker.Profile
		isEnabled = attackerEnabled
	}

	// If same profile, nothing to do
	if newProfile == currentProfile {
		return nil
	}

	// Validate the new profile works by calling AWS
	newAccountID, err := m.getAccountIDForProfile(newProfile)
	if err != nil {
		return fmt.Errorf("invalid profile '%s': %v", newProfile, err)
	}

	// If environment is enabled, check if account ID matches
	if isEnabled {
		currentAccountID, _ := m.getAccountIDForProfile(currentProfile)
		if newAccountID != currentAccountID {
			return fmt.Errorf("cannot change to different account while %s is enabled.\nDisable the %s environment first, then change the profile.", envName, envName)
		}
	}

	// All checks passed - update the config
	switch envName {
	case "prod":
		m.config.Active().AWS.Prod.Profile = newProfile
	case "dev":
		m.config.Active().AWS.Dev.Profile = newProfile
	case "ops":
		m.config.Active().AWS.Ops.Profile = newProfile
	case "attacker":
		m.config.Active().AWS.Attacker.Profile = newProfile
	}

	// Save config (single source of truth)
	if err := m.config.Save(); err != nil {
		return fmt.Errorf("failed to save config: %v", err)
	}

	// Regenerate tfvars
	if err := m.config.Active().SyncTFVars(m.paths.TerraformDir); err != nil {
		return fmt.Errorf("failed to sync tfvars: %v", err)
	}

	return nil
}

// getAccountIDForProfile calls AWS to get the account ID for a profile
func (m *Model) getAccountIDForProfile(profile string) (string, error) {
	result := aws.ValidateProfile(profile)
	if !result.Valid {
		return "", result.Error
	}
	return result.AccountID, nil
}

// validateCredentialsAsync returns a tea.Cmd that validates AWS credentials asynchronously
func (m *Model) validateCredentialsAsync() tea.Cmd {
	return func() tea.Msg {
		if m.config == nil {
			return credentialsValidatedMsg{valid: false, err: fmt.Errorf("configuration not loaded")}
		}

		profile := m.config.Active().AWS.Prod.Profile
		if profile == "" {
			return credentialsValidatedMsg{valid: false, err: fmt.Errorf("no AWS profile configured")}
		}

		err := aws.ValidatePrimaryProfile(profile)
		return credentialsValidatedMsg{valid: err == nil, profile: profile, err: err}
	}
}

// buildTerraformEnv returns a clean subprocess environment with any attacker IAM
// credentials injected as TF_VAR_* variables. Use this for all terraform invocations
// so credentials never need to be written to terraform.tfvars.
func (m *Model) buildTerraformEnv() []string {
	env := terraform.CleanEnv()
	if m.config != nil {
		env = append(env, m.config.Active().GetAttackerTFVarEnv()...)
	}
	return env
}

// runCommandStreaming runs a command and streams its output to the overlay
func (m *Model) runCommandStreaming(cmd *exec.Cmd) tea.Cmd {
	m.runningCmd = cmd

	// Create a pipe for combined stdout/stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return func() tea.Msg {
			return cmdDoneMsg{err: err}
		}
	}
	cmd.Stderr = cmd.Stdout // Combine stderr with stdout

	if err := cmd.Start(); err != nil {
		return func() tea.Msg {
			return cmdDoneMsg{err: err}
		}
	}

	// Set up scanner for incremental reading
	scanner := bufio.NewScanner(stdout)
	buf := make([]byte, 0, 64*1024)
	scanner.Buffer(buf, 1024*1024)
	m.cmdScanner = scanner

	// Set up channel to get command completion status
	m.cmdWaitDone = make(chan error, 1)
	go func() {
		m.cmdWaitDone <- cmd.Wait()
	}()

	// Start reading output
	return func() tea.Msg { return m.readNextLine() }
}

// readNextLine reads the next line of output from the running command
func (m *Model) readNextLine() tea.Msg {
	if m.cmdScanner == nil {
		return nil
	}

	// Check if command is done
	select {
	case err := <-m.cmdWaitDone:
		// Drain any remaining output
		for m.cmdScanner.Scan() {
			m.overlay.AppendContent(m.cmdScanner.Text())
		}
		return cmdDoneMsg{err: err}
	default:
		// Try to read a line
		if m.cmdScanner.Scan() {
			return cmdOutputMsg{line: m.cmdScanner.Text()}
		}
		// No more output but command might still be running
		// Check again for completion
		select {
		case err := <-m.cmdWaitDone:
			return cmdDoneMsg{err: err}
		default:
			// Keep checking
			return cmdOutputMsg{line: ""}
		}
	}
}

func (m *Model) updateLayout() {
	// Calculate pane sizes as percentages: left 25%, center 25%, right 50%
	leftWidth := m.termWidth * 25 / 100
	centerWidth := m.termWidth * 25 / 100
	rightWidth := m.termWidth - leftWidth - centerWidth

	// Ensure minimum widths
	if leftWidth < 25 {
		leftWidth = 25
	}
	if centerWidth < 20 {
		centerWidth = 20
	}
	if rightWidth < 30 {
		rightWidth = 30
	}

	// Main content height (leave room for status bar)
	mainHeight := m.termHeight - 1
	if mainHeight < 1 {
		mainHeight = 1
	}

	// Info pane height (allows for wrapped directory path and optional update notice)
	infoHeight := 12
	if m.info.HasUpdateNotice() {
		infoHeight += 4
	}

	// Environment pane height (fixed, compact)
	envHeight := 8
	if m.config != nil && m.config.Active().IsMultiAccountMode() {
		envHeight = 12
	}

	// Actions pane takes remaining height on left
	actionsHeight := mainHeight - infoHeight - envHeight
	if actionsHeight < 10 {
		actionsHeight = 10
	}

	// Set sizes
	m.info.SetSize(leftWidth, infoHeight)
	m.environment.SetSize(leftWidth, envHeight)
	m.actions.SetSize(leftWidth, actionsHeight)
	m.scenariosPane.SetSize(centerWidth, mainHeight)
	m.details.SetSize(rightWidth, mainHeight)
	m.overlay.SetSize(m.termWidth, m.termHeight)

	// Update focus
	m.updatePaneFocus()
}

// View renders the entire TUI
func (m *Model) View() string {
	if !m.ready {
		return "Loading..."
	}

	if m.err != nil {
		return fmt.Sprintf("Error: %v\n\nPress q to quit.", m.err)
	}

	// Calculate main content height (leave room for status bar)
	mainHeight := m.termHeight - 1

	// Build the three-column layout
	leftPane := lipgloss.JoinVertical(lipgloss.Left,
		m.info.View(),
		m.environment.View(),
		m.actions.View(),
	)

	// Constrain each pane to mainHeight
	leftPane = lipgloss.NewStyle().MaxHeight(mainHeight).Render(leftPane)
	centerPane := lipgloss.NewStyle().MaxHeight(mainHeight).Render(m.scenariosPane.View())
	rightPane := lipgloss.NewStyle().MaxHeight(mainHeight).Render(m.details.View())

	// Join horizontally
	mainContent := lipgloss.JoinHorizontal(lipgloss.Top,
		leftPane,
		centerPane,
		rightPane,
	)

	// Status bar
	statusBar := m.renderStatusBar()

	// Combine main content and status bar
	content := lipgloss.JoinVertical(lipgloss.Left,
		mainContent,
		statusBar,
	)

	// Render overlay on top if visible
	if m.overlay.IsVisible() {
		// The overlay View already handles centering via lipgloss.Place
		return m.overlay.View(m.termWidth, m.termHeight)
	}

	// Filter input overlay
	if m.filtering {
		return content + "\n" + m.renderFilterBar()
	}

	// Destroy type choice overlay
	if m.choosingDestroyType {
		return content + "\n" + m.renderDestroyTypeChoiceBar()
	}

	// Destroy confirmation overlay
	if m.confirmingDestroy {
		return content + "\n" + m.renderDestroyConfirmBar()
	}

	// Simple action confirmation overlay (deploy, plan, demo, cleanup)
	if m.pendingAction != "" {
		return content + "\n" + m.renderActionConfirmBar()
	}

	// Credential validation in progress
	if m.validatingCredentials {
		return content + "\n" + m.renderValidatingCredentialsBar()
	}

	// Enable type choice overlay
	if m.choosingEnableType {
		return content + "\n" + m.renderEnableTypeChoiceBar()
	}

	// Enable pattern input overlay
	if m.enteringPattern {
		return content + "\n" + m.renderEnablePatternBar()
	}

	// Disable type choice overlay
	if m.choosingDisableType {
		return content + "\n" + m.renderDisableTypeChoiceBar()
	}

	// Disable pattern input overlay
	if m.enteringDisablePattern {
		return content + "\n" + m.renderDisablePatternBar()
	}

	// Per-scenario config editing bar
	if m.editingScenarioConfig {
		return content + "\n" + m.renderScenarioConfigEditBar()
	}

	return content
}

func (m *Model) renderStatusBar() string {
	enabledCount := m.scenariosPane.GetEnabledCount()
	deployedCount := m.scenariosPane.GetDeployedCount()

	// Colors with status bar background
	statusBg := m.styles.ColorStatusBg
	enabledStyle := lipgloss.NewStyle().Foreground(m.styles.ColorKey).Background(statusBg)
	deployedStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#10B981")).Background(statusBg)
	separatorStyle := lipgloss.NewStyle().Foreground(m.styles.ColorDim).Background(statusBg)
	pendingStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Background(statusBg)
	keyStyle := lipgloss.NewStyle().Foreground(m.styles.ColorDim).Background(statusBg)
	descStyle := lipgloss.NewStyle().Foreground(m.styles.ColorDim).Background(statusBg)

	demoActiveStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Background(statusBg)

	// Build left side - copy toast when active, otherwise status counts
	var leftParts []string
	if m.copyToast != "" {
		toastStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#10B981")).Background(statusBg).Bold(true)
		leftParts = append(leftParts, toastStyle.Render(m.copyToast))
	} else {
		leftParts = append(leftParts, enabledStyle.Render(fmt.Sprintf("%d enabled", enabledCount)))
		leftParts = append(leftParts, separatorStyle.Render(" . "))
		leftParts = append(leftParts, deployedStyle.Render(fmt.Sprintf("%d deployed", deployedCount)))

		// Show demo-active count if any
		demoActiveCount := m.scenariosPane.GetDemoActiveCount()
		if demoActiveCount > 0 {
			leftParts = append(leftParts, separatorStyle.Render(" . "))
			leftParts = append(leftParts, demoActiveStyle.Render(fmt.Sprintf("%d demo active \u26a0", demoActiveCount)))
		}

		// Check if deploy is needed
		if m.scenariosPane.HasPendingChanges() {
			leftParts = append(leftParts, separatorStyle.Render(" . "))
			leftParts = append(leftParts, pendingStyle.Render("[a] to apply changes"))
		}
	}

	leftText := strings.Join(leftParts, "")

	// Build right side - global shortcuts
	var rightParts []string
	rightParts = append(rightParts, keyStyle.Render("?"))
	rightParts = append(rightParts, descStyle.Render(" help  "))
	rightParts = append(rightParts, keyStyle.Render("s"))
	rightParts = append(rightParts, descStyle.Render(" settings  "))
	rightParts = append(rightParts, keyStyle.Render("q"))
	rightParts = append(rightParts, descStyle.Render(" quit"))

	rightText := strings.Join(rightParts, "")

	// Calculate padding to push right text to the right
	leftLen := lipgloss.Width(leftText)
	rightLen := lipgloss.Width(rightText)
	padding := m.termWidth - leftLen - rightLen - 2 // -2 for some margin
	if padding < 1 {
		padding = 1
	}

	paddingStr := lipgloss.NewStyle().Background(m.styles.ColorStatusBg).Render(strings.Repeat(" ", padding))

	return m.styles.StatusBar.Width(m.termWidth).Render(leftText + paddingStr + rightText)
}

func (m *Model) renderFilterBar() string {
	return m.styles.FilterPrompt.Render("/") + m.filterInput.View()
}

func (m *Model) renderDestroyTypeChoiceBar() string {
	warningStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#EF4444")).Bold(true)
	promptStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B"))
	keyStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4")).Bold(true)
	dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#9CA3AF"))

	return warningStyle.Render("DESTROY ") +
		promptStyle.Render("What to destroy? ") +
		keyStyle.Render("[s]") +
		dimStyle.Render("cenarios only  ") +
		keyStyle.Render("[a]") +
		dimStyle.Render("ll (scenarios + environments)  ") +
		dimStyle.Render("(Esc to cancel)")
}

func (m *Model) renderDestroyConfirmBar() string {
	warningStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#EF4444")).Bold(true)
	promptStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B"))

	var action string
	if m.destroyType == "scenarios" {
		action = "DESTROY SCENARIOS"
	} else {
		action = "DESTROY ALL RESOURCES"
	}

	return warningStyle.Render("! "+action+" ! ") +
		promptStyle.Render("Type 'destroy' to confirm: ") +
		m.confirmInput.View() +
		promptStyle.Render(" (Esc to cancel)")
}

func (m *Model) renderActionConfirmBar() string {
	keyStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4")).Bold(true)
	dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#9CA3AF"))

	// Deploy warning gets its own rendering
	if m.pendingAction == "deployWarning" {
		warningStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Bold(true)
		return warningStyle.Render(fmt.Sprintf("WARNING: %d scenario(s) being disabled have active demos. Cleanup won't work after deploy.  ", len(m.deployWarningIDs))) +
			keyStyle.Render("[c]") +
			dimStyle.Render(" cleanup first  ") +
			keyStyle.Render("Enter") +
			dimStyle.Render(" apply anyway  ") +
			keyStyle.Render("Esc") +
			dimStyle.Render(" cancel")
	}

	var actionStyle lipgloss.Style
	var actionText string
	var description string

	switch m.pendingAction {
	case "deploy":
		actionStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#10B981")).Bold(true) // Green
		actionText = "APPLY"
		description = "Run terraform apply to deploy enabled scenarios"
	case "plan":
		actionStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4")).Bold(true) // Cyan
		actionText = "PLAN"
		description = "Run terraform plan to preview changes"
	case "demo":
		actionStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Bold(true) // Yellow/Orange
		actionText = "RUN DEMO"
		if m.pendingScenarioID != "" {
			description = fmt.Sprintf("Execute demo_attack.sh for %s", m.pendingScenarioID)
		} else {
			description = "Execute demo_attack.sh"
		}
	case "cleanup":
		actionStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Bold(true) // Yellow/Orange
		actionText = "RUN CLEANUP"
		if m.pendingScenarioID != "" {
			description = fmt.Sprintf("Execute cleanup_attack.sh for %s", m.pendingScenarioID)
		} else {
			description = "Execute cleanup_attack.sh"
		}
	case "cleanupAll":
		actionStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Bold(true) // Yellow/Orange
		actionText = "CLEANUP ALL"
		description = fmt.Sprintf("Run cleanup for %d scenario(s) with active demos", len(m.cleanupQueue))
	default:
		actionStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#9CA3AF"))
		actionText = "ACTION"
		description = "Confirm action"
	}

	return actionStyle.Render(actionText+" ") +
		dimStyle.Render(description+"  ") +
		keyStyle.Render("Enter") +
		dimStyle.Render(" to proceed  ") +
		keyStyle.Render("Esc") +
		dimStyle.Render(" to cancel")
}

func (m *Model) renderValidatingCredentialsBar() string {
	spinnerStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4")).Bold(true) // Cyan
	textStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#9CA3AF"))
	keyStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4")).Bold(true)

	return spinnerStyle.Render("⟳ ") +
		textStyle.Render("Validating AWS credentials...  ") +
		keyStyle.Render("Esc") +
		textStyle.Render(" to cancel")
}

func (m *Model) renderEnableTypeChoiceBar() string {
	enableStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#10B981")).Bold(true)
	promptStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4"))
	keyStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4")).Bold(true)
	dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#9CA3AF"))

	return enableStyle.Render("ENABLE ") +
		promptStyle.Render("What to enable? ") +
		keyStyle.Render("[a]") +
		dimStyle.Render("ll scenarios  ") +
		keyStyle.Render("[p]") +
		dimStyle.Render("attern (e.g., iam-*, lambda-001)  ") +
		dimStyle.Render("(Esc to cancel)")
}

func (m *Model) renderEnablePatternBar() string {
	enableStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#10B981")).Bold(true)
	promptStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4"))

	return enableStyle.Render("ENABLE ") +
		promptStyle.Render("Enter pattern: ") +
		m.patternInput.View() +
		promptStyle.Render(" (Enter to confirm, Esc to cancel)")
}

func (m *Model) renderDisableTypeChoiceBar() string {
	disableStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Bold(true)
	promptStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4"))
	keyStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4")).Bold(true)
	dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#9CA3AF"))

	return disableStyle.Render("DISABLE ") +
		promptStyle.Render("What to disable? ") +
		keyStyle.Render("[a]") +
		dimStyle.Render("ll scenarios  ") +
		keyStyle.Render("[p]") +
		dimStyle.Render("attern (e.g., iam-*, lambda-001)  ") +
		dimStyle.Render("(Esc to cancel)")
}

func (m *Model) renderDisablePatternBar() string {
	disableStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Bold(true)
	promptStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4"))

	return disableStyle.Render("DISABLE ") +
		promptStyle.Render("Enter pattern: ") +
		m.disablePatternInput.View() +
		promptStyle.Render(" (Enter to confirm, Esc to cancel)")
}

// getMissingRequiredConfigs returns human-readable entries for every enabled scenario
// that has at least one required config key with no value set.
func (m *Model) getMissingRequiredConfigs() []string {
	if m.config == nil {
		return nil
	}
	var missing []string
	for _, item := range m.scenariosPane.GetItems() {
		if !item.Enabled || !item.Scenario.HasConfig() {
			continue
		}
		for _, cfgKey := range item.Scenario.Config {
			if !cfgKey.Required {
				continue
			}
			val, _ := m.config.Active().GetScenarioConfig(item.Scenario.Name, cfgKey.Key)
			if val == "" {
				missing = append(missing, fmt.Sprintf("%s: %q", item.Scenario.Name, cfgKey.Key))
			}
		}
	}
	return missing
}

// startEditScenarioConfig begins inline editing of per-scenario config keys.
// Called when the user presses 'e' while the details pane is focused and the
// selected scenario declares at least one config key.
func (m *Model) startEditScenarioConfig(s *scenarios.Scenario) (tea.Model, tea.Cmd) {
	if !s.HasConfig() {
		return m, nil
	}
	m.editingScenarioConfig = true
	m.editingConfigKeyIndex = 0
	m.editingConfigScenarioName = s.Name

	// Pre-fill with the current value so the user can see and edit it
	currentVal := ""
	if m.config != nil {
		currentVal, _ = m.config.Active().GetScenarioConfig(s.Name, s.Config[0].Key)
	}
	m.scenarioConfigInput.SetValue(currentVal)
	m.scenarioConfigInput.CursorEnd()
	m.scenarioConfigInput.Focus()
	return m, textinput.Blink
}

// saveScenarioConfigValue persists the current input value, then advances to the
// next config key.  When all keys have been edited, exits editing mode.
func (m *Model) saveScenarioConfigValue() (tea.Model, tea.Cmd) {
	s := m.findScenarioByName(m.editingConfigScenarioName)
	if s == nil || m.editingConfigKeyIndex >= len(s.Config) {
		m.editingScenarioConfig = false
		m.scenarioConfigInput.Blur()
		return m, nil
	}

	cfgKey := s.Config[m.editingConfigKeyIndex].Key
	value := m.scenarioConfigInput.Value()

	if m.config != nil {
		m.config.Active().SetScenarioConfig(m.editingConfigScenarioName, cfgKey, value)
		if err := m.config.Save(); err != nil {
			m.editingScenarioConfig = false
			m.scenarioConfigInput.Blur()
			m.overlay.Show(OverlayError, "Config Error", fmt.Sprintf("Failed to save config: %v", err))
			return m, nil
		}
		if err := m.config.Active().SyncTFVars(m.paths.TerraformDir); err != nil {
			m.editingScenarioConfig = false
			m.scenarioConfigInput.Blur()
			m.overlay.Show(OverlayError, "Config Error", fmt.Sprintf("Failed to sync tfvars: %v", err))
			return m, nil
		}
	}

	m.editingConfigKeyIndex++
	if m.editingConfigKeyIndex >= len(s.Config) {
		// All keys done — exit editing mode and refresh details
		m.editingScenarioConfig = false
		m.scenarioConfigInput.Blur()
		m.editingConfigKeyIndex = 0
		m.updateDetails()
		return m, nil
	}

	// Advance to the next key
	nextKey := s.Config[m.editingConfigKeyIndex].Key
	nextVal := ""
	if m.config != nil {
		nextVal, _ = m.config.Active().GetScenarioConfig(m.editingConfigScenarioName, nextKey)
	}
	m.scenarioConfigInput.SetValue(nextVal)
	m.scenarioConfigInput.CursorEnd()
	return m, textinput.Blink
}

// findScenarioByName returns the scenario with the given name from m.allScenarios.
func (m *Model) findScenarioByName(name string) *scenarios.Scenario {
	for _, s := range m.allScenarios {
		if s.Name == name {
			return s
		}
	}
	return nil
}

// renderScenarioConfigEditBar renders the bottom-bar prompt for per-scenario config editing.
func (m *Model) renderScenarioConfigEditBar() string {
	s := m.findScenarioByName(m.editingConfigScenarioName)
	if s == nil || m.editingConfigKeyIndex >= len(s.Config) {
		return ""
	}

	cfgKey := s.Config[m.editingConfigKeyIndex]
	labelStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4")).Bold(true)
	dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#9CA3AF"))

	label := fmt.Sprintf("Config %s / %s: ", m.editingConfigScenarioName, cfgKey.Key)
	var hint string
	if len(s.Config) > 1 {
		hint = dimStyle.Render(fmt.Sprintf("  (%d/%d — Enter to save, Esc to cancel)", m.editingConfigKeyIndex+1, len(s.Config)))
	} else {
		hint = dimStyle.Render("  (Enter to save, Esc to cancel)")
	}

	return labelStyle.Render(label) + m.scenarioConfigInput.View() + hint
}

// parseCostString extracts the numeric value from a cost string like "$8/mo"
func parseCostString(cost string) float64 {
	if cost == "" {
		return 0
	}
	// Remove $ prefix and /mo suffix
	cost = strings.TrimPrefix(cost, "$")
	cost = strings.TrimSuffix(cost, "/mo")
	cost = strings.TrimSuffix(cost, "/month")

	// Parse as float
	var value float64
	_, _ = fmt.Sscanf(cost, "%f", &value)
	return value
}

// calculateRunningCost calculates the total monthly cost of deployed scenarios
func (m *Model) calculateRunningCost() float64 {
	var total float64
	items := m.scenariosPane.GetItems()
	for _, item := range items {
		// Only count scenarios that are both enabled AND deployed (actually running)
		if item.Enabled && item.Deployed {
			total += parseCostString(item.Scenario.CostEstimate)
		}
	}
	return total
}

// updateRunningCost recalculates and updates the running cost in the info pane
func (m *Model) updateRunningCost() {
	cost := m.calculateRunningCost()
	m.info.SetRunningCost(cost)
}

// updateDemoActiveCount recalculates and updates the demo-active count in the info and actions panes
func (m *Model) updateDemoActiveCount() {
	count := m.scenariosPane.GetDemoActiveCount()
	m.info.SetDemoActiveCount(count)
	m.actions.SetDemoActiveCount(count)
}
