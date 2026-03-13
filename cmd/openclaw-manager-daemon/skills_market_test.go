package main

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestParseAwesomeCategoryPathsDedupes(t *testing.T) {
	readme := `
[View all](categories/git-and-github.md)
[View all again](categories/git-and-github.md)
[Another](categories/devops-and-cloud.md)
`

	paths := parseAwesomeCategoryPaths(readme)
	if len(paths) != 2 {
		t.Fatalf("expected 2 unique paths, got %d: %v", len(paths), paths)
	}
	if paths[0] != "categories/devops-and-cloud.md" || paths[1] != "categories/git-and-github.md" {
		t.Fatalf("unexpected category paths: %v", paths)
	}
}

func TestParseAwesomeCategoryMarkdownExtractsSkills(t *testing.T) {
	markdown := `# Git & GitHub

- [demo-skill](https://github.com/openclaw/skills/tree/main/skills/demo-owner/demo-skill/SKILL.md) - Demo summary.
- [second-skill](https://github.com/openclaw/skills/tree/main/skills/another/second-skill) - Another summary.
`

	title, items, err := parseAwesomeCategoryMarkdown("categories/git-and-github.md", markdown)
	if err != nil {
		t.Fatalf("parseAwesomeCategoryMarkdown: %v", err)
	}
	if title != "Git & GitHub" {
		t.Fatalf("unexpected title: %s", title)
	}
	if len(items) != 2 {
		t.Fatalf("unexpected item count: %d", len(items))
	}
	if items[0].Slug != "demo-skill" || items[0].Owner != "demo-owner" {
		t.Fatalf("unexpected first item: %+v", items[0])
	}
	if items[1].Slug != "second-skill" || items[1].Owner != "another" {
		t.Fatalf("unexpected second item: %+v", items[1])
	}
}

func TestBuildOpenClawSkillsMarketSummaryUsesClawHubBrowseByDefault(t *testing.T) {
	listHits := 0
	readmeHits := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/v1/skills":
			listHits++
			if got := r.URL.Query().Get("sort"); got != "downloads" {
				t.Fatalf("expected downloads sort, got %q", got)
			}
			if got := r.URL.Query().Get("limit"); got != "100" {
				t.Fatalf("expected limit=100, got %q", got)
			}
			w.Header().Set("Content-Type", "application/json")
			if r.URL.Query().Get("cursor") == "" {
				_ = json.NewEncoder(w).Encode(map[string]any{
					"items": []map[string]any{
						{
							"slug":        "notion",
							"displayName": "Notion",
							"summary":     "Notion API for creating and managing pages, databases, and blocks.",
							"tags":        map[string]any{"latest": "1.0.0"},
							"stats": map[string]any{
								"downloads":       320,
								"installsAllTime": 120,
								"stars":           40,
							},
							"updatedAt": int64(1_773_122_478_761),
							"latestVersion": map[string]any{
								"version": "1.0.0",
							},
						},
						{
							"slug":        "github",
							"displayName": "GitHub",
							"summary":     "Manage repositories, issues, and pull requests via GitHub API.",
							"tags":        map[string]any{"latest": "2.0.0"},
							"stats": map[string]any{
								"downloads":       200,
								"installsAllTime": 90,
								"stars":           55,
							},
							"updatedAt": int64(1_773_120_000_000),
							"latestVersion": map[string]any{
								"version": "2.0.0",
							},
						},
					},
					"nextCursor": "page-2",
				})
				return
			}
			if got := r.URL.Query().Get("cursor"); got != "page-2" {
				t.Fatalf("unexpected cursor: %q", got)
			}
			_ = json.NewEncoder(w).Encode(map[string]any{
				"items": []map[string]any{
					{
						"slug":        "weather",
						"displayName": "Weather",
						"summary":     "Search weather forecasts for cities and regions.",
						"tags":        map[string]any{"latest": "0.9.0"},
						"stats": map[string]any{
							"downloads":       180,
							"installsAllTime": 75,
							"stars":           25,
						},
						"updatedAt": int64(1_773_110_000_000),
						"latestVersion": map[string]any{
							"version": "0.9.0",
						},
					},
				},
			})
		case "/README.md":
			readmeHits++
			http.Error(w, "awesome should not be used", http.StatusInternalServerError)
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	t.Setenv("OPENCLAW_CLAWHUB_API_BASE_URL", server.URL+"/api/v1")
	t.Setenv("OPENCLAW_CLAWHUB_WEB_BASE_URL", server.URL)
	t.Setenv("OPENCLAW_SKILLS_MARKET_RAW_BASE_URL", server.URL)

	app := &App{managerDir: t.TempDir()}
	summary, err := app.buildOpenClawSkillsMarketSummary(false, "", "")
	if err != nil {
		t.Fatalf("buildOpenClawSkillsMarketSummary: %v", err)
	}
	if listHits != 2 {
		t.Fatalf("expected 2 list requests, got %d", listHits)
	}
	if readmeHits != 0 {
		t.Fatalf("expected no awesome fallback, got %d README hits", readmeHits)
	}
	if summary.IsSearchResult {
		t.Fatalf("expected browse summary, got search result")
	}
	if summary.Sort != "downloads" {
		t.Fatalf("expected downloads sort, got %q", summary.Sort)
	}
	if summary.SourceRepo != server.URL+"/api/v1/skills?limit=100&sort=downloads" {
		t.Fatalf("unexpected source repo: %s", summary.SourceRepo)
	}
	if summary.TotalItems != 3 || len(summary.Items) != 3 {
		t.Fatalf("expected 3 items, got total=%d len=%d", summary.TotalItems, len(summary.Items))
	}
	if summary.Items[0].Slug != "notion" {
		t.Fatalf("expected notion to remain first by downloads, got %s", summary.Items[0].Slug)
	}
	if got := summary.Items[0].SummaryZh; !strings.Contains(got, "数据库") || !strings.Contains(got, "Notion API") {
		t.Fatalf("expected localized summary for notion, got %q", got)
	}
	if len(summary.Categories) == 0 {
		t.Fatalf("expected inferred categories for browse summary")
	}
}

