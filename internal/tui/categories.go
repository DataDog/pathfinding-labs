package tui

import (
	"fmt"
	"strings"
)

// Category represents a scenario category with counts
type Category struct {
	Name         string
	Total        int
	Enabled      int
	DisplayLabel string
}

// CategoriesPane displays the category filter list
type CategoriesPane struct {
	styles     *Styles
	categories []Category
	selected   int
	focused    bool
	width      int
	height     int
}

// PredefinedCategories returns the standard category order
func PredefinedCategories() []string {
	return []string{
		"All",
		"self-escalation",
		"one-hop",
		"multi-hop",
		"cross-account",
		"cspm-misconfig",
		"cspm-toxic-combo",
		"tool-testing",
	}
}

// CategoryDisplayName returns a human-readable display name for a category
func CategoryDisplayName(category string) string {
	switch category {
	case "All":
		return "All"
	case "self-escalation":
		return "PrivEsc: Self-Escalation"
	case "one-hop":
		return "PrivEsc: One-Hop"
	case "multi-hop":
		return "PrivEsc: Multi-Hop"
	case "cross-account":
		return "PrivEsc: Cross-Account"
	case "cspm-misconfig":
		return "CSPM: Misconfig"
	case "cspm-toxic-combo":
		return "CSPM: Toxic Combo"
	case "tool-testing":
		return "Tool Testing"
	default:
		return category
	}
}

// NewCategoriesPane creates a new categories pane
func NewCategoriesPane(styles *Styles) *CategoriesPane {
	return &CategoriesPane{
		styles:   styles,
		selected: 0,
	}
}

// SetCategories updates the category list with counts
func (c *CategoriesPane) SetCategories(categories []Category) {
	c.categories = categories
}

// SetFocused sets whether this pane is focused
func (c *CategoriesPane) SetFocused(focused bool) {
	c.focused = focused
}

// SetSize sets the pane dimensions
func (c *CategoriesPane) SetSize(width, height int) {
	c.width = width
	c.height = height
}

// Selected returns the currently selected category name
func (c *CategoriesPane) Selected() string {
	if c.selected >= 0 && c.selected < len(c.categories) {
		return c.categories[c.selected].Name
	}
	return "All"
}

// MoveUp moves the selection up
func (c *CategoriesPane) MoveUp() {
	if c.selected > 0 {
		c.selected--
	}
}

// MoveDown moves the selection down
func (c *CategoriesPane) MoveDown() {
	if c.selected < len(c.categories)-1 {
		c.selected++
	}
}

// View renders the categories pane
func (c *CategoriesPane) View() string {
	var sb strings.Builder

	// Title
	titleStyle := c.styles.PanelTitle.Width(c.width - 4)
	sb.WriteString(titleStyle.Render("Categories"))
	sb.WriteString("\n\n")

	// Categories list
	for i, cat := range c.categories {
		var line string

		// Cursor indicator
		cursor := "  "
		if i == c.selected && c.focused {
			cursor = "> "
		}

		// Count display
		countStr := fmt.Sprintf("(%d)", cat.Total)
		if cat.Enabled > 0 {
			countStr = fmt.Sprintf("(%d/%d)", cat.Enabled, cat.Total)
		}

		// Build the line
		if i == c.selected {
			label := c.styles.CategorySelected.Render(cat.DisplayLabel)
			count := c.styles.ScenarioCount.Render(countStr)
			line = fmt.Sprintf("%s%s %s", cursor, label, count)
		} else {
			label := c.styles.CategoryNormal.Render(cat.DisplayLabel)
			count := c.styles.ScenarioCount.Render(countStr)
			line = fmt.Sprintf("%s%s %s", cursor, label, count)
		}

		sb.WriteString(line)
		if i < len(c.categories)-1 {
			sb.WriteString("\n")
		}
	}

	return c.wrapInPanel(sb.String())
}

func (c *CategoriesPane) wrapInPanel(content string) string {
	panelStyle := c.styles.Panel
	if c.focused {
		panelStyle = c.styles.PanelFocused
	}

	panelStyle = panelStyle.Width(c.width - 2)
	return panelStyle.Render(content)
}
