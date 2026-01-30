package tui

import (
	"fmt"
	"sort"
	"strings"

	"github.com/DataDog/pathfinding-labs/internal/scenarios"
)

// ScenarioItem represents a scenario in the list with its state
type ScenarioItem struct {
	Scenario *scenarios.Scenario
	Enabled  bool
	Deployed bool
}

// ScenariosPane displays the main scenario list
type ScenariosPane struct {
	styles          *Styles
	items           []ScenarioItem
	filtered        []ScenarioItem
	cursor          int
	offset          int
	focused         bool
	width           int
	height          int
	filterText      string
	showGrouped     bool
	collapsed       map[string]bool // category name -> collapsed state
	showOnlyEnabled bool            // filter to show only enabled scenarios
}

// NewScenariosPane creates a new scenarios pane
func NewScenariosPane(styles *Styles) *ScenariosPane {
	return &ScenariosPane{
		styles:      styles,
		showGrouped: true,
		collapsed:   make(map[string]bool),
	}
}

// SetScenarios updates the scenario list
func (s *ScenariosPane) SetScenarios(items []ScenarioItem) {
	s.items = items
	s.applyFilter()

	// Initialize all categories as expanded by default
	for _, item := range items {
		cat := item.Scenario.CategoryShort()
		if _, exists := s.collapsed[cat]; !exists {
			s.collapsed[cat] = false // expanded by default
		}
	}
}

// SetFocused sets whether this pane is focused
func (s *ScenariosPane) SetFocused(focused bool) {
	s.focused = focused
}

// SetSize sets the pane dimensions
func (s *ScenariosPane) SetSize(width, height int) {
	s.width = width
	s.height = height
	s.ensureVisible()
}

// SetFilter sets the filter text
func (s *ScenariosPane) SetFilter(filter string) {
	s.filterText = strings.ToLower(filter)
	s.applyFilter()
	s.cursor = 0
	s.offset = 0
}

// ToggleShowOnlyEnabled toggles the filter to show only enabled scenarios
func (s *ScenariosPane) ToggleShowOnlyEnabled() {
	s.showOnlyEnabled = !s.showOnlyEnabled
	s.applyFilter()
	s.cursor = 0
	s.offset = 0
}

// IsShowingOnlyEnabled returns whether only enabled scenarios are shown
func (s *ScenariosPane) IsShowingOnlyEnabled() bool {
	return s.showOnlyEnabled
}

// SetCategoryFilter filters scenarios by category
func (s *ScenariosPane) SetCategoryFilter(category string) {
	if category == "All" || category == "" {
		s.filtered = s.items
	} else {
		s.filtered = nil
		for _, item := range s.items {
			if item.Scenario.CategoryShort() == category {
				s.filtered = append(s.filtered, item)
			}
		}
	}

	// Apply text filter on top
	if s.filterText != "" {
		s.applyTextFilter()
	}

	s.sortByCategoryOrder()
	s.cursor = 0
	s.offset = 0
}

func (s *ScenariosPane) applyFilter() {
	// Start with all items
	s.filtered = s.items

	// Filter by enabled state if requested
	if s.showOnlyEnabled {
		var result []ScenarioItem
		for _, item := range s.filtered {
			if item.Enabled {
				result = append(result, item)
			}
		}
		s.filtered = result
	}

	// Apply text filter on top
	if s.filterText != "" {
		s.applyTextFilter()
	}

	s.sortByCategoryOrder()
}

// sortByCategoryOrder sorts filtered items to match the grouped view order
func (s *ScenariosPane) sortByCategoryOrder() {
	predefined := PredefinedCategories()
	categoryIndex := make(map[string]int)
	for i, cat := range predefined {
		categoryIndex[cat] = i
	}

	sort.SliceStable(s.filtered, func(i, j int) bool {
		catI := s.filtered[i].Scenario.CategoryShort()
		catJ := s.filtered[j].Scenario.CategoryShort()

		idxI, okI := categoryIndex[catI]
		idxJ, okJ := categoryIndex[catJ]
		if !okI {
			idxI = 999
		}
		if !okJ {
			idxJ = 999
		}

		if idxI != idxJ {
			return idxI < idxJ
		}
		// Same category, sort by ID
		return s.filtered[i].Scenario.UniqueID() < s.filtered[j].Scenario.UniqueID()
	})
}