func TestBuildOpenClawSkillsMarketSummaryUsesClawHubSearchForQuery(t *testing.T) {
	searchHits := 0
	listHits := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/v1/search":
			searchHits++
			if got := r.URL.Query().Get("q"); got != "notion" {
				t.Fatalf("expected q=notion, got %q", got)
			}
			if got := r.URL.Query().Get("limit"); got != "40" {
				t.Fatalf("expected limit=40, got %q", got)
			}
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"results": []map[string]any{
					{
						"slug":        "notion",
						"displayName": "Notion",
						"summary":     "Notion API for creating and managing pages, databases, and blocks.",
						"version":     "1.4.0",
						"updatedAt":   int64(1_773_122_478_761),
					},
				},
			})
		case "/api/v1/skills":
			listHits++
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{"items": []map[string]any{}})
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	t.Setenv("OPENCLAW_CLAWHUB_API_BASE_URL", server.URL+"/api/v1")
	t.Setenv("OPENCLAW_CLAWHUB_WEB_BASE_URL", server.URL)

	app := &App{managerDir: t.TempDir()}
	summary, err := app.buildOpenClawSkillsMarketSummary(false, "notion", "")
	if err != nil {
		t.Fatalf("buildOpenClawSkillsMarketSummary search: %v", err)
	}
	if searchHits != 1 {
		t.Fatalf("expected 1 search hit, got %d", searchHits)
	}
	if listHits != 1 {
		t.Fatalf("expected 1 browse hit for local merge, got %d", listHits)
	}
	if !summary.IsSearchResult {
		t.Fatalf("expected search summary")
	}
	if summary.Query != "notion" {
		t.Fatalf("unexpected query echo: %q", summary.Query)
	}
	if summary.Sort != "relevance" {
		t.Fatalf("expected relevance sort for search, got %q", summary.Sort)
	}
	if summary.SourceRepo != server.URL+"/api/v1/search?limit=40&q=notion" {
		t.Fatalf("unexpected search source: %s", summary.SourceRepo)
	}
	if len(summary.Items) != 1 || summary.Items[0].Slug != "notion" {
		t.Fatalf("unexpected search items: %+v", summary.Items)
	}
	if got := summary.Items[0].SummaryZh; !strings.Contains(got, "数据库") {
		t.Fatalf("expected localized summary in search result, got %q", got)
	}
}

