package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReadOpenClawSkillsConfigSummaryRedactsSensitiveFields(t *testing.T) {
	rootDir := t.TempDir()
	stateDir := filepath.Join(rootDir, ".openclaw")
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		t.Fatalf("mkdir state dir: %v", err)
	}

	configPath := filepath.Join(stateDir, "openclaw.json")
	configBody := `{
  "skills": {
    "allowBundled": ["notion", "bear-notes"],
    "load": {
      "extraDirs": ["~/skills", "/tmp/skills"],
      "watch": true,
      "watchDebounceMs": 1500
    },
    "install": {
      "preferBrew": true,
      "nodeManager": "pnpm"
    },
    "entries": {
      "notion": {
        "enabled": false,
        "apiKey": "secret-token",
        "env": {
          "NOTION_API_KEY": "another-secret"
        }
      },
      "openai-image-gen": {
        "apiKey": "secret-openai"
      }
    }
  }
}`
	if err := os.WriteFile(configPath, []byte(configBody), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	app := &App{
		homeDir:              rootDir,
		openclawHomeDir:      rootDir,
		defaultOpenClawState: stateDir,
		stateDirCache:        map[string]string{},
	}

	summary, err := app.readOpenClawSkillsConfigSummary()
	if err != nil {
		t.Fatalf("readOpenClawSkillsConfigSummary: %v", err)
	}

	if !summary.Exists || !summary.Valid {
		t.Fatalf("expected existing valid config, got exists=%v valid=%v detail=%s", summary.Exists, summary.Valid, summary.Detail)
	}
	if summary.ConfigPath != configPath {
		t.Fatalf("unexpected config path: %s", summary.ConfigPath)
	}
	if len(summary.AllowBundled) != 2 {
		t.Fatalf("unexpected allowBundled count: %d", len(summary.AllowBundled))
	}
	if summary.AllowBundled[0] != "notion" || summary.AllowBundled[1] != "bear-notes" {
		t.Fatalf("unexpected allowBundled values: %v", summary.AllowBundled)
	}
	if summary.EntryCount != 2 {
		t.Fatalf("unexpected entry count: %d", summary.EntryCount)
	}
	if len(summary.Entries) != 2 {
		t.Fatalf("unexpected summarized entries: %d", len(summary.Entries))
	}

	var notionEntry OpenClawSkillConfigEntrySummary
	found := false
	for _, entry := range summary.Entries {
		if entry.Key == "notion" {
			notionEntry = entry
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("expected notion entry in summary")
	}
	if notionEntry.Enabled == nil || *notionEntry.Enabled {
		t.Fatalf("expected notion entry to preserve enabled=false")
	}
	if !notionEntry.HasEnv || !notionEntry.HasAPIKey {
		t.Fatalf("expected notion entry to expose only presence of env/apiKey")
	}
}

func TestSummarizeOpenClawSkillsPayloadClassifiesAndCounts(t *testing.T) {
	disabled := false
	configSummary := OpenClawSkillsConfigSummary{
		ConfigPath: "/tmp/openclaw.json",
		Entries: []OpenClawSkillConfigEntrySummary{
			{Key: "notion", Enabled: &disabled, HasEnv: true, HasAPIKey: true},
		},
	}
	payload := openClawSkillsListPayload{
		WorkspaceDir:     "/Users/test/project",
		ManagedSkillsDir: "/Users/test/.openclaw/skills",
		Skills: []openClawSkillsListSkillEntry{
			{
				Name:        "notion",
				Description: "Notion API",
				Eligible:    true,
				Source:      "openclaw-bundled",
				PrimaryEnv:  "NOTION_API_KEY",
			},
			{
				Name:        "apple-notes",
				Description: "Apple Notes",
				Disabled:    true,
				Source:      "openclaw-bundled",
			},
			{
				Name:               "clawhub",
				Description:        "ClawHub",
				BlockedByAllowlist: true,
				Source:             "openclaw-bundled",
			},
			{
				Name:        "bluebubbles",
				Description: "BlueBubbles",
				Source:      "openclaw-bundled",
				Missing: OpenClawSkillMissingRequirements{
					Bins: []string{"blueutil"},
				},
			},
		},
	}

	summary := summarizeOpenClawSkillsPayload(payload, configSummary, "2026-03-13T00:00:00Z")
	if summary.TotalSkills != 4 {
		t.Fatalf("unexpected total skills: %d", summary.TotalSkills)
	}
	if summary.ReadySkills != 1 || summary.DisabledSkills != 1 || summary.BlockedSkills != 1 || summary.MissingSkills != 1 {
		t.Fatalf("unexpected counts: ready=%d disabled=%d blocked=%d missing=%d", summary.ReadySkills, summary.DisabledSkills, summary.BlockedSkills, summary.MissingSkills)
	}
	if summary.ConfiguredSkills != 1 {
		t.Fatalf("unexpected configured skills: %d", summary.ConfiguredSkills)
	}
	if summary.WorkspaceDir == nil || *summary.WorkspaceDir != payload.WorkspaceDir {
		t.Fatalf("unexpected workspace dir: %v", summary.WorkspaceDir)
	}

	var readySkill OpenClawSkillSummary
	for _, skill := range summary.Skills {
		if skill.Key == "notion" {
			readySkill = skill
			break
		}
	}
	if readySkill.Status != "ready" {
		t.Fatalf("expected notion status ready, got %s", readySkill.Status)
	}
	if !readySkill.ConfigConfigured || !readySkill.HasEnvConfig || !readySkill.HasAPIKeyConfig {
		t.Fatalf("expected notion config flags to be preserved")
	}
	if readySkill.ConfigEnabled == nil || *readySkill.ConfigEnabled {
		t.Fatalf("expected notion configEnabled=false")
	}
	if readySkill.PrimaryEnv == nil || *readySkill.PrimaryEnv != "NOTION_API_KEY" {
		t.Fatalf("expected primary env to be preserved")
	}
}

func TestReadOpenClawProfileConfigDocumentIncludesHashes(t *testing.T) {
	rootDir := t.TempDir()
	writeProfileConfigFixture(t, rootDir, "demo")

	app := &App{
		homeDir:              rootDir,
		openclawHomeDir:      rootDir,
		codexHomeDir:         rootDir,
		defaultOpenClawState: filepath.Join(rootDir, ".openclaw"),
		stateDirCache:        map[string]string{},
	}

	document, err := app.readOpenClawProfileConfigDocument("demo")
	if err != nil {
		t.Fatalf("readOpenClawProfileConfigDocument: %v", err)
	}
	if !document.Summary.ConfigValid {
		t.Fatalf("expected configValid=true")
	}
	if document.ConfigHash == nil || *document.ConfigHash == "" {
		t.Fatalf("expected config hash")
	}
	if document.AuthStoreHash == nil || *document.AuthStoreHash == "" {
		t.Fatalf("expected auth store hash")
	}
	if document.Summary.PrimaryProviderID == nil || *document.Summary.PrimaryProviderID != "openai-codex" {
		t.Fatalf("unexpected primary provider: %v", document.Summary.PrimaryProviderID)
	}
}

func TestValidateOpenClawProfileConfigUsesProfileCLIAndFiltersNoise(t *testing.T) {
	rootDir := t.TempDir()
	writeProfileConfigFixture(t, rootDir, "demo")

	scriptPath := filepath.Join(rootDir, "openclaw")
	scriptBody := strings.Join([]string{
		"#!/bin/sh",
		"if [ \"$1\" = \"--profile\" ] && [ \"$2\" = \"demo\" ] && [ \"$3\" = \"config\" ] && [ \"$4\" = \"validate\" ]; then",
		"  printf '%s\\n' 'Config valid: ~/.openclaw-demo/openclaw.json'",
		"  printf '%s\\n' '(node:123) [DEP0040] DeprecationWarning: The `punycode` module is deprecated. Please use a userland alternative instead.' >&2",
		"  printf '%s\\n' '(Use `node --trace-deprecation ...` to show where the warning was created)' >&2",
		"  exit 0",
		"fi",
		"printf '%s\\n' \"unexpected args: $*\" >&2",
		"exit 1",
	}, "\n")
	if err := os.WriteFile(scriptPath, []byte(scriptBody), 0o755); err != nil {
		t.Fatalf("write fake openclaw: %v", err)
	}
	t.Setenv("OPENCLAW_BIN", scriptPath)

	app := &App{
		homeDir:              rootDir,
		openclawHomeDir:      rootDir,
		codexHomeDir:         rootDir,
		defaultOpenClawState: filepath.Join(rootDir, ".openclaw"),
		stateDirCache:        map[string]string{},
	}

	result, err := app.validateOpenClawProfileConfig("demo")
	if err != nil {
		t.Fatalf("validateOpenClawProfileConfig: %v", err)
	}
	if !result.Valid {
		t.Fatalf("expected valid result, got detail=%s output=%v", result.Detail, result.Output)
	}
	if result.ConfigPath != filepath.Join(rootDir, ".openclaw-demo", "openclaw.json") {
		t.Fatalf("unexpected config path: %s", result.ConfigPath)
	}
	if result.Output != nil {
		t.Fatalf("expected success output to be omitted, got %q", *result.Output)
	}
}

func TestValidateOpenClawProfileConfigPreservesRealFailureText(t *testing.T) {
	rootDir := t.TempDir()
	writeProfileConfigFixture(t, rootDir, "demo")

	scriptPath := filepath.Join(rootDir, "openclaw")
	scriptBody := strings.Join([]string{
		"#!/bin/sh",
		"printf '%s\\n' '(node:123) [DEP0040] DeprecationWarning: The `punycode` module is deprecated. Please use a userland alternative instead.' >&2",
		"printf '%s\\n' '(Use `node --trace-deprecation ...` to show where the warning was created)' >&2",
		"printf '%s\\n' 'Schema mismatch: agents.defaults.model.primary must be string' >&2",
		"printf '%s\\n' 'path: agents.defaults.model.primary' >&2",
		"exit 1",
	}, "\n")
	if err := os.WriteFile(scriptPath, []byte(scriptBody), 0o755); err != nil {
		t.Fatalf("write fake openclaw: %v", err)
	}
	t.Setenv("OPENCLAW_BIN", scriptPath)

	app := &App{
		homeDir:              rootDir,
		openclawHomeDir:      rootDir,
		codexHomeDir:         rootDir,
		defaultOpenClawState: filepath.Join(rootDir, ".openclaw"),
		stateDirCache:        map[string]string{},
	}

	result, err := app.validateOpenClawProfileConfig("demo")
	if err != nil {
		t.Fatalf("validateOpenClawProfileConfig: %v", err)
	}
	if result.Valid {
		t.Fatalf("expected invalid result")
	}
	if result.Detail != "Schema mismatch: agents.defaults.model.primary must be string" {
		t.Fatalf("unexpected detail: %q", result.Detail)
	}
	if result.Output == nil || strings.Contains(*result.Output, "punycode") {
		t.Fatalf("expected filtered output without noise, got %v", result.Output)
	}
}

func writeProfileConfigFixture(t *testing.T, rootDir, profileName string) {
	t.Helper()

	stateDir := filepath.Join(rootDir, ".openclaw-"+profileName)
	configPath := filepath.Join(stateDir, "openclaw.json")
	authStorePath := filepath.Join(stateDir, "agents", "main", "agent", "auth-profiles.json")

	if err := writeJSONFile(configPath, map[string]any{
		"agents": map[string]any{
			"defaults": map[string]any{
				"model": map[string]any{
					"primary": "openai-codex/gpt-5",
				},
			},
		},
		"auth": map[string]any{
			"profiles": map[string]any{
				"default": map[string]any{
					"provider": "openai-codex",
					"mode":     "chatgpt-oauth",
				},
			},
		},
	}); err != nil {
		t.Fatalf("write config: %v", err)
	}
	if err := writeJSONFile(authStorePath, defaultAuthStore()); err != nil {
		t.Fatalf("write auth store: %v", err)
	}
}
