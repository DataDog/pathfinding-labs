package scenarios

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

// AttackMap is a minimal projection of attack_map.yaml for the TUI's needs.
// We deliberately omit edge commands and hints — the details pane only needs
// node-level structure (entry point, target, pivots) and edge connectivity
// (to identify the starting node and count hops).
type AttackMap struct {
	Nodes []AttackNode `yaml:"nodes"`
	Edges []AttackEdge `yaml:"edges"`
}

// AttackNode mirrors the node schema in .claude/scenario-attackmap-schema.md.
type AttackNode struct {
	ID                   string       `yaml:"id"`
	Label                string       `yaml:"label"`
	Type                 string       `yaml:"type"`     // principal | resource
	SubType              string       `yaml:"subType"`  // iam-user, lambda-function, etc.
	IsTarget             bool         `yaml:"isTarget"`
	IsAttackerControlled bool         `yaml:"isAttackerControlled"`
	IsAdmin              bool         `yaml:"isAdmin"`
	ARN                  string       `yaml:"arn"`
	Access               *AccessEntry `yaml:"access,omitempty"`
}

// AccessEntry describes how the attacker reaches the starting node.
type AccessEntry struct {
	Type   string `yaml:"type"` // public-network | assumed-breach-network | assumed-breach-credentials
	URL    string `yaml:"url,omitempty"`
	IP     string `yaml:"ip,omitempty"`
	Domain string `yaml:"domain,omitempty"`
}

// AttackEdge captures only the structural fields needed to find the starting
// node (no incoming edges) and count hops.
type AttackEdge struct {
	From string `yaml:"from"`
	To   string `yaml:"to"`
}

type attackMapEnvelope struct {
	AttackMap AttackMap `yaml:"attackMap"`
}

// LoadAttackMap reads attack_map.yaml from the scenario directory. Returns
// (nil, nil) when the file is missing — older scenarios mid-migration and
// some tool-testing scenarios may not have one, and the caller should
// degrade gracefully rather than treat absence as an error.
func (s *Scenario) LoadAttackMap() (*AttackMap, error) {
	if s.DirPath == "" {
		return nil, nil
	}
	path := filepath.Join(s.DirPath, "attack_map.yaml")
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("read attack_map.yaml: %w", err)
	}
	var env attackMapEnvelope
	if err := yaml.Unmarshal(data, &env); err != nil {
		return nil, fmt.Errorf("parse attack_map.yaml: %w", err)
	}
	return &env.AttackMap, nil
}

// StartingNode returns the entry-point node — the node with no incoming edges.
// When multiple candidates exist (malformed map), prefer the first one that
// has an Access field, then fall back to the first node listed.
func (m *AttackMap) StartingNode() *AttackNode {
	if m == nil || len(m.Nodes) == 0 {
		return nil
	}
	hasIncoming := make(map[string]bool, len(m.Nodes))
	for _, e := range m.Edges {
		// A self-loop (from == to) doesn't disqualify a node from being the
		// starting node — self-escalation scenarios begin at the self-loop node.
		if e.From != e.To {
			hasIncoming[e.To] = true
		}
	}
	var fallback *AttackNode
	for i := range m.Nodes {
		n := &m.Nodes[i]
		if hasIncoming[n.ID] {
			continue
		}
		if n.Access != nil {
			return n
		}
		if fallback == nil {
			fallback = n
		}
	}
	if fallback != nil {
		return fallback
	}
	return &m.Nodes[0]
}

// TargetNode returns the node flagged isTarget: true. Tool-testing scenarios
// and unmigrated scenarios may not have one — callers should handle nil.
func (m *AttackMap) TargetNode() *AttackNode {
	if m == nil {
		return nil
	}
	for i := range m.Nodes {
		if m.Nodes[i].IsTarget {
			return &m.Nodes[i]
		}
	}
	return nil
}

// PivotSubTypes returns the distinct subTypes of resource nodes that act as
// pivots — i.e., resource-type nodes that are neither the starting node nor
// the target node. Order is deterministic (first-seen order in the YAML).
func (m *AttackMap) PivotSubTypes() []string {
	if m == nil {
		return nil
	}
	start := m.StartingNode()
	target := m.TargetNode()
	seen := make(map[string]bool)
	var out []string
	for i := range m.Nodes {
		n := &m.Nodes[i]
		if n.Type != "resource" {
			continue
		}
		if start != nil && n.ID == start.ID {
			continue
		}
		if target != nil && n.ID == target.ID {
			continue
		}
		if seen[n.SubType] {
			continue
		}
		seen[n.SubType] = true
		out = append(out, n.SubType)
	}
	return out
}

// HopCount returns the number of edges in the map — a reasonable proxy for
// path complexity.
func (m *AttackMap) HopCount() int {
	if m == nil {
		return 0
	}
	return len(m.Edges)
}

// HasAttackerControlled reports whether any node represents attacker-owned
// infrastructure (e.g., exfil bucket, C2 endpoint).
func (m *AttackMap) HasAttackerControlled() bool {
	if m == nil {
		return false
	}
	for i := range m.Nodes {
		if m.Nodes[i].IsAttackerControlled {
			return true
		}
	}
	return false
}

// PrettyAccessType maps the access.type enum to a short human label.
func PrettyAccessType(t string) string {
	switch t {
	case "public-network":
		return "Public internet"
	case "assumed-breach-network":
		return "Internal network"
	case "assumed-breach-credentials":
		return "IAM credentials"
	default:
		return t
	}
}

// PrettySubType converts a subType slug like "lambda-function" to "Lambda
// Function" for display. Unknown subTypes are title-cased word-by-word.
func PrettySubType(sub string) string {
	if sub == "" {
		return ""
	}
	parts := strings.Split(sub, "-")
	for i, p := range parts {
		switch strings.ToLower(p) {
		case "iam", "ec2", "ecs", "ssm", "s3", "url":
			parts[i] = strings.ToUpper(p)
		default:
			if len(p) > 0 {
				parts[i] = strings.ToUpper(p[:1]) + p[1:]
			}
		}
	}
	return strings.Join(parts, " ")
}

// Endpoint returns the network address from the access object, preferring URL
// over IP over domain. Returns "" when none are set or access is nil.
func (a *AccessEntry) Endpoint() string {
	if a == nil {
		return ""
	}
	switch {
	case a.URL != "":
		return a.URL
	case a.IP != "":
		return a.IP
	case a.Domain != "":
		return a.Domain
	}
	return ""
}

// FlagDisplay formats the target node as a "{kind} {address}" string suited
// for the header pane. Returns "" when the target node is missing.
func (m *AttackMap) FlagDisplay() string {
	t := m.TargetNode()
	if t == nil {
		return ""
	}
	switch t.SubType {
	case "ssm-parameter":
		// Extract the parameter name from the ARN tail.
		name := arnTail(t.ARN, ":parameter")
		if name == "" {
			return "SSM parameter"
		}
		return "SSM " + name
	case "s3-bucket":
		bucket := arnTail(t.ARN, ":::")
		if bucket == "" {
			return "S3 bucket"
		}
		return "S3 " + bucket + "/flag.txt"
	default:
		return PrettySubType(t.SubType)
	}
}

// arnTail returns the substring of arn after the first occurrence of sep.
// For SSM parameter ARNs the separator is ":parameter" so the returned tail
// includes the leading "/".
func arnTail(arn, sep string) string {
	idx := strings.Index(arn, sep)
	if idx < 0 {
		return ""
	}
	return arn[idx+len(sep):]
}