func TestBuildOpenClawSkillsMarketSummaryFallsBackToLocalChineseSearch(t *testing.T) {
	searchHits := 0
	listHits := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/v1/search":
			searchHits++
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{"results": []map[string]any{}})
		case "/api/v1/skills":
			listHits++
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"items": []map[string]any{
					{
						"slug":        "notion",
						"displayName": "Notion",
						"summary":     "Notion API for creating and managing pages, databases, and blocks.",
						"tags":        map[string]any{"latest": "1.0.0"},
						"stats": map[string]any{
							"downloads":       320,
							"installsAllTime": 120,
							"stars":           40,
						},
						"updatedAt": int64(1_773_122_478_761),
						"latestVersion": map[string]any{
							"version": "1.0.0",
						},
					},
				},
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	t.Setenv("OPENCLAW_CLAWHUB_API_BASE_URL", server.URL+"/api/v1")
	t.Setenv("OPENCLAW_CLAWHUB_WEB_BASE_URL", server.URL)

	app := &App{managerDir: t.TempDir()}
	summary, err := app.buildOpenClawSkillsMarketSummary(false, "数据库", "")
	if err != nil {
		t.Fatalf("buildOpenClawSkillsMarketSummary chinese query: %v", err)
	}
	if searchHits != 1 || listHits != 1 {
		t.Fatalf("expected search+browse fallback once, got search=%d list=%d", searchHits, listHits)
	}
	if len(summary.Items) != 1 || summary.Items[0].Slug != "notion" {
		t.Fatalf("expected localized fallback to return notion, got %+v", summary.Items)
	}
	if got := summary.Items[0].SummaryZh; !strings.Contains(got, "数据库") {
		t.Fatalf("expected chinese summary to drive local match, got %q", got)
	}
}

func TestLocalizeSkillSummaryPatterns(t *testing.T) {
	cases := []struct {
		name    string
		summary string
		wants   []string
	}{
		{
			name:    "Notion",
			summary: "Notion API for creating and managing pages, databases, and blocks.",
			wants:   []string{"Notion API", "页面", "数据库"},
		},
		{
			name:    "Find Skills",
			summary: "Helps users discover and install agent skills when they ask questions like \"how do I do X\".",
			wants:   []string{"发现并安装可用技能"},
		},
		{
			name:    "self-improving-agent",
			summary: "Captures learnings, errors, and corrections to enable continuous improvement.",
			wants:   []string{"经验", "持续改进"},
		},
	}

	for _, tc := range cases {
		got := localizeSkillSummary(tc.name, tc.summary, nil)
		if got == "" {
			t.Fatalf("expected localized summary for %s", tc.name)
		}
		if got == tc.summary {
			t.Fatalf("expected localized summary to differ from english for %s", tc.name)
		}
		for _, want := range tc.wants {
			if !strings.Contains(got, want) {
				t.Fatalf("expected %q to contain %q, got %q", tc.name, want, got)
			}
		}
	}
}

