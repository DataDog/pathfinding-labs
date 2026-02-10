package tui

import (
	"fmt"
	"strings"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/charmbracelet/lipgloss"
)

// Version can be set at build time via ldflags
var Version = "0.0.1"

// hyperlink creates a clickable terminal hyperlink using OSC 8 escape sequence
func infoHyperlink(url, text string) string {
	return fmt.Sprintf("\x1b]8;;%s\x07%s\x1b]8;;\x07", url, text)
}

// InfoPane displays project information and status
type InfoPane struct {
	styles              *Styles
	config              *config.Config
	terraformDir        string
	devMode             bool
	devModePath         string
	tfInitialized       bool
	totalScenarios      int
	deployedCount       int     // Number of deployed scenarios
	enabledCount        int     // Number of enabled scenarios
	runningCostPerMonth float64 // Aggregate cost of enabled+deployed scenarios
	width               int
	height              int
}

// NewInfoPane creates a new info pane
func NewInfoPane(styles *Styles) *InfoPane {
	return &InfoPane{
		styles: styles,
	}
}

// SetConfig updates the configuration
func (i *InfoPane) SetConfig(cfg *config.Config) {
	i.config = cfg
	if cfg != nil {
		i.devMode = cfg.DevMode
		i.devModePath = cfg.DevModePath
	}
}

// SetTerraformDir sets the terraform directory path
func (i *InfoPane) SetTerraformDir(dir string) {
	i.terraformDir = dir
}

// SetTerraformInitialized sets whether terraform is initialized
func (i *InfoPane) SetTerraformInitialized(initialized bool) {
	i.tfInitialized = initialized
}

// SetTotalScenarios sets the total number of scenarios
func (i *InfoPane) SetTotalScenarios(count int) {
	i.totalScenarios = count
}

// SetDeploymentCounts sets the enabled and deployed scenario counts
func (i *InfoPane) SetDeploymentCounts(enabled, deployed int) {
	i.enabledCount = enabled
	i.deployedCount = deployed
}

// SetRunningCost sets the aggregate monthly cost of deployed scenarios
func (i *InfoPane) SetRunningCost(costPerMonth float64) {
	i.runningCostPerMonth = costPerMonth
}

// SetSize sets the pane dimensions
func (i *InfoPane) SetSize(width, height int) {
	i.width = width
	i.height = height
}

