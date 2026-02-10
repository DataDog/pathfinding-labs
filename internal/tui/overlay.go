package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// OverlayType represents the type of overlay being displayed
type OverlayType int

const (
	OverlayNone OverlayType = iota
	OverlayHelp
	OverlayTerraform
	OverlayDemo
	OverlayError
	OverlayConfirm
	OverlayConfig
	OverlayInfo
)

// Overlay represents a floating overlay panel
type Overlay struct {
	styles       *Styles
	overlayType  OverlayType
	title        string
	content      []string
	isRunning    bool
	width        int
	height       int
	scroll       int
	contentWidth int // cached content width for scroll calculations
}

// NewOverlay creates a new overlay
func NewOverlay(styles *Styles) *Overlay {
	return &Overlay{
		styles:       styles,
		contentWidth: 80, // reasonable default until View() sets actual width
	}
}

// Show displays the overlay with the given content
func (o *Overlay) Show(overlayType OverlayType, title string, content string) {
	o.overlayType = overlayType
	o.title = title
	o.content = strings.Split(content, "\n")
	o.isRunning = false
	o.scroll = 0
}

// ShowRunning displays the overlay in a running state
func (o *Overlay) ShowRunning(overlayType OverlayType, title string) {
	o.overlayType = overlayType
	o.title = title
	o.content = []string{"Running..."}
	o.isRunning = true
	o.scroll = 0
}

// AppendContent adds more content to the overlay
func (o *Overlay) AppendContent(line string) {
	o.content = append(o.content, line)
	// Auto-scroll to bottom when running
	if o.isRunning {
		o.scrollToBottom()
	}
}

// SetContent replaces all content
func (o *Overlay) SetContent(content string) {
	o.content = strings.Split(content, "\n")
}

// SetComplete marks the overlay as no longer running
func (o *Overlay) SetComplete() {
	o.isRunning = false
}

// Hide hides the overlay
func (o *Overlay) Hide() {
	o.overlayType = OverlayNone
	o.content = nil
	o.title = ""
	o.isRunning = false
}

// IsVisible returns whether the overlay is visible
func (o *Overlay) IsVisible() bool {
	return o.overlayType != OverlayNone
}

// Type returns the current overlay type
func (o *Overlay) Type() OverlayType {
	return o.overlayType
}

// IsRunning returns whether the overlay is in a running state
func (o *Overlay) IsRunning() bool {
	return o.isRunning
}

// SetSize sets the overlay dimensions
func (o *Overlay) SetSize(width, height int) {
	o.width = width
	o.height = height
}

// ScrollUp scrolls the overlay content up
func (o *Overlay) ScrollUp() {
	if o.scroll > 0 {
		o.scroll--
	}
}

// ScrollDown scrolls the overlay content down
func (o *Overlay) ScrollDown() {
	maxScroll := o.wrappedLineCount() - o.visibleLines()
	if maxScroll < 0 {
		maxScroll = 0
	}
	if o.scroll < maxScroll {
		o.scroll++
	}
}

func (o *Overlay) scrollToBottom() {
	maxScroll := o.wrappedLineCount() - o.visibleLines()
	if maxScroll < 0 {
		maxScroll = 0
	}
	o.scroll = maxScroll
}

// wrappedLineCount returns the total number of lines after wrapping
func (o *Overlay) wrappedLineCount() int {
	if o.contentWidth <= 0 {
		return len(o.content)
	}
	count := 0
	for _, line := range o.content {
		wrapped := wrapWithStyle(line, o.contentWidth)
		count += len(wrapped)
	}
	return count
}

// ScrollToBottom scrolls the overlay content to the bottom
func (o *Overlay) ScrollToBottom() {
	o.scrollToBottom()
}

func (o *Overlay) visibleLines() int {
	// Account for title, borders, and footer
	return o.height - 8
}

// View renders the overlay
func (o *Overlay) View(termWidth, termHeight int) string {
	if !o.IsVisible() {
		return ""
	}

	// Calculate overlay size (95% width, 90% height - fixed)
	overlayWidth := termWidth * 95 / 100
	if overlayWidth < 40 {
		overlayWidth = 40
	}

	overlayHeight := termHeight * 90 / 100
	if overlayHeight < 15 {
		overlayHeight = 15
	}

	o.width = overlayWidth
	o.height = overlayHeight

	var sb strings.Builder

	// Title
	sb.WriteString(o.styles.OverlayTitle.Render(o.title))
	sb.WriteString("\n\n")

	// Content area
	visibleLines := o.visibleLines()
	contentWidth := overlayWidth - 6
	o.contentWidth = contentWidth // Store for scroll calculations

	// Wrap all content lines to get the actual displayable lines
	var wrappedLines []string
	for _, line := range o.content {
		wrapped := wrapWithStyle(line, contentWidth)
		wrappedLines = append(wrappedLines, wrapped...)
	}

	// Calculate scroll bounds based on wrapped content
	start := o.scroll
	if start > len(wrappedLines) {
		start = len(wrappedLines)
	}
	end := start + visibleLines
	if end > len(wrappedLines) {
		end = len(wrappedLines)
	}

	for i := start; i < end; i++ {
		sb.WriteString(o.styles.OverlayText.Render(wrappedLines[i]))
		sb.WriteString("\n")
	}

	// Padding if content is short
	for i := end - start; i < visibleLines; i++ {
		sb.WriteString("\n")
	}

	// Footer
	sb.WriteString("\n")
	if o.isRunning {
		sb.WriteString(o.styles.OverlayDimmed.Render("Running... (↑/↓ scroll, Esc cancel)"))
	} else {
		sb.WriteString(o.styles.OverlayDimmed.Render("[Press Esc to close]"))
	}

	// Apply overlay style
	overlayStyle := o.styles.Overlay.
		Width(overlayWidth).
		Height(overlayHeight)

	content := overlayStyle.Render(sb.String())

	// Center the overlay
	return lipgloss.Place(
		termWidth,
		termHeight,
		lipgloss.Center,
		lipgloss.Center,
		content,
	)
}

