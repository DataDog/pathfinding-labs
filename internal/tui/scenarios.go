package tui

import (
	"fmt"
	"sort"
	"strings"

	"github.com/charmbracelet/lipgloss"

	"github.com/DataDog/pathfinding-labs/internal/scenarios"
)

// ScenarioItem represents a scenario in the list with its state
type ScenarioItem struct {
	Scenario   *scenarios.Scenario
	Enabled    bool
	Deployed   bool
	DemoActive bool
}

// ScenariosPane displays the main scenario list
type ScenariosPane struct {
	styles          *Styles
	items           []ScenarioItem
	filtered        []ScenarioItem
	cursor          int
	offset          int
	focused         bool
	loading         bool
	width           int
	height          int
	filterText      string
	showGrouped     bool
	collapsed       map[string]bool // category name -> collapsed state
	showOnlyEnabled    bool // filter to show only enabled scenarios
	showOnlyDemoActive bool // filter to show only demo-active scenarios
	showCosts          bool // show cost estimates next to scenario names
}

// NewScenariosPane creates a new scenarios pane
func NewScenariosPane(styles *Styles) *ScenariosPane {
	return &ScenariosPane{
		styles:      styles,
		showGrouped: true,
		collapsed:   make(map[string]bool),
		loading:     true, // Start in loading state
		showCosts:   true, // Show costs by default
	}
}

