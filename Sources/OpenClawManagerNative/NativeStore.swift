@preconcurrency import Combine
@preconcurrency import Foundation

struct RuntimeConfig: Codable, Equatable, Sendable {
    var openclawHomeDir: String
    var codexHomeDir: String

    static func `default`() -> RuntimeConfig {
        RuntimeConfig(
            openclawHomeDir: NSHomeDirectory(),
            codexHomeDir: NSHomeDirectory()
        )
    }
}

struct WatchdogState: Codable, Equatable, Sendable {
    var createdAt: String?
    var restartCount: Int?
    var lastRestartAtMs: Int?
    var lastRestartReason: String?
    var lastHealthyAt: String?
    var lastIssueAt: String?
    var lastIssueReason: String?
    var lastLoopAt: String?
    var lastLoopResult: String?
}

struct WatchdogSummary: Equatable, Sendable {
    var installed: Bool
    var configuredForCurrentRoot: Bool
    var monitoredStateDir: String?
    var state: WatchdogState?

    var statusLine: String {
        if !installed {
            return "未启用"
        }
        if !configuredForCurrentRoot {
            return "已启用（目录不匹配）"
        }
        if let result = state?.lastLoopResult, result == "healthy" {
            return "已启用（运行正常）"
        }
        if let result = state?.lastLoopResult, !result.isEmpty {
            return "已启用（最近结果: \(result)）"
        }
        return "已启用"
    }
}

struct ShellCommandResult: Sendable {
    var status: Int32
    var stdout: String
    var stderr: String
}

enum ProfileStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case healthy
    case draining
    case cooldown
    case exhausted
    case reauthRequired = "reauth_required"
    case unknown

    var id: String { rawValue }
}

enum LoginFlowStatus: String, Codable, Sendable {
    case pending
    case completed
    case failed
    case expired
}

enum ActivationTrigger: String, Codable, Sendable {
    case manual
    case auto
    case recommended
}

enum RuntimeMode: String, Codable, Sendable {
    case native
    case desktop
    case docker
    case web
}

enum NativeSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case monitor
    case profiles
    case skills
    case settings
    case diagnostics
    case deployment

    var id: String { rawValue }
}

enum SupportRepairAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case validateConfig = "validate_config"
    case runOpenClawDoctor = "run_openclaw_doctor"
    case runOpenClawDoctorFix = "run_openclaw_doctor_fix"
    case reinstallGatewayService = "reinstall_gateway_service"
    case runWatchdogCheck = "run_watchdog_check"
    case restartGateway = "restart_gateway"
    case reinstallWatchdog = "reinstall_watchdog"
    case openGatewayLog = "open_gateway_log"
    case openWatchdogLog = "open_watchdog_log"

    var id: String { rawValue }
}

struct UsageWindow: Codable, Equatable, Sendable {
    var label: String
    var usedPercent: Int
    var leftPercent: Int
    var resetAt: String?
    var resetInMs: Int?
}

struct UsageSnapshot: Codable, Equatable, Sendable {
    var plan: String?
    var fiveHour: UsageWindow?
    var week: UsageWindow?
}

struct ManagedProfileSnapshot: Decodable, Equatable, Identifiable, Sendable {
    var name: String
    var isDefault: Bool
    var isActive: Bool
    var isRecommended: Bool
    var stateDir: String
    var authStorePath: String
    var hasConfig: Bool
    var hasAuthStore: Bool
    var authMode: String
    var profileId: String?
    var accountEmail: String?
    var accountId: String?
    var primaryProviderId: String?
    var primaryModelId: String?
    var configuredProviderIds: [String]
    var supportsQuota: Bool
    var supportsLogin: Bool
    var loginKind: String?
    var companionRuntimeKind: String?
    var codexHome: String
    var codexConfigPath: String
    var codexAuthPath: String
    var hasCodexConfig: Bool
    var hasCodexAuth: Bool
    var codexAuthMode: String?
    var codexAccountId: String?
    var codexLastRefreshAt: String?
    var tokenExpiresAt: String?
    var tokenExpiresInMs: Int?
    var status: ProfileStatus
    var statusReason: String
    var quota: UsageSnapshot
    var lastError: String?

    var id: String { name }
}

struct AutomationSnapshot: Decodable, Equatable, Sendable {
    var enabled: Bool
    var probeIntervalMinMs: Int
    var probeIntervalMaxMs: Int
    var pollIntervalMs: Int
    var fiveHourDrainPercent: Int
    var weekDrainPercent: Int
    var autoSwitchStatuses: [ProfileStatus]
    var lastProbeAt: String?
    var nextProbeAt: String?
    var lastScheduledDelayMs: Int?
    var lastAutoActivationAt: String?
    var lastAutoActivationFrom: String?
    var lastAutoActivationTo: String?
    var lastAutoActivationReason: String?
    var lastTickError: String?
    var wrapperCommand: String
    var codexWrapperCommand: String
}