func (s *ScenariosPane) applyTextFilter() {
	var result []ScenarioItem
	for _, item := range s.filtered {
		id := strings.ToLower(item.Scenario.UniqueID())
		name := strings.ToLower(item.Scenario.Name)
		desc := strings.ToLower(item.Scenario.Description)
		if strings.Contains(id, s.filterText) ||
			strings.Contains(name, s.filterText) ||
			strings.Contains(desc, s.filterText) {
			result = append(result, item)
		}
	}
	s.filtered = result
}

// MoveUp moves the cursor up, skipping collapsed scenarios
func (s *ScenariosPane) MoveUp() {
	if s.cursor <= 0 {
		return
	}

	// Get current category
	currentCat := s.filtered[s.cursor].Scenario.CategoryShort()

	// Move up one
	s.cursor--

	// If we're now in a collapsed category (different from where we started),
	// jump to the first item of that category
	newCat := s.filtered[s.cursor].Scenario.CategoryShort()
	if newCat != currentCat && s.collapsed[newCat] {
		// Find the first item of this collapsed category
		for s.cursor > 0 {
			prevCat := s.filtered[s.cursor-1].Scenario.CategoryShort()
			if prevCat != newCat {
				break
			}
			s.cursor--
		}
	}

	s.ensureVisible()
}

// MoveDown moves the cursor down, skipping collapsed scenarios
func (s *ScenariosPane) MoveDown() {
	if s.cursor >= len(s.filtered)-1 {
		return
	}

	// Get current category
	currentCat := s.filtered[s.cursor].Scenario.CategoryShort()

	// If current category is collapsed, jump to first item of next category
	if s.collapsed[currentCat] {
		for s.cursor < len(s.filtered)-1 {
			s.cursor++
			newCat := s.filtered[s.cursor].Scenario.CategoryShort()
			if newCat != currentCat {
				break
			}
		}
	} else {
		// Move down one
		s.cursor++

		// If we entered a collapsed category, stay on its first item
		newCat := s.filtered[s.cursor].Scenario.CategoryShort()
		if newCat != currentCat && s.collapsed[newCat] {
			// Already on the first item of the collapsed category, which is fine
		}
	}

	s.ensureVisible()
}

// PageUp moves up a page
func (s *ScenariosPane) PageUp() {
	pageSize := s.visibleRows()
	s.cursor -= pageSize
	if s.cursor < 0 {
		s.cursor = 0
	}
	s.ensureVisible()
}

// PageDown moves down a page
func (s *ScenariosPane) PageDown() {
	pageSize := s.visibleRows()
	s.cursor += pageSize
	if s.cursor >= len(s.filtered) {
		s.cursor = len(s.filtered) - 1
	}
	if s.cursor < 0 {
		s.cursor = 0
	}
	s.ensureVisible()
}

// GoToFirst moves to the first item
func (s *ScenariosPane) GoToFirst() {
	s.cursor = 0
	s.offset = 0
}

// GoToLast moves to the last item
func (s *ScenariosPane) GoToLast() {
	s.cursor = len(s.filtered) - 1
	if s.cursor < 0 {
		s.cursor = 0
	}
	s.ensureVisible()
}

// Selected returns the currently selected scenario item
func (s *ScenariosPane) Selected() *ScenarioItem {
	if s.cursor >= 0 && s.cursor < len(s.filtered) {
		return &s.filtered[s.cursor]
	}
	return nil
}

// SelectedScenario returns the currently selected scenario
func (s *ScenariosPane) SelectedScenario() *scenarios.Scenario {
	item := s.Selected()
	if item != nil {
		return item.Scenario
	}
	return nil
}

