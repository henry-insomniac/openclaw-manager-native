package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

var errOpenClawProfileConfigConflict = errors.New("openclaw_profile_config_conflict")

type OpenClawProfileConfigPatch struct {
	PrimaryProviderID *string `json:"primaryProviderId,omitempty"`
	PrimaryModelID    *string `json:"primaryModelId,omitempty"`
	AuthMode          *string `json:"authMode,omitempty"`
}

type OpenClawProfileConfigEditRequest struct {
	BaseHash string                     `json:"baseHash"`
	Patch    OpenClawProfileConfigPatch `json:"patch"`
}

type OpenClawProfileConfigFieldChange struct {
	Key    string `json:"key"`
	Label  string `json:"label"`
	Before string `json:"before"`
	After  string `json:"after"`
}

type OpenClawProfileConfigPreviewResult struct {
	CollectedAt   string                             `json:"collectedAt"`
	ProfileName   string                             `json:"profileName"`
	ConfigPath    string                             `json:"configPath"`
	BaseHash      string                             `json:"baseHash"`
	NextHash      string                             `json:"nextHash"`
	Changed       bool                               `json:"changed"`
	Message       string                             `json:"message"`
	Changes       []OpenClawProfileConfigFieldChange `json:"changes"`
	PreviewConfig string                             `json:"previewConfig"`
}

type OpenClawProfileConfigApplyResult struct {
	OK          bool                                  `json:"ok"`
	ProfileName string                                `json:"profileName"`
	ConfigPath  string                                `json:"configPath"`
	AppliedHash string                                `json:"appliedHash"`
	Changed     bool                                  `json:"changed"`
	Message     string                                `json:"message"`
	Changes     []OpenClawProfileConfigFieldChange    `json:"changes"`
	Validation  OpenClawProfileConfigValidationResult `json:"validation"`
}

type openClawProfileConfigEditPlan struct {
	ProfileName   string
	ConfigPath    string
	BaseHash      string
	NextHash      string
	AppliesNow    bool
	Changed       bool
	Message       string
	Changes       []OpenClawProfileConfigFieldChange
	PreviewConfig string
	PreviewBytes  []byte
}

