package tui

import (
	"bufio"
	"fmt"
	"io"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

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
	paths            *repo.Paths
	config           *config.Config
	tfvars           *terraform.TFVars
	tfRunner         *terraform.Runner
	discovery        *scenarios.Discovery
	allScenarios     []*scenarios.Scenario
	cachedOutputs    terraform.Outputs      // Cached terraform outputs for credentials
	cachedResources  map[string][]string    // Cached module name -> ARNs

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

	// Confirmation state for destroy operations
	confirmingDestroy   bool
	destroyType         string // "scenarios" or "all"
	confirmInput        textinput.Model

	// Running command (for cancellation and streaming)
	runningCmd    *exec.Cmd
	cmdScanner    *bufio.Scanner
	cmdWaitDone   chan error
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

type cmdOutputMsg struct {
	line string
}

type cmdDoneMsg struct {
	err error
}

type errMsg struct {
	err error
}

// NewModel creates a new TUI model
func NewModel(paths *repo.Paths) *Model {
	styles := DefaultStyles()
	keys := DefaultKeyMap()

	// Filter input
	ti := textinput.New()
	ti.Placeholder = "Filter scenarios..."
	ti.CharLimit = 50

	// Confirm input for destroy operations
	ci := textinput.New()
	ci.Placeholder = "Type 'destroy' to confirm"
	ci.CharLimit = 10

	m := &Model{
		paths:         paths,
		styles:        styles,
		keys:          keys,
		info:          NewInfoPane(styles),
		environment:   NewEnvironmentPane(styles),
		scenariosPane: NewScenariosPane(styles),
		details:       NewDetailsPane(styles),
		actions:       NewActionsPane(styles),
		overlay:       NewOverlay(styles),
		filterInput:   ti,
		confirmInput:  ci,
		currentPane:   PaneScenarios,
		loading:       true,
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
	// Load config (we don't need to use it here, config is loaded in the Update handler)
	_, err := config.Load(m.paths.ConfigPath)
	if err != nil {
		return errMsg{err}
	}

	// Create terraform components
	tfvars := terraform.NewTFVars(m.paths.TFVarsPath)
	runner := terraform.NewRunner(m.paths.BinPath, m.paths.RepoPath)

	// Discover scenarios
	discovery := scenarios.NewDiscovery(m.paths.ScenariosPath())
	allScenarios, err := discovery.DiscoverAll()
	if err != nil {
		return errMsg{err}
	}

	// Get enabled status
	enabled, err := tfvars.GetEnabledScenarios()
	if err != nil {
		enabled = make(map[string]bool)
	}

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
		cfg, _ := config.Load(m.paths.ConfigPath)
		m.config = cfg
		m.tfvars = terraform.NewTFVars(m.paths.TFVarsPath)
		m.tfRunner = terraform.NewRunner(m.paths.BinPath, m.paths.RepoPath)
		m.discovery = scenarios.NewDiscovery(m.paths.ScenariosPath())
		m.allScenarios = msg.scenarios

		// Recalculate layout now that config is available
		m.updateLayout()

		// Update environment pane
		m.environment.SetConfig(cfg)

		// Load enabled states for environments
		if m.tfvars != nil {
			prodEnabled, devEnabled, opsEnabled, _ := m.tfvars.GetEnabledEnvironments()
			m.environment.SetEnabledStatus(prodEnabled, devEnabled, opsEnabled)
		}

		// Load deployed states for environments
		if m.tfRunner != nil && m.tfRunner.IsInitialized() {
			deployed := m.tfRunner.GetDeployedModules()
			m.environment.SetDeploymentStatus(
				deployed["prod_environment"],
				deployed["dev_environment"],
				deployed["ops_environment"],
			)
		}

		// Build scenario items
		var items []ScenarioItem
		for _, s := range msg.scenarios {
			items = append(items, ScenarioItem{
				Scenario: s,
				Enabled:  msg.enabled[s.Terraform.VariableName],
				Deployed: msg.deployed[s.Terraform.VariableName],
			})
		}
		m.scenariosPane.SetScenarios(items)

		// Update info pane
		m.info.SetConfig(cfg)
		m.info.SetTotalScenarios(len(msg.scenarios))
		if m.tfRunner != nil {
			m.info.SetTerraformInitialized(m.tfRunner.IsInitialized())
		}

		// Cache outputs, then update details for initially selected scenario
		m.cachedOutputs = msg.outputs
		m.cachedResources = nil // Will be populated async
		m.updateDetails()

		// Set derived account IDs from terraform outputs
		if msg.outputs != nil {
			prodID, devID, opsID := msg.outputs.GetAccountIDs()
			m.environment.SetDerivedAccountIDs(prodID, devID, opsID)
		}

		// Done loading (UI is ready, resources will load in background)
		m.loading = false
		m.scenariosPane.SetLoading(false)
		m.environment.SetLoading(false)

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
		} else {
			m.overlay.AppendContent("\n[Done - press Esc to close]")
		}
		// Ensure the done message is visible
		m.overlay.ScrollToBottom()
		// Reload scenarios to refresh deployment state
		return m, m.loadScenarios

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
				m.runningCmd.Process.Kill()
				m.runningCmd = nil
			}
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

	case key.Matches(msg, m.keys.DestroyScenarios):
		return m, m.showDestroyConfirmation("scenarios")

	case key.Matches(msg, m.keys.DestroyAll):
		return m, m.showDestroyConfirmation("all")

	case key.Matches(msg, m.keys.Config):
		m.showConfig()
		return m, nil
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
func (m *Model) toggleEnvironment() tea.Cmd {
	envName, enabled := m.environment.Toggle()
	if envName == "" || m.tfvars == nil {
		return nil
	}

	// Update tfvars
	err := m.tfvars.SetEnvironmentEnabled(envName, enabled)
	if err != nil {
		m.err = err
	}

	// Update actions pane
	m.updateEnvironmentActions()

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
		m.details.SetScenario(nil, false, false)
		m.details.ClearCredentials()
		m.details.ClearResources()
		m.actions.SetScenario(nil, false, false)
		return
	}

	m.details.SetScenario(selected.Scenario, selected.Enabled, selected.Deployed)
	m.actions.SetScenario(selected.Scenario, selected.Enabled, selected.Deployed)

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
}

