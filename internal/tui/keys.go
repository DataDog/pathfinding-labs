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
	Deploy  key.Binding
	Plan    key.Binding
	RunDemo key.Binding
	Cleanup key.Binding

	// Filter
	Filter          key.Binding
	ClearFilter     key.Binding
	ToggleEnabledOnly key.Binding

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
			key.WithKeys("up", "k"),
			key.WithHelp("↑/k", "up"),
		),
		Down: key.NewBinding(
			key.WithKeys("down", "j"),
			key.WithHelp("↓/j", "down"),
		),
		Left: key.NewBinding(
			key.WithKeys("left", "h"),
			key.WithHelp("←/h", "left"),
		),
		Right: key.NewBinding(
			key.WithKeys("right", "l"),
			key.WithHelp("→/l", "right"),
		),
		PageUp: key.NewBinding(
			key.WithKeys("pgup", "ctrl+u"),
			key.WithHelp("pgup", "page up"),
		),
		PageDown: key.NewBinding(
			key.WithKeys("pgdown", "ctrl+d"),
			key.WithHelp("pgdn", "page down"),
		),
		Home: key.NewBinding(
			key.WithKeys("home", "g"),
			key.WithHelp("home/g", "first"),
		),
		End: key.NewBinding(
			key.WithKeys("end", "G"),
			key.WithHelp("end/G", "last"),
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
		Deploy: key.NewBinding(
			key.WithKeys("d"),
			key.WithHelp("d", "deploy"),
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
		k.Toggle, k.Deploy, k.Filter, k.Help, k.Quit,
	}
}

// FullHelp returns all keybindings for the help overlay
func (k *KeyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.Up, k.Down, k.PageUp, k.PageDown},
		{k.Tab, k.Toggle},
		{k.Deploy, k.Plan, k.RunDemo, k.Cleanup},
		{k.Filter, k.Help, k.Quit},
	}
}
