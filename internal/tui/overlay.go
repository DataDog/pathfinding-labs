package tui

import (
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
)

// Overlay represents a floating overlay panel
type Overlay struct {
	styles      *Styles
	overlayType OverlayType
	title       string
	content     []string
	isRunning   bool
	width       int
	height      int
	scroll      int
}

// NewOverlay creates a new overlay
func NewOverlay(styles *Styles) *Overlay {
	return &Overlay{
		styles: styles,
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
	maxScroll := len(o.content) - o.visibleLines()
	if maxScroll < 0 {
		maxScroll = 0
	}
	if o.scroll < maxScroll {
		o.scroll++
	}
}

func (o *Overlay) scrollToBottom() {
	maxScroll := len(o.content) - o.visibleLines()
	if maxScroll < 0 {
		maxScroll = 0
	}
	o.scroll = maxScroll
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

	// Calculate overlay size (80% of terminal, max 80x40)
	overlayWidth := termWidth * 80 / 100
	if overlayWidth > 100 {
		overlayWidth = 100
	}
	if overlayWidth < 40 {
		overlayWidth = 40
	}

	overlayHeight := termHeight * 70 / 100
	if overlayHeight > 40 {
		overlayHeight = 40
	}
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

	start := o.scroll
	end := start + visibleLines
	if end > len(o.content) {
		end = len(o.content)
	}

	for i := start; i < end; i++ {
		line := o.content[i]
		// Truncate long lines
		if len(line) > contentWidth {
			line = line[:contentWidth-3] + "..."
		}
		sb.WriteString(o.styles.OverlayText.Render(line))
		sb.WriteString("\n")
	}

	// Padding if content is short
	for i := end - start; i < visibleLines; i++ {
		sb.WriteString("\n")
	}

	// Footer
	sb.WriteString("\n")
	if o.isRunning {
		sb.WriteString(o.styles.OverlayDimmed.Render("Running... (j/k scroll, Esc cancel)"))
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

// RenderHelpOverlay renders the help content
func (o *Overlay) RenderHelpOverlay() string {
	var sb strings.Builder

	sections := []struct {
		title string
		keys  [][]string
	}{
		{
			title: "Navigation",
			keys: [][]string{
				{"j/k, ↑/↓", "Move cursor up/down"},
				{"h/←", "Collapse category"},
				{"l/→", "Expand category"},
				{"pgup/pgdn", "Page up/down"},
				{"g/G", "First/last item"},
				{"Tab", "Switch panes"},
			},
		},
		{
			title: "Actions",
			keys: [][]string{
				{"Space", "Toggle enable/disable"},
				{"d", "Deploy enabled scenarios"},
				{"p", "Plan (preview changes)"},
				{"r", "Run demo (deployed only)"},
				{"c", "Cleanup (deployed only)"},
			},
		},
		{
			title: "Filter & Help",
			keys: [][]string{
				{"/", "Filter scenarios"},
				{".", "Toggle enabled only"},
				{"Esc", "Clear filter / dismiss"},
				{"?", "Toggle help"},
				{"q", "Quit"},
			},
		},
	}

	for i, section := range sections {
		if i > 0 {
			sb.WriteString("\n")
		}
		sb.WriteString(o.styles.DetailSection.Render(section.title))
		sb.WriteString("\n")

		for _, kv := range section.keys {
			key := o.styles.HelpKey.Render(kv[0])
			desc := o.styles.HelpDesc.Render(kv[1])
			sb.WriteString("  ")
			sb.WriteString(key)
			sb.WriteString("  ")
			sb.WriteString(desc)
			sb.WriteString("\n")
		}
	}

	return sb.String()
}