struct ManagerSummary: Decodable, Equatable, Sendable {
    var generatedAt: String
    var activeProfileName: String?
    var recommendedProfileName: String?
    var automation: AutomationSnapshot
    var runtime: RuntimeOverview
    var profiles: [ManagedProfileSnapshot]
}

struct RuntimeOverview: Decodable, Equatable, Sendable {
    struct Roots: Decodable, Equatable, Sendable {
        var openclawHomeDir: String
        var codexHomeDir: String
        var managerDir: String
        var defaultOpenClawStateDir: String
        var defaultCodexHome: String
        var oauthCallbackUrl: String
        var oauthCallbackBindHost: String
    }

    struct Daemon: Decodable, Equatable, Sendable {
        var pid: Int
        var host: String
        var port: Int?
        var apiBaseUrl: String?
        var startedAt: String
        var uptimeMs: Int
        var probeIntervalMinMs: Int
        var probeIntervalMaxMs: Int
        var pollIntervalMs: Int
        var nextProbeAt: String?
        var autoActivateEnabled: Bool
        var loopScheduled: Bool
        var loopRunning: Bool
    }

    struct Switching: Decodable, Equatable, Sendable {
        var activeProfileName: String?
        var recommendedProfileName: String?
        var totalProfiles: Int
        var healthyProfiles: Int
        var drainingProfiles: Int
        var riskyProfiles: Int
        var totalActivations: Int
        var manualActivations: Int
        var autoActivations: Int
        var recommendedActivations: Int
        var lastActivationAt: String?
        var lastActivationDurationMs: Int?
        var averageActivationDurationMs: Int?
        var lastActivationTrigger: ActivationTrigger?
        var lastActivationReason: String?
        var lastSyncedAt: String?
    }

    struct Compatibility: Decodable, Equatable, Sendable {
        var allowedOrigins: [String]
        var allowLocalhostDev: Bool
        var browserShellSupported: Bool
        var nativeShellRecommended: Bool
        var wrapperCommand: String
        var codexWrapperCommand: String
    }

    var generatedAt: String
    var mode: RuntimeMode
    var roots: Roots
    var daemon: Daemon
    var switching: Switching
    var compatibility: Compatibility
}

struct AutomationTickResult: Decodable, Equatable, Sendable {
    var switched: Bool
    var fromProfileName: String?
    var toProfileName: String?
    var reason: String
    var summary: ManagerSummary
}

struct LoginFlowSnapshot: Decodable, Equatable, Identifiable, Sendable {
    var id: String
    var profileName: String
    var status: LoginFlowStatus
    var authUrl: String
    var browserOpened: Bool
    var startedAt: String
    var expiresAt: String
    var completedAt: String?
    var error: String?
}

struct SupportLogEvent: Decodable, Equatable, Identifiable, Sendable {
    var timestamp: String
    var kind: String
    var line: String

    var id: String { "\(timestamp)-\(kind)-\(line)" }
}

struct SupportSummary: Decodable, Equatable, Sendable {
    struct Gateway: Decodable, Equatable, Sendable {
        var reachable: Bool
        var url: String?
        var connectLatencyMs: Int?
        var version: String?
        var host: String?
        var error: String?
    }

    struct Discord: Decodable, Equatable, Sendable {
        var status: String
        var lastLoggedInAt: String?
        var lastDisconnectAt: String?
        var disconnectCount15m: Int
        var disconnectCount60m: Int
        var recentEvents: [SupportLogEvent]
        var recommendation: String
    }

    struct Watchdog: Decodable, Equatable, Sendable {
        var installed: Bool
        var monitoredStateDir: String?
        var lastLoopResult: String?
        var lastHealthyAt: String?
        var lastRestartAt: String?
        var restartCount: Int?
        var statePath: String
        var logPath: String
        var statusLine: String
    }

    struct Environment: Decodable, Equatable, Sendable {
        var primaryInterface: String?
        var gatewayAddress: String?
        var vpnLikelyActive: Bool
        var vpnServiceNames: [String]
        var proxyLikelyEnabled: Bool
        var proxySummary: String?
        var lastSleepAt: String?
        var lastWakeAt: String?
        var sleepWakeCount60m: Int
        var riskLevel: String
        var riskySignals: [String]
        var recommendation: String
    }

