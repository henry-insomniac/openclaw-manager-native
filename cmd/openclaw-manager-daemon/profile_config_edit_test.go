package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPreviewOpenClawProfileConfigBuildsFieldChanges(t *testing.T) {
	rootDir := t.TempDir()
	writeProfileConfigFixture(t, rootDir, "demo")

	app := newProfileConfigEditTestApp(t, rootDir, "demo")
	document, err := app.readOpenClawProfileConfigDocument("demo")
	if err != nil {
		t.Fatalf("readOpenClawProfileConfigDocument: %v", err)
	}

	nextProvider := "openai"
	nextModel := "openai/gpt-5"
	nextAuthMode := "api-key"
	preview, err := app.previewOpenClawProfileConfig("demo", OpenClawProfileConfigEditRequest{
		BaseHash: derefString(document.ConfigHash),
		Patch: OpenClawProfileConfigPatch{
			PrimaryProviderID: &nextProvider,
			PrimaryModelID:    &nextModel,
			AuthMode:          &nextAuthMode,
		},
	})
	if err != nil {
		t.Fatalf("previewOpenClawProfileConfig: %v", err)
	}
	if !preview.Changed {
		t.Fatalf("expected preview to be marked changed")
	}
	if len(preview.Changes) != 3 {
		t.Fatalf("expected 3 field changes, got %d", len(preview.Changes))
	}
	if !strings.Contains(preview.PreviewConfig, `"primary": "openai/gpt-5"`) {
		t.Fatalf("expected preview config to include updated primary model, got %s", preview.PreviewConfig)
	}
	if !strings.Contains(preview.PreviewConfig, `"provider": "openai"`) {
		t.Fatalf("expected preview config to include updated provider")
	}
	if !strings.Contains(preview.PreviewConfig, `"mode": "api-key"`) {
		t.Fatalf("expected preview config to include updated auth mode")
	}
}

func TestApplyOpenClawProfileConfigRollsBackWhenValidationFails(t *testing.T) {
	rootDir := t.TempDir()
	writeProfileConfigFixture(t, rootDir, "demo")

	scriptPath := filepath.Join(rootDir, "openclaw")
	scriptBody := strings.Join([]string{
		"#!/bin/sh",
		"if [ \"$1\" = \"--profile\" ] && [ \"$2\" = \"demo\" ] && [ \"$3\" = \"config\" ] && [ \"$4\" = \"validate\" ]; then",
		"  printf '%s\\n' 'Schema mismatch: agents.defaults.model.primary must be string' >&2",
		"  exit 1",
		"fi",
		"printf '%s\\n' \"unexpected args: $*\" >&2",
		"exit 1",
	}, "\n")
	if err := os.WriteFile(scriptPath, []byte(scriptBody), 0o755); err != nil {
		t.Fatalf("write fake openclaw: %v", err)
	}
	t.Setenv("OPENCLAW_BIN", scriptPath)

	app := newProfileConfigEditTestApp(t, rootDir, "demo")
	configPath, err := app.resolveConfigPath("demo")
	if err != nil {
		t.Fatalf("resolveConfigPath: %v", err)
	}
	before, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read original config: %v", err)
	}
	document, err := app.readOpenClawProfileConfigDocument("demo")
	if err != nil {
		t.Fatalf("readOpenClawProfileConfigDocument: %v", err)
	}

	nextModel := "openai-codex/gpt-5.1"
	nextProvider := "openai-codex"
	nextAuthMode := "chatgpt-oauth"
	_, err = app.applyOpenClawProfileConfig("demo", OpenClawProfileConfigEditRequest{
		BaseHash: derefString(document.ConfigHash),
		Patch: OpenClawProfileConfigPatch{
			PrimaryProviderID: &nextProvider,
			PrimaryModelID:    &nextModel,
			AuthMode:          &nextAuthMode,
		},
	})
	if err == nil || !strings.Contains(err.Error(), "已回滚") {
		t.Fatalf("expected rollback error, got %v", err)
	}

	after, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read rolled back config: %v", err)
	}
	if string(before) != string(after) {
		t.Fatalf("expected config to be restored after rollback")
	}
}

func newProfileConfigEditTestApp(t *testing.T, rootDir, activeProfile string) *App {
	t.Helper()

	managerDir := filepath.Join(rootDir, ".manager")
	if err := os.MkdirAll(managerDir, 0o755); err != nil {
		t.Fatalf("mkdir manager dir: %v", err)
	}

	app := &App{
		homeDir:              rootDir,
		openclawHomeDir:      rootDir,
		codexHomeDir:         rootDir,
		managerDir:           managerDir,
		managerStatePath:     filepath.Join(managerDir, "state.json"),
		backupDir:            filepath.Join(managerDir, "backups"),
		defaultOpenClawState: filepath.Join(rootDir, ".openclaw"),
		stateDirCache:        map[string]string{},
	}

	if err := writeJSONFile(app.managerStatePath, ManagerStateFile{
		ActiveProfileName: &activeProfile,
	}); err != nil {
		t.Fatalf("write manager state: %v", err)
	}

	return app
}
