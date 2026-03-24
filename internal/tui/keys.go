package tui

import (
	"github.com/charmbracelet/bubbles/key"
)

// KeyMap defines the keybindings for the TUI
type KeyMap struct {
	// Navigation
	Up       key.Binding
	Down     key.Binding
	Left     key.Binding
	Right    key.Binding
	PageUp   key.Binding
	PageDown key.Binding
	Home     key.Binding
	End      key.Binding

	// Pane focus
	Tab      key.Binding
	ShiftTab key.Binding

	// Actions
	Toggle  key.Binding
	Enable  key.Binding
	Disable key.Binding
	Deploy  key.Binding
	Plan    key.Binding
	RunDemo key.Binding
	Cleanup    key.Binding
	CleanupAll key.Binding
	Destroy    key.Binding
	Config  key.Binding

	// Filter
	Filter             key.Binding
	ClearFilter        key.Binding
	ToggleEnabledOnly  key.Binding
	ToggleDemoActive   key.Binding
	ToggleCosts        key.Binding

	// Category collapse
	ToggleCollapseAll key.Binding

	// Help and quit
	Help key.Binding
	Quit key.Binding
	Esc  key.Binding

	// Overlay
	Dismiss key.Binding
}

// DefaultKeyMap returns the default keybindings
func DefaultKeyMap() *KeyMap {
	return &KeyMap{
		// Navigation
		Up: key.NewBinding(
			key.WithKeys("up"),
			key.WithHelp("↑", "up"),
		),
		Down: key.NewBinding(
			key.WithKeys("down"),
			key.WithHelp("↓", "down"),
		),
		Left: key.NewBinding(
			key.WithKeys("left"),
			key.WithHelp("←", "left"),
		),
		Right: key.NewBinding(
			key.WithKeys("right"),
			key.WithHelp("→", "right"),
		),
		PageUp: key.NewBinding(
			key.WithKeys("pgup"),
			key.WithHelp("pgup", "page up"),
		),
		PageDown: key.NewBinding(
			key.WithKeys("pgdown"),
			key.WithHelp("pgdn", "page down"),
		),
		Home: key.NewBinding(
			key.WithKeys("home"),
			key.WithHelp("home", "first"),
		),
		End: key.NewBinding(
			key.WithKeys("end"),
			key.WithHelp("end", "last"),
		),

		// Pane focus
		Tab: key.NewBinding(
			key.WithKeys("tab"),
			key.WithHelp("tab", "next pane"),
		),
		ShiftTab: key.NewBinding(
			key.WithKeys("shift+tab"),
			key.WithHelp("shift+tab", "prev pane"),
		),

		// Actions
		Toggle: key.NewBinding(
			key.WithKeys(" "),
			key.WithHelp("space", "toggle"),
		),
		Enable: key.NewBinding(
			key.WithKeys("e"),
			key.WithHelp("e", "enable"),
		),
		Disable: key.NewBinding(
			key.WithKeys("d"),
			key.WithHelp("d", "disable"),
		),
		Deploy: key.NewBinding(
			key.WithKeys("a"),
			key.WithHelp("a", "apply"),
		),
		Plan: key.NewBinding(
			key.WithKeys("p"),
			key.WithHelp("p", "plan"),
		),
		RunDemo: key.NewBinding(
			key.WithKeys("r"),
			key.WithHelp("r", "run demo"),
		),
		Cleanup: key.NewBinding(
			key.WithKeys("c"),
			key.WithHelp("c", "cleanup"),
		),
		CleanupAll: key.NewBinding(
			key.WithKeys("C"),
			key.WithHelp("C", "cleanup all"),
		),
		Destroy: key.NewBinding(
			key.WithKeys("D"),
			key.WithHelp("D", "destroy"),
		),
		Config: key.NewBinding(
			key.WithKeys("s"),
			key.WithHelp("s", "settings"),
		),

		// Filter
		Filter: key.NewBinding(
			key.WithKeys("/"),
			key.WithHelp("/", "filter"),
		),
		ClearFilter: key.NewBinding(
			key.WithKeys("esc"),
			key.WithHelp("esc", "clear filter"),
		),
		ToggleEnabledOnly: key.NewBinding(
			key.WithKeys("."),
			key.WithHelp(".", "toggle enabled only"),
		),
		ToggleDemoActive: key.NewBinding(
			key.WithKeys("!"),
			key.WithHelp("!", "demo active only"),
		),
		ToggleCosts: key.NewBinding(
			key.WithKeys("$"),
			key.WithHelp("$", "toggle costs"),
		),

		// Category collapse
		ToggleCollapseAll: key.NewBinding(
			key.WithKeys(","),
			key.WithHelp(",", "toggle collapse all"),
		),

		// Help and quit
		Help: key.NewBinding(
			key.WithKeys("?"),
			key.WithHelp("?", "help"),
		),
		Quit: key.NewBinding(
			key.WithKeys("q", "ctrl+c"),
			key.WithHelp("q", "quit"),
		),
		Esc: key.NewBinding(
			key.WithKeys("esc"),
			key.WithHelp("esc", "dismiss"),
		),

		// Overlay
		Dismiss: key.NewBinding(
			key.WithKeys("enter", "esc", " "),
			key.WithHelp("any key", "dismiss"),
		),
	}
}

// ShortHelp returns a short help string for the status bar
func (k *KeyMap) ShortHelp() []key.Binding {
	return []key.Binding{
		k.Toggle, k.Enable, k.Disable, k.Deploy, k.Filter, k.Help, k.Quit,
	}
}

// FullHelp returns all keybindings for the help overlay
func (k *KeyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.Up, k.Down, k.PageUp, k.PageDown},
		{k.Tab, k.Toggle, k.Enable, k.Disable},
		{k.Deploy, k.Plan, k.RunDemo, k.Cleanup, k.CleanupAll},
		{k.Destroy, k.Config},
		{k.Filter, k.ToggleEnabledOnly, k.ToggleDemoActive, k.ToggleCosts},
		{k.ToggleCollapseAll},
		{k.Help, k.Quit},
	}
}