    struct Maintenance: Decodable, Equatable, Sendable {
        struct Config: Decodable, Equatable, Sendable {
            var path: String
            var exists: Bool
            var valid: Bool
            var detail: String
        }

        struct GatewayService: Decodable, Equatable, Sendable {
            var installed: Bool
            var status: String
            var serviceFile: String?
            var cliConfigPath: String?
            var serviceConfigPath: String?
            var logPath: String?
            var command: String?
            var runtimeStatus: String?
            var probeStatus: String?
            var issue: String?
            var recommendation: String?
        }

        var cliPath: String?
        var stateDir: String
        var config: Config
        var gatewayService: GatewayService
        var doctorCommand: String
        var doctorFixCommand: String
        var gatewayInstallCommand: String
    }

    var collectedAt: String
    var gateway: Gateway
    var discord: Discord
    var watchdog: Watchdog
    var environment: Environment
    var maintenance: Maintenance
}

struct SupportRepairResult: Decodable, Equatable, Sendable {
    var ok: Bool
    var action: SupportRepairAction
    var message: String
    var output: String?
    var summary: SupportSummary
}

struct OpenClawProfileConfigSummary: Decodable, Equatable, Sendable {
    var collectedAt: String
    var profileName: String
    var stateDir: String
    var configPath: String
    var authStorePath: String
    var configExists: Bool
    var authStoreExists: Bool
    var configValid: Bool
    var authStoreValid: Bool
    var configDetail: String
    var authStoreDetail: String
    var primaryProviderId: String?
    var primaryModelId: String?
    var configuredProviderIds: [String]
    var authModes: [String: String]
    var loginKind: String?
    var companionRuntimeKind: String?
    var configUpdatedAt: String?
    var authStoreUpdatedAt: String?
}

struct OpenClawProfileConfigDocument: Decodable, Equatable, Sendable {
    var summary: OpenClawProfileConfigSummary
    var rawConfig: String?
    var rawAuthStore: String?
    var configHash: String?
    var authStoreHash: String?
}

struct OpenClawProfileConfigValidationResult: Decodable, Equatable, Sendable {
    var collectedAt: String
    var profileName: String
    var configPath: String
    var valid: Bool
    var detail: String
    var output: String?
}

struct OpenClawProfileConfigPatch: Encodable, Equatable, Sendable {
    var primaryProviderId: String?
    var primaryModelId: String?
    var authMode: String?
}

struct OpenClawProfileConfigEditRequest: Encodable, Equatable, Sendable {
    var baseHash: String
    var patch: OpenClawProfileConfigPatch
}

struct OpenClawProfileConfigFieldChange: Decodable, Equatable, Identifiable, Sendable {
    var key: String
    var label: String
    var before: String
    var after: String

    var id: String { key }
}

struct OpenClawProfileConfigPreviewResult: Decodable, Equatable, Sendable {
    var collectedAt: String
    var profileName: String
    var configPath: String
    var baseHash: String
    var nextHash: String
    var changed: Bool
    var message: String
    var changes: [OpenClawProfileConfigFieldChange]
    var previewConfig: String
}

struct OpenClawProfileConfigApplyResult: Decodable, Equatable, Sendable {
    var ok: Bool
    var profileName: String
    var configPath: String
    var appliedHash: String
    var changed: Bool
    var message: String
    var changes: [OpenClawProfileConfigFieldChange]
    var validation: OpenClawProfileConfigValidationResult
}

struct MachineSummary: Decodable, Equatable, Sendable {
    struct OpenClaw: Decodable, Equatable, Sendable {
        var available: Bool
        var path: String?
        var source: String
    }

    struct CPU: Decodable, Equatable, Sendable {
        var activePercent: Int
        var userPercent: Int
        var systemPercent: Int
        var idlePercent: Int
        var logicalCores: Int
    }

    struct Memory: Decodable, Equatable, Sendable {
        var totalBytes: Int
        var usedBytes: Int
        var availableBytes: Int
        var wiredBytes: Int
        var activeBytes: Int
        var cachedBytes: Int
        var freeBytes: Int
        var otherBytes: Int
        var compressedBytes: Int
        var usedPercent: Int
        var pressurePercent: Int
        var pressure: String
    }

    struct Swap: Decodable, Equatable, Sendable {
        var totalBytes: Int
        var usedBytes: Int
        var freeBytes: Int
        var usedPercent: Int
    }

    struct Disk: Decodable, Equatable, Sendable {
        var path: String
        var totalBytes: Int
        var usedBytes: Int
        var freeBytes: Int
        var usedPercent: Int
    }