// Toggle toggles the enabled state of the selected scenario
// Returns the scenario that was toggled, or nil if none
func (s *ScenariosPane) Toggle() *scenarios.Scenario {
	if s.cursor >= 0 && s.cursor < len(s.filtered) {
		s.filtered[s.cursor].Enabled = !s.filtered[s.cursor].Enabled
		// Also update in the main items list
		for i := range s.items {
			if s.items[i].Scenario.UniqueID() == s.filtered[s.cursor].Scenario.UniqueID() {
				s.items[i].Enabled = s.filtered[s.cursor].Enabled
				break
			}
		}
		return s.filtered[s.cursor].Scenario
	}
	return nil
}

// GetCurrentCategory returns the category of the currently selected scenario
func (s *ScenariosPane) GetCurrentCategory() string {
	if s.cursor >= 0 && s.cursor < len(s.filtered) {
		return s.filtered[s.cursor].Scenario.CategoryShort()
	}
	return ""
}

// IsCategoryCollapsed returns whether a category is collapsed
func (s *ScenariosPane) IsCategoryCollapsed(category string) bool {
	return s.collapsed[category]
}

// ToggleCollapse toggles the collapse state of the current category
func (s *ScenariosPane) ToggleCollapse() {
	cat := s.GetCurrentCategory()
	if cat != "" {
		s.collapsed[cat] = !s.collapsed[cat]
	}
}

// Expand expands the current category (right arrow)
func (s *ScenariosPane) Expand() {
	cat := s.GetCurrentCategory()
	if cat != "" {
		s.collapsed[cat] = false
	}
}

// Collapse collapses the current category (left arrow)
func (s *ScenariosPane) Collapse() {
	cat := s.GetCurrentCategory()
	if cat != "" {
		s.collapsed[cat] = true
	}
}

// ExpandAll expands all categories
func (s *ScenariosPane) ExpandAll() {
	for cat := range s.collapsed {
		s.collapsed[cat] = false
	}
}

// CollapseAll collapses all categories
func (s *ScenariosPane) CollapseAll() {
	for cat := range s.collapsed {
		s.collapsed[cat] = true
	}
}

// UpdateEnabled updates the enabled state from external source
func (s *ScenariosPane) UpdateEnabled(varName string, enabled bool) {
	for i := range s.items {
		if s.items[i].Scenario.Terraform.VariableName == varName {
			s.items[i].Enabled = enabled
			break
		}
	}
	for i := range s.filtered {
		if s.filtered[i].Scenario.Terraform.VariableName == varName {
			s.filtered[i].Enabled = enabled
			break
		}
	}
}

// UpdateDeployed updates the deployed state
func (s *ScenariosPane) UpdateDeployed(varName string, deployed bool) {
	for i := range s.items {
		if s.items[i].Scenario.Terraform.VariableName == varName {
			s.items[i].Deployed = deployed
			break
		}
	}
	for i := range s.filtered {
		if s.filtered[i].Scenario.Terraform.VariableName == varName {
			s.filtered[i].Deployed = deployed
			break
		}
	}
}

// GetEnabledScenarios returns all enabled scenarios
func (s *ScenariosPane) GetEnabledScenarios() []*scenarios.Scenario {
	var enabled []*scenarios.Scenario
	for _, item := range s.items {
		if item.Enabled {
			enabled = append(enabled, item.Scenario)
		}
	}
	return enabled
}

// GetEnabledCount returns the count of enabled scenarios
func (s *ScenariosPane) GetEnabledCount() int {
	count := 0
	for _, item := range s.items {
		if item.Enabled {
			count++
		}
	}
	return count
}

// GetDeployedCount returns the count of deployed scenarios
func (s *ScenariosPane) GetDeployedCount() int {
	count := 0
	for _, item := range s.items {
		if item.Deployed {
			count++
		}
	}
	return count
}