func (app *App) handlePreviewOpenClawProfileConfig(w http.ResponseWriter, r *http.Request) {
	var body OpenClawProfileConfigEditRequest
	if err := decodeJSONBody(r, &body); err != nil {
		writeAPIMessage(w, http.StatusBadRequest, "profile config preview payload is invalid")
		return
	}

	result, err := app.previewOpenClawProfileConfig(r.PathValue("profileName"), body)
	if err != nil {
		writeAPIMessage(w, openClawProfileConfigErrorStatus(err), err.Error())
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (app *App) handleApplyOpenClawProfileConfig(w http.ResponseWriter, r *http.Request) {
	var body OpenClawProfileConfigEditRequest
	if err := decodeJSONBody(r, &body); err != nil {
		writeAPIMessage(w, http.StatusBadRequest, "profile config apply payload is invalid")
		return
	}

	result, err := app.applyOpenClawProfileConfig(r.PathValue("profileName"), body)
	if err != nil {
		writeAPIMessage(w, openClawProfileConfigErrorStatus(err), err.Error())
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (app *App) previewOpenClawProfileConfig(rawProfileName string, request OpenClawProfileConfigEditRequest) (OpenClawProfileConfigPreviewResult, error) {
	plan, err := app.buildOpenClawProfileConfigEditPlan(rawProfileName, request)
	if err != nil {
		return OpenClawProfileConfigPreviewResult{}, err
	}

	return OpenClawProfileConfigPreviewResult{
		CollectedAt:   nowISO(),
		ProfileName:   plan.ProfileName,
		ConfigPath:    plan.ConfigPath,
		BaseHash:      plan.BaseHash,
		NextHash:      plan.NextHash,
		Changed:       plan.Changed,
		Message:       plan.Message,
		Changes:       append([]OpenClawProfileConfigFieldChange(nil), plan.Changes...),
		PreviewConfig: plan.PreviewConfig,
	}, nil
}

func (app *App) applyOpenClawProfileConfig(rawProfileName string, request OpenClawProfileConfigEditRequest) (OpenClawProfileConfigApplyResult, error) {
	app.opMu.Lock()
	defer app.opMu.Unlock()

	plan, err := app.buildOpenClawProfileConfigEditPlan(rawProfileName, request)
	if err != nil {
		return OpenClawProfileConfigApplyResult{}, err
	}

	if !plan.Changed {
		validation, validationErr := app.validateOpenClawProfileConfigUnlocked(plan.ProfileName)
		if validationErr != nil {
			return OpenClawProfileConfigApplyResult{}, validationErr
		}
		return OpenClawProfileConfigApplyResult{
			OK:          true,
			ProfileName: plan.ProfileName,
			ConfigPath:  plan.ConfigPath,
			AppliedHash: plan.BaseHash,
			Changed:     false,
			Message:     plan.Message,
			Changes:     nil,
			Validation:  validation,
		}, nil
	}

	hadOriginal := pathExists(plan.ConfigPath)
	var originalData []byte
	if hadOriginal {
		originalData, err = os.ReadFile(plan.ConfigPath)
		if err != nil {
			return OpenClawProfileConfigApplyResult{}, err
		}
		_ = app.backupFile(plan.ConfigPath, "profile-config-"+plan.ProfileName)
	}

	if err := ensureDir(filepath.Dir(plan.ConfigPath)); err != nil {
		return OpenClawProfileConfigApplyResult{}, err
	}
	if err := os.WriteFile(plan.ConfigPath, plan.PreviewBytes, 0o600); err != nil {
		return OpenClawProfileConfigApplyResult{}, err
	}

	validation, err := app.validateOpenClawProfileConfigUnlocked(plan.ProfileName)
	if err != nil {
		if rollbackErr := restoreOpenClawProfileConfig(plan.ConfigPath, originalData, hadOriginal); rollbackErr != nil {
			return OpenClawProfileConfigApplyResult{}, fmt.Errorf("应用后校验失败且回滚失败: %v; 原始错误: %w", rollbackErr, err)
		}
		return OpenClawProfileConfigApplyResult{}, fmt.Errorf("应用后校验失败，已回滚: %w", err)
	}
	if !validation.Valid {
		if rollbackErr := restoreOpenClawProfileConfig(plan.ConfigPath, originalData, hadOriginal); rollbackErr != nil {
			return OpenClawProfileConfigApplyResult{}, fmt.Errorf("配置校验未通过且回滚失败: %v; 校验结果: %s", rollbackErr, validation.Detail)
		}
		return OpenClawProfileConfigApplyResult{}, fmt.Errorf("配置校验未通过，已回滚: %s", validation.Detail)
	}

	return OpenClawProfileConfigApplyResult{
		OK:          true,
		ProfileName: plan.ProfileName,
		ConfigPath:  plan.ConfigPath,
		AppliedHash: plan.NextHash,
		Changed:     true,
		Message:     openClawProfileConfigApplyMessage(plan.ProfileName, plan.AppliesNow),
		Changes:     append([]OpenClawProfileConfigFieldChange(nil), plan.Changes...),
		Validation:  validation,
	}, nil
}

func (app *App) buildOpenClawProfileConfigEditPlan(rawProfileName string, request OpenClawProfileConfigEditRequest) (openClawProfileConfigEditPlan, error) {
	profileName, err := normalizeProfileName(rawProfileName, true)
	if err != nil {
		return openClawProfileConfigEditPlan{}, err
	}
	appliesNow, err := app.openClawProfileConfigAppliesNow(profileName)
	if err != nil {
		return openClawProfileConfigEditPlan{}, err
	}

	patch, hasPatch, err := normalizeOpenClawProfileConfigPatch(request.Patch)
	if err != nil {
		return openClawProfileConfigEditPlan{}, err
	}
	if !hasPatch {
		return openClawProfileConfigEditPlan{}, errors.New("未提供可预览的配置变更")
	}

	baseHash := strings.TrimSpace(request.BaseHash)
	if baseHash == "" {
		return openClawProfileConfigEditPlan{}, errors.New("缺少 baseHash，请先刷新配置")
	}

	document, err := app.readOpenClawProfileConfigDocument(profileName)
	if err != nil {
		return openClawProfileConfigEditPlan{}, err
	}
	currentHash := strings.TrimSpace(derefString(document.ConfigHash))
	if currentHash != baseHash {
		return openClawProfileConfigEditPlan{}, fmt.Errorf("%w: 配置已被其他操作修改，请先刷新", errOpenClawProfileConfigConflict)
	}

	configPath, root, err := app.loadOpenClawProfileConfigRoot(profileName, openClawProfileConfigEditContextLabel(appliesNow))
	if err != nil {
		return openClawProfileConfigEditPlan{}, err
	}

	currentSnapshot := readOpenClawConfigSnapshot(configPath)
	currentModel := strings.TrimSpace(derefString(currentSnapshot.PrimaryModelID))
	currentProvider := strings.TrimSpace(derefString(currentSnapshot.PrimaryProviderID))
	if currentProvider == "" {
		currentProvider = strings.TrimSpace(derefString(providerIDFromModelID(currentModel)))
	}
	currentAuthMode := resolveAuthMode(currentSnapshot)

	nextModel := currentModel
	if patch.PrimaryModelID != nil {
		nextModel = *patch.PrimaryModelID
	}
	nextProvider := currentProvider
	if patch.PrimaryProviderID != nil {
		nextProvider = *patch.PrimaryProviderID
	}
	nextAuthMode := currentAuthMode
	if patch.AuthMode != nil {
		nextAuthMode = *patch.AuthMode
	}

	if strings.TrimSpace(nextModel) == "" {
		return openClawProfileConfigEditPlan{}, errors.New("主模型不能为空")
	}
	inferredProvider := derefString(providerIDFromModelID(nextModel))
	if inferredProvider == "" {
		return openClawProfileConfigEditPlan{}, errors.New("主模型格式必须是 provider/model")
	}
	if strings.TrimSpace(nextProvider) == "" {
		nextProvider = inferredProvider
	}
	if nextProvider != inferredProvider {
		return openClawProfileConfigEditPlan{}, errors.New("主 Provider 必须与主模型前缀一致")
	}
	if strings.TrimSpace(nextAuthMode) == "" {
		return openClawProfileConfigEditPlan{}, errors.New("认证模式不能为空")
	}

	agentsMap := ensureMap(root, "agents")
	defaultsMap := ensureMap(agentsMap, "defaults")
	modelMap := ensureMap(defaultsMap, "model")
	modelMap["primary"] = nextModel

	authEntry := ensureOpenClawPrimaryAuthProfile(root)
	authEntry["provider"] = nextProvider
	authEntry["mode"] = nextAuthMode

	changes := buildOpenClawProfileConfigFieldChanges(currentProvider, nextProvider, currentModel, nextModel, currentAuthMode, nextAuthMode)
	previewBytes, err := marshalOpenClawConfigPreview(root)
	if err != nil {
		return openClawProfileConfigEditPlan{}, err
	}
	previewText := string(previewBytes)
	nextHash := strings.TrimSpace(derefString(hashText(&previewText)))
	message := openClawProfileConfigPlanMessage(profileName, appliesNow, len(changes))

	return openClawProfileConfigEditPlan{
		ProfileName:   profileName,
		ConfigPath:    configPath,
		BaseHash:      baseHash,
		NextHash:      nextHash,
		AppliesNow:    appliesNow,
		Changed:       len(changes) > 0,
		Message:       message,
		Changes:       changes,
		PreviewConfig: previewText,
		PreviewBytes:  previewBytes,
	}, nil
}

func (app *App) openClawProfileConfigAppliesNow(profileName string) (bool, error) {
	state, err := app.loadNormalizedManagerState()
	if err != nil {
		return false, err
	}
	if state.ActiveProfileName == nil {
		return false, nil
	}
	return *state.ActiveProfileName == profileName, nil
}

func (app *App) loadOpenClawProfileConfigRoot(profileName, context string) (string, map[string]any, error) {
	configPath, err := app.resolveConfigPath(profileName)
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
			return "", nil, fmt.Errorf("%s无法解析，未执行%s: %w", configPath, context, err)
		}
	} else {
		root = map[string]any{}
	}
	if root == nil {
		root = map[string]any{}
	}
	return configPath, root, nil
}

func normalizeOpenClawProfileConfigPatch(patch OpenClawProfileConfigPatch) (OpenClawProfileConfigPatch, bool, error) {
	hasPatch := false
	if patch.PrimaryProviderID != nil {
		hasPatch = true
		value := strings.TrimSpace(*patch.PrimaryProviderID)
		if value == "" {
			return OpenClawProfileConfigPatch{}, false, errors.New("主 Provider 不能为空")
		}
		patch.PrimaryProviderID = ptr(value)
	}
	if patch.PrimaryModelID != nil {
		hasPatch = true
		value := strings.TrimSpace(*patch.PrimaryModelID)
		if value == "" {
			return OpenClawProfileConfigPatch{}, false, errors.New("主模型不能为空")
		}
		patch.PrimaryModelID = ptr(value)
	}
	if patch.AuthMode != nil {
		hasPatch = true
		value := strings.TrimSpace(*patch.AuthMode)
		if value == "" {
			return OpenClawProfileConfigPatch{}, false, errors.New("认证模式不能为空")
		}
		patch.AuthMode = ptr(value)
	}
	return patch, hasPatch, nil
}

func openClawProfileConfigEditContextLabel(appliesNow bool) string {
	if appliesNow {
		return "active profile 配置预览"
	}
	return "inactive profile 配置预览"
}

func openClawProfileConfigPlanMessage(profileName string, appliesNow bool, changeCount int) string {
	if changeCount == 0 {
		if appliesNow {
			return "没有配置变更。"
		}
		return fmt.Sprintf("没有配置变更；%s 的账号文件保持不变。", profileName)
	}
	if appliesNow {
		return fmt.Sprintf("将更新 %d 项配置，并立即校验当前账号。", changeCount)
	}
	return fmt.Sprintf("将更新 %d 项配置；只写入 %s 的账号文件，切换到这个账号后生效。", changeCount, profileName)
}

func openClawProfileConfigApplyMessage(profileName string, appliesNow bool) string {
	if appliesNow {
		return "配置已应用，并完成当前账号校验。"
	}
	return fmt.Sprintf("配置已写入 %s；切换到这个账号后会按新配置运行。", profileName)
}

func ensureOpenClawPrimaryAuthProfile(root map[string]any) map[string]any {
	authMap := ensureMap(root, "auth")
	profilesMap := ensureMap(authMap, "profiles")
	return ensureMap(profilesMap, "default")
}

func buildOpenClawProfileConfigFieldChanges(
	currentProvider string,
	nextProvider string,
	currentModel string,
	nextModel string,
	currentAuthMode string,
	nextAuthMode string,
) []OpenClawProfileConfigFieldChange {
	changes := make([]OpenClawProfileConfigFieldChange, 0, 3)
	if currentProvider != nextProvider {
		changes = append(changes, OpenClawProfileConfigFieldChange{
			Key:    "primaryProviderId",
			Label:  "主 Provider",
			Before: openClawProfileConfigDisplayValue(currentProvider),
			After:  nextProvider,
		})
	}
	if currentModel != nextModel {
		changes = append(changes, OpenClawProfileConfigFieldChange{
			Key:    "primaryModelId",
			Label:  "主模型",
			Before: openClawProfileConfigDisplayValue(currentModel),
			After:  nextModel,
		})
	}
	if currentAuthMode != nextAuthMode {
		changes = append(changes, OpenClawProfileConfigFieldChange{
			Key:    "authMode",
			Label:  "认证模式",
			Before: openClawProfileConfigDisplayValue(currentAuthMode),
			After:  nextAuthMode,
		})
	}
	return changes
}

func marshalOpenClawConfigPreview(root map[string]any) ([]byte, error) {
	data, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(data, '\n'), nil
}

func restoreOpenClawProfileConfig(configPath string, originalData []byte, hadOriginal bool) error {
	if hadOriginal {
		return os.WriteFile(configPath, originalData, 0o600)
	}
	if err := os.Remove(configPath); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

func openClawProfileConfigErrorStatus(err error) int {
	if errors.Is(err, errOpenClawProfileConfigConflict) {
		return http.StatusConflict
	}
	return http.StatusBadRequest
}

func openClawProfileConfigDisplayValue(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return "未配置"
	}
	return value
}