// SetLoading sets the loading state
func (s *ScenariosPane) SetLoading(loading bool) {
	s.loading = loading
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

// ToggleShowOnlyDemoActive toggles the filter to show only demo-active scenarios
func (s *ScenariosPane) ToggleShowOnlyDemoActive() {
	s.showOnlyDemoActive = !s.showOnlyDemoActive
	s.applyFilter()
	s.cursor = 0
	s.offset = 0
}

// IsShowingOnlyDemoActive returns whether only demo-active scenarios are shown
func (s *ScenariosPane) IsShowingOnlyDemoActive() bool {
	return s.showOnlyDemoActive
}

// ToggleShowCosts toggles the display of cost estimates
func (s *ScenariosPane) ToggleShowCosts() {
	s.showCosts = !s.showCosts
}

// IsShowingCosts returns whether costs are being displayed
func (s *ScenariosPane) IsShowingCosts() bool {
	return s.showCosts
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

	// Filter by demo-active state if requested
	if s.showOnlyDemoActive {
		var result []ScenarioItem
		for _, item := range s.filtered {
			if item.DemoActive {
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
		// Already at top, but still call ensureVisible to scroll to show header
		s.ensureVisible()
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
	// Move cursor up by pageSize items, accounting for collapsed categories
	for i := 0; i < pageSize && s.cursor > 0; i++ {
		s.cursor--
		// Skip over collapsed category items
		if s.cursor > 0 {
			currentCat := s.filtered[s.cursor].Scenario.CategoryShort()
			if s.collapsed[currentCat] {
				// Find first item of this collapsed category
				for s.cursor > 0 {
					prevCat := s.filtered[s.cursor-1].Scenario.CategoryShort()
					if prevCat != currentCat {
						break
					}
					s.cursor--
				}
			}
		}
	}
	s.ensureVisible()
}

// PageDown moves down a page
func (s *ScenariosPane) PageDown() {
	pageSize := s.visibleRows()
	// Move cursor down by pageSize items, accounting for collapsed categories
	for i := 0; i < pageSize && s.cursor < len(s.filtered)-1; i++ {
		currentCat := s.filtered[s.cursor].Scenario.CategoryShort()
		// If in a collapsed category, jump to first of next category
		if s.collapsed[currentCat] {
			for s.cursor < len(s.filtered)-1 {
				s.cursor++
				newCat := s.filtered[s.cursor].Scenario.CategoryShort()
				if newCat != currentCat {
					break
				}
			}
		} else {
			s.cursor++
			// If we entered a collapsed category, that's fine - we're on its first item
		}
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

// ToggleCollapseAll toggles between all collapsed and all expanded
func (s *ScenariosPane) ToggleCollapseAll() {
	// Check if any category is expanded
	anyExpanded := false
	for _, isCollapsed := range s.collapsed {
		if !isCollapsed {
			anyExpanded = true
			break
		}
	}

	// If any are expanded, collapse all; otherwise expand all
	if anyExpanded {
		s.CollapseAll()
	} else {
		s.ExpandAll()
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

// GetItems returns all scenario items
func (s *ScenariosPane) GetItems() []ScenarioItem {
	return s.items
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

// GetDemoActiveCount returns the count of scenarios with active demos
func (s *ScenariosPane) GetDemoActiveCount() int {
	count := 0
	for _, item := range s.items {
		if item.DemoActive {
			count++
		}
	}
	return count
}

// UpdateDemoActive updates the demo-active state
func (s *ScenariosPane) UpdateDemoActive(varName string, active bool) {
	for i := range s.items {
		if s.items[i].Scenario.Terraform.VariableName == varName {
			s.items[i].DemoActive = active
			break
		}
	}
	for i := range s.filtered {
		if s.filtered[i].Scenario.Terraform.VariableName == varName {
			s.filtered[i].DemoActive = active
			break
		}
	}
}

// GetDemoActiveScenarioIDs returns UniqueIDs of all scenarios with DemoActive=true and HasCleanup()=true
func (s *ScenariosPane) GetDemoActiveScenarioIDs() []string {
	var ids []string
	for _, item := range s.items {
		if item.DemoActive && item.Scenario.HasCleanup() {
			ids = append(ids, item.Scenario.UniqueID())
		}
	}
	return ids
}

// GetDisabledDemoActiveScenarioIDs returns UniqueIDs where Deployed=true, Enabled=false, DemoActive=true, and HasCleanup()=true
func (s *ScenariosPane) GetDisabledDemoActiveScenarioIDs() []string {
	var ids []string
	for _, item := range s.items {
		if item.Deployed && !item.Enabled && item.DemoActive && item.Scenario.HasCleanup() {
			ids = append(ids, item.Scenario.UniqueID())
		}
	}
	return ids
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
	return s.height - 3
}

func (s *ScenariosPane) contentWidth() int {
	width := s.width - 4
	if width < 1 {
		width = 1
	}
	return width
}

func (s *ScenariosPane) wrapLines(line string) []string {
	wrapped := lipgloss.NewStyle().Width(s.contentWidth()).Render(line)
	lines := strings.Split(wrapped, "\n")
	if len(lines) == 0 {
		return []string{""}
	}
	return lines
}

func (s *ScenariosPane) lineHeight(line string) int {
	return len(s.wrapLines(line))
}

func (s *ScenariosPane) categoryCounts(category string) (int, int) {
	enabledCount := 0
	totalCount := 0
	for _, item := range s.filtered {
		if item.Scenario.CategoryShort() == category {
			totalCount++
			if item.Enabled {
				enabledCount++
			}
		}
	}
	return enabledCount, totalCount
}

func (s *ScenariosPane) renderCategoryHeaderLine(category string, enabledCount, totalCount int, highlight bool) string {
	collapseIndicator := "▾ "
	if s.collapsed[category] {
		collapseIndicator = "▸ "
	}
	headerText := fmt.Sprintf("%s%s (%d/%d)", collapseIndicator, CategoryDisplayName(category), enabledCount, totalCount)
	headerStyle := s.styles.CategoryHeader
	if highlight {
		headerStyle = headerStyle.Bold(true).Foreground(s.styles.ScenarioCursor.GetForeground())
	}
	return headerStyle.Render(headerText)
}

func (s *ScenariosPane) categoryHeaderHeight(category string) int {
	enabledCount, totalCount := s.categoryCounts(category)
	headerLine := s.renderCategoryHeaderLine(category, enabledCount, totalCount, false)
	return s.lineHeight(headerLine)
}

func (s *ScenariosPane) appendVisibleLines(sb *strings.Builder, lines []string, visualRow *int, offset, visible int) {
	for _, line := range lines {
		if *visualRow >= offset && *visualRow < offset+visible {
			sb.WriteString("\n")
			sb.WriteString(line)
		}
		*visualRow++
	}
}

// getVisualRow calculates the visual row for a given cursor position,
// accounting for collapsed categories and category headers
func (s *ScenariosPane) getVisualRow() int {
	if s.cursor < 0 || s.cursor >= len(s.filtered) {
		return 0
	}

	visualRow := 0
	currentCat := ""

	for i := 0; i <= s.cursor; i++ {
		item := s.filtered[i]
		cat := item.Scenario.CategoryShort()

		if cat != currentCat {
			headerHeight := s.categoryHeaderHeight(cat)
			if i == s.cursor && s.collapsed[cat] {
				return visualRow
			}
			visualRow += headerHeight
			currentCat = cat
		}

		if i == s.cursor {
			if s.collapsed[cat] {
				return visualRow
			}
			return visualRow
		}

		if !s.collapsed[cat] {
			visualRow += s.lineHeight(s.renderScenarioLine(item, false))
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
			visualRows += s.categoryHeaderHeight(cat)
			currentCat = cat
		}

		if !s.collapsed[cat] {
			visualRows += s.lineHeight(s.renderScenarioLine(item, false))
		}
	}

	return visualRows
}

func (s *ScenariosPane) ensureVisible() {
	visible := s.visibleRows()
	if visible <= 0 {
		visible = 10
	}

	// Special case: cursor at first item should always show from the top
	// This ensures the first category header is always visible
	if s.cursor == 0 {
		s.offset = 0
		return
	}

	visualRow := s.getVisualRow()

	// Check if cursor is at the first item in its category
	// If so, we want to show the category header too
	isFirstInCategory := false
	if s.cursor >= 0 && s.cursor < len(s.filtered) {
		currentCat := s.filtered[s.cursor].Scenario.CategoryShort()
		prevCat := s.filtered[s.cursor-1].Scenario.CategoryShort()
		isFirstInCategory = (currentCat != prevCat)
	}

	// Adjust visual row to include header if at first item in category
	targetRow := visualRow
	if isFirstInCategory {
		currentCat := s.filtered[s.cursor].Scenario.CategoryShort()
		headerHeight := s.categoryHeaderHeight(currentCat)
		if visualRow >= headerHeight {
			targetRow = visualRow - headerHeight
		} else {
			targetRow = 0
		}
	}

	if targetRow < s.offset {
		s.offset = targetRow
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
	var filters []string
	if s.showOnlyEnabled {
		filters = append(filters, "enabled")
	}
	if s.showOnlyDemoActive {
		filters = append(filters, "demo active")
	}
	if s.filterText != "" {
		filters = append(filters, fmt.Sprintf("/%s", s.filterText))
	}
	if len(filters) > 0 {
		titleText = fmt.Sprintf("Scenarios [%s]", strings.Join(filters, "] ["))
	}
	titleStyle := s.styles.PanelTitle.Width(s.width - 4)
	sb.WriteString(titleStyle.Render(titleText))

	if s.loading {
		sb.WriteString("\n")
		sb.WriteString(s.styles.ScenarioDisabled.Render("  Loading scenarios..."))
		return s.wrapInPanel(sb.String())
	}

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

		enabledCount := 0
		for _, item := range items {
			if item.Enabled {
				enabledCount++
			}
		}

		headerLine := s.renderCategoryHeaderLine(cat, enabledCount, len(items), isCatSelected && isCollapsed && s.focused)
		headerLines := s.wrapLines(headerLine)
		s.appendVisibleLines(&sb, headerLines, &visualRow, s.offset, visible)

		if !isCollapsed {
			for _, item := range items {
				isSelected := item.Scenario.UniqueID() == selectedID
				scenarioLine := s.renderScenarioLine(item, isSelected)
				scenarioLines := s.wrapLines(scenarioLine)
				s.appendVisibleLines(&sb, scenarioLines, &visualRow, s.offset, visible)
			}
		}
	}

	return sb.String()
}

func (s *ScenariosPane) renderFlat() string {
	var sb strings.Builder

	visible := s.visibleRows()
	visualRow := 0

	for i, item := range s.filtered {
		line := s.renderScenarioLine(item, i == s.cursor)
		lines := s.wrapLines(line)
		s.appendVisibleLines(&sb, lines, &visualRow, s.offset, visible)
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

	// Status indicator based on enabled AND deployed state
	// Green = enabled & deployed (live)
	// Yellow = enabled but not deployed (pending deploy)
	// Red = disabled but still deployed (pending destroy)
	// Gray = disabled and not deployed (off)
	if item.Enabled && item.Deployed {
		parts = append(parts, s.styles.EnabledIndicator.Render()) // Green
	} else if item.Enabled && !item.Deployed {
		parts = append(parts, s.styles.PendingDeployIndicator.Render()) // Yellow
	} else if !item.Enabled && item.Deployed {
		parts = append(parts, s.styles.PendingDestroyIndicator.Render()) // Red
	} else {
		parts = append(parts, s.styles.DisabledIndicator.Render()) // Gray
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

	// Cost estimate (if showing costs)
	if s.showCosts && item.Scenario.CostEstimate != "" {
		costStyle := s.styles.ScenarioDisabled // Use dim style for $0 costs
		// Use orange for non-zero costs to match the running cost display
		if item.Scenario.CostEstimate != "$0/mo" && item.Scenario.CostEstimate != "$0" {
			costStyle = s.styles.CostNonZero
		}
		parts = append(parts, costStyle.Render(fmt.Sprintf(" (%s)", item.Scenario.CostEstimate)))
	}

	// Status label for pending states - use short version if width is limited
	// Calculate used width: cursor(2) + indicator(1) + space(1) + id + cost + space(1)
	costWidth := 0
	if s.showCosts && item.Scenario.CostEstimate != "" {
		costWidth = len(item.Scenario.CostEstimate) + 3 // " ($X/mo)"
	}
	usedWidth := 2 + 1 + 1 + len(id) + costWidth + 1
	availableWidth := s.width - usedWidth - 4 // 4 for panel padding/borders

	if item.Enabled && !item.Deployed {
		parts = append(parts, " ")
		if availableWidth >= 27 { // len("[Enablement pending deploy]")
			parts = append(parts, s.styles.PendingDeployLabel.Render("[Enablement pending deploy]"))
		} else {
			parts = append(parts, s.styles.PendingDeployLabel.Render("[pending]"))
		}
	} else if !item.Enabled && item.Deployed {
		parts = append(parts, " ")
		if availableWidth >= 28 { // len("[Disablement pending deploy]")
			parts = append(parts, s.styles.PendingDestroyLabel.Render("[Disablement pending deploy]"))
		} else {
			parts = append(parts, s.styles.PendingDestroyLabel.Render("[pending]"))
		}
	}

	// Demo active indicator
	if item.DemoActive {
		parts = append(parts, " ")
		parts = append(parts, s.styles.DemoActiveLabel.Render("\u26a0 demo active"))
	}

	return strings.Join(parts, "")
}

func (s *ScenariosPane) wrapInPanel(content string) string {
	panelStyle := s.styles.Panel
	if s.focused {
		panelStyle = s.styles.PanelFocused
	}

	contentHeight := s.height - 2
	if contentHeight < 1 {
		contentHeight = 1
	}
	content = lipgloss.NewStyle().Height(contentHeight).MaxHeight(contentHeight).Render(content)

	panelStyle = panelStyle.Width(s.width - 2)
	return panelStyle.Render(content)
}