    struct Network: Decodable, Equatable, Sendable {
        var primaryInterface: String?
        var receivedBytesPerSec: Int?
        var sentBytesPerSec: Int?
        var totalReceivedBytes: Int
        var totalSentBytes: Int
    }

    struct ProcessGroup: Decodable, Equatable, Sendable {
        struct Snapshot: Decodable, Equatable, Sendable {
            var running: Bool
            var pid: Int?
            var cpuPercent: Double?
            var rssBytes: Int?
            var uptimeSeconds: Int?
            var command: String?
        }

        var manager: Snapshot
        var watchdog: Snapshot
    }

    struct TopProcess: Decodable, Equatable, Identifiable, Sendable {
        var name: String
        var pid: Int
        var cpuPercent: Double
        var rssBytes: Int
        var uptimeSeconds: Int
        var command: String

        var id: String { "\(pid)-\(command)" }
    }

    var collectedAt: String
    var openClaw: OpenClaw
    var cpu: CPU
    var memory: Memory
    var swap: Swap
    var disk: Disk
    var network: Network
    var processes: ProcessGroup
    var topProcesses: [TopProcess]

    enum CodingKeys: String, CodingKey {
        case collectedAt
        case openClaw = "openclaw"
        case cpu
        case memory
        case swap
        case disk
        case network
        case processes
        case topProcesses
    }

    init(
        collectedAt: String,
        openClaw: OpenClaw,
        cpu: CPU,
        memory: Memory,
        swap: Swap,
        disk: Disk,
        network: Network,
        processes: ProcessGroup,
        topProcesses: [TopProcess]
    ) {
        self.collectedAt = collectedAt
        self.openClaw = openClaw
        self.cpu = cpu
        self.memory = memory
        self.swap = swap
        self.disk = disk
        self.network = network
        self.processes = processes
        self.topProcesses = topProcesses
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.collectedAt = try container.decode(String.self, forKey: .collectedAt)
        self.openClaw = try container.decode(OpenClaw.self, forKey: .openClaw)
        self.cpu = try container.decode(CPU.self, forKey: .cpu)
        self.memory = try container.decode(Memory.self, forKey: .memory)
        self.swap = try container.decode(Swap.self, forKey: .swap)
        self.disk = try container.decode(Disk.self, forKey: .disk)
        self.network = try container.decode(Network.self, forKey: .network)
        self.processes = try container.decode(ProcessGroup.self, forKey: .processes)
        self.topProcesses = try container.decodeIfPresent([TopProcess].self, forKey: .topProcesses) ?? []
    }
}

struct MachineTrendSample: Equatable, Identifiable, Sendable {
    var collectedAt: String
    var cpuActivePercent: Double
    var memoryPressurePercent: Double
    var swapUsedPercent: Double
    var receivedBytesPerSec: Double
    var sentBytesPerSec: Double

    var id: String { collectedAt }
}

struct OpenClawSkillsConfigSummary: Decodable, Equatable, Sendable {
    struct Entry: Decodable, Equatable, Identifiable, Sendable {
        var key: String
        var enabled: Bool?
        var hasEnv: Bool
        var hasApiKey: Bool

        var id: String { key }
    }

    var collectedAt: String
    var configPath: String
    var exists: Bool
    var valid: Bool
    var detail: String
    var allowBundled: [String]
    var extraDirs: [String]
    var watch: Bool?
    var watchDebounceMs: Int?
    var installPreferBrew: Bool?
    var installNodeManager: String?
    var entryCount: Int
    var updatedAt: String?
    var entries: [Entry]
}

struct OpenClawSkillsSummary: Decodable, Equatable, Sendable {
    struct Missing: Decodable, Equatable, Sendable {
        var bins: [String]
        var anyBins: [String]
        var env: [String]
        var config: [String]
        var os: [String]
    }

    struct Skill: Decodable, Equatable, Identifiable, Sendable {
        var key: String
        var name: String
        var description: String
        var emoji: String?
        var source: String
        var bundled: Bool
        var status: String
        var enabled: Bool
        var eligible: Bool
        var blockedByAllowlist: Bool
        var homepage: String?
        var primaryEnv: String?
        var configConfigured: Bool
        var configEnabled: Bool?
        var hasEnvConfig: Bool
        var hasApiKeyConfig: Bool
        var missing: Missing

        var id: String { key }
    }

    var collectedAt: String
    var configPath: String
    var workspaceDir: String?
    var managedSkillsDir: String?
    var totalSkills: Int
    var readySkills: Int
    var disabledSkills: Int
    var blockedSkills: Int
    var missingSkills: Int
    var configuredSkills: Int
    var skills: [Skill]
}