func (m *Model) updateDetailsForSelected() {
	// Use cached outputs - no need to re-fetch on every navigation
	m.updateDetails()
}

func (m *Model) toggleSelected() tea.Cmd {
	scenario := m.scenariosPane.Toggle()
	if scenario == nil || m.tfvars == nil {
		return nil
	}

	// Get the new enabled state
	selected := m.scenariosPane.Selected()
	if selected == nil {
		return nil
	}

	// Update tfvars
	err := m.tfvars.SetScenarioEnabled(scenario.Terraform.VariableName, selected.Enabled)
	if err != nil {
		m.err = err
	}

	return nil
}

func (m *Model) runDeploy() tea.Cmd {
	m.overlay.ShowRunning(OverlayTerraform, "Deploy")
	cmd := exec.Command("bash", "-c", fmt.Sprintf("cd %s && terraform init && terraform apply -auto-approve", m.paths.RepoPath))
	return m.runCommandStreaming(cmd)
}

func (m *Model) runPlan() tea.Cmd {
	m.overlay.ShowRunning(OverlayTerraform, "Plan")
	cmd := exec.Command("bash", "-c", fmt.Sprintf("cd %s && terraform init && terraform plan", m.paths.RepoPath))
	return m.runCommandStreaming(cmd)
}

func (m *Model) runDemo() tea.Cmd {
	selected := m.scenariosPane.Selected()
	if selected == nil || !selected.Deployed {
		m.overlay.Show(OverlayError, "Run Demo", "Scenario must be deployed first.\n\nUse [d] to deploy enabled scenarios.")
		return nil
	}

	if !selected.Scenario.HasDemo() {
		m.overlay.Show(OverlayError, "Run Demo", "No demo script available for this scenario.")
		return nil
	}

	m.overlay.ShowRunning(OverlayDemo, fmt.Sprintf("Demo: %s", selected.Scenario.UniqueID()))
	demoPath := selected.Scenario.DemoPath()
	cmd := exec.Command("bash", demoPath)
	cmd.Dir = filepath.Dir(demoPath)
	return m.runCommandStreaming(cmd)
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

	m.overlay.ShowRunning(OverlayDemo, fmt.Sprintf("Cleanup: %s", selected.Scenario.UniqueID()))
	cleanupPath := selected.Scenario.CleanupPath()
	cmd := exec.Command("bash", cleanupPath)
	cmd.Dir = filepath.Dir(cleanupPath)
	return m.runCommandStreaming(cmd)
}