func TestInstallAndUninstallOpenClawSkill(t *testing.T) {
	zipBuffer := bytes.NewBuffer(nil)
	zipWriter := zip.NewWriter(zipBuffer)
	skillFile, err := zipWriter.Create("SKILL.md")
	if err != nil {
		t.Fatalf("create zip entry: %v", err)
	}
	if _, err := skillFile.Write([]byte("# Demo Skill\n")); err != nil {
		t.Fatalf("write zip entry: %v", err)
	}
	if err := zipWriter.Close(); err != nil {
		t.Fatalf("close zip: %v", err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/README.md":
			_, _ = w.Write([]byte(`
[View all](categories/git-and-github.md)
`))
		case r.URL.Path == "/categories/git-and-github.md":
			_, _ = w.Write([]byte(`
# Git & GitHub

- [demo-skill](https://github.com/openclaw/skills/tree/main/skills/demo-owner/demo-skill/SKILL.md) - Demo summary.
`))
		case r.URL.Path == "/api/v1/skills/demo-skill":
			payload := map[string]any{
				"skill": map[string]any{
					"slug":        "demo-skill",
					"displayName": "Demo Skill",
					"summary":     "Demo summary.",
					"stats": map[string]any{
						"comments":        1,
						"downloads":       2,
						"installsAllTime": 3,
						"installsCurrent": 1,
						"stars":           4,
						"versions":        1,
					},
					"createdAt": int64(1_773_300_000_000),
					"updatedAt": int64(1_773_300_100_000),
				},
				"latestVersion": map[string]any{
					"version":   "1.2.3",
					"createdAt": int64(1_773_300_100_000),
					"changelog": "Initial release",
					"license":   "MIT",
				},
				"metadata": map[string]any{
					"os":      []string{"darwin"},
					"systems": []string{"git"},
				},
				"owner": map[string]any{
					"handle":      "demo-owner",
					"displayName": "Demo Owner",
					"image":       "https://example.com/avatar.png",
				},
				"moderation": map[string]any{
					"verdict":          "clean",
					"isSuspicious":     false,
					"isMalwareBlocked": false,
					"reasonCodes":      []string{},
					"summary":          "",
					"updatedAt":        int64(1_773_300_100_000),
				},
			}
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(payload)
		case r.URL.Path == "/api/v1/download":
			w.Header().Set("Content-Type", "application/zip")
			_, _ = w.Write(zipBuffer.Bytes())
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	t.Setenv("OPENCLAW_SKILLS_MARKET_RAW_BASE_URL", server.URL)
	t.Setenv("OPENCLAW_CLAWHUB_API_BASE_URL", server.URL+"/api/v1")
	t.Setenv("OPENCLAW_CLAWHUB_WEB_BASE_URL", server.URL)

	rootDir := t.TempDir()
	stateDir := filepath.Join(rootDir, ".openclaw")
	managerDir := filepath.Join(rootDir, ".manager")
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		t.Fatalf("mkdir state dir: %v", err)
	}
	if err := os.MkdirAll(managerDir, 0o755); err != nil {
		t.Fatalf("mkdir manager dir: %v", err)
	}

	configPath := filepath.Join(stateDir, "openclaw.json")
	if err := os.WriteFile(configPath, []byte(`{
  "agents": {"defaults": {"model": {"primary": "openai-codex/gpt-5"}}},
  "custom": {"keep": true},
  "skills": {
    "allowBundled": ["notion"],
    "load": {"extraDirs": ["/already/there"]}
  }
}`), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	app := &App{
		homeDir:                 rootDir,
		openclawHomeDir:         rootDir,
		managerDir:              managerDir,
		backupDir:               filepath.Join(managerDir, "backups"),
		defaultOpenClawState:    stateDir,
		stateDirCache:           map[string]string{},
		skillsMarketDetailCache: map[string]cachedOpenClawSkillMarketDetail{},
	}

	result, err := app.installOpenClawSkill("demo-skill")
	if err != nil {
		t.Fatalf("installOpenClawSkill: %v", err)
	}
	if !result.OK || result.Action != "install" {
		t.Fatalf("unexpected install result: %+v", result)
	}

	targetDir := filepath.Join(managerDir, "skills-market", "demo-skill")
	if !pathExists(filepath.Join(targetDir, "SKILL.md")) {
		t.Fatalf("expected extracted skill in %s", targetDir)
	}
	if !pathExists(filepath.Join(targetDir, ".clawhub", "origin.json")) {
		t.Fatalf("expected origin.json")
	}

	lock := readJSONFile(filepath.Join(managerDir, "skills-market", ".clawhub", "lock.json"), clawHubLockFile{})
	if _, ok := lock.Skills["demo-skill"]; !ok {
		t.Fatalf("expected lock entry for demo-skill")
	}

	var updatedConfig map[string]any
	configData, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read updated config: %v", err)
	}
	if err := json.Unmarshal(configData, &updatedConfig); err != nil {
		t.Fatalf("unmarshal updated config: %v", err)
	}
	customSection, ok := updatedConfig["custom"].(map[string]any)
	if !ok || customSection["keep"] != true {
		t.Fatalf("expected custom section preserved, got %#v", updatedConfig["custom"])
	}
	skillsSection, ok := updatedConfig["skills"].(map[string]any)
	if !ok {
		t.Fatalf("expected skills section")
	}
	loadSection, ok := skillsSection["load"].(map[string]any)
	if !ok {
		t.Fatalf("expected load section")
	}
	extraDirs := anyStrings(loadSection["extraDirs"])
	if !containsString(extraDirs, filepath.Join(managerDir, "skills-market")) {
		t.Fatalf("expected managed skills dir in extraDirs, got %v", extraDirs)
	}

	uninstallResult, err := app.uninstallOpenClawSkill("demo-skill")
	if err != nil {
		t.Fatalf("uninstallOpenClawSkill: %v", err)
	}
	if !uninstallResult.OK || uninstallResult.Action != "uninstall" {
		t.Fatalf("unexpected uninstall result: %+v", uninstallResult)
	}
	if pathExists(targetDir) {
		t.Fatalf("expected skill directory removed")
	}

	lock = readJSONFile(filepath.Join(managerDir, "skills-market", ".clawhub", "lock.json"), clawHubLockFile{})
	if _, ok := lock.Skills["demo-skill"]; ok {
		t.Fatalf("expected lock entry removed after uninstall")
	}
}

func TestDownloadClawHubSkillArchiveRetriesRateLimit(t *testing.T) {
	zipBuffer := bytes.NewBuffer(nil)
	zipWriter := zip.NewWriter(zipBuffer)
	file, err := zipWriter.Create("SKILL.md")
	if err != nil {
		t.Fatalf("create zip entry: %v", err)
	}
	if _, err := file.Write([]byte("# Retry Skill\n")); err != nil {
		t.Fatalf("write zip entry: %v", err)
	}
	if err := zipWriter.Close(); err != nil {
		t.Fatalf("close zip: %v", err)
	}

	attempts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/download" {
			http.NotFound(w, r)
			return
		}
		attempts++
		if attempts == 1 {
			w.Header().Set("Retry-After", "1")
			http.Error(w, "Rate limit exceeded", http.StatusTooManyRequests)
			return
		}
		w.Header().Set("Content-Type", "application/zip")
		_, _ = w.Write(zipBuffer.Bytes())
	}))
	defer server.Close()

	t.Setenv("OPENCLAW_CLAWHUB_API_BASE_URL", server.URL+"/api/v1")

	startedAt := time.Now()
	data, notice, err := (&App{}).downloadClawHubSkillArchive("retry-skill", "1.0.0")
	if err != nil {
		t.Fatalf("downloadClawHubSkillArchive: %v", err)
	}
	if len(data) == 0 {
		t.Fatalf("expected downloaded archive")
	}
	if attempts != 2 {
		t.Fatalf("expected 2 attempts, got %d", attempts)
	}
	if time.Since(startedAt) < time.Second {
		t.Fatalf("expected retry wait before second attempt")
	}
	if notice == "" {
		t.Fatalf("expected non-empty retry notice")
	}
}