struct NativeLocalSnapshot: Equatable, Sendable {
    var config: RuntimeConfig
    var runtimeRootPath: String?
    var settingsPath: String?
    var appSupportPath: String?
    var apiBaseURL: String?
    var callbackURL: String?
    var watchdog: WatchdogSummary
    var gatewayLogPath: String
    var watchdogLogPath: String
}

struct AutomationSettingsPatch: Encodable, Equatable, Sendable {
    var autoActivateEnabled: Bool
    var probeIntervalMinMs: Int
    var probeIntervalMaxMs: Int
    var fiveHourDrainPercent: Int
    var weekDrainPercent: Int
    var autoSwitchStatuses: [ProfileStatus]
}

struct OpenClawSkillsConfigPatch: Encodable, Equatable, Sendable {
    var addExtraDir: String?
    var removeExtraDir: String?
    var watch: Bool?
    var watchDebounceMs: Int?
    var installPreferBrew: Bool?
    var clearInstallPreferBrew: Bool?
    var installNodeManager: String?
    var clearInstallNodeManager: Bool?
}

struct NativeNotice: Equatable, Identifiable, Sendable {
    enum Tone: String, Sendable {
        case info
        case success
        case warning
        case error
    }

    var id = UUID()
    var tone: Tone
    var title: String
    var detail: String?
}

enum NativeRefreshScope: Sendable {
    case full
    case managerOnly
    case monitorOnly
    case supportOnly
    case settingsOnly
    case skillsOnly
}

struct NativeRefreshRequest: Sendable {
    var silent: Bool
    var scope: NativeRefreshScope
    var busyKey: String?

    static func full(silent: Bool = false) -> NativeRefreshRequest {
        NativeRefreshRequest(silent: silent, scope: .full, busyKey: nil)
    }

    static func managerOnly(silent: Bool = true) -> NativeRefreshRequest {
        NativeRefreshRequest(silent: silent, scope: .managerOnly, busyKey: nil)
    }

    static func monitorOnly(silent: Bool = true) -> NativeRefreshRequest {
        NativeRefreshRequest(silent: silent, scope: .monitorOnly, busyKey: nil)
    }

    static func supportOnly(silent: Bool = true) -> NativeRefreshRequest {
        NativeRefreshRequest(silent: silent, scope: .supportOnly, busyKey: nil)
    }

    static func settingsOnly(silent: Bool = true) -> NativeRefreshRequest {
        NativeRefreshRequest(silent: silent, scope: .settingsOnly, busyKey: nil)
    }

    static func skillsOnly(silent: Bool = true) -> NativeRefreshRequest {
        NativeRefreshRequest(silent: silent, scope: .skillsOnly, busyKey: nil)
    }
}

struct NativeAppActions: Sendable {
    var refreshAll: @Sendable (NativeRefreshRequest) -> Void = { _ in }
    var pollLoginFlow: @Sendable (String) -> Void = { _ in }
    var createProfile: @Sendable (String) -> Void = { _ in }
    var loginProfile: @Sendable (String) -> Void = { _ in }
    var probeProfile: @Sendable (String) -> Void = { _ in }
    var activateProfile: @Sendable (String) -> Void = { _ in }
    var activateRecommended: @Sendable () -> Void = {}
    var validateProfileConfig: @Sendable (String) -> Void = { _ in }
    var previewProfileConfig: @Sendable (String, OpenClawProfileConfigEditRequest) -> Void = { _, _ in }
    var applyProfileConfig: @Sendable (String, OpenClawProfileConfigEditRequest) -> Void = { _, _ in }
    var saveAutomation: @Sendable (AutomationSettingsPatch) -> Void = { _ in }
    var saveSkillsConfig: @Sendable (OpenClawSkillsConfigPatch) -> Void = { _ in }
    var runAutomationTick: @Sendable () -> Void = {}
    var selectOpenClawRoot: @Sendable () -> Void = {}
    var resetOpenClawRoot: @Sendable () -> Void = {}
    var selectCodexRoot: @Sendable () -> Void = {}
    var resetCodexRoot: @Sendable () -> Void = {}
    var openSettingsFile: @Sendable () -> Void = {}
    var openAppSupportDirectory: @Sendable () -> Void = {}
    var openManagerStateDirectory: @Sendable () -> Void = {}
    var restartServices: @Sendable () -> Void = {}
    var supportRepair: @Sendable (SupportRepairAction) -> Void = { _ in }
    var loadSkillMarketDetail: @Sendable (String) -> Void = { _ in }
    var installSkill: @Sendable (String) -> Void = { _ in }
    var uninstallSkill: @Sendable (String) -> Void = { _ in }
    var setSkillEnabled: @Sendable (String, Bool, Bool) -> Void = { _, _, _ in }
    var addSkillsExtraDir: @Sendable () -> Void = {}
    var removeSkillsExtraDir: @Sendable (String) -> Void = { _ in }
    var openURL: @Sendable (URL) -> Void = { _ in }
    var openActivityMonitor: @Sendable () -> Void = {}
    var openGatewayLog: @Sendable () -> Void = {}
    var openWatchdogLog: @Sendable () -> Void = {}
    var openWatchdogStateDirectory: @Sendable () -> Void = {}
}

