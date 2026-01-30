package tui

import (
	"fmt"
	"strings"

	"github.com/DataDog/pathfinding-labs/internal/scenarios"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

// DetailsPane displays detailed information about the selected scenario
type DetailsPane struct {
	styles    *Styles
	scenario  *scenarios.Scenario
	enabled   bool
	deployed  bool
	creds     *terraform.Credentials
	resources []string // ARNs of deployed resources
	focused   bool
	width     int
	height    int
	scroll    int
}

// NewDetailsPane creates a new details pane
func NewDetailsPane(styles *Styles) *DetailsPane {
	return &DetailsPane{
		styles: styles,
	}
}

// SetScenario updates the displayed scenario
func (d *DetailsPane) SetScenario(s *scenarios.Scenario, enabled, deployed bool) {
	d.scenario = s
	d.enabled = enabled
	d.deployed = deployed
	d.scroll = 0
}

// SetCredentials sets the credentials for the displayed scenario
func (d *DetailsPane) SetCredentials(creds *terraform.Credentials) {
	d.creds = creds
}

// ClearCredentials clears the credentials
func (d *DetailsPane) ClearCredentials() {
	d.creds = nil
}

// SetResources sets the deployed resource ARNs for the displayed scenario
func (d *DetailsPane) SetResources(resources []string) {
	d.resources = resources
}

// ClearResources clears the resources
func (d *DetailsPane) ClearResources() {
	d.resources = nil
}

// SetFocused sets whether this pane is focused
func (d *DetailsPane) SetFocused(focused bool) {
	d.focused = focused
}

// SetSize sets the pane dimensions
func (d *DetailsPane) SetSize(width, height int) {
	d.width = width
	d.height = height
}

// ScrollUp scrolls the content up
func (d *DetailsPane) ScrollUp() {
	if d.scroll > 0 {
		d.scroll--
	}
}

// ScrollDown scrolls the content down
func (d *DetailsPane) ScrollDown() {
	d.scroll++
}

// View renders the details pane
func (d *DetailsPane) View() string {
	var sb strings.Builder

	if d.scenario == nil {
		sb.WriteString("\n")
		sb.WriteString(d.styles.DetailLabel.Render("  Select a scenario"))
		return d.wrapInPanel(sb.String())
	}

	contentWidth := d.width - 6
	if contentWidth < 20 {
		contentWidth = 20
	}

	// Scenario ID (bold, highlighted)
	idStyle := d.styles.DetailHighlight.Bold(true)
	sb.WriteString(idStyle.Render(d.scenario.UniqueID()))
	sb.WriteString("\n")

	// Name (truncated if needed)
	name := d.scenario.Name
	if len(name) > contentWidth {
		name = name[:contentWidth-3] + "..."
	}
	sb.WriteString(d.styles.DetailValue.Render(name))
	sb.WriteString("\n")

	// Status with color
	if d.enabled && d.deployed {
		sb.WriteString(d.styles.EnvDeployed.Render("● Deployed"))
	} else if d.enabled {
		sb.WriteString(d.styles.EnvConfigured.Render("● Enabled"))
	} else {
		sb.WriteString(d.styles.ScenarioDisabled.Render("○ Disabled"))
	}
	sb.WriteString("\n\n")

	// Metadata fields (each on own line with label styling)
	sb.WriteString(d.styles.DetailLabel.Render("Category  "))
	sb.WriteString(d.styles.DetailValue.Render(d.scenario.CategoryShort()))
	sb.WriteString("\n")

	sb.WriteString(d.styles.DetailLabel.Render("Target    "))
	sb.WriteString(d.styles.DetailValue.Render(d.scenario.TargetShort()))
	sb.WriteString("\n")

	sb.WriteString(d.styles.DetailLabel.Render("Cost      "))
	sb.WriteString(d.styles.DetailValue.Render(d.scenario.CostEstimate))
	sb.WriteString("\n")

	// Pathfinding.cloud link
	if d.scenario.PathfindingCloudID != "" {
		sb.WriteString(d.styles.DetailLabel.Render("Link      "))
		link := fmt.Sprintf("pathfinding.cloud/paths/%s", d.scenario.PathfindingCloudID)
		if len(link) > contentWidth-10 {
			link = link[:contentWidth-13] + "..."
		}
		sb.WriteString(d.styles.DetailHighlight.Render(link))
		sb.WriteString("\n")
	}

	// Description
	sb.WriteString("\n")
	sb.WriteString(d.styles.DetailSection.Render("Description"))
	sb.WriteString("\n")
	if d.scenario.Description != "" {
		wrapped := d.wordWrap(d.scenario.Description, contentWidth)
		sb.WriteString(d.styles.DetailValue.Render(wrapped))
	} else {
		sb.WriteString(d.styles.ScenarioDisabled.Render("No description available"))
	}
	sb.WriteString("\n")

	// MITRE ATT&CK (compact)
	if len(d.scenario.MitreAttack.Techniques) > 0 {
		sb.WriteString("\n")
		sb.WriteString(d.styles.DetailSection.Render("MITRE ATT&CK"))
		sb.WriteString("\n")
		for _, tech := range d.scenario.MitreAttack.Techniques {
			if len(tech) > contentWidth {
				tech = tech[:contentWidth-3] + "..."
			}
			sb.WriteString(d.styles.DetailValue.Render("  " + tech))
			sb.WriteString("\n")
		}
	}

	// Required Permissions (compact, show first 3)
	if len(d.scenario.Permissions.Required) > 0 {
		sb.WriteString("\n")
		sb.WriteString(d.styles.DetailSection.Render("Required Permissions"))
		sb.WriteString("\n")
		shown := 0
		for _, perm := range d.scenario.Permissions.Required {
			if shown >= 3 {
				remaining := len(d.scenario.Permissions.Required) - 3
				sb.WriteString(d.styles.ScenarioDisabled.Render(fmt.Sprintf("  ...and %d more", remaining)))
				sb.WriteString("\n")
				break
			}
			permText := perm.Permission
			if len(permText) > contentWidth-2 {
				permText = permText[:contentWidth-5] + "..."
			}
			sb.WriteString(d.styles.DetailValue.Render("  " + permText))
			sb.WriteString("\n")
			shown++
		}
	}

	// Credentials (only if deployed)
	if d.deployed && d.creds != nil {
		sb.WriteString("\n")
		sb.WriteString(d.styles.DetailSection.Render("Credentials"))
		sb.WriteString("\n")
		if d.creds.AccessKeyID != "" {
			sb.WriteString(d.styles.CredentialKey.Render("  Access Key: "))
			sb.WriteString(d.styles.CredentialValue.Render(d.creds.AccessKeyID))
			sb.WriteString("\n")
		}
		if d.creds.SecretAccessKey != "" {
			sb.WriteString(d.styles.CredentialKey.Render("  Secret Key: "))
			// Show full secret - user can copy it
			sb.WriteString(d.styles.CredentialValue.Render(d.creds.SecretAccessKey))
			sb.WriteString("\n")
		}
	}

	// Deployed Resources (only if deployed)
	if d.deployed && len(d.resources) > 0 {
		sb.WriteString("\n")
		sb.WriteString(d.styles.DetailSection.Render("Deployed Resources"))
		sb.WriteString("\n")
		for _, arn := range d.resources {
			// Truncate if needed
			displayARN := arn
			if len(displayARN) > contentWidth-2 {
				displayARN = displayARN[:contentWidth-5] + "..."
			}
			sb.WriteString(d.styles.DetailValue.Render("  • " + displayARN))
			sb.WriteString("\n")
		}
	}

	return d.wrapInPanel(sb.String())
}

func (d *DetailsPane) wordWrap(text string, width int) string {
	if width <= 0 {
		return text
	}

	var lines []string
	var currentLine strings.Builder

	words := strings.Fields(text)
	for _, word := range words {
		if currentLine.Len()+len(word)+1 > width {
			if currentLine.Len() > 0 {
				lines = append(lines, currentLine.String())
				currentLine.Reset()
			}
		}
		if currentLine.Len() > 0 {
			currentLine.WriteString(" ")
		}
		currentLine.WriteString(word)
	}
	if currentLine.Len() > 0 {
		lines = append(lines, currentLine.String())
	}

	return strings.Join(lines, "\n")
}

func (d *DetailsPane) wrapInPanel(content string) string {
	panelStyle := d.styles.Panel
	if d.focused {
		panelStyle = d.styles.PanelFocused
	}

	panelStyle = panelStyle.Width(d.width - 2)
	return panelStyle.Render(content)
}
