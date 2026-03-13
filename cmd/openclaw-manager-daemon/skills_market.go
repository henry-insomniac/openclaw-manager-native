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
)

const (
	skillsMarketCatalogTTL         = 30 * time.Minute
	skillsMarketDetailTTL          = 10 * time.Minute
	skillsMarketDownloadTimeout    = 95 * time.Second
	skillsMarketMaxRetryAfter      = 45 * time.Second
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
}

type cachedOpenClawSkillMarketDetail struct {
	Detail    OpenClawSkillMarketDetail
	FetchedAt time.Time
}

type OpenClawSkillsMarketSummary struct {
	CollectedAt      string                        `json:"collectedAt"`
	SourceRepo       string                        `json:"sourceRepo"`
	ManagedDirectory string                        `json:"managedDirectory"`
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
	Slug        string   `json:"slug"`
	Name        string   `json:"name"`
	Summary     string   `json:"summary"`
	Owner       string   `json:"owner"`
	GitHubURL   string   `json:"githubUrl"`
	RegistryURL string   `json:"registryUrl"`
	CategoryIDs []string `json:"categoryIds"`
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

func (app *App) handleOpenClawSkillsMarket(w http.ResponseWriter, r *http.Request) {
	summary, err := app.buildOpenClawSkillsMarketSummary(r.URL.Query().Get("fresh") == "1")
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

func (app *App) buildOpenClawSkillsMarketSummary(fresh bool) (OpenClawSkillsMarketSummary, error) {
	if !fresh {
		app.mu.Lock()
		if app.skillsMarketCache != nil && time.Since(app.skillsMarketCache.FetchedAt) <= skillsMarketCatalogTTL {
			cached := app.skillsMarketCache.Summary
			app.mu.Unlock()
			return cached, nil
		}
		app.mu.Unlock()
	}

	categories, items, err := app.fetchAwesomeCatalog()
	if err != nil {
		return OpenClawSkillsMarketSummary{}, err
	}
	summary := OpenClawSkillsMarketSummary{
		CollectedAt:      nowISO(),
		SourceRepo:       defaultAwesomeSkillsRepoURL,
		ManagedDirectory: app.managerSkillsMarketDir(),
		TotalItems:       len(items),
		Categories:       categories,
		Items:            items,
	}

	app.mu.Lock()
	app.skillsMarketCache = &cachedOpenClawSkillsMarketSummary{
		Summary:   summary,
		FetchedAt: time.Now(),
	}
	app.mu.Unlock()

	return summary, nil
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

	marketSummary, err := app.buildOpenClawSkillsMarketSummary(false)
	if err != nil {
		return OpenClawSkillMarketDetail{}, err
	}
	item := findMarketItemBySlug(marketSummary.Items, slug)

	var payload clawHubSkillDetailPayload
	if err := fetchJSONWithTimeout(clawHubSkillDetailURL(slug), httpTimeout, &payload); err != nil {
		return OpenClawSkillMarketDetail{}, fmt.Errorf("读取 ClawHub skill 详情失败: %w", err)
	}

	if item == nil {
		item = &OpenClawSkillMarketItem{
			Slug:        slug,
			Name:        firstNonEmpty(payload.Skill.DisplayName, slug),
			Summary:     payload.Skill.Summary,
			RegistryURL: registryURLForSlug(slug),
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
					Owner:       item.Owner,
					GitHubURL:   item.GitHubURL,
					RegistryURL: registryURLForSlug(item.Slug),
					CategoryIDs: []string{item.CategoryID},
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

	marketSummary, marketErr := app.buildOpenClawSkillsMarketSummary(false)
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

func clawHubSkillDetailURL(slug string) string {
	return clawHubAPIBaseURL() + "/skills/" + url.PathEscape(slug)
}

func registryURLForSlug(slug string) string {
	base := strings.TrimRight(strings.TrimSpace(os.Getenv("OPENCLAW_CLAWHUB_WEB_BASE_URL")), "/")
	if base == "" {
		base = defaultClawHubWebBaseURL
	}
	return base + "/" + url.PathEscape(slug)
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
