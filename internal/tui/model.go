package tui

import (
	"bufio"
	"fmt"
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
	PaneCategories
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
	environment   *EnvironmentPane
	categories    *CategoriesPane
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
	err         error

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

	m := &Model{
		paths:         paths,
		styles:        styles,
		keys:          keys,
		environment:   NewEnvironmentPane(styles),
		categories:    NewCategoriesPane(styles),
		scenariosPane: NewScenariosPane(styles),
		details:       NewDetailsPane(styles),
		actions:       NewActionsPane(styles),
		overlay:       NewOverlay(styles),
		filterInput:   ti,
		currentPane:   PaneScenarios,
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
	var resources map[string][]string

	if runner.IsInitialized() {
		deployedModules := runner.GetDeployedModules()
		for _, s := range allScenarios {
			outputName := strings.TrimPrefix(s.Terraform.VariableName, "enable_")
			if deployedModules[outputName] {
				deployed[s.Terraform.VariableName] = true
			}
		}

		// Get outputs for credentials
		outputJSON, err := runner.OutputJSON()
		if err == nil && outputJSON != "" {
			outputs, _ = terraform.ParseOutputs(outputJSON)
		}

		// Get resources for all modules
		resources, _ = runner.GetAllModuleResources()
	}

	return scenariosLoadedMsg{
		scenarios: allScenarios,
		enabled:   enabled,
		deployed:  deployed,
		outputs:   outputs,
		resources: resources,
	}
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

		// Build categories
		m.updateCategories()

		// Cache outputs and resources, then update details for initially selected scenario
		m.cachedOutputs = msg.outputs
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
		// Reload scenarios to refresh deployment state
		return m, m.loadScenarios

	case errMsg:
		m.err = msg.err
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
	// Handle overlay - Esc dismisses (and cancels if running)
	if m.overlay.IsVisible() {
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
		m.updateCategories()
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
	}

	// Pane-specific keys
	switch m.currentPane {
	case PaneCategories:
		switch {
		case key.Matches(msg, m.keys.Up):
			m.categories.MoveUp()
			m.scenariosPane.SetCategoryFilter(m.categories.Selected())
			m.updateDetailsForSelected()
		case key.Matches(msg, m.keys.Down):
			m.categories.MoveDown()
			m.scenariosPane.SetCategoryFilter(m.categories.Selected())
			m.updateDetailsForSelected()
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
	}

	return m, nil
}

func (m *Model) nextPane() {
	m.currentPane = (m.currentPane + 1) % 4
	m.updatePaneFocus()
}

func (m *Model) prevPane() {
	m.currentPane = (m.currentPane + 3) % 4
	m.updatePaneFocus()
}

func (m *Model) updatePaneFocus() {
	m.environment.SetFocused(m.currentPane == PaneEnvironment)
	m.categories.SetFocused(m.currentPane == PaneCategories)
	m.scenariosPane.SetFocused(m.currentPane == PaneScenarios)
	m.details.SetFocused(m.currentPane == PaneDetails)
}

func (m *Model) updateCategories() {
	predefined := PredefinedCategories()
	counts := make(map[string]int)
	enabledCounts := make(map[string]int)

	for _, s := range m.allScenarios {
		cat := s.CategoryShort()
		counts[cat]++
	}

	// Count enabled
	if m.tfvars != nil {
		enabled, _ := m.tfvars.GetEnabledScenarios()
		for _, s := range m.allScenarios {
			if enabled[s.Terraform.VariableName] {
				cat := s.CategoryShort()
				enabledCounts[cat]++
			}
		}
	}

	// Build category list
	var categories []Category

	// All category
	totalEnabled := 0
	for _, c := range enabledCounts {
		totalEnabled += c
	}
	categories = append(categories, Category{
		Name:         "All",
		Total:        len(m.allScenarios),
		Enabled:      totalEnabled,
		DisplayLabel: CategoryDisplayName("All"),
	})

	// Predefined categories
	for _, name := range predefined[1:] {
		if counts[name] > 0 {
			categories = append(categories, Category{
				Name:         name,
				Total:        counts[name],
				Enabled:      enabledCounts[name],
				DisplayLabel: CategoryDisplayName(name),
			})
		}
	}

	m.categories.SetCategories(categories)
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

	// Update categories
	m.updateCategories()

	return nil
}

func (m *Model) runDeploy() tea.Cmd {
	enabled := m.scenariosPane.GetEnabledCount()
	if enabled == 0 {
		m.overlay.Show(OverlayError, "Deploy", "No scenarios enabled.\n\nUse [space] to enable scenarios first.")
		return nil
	}

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
	// Calculate pane sizes as percentages: left 20%, center 30%, right 50%
	leftWidth := m.termWidth * 20 / 100
	centerWidth := m.termWidth * 30 / 100
	rightWidth := m.termWidth - leftWidth - centerWidth

	// Ensure minimum widths
	if leftWidth < 20 {
		leftWidth = 20
	}
	if centerWidth < 25 {
		centerWidth = 25
	}
	if rightWidth < 30 {
		rightWidth = 30
	}

	// Main content height (leave room for status bar)
	mainHeight := m.termHeight - 1

	// Environment pane height (fixed, compact)
	envHeight := 8
	if m.config != nil && m.config.IsMultiAccountMode() {
		envHeight = 12
	}

	// Actions pane height (fixed, shows shortcuts)
	actionsHeight := 14

	// Categories pane takes remaining height on left
	catHeight := mainHeight - envHeight - actionsHeight
	if catHeight < 5 {
		catHeight = 5
	}

	// Set sizes
	m.environment.SetSize(leftWidth, envHeight)
	m.categories.SetSize(leftWidth, catHeight)
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
		m.environment.View(),
		m.categories.View(),
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

	// Build status text with colors
	var parts []string
	parts = append(parts, enabledStyle.Render(fmt.Sprintf("%d enabled", enabledCount)))
	parts = append(parts, separatorStyle.Render(" · "))
	parts = append(parts, deployedStyle.Render(fmt.Sprintf("%d deployed", deployedCount)))

	// Check if deploy is needed
	if m.scenariosPane.HasPendingChanges() {
		parts = append(parts, separatorStyle.Render(" · "))
		parts = append(parts, pendingStyle.Render("[d] to deploy changes"))
	}

	statusText := strings.Join(parts, "")

	return m.styles.StatusBar.Width(m.termWidth).Render(statusText)
}

func (m *Model) renderFilterBar() string {
	return m.styles.FilterPrompt.Render("/") + m.filterInput.View()
}