func (m *Model) showDestroyConfirmation(destroyType string) tea.Cmd {
	// Validate there's something to destroy
	if destroyType == "scenarios" {
		enabledCount := 0
		for _, s := range m.allScenarios {
			enabled, _ := m.tfvars.GetEnabledScenarios()
			if enabled[s.Terraform.VariableName] {
				enabledCount++
			}
		}
		if enabledCount == 0 {
			m.overlay.Show(OverlayError, "Destroy Scenarios", "No scenarios are currently enabled.")
			return nil
		}
	} else if destroyType == "all" {
		if m.tfRunner == nil || !m.tfRunner.IsInitialized() {
			m.overlay.Show(OverlayError, "Destroy All", "Terraform is not initialized. Nothing to destroy.")
			return nil
		}
		resources, err := m.tfRunner.StateList()
		if err != nil || len(resources) == 0 {
			m.overlay.Show(OverlayError, "Destroy All", "No resources found. Nothing to destroy.")
			return nil
		}
	}

	// Show confirmation prompt
	m.confirmingDestroy = true
	m.destroyType = destroyType
	m.confirmInput.SetValue("")
	m.confirmInput.Focus()
	return textinput.Blink
}

func (m *Model) executeDestroyScenarios() tea.Cmd {
	// Disable all enabled scenarios first
	for _, s := range m.allScenarios {
		enabled, _ := m.tfvars.GetEnabledScenarios()
		if enabled[s.Terraform.VariableName] {
			m.tfvars.SetScenarioEnabled(s.Terraform.VariableName, false)
		}
	}

	// Refresh the scenarios pane to show disabled state
	items := m.scenariosPane.GetItems()
	for i := range items {
		items[i].Enabled = false
	}
	m.scenariosPane.SetScenarios(items)

	m.overlay.ShowRunning(OverlayTerraform, "Destroy Scenarios")
	cmd := exec.Command("bash", "-c", fmt.Sprintf("cd %s && terraform apply -auto-approve", m.paths.RepoPath))
	return m.runCommandStreaming(cmd)
}

func (m *Model) executeDestroyAll() tea.Cmd {
	m.overlay.ShowRunning(OverlayTerraform, "Destroy All")
	cmd := exec.Command("bash", "-c", fmt.Sprintf("cd %s && terraform destroy -auto-approve", m.paths.RepoPath))
	return m.runCommandStreaming(cmd)
}

func (m *Model) showConfig() {
	m.overlay.Show(OverlayConfig, "Settings", m.renderSettingsMenu())
}

