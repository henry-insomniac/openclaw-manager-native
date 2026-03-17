package main

import (
	"encoding/json"
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

func TestSyncProfileToDefaultPreservesDefaultSkillsConfig(t *testing.T) {
	rootDir := t.TempDir()
	writeProfileConfigFixture(t, rootDir, "demo")

	defaultStateDir := filepath.Join(rootDir, ".openclaw")
	defaultConfigPath := filepath.Join(defaultStateDir, "openclaw.json")
	defaultAuthStorePath := filepath.Join(defaultStateDir, "agents", "main", "agent", "auth-profiles.json")
	if err := writeJSONFile(defaultConfigPath, map[string]any{
		"agents": map[string]any{
			"defaults": map[string]any{
				"model": map[string]any{
					"primary": "anthropic/claude-sonnet-4",
				},
			},
		},
		"skills": map[string]any{
			"load": map[string]any{
				"extraDirs": []string{"/tmp/manager-skills"},
				"watch":     true,
			},
			"entries": map[string]any{
				"4todo": map[string]any{
					"enabled": true,
				},
			},
		},
	}); err != nil {
		t.Fatalf("write default config: %v", err)
	}
	if err := writeJSONFile(defaultAuthStorePath, defaultAuthStore()); err != nil {
		t.Fatalf("write default auth store: %v", err)
	}

	app := &App{
		homeDir:              rootDir,
		openclawHomeDir:      rootDir,
		codexHomeDir:         rootDir,
		managerDir:           filepath.Join(rootDir, ".manager"),
		backupDir:            filepath.Join(rootDir, ".manager", "backups"),
		defaultOpenClawState: defaultStateDir,
		stateDirCache:        map[string]string{},
	}

	if err := app.syncProfileToDefault("demo"); err != nil {
		t.Fatalf("syncProfileToDefault: %v", err)
	}

	var merged map[string]any
	data, err := os.ReadFile(defaultConfigPath)
	if err != nil {
		t.Fatalf("read merged default config: %v", err)
	}
	if err := json.Unmarshal(data, &merged); err != nil {
		t.Fatalf("unmarshal merged default config: %v", err)
	}

	model := derefString(readOpenClawConfigSnapshot(defaultConfigPath).PrimaryModelID)
	if model != "openai-codex/gpt-5" {
		t.Fatalf("expected source model to sync into default config, got %s", model)
	}
	skillsMap, ok := merged["skills"].(map[string]any)
	if !ok {
		t.Fatalf("expected skills section preserved")
	}
	loadMap, ok := skillsMap["load"].(map[string]any)
	if !ok {
		t.Fatalf("expected skills.load section preserved")
	}
	extraDirs := anyStrings(loadMap["extraDirs"])
	if len(extraDirs) != 1 || extraDirs[0] != "/tmp/manager-skills" {
		t.Fatalf("expected default extraDirs to be preserved, got %v", extraDirs)
	}
	entriesMap, ok := skillsMap["entries"].(map[string]any)
	if !ok {
		t.Fatalf("expected skills.entries preserved")
	}
	if _, ok := entriesMap["4todo"]; !ok {
		t.Fatalf("expected 4todo skill entry preserved")
	}
}

func TestSyncProfileToDefaultBuildsDefaultCodexAuthPool(t *testing.T) {
	rootDir := t.TempDir()
	writeManagedCodexProfileFixture(t, rootDir, "acct-f", "acct-f-id")
	writeManagedCodexProfileFixture(t, rootDir, "acct-g", "acct-g-id")

	defaultStateDir := filepath.Join(rootDir, ".openclaw")
	defaultConfigPath := filepath.Join(defaultStateDir, "openclaw.json")
	defaultAuthStorePath := filepath.Join(defaultStateDir, "agents", "main", "agent", "auth-profiles.json")
	if err := writeJSONFile(defaultConfigPath, map[string]any{
		"agents": map[string]any{
			"defaults": map[string]any{
				"model": map[string]any{
					"primary": "anthropic/claude-sonnet-4",
				},
			},
		},
		"auth": map[string]any{
			"profiles": map[string]any{
				"anthropic:default": map[string]any{
					"provider": "anthropic",
					"mode":     "api-key",
				},
				"openai-codex:stale": map[string]any{
					"provider": "openai-codex",
					"mode":     "oauth",
				},
			},
			"order": map[string]any{
				"anthropic":    []string{"anthropic:default"},
				"openai-codex": []string{"openai-codex:stale"},
			},
		},
		"skills": map[string]any{
			"entries": map[string]any{
				"4todo": map[string]any{
					"enabled": true,
				},
			},
		},
	}); err != nil {
		t.Fatalf("write default config: %v", err)
	}

	defaultStore := defaultAuthStore()
	defaultStore.Profiles["anthropic:default"] = map[string]any{
		"type":     "api-key",
		"provider": "anthropic",
		"apiKey":   "anthropic-secret",
	}
	defaultStore.UsageStats["anthropic:default"] = map[string]any{
		"lastUsed": int64(123),
	}
	defaultStore.UsageStats["openai-codex:acct-g"] = map[string]any{
		"cooldownUntil": "2099-01-01T00:00:00Z",
		"errorCount":    7,
	}
	if err := writeJSONFile(defaultAuthStorePath, defaultStore); err != nil {
		t.Fatalf("write default auth store: %v", err)
	}

	app := &App{
		homeDir:              rootDir,
		openclawHomeDir:      rootDir,
		codexHomeDir:         rootDir,
		managerDir:           filepath.Join(rootDir, ".manager"),
		backupDir:            filepath.Join(rootDir, ".manager", "backups"),
		defaultOpenClawState: defaultStateDir,
		stateDirCache:        map[string]string{},
	}

	if err := app.syncProfileToDefault("acct-f"); err != nil {
		t.Fatalf("syncProfileToDefault: %v", err)
	}

	mergedStore, err := app.loadAuthStore(defaultProfileName)
	if err != nil {
		t.Fatalf("loadAuthStore(default): %v", err)
	}
	if got := mergedStore.LastGood["openai-codex"]; got != "openai-codex:acct-f" {
		t.Fatalf("expected active account to become lastGood, got %q", got)
	}
	if _, ok := mergedStore.Profiles["openai-codex:acct-f"]; !ok {
		t.Fatalf("expected acct-f runtime auth profile")
	}
	if _, ok := mergedStore.Profiles["openai-codex:acct-g"]; !ok {
		t.Fatalf("expected acct-g runtime auth profile")
	}
	if _, ok := mergedStore.Profiles["anthropic:default"]; !ok {
		t.Fatalf("expected non-codex auth profile to be preserved")
	}
	if got := anyString(mergedStore.UsageStats["openai-codex:acct-g"]["cooldownUntil"]); got != "2099-01-01T00:00:00Z" {
		t.Fatalf("expected target cooldown metadata to be preserved, got %q", got)
	}
	if errorCount, ok := anyInt64(mergedStore.UsageStats["openai-codex:acct-g"]["errorCount"]); !ok || errorCount != 7 {
		t.Fatalf("expected preserved errorCount=7, got %v ok=%v", mergedStore.UsageStats["openai-codex:acct-g"]["errorCount"], ok)
	}

	var merged map[string]any
	data, err := os.ReadFile(defaultConfigPath)
	if err != nil {
		t.Fatalf("read merged default config: %v", err)
	}
	if err := json.Unmarshal(data, &merged); err != nil {
		t.Fatalf("unmarshal merged default config: %v", err)
	}

	model := derefString(readOpenClawConfigSnapshot(defaultConfigPath).PrimaryModelID)
	if model != "openai-codex/gpt-5" {
		t.Fatalf("expected source model to sync into default config, got %s", model)
	}
	authMap, ok := merged["auth"].(map[string]any)
	if !ok {
		t.Fatalf("expected auth section in merged config")
	}
	profilesMap, ok := authMap["profiles"].(map[string]any)
	if !ok {
		t.Fatalf("expected auth.profiles in merged config")
	}
	if _, ok := profilesMap["openai-codex:acct-f"]; !ok {
		t.Fatalf("expected acct-f auth profile entry in default config")
	}
	if _, ok := profilesMap["openai-codex:acct-g"]; !ok {
		t.Fatalf("expected acct-g auth profile entry in default config")
	}
	if _, ok := profilesMap["anthropic:default"]; !ok {
		t.Fatalf("expected non-codex auth config entry to be preserved")
	}
	if _, ok := profilesMap["openai-codex:stale"]; ok {
		t.Fatalf("expected stale codex config entry to be removed")
	}
	orderMap, ok := authMap["order"].(map[string]any)
	if !ok {
		t.Fatalf("expected auth.order in merged config")
	}
	order := anyStrings(orderMap["openai-codex"])
	if len(order) != 2 || order[0] != "openai-codex:acct-f" || order[1] != "openai-codex:acct-g" {
		t.Fatalf("expected active-first codex order, got %v", order)
	}

	defaultCodexAuth := readJSONFile(resolveCodexAuthPath(defaultProfileName, rootDir), CodexAuthFile{})
	if defaultCodexAuth.Tokens.AccountID != "acct-f-id" {
		t.Fatalf("expected active codex auth file to sync, got account %q", defaultCodexAuth.Tokens.AccountID)
	}
}

func TestResolveCurrentRuntimeAuthSelectionMapsBackToManagedProfile(t *testing.T) {
	rootDir := t.TempDir()
	writeManagedCodexProfileFixture(t, rootDir, "acct-f", "acct-f-id")
	writeManagedCodexProfileFixture(t, rootDir, "acct-g", "acct-g-id")

	defaultStateDir := filepath.Join(rootDir, ".openclaw")
	defaultConfigPath := filepath.Join(defaultStateDir, "openclaw.json")
	defaultAuthStorePath := filepath.Join(defaultStateDir, "agents", "main", "agent", "auth-profiles.json")
	if err := writeJSONFile(defaultConfigPath, map[string]any{
		"agents": map[string]any{
			"defaults": map[string]any{
				"model": map[string]any{
					"primary": "openai-codex/gpt-5",
				},
			},
		},
		"auth": map[string]any{
			"profiles": map[string]any{},
		},
	}); err != nil {
		t.Fatalf("write default config: %v", err)
	}
	if err := writeJSONFile(defaultAuthStorePath, defaultAuthStore()); err != nil {
		t.Fatalf("write default auth store: %v", err)
	}

	app := &App{
		homeDir:              rootDir,
		openclawHomeDir:      rootDir,
		codexHomeDir:         rootDir,
		managerDir:           filepath.Join(rootDir, ".manager"),
		backupDir:            filepath.Join(rootDir, ".manager", "backups"),
		defaultOpenClawState: defaultStateDir,
		stateDirCache:        map[string]string{},
	}

	if err := app.syncProfileToDefault("acct-f"); err != nil {
		t.Fatalf("syncProfileToDefault: %v", err)
	}

	store, err := app.loadAuthStore(defaultProfileName)
	if err != nil {
		t.Fatalf("loadAuthStore(default): %v", err)
	}
	store.LastGood["openai-codex"] = "openai-codex:acct-g"
	store.UsageStats["openai-codex:acct-g"] = map[string]any{
		"lastUsed": int64(1893456000000),
	}
	if err := app.saveAuthStore(defaultProfileName, store); err != nil {
		t.Fatalf("saveAuthStore(default): %v", err)
	}

	profiles := []ManagedProfileSnapshot{
		{
			Name:         defaultProfileName,
			IsDefault:    true,
			AccountID:    ptr("acct-f-id"),
			AccountEmail: ptr("default@example.com"),
		},
		{
			Name:         "acct-f",
			AccountID:    ptr("acct-f-id"),
			AccountEmail: ptr("acct-f@example.com"),
		},
		{
			Name:         "acct-g",
			AccountID:    ptr("acct-g-id"),
			AccountEmail: ptr("acct-g@example.com"),
		},
	}

	selection := app.resolveCurrentRuntimeAuthSelection(profiles)
	if selection == nil {
		t.Fatalf("expected runtime auth selection")
	}
	if derefString(selection.ProviderID) != "openai-codex" {
		t.Fatalf("unexpected provider: %v", selection.ProviderID)
	}
	if derefString(selection.ProfileID) != "openai-codex:acct-g" {
		t.Fatalf("unexpected profile id: %v", selection.ProfileID)
	}
	if derefString(selection.ManagedProfileName) != "acct-g" {
		t.Fatalf("expected mapped managed profile acct-g, got %v", selection.ManagedProfileName)
	}
	if derefString(selection.AccountEmail) != "acct-g@example.com" {
		t.Fatalf("expected managed profile email, got %v", selection.AccountEmail)
	}
	if derefString(selection.AccountID) != "acct-g-id" {
		t.Fatalf("expected managed profile account id, got %v", selection.AccountID)
	}
	if selection.LastUsedAt == nil || *selection.LastUsedAt == "" {
		t.Fatalf("expected lastUsedAt to be populated")
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

func writeManagedCodexProfileFixture(t *testing.T, rootDir, profileName, accountID string) {
	t.Helper()

	writeProfileConfigFixture(t, rootDir, profileName)

	stateDir := filepath.Join(rootDir, ".openclaw-"+profileName)
	authStorePath := filepath.Join(stateDir, "agents", "main", "agent", "auth-profiles.json")
	tokens := OAuthTokens{
		Access:    "access-" + profileName,
		Refresh:   "refresh-" + profileName,
		IDToken:   "id-" + profileName,
		Expires:   1893456000000,
		AccountID: accountID,
	}

	store := defaultAuthStore()
	upsertOpenAICodexCredential(&store, "openai-codex:default", tokens)
	if err := writeJSONFile(authStorePath, store); err != nil {
		t.Fatalf("write codex auth store: %v", err)
	}

	authFile, err := buildCodexAuthFile(tokens)
	if err != nil {
		t.Fatalf("build codex auth file: %v", err)
	}
	if err := writeJSONFile(resolveCodexAuthPath(profileName, rootDir), authFile); err != nil {
		t.Fatalf("write codex auth file: %v", err)
	}
}