func TestEnsureManagerSkillsMountConfiguredRepairsMissingExtraDir(t *testing.T) {
	rootDir := t.TempDir()
	stateDir := filepath.Join(rootDir, ".openclaw")
	managerDir := filepath.Join(rootDir, ".manager")
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		t.Fatalf("mkdir state dir: %v", err)
	}
	if err := os.MkdirAll(managerDir, 0o755); err != nil {
		t.Fatalf("mkdir manager dir: %v", err)
	}

	configPath := filepath.Join(stateDir, "openclaw.json")
	if err := os.WriteFile(configPath, []byte(`{"skills":{"load":{"watch":true}}}`), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	installRoot := filepath.Join(managerDir, "skills-market")
	originPath := filepath.Join(installRoot, "demo-skill", ".clawhub", "origin.json")
	if err := writeJSONFile(originPath, clawHubOriginFile{
		Version:          1,
		Registry:         defaultClawHubWebBaseURL,
		Slug:             "demo-skill",
		InstalledVersion: ptr("1.2.3"),
		InstalledAt:      time.Now().UnixMilli(),
	}); err != nil {
		t.Fatalf("write origin: %v", err)
	}

	app := &App{
		homeDir:              rootDir,
		openclawHomeDir:      rootDir,
		managerDir:           managerDir,
		backupDir:            filepath.Join(managerDir, "backups"),
		defaultOpenClawState: stateDir,
		stateDirCache:        map[string]string{},
	}

	repaired, err := app.ensureManagerSkillsMountConfigured()
	if err != nil {
		t.Fatalf("ensureManagerSkillsMountConfigured: %v", err)
	}
	if !repaired {
		t.Fatalf("expected mount repair to run")
	}

	var updated map[string]any
	data, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read updated config: %v", err)
	}
	if err := json.Unmarshal(data, &updated); err != nil {
		t.Fatalf("unmarshal updated config: %v", err)
	}
	loadMap := ensureMap(ensureMap(updated, "skills"), "load")
	extraDirs := anyStrings(loadMap["extraDirs"])
	if !containsString(extraDirs, installRoot) {
		t.Fatalf("expected install root to be reattached, got %v", extraDirs)
	}
}

