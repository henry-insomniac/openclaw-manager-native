import Foundation
import XCTest
@testable import OpenClawManagerNative

final class NativeAppStoreConfigCenterTests: XCTestCase {
    func testSectionSwitchToSettingsRequestsSettingsOnlyRefresh() {
        let store = NativeAppStore()
        let recorder = RefreshRequestRecorder()

        store.configure(actions: NativeAppActions(
            refreshAll: { request in
                recorder.append(request)
            }
        ))

        store.start()
        defer { store.stop() }

        store.selectedSection = .settings

        let requests = recorder.snapshot()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.scope, .settingsOnly)
        XCTAssertEqual(requests.first?.silent, true)
    }

    func testSectionSwitchToSkillsRequestsSkillsOnlyRefresh() {
        let store = NativeAppStore()
        let recorder = RefreshRequestRecorder()

        store.configure(actions: NativeAppActions(
            refreshAll: { request in
                recorder.append(request)
            }
        ))

        store.start()
        defer { store.stop() }

        store.selectedSection = .skills

        let requests = recorder.snapshot()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.scope, .skillsOnly)
        XCTAssertEqual(requests.first?.silent, true)
    }

    func testLoadSkillsMarketForwardsQueryAndSort() {
        let store = NativeAppStore()
        let recorder = SkillsMarketLoadRecorder()

        store.configure(actions: NativeAppActions(
            loadSkillsMarket: { query, sort in
                recorder.record(query: query, sort: sort)
            }
        ))

        store.loadSkillsMarket(query: "notion", sort: .downloads)

        let event = recorder.snapshot()
        XCTAssertEqual(event?.query, "notion")
        XCTAssertEqual(event?.sort, .downloads)
    }

    func testSelectingProfileWhileFocusedOnProfilesRefreshesConfigCenter() {
        let store = NativeAppStore()
        let recorder = RefreshRequestRecorder()

        store.configure(actions: NativeAppActions(
            refreshAll: { request in
                recorder.append(request)
            }
        ))

        let summary = ManagerSummary(
            generatedAt: "2026-03-13T00:00:00Z",
            activeProfileName: "default",
            recommendedProfileName: nil,
            automation: AutomationSnapshot(
                enabled: true,
                probeIntervalMinMs: 90_000,
                probeIntervalMaxMs: 180_000,
                pollIntervalMs: 60_000,
                fiveHourDrainPercent: 20,
                weekDrainPercent: 10,
                autoSwitchStatuses: [.draining],
                lastProbeAt: nil,
                nextProbeAt: nil,
                lastScheduledDelayMs: nil,
                lastAutoActivationAt: nil,
                lastAutoActivationFrom: nil,
                lastAutoActivationTo: nil,
                lastAutoActivationReason: nil,
                lastTickError: nil,
                wrapperCommand: "openclaw-manager-daemon",
                codexWrapperCommand: "openclaw-manager-daemon"
            ),
            runtime: RuntimeOverview(
                generatedAt: "2026-03-13T00:00:00Z",
                mode: .native,
                roots: RuntimeOverview.Roots(
                    openclawHomeDir: "/tmp",
                    codexHomeDir: "/tmp",
                    managerDir: "/tmp/manager",
                    defaultOpenClawStateDir: "/tmp/.openclaw",
                    defaultCodexHome: "/tmp/.codex",
                    oauthCallbackUrl: "http://localhost:1455/auth/callback",
                    oauthCallbackBindHost: "127.0.0.1"
                ),
                daemon: RuntimeOverview.Daemon(
                    pid: 1,
                    host: "127.0.0.1",
                    port: 3311,
                    apiBaseUrl: "http://127.0.0.1:3311/api",
                    startedAt: "2026-03-13T00:00:00Z",
                    uptimeMs: 1000,
                    probeIntervalMinMs: 90_000,
                    probeIntervalMaxMs: 180_000,
                    pollIntervalMs: 60_000,
                    nextProbeAt: nil,
                    autoActivateEnabled: true,
                    loopScheduled: true,
                    loopRunning: false
                ),
                switching: RuntimeOverview.Switching(
                    activeProfileName: "default",
                    recommendedProfileName: nil,
                    totalProfiles: 2,
                    healthyProfiles: 1,
                    drainingProfiles: 0,
                    riskyProfiles: 0,
                    totalActivations: 0,
                    manualActivations: 0,
                    autoActivations: 0,
                    recommendedActivations: 0,
                    lastActivationAt: nil,
                    lastActivationDurationMs: nil,
                    averageActivationDurationMs: nil,
                    lastActivationTrigger: nil,
                    lastActivationReason: nil,
                    lastSyncedAt: nil
                ),
                compatibility: RuntimeOverview.Compatibility(
                    allowedOrigins: [],
                    allowLocalhostDev: true,
                    browserShellSupported: true,
                    nativeShellRecommended: true,
                    wrapperCommand: "openclaw-manager-daemon",
                    codexWrapperCommand: "openclaw-manager-daemon"
                )
            ),
            profiles: [
                ManagedProfileSnapshot(
                    name: "default",
                    isDefault: true,
                    isActive: true,
                    isRecommended: false,
                    stateDir: "/tmp/.openclaw",
                    authStorePath: "/tmp/.openclaw/agents/main/agent/auth-profiles.json",
                    hasConfig: true,
                    hasAuthStore: true,
                    authMode: "chatgpt-oauth",
                    profileId: nil,
                    accountEmail: nil,
                    accountId: nil,
                    primaryProviderId: "openai-codex",
                    primaryModelId: "openai-codex/gpt-5",
                    configuredProviderIds: ["openai-codex"],
                    supportsQuota: false,
                    supportsLogin: true,
                    loginKind: "codex-oauth",
                    companionRuntimeKind: "codex",
                    codexHome: "/tmp/.codex",
                    codexConfigPath: "/tmp/.codex/config.toml",
                    codexAuthPath: "/tmp/.codex/auth.json",
                    hasCodexConfig: true,
                    hasCodexAuth: true,
                    codexAuthMode: "chatgpt-oauth",
                    codexAccountId: nil,
                    codexLastRefreshAt: nil,
                    tokenExpiresAt: nil,
                    tokenExpiresInMs: nil,
                    status: .healthy,
                    statusReason: "healthy",
                    quota: UsageSnapshot(),
                    lastError: nil
                ),
                ManagedProfileSnapshot(
                    name: "beta",
                    isDefault: false,
                    isActive: false,
                    isRecommended: false,
                    stateDir: "/tmp/.openclaw-beta",
                    authStorePath: "/tmp/.openclaw-beta/agents/main/agent/auth-profiles.json",
                    hasConfig: true,
                    hasAuthStore: true,
                    authMode: "configured",
                    profileId: nil,
                    accountEmail: nil,
                    accountId: nil,
                    primaryProviderId: "anthropic",
                    primaryModelId: "anthropic/claude-3-7-sonnet",
                    configuredProviderIds: ["anthropic"],
                    supportsQuota: false,
                    supportsLogin: false,
                    loginKind: nil,
                    companionRuntimeKind: nil,
                    codexHome: "/tmp/.codex-beta",
                    codexConfigPath: "/tmp/.codex-beta/config.toml",
                    codexAuthPath: "/tmp/.codex-beta/auth.json",
                    hasCodexConfig: false,
                    hasCodexAuth: false,
                    codexAuthMode: nil,
                    codexAccountId: nil,
                    codexLastRefreshAt: nil,
                    tokenExpiresAt: nil,
                    tokenExpiresInMs: nil,
                    status: .unknown,
                    statusReason: "configured",
                    quota: UsageSnapshot(),
                    lastError: nil
                )
            ]
        )

        store.applyRefresh(summary: summary, supportSummary: nil, machineSummary: nil)
        store.start()
        defer { store.stop() }
        store.selectedSection = .profiles
        recorder.reset()

        store.selectProfile("beta")

        let requests = recorder.snapshot()
        XCTAssertEqual(store.selectedProfileName, "beta")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.scope, .settingsOnly)
    }

    func testApplySettingsRefreshStoresProfileAndSkillsPayloads() {
        let store = NativeAppStore()

        let profileDocument = OpenClawProfileConfigDocument(
            summary: OpenClawProfileConfigSummary(
                collectedAt: "2026-03-13T00:00:00Z",
                profileName: "default",
                stateDir: "/tmp/.openclaw",
                configPath: "/tmp/.openclaw/openclaw.json",
                authStorePath: "/tmp/.openclaw/agents/main/agent/auth-profiles.json",
                configExists: true,
                authStoreExists: true,
                configValid: true,
                authStoreValid: true,
                configDetail: "配置可读",
                authStoreDetail: "配置可读",
                primaryProviderId: "openai-codex",
                primaryModelId: "openai-codex/gpt-5",
                configuredProviderIds: ["openai-codex"],
                authModes: ["openai-codex": "chatgpt-oauth"],
                loginKind: "codex-oauth",
                companionRuntimeKind: "codex",
                configUpdatedAt: nil,
                authStoreUpdatedAt: nil
            ),
            rawConfig: "{}",
            rawAuthStore: "{}",
            configHash: "abc",
            authStoreHash: "def"
        )

        let skillsSummary = OpenClawSkillsSummary(
            collectedAt: "2026-03-13T00:00:00Z",
            configPath: "/tmp/.openclaw/openclaw.json",
            workspaceDir: "/tmp/workspace",
            managedSkillsDir: "/tmp/.openclaw/skills",
            totalSkills: 1,
            readySkills: 1,
            disabledSkills: 0,
            blockedSkills: 0,
            missingSkills: 0,
            configuredSkills: 1,
            skills: [
                .init(
                    key: "adapt",
                    name: "adapt",
                    description: "desc",
                    emoji: nil,
                    source: "agents-skills-personal",
                    bundled: false,
                    status: "ready",
                    enabled: true,
                    eligible: true,
                    blockedByAllowlist: false,
                    homepage: nil,
                    primaryEnv: nil,
                    configConfigured: true,
                    configEnabled: true,
                    hasEnvConfig: false,
                    hasApiKeyConfig: false,
                    missing: .init(bins: [], anyBins: [], env: [], config: [], os: [])
                )
            ]
        )

        let skillsConfig = OpenClawSkillsConfigSummary(
            collectedAt: "2026-03-13T00:00:00Z",
            configPath: "/tmp/.openclaw/openclaw.json",
            exists: true,
            valid: true,
            detail: "配置可读",
            allowBundled: ["adapt"],
            extraDirs: [],
            watch: true,
            watchDebounceMs: 250,
            installPreferBrew: true,
            installNodeManager: "mise",
            entryCount: 1,
            updatedAt: nil,
            entries: [.init(key: "adapt", enabled: true, hasEnv: false, hasApiKey: false)]
        )

        store.applySettingsRefresh(
            profileConfigDocument: profileDocument,
            skillsSummary: skillsSummary,
            skillsConfig: skillsConfig
        )

        XCTAssertEqual(store.openClawProfileConfigDocument?.summary.profileName, "default")
        XCTAssertEqual(store.openClawSkillsSummary?.totalSkills, 1)
        XCTAssertEqual(store.openClawSkillsConfig?.allowBundled, ["adapt"])
        XCTAssertNil(store.openClawProfileConfigPreview)
    }

    func testAddSkillsExtraDirTriggersAction() {
        let store = NativeAppStore()
        let recorder = CountRecorder()

        store.configure(actions: NativeAppActions(
            addSkillsExtraDir: {
                recorder.increment()
            }
        ))

        store.addSkillsExtraDir()

        XCTAssertEqual(recorder.value, 1)
    }

    func testSaveSkillsConfigForwardsPatch() {
        let store = NativeAppStore()
        let recorder = SkillsConfigPatchRecorder()

        store.configure(actions: NativeAppActions(
            saveSkillsConfig: { patch in
                recorder.append(patch)
            }
        ))

        store.saveSkillsConfig(OpenClawSkillsConfigPatch(
            addExtraDir: nil,
            removeExtraDir: nil,
            watch: true,
            watchDebounceMs: 2500,
            installPreferBrew: nil,
            clearInstallPreferBrew: nil,
            installNodeManager: nil,
            clearInstallNodeManager: nil
        ))

        XCTAssertEqual(recorder.snapshot(), [
            OpenClawSkillsConfigPatch(
                addExtraDir: nil,
                removeExtraDir: nil,
                watch: true,
                watchDebounceMs: 2500,
                installPreferBrew: nil,
                clearInstallPreferBrew: nil,
                installNodeManager: nil,
                clearInstallNodeManager: nil
            )
        ])
    }

    func testSaveSkillsInstallConfigForwardsPatch() {
        let store = NativeAppStore()
        let recorder = SkillsConfigPatchRecorder()

        store.configure(actions: NativeAppActions(
            saveSkillsConfig: { patch in
                recorder.append(patch)
            }
        ))

        store.saveSkillsConfig(OpenClawSkillsConfigPatch(
            addExtraDir: nil,
            removeExtraDir: nil,
            watch: nil,
            watchDebounceMs: nil,
            installPreferBrew: nil,
            clearInstallPreferBrew: true,
            installNodeManager: "pnpm",
            clearInstallNodeManager: nil
        ))

        XCTAssertEqual(recorder.snapshot(), [
            OpenClawSkillsConfigPatch(
                addExtraDir: nil,
                removeExtraDir: nil,
                watch: nil,
                watchDebounceMs: nil,
                installPreferBrew: nil,
                clearInstallPreferBrew: true,
                installNodeManager: "pnpm",
                clearInstallNodeManager: nil
            )
        ])
    }

    func testRemoveSkillsExtraDirForwardsPath() {
        let store = NativeAppStore()
        let recorder = StringRecorder()

        store.configure(actions: NativeAppActions(
            removeSkillsExtraDir: { path in
                recorder.append(path)
            }
        ))

        store.removeSkillsExtraDir(path: "/tmp/custom-skills")

        XCTAssertEqual(recorder.snapshot(), ["/tmp/custom-skills"])
    }

    func testValidateProfileConfigForwardsProfileName() {
        let store = NativeAppStore()
        let recorder = StringRecorder()

        store.configure(actions: NativeAppActions(
            validateProfileConfig: { profileName in
                recorder.append(profileName)
            }
        ))

        store.validateProfileConfig(profileName: "beta")

        XCTAssertEqual(recorder.snapshot(), ["beta"])
    }

    func testPreviewProfileConfigForwardsRequest() {
        let store = NativeAppStore()
        let recorder = ProfileConfigEditRecorder()

        store.configure(actions: NativeAppActions(
            previewProfileConfig: { profileName, request in
                recorder.append(profileName: profileName, request: request)
            }
        ))

        store.previewProfileConfig(
            profileName: "default",
            request: OpenClawProfileConfigEditRequest(
                baseHash: "hash-1",
                patch: OpenClawProfileConfigPatch(
                    primaryProviderId: "openai-codex",
                    primaryModelId: "openai-codex/gpt-5",
                    authMode: "chatgpt-oauth"
                )
            )
        )

        XCTAssertEqual(recorder.snapshot().count, 1)
        XCTAssertEqual(recorder.snapshot().first?.profileName, "default")
        XCTAssertEqual(recorder.snapshot().first?.request.baseHash, "hash-1")
    }

    func testApplyProfileConfigForwardsRequest() {
        let store = NativeAppStore()
        let recorder = ProfileConfigEditRecorder()

        store.configure(actions: NativeAppActions(
            applyProfileConfig: { profileName, request in
                recorder.append(profileName: profileName, request: request)
            }
        ))

        store.applyProfileConfig(
            profileName: "default",
            request: OpenClawProfileConfigEditRequest(
                baseHash: "hash-2",
                patch: OpenClawProfileConfigPatch(
                    primaryProviderId: "openai",
                    primaryModelId: "openai/gpt-5",
                    authMode: "api-key"
                )
            )
        )

        XCTAssertEqual(recorder.snapshot().count, 1)
        XCTAssertEqual(recorder.snapshot().first?.profileName, "default")
        XCTAssertEqual(recorder.snapshot().first?.request.patch.authMode, "api-key")
    }

    func testApplyProfileConfigValidationStoresLatestResult() {
        let store = NativeAppStore()

        store.applyProfileConfigValidation(
            OpenClawProfileConfigValidationResult(
                collectedAt: "2026-03-13T01:23:45Z",
                profileName: "default",
                configPath: "/tmp/.openclaw/openclaw.json",
                valid: false,
                detail: "Schema mismatch",
                output: "Schema mismatch\npath: agents.defaults.model.primary"
            )
        )

        XCTAssertEqual(store.openClawProfileConfigValidation?.profileName, "default")
        XCTAssertEqual(store.openClawProfileConfigValidation?.valid, false)
        XCTAssertEqual(store.openClawProfileConfigValidation?.detail, "Schema mismatch")
    }

    func testApplyProfileConfigPreviewStoresLatestResult() {
        let store = NativeAppStore()

        store.applyProfileConfigPreview(
            OpenClawProfileConfigPreviewResult(
                collectedAt: "2026-03-13T02:00:00Z",
                profileName: "default",
                configPath: "/tmp/.openclaw/openclaw.json",
                baseHash: "base-hash",
                nextHash: "next-hash",
                changed: true,
                message: "将更新 1 项配置。",
                changes: [
                    .init(key: "primaryModelId", label: "主模型", before: "openai-codex/gpt-5", after: "openai-codex/gpt-5.1")
                ],
                previewConfig: "{\n  \"agents\": {}\n}\n"
            )
        )

        XCTAssertEqual(store.openClawProfileConfigPreview?.profileName, "default")
        XCTAssertEqual(store.openClawProfileConfigPreview?.changes.count, 1)
    }

    func testApplySkillsRefreshStoresMarketAndInventoryPayloads() {
        let store = NativeAppStore()

        let skillsSummary = OpenClawSkillsSummary(
            collectedAt: "2026-03-13T00:00:00Z",
            configPath: "/tmp/.openclaw/openclaw.json",
            workspaceDir: "/tmp/workspace",
            managedSkillsDir: "/tmp/.openclaw/skills",
            totalSkills: 0,
            readySkills: 0,
            disabledSkills: 0,
            blockedSkills: 0,
            missingSkills: 0,
            configuredSkills: 0,
            skills: []
        )

        let skillsConfig = OpenClawSkillsConfigSummary(
            collectedAt: "2026-03-13T00:00:00Z",
            configPath: "/tmp/.openclaw/openclaw.json",
            exists: true,
            valid: true,
            detail: "配置可读",
            allowBundled: [],
            extraDirs: ["/tmp/manager/skills-market"],
            watch: true,
            watchDebounceMs: 250,
            installPreferBrew: false,
            installNodeManager: "pnpm",
            entryCount: 0,
            updatedAt: nil,
            entries: []
        )

        let marketSummary = OpenClawSkillsMarketSummary(
            collectedAt: "2026-03-13T00:00:00Z",
            sourceRepo: "https://clawhub.ai/api/v1/skills",
            managedDirectory: "/tmp/manager/skills-market",
            totalItems: 1,
            categories: [.init(id: "git-and-github", title: "Git & GitHub", count: 1)],
            items: [
                .init(
                    slug: "demo-skill",
                    name: "Demo Skill",
                    summary: "desc",
                    summaryZh: "用于演示的技能。",
                    owner: "demo-owner",
                    githubUrl: "https://github.com/openclaw/skills/tree/main/skills/demo-owner/demo-skill",
                    registryUrl: "https://clawhub.ai/demo-skill",
                    categoryIds: ["git-and-github"],
                    tags: ["git"],
                    downloads: 10,
                    stars: 2,
                    installsCurrent: 1,
                    updatedAt: "2026-03-13T00:00:00Z"
                )
            ]
        )

        let inventory = OpenClawSkillsInventory(
            collectedAt: "2026-03-13T00:00:00Z",
            managedDirectory: "/tmp/manager/skills-market",
            lockPath: "/tmp/manager/skills-market/.clawhub/lock.json",
            runtimeError: nil,
            totalItems: 1,
            managerInstalled: 1,
            personalInstalled: 0,
            bundledInstalled: 0,
            workspaceInstalled: 0,
            globalInstalled: 0,
            externalInstalled: 0,
            items: [
                .init(
                    slug: "demo-skill",
                    name: "Demo Skill",
                    summary: "installed",
                    source: "manager-installed",
                    runtimeSource: nil,
                    runtimeStatus: nil,
                    enabled: true,
                    eligible: true,
                    bundled: false,
                    managerOwned: true,
                    uninstallable: true,
                    visibleInRuntime: false,
                    homepage: nil,
                    installedVersion: "1.2.3",
                    installedAt: "2026-03-13T00:00:00Z",
                    originRegistry: "https://clawhub.ai"
                )
            ]
        )

        store.applySkillsRefresh(
            skillsSummary: skillsSummary,
            skillsConfig: skillsConfig,
            marketSummary: marketSummary,
            inventory: inventory
        )

        XCTAssertEqual(store.skillsMarketSummary?.totalItems, 1)
        XCTAssertEqual(store.skillsInventory?.managerInstalled, 1)
        XCTAssertEqual(store.openClawSkillsConfig?.extraDirs, ["/tmp/manager/skills-market"])
    }
}