// View renders the info pane
func (i *InfoPane) View() string {
	var sb strings.Builder

	contentWidth := i.width - 4
	if contentWidth < 10 {
		contentWidth = 10
	}

	// Styled ASCII art title box
	titleColor := lipgloss.Color("#06B6D4")  // Cyan
	accentColor := lipgloss.Color("#8B5CF6") // Purple
	dimColor := lipgloss.Color("#6B7280")    // Gray
	boxStyle := lipgloss.NewStyle().Foreground(accentColor)
	titleStyle := lipgloss.NewStyle().Foreground(titleColor).Bold(true)
	dimStyle := lipgloss.NewStyle().Foreground(dimColor)

	// Build the box content - now just title and version
	titleText := "PATHFINDING LABS"
	versionText := fmt.Sprintf("v%s", Version)

	// Find the widest line for box width
	boxWidth := len(titleText)
	if len(versionText) > boxWidth {
		boxWidth = len(versionText)
	}
	boxWidth += 4 // padding
	if boxWidth > contentWidth {
		boxWidth = contentWidth
	}

	// Helper to center text in box
	centerInBox := func(text string, style lipgloss.Style) string {
		padding := (boxWidth - len(text)) / 2
		rightPad := boxWidth - padding - len(text)
		return boxStyle.Render("│") + strings.Repeat(" ", padding) + style.Render(text) + strings.Repeat(" ", rightPad) + boxStyle.Render("│")
	}

	topBorder := boxStyle.Render("╭" + strings.Repeat("─", boxWidth) + "╮")
	bottomBorder := boxStyle.Render("╰" + strings.Repeat("─", boxWidth) + "╯")

	// Build the complete box first
	var boxLines []string
	boxLines = append(boxLines, topBorder)
	boxLines = append(boxLines, centerInBox(titleText, titleStyle))
	boxLines = append(boxLines, centerInBox(versionText, dimStyle))
	boxLines = append(boxLines, bottomBorder)
	box := strings.Join(boxLines, "\n")

	// Center the entire box as one unit
	centerStyle := lipgloss.NewStyle().Width(contentWidth).Align(lipgloss.Center)
	sb.WriteString(centerStyle.Render(box))
	sb.WriteString("\n")

	// Clickable URL centered
	url := "https://pathfinding.cloud/labs"
	linkStyle := lipgloss.NewStyle().Foreground(dimColor)
	clickableLink := infoHyperlink(url, linkStyle.Render(url))
	centeredLink := lipgloss.NewStyle().Width(contentWidth).Align(lipgloss.Center).Render(clickableLink)
	sb.WriteString(centeredLink)
	sb.WriteString("\n")

	// ─── DEPLOYMENT STATUS ────────────────
	dividerStyle := lipgloss.NewStyle().Foreground(dimColor)
	divider := dividerStyle.Render(strings.Repeat("─", contentWidth))
	sb.WriteString(divider)
	sb.WriteString("\n")

	// Deployment stats - more prominent
	labelStyle := lipgloss.NewStyle().Foreground(dimColor)
	valueStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#F3F4F6")) // Light text
	deployedStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#10B981")).Bold(true) // Green for deployed count
	costStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")) // Warning yellow for cost

	// Scenarios deployed: X/Y
	sb.WriteString(labelStyle.Render("Scenarios deployed "))
	sb.WriteString(deployedStyle.Render(fmt.Sprintf("%d", i.deployedCount)))
	sb.WriteString(valueStyle.Render(fmt.Sprintf("/%d", i.totalScenarios)))
	sb.WriteString("\n")

	// Running cost
	if i.runningCostPerMonth > 0 {
		costPerDay := i.runningCostPerMonth / 30
		sb.WriteString(labelStyle.Render("Running cost "))
		sb.WriteString(costStyle.Render(fmt.Sprintf("$%.0f/mo", i.runningCostPerMonth)))
		sb.WriteString(dimStyle.Render(fmt.Sprintf(" ($%.2f/day)", costPerDay)))
		sb.WriteString("\n")
	} else {
		sb.WriteString(labelStyle.Render("Running cost "))
		sb.WriteString(dimStyle.Render("$0/mo"))
		sb.WriteString("\n")
	}

	// ─── CONFIGURATION ────────────────
	sb.WriteString(divider)
	sb.WriteString("\n")

	// Mode - only show when in dev mode
	if i.devMode {
		sb.WriteString(labelStyle.Render("Mode         "))
		sb.WriteString(i.styles.EnvConfigured.Render("dev"))
		sb.WriteString("\n")
	}

	// Terraform status
	sb.WriteString(labelStyle.Render("Terraform    "))
	if i.tfInitialized {
		sb.WriteString(i.styles.EnvConfigured.Render("ready"))
	} else {
		sb.WriteString(i.styles.ScenarioDisabled.Render("not initialized"))
	}
	sb.WriteString("\n")

	// Dev mode path - show below terraform, wrapped if needed
	if i.devMode && i.devModePath != "" {
		sb.WriteString(labelStyle.Render("Path         "))
		wrapped := i.wordWrap(i.devModePath, contentWidth-13, 13) // 13 = len("Path         ")
		sb.WriteString(dimStyle.Render(wrapped))
	}

	return i.wrapInPanel(sb.String())
}

// wordWrap wraps text to fit within width, with optional indentation for continuation lines
func (i *InfoPane) wordWrap(text string, width int, indent int) string {
	if width <= 0 || len(text) <= width {
		return text
	}

	indentStr := strings.Repeat(" ", indent)
	var lines []string
	remaining := text

	// First line uses full width
	if len(remaining) > width {
		lines = append(lines, remaining[:width])
		remaining = remaining[width:]
	} else {
		return remaining
	}

	// Subsequent lines are indented
	for len(remaining) > width {
		lines = append(lines, indentStr+remaining[:width])
		remaining = remaining[width:]
	}
	if len(remaining) > 0 {
		lines = append(lines, indentStr+remaining)
	}

	return strings.Join(lines, "\n")
}

func (i *InfoPane) wrapInPanel(content string) string {
	// Set both width and height to keep the panel size constant
	panelStyle := i.styles.Panel.Width(i.width - 2).Height(i.height - 2)
	return panelStyle.Render(content)
}