func TestClassifyInventorySourceRecognizesPersonalSkills(t *testing.T) {
	skill := OpenClawSkillSummary{
		Key:    "adapt",
		Name:   "adapt",
		Source: "agents-skills-personal",
	}
	if got := classifyInventorySource(skill, nil, nil, false); got != "personal" {
		t.Fatalf("expected personal source, got %s", got)
	}
}

func TestSetOpenClawSkillEnabledPreservesConfigAndAllowBundled(t *testing.T) {
	rootDir := t.TempDir()
	stateDir := filepath.Join(rootDir, ".openclaw")
	managerDir := filepath.Join(rootDir, ".manager")
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		t.Fatalf("mkdir state dir: %v", err)
	}
	if err := os.MkdirAll(managerDir, 0o755); err != nil {
		t.Fatalf("mkdir manager dir: %v", err)
	}

	configPath := filepath.Join(stateDir, "openclaw.json")
	if err := os.WriteFile(configPath, []byte(`{
  "custom": {"keep": true},
  "skills": {
    "allowBundled": ["notion"],
    "entries": {
      "demo-skill": {
        "enabled": false,
        "env": {"DEMO_TOKEN": "secret"}
      }
    }
  }
}`), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	app := &App{
		homeDir:              rootDir,
		openclawHomeDir:      rootDir,
		managerDir:           managerDir,
		backupDir:            filepath.Join(managerDir, "backups"),
		defaultOpenClawState: stateDir,
		stateDirCache:        map[string]string{},
	}

	result, err := app.setOpenClawSkillEnabled("demo-skill", true, true)
	if err != nil {
		t.Fatalf("setOpenClawSkillEnabled: %v", err)
	}
	if !result.OK || result.Action != "enable" {
		t.Fatalf("unexpected result: %+v", result)
	}

	var updated map[string]any
	data, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if err := json.Unmarshal(data, &updated); err != nil {
		t.Fatalf("unmarshal config: %v", err)
	}

	customSection, ok := updated["custom"].(map[string]any)
	if !ok || customSection["keep"] != true {
		t.Fatalf("expected custom section preserved, got %#v", updated["custom"])
	}
	skillsSection, ok := updated["skills"].(map[string]any)
	if !ok {
		t.Fatalf("expected skills section")
	}
	allowBundled := anyStrings(skillsSection["allowBundled"])
	if !containsString(allowBundled, "demo-skill") || !containsString(allowBundled, "notion") {
		t.Fatalf("expected allowBundled updated, got %v", allowBundled)
	}
	entriesSection, ok := skillsSection["entries"].(map[string]any)
	if !ok {
		t.Fatalf("expected entries section")
	}
	entry, ok := entriesSection["demo-skill"].(map[string]any)
	if !ok {
		t.Fatalf("expected demo-skill entry")
	}
	if enabled, ok := entry["enabled"].(bool); !ok || !enabled {
		t.Fatalf("expected enabled=true, got %#v", entry["enabled"])
	}
	envSection, ok := entry["env"].(map[string]any)
	if !ok || envSection["DEMO_TOKEN"] != "secret" {
		t.Fatalf("expected env preserved, got %#v", entry["env"])
	}

	backups, err := os.ReadDir(app.backupDir)
	if err != nil {
		t.Fatalf("read backup dir: %v", err)
	}
	if len(backups) == 0 {
		t.Fatalf("expected config backup to be created")
	}
}