private final class SkillsMarketLoadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: (query: String, sort: SkillsMarketSort)?

    func record(query: String, sort: SkillsMarketSort) {
        lock.lock()
        latest = (query, sort)
        lock.unlock()
    }

    func snapshot() -> (query: String, sort: SkillsMarketSort)? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }
}

private final class RefreshRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [NativeRefreshRequest] = []

    func append(_ request: NativeRefreshRequest) {
        lock.lock()
        requests.append(request)
        lock.unlock()
    }

    func snapshot() -> [NativeRefreshRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func reset() {
        lock.lock()
        requests.removeAll()
        lock.unlock()
    }
}

private final class StringRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private final class CountRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}

private final class SkillsConfigPatchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [OpenClawSkillsConfigPatch] = []

    func append(_ value: OpenClawSkillsConfigPatch) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [OpenClawSkillsConfigPatch] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private final class ProfileConfigEditRecorder: @unchecked Sendable {
    struct Entry: Equatable {
        var profileName: String
        var request: OpenClawProfileConfigEditRequest
    }

    private let lock = NSLock()
    private var values: [Entry] = []

    func append(profileName: String, request: OpenClawProfileConfigEditRequest) {
        lock.lock()
        values.append(.init(profileName: profileName, request: request))
        lock.unlock()
    }

    func snapshot() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