// HasPendingChanges returns true if there are enabled/deployed mismatches
func (s *ScenariosPane) HasPendingChanges() bool {
	for _, item := range s.items {
		// Enabled but not deployed = needs deploy
		// Deployed but not enabled = needs deploy (to destroy)
		if item.Enabled != item.Deployed {
			return true
		}
	}
	return false
}

func (s *ScenariosPane) visibleRows() int {
	// Account for panel borders and title
	return s.height - 6
}

// getVisualRow calculates the visual row for a given cursor position,
// accounting for collapsed categories and category headers
func (s *ScenariosPane) getVisualRow() int {
	if s.cursor < 0 || s.cursor >= len(s.filtered) {
		return 0
	}

	// Group by category to calculate visual position
	visualRow := 0
	currentCat := ""

	for i := 0; i <= s.cursor; i++ {
		item := s.filtered[i]
		cat := item.Scenario.CategoryShort()

		// New category? Add header row
		if cat != currentCat {
			visualRow++ // category header
			currentCat = cat
		}

		// If this is our cursor position, we're done
		if i == s.cursor {
			// If category is collapsed, cursor is on the header row
			if s.collapsed[cat] {
				// visualRow already includes the header
			} else {
				visualRow++ // add the scenario row
			}
			break
		}

		// Only count scenario rows if category is expanded
		if !s.collapsed[cat] {
			visualRow++
		}
	}

	return visualRow
}

// getTotalVisualRows returns the total number of visual rows
func (s *ScenariosPane) getTotalVisualRows() int {
	visualRows := 0
	currentCat := ""

	for _, item := range s.filtered {
		cat := item.Scenario.CategoryShort()

		if cat != currentCat {
			visualRows++ // category header
			currentCat = cat
		}

		if !s.collapsed[cat] {
			visualRows++ // scenario row
		}
	}

	return visualRows
}

func (s *ScenariosPane) ensureVisible() {
	visible := s.visibleRows()
	if visible <= 0 {
		visible = 10
	}

	visualRow := s.getVisualRow()

	if visualRow < s.offset {
		s.offset = visualRow
	} else if visualRow >= s.offset+visible {
		s.offset = visualRow - visible + 1
	}

	// Don't let offset go negative
	if s.offset < 0 {
		s.offset = 0
	}
}

// View renders the scenarios pane
func (s *ScenariosPane) View() string {
	var sb strings.Builder

	// Title with filter info
	titleText := "Scenarios"
	if s.showOnlyEnabled && s.filterText != "" {
		titleText = fmt.Sprintf("Scenarios [enabled] [/%s]", s.filterText)
	} else if s.showOnlyEnabled {
		titleText = "Scenarios [enabled]"
	} else if s.filterText != "" {
		titleText = fmt.Sprintf("Scenarios [/%s]", s.filterText)
	}
	titleStyle := s.styles.PanelTitle.Width(s.width - 4)
	sb.WriteString(titleStyle.Render(titleText))
	sb.WriteString("\n")

	if len(s.filtered) == 0 {
		sb.WriteString("\n")
		sb.WriteString(s.styles.ScenarioDisabled.Render("  No scenarios found"))
		return s.wrapInPanel(sb.String())
	}

	// Group scenarios by category if showing grouped
	if s.showGrouped {
		sb.WriteString(s.renderGrouped())
	} else {
		sb.WriteString(s.renderFlat())
	}

	return s.wrapInPanel(sb.String())
}