final class NativeAppStore: ObservableObject, @unchecked Sendable {
    @Published var summary: ManagerSummary?
    @Published var supportSummary: SupportSummary?
    @Published var machineSummary: MachineSummary?
    @Published var openClawProfileConfigDocument: OpenClawProfileConfigDocument?
    @Published var openClawProfileConfigValidation: OpenClawProfileConfigValidationResult?
    @Published var openClawProfileConfigPreview: OpenClawProfileConfigPreviewResult?
    @Published var openClawSkillsSummary: OpenClawSkillsSummary?
    @Published var openClawSkillsConfig: OpenClawSkillsConfigSummary?
    @Published var skillsMarketSummary: OpenClawSkillsMarketSummary?
    @Published var skillsInventory: OpenClawSkillsInventory?
    @Published var skillMarketDetail: OpenClawSkillMarketDetail?
    @Published var machineHistory: [MachineTrendSample] = []
    @Published var lastSupportRepairResult: SupportRepairResult?
    @Published var loginFlow: LoginFlowSnapshot?
    @Published var selectedSection: NativeSection = .overview {
        didSet {
            guard started, oldValue != selectedSection else { return }
            scheduleRefreshTimer()
            switch selectedSection {
            case .diagnostics:
                actions.refreshAll(.full(silent: true))
            case .monitor:
                actions.refreshAll(.monitorOnly(silent: true))
            case .skills:
                actions.refreshAll(.skillsOnly(silent: true))
            case .settings, .profiles:
                actions.refreshAll(.settingsOnly(silent: true))
            default:
                break
            }
        }
    }
    @Published var selectedProfileName: String?
    @Published var busyKeys: Set<String> = []
    @Published var notice: NativeNotice?
    @Published var isLoading = true
    @Published var localSnapshot = NativeLocalSnapshot(
        config: .default(),
        runtimeRootPath: nil,
        settingsPath: nil,
        appSupportPath: nil,
        apiBaseURL: nil,
        callbackURL: nil,
        watchdog: WatchdogSummary(installed: false, configuredForCurrentRoot: false, monitoredStateDir: nil, state: nil),
        gatewayLogPath: "",
        watchdogLogPath: ""
    )

    private var actions = NativeAppActions()
    private var started = false
    private var refreshTimer: Timer?
    private var loginTimer: Timer?
    private var didResolveInitialLandingSection = false
    private let maxMachineHistoryPoints = 72

    var profiles: [ManagedProfileSnapshot] {
        summary?.profiles ?? []
    }

    var automation: AutomationSnapshot? {
        summary?.automation
    }

    var runtime: RuntimeOverview? {
        summary?.runtime
    }

    var activeProfile: ManagedProfileSnapshot? {
        profiles.first(where: \.isActive)
    }

    var recommendedProfile: ManagedProfileSnapshot? {
        profiles.first(where: \.isRecommended)
    }

    var selectedProfile: ManagedProfileSnapshot? {
        if let selectedProfileName, let matched = profiles.first(where: { $0.name == selectedProfileName }) {
            return matched
        }
        return activeProfile ?? recommendedProfile ?? profiles.first
    }

    var configFocusProfileName: String? {
        selectedProfile?.name ?? activeProfile?.name ?? profiles.first?.name
    }

    func configure(actions: NativeAppActions) {
        self.actions = actions
    }

    func start() {
        guard !started else { return }
        started = true
        selectedSection = .overview
        scheduleRefreshTimer()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        loginTimer?.invalidate()
        loginTimer = nil
        started = false
        didResolveInitialLandingSection = false
        machineHistory = []
        openClawProfileConfigDocument = nil
        openClawProfileConfigValidation = nil
        openClawProfileConfigPreview = nil
        openClawSkillsSummary = nil
        openClawSkillsConfig = nil
        skillsMarketSummary = nil
        skillsInventory = nil
        skillMarketDetail = nil
    }

