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
	styles           *Styles
	config           *config.Config
	workingDirectory string
	devMode          bool
	tfInitialized    bool
	totalScenarios   int
	width            int
	height           int
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
		i.workingDirectory = cfg.WorkingDirectory
	}
}

// SetTerraformInitialized sets whether terraform is initialized
func (i *InfoPane) SetTerraformInitialized(initialized bool) {
	i.tfInitialized = initialized
}

// SetTotalScenarios sets the total number of scenarios
func (i *InfoPane) SetTotalScenarios(count int) {
	i.totalScenarios = count
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
	titleColor := lipgloss.Color("#06B6D4")    // Cyan
	accentColor := lipgloss.Color("#8B5CF6")   // Purple
	dimColor := lipgloss.Color("#6B7280")      // Gray
	boxStyle := lipgloss.NewStyle().Foreground(accentColor)
	titleStyle := lipgloss.NewStyle().Foreground(titleColor).Bold(true)
	dimStyle := lipgloss.NewStyle().Foreground(dimColor)

	// Build the box content
	titleText := "PATHFINDING LABS"
	versionText := fmt.Sprintf("version: %s", Version)
	labsText := fmt.Sprintf("labs: %d", i.totalScenarios)

	// Find the widest line for box width
	boxWidth := len(titleText)
	if len(versionText) > boxWidth {
		boxWidth = len(versionText)
	}
	if len(labsText) > boxWidth {
		boxWidth = len(labsText)
	}
	boxWidth += 4 // padding
	if boxWidth > contentWidth {
		boxWidth = contentWidth
	}

	// Helper to center text in box
	centerInBox := func(text string, style lipgloss.Style) string {
		padding := (boxWidth - len(text)) / 2
		rightPad := boxWidth - padding - len(text)
		return boxStyle.Render("║") + strings.Repeat(" ", padding) + style.Render(text) + strings.Repeat(" ", rightPad) + boxStyle.Render("║")
	}

	topBorder := "╔" + strings.Repeat("═", boxWidth) + "╗"
	bottomBorder := "╚" + strings.Repeat("═", boxWidth) + "╝"

	// Center the box
	centerStyle := lipgloss.NewStyle().Width(contentWidth).Align(lipgloss.Center)
	sb.WriteString(centerStyle.Render(boxStyle.Render(topBorder)))
	sb.WriteString("\n")
	sb.WriteString(centerStyle.Render(centerInBox(titleText, titleStyle)))
	sb.WriteString("\n")
	sb.WriteString(centerStyle.Render(centerInBox(versionText, dimStyle)))
	sb.WriteString("\n")
	sb.WriteString(centerStyle.Render(centerInBox(labsText, dimStyle)))
	sb.WriteString("\n")
	sb.WriteString(centerStyle.Render(boxStyle.Render(bottomBorder)))
	sb.WriteString("\n")

	// Clickable URL centered
	url := "https://pathfinding.cloud/labs"
	linkStyle := lipgloss.NewStyle().Foreground(dimColor)
	clickableLink := infoHyperlink(url, linkStyle.Render(url))
	centeredLink := lipgloss.NewStyle().Width(contentWidth).Align(lipgloss.Center).Render(clickableLink)
	sb.WriteString(centeredLink)
	sb.WriteString("\n\n")

	// Mode - only show when in dev mode
	if i.devMode {
		sb.WriteString(i.styles.HelpKey.Render("Mode "))
		sb.WriteString(i.styles.EnvConfigured.Render("dev"))
		sb.WriteString("\n")
	}

	// Terraform status
	sb.WriteString(i.styles.HelpKey.Render("Terraform "))
	if i.tfInitialized {
		sb.WriteString(i.styles.EnvConfigured.Render("initialized"))
	} else {
		sb.WriteString(i.styles.ScenarioDisabled.Render("not initialized"))
	}
	sb.WriteString("\n")

	// Working directory (wrapped to multiple lines)
	if i.workingDirectory != "" {
		sb.WriteString(i.styles.HelpKey.Render("Data Directory"))
		sb.WriteString("\n")
		wrapped := i.wordWrap(i.workingDirectory, contentWidth)
		sb.WriteString(i.styles.ScenarioDisabled.Render(wrapped))
	}

	return i.wrapInPanel(sb.String())
}

func (i *InfoPane) wordWrap(text string, width int) string {
	if width <= 0 || len(text) <= width {
		return text
	}

	var lines []string
	for len(text) > width {
		lines = append(lines, text[:width])
		text = text[width:]
	}
	if len(text) > 0 {
		lines = append(lines, text)
	}

	return strings.Join(lines, "\n")
}

func (i *InfoPane) wrapInPanel(content string) string {
	panelStyle := i.styles.Panel.Width(i.width - 2)
	return panelStyle.Render(content)
}