// wrapWithStyle wraps a string to maxWidth visual characters,
// preserving ANSI escape codes and returning multiple lines if needed
func wrapWithStyle(s string, maxWidth int) []string {
	if maxWidth <= 0 {
		return []string{s}
	}

	// Handle empty string
	if s == "" {
		return []string{""}
	}

	visualWidth := lipgloss.Width(s)
	if visualWidth <= maxWidth {
		return []string{s}
	}

	// Need to wrap - walk through and count visual width
	var lines []string
	var currentLine strings.Builder
	var visualCount int
	inEscape := false
	var activeEscapes strings.Builder // Track active ANSI codes for continuation

	for _, r := range s {
		if r == '\x1b' {
			inEscape = true
			currentLine.WriteRune(r)
			activeEscapes.WriteRune(r)
			continue
		}

		if inEscape {
			currentLine.WriteRune(r)
			activeEscapes.WriteRune(r)
			if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') {
				inEscape = false
				// Check if this is a reset code
				escapeStr := activeEscapes.String()
				if escapeStr == "\x1b[0m" || escapeStr == "\x1b[m" {
					activeEscapes.Reset()
				}
			}
			continue
		}

		// Regular character - check if we need to wrap
		if visualCount >= maxWidth {
			// Close current line with reset and start new line
			currentLine.WriteString("\x1b[0m")
			lines = append(lines, currentLine.String())
			currentLine.Reset()
			visualCount = 0
			// Re-apply active escapes to new line
			if activeEscapes.Len() > 0 {
				currentLine.WriteString(activeEscapes.String())
			}
		}

		currentLine.WriteRune(r)
		visualCount++
	}

	// Add the last line if there's content
	if currentLine.Len() > 0 {
		lines = append(lines, currentLine.String())
	}

	return lines
}

// RenderHelpOverlay renders the help content as columns (or single column if too narrow)
func (o *Overlay) RenderHelpOverlay() string {
	sections := []struct {
		title string
		keys  [][]string
	}{
		{
			title: "Navigation",
			keys: [][]string{
				{"↑/↓", "Move cursor"},
				{"←", "Collapse scenario section"},
				{"→", "Expand scenario section"},
				{"pgup/pgdn", "Page up/down"},
				{"Tab", "Switch panes"},
			},
		},
		{
			title: "Actions",
			keys: [][]string{
				{"Space", "Toggle if a scenario is enabled/disabled"},
				{"e", "Enable scenarios (all or by pattern)"},
				{"d", "Deploy scenarios and environments"},
				{"p", "Plan"},
				{"r", "Run attack demo"},
				{"c", "Cleanup attack demo"},
				{"D", "Destroy scenarios"},
				{"s", "Settings"},
			},
		},
		{
			title: "Filtering and other",
			keys: [][]string{
				{"/", "Filter scenarios by prefix"},
				{".", "Show enabled scenarios only"},
				{"Esc", "Dismiss"},
				{"?", "Help"},
				{"q", "Quit"},
			},
		},
	}

	columnStyle := lipgloss.NewStyle().Padding(0, 2)

	// First, render columns to measure total width
	var columns []string
	for _, section := range sections {
		var sb strings.Builder
		sb.WriteString(o.styles.DetailSection.Render(section.title))
		sb.WriteString("\n\n")

		for _, kv := range section.keys {
			key := o.styles.HelpKey.Render(fmt.Sprintf("%-10s", kv[0]))
			desc := o.styles.HelpDesc.Render(kv[1])
			sb.WriteString(key)
			sb.WriteString(" ")
			sb.WriteString(desc)
			sb.WriteString("\n")
		}

		columns = append(columns, columnStyle.Render(sb.String()))
	}

	// Calculate total width of columns
	columnsJoined := lipgloss.JoinHorizontal(lipgloss.Top, columns...)
	totalWidth := lipgloss.Width(columnsJoined)

	// If columns fit, use column layout
	availableWidth := o.width - 6 // account for padding/borders
	if totalWidth <= availableWidth {
		return columnsJoined
	}

	// Otherwise, render as single scrollable column
	var sb strings.Builder
	for i, section := range sections {
		if i > 0 {
			sb.WriteString("\n")
		}
		sb.WriteString(o.styles.DetailSection.Render(section.title))
		sb.WriteString("\n")

		for _, kv := range section.keys {
			key := o.styles.HelpKey.Render(fmt.Sprintf("%-10s", kv[0]))
			desc := o.styles.HelpDesc.Render(kv[1])
			sb.WriteString("  ")
			sb.WriteString(key)
			sb.WriteString(" ")
			sb.WriteString(desc)
			sb.WriteString("\n")
		}
	}

	return sb.String()
}