func TestSetOpenClawSkillDisabledKeepsAllowBundled(t *testing.T) {
	rootDir := t.TempDir()
	stateDir := filepath.Join(rootDir, ".openclaw")
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		t.Fatalf("mkdir state dir: %v", err)
	}

	configPath := filepath.Join(stateDir, "openclaw.json")
	if err := os.WriteFile(configPath, []byte(`{
  "skills": {
    "allowBundled": ["demo-skill"],
    "entries": {
      "demo-skill": {
        "enabled": true
      }
    }
  }
}`), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	app := &App{
		homeDir:              rootDir,
		openclawHomeDir:      rootDir,
		backupDir:            filepath.Join(rootDir, ".manager", "backups"),
		defaultOpenClawState: stateDir,
		stateDirCache:        map[string]string{},
	}

	result, err := app.setOpenClawSkillEnabled("demo-skill", false, true)
	if err != nil {
		t.Fatalf("setOpenClawSkillEnabled: %v", err)
	}
	if !result.OK || result.Action != "disable" {
		t.Fatalf("unexpected result: %+v", result)
	}

	var updated map[string]any
	data, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if err := json.Unmarshal(data, &updated); err != nil {
		t.Fatalf("unmarshal config: %v", err)
	}

	skillsSection := updated["skills"].(map[string]any)
	allowBundled := anyStrings(skillsSection["allowBundled"])
	if !containsString(allowBundled, "demo-skill") {
		t.Fatalf("expected allowBundled to stay intact, got %v", allowBundled)
	}
	entry := skillsSection["entries"].(map[string]any)["demo-skill"].(map[string]any)
	if enabled, ok := entry["enabled"].(bool); !ok || enabled {
		t.Fatalf("expected enabled=false, got %#v", entry["enabled"])
	}
}

func TestAddAndRemoveOpenClawSkillsExtraDirPreservesConfig(t *testing.T) {
	rootDir := t.TempDir()
	stateDir := filepath.Join(rootDir, ".openclaw")
	managerDir := filepath.Join(rootDir, ".manager")
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		t.Fatalf("mkdir state dir: %v", err)
	}
	if err := os.MkdirAll(managerDir, 0o755); err != nil {
		t.Fatalf("mkdir manager dir: %v", err)
	}

	configPath := filepath.Join(stateDir, "openclaw.json")
	if err := os.WriteFile(configPath, []byte(`{
  "custom": {"keep": true},
  "skills": {
    "load": {
      "extraDirs": ["/already/there"]
    }
  }
}`), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	app := &App{
		homeDir:              rootDir,
		openclawHomeDir:      rootDir,
		managerDir:           managerDir,
		backupDir:            filepath.Join(managerDir, "backups"),
		defaultOpenClawState: stateDir,
		stateDirCache:        map[string]string{},
	}

	addResult, err := app.addOpenClawSkillsExtraDir("/tmp/custom-skills")
	if err != nil {
		t.Fatalf("addOpenClawSkillsExtraDir: %v", err)
	}
	if !addResult.OK || addResult.Action != "add-extra-dir" {
		t.Fatalf("unexpected add result: %+v", addResult)
	}

	removeResult, err := app.removeOpenClawSkillsExtraDir("/already/there")
	if err != nil {
		t.Fatalf("removeOpenClawSkillsExtraDir: %v", err)
	}
	if !removeResult.OK || removeResult.Action != "remove-extra-dir" {
		t.Fatalf("unexpected remove result: %+v", removeResult)
	}

	var updated map[string]any
	data, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if err := json.Unmarshal(data, &updated); err != nil {
		t.Fatalf("unmarshal config: %v", err)
	}

	customSection, ok := updated["custom"].(map[string]any)
	if !ok || customSection["keep"] != true {
		t.Fatalf("expected custom section preserved, got %#v", updated["custom"])
	}
	skillsSection := updated["skills"].(map[string]any)
	loadSection := skillsSection["load"].(map[string]any)
	extraDirs := anyStrings(loadSection["extraDirs"])
	if len(extraDirs) != 1 || extraDirs[0] != "/tmp/custom-skills" {
		t.Fatalf("unexpected extraDirs: %v", extraDirs)
	}
}