func (s *ScenariosPane) renderGrouped() string {
	var sb strings.Builder

	// Get the currently selected scenario for comparison
	var selectedID string
	var selectedCat string
	if s.cursor >= 0 && s.cursor < len(s.filtered) {
		selectedID = s.filtered[s.cursor].Scenario.UniqueID()
		selectedCat = s.filtered[s.cursor].Scenario.CategoryShort()
	}

	// Group by category
	groups := make(map[string][]ScenarioItem)
	var categoryOrder []string

	for _, item := range s.filtered {
		cat := item.Scenario.CategoryShort()
		if _, exists := groups[cat]; !exists {
			categoryOrder = append(categoryOrder, cat)
		}
		groups[cat] = append(groups[cat], item)
	}

	// Sort categories by predefined order
	predefined := PredefinedCategories()
	sort.Slice(categoryOrder, func(i, j int) bool {
		iIdx, jIdx := 999, 999
		for k, p := range predefined {
			if p == categoryOrder[i] {
				iIdx = k
			}
			if p == categoryOrder[j] {
				jIdx = k
			}
		}
		return iIdx < jIdx
	})

	visible := s.visibleRows()
	visualRow := 0

	for _, cat := range categoryOrder {
		items := groups[cat]
		isCollapsed := s.collapsed[cat]
		isCatSelected := cat == selectedCat

		// Count enabled in this category
		enabledCount := 0
		for _, item := range items {
			if item.Enabled {
				enabledCount++
			}
		}

		// Category header with collapse indicator
		if visualRow >= s.offset && visualRow < s.offset+visible {
			var collapseIndicator string
			if isCollapsed {
				collapseIndicator = "▸ "
			} else {
				collapseIndicator = "▾ "
			}

			headerText := fmt.Sprintf("%s%s (%d/%d)", collapseIndicator, CategoryDisplayName(cat), enabledCount, len(items))

			// Highlight the category header if it's selected and collapsed
			headerStyle := s.styles.CategoryHeader
			if isCatSelected && isCollapsed && s.focused {
				headerStyle = headerStyle.Bold(true).Foreground(s.styles.ScenarioCursor.GetForeground())
			}

			sb.WriteString("\n")
			sb.WriteString(headerStyle.Render(headerText))
			sb.WriteString("\n")
		}
		visualRow++

		// Scenarios in this category (only if expanded)
		if !isCollapsed {
			for _, item := range items {
				if visualRow >= s.offset && visualRow < s.offset+visible {
					// Compare by scenario ID, not by index
					isSelected := item.Scenario.UniqueID() == selectedID
					sb.WriteString(s.renderScenarioLine(item, isSelected))
					sb.WriteString("\n")
				}
				visualRow++
			}
		}
	}

	return sb.String()
}

func (s *ScenariosPane) renderFlat() string {
	var sb strings.Builder

	visible := s.visibleRows()
	start := s.offset
	end := s.offset + visible
	if end > len(s.filtered) {
		end = len(s.filtered)
	}

	for i := start; i < end; i++ {
		item := s.filtered[i]
		sb.WriteString(s.renderScenarioLine(item, i == s.cursor))
		sb.WriteString("\n")
	}

	return sb.String()
}

func (s *ScenariosPane) renderScenarioLine(item ScenarioItem, selected bool) string {
	var parts []string

	// Cursor
	cursor := "  "
	if selected && s.focused {
		cursor = s.styles.ScenarioCursor.Render("> ")
	} else if selected {
		cursor = "> "
	}
	parts = append(parts, cursor)

	// Enabled indicator
	if item.Enabled {
		parts = append(parts, s.styles.EnabledIndicator.Render())
	} else {
		parts = append(parts, s.styles.DisabledIndicator.Render())
	}
	parts = append(parts, " ")

	// Scenario ID (use UniqueID for clarity, e.g., "iam-002-to-admin")
	idStyle := s.styles.ScenarioID
	if selected {
		idStyle = idStyle.Bold(true)
	}
	if !item.Enabled {
		idStyle = s.styles.ScenarioDisabled
	}
	id := item.Scenario.UniqueID()
	parts = append(parts, idStyle.Render(id))

	// Deployed indicator
	if item.Deployed {
		parts = append(parts, " ")
		parts = append(parts, s.styles.DeployedIndicator.Render())
	}

	return strings.Join(parts, "")
}

func (s *ScenariosPane) wrapInPanel(content string) string {
	panelStyle := s.styles.Panel
	if s.focused {
		panelStyle = s.styles.PanelFocused
	}

	panelStyle = panelStyle.Width(s.width - 2)
	return panelStyle.Render(content)
}