    func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = selectedSection == .monitor ? 5.0 : 30.0
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let request: NativeRefreshRequest
            switch self.selectedSection {
            case .diagnostics:
                request = .full(silent: true)
            case .monitor:
                request = .monitorOnly(silent: true)
            case .skills:
                request = .skillsOnly(silent: true)
            case .settings:
                request = .settingsOnly(silent: true)
            default:
                request = .managerOnly(silent: true)
            }
            self.actions.refreshAll(request)
        }
    }

    func restartLoginFlowTimerIfNeeded() {
        loginTimer?.invalidate()
        guard let loginFlow, loginFlow.status == .pending else {
            loginTimer = nil
            return
        }

        loginTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self, let activeFlow = self.loginFlow, activeFlow.status == .pending else {
                return
            }
            self.actions.pollLoginFlow(activeFlow.id)
        }
    }

    func applyLocalSnapshot(_ snapshot: NativeLocalSnapshot) {
        localSnapshot = snapshot
    }

    func applyRefresh(summary: ManagerSummary, supportSummary: SupportSummary?, machineSummary: MachineSummary?) {
        self.summary = summary
        self.supportSummary = supportSummary ?? self.supportSummary
        if let machineSummary {
            self.machineSummary = machineSummary
            recordMachineHistory(machineSummary)
        }
        isLoading = false
        syncSelectedProfile()
        resolveInitialLandingSectionIfNeeded()
    }

    func applyMachineRefresh(_ machineSummary: MachineSummary) {
        self.machineSummary = machineSummary
        recordMachineHistory(machineSummary)
        isLoading = false
        resolveInitialLandingSectionIfNeeded()
    }

    func applySupportRefresh(_ supportSummary: SupportSummary) {
        self.supportSummary = supportSummary
        isLoading = false
    }

    func applySettingsRefresh(
        profileConfigDocument: OpenClawProfileConfigDocument?,
        skillsSummary: OpenClawSkillsSummary,
        skillsConfig: OpenClawSkillsConfigSummary
    ) {
        openClawProfileConfigDocument = profileConfigDocument
        openClawProfileConfigPreview = nil
        openClawSkillsSummary = skillsSummary
        openClawSkillsConfig = skillsConfig
        isLoading = false
    }

    func applyProfileConfigValidation(_ result: OpenClawProfileConfigValidationResult) {
        openClawProfileConfigValidation = result
    }

    func applyProfileConfigPreview(_ result: OpenClawProfileConfigPreviewResult) {
        openClawProfileConfigPreview = result
    }

    func applySkillsRefresh(
        skillsSummary: OpenClawSkillsSummary,
        skillsConfig: OpenClawSkillsConfigSummary,
        marketSummary: OpenClawSkillsMarketSummary,
        inventory: OpenClawSkillsInventory
    ) {
        openClawSkillsSummary = skillsSummary
        openClawSkillsConfig = skillsConfig
        skillsMarketSummary = marketSummary
        skillsInventory = inventory
        isLoading = false
    }

    func applySkillMarketDetail(_ detail: OpenClawSkillMarketDetail) {
        skillMarketDetail = detail
        isLoading = false
    }

    func applyRefreshError(_ message: String, silent: Bool) {
        if !silent {
            isLoading = false
            showNotice(.error, title: "读取状态失败", detail: message)
        }
    }

    func applyLoginFlow(_ flow: LoginFlowSnapshot) {
        loginFlow = flow
        if flow.status != .pending {
            actions.refreshAll(.managerOnly(silent: true))
        }
        restartLoginFlowTimerIfNeeded()
    }

    func applySupportRepairResult(_ result: SupportRepairResult) {
        lastSupportRepairResult = result
        supportSummary = result.summary
        isLoading = false
    }

    func resolveInitialLandingSectionIfNeeded() {
        guard !didResolveInitialLandingSection, let machineSummary else { return }
        didResolveInitialLandingSection = true
        if !machineSummary.openClaw.available {
            selectedSection = .monitor
        }
    }

    func recordMachineHistory(_ machineSummary: MachineSummary) {
        let sample = MachineTrendSample(
            collectedAt: machineSummary.collectedAt,
            cpuActivePercent: Double(machineSummary.cpu.activePercent),
            memoryPressurePercent: Double(machineSummary.memory.pressurePercent),
            swapUsedPercent: Double(machineSummary.swap.usedPercent),
            receivedBytesPerSec: Double(machineSummary.network.receivedBytesPerSec ?? 0),
            sentBytesPerSec: Double(machineSummary.network.sentBytesPerSec ?? 0)
        )

        if machineHistory.last?.collectedAt == sample.collectedAt {
            machineHistory[machineHistory.count - 1] = sample
            return
        }

        machineHistory.append(sample)
        if machineHistory.count > maxMachineHistoryPoints {
            machineHistory.removeFirst(machineHistory.count - maxMachineHistoryPoints)
        }
    }

    func clearLoginFlow() {
        loginFlow = nil
        restartLoginFlowTimerIfNeeded()
    }

    func setBusy(_ key: String, active: Bool) {
        if active {
            busyKeys.insert(key)
        } else {
            busyKeys.remove(key)
        }
    }

    func isBusy(_ key: String) -> Bool {
        busyKeys.contains(key)
    }

    func showNotice(_ tone: NativeNotice.Tone, title: String, detail: String? = nil) {
        notice = NativeNotice(tone: tone, title: title, detail: detail)
    }

    func dismissNotice() {
        notice = nil
    }

    func syncSelectedProfile() {
        if let selectedProfileName, profiles.contains(where: { $0.name == selectedProfileName }) {
            return
        }
        selectedProfileName = selectedProfile?.name
    }

    func selectProfile(_ name: String?) {
        let shouldRefreshSettings = started && selectedSection == .profiles
        selectedProfileName = name
        openClawProfileConfigPreview = nil
        selectedSection = .profiles
        if shouldRefreshSettings {
            actions.refreshAll(.settingsOnly(silent: true))
        }
    }

    func openPendingLoginInBrowser() {
        guard let authURL = loginFlow?.authUrl, let url = URL(string: authURL) else {
            return
        }
        actions.openURL(url)
    }

    func open(_ url: URL) {
        actions.openURL(url)
    }

    func openActivityMonitor() {
        actions.openActivityMonitor()
    }

    func loadSkillMarketDetail(slug: String) {
        actions.loadSkillMarketDetail(slug)
    }

    func installSkill(slug: String) {
        actions.installSkill(slug)
    }

    func uninstallSkill(slug: String) {
        actions.uninstallSkill(slug)
    }

    func setSkillEnabled(slug: String, enabled: Bool, bundled: Bool) {
        actions.setSkillEnabled(slug, enabled, bundled)
    }

    func addSkillsExtraDir() {
        actions.addSkillsExtraDir()
    }

    func removeSkillsExtraDir(path: String) {
        actions.removeSkillsExtraDir(path)
    }

    func createProfile(named name: String) {
        actions.createProfile(name)
    }

    func refreshAll(silent: Bool = false, scope: NativeRefreshScope = .full, busyKey: String? = nil) {
        actions.refreshAll(NativeRefreshRequest(silent: silent, scope: scope, busyKey: busyKey))
    }

    func login(profileName: String) {
        actions.loginProfile(profileName)
    }

    func probe(profileName: String) {
        actions.probeProfile(profileName)
    }

    func activate(profileName: String) {
        actions.activateProfile(profileName)
    }

    func activateRecommended() {
        actions.activateRecommended()
    }

    func validateProfileConfig(profileName: String) {
        actions.validateProfileConfig(profileName)
    }

    func previewProfileConfig(profileName: String, request: OpenClawProfileConfigEditRequest) {
        actions.previewProfileConfig(profileName, request)
    }

    func applyProfileConfig(profileName: String, request: OpenClawProfileConfigEditRequest) {
        actions.applyProfileConfig(profileName, request)
    }

    func clearProfileConfigPreview() {
        openClawProfileConfigPreview = nil
    }

    func saveAutomation(_ patch: AutomationSettingsPatch) {
        actions.saveAutomation(patch)
    }

    func saveSkillsConfig(_ patch: OpenClawSkillsConfigPatch) {
        actions.saveSkillsConfig(patch)
    }

    func runAutomationTick() {
        actions.runAutomationTick()
    }

    func pickOpenClawRoot() {
        actions.selectOpenClawRoot()
    }

    func resetOpenClawRoot() {
        actions.resetOpenClawRoot()
    }

    func pickCodexRoot() {
        actions.selectCodexRoot()
    }

    func resetCodexRoot() {
        actions.resetCodexRoot()
    }

    func openSettingsFile() {
        actions.openSettingsFile()
    }

    func openAppSupportDirectory() {
        actions.openAppSupportDirectory()
    }

    func openManagerStateDirectory() {
        actions.openManagerStateDirectory()
    }

    func restartServices() {
        actions.restartServices()
    }

    func repair(_ action: SupportRepairAction) {
        actions.supportRepair(action)
    }

    func openGatewayLog() {
        actions.openGatewayLog()
    }

    func openWatchdogLog() {
        actions.openWatchdogLog()
    }

    func openWatchdogStateDirectory() {
        actions.openWatchdogStateDirectory()
    }
}