func TestUpdateOpenClawSkillsWatcherConfigPreservesCustomFields(t *testing.T) {
	rootDir := t.TempDir()
	stateDir := filepath.Join(rootDir, ".openclaw")
	managerDir := filepath.Join(rootDir, ".manager")
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		t.Fatalf("mkdir state dir: %v", err)
	}
	if err := os.MkdirAll(managerDir, 0o755); err != nil {
		t.Fatalf("mkdir manager dir: %v", err)
	}

	configPath := filepath.Join(stateDir, "openclaw.json")
	if err := os.WriteFile(configPath, []byte(`{
  "custom": {"keep": true},
  "skills": {
    "load": {
      "watch": false,
      "watchDebounceMs": 1200
    }
  }
}`), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	app := &App{
		homeDir:              rootDir,
		openclawHomeDir:      rootDir,
		managerDir:           managerDir,
		backupDir:            filepath.Join(managerDir, "backups"),
		defaultOpenClawState: stateDir,
		stateDirCache:        map[string]string{},
	}

	watch := true
	debounce := 2500
	result, err := app.updateOpenClawSkillsWatcherConfig(&watch, &debounce)
	if err != nil {
		t.Fatalf("updateOpenClawSkillsWatcherConfig: %v", err)
	}
	if !result.OK || result.Action != "update-watch" {
		t.Fatalf("unexpected result: %+v", result)
	}

	var updated map[string]any
	data, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if err := json.Unmarshal(data, &updated); err != nil {
		t.Fatalf("unmarshal config: %v", err)
	}

	customSection, ok := updated["custom"].(map[string]any)
	if !ok || customSection["keep"] != true {
		t.Fatalf("expected custom section preserved, got %#v", updated["custom"])
	}
	loadSection := updated["skills"].(map[string]any)["load"].(map[string]any)
	if watched, ok := loadSection["watch"].(bool); !ok || !watched {
		t.Fatalf("expected watch=true, got %#v", loadSection["watch"])
	}
	if got := anyInt(loadSection["watchDebounceMs"]); got != 2500 {
		t.Fatalf("expected watchDebounceMs=2500, got %d", got)
	}
}

func TestUpdateOpenClawSkillsInstallConfigPreservesCustomFields(t *testing.T) {
	rootDir := t.TempDir()
	stateDir := filepath.Join(rootDir, ".openclaw")
	managerDir := filepath.Join(rootDir, ".manager")
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		t.Fatalf("mkdir state dir: %v", err)
	}
	if err := os.MkdirAll(managerDir, 0o755); err != nil {
		t.Fatalf("mkdir manager dir: %v", err)
	}

	configPath := filepath.Join(stateDir, "openclaw.json")
	if err := os.WriteFile(configPath, []byte(`{
  "custom": {"keep": true},
  "skills": {
    "load": {
      "watch": true
    },
    "install": {
      "preferBrew": false,
      "nodeManager": "npm"
    }
  }
}`), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	app := &App{
		homeDir:              rootDir,
		openclawHomeDir:      rootDir,
		managerDir:           managerDir,
		backupDir:            filepath.Join(managerDir, "backups"),
		defaultOpenClawState: stateDir,
		stateDirCache:        map[string]string{},
	}

	preferBrew := true
	nodeManager := "pnpm"
	result, err := app.updateOpenClawSkillsInstallConfig(&preferBrew, false, &nodeManager, false)
	if err != nil {
		t.Fatalf("updateOpenClawSkillsInstallConfig: %v", err)
	}
	if !result.OK || result.Action != "update-install" {
		t.Fatalf("unexpected result: %+v", result)
	}

	var updated map[string]any
	data, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if err := json.Unmarshal(data, &updated); err != nil {
		t.Fatalf("unmarshal config: %v", err)
	}

	customSection, ok := updated["custom"].(map[string]any)
	if !ok || customSection["keep"] != true {
		t.Fatalf("expected custom section preserved, got %#v", updated["custom"])
	}
	skillsSection := updated["skills"].(map[string]any)
	loadSection := skillsSection["load"].(map[string]any)
	if watched, ok := loadSection["watch"].(bool); !ok || !watched {
		t.Fatalf("expected watch=true preserved, got %#v", loadSection["watch"])
	}
	installSection := skillsSection["install"].(map[string]any)
	if prefer, ok := installSection["preferBrew"].(bool); !ok || !prefer {
		t.Fatalf("expected preferBrew=true, got %#v", installSection["preferBrew"])
	}
	if got := anyString(installSection["nodeManager"]); got != "pnpm" {
		t.Fatalf("expected nodeManager=pnpm, got %q", got)
	}
}