func (m *Model) renderSettingsMenu() string {
	var sb strings.Builder

	// Get environment states
	prodEnabled, devEnabled, opsEnabled, _ := m.tfvars.GetEnabledEnvironments()
	deployed := make(map[string]bool)
	if m.tfRunner != nil && m.tfRunner.IsInitialized() {
		deployed = m.tfRunner.GetDeployedModules()
	}
	prodDeployed := deployed["prod_environment"]
	devDeployed := deployed["dev_environment"]
	opsDeployed := deployed["ops_environment"]

	sb.WriteString("AWS Profiles\n")
	sb.WriteString("────────────────────────────────────────\n\n")

	// Prod
	sb.WriteString(fmt.Sprintf("  [1] prod:  %s", m.valueOrNotSet(m.config.ProdProfile)))
	sb.WriteString(m.envStatusSuffix(prodEnabled, prodDeployed))
	sb.WriteString("\n")

	// Dev
	sb.WriteString(fmt.Sprintf("  [2] dev:   %s", m.valueOrNotSet(m.config.DevProfile)))
	sb.WriteString(m.envStatusSuffix(devEnabled, devDeployed))
	sb.WriteString("\n")

	// Ops
	sb.WriteString(fmt.Sprintf("  [3] ops:   %s", m.valueOrNotSet(m.config.OpsProfile)))
	sb.WriteString(m.envStatusSuffix(opsEnabled, opsDeployed))
	sb.WriteString("\n")

	sb.WriteString("\n────────────────────────────────────────\n")
	sb.WriteString("Press 1/2/3 to change a profile\n")
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

func (w *wizardCmd) SetStdin(r io.Reader)  {}
func (w *wizardCmd) SetStdout(wr io.Writer) {}
func (w *wizardCmd) SetStderr(wr io.Writer) {}

// runProfileWizard runs the wizard for a single environment
func (m *Model) runProfileWizard(envName string) tea.Cmd {
	// Get current profile
	var currentProfile string
	switch envName {
	case "prod":
		currentProfile = m.config.ProdProfile
	case "dev":
		currentProfile = m.config.DevProfile
	case "ops":
		currentProfile = m.config.OpsProfile
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

// validateAndSetProfile validates the new profile and sets it if allowed
func (m *Model) validateAndSetProfile(envName, newProfile string) error {
	if newProfile == "" {
		return fmt.Errorf("profile name cannot be empty")
	}

	// Get current state
	var currentProfile string
	var isEnabled bool

	prodEnabled, devEnabled, opsEnabled, _ := m.tfvars.GetEnabledEnvironments()

	switch envName {
	case "prod":
		currentProfile = m.config.ProdProfile
		isEnabled = prodEnabled
	case "dev":
		currentProfile = m.config.DevProfile
		isEnabled = devEnabled
	case "ops":
		currentProfile = m.config.OpsProfile
		isEnabled = opsEnabled
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
		m.config.ProdProfile = newProfile
		m.config.ProdAccountID = newAccountID
	case "dev":
		m.config.DevProfile = newProfile
		m.config.DevAccountID = newAccountID
	case "ops":
		m.config.OpsProfile = newProfile
		m.config.OpsAccountID = newAccountID
	}

	// Save config
	if err := m.config.Save(m.paths.ConfigPath); err != nil {
		return fmt.Errorf("failed to save config: %v", err)
	}

	// Update tfvars
	if err := m.tfvars.SetProfile(envName, newProfile); err != nil {
		return fmt.Errorf("failed to update tfvars: %v", err)
	}

	return nil
}

// getAccountIDForProfile calls AWS to get the account ID for a profile
func (m *Model) getAccountIDForProfile(profile string) (string, error) {
	cmd := exec.Command("aws", "sts", "get-caller-identity", "--profile", profile, "--query", "Account", "--output", "text")
	output, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(output)), nil
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

	// Info pane height (allows for wrapped directory path)
	infoHeight := 12

	// Environment pane height (fixed, compact)
	envHeight := 8
	if m.config != nil && m.config.IsMultiAccountMode() {
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

	// Destroy confirmation overlay
	if m.confirmingDestroy {
		return content + "\n" + m.renderDestroyConfirmBar()
	}

	return content
}

func (m *Model) renderStatusBar() string {
	enabledCount := m.scenariosPane.GetEnabledCount()
	deployedCount := m.scenariosPane.GetDeployedCount()

	// Colors with status bar background
	statusBg := lipgloss.Color("#1F2937")
	enabledStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#06B6D4")).Background(statusBg)  // Cyan
	deployedStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#10B981")).Background(statusBg) // Green
	separatorStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#6B7280")).Background(statusBg) // Gray
	pendingStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Background(statusBg)   // Warning yellow
	keyStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#9CA3AF")).Background(statusBg)       // Light gray for keys
	descStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#6B7280")).Background(statusBg)      // Dim for descriptions

	// Build left side - status counts
	var leftParts []string
	leftParts = append(leftParts, enabledStyle.Render(fmt.Sprintf("%d enabled", enabledCount)))
	leftParts = append(leftParts, separatorStyle.Render(" · "))
	leftParts = append(leftParts, deployedStyle.Render(fmt.Sprintf("%d deployed", deployedCount)))

	// Check if deploy is needed
	if m.scenariosPane.HasPendingChanges() {
		leftParts = append(leftParts, separatorStyle.Render(" · "))
		leftParts = append(leftParts, pendingStyle.Render("[d] to deploy changes"))
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

	paddingStr := lipgloss.NewStyle().Background(statusBg).Render(strings.Repeat(" ", padding))

	return m.styles.StatusBar.Width(m.termWidth).Render(leftText + paddingStr + rightText)
}

func (m *Model) renderFilterBar() string {
	return m.styles.FilterPrompt.Render("/") + m.filterInput.View()
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

	return warningStyle.Render("⚠ "+action+" ⚠ ") +
		promptStyle.Render("Type 'destroy' to confirm: ") +
		m.confirmInput.View() +
		promptStyle.Render(" (Esc to cancel)")
}
