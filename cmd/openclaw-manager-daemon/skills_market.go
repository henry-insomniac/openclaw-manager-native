package main

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"
)

const (
	skillsMarketCatalogTTL         = 30 * time.Minute
	skillsMarketDetailTTL          = 10 * time.Minute
	skillsMarketDownloadTimeout    = 95 * time.Second
	skillsMarketMaxRetryAfter      = 45 * time.Second
	skillsMarketBrowsePageSize     = 100
	skillsMarketBrowseMaxPages     = 3
	skillsMarketSearchLimit        = 40
	skillsMarketMaxCategoryCount   = 8
	defaultAwesomeSkillsRepoURL    = "https://github.com/VoltAgent/awesome-openclaw-skills"
	defaultAwesomeSkillsRawBaseURL = "https://raw.githubusercontent.com/VoltAgent/awesome-openclaw-skills/main"
	defaultClawHubAPIBaseURL       = "https://clawhub.ai/api/v1"
	defaultClawHubWebBaseURL       = "https://clawhub.ai"
)

var (
	awesomeCategoryLinkPattern = regexp.MustCompile(`\((categories/[^)#?]+\.md)\)`)
	awesomeSkillLinePattern    = regexp.MustCompile(`^- \[([^\]]+)\]\((https://github\.com/openclaw/skills/tree/main/skills/[^)]+)\)\s*-\s*(.+?)\s*$`)
	openClawSkillRepoPattern   = regexp.MustCompile(`https://github\.com/openclaw/skills/tree/main/skills/([^/]+)/([^/)#?]+)`)
	skillSlugPattern           = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`)
)

type cachedOpenClawSkillsMarketSummary struct {
	Summary   OpenClawSkillsMarketSummary
	FetchedAt time.Time
	Query     string
	Sort      string
}

type cachedOpenClawSkillMarketDetail struct {
	Detail    OpenClawSkillMarketDetail
	FetchedAt time.Time
}

type OpenClawSkillsMarketSummary struct {
	CollectedAt      string                        `json:"collectedAt"`
	SourceRepo       string                        `json:"sourceRepo"`
	ManagedDirectory string                        `json:"managedDirectory"`
	Query            string                        `json:"query,omitempty"`
	Sort             string                        `json:"sort,omitempty"`
	IsSearchResult   bool                          `json:"isSearchResult"`
	TotalItems       int                           `json:"totalItems"`
	Categories       []OpenClawSkillMarketCategory `json:"categories"`
	Items            []OpenClawSkillMarketItem     `json:"items"`
}

type OpenClawSkillMarketCategory struct {
	ID    string `json:"id"`
	Title string `json:"title"`
	Count int    `json:"count"`
}

type OpenClawSkillMarketItem struct {
	Slug            string   `json:"slug"`
	Name            string   `json:"name"`
	Summary         string   `json:"summary"`
	SummaryZh       string   `json:"summaryZh,omitempty"`
	Owner           string   `json:"owner,omitempty"`
	GitHubURL       string   `json:"githubUrl,omitempty"`
	RegistryURL     string   `json:"registryUrl"`
	CategoryIDs     []string `json:"categoryIds"`
	Tags            []string `json:"tags,omitempty"`
	Downloads       int      `json:"downloads,omitempty"`
	InstallsCurrent int      `json:"installsCurrent,omitempty"`
	Stars           int      `json:"stars,omitempty"`
	LatestVersion   string   `json:"latestVersion,omitempty"`
	UpdatedAt       *string  `json:"updatedAt,omitempty"`
}

type OpenClawSkillsInventory struct {
	CollectedAt        string                       `json:"collectedAt"`
	ManagedDirectory   string                       `json:"managedDirectory"`
	LockPath           string                       `json:"lockPath"`
	RuntimeError       *string                      `json:"runtimeError,omitempty"`
	TotalItems         int                          `json:"totalItems"`
	ManagerInstalled   int                          `json:"managerInstalled"`
	PersonalInstalled  int                          `json:"personalInstalled"`
	BundledInstalled   int                          `json:"bundledInstalled"`
	WorkspaceInstalled int                          `json:"workspaceInstalled"`
	GlobalInstalled    int                          `json:"globalInstalled"`
	ExternalInstalled  int                          `json:"externalInstalled"`
	Items              []OpenClawSkillInventoryItem `json:"items"`
}

type OpenClawSkillInventoryItem struct {
	Slug             string  `json:"slug"`
	Name             string  `json:"name"`
	Summary          string  `json:"summary"`
	Source           string  `json:"source"`
	RuntimeSource    *string `json:"runtimeSource,omitempty"`
	RuntimeStatus    *string `json:"runtimeStatus,omitempty"`
	Enabled          *bool   `json:"enabled,omitempty"`
	Eligible         *bool   `json:"eligible,omitempty"`
	Bundled          bool    `json:"bundled"`
	ManagerOwned     bool    `json:"managerOwned"`
	Uninstallable    bool    `json:"uninstallable"`
	VisibleInRuntime bool    `json:"visibleInRuntime"`
	Homepage         *string `json:"homepage,omitempty"`
	InstalledVersion *string `json:"installedVersion,omitempty"`
	InstalledAt      *string `json:"installedAt,omitempty"`
	OriginRegistry   *string `json:"originRegistry,omitempty"`
}

type OpenClawSkillMarketDetail struct {
	CollectedAt   string                        `json:"collectedAt"`
	Item          OpenClawSkillMarketItem       `json:"item"`
	CreatedAt     *string                       `json:"createdAt,omitempty"`
	UpdatedAt     *string                       `json:"updatedAt,omitempty"`
	Stats         OpenClawSkillRegistryStats    `json:"stats"`
	LatestVersion *OpenClawSkillLatestVersion   `json:"latestVersion,omitempty"`
	Metadata      OpenClawSkillRegistryMetadata `json:"metadata"`
	Owner         *OpenClawSkillRegistryOwner   `json:"owner,omitempty"`
	Moderation    *OpenClawSkillModeration      `json:"moderation,omitempty"`
}

type OpenClawSkillRegistryStats struct {
	Comments        int `json:"comments"`
	Downloads       int `json:"downloads"`
	InstallsAllTime int `json:"installsAllTime"`
	InstallsCurrent int `json:"installsCurrent"`
	Stars           int `json:"stars"`
	Versions        int `json:"versions"`
}

type OpenClawSkillLatestVersion struct {
	Version   *string `json:"version,omitempty"`
	CreatedAt *string `json:"createdAt,omitempty"`
	Changelog *string `json:"changelog,omitempty"`
	License   *string `json:"license,omitempty"`
}

type OpenClawSkillRegistryMetadata struct {
	OS      []string `json:"os"`
	Systems []string `json:"systems"`
}

type OpenClawSkillRegistryOwner struct {
	Handle      *string `json:"handle,omitempty"`
	DisplayName *string `json:"displayName,omitempty"`
	Image       *string `json:"image,omitempty"`
}

type OpenClawSkillModeration struct {
	Verdict          string   `json:"verdict"`
	IsSuspicious     bool     `json:"isSuspicious"`
	IsMalwareBlocked bool     `json:"isMalwareBlocked"`
	ReasonCodes      []string `json:"reasonCodes"`
	Summary          *string  `json:"summary,omitempty"`
	UpdatedAt        *string  `json:"updatedAt,omitempty"`
}

type OpenClawSkillMutationResult struct {
	OK               bool    `json:"ok"`
	Action           string  `json:"action"`
	Slug             string  `json:"slug"`
	Message          string  `json:"message"`
	InstallDirectory *string `json:"installDirectory,omitempty"`
	InstalledVersion *string `json:"installedVersion,omitempty"`
}

type OpenClawSkillsConfigMutationResult struct {
	OK         bool   `json:"ok"`
	Action     string `json:"action"`
	Path       string `json:"path"`
	Message    string `json:"message"`
	ConfigPath string `json:"configPath"`
}

type awesomeCatalogItem struct {
	Slug         string
	Name         string
	Summary      string
	Owner        string
	GitHubURL    string
	CategoryID   string
	CategoryName string
}

type clawHubSkillDetailPayload struct {
	Skill struct {
		Slug        string `json:"slug"`
		DisplayName string `json:"displayName"`
		Summary     string `json:"summary"`
		Stats       struct {
			Comments        int `json:"comments"`
			Downloads       int `json:"downloads"`
			InstallsAllTime int `json:"installsAllTime"`
			InstallsCurrent int `json:"installsCurrent"`
			Stars           int `json:"stars"`
			Versions        int `json:"versions"`
		} `json:"stats"`
		CreatedAt int64 `json:"createdAt"`
		UpdatedAt int64 `json:"updatedAt"`
	} `json:"skill"`
	LatestVersion struct {
		Version   string  `json:"version"`
		CreatedAt int64   `json:"createdAt"`
		Changelog string  `json:"changelog"`
		License   *string `json:"license"`
	} `json:"latestVersion"`
	Metadata struct {
		OS      any `json:"os"`
		Systems any `json:"systems"`
	} `json:"metadata"`
	Owner struct {
		Handle      string `json:"handle"`
		DisplayName string `json:"displayName"`
		Image       string `json:"image"`
	} `json:"owner"`
	Moderation struct {
		Verdict          string   `json:"verdict"`
		IsSuspicious     bool     `json:"isSuspicious"`
		IsMalwareBlocked bool     `json:"isMalwareBlocked"`
		ReasonCodes      []string `json:"reasonCodes"`
		Summary          string   `json:"summary"`
		UpdatedAt        int64    `json:"updatedAt"`
	} `json:"moderation"`
}

type clawHubSkillsListPayload struct {
	Items      []clawHubSkillListItem `json:"items"`
	NextCursor string                 `json:"nextCursor"`
}

type clawHubSkillListItem struct {
	Slug          string            `json:"slug"`
	DisplayName   string            `json:"displayName"`
	Summary       string            `json:"summary"`
	Tags          map[string]string `json:"tags"`
	CreatedAt     int64             `json:"createdAt"`
	UpdatedAt     int64             `json:"updatedAt"`
	LatestVersion struct {
		Version string `json:"version"`
	} `json:"latestVersion"`
	Stats struct {
		Downloads       int `json:"downloads"`
		InstallsAllTime int `json:"installsAllTime"`
		InstallsCurrent int `json:"installsCurrent"`
		Stars           int `json:"stars"`
	} `json:"stats"`
}

type clawHubSearchPayload struct {
	Results []clawHubSearchResult `json:"results"`
}

type clawHubSearchResult struct {
	Slug        string  `json:"slug"`
	DisplayName string  `json:"displayName"`
	Summary     string  `json:"summary"`
	Version     *string `json:"version"`
	UpdatedAt   int64   `json:"updatedAt"`
}

type clawHubLockFile struct {
	Version int                         `json:"version"`
	Skills  map[string]clawHubLockSkill `json:"skills,omitempty"`
}

type clawHubLockSkill struct {
	Version     *string `json:"version,omitempty"`
	InstalledAt int64   `json:"installedAt"`
}

type clawHubOriginFile struct {
	Version          int     `json:"version"`
	Registry         string  `json:"registry"`
	Slug             string  `json:"slug"`
	InstalledVersion *string `json:"installedVersion,omitempty"`
	InstalledAt      int64   `json:"installedAt"`
}

type skillsMarketCategoryRule struct {
	ID       string
	Title    string
	Keywords []string
}

var skillsMarketCategoryRules = []skillsMarketCategoryRule{
	{ID: "automation", Title: "自动化", Keywords: []string{"automation", "automate", "workflow", "agent", "orchestrat", "任务流"}},
	{ID: "browser-web", Title: "浏览器 / Web", Keywords: []string{"browser", "playwright", "web", "website", "page", "scrape", "crawl", "url", "网页", "浏览器"}},
	{ID: "git-dev", Title: "Git / 开发", Keywords: []string{"git", "github", "repo", "pull request", "issue", "code", "devops", "ci", "开发", "代码"}},
	{ID: "docs-knowledge", Title: "文档 / 知识", Keywords: []string{"docs", "documentation", "markdown", "wiki", "knowledge", "note", "文档", "知识", "笔记"}},
	{ID: "productivity", Title: "办公 / 协作", Keywords: []string{"calendar", "notion", "slack", "discord", "email", "mail", "task", "todo", "reminder", "协作", "待办", "提醒", "日历"}},
	{ID: "data-api", Title: "数据 / API", Keywords: []string{"api", "database", "sql", "postgres", "mysql", "sqlite", "json", "graphql", "数据", "数据库"}},
	{ID: "media-files", Title: "媒体 / 文件", Keywords: []string{"pdf", "image", "video", "audio", "file", "document", "媒体", "文件", "图像", "音频"}},
	{ID: "system-tools", Title: "系统 / 命令行", Keywords: []string{"terminal", "shell", "command", "filesystem", "system", "brew", "cli", "node", "系统", "终端"}},
	{ID: "search-research", Title: "搜索 / 检索", Keywords: []string{"search", "find", "lookup", "discover", "research", "检索", "搜索", "发现"}},
	{ID: "analysis-writing", Title: "分析 / 写作", Keywords: []string{"summary", "summarize", "analysis", "analyze", "report", "translate", "translation", "write", "摘要", "分析", "翻译", "写作"}},
}

func (app *App) handleOpenClawSkillsMarket(w http.ResponseWriter, r *http.Request) {
	query := strings.TrimSpace(r.URL.Query().Get("query"))
	if query == "" {
		query = strings.TrimSpace(r.URL.Query().Get("q"))
	}
	summary, err := app.buildOpenClawSkillsMarketSummary(
		r.URL.Query().Get("fresh") == "1",
		query,
		r.URL.Query().Get("sort"),
	)
	if err != nil {
		writeAPIError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, summary)
}

func (app *App) handleOpenClawSkillMarketDetail(w http.ResponseWriter, r *http.Request) {
	detail, err := app.fetchOpenClawSkillMarketDetail(r.PathValue("slug"), r.URL.Query().Get("fresh") == "1")
	if err != nil {
		writeAPIMessage(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, detail)
}

func (app *App) handleOpenClawSkillsInventory(w http.ResponseWriter, r *http.Request) {
	inventory, err := app.buildOpenClawSkillsInventory(r.URL.Query().Get("fresh") == "1")
	if err != nil {
		writeAPIError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, inventory)
}

func (app *App) handlePatchOpenClawSkillsConfig(w http.ResponseWriter, r *http.Request) {
	var body struct {
		AddExtraDir             *string `json:"addExtraDir,omitempty"`
		RemoveExtraDir          *string `json:"removeExtraDir,omitempty"`
		Watch                   *bool   `json:"watch,omitempty"`
		WatchDebounceMs         *int    `json:"watchDebounceMs,omitempty"`
		InstallPreferBrew       *bool   `json:"installPreferBrew,omitempty"`
		ClearInstallPreferBrew  bool    `json:"clearInstallPreferBrew,omitempty"`
		InstallNodeManager      *string `json:"installNodeManager,omitempty"`
		ClearInstallNodeManager bool    `json:"clearInstallNodeManager,omitempty"`
	}
	if err := decodeJSONBody(r, &body); err != nil {
		writeAPIMessage(w, http.StatusBadRequest, "skills config patch payload is invalid")
		return
	}

	var (
		result OpenClawSkillsConfigMutationResult
		err    error
	)
	hasPathPatch := body.AddExtraDir != nil || body.RemoveExtraDir != nil
	hasRuntimePatch := body.Watch != nil || body.WatchDebounceMs != nil
	hasInstallPatch := body.InstallPreferBrew != nil || body.ClearInstallPreferBrew || body.InstallNodeManager != nil || body.ClearInstallNodeManager
	switch {
	case body.AddExtraDir != nil && body.RemoveExtraDir != nil:
		err = errors.New("一次只能提交一个目录变更")
	case hasPathPatch && (hasRuntimePatch || hasInstallPatch):
		err = errors.New("当前一次只能保存一组 skills 配置变更")
	case hasRuntimePatch && hasInstallPatch:
		err = errors.New("当前一次只能保存一组 skills 配置变更")
	case body.AddExtraDir != nil:
		result, err = app.addOpenClawSkillsExtraDir(*body.AddExtraDir)
	case body.RemoveExtraDir != nil:
		result, err = app.removeOpenClawSkillsExtraDir(*body.RemoveExtraDir)
	case hasRuntimePatch:
		result, err = app.updateOpenClawSkillsWatcherConfig(body.Watch, body.WatchDebounceMs)
	case hasInstallPatch:
		result, err = app.updateOpenClawSkillsInstallConfig(
			body.InstallPreferBrew,
			body.ClearInstallPreferBrew,
			body.InstallNodeManager,
			body.ClearInstallNodeManager,
		)
	default:
		err = errors.New("未提供可执行的 skills 配置变更")
	}
	if err != nil {
		writeAPIMessage(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (app *App) handleEnableOpenClawSkill(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Bundled bool `json:"bundled"`
	}
	if err := decodeJSONBody(r, &body); err != nil {
		writeAPIMessage(w, http.StatusBadRequest, "skill enable payload is invalid")
		return
	}
	result, err := app.setOpenClawSkillEnabled(r.PathValue("skillKey"), true, body.Bundled)
	if err != nil {
		writeAPIMessage(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (app *App) handleDisableOpenClawSkill(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Bundled bool `json:"bundled"`
	}
	if err := decodeJSONBody(r, &body); err != nil {
		writeAPIMessage(w, http.StatusBadRequest, "skill disable payload is invalid")
		return
	}
	result, err := app.setOpenClawSkillEnabled(r.PathValue("skillKey"), false, body.Bundled)
	if err != nil {
		writeAPIMessage(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (app *App) handleInstallOpenClawSkill(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Slug string `json:"slug"`
	}
	if err := decodeJSONBody(r, &body); err != nil {
		writeAPIMessage(w, http.StatusBadRequest, "skill install payload is invalid")
		return
	}
	result, err := app.installOpenClawSkill(body.Slug)
	if err != nil {
		writeAPIMessage(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (app *App) handleUninstallOpenClawSkill(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Slug string `json:"slug"`
	}
	if err := decodeJSONBody(r, &body); err != nil {
		writeAPIMessage(w, http.StatusBadRequest, "skill uninstall payload is invalid")
		return
	}
	result, err := app.uninstallOpenClawSkill(body.Slug)
	if err != nil {
		writeAPIMessage(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (app *App) setOpenClawSkillEnabled(skillKey string, enabled bool, bundled bool) (OpenClawSkillMutationResult, error) {
	skillKey = strings.TrimSpace(skillKey)
	if !skillSlugPattern.MatchString(skillKey) {
		return OpenClawSkillMutationResult{}, errors.New("skill key 不合法")
	}

	configPath, root, err := app.loadDefaultOpenClawConfigRoot("技能状态更新")
	if err != nil {
		return OpenClawSkillMutationResult{}, err
	}

	skillsMap := ensureMap(root, "skills")
	entriesMap := ensureMap(skillsMap, "entries")
	entryMap := ensureMap(entriesMap, skillKey)
	entryMap["enabled"] = enabled

	message := "已更新技能状态。"
	if enabled {
		if bundled {
			allowBundled := compactStrings(anyStrings(skillsMap["allowBundled"]))
			if !containsString(allowBundled, skillKey) {
				allowBundled = append(allowBundled, skillKey)
				sort.Strings(allowBundled)
			}
			skillsMap["allowBundled"] = allowBundled
			message = "已允许并启用，刷新后会按新配置加载。"
		} else {
			message = "已启用，刷新后会按新配置加载。"
		}
	} else {
		message = "已停用，刷新后会按新配置加载。"
	}

	root["skills"] = skillsMap
	if err := app.saveDefaultOpenClawConfigRoot(configPath, root); err != nil {
		return OpenClawSkillMutationResult{}, err
	}
	app.invalidateSkillsCaches()

	action := "enable"
	if !enabled {
		action = "disable"
	}
	return OpenClawSkillMutationResult{
		OK:      true,
		Action:  action,
		Slug:    skillKey,
		Message: message,
	}, nil
}

func (app *App) buildOpenClawSkillsMarketSummary(fresh bool, rawQuery, rawSort string) (OpenClawSkillsMarketSummary, error) {
	query := strings.TrimSpace(rawQuery)
	sortKey := normalizeSkillsMarketSort(rawSort)
	if query != "" {
		return app.buildSearchOpenClawSkillsMarketSummary(fresh, query, sortKey)
	}
	return app.buildDefaultOpenClawSkillsMarketSummary(fresh, sortKey)
}

func (app *App) buildDefaultOpenClawSkillsMarketSummary(fresh bool, sortKey string) (OpenClawSkillsMarketSummary, error) {
	if !fresh {
		app.mu.Lock()
		if app.skillsMarketCache != nil &&
			time.Since(app.skillsMarketCache.FetchedAt) <= skillsMarketCatalogTTL &&
			app.skillsMarketCache.Query == "" &&
			app.skillsMarketCache.Sort == sortKey {
			cached := app.skillsMarketCache.Summary
			app.mu.Unlock()
			return cached, nil
		}
		app.mu.Unlock()
	}

	items, err := fetchClawHubBrowseItems(sortKey)
	if err != nil {
		categories, fallbackItems, fallbackErr := app.fetchAwesomeCatalog()
		if fallbackErr != nil {
			return OpenClawSkillsMarketSummary{}, err
		}
		summary := OpenClawSkillsMarketSummary{
			CollectedAt:      nowISO(),
			SourceRepo:       defaultAwesomeSkillsRepoURL,
			ManagedDirectory: app.managerSkillsMarketDir(),
			Sort:             sortKey,
			TotalItems:       len(fallbackItems),
			Categories:       categories,
			Items:            fallbackItems,
		}
		app.mu.Lock()
		app.skillsMarketCache = &cachedOpenClawSkillsMarketSummary{
			Summary:   summary,
			FetchedAt: time.Now(),
			Query:     "",
			Sort:      sortKey,
		}
		app.mu.Unlock()
		return summary, nil
	}

	summary := summarizeOpenClawSkillsMarketSummary(
		app.managerSkillsMarketDir(),
		clawHubSkillsListURL(sortKey, "", skillsMarketBrowsePageSize),
		"",
		sortKey,
		false,
		items,
	)

	app.mu.Lock()
	app.skillsMarketCache = &cachedOpenClawSkillsMarketSummary{
		Summary:   summary,
		FetchedAt: time.Now(),
		Query:     "",
		Sort:      sortKey,
	}
	app.mu.Unlock()

	return summary, nil
}

func (app *App) buildSearchOpenClawSkillsMarketSummary(fresh bool, query, sortKey string) (OpenClawSkillsMarketSummary, error) {
	remoteItems, remoteErr := searchClawHubMarketItems(query)
	merged := mergeMarketItems(nil, remoteItems)

	browseItems, browseErr := fetchClawHubBrowseItems(sortKey)
	if browseErr == nil {
		merged = mergeMarketItems(merged, filterMarketItemsLocally(browseItems, query))
	}
	if len(merged) == 0 && remoteErr != nil && browseErr != nil {
		return OpenClawSkillsMarketSummary{}, fmt.Errorf("搜索 ClawHub 失败: %w", remoteErr)
	}
	if len(merged) == 0 && remoteErr != nil {
		return OpenClawSkillsMarketSummary{}, fmt.Errorf("搜索 ClawHub 失败，且本地热门列表未匹配到结果: %w", remoteErr)
	}

	sourceRepo := clawHubSearchURL(query, skillsMarketSearchLimit)
	if remoteErr != nil && browseErr == nil {
		sourceRepo = clawHubSkillsListURL(sortKey, "", skillsMarketBrowsePageSize)
	}
	return summarizeOpenClawSkillsMarketSummary(
		app.managerSkillsMarketDir(),
		sourceRepo,
		query,
		"relevance",
		true,
		merged,
	), nil
}

func normalizeSkillsMarketSort(raw string) string {
	normalized := strings.ToLower(strings.TrimSpace(raw))
	switch normalized {
	case "", "downloads":
		return "downloads"
	case "updated", "recent", "latest":
		return "updated"
	case "stars", "star":
		return "stars"
	case "installscurrent", "installs_current", "installs-current", "current-installs":
		return "installsCurrent"
	case "relevance":
		return "relevance"
	default:
		return "downloads"
	}
}

func clawHubSkillsListURL(sortKey, cursor string, limit int) string {
	if limit <= 0 {
		limit = skillsMarketBrowsePageSize
	}
	query := url.Values{}
	query.Set("sort", normalizeSkillsMarketSort(sortKey))
	query.Set("limit", strconv.Itoa(limit))
	if strings.TrimSpace(cursor) != "" {
		query.Set("cursor", strings.TrimSpace(cursor))
	}
	return clawHubAPIBaseURL() + "/skills?" + query.Encode()
}

func clawHubSearchURL(query string, limit int) string {
	if limit <= 0 {
		limit = skillsMarketSearchLimit
	}
	values := url.Values{}
	values.Set("q", strings.TrimSpace(query))
	values.Set("limit", strconv.Itoa(limit))
	return clawHubAPIBaseURL() + "/search?" + values.Encode()
}

func fetchClawHubBrowseItems(sortKey string) ([]OpenClawSkillMarketItem, error) {
	sortKey = normalizeSkillsMarketSort(sortKey)
	cursor := ""
	items := []OpenClawSkillMarketItem{}

	for page := 0; page < skillsMarketBrowseMaxPages; page++ {
		var payload clawHubSkillsListPayload
		if err := fetchJSONWithTimeout(clawHubSkillsListURL(sortKey, cursor, skillsMarketBrowsePageSize), httpTimeout, &payload); err != nil {
			if len(items) > 0 {
				break
			}
			return nil, fmt.Errorf("读取 ClawHub 市场列表失败: %w", err)
		}

		batch := make([]OpenClawSkillMarketItem, 0, len(payload.Items))
		for _, raw := range payload.Items {
			if strings.TrimSpace(raw.Slug) == "" {
				continue
			}
			name := firstNonEmpty(raw.DisplayName, raw.Slug)
			categoryIDs := inferSkillsMarketCategoryIDs(name, raw.Summary)
			batch = append(batch, OpenClawSkillMarketItem{
				Slug:            raw.Slug,
				Name:            name,
				Summary:         strings.TrimSpace(raw.Summary),
				SummaryZh:       localizeSkillSummary(name, raw.Summary, categoryIDs),
				RegistryURL:     registryURLForSlug(raw.Slug),
				CategoryIDs:     categoryIDs,
				Tags:            mergeUniqueStrings(localizedSkillTags(categoryIDs), marketReadableTags(raw.Tags)),
				Downloads:       raw.Stats.Downloads,
				InstallsCurrent: raw.Stats.InstallsCurrent,
				Stars:           raw.Stats.Stars,
				LatestVersion:   strings.TrimSpace(raw.LatestVersion.Version),
				UpdatedAt:       nullableTimeFromMillis(raw.UpdatedAt),
			})
		}

		items = mergeMarketItems(items, batch)
		cursor = strings.TrimSpace(payload.NextCursor)
		if cursor == "" || len(payload.Items) == 0 {
			break
		}
	}

	if len(items) == 0 {
		return nil, errors.New("ClawHub 市场列表为空")
	}
	return items, nil
}

func searchClawHubMarketItems(query string) ([]OpenClawSkillMarketItem, error) {
	query = strings.TrimSpace(query)
	if query == "" {
		return nil, nil
	}

	var payload clawHubSearchPayload
	if err := fetchJSONWithTimeout(clawHubSearchURL(query, skillsMarketSearchLimit), httpTimeout, &payload); err != nil {
		return nil, fmt.Errorf("读取 ClawHub 搜索结果失败: %w", err)
	}

	items := make([]OpenClawSkillMarketItem, 0, len(payload.Results))
	for _, raw := range payload.Results {
		if strings.TrimSpace(raw.Slug) == "" {
			continue
		}
		name := firstNonEmpty(raw.DisplayName, raw.Slug)
		categoryIDs := inferSkillsMarketCategoryIDs(name, raw.Summary)
		tags := localizedSkillTags(categoryIDs)
		items = append(items, OpenClawSkillMarketItem{
			Slug:          raw.Slug,
			Name:          name,
			Summary:       strings.TrimSpace(raw.Summary),
			SummaryZh:     localizeSkillSummary(name, raw.Summary, categoryIDs),
			RegistryURL:   registryURLForSlug(raw.Slug),
			CategoryIDs:   categoryIDs,
			Tags:          tags,
			LatestVersion: strings.TrimSpace(derefString(raw.Version)),
			UpdatedAt:     nullableTimeFromMillis(raw.UpdatedAt),
		})
	}

	return items, nil
}

func summarizeOpenClawSkillsMarketSummary(
	managedDirectory, sourceRepo, query, sortKey string,
	isSearchResult bool,
	items []OpenClawSkillMarketItem,
) OpenClawSkillsMarketSummary {
	normalizedItems := make([]OpenClawSkillMarketItem, 0, len(items))
	categoryCounts := map[string]int{}

	for _, item := range items {
		item.Slug = strings.TrimSpace(item.Slug)
		if item.Slug == "" {
			continue
		}
		item.Name = firstNonEmpty(strings.TrimSpace(item.Name), item.Slug)
		item.Summary = strings.TrimSpace(item.Summary)
		if len(item.CategoryIDs) == 0 {
			item.CategoryIDs = inferSkillsMarketCategoryIDs(item.Name, item.Summary)
		}
		if strings.TrimSpace(item.SummaryZh) == "" {
			item.SummaryZh = localizeSkillSummary(item.Name, item.Summary, item.CategoryIDs)
		}
		item.CategoryIDs = mergeUniqueStrings(nil, item.CategoryIDs)
		if len(item.Tags) == 0 {
			item.Tags = localizedSkillTags(item.CategoryIDs)
		} else {
			item.Tags = mergeUniqueStrings(localizedSkillTags(item.CategoryIDs), item.Tags)
		}
		if strings.TrimSpace(item.RegistryURL) == "" {
			item.RegistryURL = registryURLForSlug(item.Slug)
		}
		for _, categoryID := range item.CategoryIDs {
			categoryCounts[categoryID]++
		}
		normalizedItems = append(normalizedItems, item)
	}

	categories := make([]OpenClawSkillMarketCategory, 0, len(categoryCounts))
	for categoryID, count := range categoryCounts {
		categories = append(categories, OpenClawSkillMarketCategory{
			ID:    categoryID,
			Title: skillsMarketCategoryTitle(categoryID),
			Count: count,
		})
	}
	sort.Slice(categories, func(i, j int) bool {
		if categories[i].Count != categories[j].Count {
			return categories[i].Count > categories[j].Count
		}
		return strings.ToLower(categories[i].Title) < strings.ToLower(categories[j].Title)
	})
	if len(categories) > skillsMarketMaxCategoryCount {
		categories = append([]OpenClawSkillMarketCategory(nil), categories[:skillsMarketMaxCategoryCount]...)
	}

	return OpenClawSkillsMarketSummary{
		CollectedAt:      nowISO(),
		SourceRepo:       firstNonEmpty(strings.TrimSpace(sourceRepo), clawHubSkillsListURL(sortKey, "", skillsMarketBrowsePageSize)),
		ManagedDirectory: managedDirectory,
		Query:            strings.TrimSpace(query),
		Sort:             normalizeSkillsMarketSort(sortKey),
		IsSearchResult:   isSearchResult,
		TotalItems:       len(normalizedItems),
		Categories:       categories,
		Items:            normalizedItems,
	}
}

func mergeMarketItems(base []OpenClawSkillMarketItem, incoming []OpenClawSkillMarketItem) []OpenClawSkillMarketItem {
	order := make([]string, 0, len(base)+len(incoming))
	merged := map[string]OpenClawSkillMarketItem{}

	apply := func(item OpenClawSkillMarketItem) {
		slug := strings.TrimSpace(item.Slug)
		if slug == "" {
			return
		}
		item.Slug = slug
		existing, ok := merged[slug]
		if !ok {
			merged[slug] = item
			order = append(order, slug)
			return
		}

		if betterMarketString(item.Name, existing.Name) {
			existing.Name = item.Name
		}
		if betterMarketString(item.Summary, existing.Summary) {
			existing.Summary = item.Summary
		}
		if betterMarketString(item.SummaryZh, existing.SummaryZh) {
			existing.SummaryZh = item.SummaryZh
		}
		if betterMarketString(item.Owner, existing.Owner) {
			existing.Owner = item.Owner
		}
		if betterMarketString(item.GitHubURL, existing.GitHubURL) {
			existing.GitHubURL = item.GitHubURL
		}
		if betterMarketString(item.RegistryURL, existing.RegistryURL) {
			existing.RegistryURL = item.RegistryURL
		}
		if betterMarketString(item.LatestVersion, existing.LatestVersion) {
			existing.LatestVersion = item.LatestVersion
		}
		existing.CategoryIDs = mergeUniqueStrings(existing.CategoryIDs, item.CategoryIDs)
		existing.Tags = mergeUniqueStrings(existing.Tags, item.Tags)
		if item.Downloads > existing.Downloads {
			existing.Downloads = item.Downloads
		}
		if item.InstallsCurrent > existing.InstallsCurrent {
			existing.InstallsCurrent = item.InstallsCurrent
		}
		if item.Stars > existing.Stars {
			existing.Stars = item.Stars
		}
		if newerMarketTimestamp(item.UpdatedAt, existing.UpdatedAt) {
			existing.UpdatedAt = item.UpdatedAt
		}
		merged[slug] = existing
	}

	for _, item := range base {
		apply(item)
	}
	for _, item := range incoming {
		apply(item)
	}

	out := make([]OpenClawSkillMarketItem, 0, len(order))
	for _, slug := range order {
		out = append(out, merged[slug])
	}
	return out
}

func filterMarketItemsLocally(items []OpenClawSkillMarketItem, query string) []OpenClawSkillMarketItem {
	query = strings.TrimSpace(query)
	if query == "" {
		return append([]OpenClawSkillMarketItem(nil), items...)
	}

	type scoredItem struct {
		Item  OpenClawSkillMarketItem
		Score int
	}

	terms := expandSkillsMarketSearchTerms(query)
	scored := make([]scoredItem, 0, len(items))
	for _, item := range items {
		score := scoreSkillsMarketItem(item, query, terms)
		if score <= 0 {
			continue
		}
		scored = append(scored, scoredItem{Item: item, Score: score})
	}

	sort.Slice(scored, func(i, j int) bool {
		if scored[i].Score != scored[j].Score {
			return scored[i].Score > scored[j].Score
		}
		if scored[i].Item.Downloads != scored[j].Item.Downloads {
			return scored[i].Item.Downloads > scored[j].Item.Downloads
		}
		if scored[i].Item.Stars != scored[j].Item.Stars {
			return scored[i].Item.Stars > scored[j].Item.Stars
		}
		return strings.ToLower(scored[i].Item.Name) < strings.ToLower(scored[j].Item.Name)
	})

	out := make([]OpenClawSkillMarketItem, 0, len(scored))
	for _, entry := range scored {
		out = append(out, entry.Item)
	}
	return out
}

func scoreSkillsMarketItem(item OpenClawSkillMarketItem, query string, terms []string) int {
	score := 0
	score += marketFieldScore(item.Name, query, 160)
	score += marketFieldScore(item.Slug, query, 150)
	score += marketFieldScore(item.SummaryZh, query, 120)
	score += marketFieldScore(item.Summary, query, 100)
	score += marketFieldScore(item.Owner, query, 80)
	score += marketFieldScore(strings.Join(item.Tags, " "), query, 70)
	score += marketFieldScore(strings.Join(item.CategoryIDs, " "), query, 60)

	for _, term := range terms {
		if strings.EqualFold(strings.TrimSpace(term), strings.TrimSpace(query)) {
			continue
		}
		score += marketFieldScore(item.Name, term, 65)
		score += marketFieldScore(item.Slug, term, 60)
		score += marketFieldScore(item.SummaryZh, term, 55)
		score += marketFieldScore(item.Summary, term, 45)
		score += marketFieldScore(strings.Join(item.Tags, " "), term, 35)
	}

	return score
}

func marketFieldScore(value, query string, weight int) int {
	if !marketContains(value, query) {
		return 0
	}
	return weight
}

func marketContains(value, query string) bool {
	query = strings.TrimSpace(query)
	value = strings.TrimSpace(value)
	if query == "" || value == "" {
		return false
	}
	lowerValue := strings.ToLower(value)
	lowerQuery := strings.ToLower(query)
	if strings.Contains(lowerValue, lowerQuery) {
		return true
	}
	return strings.Contains(normalizeSearchableText(lowerValue), normalizeSearchableText(lowerQuery))
}

func normalizeSearchableText(value string) string {
	value = strings.TrimSpace(strings.ToLower(value))
	if value == "" {
		return ""
	}
	var builder strings.Builder
	lastSpace := true
	for _, r := range value {
		switch {
		case unicode.IsLetter(r), unicode.IsDigit(r), unicode.In(r, unicode.Han):
			builder.WriteRune(r)
			lastSpace = false
		default:
			if !lastSpace {
				builder.WriteByte(' ')
				lastSpace = true
			}
		}
	}
	return strings.TrimSpace(builder.String())
}

func expandSkillsMarketSearchTerms(query string) []string {
	query = strings.TrimSpace(strings.ToLower(query))
	if query == "" {
		return nil
	}
	terms := []string{query}
	for _, token := range strings.Fields(normalizeSearchableText(query)) {
		terms = append(terms, token)
	}
	aliases := map[string][]string{
		"天气":     {"weather", "forecast"},
		"浏览器":    {"browser", "playwright", "web"},
		"网页":     {"web", "browser", "site"},
		"搜索":     {"search", "find", "discover"},
		"检索":     {"search", "lookup", "discover"},
		"总结":     {"summary", "summarize", "report"},
		"摘要":     {"summary", "summarize"},
		"翻译":     {"translate", "translation", "localization"},
		"提醒":     {"reminder", "todo", "task"},
		"待办":     {"todo", "task", "reminder"},
		"日历":     {"calendar", "schedule"},
		"文档":     {"docs", "documentation", "markdown"},
		"数据库":    {"database", "sql", "postgres", "mysql", "sqlite"},
		"邮件":     {"email", "mail", "gmail"},
		"pdf":    {"pdf", "document"},
		"图片":     {"image", "photo", "vision"},
		"音频":     {"audio", "speech", "voice"},
		"视频":     {"video", "media"},
		"github": {"github", "git", "repo", "pull request", "issue"},
		"git":    {"git", "github", "repo", "pull request"},
		"notion": {"notion"},
	}
	for key, extras := range aliases {
		if strings.Contains(query, key) {
			terms = append(terms, extras...)
		}
	}
	for _, rule := range skillsMarketCategoryRules {
		if marketContains(rule.Title, query) {
			terms = append(terms, rule.Keywords...)
			continue
		}
		for _, keyword := range rule.Keywords {
			if marketContains(keyword, query) || marketContains(query, keyword) {
				terms = append(terms, rule.Keywords...)
				break
			}
		}
	}
	return mergeUniqueStrings(nil, terms)
}

func inferSkillsMarketCategoryIDs(name, summary string) []string {
	text := strings.ToLower(strings.TrimSpace(name + " " + summary))
	out := make([]string, 0, 3)
	for _, rule := range skillsMarketCategoryRules {
		for _, keyword := range rule.Keywords {
			if marketContains(text, keyword) {
				out = append(out, rule.ID)
				break
			}
		}
		if len(out) >= 3 {
			break
		}
	}
	return mergeUniqueStrings(nil, out)
}

func skillsMarketCategoryTitle(categoryID string) string {
	for _, rule := range skillsMarketCategoryRules {
		if rule.ID == categoryID {
			return rule.Title
		}
	}
	if categoryID == "" {
		return "未分类"
	}
	return categoryID
}

func localizedSkillTags(categoryIDs []string) []string {
	tags := make([]string, 0, len(categoryIDs))
	for _, categoryID := range categoryIDs {
		title := skillsMarketCategoryTitle(categoryID)
		if strings.TrimSpace(title) == "" || title == categoryID {
			continue
		}
		tags = append(tags, title)
	}
	return mergeUniqueStrings(nil, tags)
}

func marketReadableTags(values map[string]string) []string {
	if len(values) == 0 {
		return nil
	}
	out := make([]string, 0, len(values))
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		value := strings.TrimSpace(values[key])
		switch key {
		case "latest":
			if value != "" {
				out = append(out, "v"+value)
			}
		default:
			if value != "" {
				out = append(out, value)
			} else if strings.TrimSpace(key) != "" {
				out = append(out, key)
			}
		}
	}
	return mergeUniqueStrings(nil, out)
}

func localizeSkillSummary(name, summary string, categories []string) string {
	summary = strings.TrimSpace(summary)
	if summary == "" {
		return fallbackLocalizedSkillSummary(name, categories)
	}
	if containsHan(summary) {
		return summary
	}

	lower := strings.ToLower(summary)
	switch {
	case strings.Contains(lower, "notion"):
		return "通过 Notion API 处理页面、数据库与内容块。"
	case strings.Contains(lower, "discover and install agent skills"):
		return "帮助发现并安装可用技能，适合扩展代理能力时使用。"
	case strings.Contains(lower, "github") || strings.Contains(lower, "pull request") || strings.Contains(lower, "issue"):
		return "处理 GitHub 仓库、Issue、PR 与代码协作流程。"
	case strings.Contains(lower, "pdf"):
		return "处理 PDF 的读取、提取、总结或转换。"
	case strings.Contains(lower, "calendar"):
		return "读取和管理日历事件、日程与提醒。"
	case strings.Contains(lower, "slack"):
		return "连接 Slack，处理频道消息与协作通知。"
	case strings.Contains(lower, "discord"):
		return "连接 Discord，处理频道消息与机器人协作。"
	case strings.Contains(lower, "email") || strings.Contains(lower, "gmail") || strings.Contains(lower, "mail"):
		return "处理邮件读取、检索与整理。"
	case strings.Contains(lower, "weather") || strings.Contains(lower, "forecast"):
		return "提供天气查询与天气预报能力。"
	case strings.Contains(lower, "browser") || strings.Contains(lower, "playwright") || strings.Contains(lower, "website"):
		return "用于网页浏览、抓取与浏览器自动化。"
	case strings.Contains(lower, "search") || strings.Contains(lower, "discover") || strings.Contains(lower, "find"):
		return "用于搜索、发现和筛选相关技能或信息。"
	case strings.Contains(lower, "summary") || strings.Contains(lower, "summarize"):
		return "用于摘要、总结与信息压缩。"
	case strings.Contains(lower, "translate") || strings.Contains(lower, "translation"):
		return "提供翻译与本地化辅助。"
	case strings.Contains(lower, "database") || strings.Contains(lower, "sql") || strings.Contains(lower, "postgres") || strings.Contains(lower, "mysql") || strings.Contains(lower, "sqlite"):
		return "用于数据库查询、读写与结构化数据处理。"
	case strings.Contains(lower, "task") || strings.Contains(lower, "todo") || strings.Contains(lower, "reminder"):
		return "用于任务、待办与提醒管理。"
	case strings.Contains(lower, "learn") || strings.Contains(lower, "error") || strings.Contains(lower, "continuous improvement"):
		return "记录经验、错误与修正，帮助代理持续改进。"
	}

	prefix := localizedSummaryPrefix(name, categories, lower)
	switch {
	case strings.Contains(lower, "create") && strings.Contains(lower, "manage"):
		return prefix + "支持创建、管理和更新相关内容。"
	case strings.Contains(lower, "query") || strings.Contains(lower, "read"):
		return prefix + "支持读取、查询和整理相关信息。"
	case strings.Contains(lower, "analy") || strings.Contains(lower, "report"):
		return prefix + "适合分析、总结与生成报告。"
	case strings.Contains(lower, "install"):
		return prefix + "支持发现、安装与维护相关能力。"
	default:
		return prefix + "可帮助代理完成相关任务。"
	}
}

func localizedSummaryPrefix(name string, categories []string, lowerSummary string) string {
	switch {
	case strings.Contains(lowerSummary, "api"):
		if domain := fallbackLocalizedSkillSummary(name, categories); domain != "" {
			return strings.TrimSuffix(domain, "。") + "，"
		}
	case strings.Contains(lowerSummary, "workflow") || strings.Contains(lowerSummary, "agent"):
		return "用于自动化工作流与代理协作，"
	}
	return strings.TrimSuffix(fallbackLocalizedSkillSummary(name, categories), "。") + "，"
}

func fallbackLocalizedSkillSummary(name string, categories []string) string {
	if len(categories) > 0 {
		labels := localizedSkillTags(categories)
		if len(labels) > 0 {
			return fmt.Sprintf("面向%s的技能。", strings.Join(labels, "、"))
		}
	}
	name = strings.TrimSpace(name)
	if name == "" {
		return "用于扩展代理能力的技能。"
	}
	return fmt.Sprintf("围绕 %s 的技能。", name)
}

func containsHan(value string) bool {
	for _, r := range value {
		if unicode.In(r, unicode.Han) {
			return true
		}
	}
	return false
}

func mergeUniqueStrings(left []string, right []string) []string {
	seen := map[string]struct{}{}
	out := make([]string, 0, len(left)+len(right))
	push := func(values []string) {
		for _, value := range values {
			value = strings.TrimSpace(value)
			if value == "" {
				continue
			}
			if _, ok := seen[value]; ok {
				continue
			}
			seen[value] = struct{}{}
			out = append(out, value)
		}
	}
	push(left)
	push(right)
	return out
}

func betterMarketString(candidate, existing string) bool {
	candidate = strings.TrimSpace(candidate)
	existing = strings.TrimSpace(existing)
	if candidate == "" {
		return false
	}
	if existing == "" {
		return true
	}
	return len(candidate) > len(existing)
}

func newerMarketTimestamp(candidate, existing *string) bool {
	if candidate == nil || strings.TrimSpace(*candidate) == "" {
		return false
	}
	if existing == nil || strings.TrimSpace(*existing) == "" {
		return true
	}
	return strings.TrimSpace(*candidate) > strings.TrimSpace(*existing)
}

func (app *App) fetchOpenClawSkillMarketDetail(rawSlug string, fresh bool) (OpenClawSkillMarketDetail, error) {
	slug, err := normalizeMarketSkillSlug(rawSlug)
	if err != nil {
		return OpenClawSkillMarketDetail{}, err
	}

	if !fresh {
		app.mu.Lock()
		if cached, ok := app.skillsMarketDetailCache[slug]; ok && time.Since(cached.FetchedAt) <= skillsMarketDetailTTL {
			detail := cached.Detail
			app.mu.Unlock()
			return detail, nil
		}
		app.mu.Unlock()
	}

	marketSummary, marketErr := app.buildDefaultOpenClawSkillsMarketSummary(false, normalizeSkillsMarketSort(""))
	var item *OpenClawSkillMarketItem
	if marketErr == nil {
		item = findMarketItemBySlug(marketSummary.Items, slug)
	}

	var payload clawHubSkillDetailPayload
	if err := fetchJSONWithTimeout(clawHubSkillDetailURL(slug), httpTimeout, &payload); err != nil {
		return OpenClawSkillMarketDetail{}, fmt.Errorf("读取 ClawHub skill 详情失败: %w", err)
	}

	if item == nil {
		categoryIDs := inferSkillsMarketCategoryIDs(firstNonEmpty(payload.Skill.DisplayName, slug), payload.Skill.Summary)
		item = &OpenClawSkillMarketItem{
			Slug:            slug,
			Name:            firstNonEmpty(payload.Skill.DisplayName, slug),
			Summary:         payload.Skill.Summary,
			SummaryZh:       localizeSkillSummary(firstNonEmpty(payload.Skill.DisplayName, slug), payload.Skill.Summary, categoryIDs),
			Owner:           firstNonEmpty(payload.Owner.DisplayName, payload.Owner.Handle),
			RegistryURL:     registryURLForSlug(slug),
			CategoryIDs:     categoryIDs,
			Tags:            localizedSkillTags(categoryIDs),
			Downloads:       payload.Skill.Stats.Downloads,
			InstallsCurrent: payload.Skill.Stats.InstallsCurrent,
			Stars:           payload.Skill.Stats.Stars,
			LatestVersion:   payload.LatestVersion.Version,
			UpdatedAt:       nullableTimeFromMillis(payload.Skill.UpdatedAt),
		}
	} else {
		if strings.TrimSpace(item.Name) == "" {
			item.Name = firstNonEmpty(payload.Skill.DisplayName, slug)
		}
		if strings.TrimSpace(item.Summary) == "" {
			item.Summary = payload.Skill.Summary
		}
		if len(item.CategoryIDs) == 0 {
			item.CategoryIDs = inferSkillsMarketCategoryIDs(item.Name, item.Summary)
		}
		if len(item.Tags) == 0 {
			item.Tags = localizedSkillTags(item.CategoryIDs)
		}
		if strings.TrimSpace(item.SummaryZh) == "" {
			item.SummaryZh = localizeSkillSummary(item.Name, item.Summary, item.CategoryIDs)
		}
		if strings.TrimSpace(item.Owner) == "" {
			item.Owner = firstNonEmpty(payload.Owner.DisplayName, payload.Owner.Handle)
		}
		if item.Downloads == 0 {
			item.Downloads = payload.Skill.Stats.Downloads
		}
		if item.InstallsCurrent == 0 {
			item.InstallsCurrent = payload.Skill.Stats.InstallsCurrent
		}
		if item.Stars == 0 {
			item.Stars = payload.Skill.Stats.Stars
		}
		if strings.TrimSpace(item.LatestVersion) == "" {
			item.LatestVersion = payload.LatestVersion.Version
		}
		if item.UpdatedAt == nil {
			item.UpdatedAt = nullableTimeFromMillis(payload.Skill.UpdatedAt)
		}
	}

	detail := OpenClawSkillMarketDetail{
		CollectedAt: nowISO(),
		Item:        *item,
		CreatedAt:   nullableTimeFromMillis(payload.Skill.CreatedAt),
		UpdatedAt:   nullableTimeFromMillis(payload.Skill.UpdatedAt),
		Stats: OpenClawSkillRegistryStats{
			Comments:        payload.Skill.Stats.Comments,
			Downloads:       payload.Skill.Stats.Downloads,
			InstallsAllTime: payload.Skill.Stats.InstallsAllTime,
			InstallsCurrent: payload.Skill.Stats.InstallsCurrent,
			Stars:           payload.Skill.Stats.Stars,
			Versions:        payload.Skill.Stats.Versions,
		},
		LatestVersion: &OpenClawSkillLatestVersion{
			Version:   nullableString(payload.LatestVersion.Version),
			CreatedAt: nullableTimeFromMillis(payload.LatestVersion.CreatedAt),
			Changelog: nullableString(payload.LatestVersion.Changelog),
			License:   payload.LatestVersion.License,
		},
		Metadata: OpenClawSkillRegistryMetadata{
			OS:      compactStrings(anyStrings(payload.Metadata.OS)),
			Systems: compactStrings(anyStrings(payload.Metadata.Systems)),
		},
	}
	if owner := nullableString(firstNonEmpty(payload.Owner.DisplayName, payload.Owner.Handle)); owner != nil || nullableString(payload.Owner.Image) != nil {
		detail.Owner = &OpenClawSkillRegistryOwner{
			Handle:      nullableString(payload.Owner.Handle),
			DisplayName: owner,
			Image:       nullableString(payload.Owner.Image),
		}
	}
	if payload.Moderation.Verdict != "" || payload.Moderation.IsSuspicious || payload.Moderation.IsMalwareBlocked {
		detail.Moderation = &OpenClawSkillModeration{
			Verdict:          payload.Moderation.Verdict,
			IsSuspicious:     payload.Moderation.IsSuspicious,
			IsMalwareBlocked: payload.Moderation.IsMalwareBlocked,
			ReasonCodes:      append([]string(nil), payload.Moderation.ReasonCodes...),
			Summary:          nullableString(payload.Moderation.Summary),
			UpdatedAt:        nullableTimeFromMillis(payload.Moderation.UpdatedAt),
		}
	}

	app.mu.Lock()
	if app.skillsMarketDetailCache == nil {
		app.skillsMarketDetailCache = map[string]cachedOpenClawSkillMarketDetail{}
	}
	app.skillsMarketDetailCache[slug] = cachedOpenClawSkillMarketDetail{
		Detail:    detail,
		FetchedAt: time.Now(),
	}
	app.mu.Unlock()

	return detail, nil
}

func (app *App) buildOpenClawSkillsInventory(fresh bool) (OpenClawSkillsInventory, error) {
	repaired, err := app.ensureManagerSkillsMountConfigured()
	if err != nil {
		return OpenClawSkillsInventory{}, err
	}
	if repaired {
		fresh = true
	}

	installRoot := app.managerSkillsMarketDir()
	lock := readJSONFile(app.managerSkillsLockPath(), clawHubLockFile{Version: 1, Skills: map[string]clawHubLockSkill{}})
	if lock.Skills == nil {
		lock.Skills = map[string]clawHubLockSkill{}
	}
	origins := app.readManagerSkillOrigins(installRoot)

	inventory := OpenClawSkillsInventory{
		CollectedAt:      nowISO(),
		ManagedDirectory: installRoot,
		LockPath:         app.managerSkillsLockPath(),
		Items:            []OpenClawSkillInventoryItem{},
	}
	itemsBySlug := map[string]OpenClawSkillInventoryItem{}

	summary, err := app.buildOpenClawSkillsSummary(fresh)
	if err != nil {
		inventory.RuntimeError = ptr(err.Error())
	} else {
		for _, skill := range summary.Skills {
			lockEntry, hasLock := lock.Skills[skill.Key]
			origin, hasOrigin := origins[skill.Key]
			managerOwned := hasLock || hasOrigin || pathExists(filepath.Join(installRoot, skill.Key))
			source := classifyInventorySource(skill, summary.ManagedSkillsDir, summary.WorkspaceDir, managerOwned)
			item := OpenClawSkillInventoryItem{
				Slug:             skill.Key,
				Name:             firstNonEmpty(skill.Name, skill.Key),
				Summary:          skill.Description,
				Source:           source,
				RuntimeSource:    nullableString(skill.Source),
				RuntimeStatus:    nullableString(skill.Status),
				Enabled:          ptr(skill.Enabled),
				Eligible:         ptr(skill.Eligible),
				Bundled:          skill.Bundled,
				ManagerOwned:     managerOwned,
				Uninstallable:    managerOwned,
				VisibleInRuntime: true,
				Homepage:         skill.Homepage,
			}
			if hasLock {
				item.InstalledVersion = lockEntry.Version
				item.InstalledAt = nullableTimeFromMillis(lockEntry.InstalledAt)
			}
			if hasOrigin {
				item.OriginRegistry = nullableString(origin.Registry)
				if item.InstalledVersion == nil {
					item.InstalledVersion = origin.InstalledVersion
				}
				if item.InstalledAt == nil {
					item.InstalledAt = nullableTimeFromMillis(origin.InstalledAt)
				}
			}
			itemsBySlug[item.Slug] = item
		}
	}

	for slug, origin := range origins {
		if _, ok := itemsBySlug[slug]; ok {
			continue
		}
		lockEntry, hasLock := lock.Skills[slug]
		item := OpenClawSkillInventoryItem{
			Slug:             slug,
			Name:             slug,
			Summary:          "已安装到 Manager 托管目录，等待 OpenClaw 下一次扫描。",
			Source:           "manager-installed",
			ManagerOwned:     true,
			Uninstallable:    true,
			VisibleInRuntime: false,
			OriginRegistry:   nullableString(origin.Registry),
			InstalledVersion: origin.InstalledVersion,
			InstalledAt:      nullableTimeFromMillis(origin.InstalledAt),
		}
		if hasLock {
			if item.InstalledVersion == nil {
				item.InstalledVersion = lockEntry.Version
			}
			if item.InstalledAt == nil {
				item.InstalledAt = nullableTimeFromMillis(lockEntry.InstalledAt)
			}
		}
		itemsBySlug[slug] = item
	}
	for slug, lockEntry := range lock.Skills {
		if _, ok := itemsBySlug[slug]; ok {
			continue
		}
		itemsBySlug[slug] = OpenClawSkillInventoryItem{
			Slug:             slug,
			Name:             slug,
			Summary:          "安装记录仍在，但磁盘目录已经缺失。",
			Source:           "manager-installed",
			ManagerOwned:     true,
			Uninstallable:    true,
			VisibleInRuntime: false,
			InstalledVersion: lockEntry.Version,
			InstalledAt:      nullableTimeFromMillis(lockEntry.InstalledAt),
		}
	}

	inventory.Items = make([]OpenClawSkillInventoryItem, 0, len(itemsBySlug))
	for _, item := range itemsBySlug {
		inventory.Items = append(inventory.Items, item)
	}

	sort.Slice(inventory.Items, func(i, j int) bool {
		left := inventory.Items[i]
		right := inventory.Items[j]
		leftRank := inventorySourceRank(left.Source)
		rightRank := inventorySourceRank(right.Source)
		if leftRank != rightRank {
			return leftRank < rightRank
		}
		return strings.ToLower(left.Name) < strings.ToLower(right.Name)
	})

	for _, item := range inventory.Items {
		switch item.Source {
		case "manager-installed":
			inventory.ManagerInstalled++
		case "personal":
			inventory.PersonalInstalled++
		case "bundled":
			inventory.BundledInstalled++
		case "workspace":
			inventory.WorkspaceInstalled++
		case "global":
			inventory.GlobalInstalled++
		default:
			inventory.ExternalInstalled++
		}
	}
	inventory.TotalItems = len(inventory.Items)

	return inventory, nil
}

func (app *App) installOpenClawSkill(rawSlug string) (OpenClawSkillMutationResult, error) {
	slug, err := normalizeMarketSkillSlug(rawSlug)
	if err != nil {
		return OpenClawSkillMutationResult{}, err
	}

	app.opMu.Lock()
	defer app.opMu.Unlock()

	detail, detailWarning, err := app.resolveInstallSkillDetail(slug)
	if err != nil {
		return OpenClawSkillMutationResult{}, err
	}
	if detail.Moderation != nil && detail.Moderation.IsMalwareBlocked {
		return OpenClawSkillMutationResult{}, errors.New("该 skill 已被 ClawHub 标记为恶意，已阻止安装")
	}

	installRoot := app.managerSkillsMarketDir()
	if err := ensureDir(installRoot); err != nil {
		return OpenClawSkillMutationResult{}, err
	}
	if err := app.ensureManagerSkillsExtraDir(installRoot); err != nil {
		return OpenClawSkillMutationResult{}, err
	}

	archiveData, downloadNotice, err := app.downloadClawHubSkillArchive(slug, derefString(detail.LatestVersion.Version))
	if err != nil {
		return OpenClawSkillMutationResult{}, err
	}

	stagingRoot, err := os.MkdirTemp(app.managerDir, "skill-install-*")
	if err != nil {
		return OpenClawSkillMutationResult{}, err
	}
	defer os.RemoveAll(stagingRoot)

	stagingDir := filepath.Join(stagingRoot, slug)
	if err := ensureDir(stagingDir); err != nil {
		return OpenClawSkillMutationResult{}, err
	}
	if err := extractZipToDir(archiveData, stagingDir); err != nil {
		return OpenClawSkillMutationResult{}, err
	}

	sourceDir, err := resolveExtractedSkillDir(stagingDir)
	if err != nil {
		return OpenClawSkillMutationResult{}, err
	}

	targetDir := filepath.Join(installRoot, slug)
	if err := os.RemoveAll(targetDir); err != nil {
		return OpenClawSkillMutationResult{}, err
	}
	if err := os.Rename(sourceDir, targetDir); err != nil {
		return OpenClawSkillMutationResult{}, err
	}

	installedAt := time.Now().UnixMilli()
	origin := clawHubOriginFile{
		Version:          1,
		Registry:         defaultClawHubWebBaseURL,
		Slug:             slug,
		InstalledVersion: detail.LatestVersion.Version,
		InstalledAt:      installedAt,
	}
	if err := writeJSONFile(filepath.Join(targetDir, ".clawhub", "origin.json"), origin); err != nil {
		return OpenClawSkillMutationResult{}, err
	}

	lock := app.readManagerSkillLock()
	lock.Skills[slug] = clawHubLockSkill{
		Version:     detail.LatestVersion.Version,
		InstalledAt: installedAt,
	}
	if err := app.writeManagerSkillLock(lock); err != nil {
		return OpenClawSkillMutationResult{}, err
	}

	app.invalidateSkillsCaches()

	messageParts := []string{fmt.Sprintf("已安装 %s 到 Manager 托管目录。", detail.Item.Name)}
	if downloadNotice != "" {
		messageParts = append(messageParts, downloadNotice)
	}
	if detailWarning != "" {
		messageParts = append(messageParts, detailWarning)
	}

	return OpenClawSkillMutationResult{
		OK:               true,
		Action:           "install",
		Slug:             slug,
		Message:          strings.Join(messageParts, " "),
		InstallDirectory: ptr(targetDir),
		InstalledVersion: detail.LatestVersion.Version,
	}, nil
}

func (app *App) uninstallOpenClawSkill(rawSlug string) (OpenClawSkillMutationResult, error) {
	slug, err := normalizeMarketSkillSlug(rawSlug)
	if err != nil {
		return OpenClawSkillMutationResult{}, err
	}

	app.opMu.Lock()
	defer app.opMu.Unlock()

	targetDir := filepath.Join(app.managerSkillsMarketDir(), slug)
	originPath := filepath.Join(targetDir, ".clawhub", "origin.json")
	lock := app.readManagerSkillLock()
	_, inLock := lock.Skills[slug]
	if !pathExists(targetDir) && !pathExists(originPath) && !inLock {
		return OpenClawSkillMutationResult{}, errors.New("该 skill 不在 Manager 托管目录内，无法一键卸载")
	}

	if err := os.RemoveAll(targetDir); err != nil {
		return OpenClawSkillMutationResult{}, err
	}
	delete(lock.Skills, slug)
	if err := app.writeManagerSkillLock(lock); err != nil {
		return OpenClawSkillMutationResult{}, err
	}
	app.invalidateSkillsCaches()

	return OpenClawSkillMutationResult{
		OK:      true,
		Action:  "uninstall",
		Slug:    slug,
		Message: fmt.Sprintf("已从 Manager 托管目录卸载 %s。", slug),
	}, nil
}

func (app *App) fetchAwesomeCatalog() ([]OpenClawSkillMarketCategory, []OpenClawSkillMarketItem, error) {
	readmeURL := awesomeReadmeURL()
	readmeText, err := fetchTextWithTimeout(readmeURL, httpTimeout)
	if err != nil {
		return nil, nil, fmt.Errorf("读取 awesome skills README 失败: %w", err)
	}

	categoryPaths := parseAwesomeCategoryPaths(readmeText)
	if len(categoryPaths) == 0 {
		return nil, nil, errors.New("awesome skills README 中没有发现分类文件")
	}

	type categoryResult struct {
		path  string
		title string
		items []awesomeCatalogItem
		err   error
	}

	results := make(chan categoryResult, len(categoryPaths))
	var wg sync.WaitGroup
	for _, relPath := range categoryPaths {
		wg.Add(1)
		go func(path string) {
			defer wg.Done()
			text, err := fetchTextWithTimeout(awesomeRawURL(path), httpTimeout)
			if err != nil {
				results <- categoryResult{path: path, err: err}
				return
			}
			title, items, err := parseAwesomeCategoryMarkdown(path, text)
			results <- categoryResult{path: path, title: title, items: items, err: err}
		}(relPath)
	}
	wg.Wait()
	close(results)

	categoryTitles := map[string]string{}
	bySlug := map[string]OpenClawSkillMarketItem{}
	var firstErr error
	for result := range results {
		if result.err != nil {
			if firstErr == nil {
				firstErr = result.err
			}
			continue
		}
		categoryID := strings.TrimSuffix(filepath.Base(result.path), filepath.Ext(result.path))
		categoryTitles[categoryID] = result.title
		for _, item := range result.items {
			existing, ok := bySlug[item.Slug]
			if !ok {
				bySlug[item.Slug] = OpenClawSkillMarketItem{
					Slug:        item.Slug,
					Name:        item.Name,
					Summary:     item.Summary,
					SummaryZh:   localizeSkillSummary(item.Name, item.Summary, []string{item.CategoryID}),
					Owner:       item.Owner,
					GitHubURL:   item.GitHubURL,
					RegistryURL: registryURLForSlug(item.Slug),
					CategoryIDs: []string{item.CategoryID},
					Tags:        []string{item.CategoryName},
				}
				continue
			}
			if len(existing.Summary) < len(item.Summary) {
				existing.Summary = item.Summary
			}
			if existing.Name == "" {
				existing.Name = item.Name
			}
			if existing.Owner == "" {
				existing.Owner = item.Owner
			}
			if existing.GitHubURL == "" {
				existing.GitHubURL = item.GitHubURL
			}
			if !containsString(existing.CategoryIDs, item.CategoryID) {
				existing.CategoryIDs = append(existing.CategoryIDs, item.CategoryID)
				sort.Strings(existing.CategoryIDs)
			}
			existing.Tags = mergeUniqueStrings(existing.Tags, []string{item.CategoryName})
			existing.SummaryZh = localizeSkillSummary(existing.Name, existing.Summary, existing.CategoryIDs)
			bySlug[item.Slug] = existing
		}
	}
	if len(bySlug) == 0 {
		if firstErr != nil {
			return nil, nil, firstErr
		}
		return nil, nil, errors.New("awesome skills 分类为空")
	}

	categories := make([]OpenClawSkillMarketCategory, 0, len(categoryTitles))
	for categoryID, title := range categoryTitles {
		count := 0
		for _, item := range bySlug {
			if containsString(item.CategoryIDs, categoryID) {
				count++
			}
		}
		categories = append(categories, OpenClawSkillMarketCategory{
			ID:    categoryID,
			Title: title,
			Count: count,
		})
	}
	sort.Slice(categories, func(i, j int) bool {
		return strings.ToLower(categories[i].Title) < strings.ToLower(categories[j].Title)
	})

	items := make([]OpenClawSkillMarketItem, 0, len(bySlug))
	for _, item := range bySlug {
		sort.Strings(item.CategoryIDs)
		items = append(items, item)
	}
	sort.Slice(items, func(i, j int) bool {
		return strings.ToLower(items[i].Name) < strings.ToLower(items[j].Name)
	})

	return categories, items, nil
}

func parseAwesomeCategoryPaths(readmeText string) []string {
	matches := awesomeCategoryLinkPattern.FindAllStringSubmatch(readmeText, -1)
	seen := map[string]struct{}{}
	out := make([]string, 0, len(matches))
	for _, match := range matches {
		if len(match) < 2 {
			continue
		}
		relPath := strings.TrimSpace(match[1])
		if relPath == "" {
			continue
		}
		if _, ok := seen[relPath]; ok {
			continue
		}
		seen[relPath] = struct{}{}
		out = append(out, relPath)
	}
	sort.Strings(out)
	return out
}

func parseAwesomeCategoryMarkdown(relPath, markdown string) (string, []awesomeCatalogItem, error) {
	categoryID := strings.TrimSuffix(filepath.Base(relPath), filepath.Ext(relPath))
	categoryTitle := strings.ReplaceAll(categoryID, "-", " ")
	for _, line := range strings.Split(markdown, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "#") {
			categoryTitle = strings.TrimSpace(strings.TrimLeft(trimmed, "# "))
			break
		}
	}

	items := []awesomeCatalogItem{}
	for _, line := range strings.Split(markdown, "\n") {
		matches := awesomeSkillLinePattern.FindStringSubmatch(strings.TrimSpace(line))
		if len(matches) != 4 {
			continue
		}
		repoMatch := openClawSkillRepoPattern.FindStringSubmatch(matches[2])
		if len(repoMatch) != 3 {
			continue
		}
		items = append(items, awesomeCatalogItem{
			Slug:         repoMatch[2],
			Name:         strings.TrimSpace(matches[1]),
			Summary:      strings.TrimSpace(matches[3]),
			Owner:        repoMatch[1],
			GitHubURL:    strings.TrimSpace(matches[2]),
			CategoryID:   categoryID,
			CategoryName: categoryTitle,
		})
	}
	if len(items) == 0 {
		return "", nil, fmt.Errorf("分类 %s 没有解析到任何 skill", relPath)
	}
	return categoryTitle, items, nil
}

func normalizeMarketSkillSlug(raw string) (string, error) {
	slug := strings.TrimSpace(raw)
	if !skillSlugPattern.MatchString(slug) || strings.Contains(slug, "..") || strings.ContainsAny(slug, `/\`) {
		return "", errors.New("skill slug 无效")
	}
	return slug, nil
}

func (app *App) managerSkillsMarketDir() string {
	return filepath.Join(app.managerDir, "skills-market")
}

func (app *App) managerSkillsLockPath() string {
	return filepath.Join(app.managerSkillsMarketDir(), ".clawhub", "lock.json")
}

func (app *App) readManagerSkillLock() clawHubLockFile {
	lock := readJSONFile(app.managerSkillsLockPath(), clawHubLockFile{Version: 1, Skills: map[string]clawHubLockSkill{}})
	if lock.Version == 0 {
		lock.Version = 1
	}
	if lock.Skills == nil {
		lock.Skills = map[string]clawHubLockSkill{}
	}
	return lock
}

func (app *App) writeManagerSkillLock(lock clawHubLockFile) error {
	if lock.Version == 0 {
		lock.Version = 1
	}
	if lock.Skills == nil {
		lock.Skills = map[string]clawHubLockSkill{}
	}
	return writeJSONFile(app.managerSkillsLockPath(), lock)
}

func (app *App) readManagerSkillOrigins(installRoot string) map[string]clawHubOriginFile {
	entries, err := os.ReadDir(installRoot)
	if err != nil {
		return map[string]clawHubOriginFile{}
	}
	out := map[string]clawHubOriginFile{}
	for _, entry := range entries {
		if !entry.IsDir() || strings.HasPrefix(entry.Name(), ".") {
			continue
		}
		originPath := filepath.Join(installRoot, entry.Name(), ".clawhub", "origin.json")
		if !pathExists(originPath) {
			continue
		}
		origin := readJSONFile(originPath, clawHubOriginFile{})
		if strings.TrimSpace(origin.Slug) == "" {
			origin.Slug = entry.Name()
		}
		out[entry.Name()] = origin
	}
	return out
}

func skillsExtraDirConfigured(extraDirs []string, want string) bool {
	want = normalizeSkillsExtraDir(want)
	if want == "" {
		return false
	}
	for _, item := range extraDirs {
		if normalizeSkillsExtraDir(item) == want {
			return true
		}
	}
	return false
}

func (app *App) hasManagerInstalledSkills(installRoot string) bool {
	if len(app.readManagerSkillOrigins(installRoot)) > 0 {
		return true
	}
	if len(app.readManagerSkillLock().Skills) > 0 {
		return true
	}
	entries, err := os.ReadDir(installRoot)
	if err != nil {
		return false
	}
	for _, entry := range entries {
		if entry.IsDir() && !strings.HasPrefix(entry.Name(), ".") {
			return true
		}
	}
	return false
}

func normalizeSkillsExtraDir(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	if filepath.IsAbs(value) {
		return filepath.Clean(value)
	}
	return value
}

func (app *App) loadDefaultOpenClawConfigRoot(context string) (string, map[string]any, error) {
	configPath, err := app.resolveConfigPath(defaultProfileName)
	if err != nil {
		return "", nil, err
	}

	var root map[string]any
	if pathExists(configPath) {
		data, err := os.ReadFile(configPath)
		if err != nil {
			return "", nil, err
		}
		if len(bytes.TrimSpace(data)) == 0 {
			root = map[string]any{}
		} else if err := json.Unmarshal(data, &root); err != nil {
			return "", nil, fmt.Errorf("默认 openclaw.json 无法解析，未执行%s: %w", context, err)
		}
	} else {
		root = map[string]any{}
	}
	if root == nil {
		root = map[string]any{}
	}
	return configPath, root, nil
}

func (app *App) saveDefaultOpenClawConfigRoot(configPath string, root map[string]any) error {
	if pathExists(configPath) {
		_ = app.backupFile(configPath, "default-openclaw-config")
	}
	return writeJSONFile(configPath, root)
}

func (app *App) ensureManagerSkillsMountConfigured() (bool, error) {
	installRoot := app.managerSkillsMarketDir()
	if !app.hasManagerInstalledSkills(installRoot) {
		return false, nil
	}

	configSummary, err := app.readOpenClawSkillsConfigSummary()
	if err != nil {
		return false, err
	}
	if skillsExtraDirConfigured(configSummary.ExtraDirs, installRoot) {
		return false, nil
	}
	if err := app.ensureManagerSkillsExtraDir(installRoot); err != nil {
		return false, err
	}
	app.invalidateSkillsCaches()
	return true, nil
}

func (app *App) ensureManagerSkillsExtraDir(extraDir string) error {
	configPath, root, err := app.loadDefaultOpenClawConfigRoot("安装")
	if err != nil {
		return err
	}

	extraDir = normalizeSkillsExtraDir(extraDir)
	if extraDir == "" {
		return errors.New("缺少要挂载的 skills 目录")
	}

	skillsMap := ensureMap(root, "skills")
	loadMap := ensureMap(skillsMap, "load")
	current := compactStrings(anyStrings(loadMap["extraDirs"]))
	if containsString(current, extraDir) {
		return nil
	}
	loadMap["extraDirs"] = append(current, extraDir)
	root["skills"] = skillsMap

	return app.saveDefaultOpenClawConfigRoot(configPath, root)
}

func (app *App) addOpenClawSkillsExtraDir(extraDir string) (OpenClawSkillsConfigMutationResult, error) {
	configPath, root, err := app.loadDefaultOpenClawConfigRoot("skills 目录挂载")
	if err != nil {
		return OpenClawSkillsConfigMutationResult{}, err
	}

	extraDir = normalizeSkillsExtraDir(extraDir)
	if extraDir == "" {
		return OpenClawSkillsConfigMutationResult{}, errors.New("请选择要挂载的目录")
	}

	skillsMap := ensureMap(root, "skills")
	loadMap := ensureMap(skillsMap, "load")
	current := compactStrings(anyStrings(loadMap["extraDirs"]))
	if containsString(current, extraDir) {
		return OpenClawSkillsConfigMutationResult{
			OK:         true,
			Action:     "add-extra-dir",
			Path:       extraDir,
			Message:    "目录已在额外挂载列表里。",
			ConfigPath: configPath,
		}, nil
	}

	loadMap["extraDirs"] = append(current, extraDir)
	root["skills"] = skillsMap
	if err := app.saveDefaultOpenClawConfigRoot(configPath, root); err != nil {
		return OpenClawSkillsConfigMutationResult{}, err
	}
	app.invalidateSkillsCaches()

	return OpenClawSkillsConfigMutationResult{
		OK:         true,
		Action:     "add-extra-dir",
		Path:       extraDir,
		Message:    "已加入额外挂载目录，刷新后会按新配置读取。",
		ConfigPath: configPath,
	}, nil
}

func (app *App) removeOpenClawSkillsExtraDir(extraDir string) (OpenClawSkillsConfigMutationResult, error) {
	configPath, root, err := app.loadDefaultOpenClawConfigRoot("skills 目录变更")
	if err != nil {
		return OpenClawSkillsConfigMutationResult{}, err
	}

	extraDir = normalizeSkillsExtraDir(extraDir)
	if extraDir == "" {
		return OpenClawSkillsConfigMutationResult{}, errors.New("缺少要移除的目录")
	}

	skillsMap := ensureMap(root, "skills")
	loadMap := ensureMap(skillsMap, "load")
	current := compactStrings(anyStrings(loadMap["extraDirs"]))
	next := make([]string, 0, len(current))
	removed := false
	for _, item := range current {
		if normalizeSkillsExtraDir(item) == extraDir {
			removed = true
			continue
		}
		next = append(next, item)
	}
	if !removed {
		return OpenClawSkillsConfigMutationResult{}, errors.New("未找到这个额外挂载目录")
	}

	if len(next) == 0 {
		delete(loadMap, "extraDirs")
	} else {
		loadMap["extraDirs"] = next
	}
	if len(loadMap) == 0 {
		delete(skillsMap, "load")
	}
	root["skills"] = skillsMap
	if err := app.saveDefaultOpenClawConfigRoot(configPath, root); err != nil {
		return OpenClawSkillsConfigMutationResult{}, err
	}
	app.invalidateSkillsCaches()

	return OpenClawSkillsConfigMutationResult{
		OK:         true,
		Action:     "remove-extra-dir",
		Path:       extraDir,
		Message:    "已移除额外挂载目录，刷新后会按新配置读取。",
		ConfigPath: configPath,
	}, nil
}

func (app *App) updateOpenClawSkillsWatcherConfig(watch *bool, watchDebounceMs *int) (OpenClawSkillsConfigMutationResult, error) {
	configPath, root, err := app.loadDefaultOpenClawConfigRoot("skills 监听配置更新")
	if err != nil {
		return OpenClawSkillsConfigMutationResult{}, err
	}

	if watch == nil && watchDebounceMs == nil {
		return OpenClawSkillsConfigMutationResult{}, errors.New("没有可保存的监听配置")
	}
	if watchDebounceMs != nil && *watchDebounceMs <= 0 {
		return OpenClawSkillsConfigMutationResult{}, errors.New("防抖时间必须大于 0")
	}

	skillsMap := ensureMap(root, "skills")
	loadMap := ensureMap(skillsMap, "load")

	currentWatch := false
	if raw, ok := loadMap["watch"].(bool); ok {
		currentWatch = raw
	}
	currentDebounce := anyInt(loadMap["watchDebounceMs"])
	changed := false

	if watch != nil && currentWatch != *watch {
		loadMap["watch"] = *watch
		changed = true
	}
	if watchDebounceMs != nil && currentDebounce != *watchDebounceMs {
		loadMap["watchDebounceMs"] = *watchDebounceMs
		changed = true
	}

	if !changed {
		return OpenClawSkillsConfigMutationResult{
			OK:         true,
			Action:     "update-watch",
			Path:       "",
			Message:    "目录监听配置没有变化。",
			ConfigPath: configPath,
		}, nil
	}

	root["skills"] = skillsMap
	if err := app.saveDefaultOpenClawConfigRoot(configPath, root); err != nil {
		return OpenClawSkillsConfigMutationResult{}, err
	}
	app.invalidateSkillsCaches()

	watchState := "关闭"
	if watch != nil && *watch {
		watchState = "开启"
	} else if watch == nil && currentWatch {
		watchState = "开启"
	}
	message := fmt.Sprintf("目录监听已更新：监听 %s", watchState)
	if watchDebounceMs != nil {
		message += fmt.Sprintf("，防抖 %d ms。", *watchDebounceMs)
	} else {
		message += "。"
	}

	return OpenClawSkillsConfigMutationResult{
		OK:         true,
		Action:     "update-watch",
		Path:       "",
		Message:    message,
		ConfigPath: configPath,
	}, nil
}

func (app *App) updateOpenClawSkillsInstallConfig(
	preferBrew *bool,
	clearPreferBrew bool,
	nodeManager *string,
	clearNodeManager bool,
) (OpenClawSkillsConfigMutationResult, error) {
	if preferBrew == nil && !clearPreferBrew && nodeManager == nil && !clearNodeManager {
		return OpenClawSkillsConfigMutationResult{}, errors.New("没有可保存的安装配置")
	}
	if preferBrew != nil && clearPreferBrew {
		return OpenClawSkillsConfigMutationResult{}, errors.New("preferBrew 不能同时设置和清空")
	}
	if nodeManager != nil && clearNodeManager {
		return OpenClawSkillsConfigMutationResult{}, errors.New("nodeManager 不能同时设置和清空")
	}

	var nextNodeManager *string
	if nodeManager != nil {
		trimmed := strings.TrimSpace(*nodeManager)
		if trimmed == "" {
			return OpenClawSkillsConfigMutationResult{}, errors.New("nodeManager 不能为空")
		}
		nextNodeManager = &trimmed
	}

	configPath, root, err := app.loadDefaultOpenClawConfigRoot("skills 安装配置更新")
	if err != nil {
		return OpenClawSkillsConfigMutationResult{}, err
	}

	skillsMap := ensureMap(root, "skills")
	installMap := ensureMap(skillsMap, "install")
	changed := false

	currentPreferBrew, hasCurrentPreferBrew := installMap["preferBrew"].(bool)
	switch {
	case clearPreferBrew:
		if _, ok := installMap["preferBrew"]; ok {
			delete(installMap, "preferBrew")
			changed = true
		}
	case preferBrew != nil:
		if !hasCurrentPreferBrew || currentPreferBrew != *preferBrew {
			installMap["preferBrew"] = *preferBrew
			changed = true
		}
	}

	currentNodeManager := strings.TrimSpace(anyString(installMap["nodeManager"]))
	switch {
	case clearNodeManager:
		if _, ok := installMap["nodeManager"]; ok {
			delete(installMap, "nodeManager")
			changed = true
		}
	case nextNodeManager != nil:
		if currentNodeManager != *nextNodeManager {
			installMap["nodeManager"] = *nextNodeManager
			changed = true
		}
	}

	if len(installMap) == 0 {
		delete(skillsMap, "install")
	}

	if !changed {
		return OpenClawSkillsConfigMutationResult{
			OK:         true,
			Action:     "update-install",
			Path:       "",
			Message:    "安装配置没有变化。",
			ConfigPath: configPath,
		}, nil
	}

	root["skills"] = skillsMap
	if err := app.saveDefaultOpenClawConfigRoot(configPath, root); err != nil {
		return OpenClawSkillsConfigMutationResult{}, err
	}
	app.invalidateSkillsCaches()

	preferLabel := "未配置"
	if value, ok := installMap["preferBrew"].(bool); ok {
		if value {
			preferLabel = "优先"
		} else {
			preferLabel = "不优先"
		}
	}
	nodeManagerLabel := "未配置"
	if value := strings.TrimSpace(anyString(installMap["nodeManager"])); value != "" {
		nodeManagerLabel = value
	}

	return OpenClawSkillsConfigMutationResult{
		OK:         true,
		Action:     "update-install",
		Path:       "",
		Message:    fmt.Sprintf("安装配置已更新：Homebrew %s，Node 管理器 %s。", preferLabel, nodeManagerLabel),
		ConfigPath: configPath,
	}, nil
}

func (app *App) resolveInstallSkillDetail(slug string) (OpenClawSkillMarketDetail, string, error) {
	detail, err := app.fetchOpenClawSkillMarketDetail(slug, false)
	if err == nil {
		return detail, "", nil
	}

	marketSummary, marketErr := app.buildDefaultOpenClawSkillsMarketSummary(false, normalizeSkillsMarketSort(""))
	if marketErr != nil {
		return OpenClawSkillMarketDetail{}, "", err
	}
	item := findMarketItemBySlug(marketSummary.Items, slug)
	if item == nil {
		return OpenClawSkillMarketDetail{}, "", err
	}

	return OpenClawSkillMarketDetail{
		CollectedAt: nowISO(),
		Item:        *item,
		Metadata: OpenClawSkillRegistryMetadata{
			OS:      []string{},
			Systems: []string{},
		},
	}, "ClawHub 详情读取受限，已按目录信息继续安装。", nil
}

func (app *App) downloadClawHubSkillArchive(slug, version string) ([]byte, string, error) {
	query := url.Values{}
	query.Set("slug", slug)
	if strings.TrimSpace(version) != "" {
		query.Set("version", version)
	}
	downloadURL := clawHubAPIBaseURL() + "/download?" + query.Encode()

	ctx, cancel := context.WithTimeout(context.Background(), skillsMarketDownloadTimeout)
	defer cancel()

	waitedForRateLimit := false
	for attempt := 0; attempt < 3; attempt++ {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, downloadURL, nil)
		if err != nil {
			return nil, "", err
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return nil, "", err
		}

		if resp.StatusCode == http.StatusTooManyRequests {
			retryAfter := parseRetryAfter(resp.Header.Get("Retry-After"))
			body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
			_ = resp.Body.Close()
			if retryAfter <= 0 || retryAfter > skillsMarketMaxRetryAfter || attempt >= 2 {
				message := strings.TrimSpace(string(body))
				if message == "" {
					message = "Rate limit exceeded"
				}
				return nil, "", fmt.Errorf("ClawHub 下载接口限流，约 %d 秒后重试: %s", int(retryAfter.Seconds()), message)
			}
			waitedForRateLimit = true
			select {
			case <-ctx.Done():
				return nil, "", ctx.Err()
			case <-time.After(retryAfter):
			}
			continue
		}

		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
			_ = resp.Body.Close()
			return nil, "", fmt.Errorf("下载 skill 失败: HTTP %d %s", resp.StatusCode, strings.TrimSpace(string(body)))
		}

		data, err := io.ReadAll(io.LimitReader(resp.Body, 64<<20))
		_ = resp.Body.Close()
		if err != nil {
			return nil, "", err
		}
		if len(data) == 0 {
			return nil, "", errors.New("下载 skill 失败: 返回空文件")
		}
		if waitedForRateLimit {
			return data, "ClawHub 下载接口发生过限流，已自动等待后完成安装。", nil
		}
		return data, "", nil
	}

	return nil, "", errors.New("下载 skill 失败: 达到最大重试次数")
}

func parseRetryAfter(raw string) time.Duration {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return 0
	}
	if seconds, err := strconv.Atoi(raw); err == nil {
		if seconds < 0 {
			return 0
		}
		return time.Duration(seconds) * time.Second
	}
	if when, err := http.ParseTime(raw); err == nil {
		delay := time.Until(when)
		if delay < 0 {
			return 0
		}
		return delay
	}
	return 0
}

func extractZipToDir(data []byte, targetDir string) error {
	reader, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return fmt.Errorf("技能压缩包无效: %w", err)
	}

	for _, file := range reader.File {
		name := filepath.Clean(strings.ReplaceAll(strings.TrimSpace(file.Name), "\\", "/"))
		if name == "." || name == "" {
			continue
		}
		if strings.HasPrefix(name, "..") || strings.HasPrefix(name, "/") {
			return fmt.Errorf("技能压缩包包含非法路径: %s", file.Name)
		}

		destination := filepath.Join(targetDir, name)
		prefix := targetDir + string(os.PathSeparator)
		if destination != targetDir && !strings.HasPrefix(destination, prefix) {
			return fmt.Errorf("技能压缩包路径越界: %s", file.Name)
		}

		mode := file.Mode()
		if mode&os.ModeSymlink != 0 {
			return fmt.Errorf("技能压缩包包含符号链接，已拒绝安装: %s", file.Name)
		}

		if file.FileInfo().IsDir() {
			if err := ensureDir(destination); err != nil {
				return err
			}
			continue
		}

		if err := ensureDir(filepath.Dir(destination)); err != nil {
			return err
		}
		handle, err := file.Open()
		if err != nil {
			return err
		}
		content, err := io.ReadAll(handle)
		_ = handle.Close()
		if err != nil {
			return err
		}

		writeMode := os.FileMode(0o644)
		if mode&0o111 != 0 {
			writeMode = 0o755
		}
		if err := os.WriteFile(destination, content, writeMode); err != nil {
			return err
		}
	}
	return nil
}

func resolveExtractedSkillDir(stagingDir string) (string, error) {
	if pathExists(filepath.Join(stagingDir, "SKILL.md")) {
		return stagingDir, nil
	}
	entries, err := os.ReadDir(stagingDir)
	if err != nil {
		return "", err
	}
	realEntries := make([]os.DirEntry, 0, len(entries))
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), ".") {
			continue
		}
		realEntries = append(realEntries, entry)
	}
	if len(realEntries) == 1 && realEntries[0].IsDir() {
		candidate := filepath.Join(stagingDir, realEntries[0].Name())
		if pathExists(filepath.Join(candidate, "SKILL.md")) {
			return candidate, nil
		}
	}
	return "", errors.New("安装失败：压缩包中未找到有效的 skill 根目录")
}

func (app *App) invalidateSkillsCaches() {
	app.mu.Lock()
	defer app.mu.Unlock()
	app.skillsSummaryCache = nil
}

func classifyInventorySource(skill OpenClawSkillSummary, managedSkillsDir, workspaceDir *string, managerOwned bool) string {
	if managerOwned {
		return "manager-installed"
	}
	if skill.Bundled {
		return "bundled"
	}
	source := strings.TrimSpace(skill.Source)
	if strings.HasPrefix(source, "agents-skills-personal") || strings.HasPrefix(source, "agents-skills-local") {
		return "personal"
	}
	if workspaceDir != nil && *workspaceDir != "" && strings.Contains(source, *workspaceDir) {
		return "workspace"
	}
	if managedSkillsDir != nil && *managedSkillsDir != "" && strings.Contains(source, *managedSkillsDir) {
		return "global"
	}
	if source == "" {
		return "external"
	}
	return "external"
}

func inventorySourceRank(source string) int {
	switch source {
	case "manager-installed":
		return 0
	case "personal":
		return 1
	case "workspace":
		return 2
	case "global":
		return 3
	case "external":
		return 4
	case "bundled":
		return 5
	default:
		return 6
	}
}

func findMarketItemBySlug(items []OpenClawSkillMarketItem, slug string) *OpenClawSkillMarketItem {
	for idx := range items {
		if items[idx].Slug == slug {
			item := items[idx]
			return &item
		}
	}
	return nil
}

func awesomeReadmeURL() string {
	return awesomeRawURL("README.md")
}

func awesomeRawURL(relPath string) string {
	base := strings.TrimRight(strings.TrimSpace(os.Getenv("OPENCLAW_SKILLS_MARKET_RAW_BASE_URL")), "/")
	if base == "" {
		base = defaultAwesomeSkillsRawBaseURL
	}
	return base + "/" + strings.TrimLeft(relPath, "/")
}

func clawHubAPIBaseURL() string {
	base := strings.TrimRight(strings.TrimSpace(os.Getenv("OPENCLAW_CLAWHUB_API_BASE_URL")), "/")
	if base == "" {
		base = defaultClawHubAPIBaseURL
	}
	return base
}

func clawHubWebBaseURL() string {
	base := strings.TrimRight(strings.TrimSpace(os.Getenv("OPENCLAW_CLAWHUB_WEB_BASE_URL")), "/")
	if base == "" {
		base = defaultClawHubWebBaseURL
	}
	return base
}

func clawHubSkillDetailURL(slug string) string {
	return clawHubAPIBaseURL() + "/skills/" + url.PathEscape(slug)
}

func registryURLForSlug(slug string) string {
	return clawHubWebBaseURL() + "/skills/" + url.PathEscape(slug)
}

func fetchTextWithTimeout(targetURL string, timeout time.Duration) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, targetURL, nil)
	if err != nil {
		return "", err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return "", fmt.Errorf("HTTP %d %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return "", err
	}
	return string(body), nil
}

func fetchJSONWithTimeout(targetURL string, timeout time.Duration, target any) error {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, targetURL, nil)
	if err != nil {
		return err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return fmt.Errorf("HTTP %d %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	decoder := json.NewDecoder(io.LimitReader(resp.Body, 8<<20))
	return decoder.Decode(target)
}

func ensureMap(root map[string]any, key string) map[string]any {
	if existing, ok := root[key].(map[string]any); ok {
		return existing
	}
	created := map[string]any{}
	root[key] = created
	return created
}

func anyStrings(value any) []string {
	switch typed := value.(type) {
	case []string:
		return typed
	case []any:
		out := make([]string, 0, len(typed))
		for _, item := range typed {
			text := strings.TrimSpace(anyString(item))
			if text == "" {
				continue
			}
			out = append(out, text)
		}
		return out
	default:
		return nil
	}
}
