@preconcurrency import AppKit
import Darwin
@preconcurrency import Foundation
import SwiftUI

private final class RequestResultBox<T>: @unchecked Sendable {
    var value: Result<T, Error>?
}

private final class StatusCodeBox: @unchecked Sendable {
    var value: Int?
}

private enum RuntimeRootTarget: Sendable {
    case openclaw
    case codex
}

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, @unchecked Sendable {
    private let appName = "OpenClaw Manager Native"
    private let automaticTerminationReason = "OpenClaw Manager Native keeps local OpenClaw services available"
    private let apiPreferredPort: UInt16 = 3311
    private let callbackPreferredPort: UInt16 = 1455

    private let store = NativeAppStore()

    private var window: NSWindow?
    private var backendProcess: Process?
    private var runtimeRootURL: URL?
    private var settingsURL: URL?
    private var appSupportURL: URL?
    private var currentConfig = RuntimeConfig.default()
    private var currentApiPort: UInt16?
    private var currentCallbackPort: UInt16?
    private var statusItem: NSStatusItem?
    private var latestManagerSummary: ManagerSummary?
    private var latestSupportSummary: SupportSummary?
    private var latestMachineSummary: MachineSummary?
    private var latestOpenClawProfileConfigDocument: OpenClawProfileConfigDocument?
    private var latestOpenClawSkillsSummary: OpenClawSkillsSummary?
    private var latestOpenClawSkillsConfig: OpenClawSkillsConfigSummary?
    private var latestSkillsMarketSummary: OpenClawSkillsMarketSummary?
    private var latestSkillsInventory: OpenClawSkillsInventory?
    private var lastMenuBarError: String?
    private var isRestarting = false

    private func requireMainThread() {
        precondition(Thread.isMainThread, "AppKit operation must run on the main thread")
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableSuddenTermination()
        ProcessInfo.processInfo.disableAutomaticTermination(automaticTerminationReason)
        NSApp.setActivationPolicy(.regular)
        configureStoreActions()
        configureStatusItem()

        do {
            try initializeEnvironment()
            appendLifecycleLog("application did finish launching")
            pushLocalSnapshotToStore()
            rebuildMenu()
            try restartRuntime(reason: "startup")
            ensureWindow()
            refreshStartupData()
            store.start()
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            showFatalError(error)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        appendLifecycleLog("application will terminate")
        store.stop()
        terminateProcesses()
        ProcessInfo.processInfo.enableAutomaticTermination(automaticTerminationReason)
        ProcessInfo.processInfo.enableSuddenTermination()
    }

    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentMainWindow()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @MainActor
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func configureStoreActions() {
        store.configure(actions: NativeAppActions(
            refreshAll: { [weak self] request in
                Task { @MainActor [weak self] in
                    self?.refreshManagerData(
                        scope: request.scope,
                        showErrorAlerts: false,
                        silentForStore: request.silent,
                        busyKey: request.busyKey
                    )
                }
            },
            pollLoginFlow: { [weak self] flowId in
                Task { @MainActor [weak self] in
                    self?.pollLoginFlow(flowId)
                }
            },
            createProfile: { [weak self] profileName in
                Task { @MainActor [weak self] in
                    self?.createProfile(profileName)
                }
            },
            loginProfile: { [weak self] profileName in
                Task { @MainActor [weak self] in
                    self?.loginProfile(profileName)
                }
            },
            probeProfile: { [weak self] profileName in
                Task { @MainActor [weak self] in
                    self?.probeProfile(profileName)
                }
            },
            activateProfile: { [weak self] profileName in
                Task { @MainActor [weak self] in
                    self?.activateProfile(profileName)
                }
            },
            activateRecommended: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.activateRecommended()
                }
            },
            validateProfileConfig: { [weak self] profileName in
                Task { @MainActor [weak self] in
                    self?.validateProfileConfig(profileName)
                }
            },
            previewProfileConfig: { [weak self] profileName, request in
                Task { @MainActor [weak self] in
                    self?.previewProfileConfig(profileName, request: request)
                }
            },
            applyProfileConfig: { [weak self] profileName, request in
                Task { @MainActor [weak self] in
                    self?.applyProfileConfig(profileName, request: request)
                }
            },
            saveAutomation: { [weak self] patch in
                Task { @MainActor [weak self] in
                    self?.saveAutomation(patch)
                }
            },
            saveSkillsConfig: { [weak self] patch in
                Task { @MainActor [weak self] in
                    self?.saveSkillsConfig(patch)
                }
            },
            runAutomationTick: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.runAutomationTick()
                }
            },
            selectOpenClawRoot: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.selectOpenClawRoot(nil)
                }
            },
            resetOpenClawRoot: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.resetOpenClawRoot(nil)
                }
            },
            selectCodexRoot: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.selectCodexRoot(nil)
                }
            },
            resetCodexRoot: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.resetCodexRoot(nil)
                }
            },
            openSettingsFile: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.openSettingsFile(nil)
                }
            },
            openAppSupportDirectory: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.openAppSupportDirectory(nil)
                }
            },
            openManagerStateDirectory: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.openManagerStateDirectory(nil)
                }
            },
            restartServices: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.restartServices(nil)
                }
            },
            supportRepair: { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.runSupportRepair(action)
                }
            },
            loadSkillMarketDetail: { [weak self] slug in
                Task { @MainActor [weak self] in
                    self?.loadSkillMarketDetail(slug)
                }
            },
            installSkill: { [weak self] slug in
                Task { @MainActor [weak self] in
                    self?.installSkill(slug)
                }
            },
            uninstallSkill: { [weak self] slug in
                Task { @MainActor [weak self] in
                    self?.uninstallSkill(slug)
                }
            },
            setSkillEnabled: { [weak self] slug, enabled, bundled in
                Task { @MainActor [weak self] in
                    self?.setSkillEnabled(slug, enabled: enabled, bundled: bundled)
                }
            },
            addSkillsExtraDir: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.selectSkillsExtraDir()
                }
            },
            removeSkillsExtraDir: { [weak self] path in
                Task { @MainActor [weak self] in
                    self?.removeSkillsExtraDir(path)
                }
            },
            openURL: { url in
                Task { @MainActor in
                    NSWorkspace.shared.open(url)
                }
            },
            openActivityMonitor: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.openActivityMonitor()
                }
            },
            openGatewayLog: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.openGatewayLog(nil)
                }
            },
            openWatchdogLog: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.openWatchdogLog(nil)
                }
            },
            openWatchdogStateDirectory: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.openWatchdogStateDirectory(nil)
                }
            }
        ))
    }

    @MainActor
    private func initializeEnvironment() throws {
        let appSupport = try ensureApplicationSupportDirectory()
        appSupportURL = appSupport
        settingsURL = appSupport.appendingPathComponent("settings.json")
        currentConfig = try loadOrCreateSettings()
        runtimeRootURL = try resolveRuntimeRoot()
    }

    private func ensureApplicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let target = base.appendingPathComponent(appName, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    private func lifecycleLogURL() -> URL? {
        appSupportURL?.appendingPathComponent("native.log")
    }

    private func appendLifecycleLog(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        FileHandle.standardError.write(Data("[native] \(line)".utf8))

        guard let logURL = lifecycleLogURL() else { return }
        let data = Data(line.utf8)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: logURL.path) {
            try? data.write(to: logURL, options: .atomic)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    @MainActor
    private func loadOrCreateSettings() throws -> RuntimeConfig {
        guard let settingsURL else {
            throw NSError(domain: appName, code: 1, userInfo: [NSLocalizedDescriptionKey: "settings.json 路径不可用"])
        }

        if FileManager.default.fileExists(atPath: settingsURL.path) {
            do {
                let data = try Data(contentsOf: settingsURL)
                let decoded = try JSONDecoder().decode(RuntimeConfig.self, from: data)
                return RuntimeConfig(
                    openclawHomeDir: ProcessInfo.processInfo.environment["OPENCLAW_HOME_DIR"] ?? decoded.openclawHomeDir,
                    codexHomeDir: ProcessInfo.processInfo.environment["OPENCLAW_CODEX_HOME_DIR"] ?? decoded.codexHomeDir
                )
            } catch {
                let fallback = RuntimeConfig.default()
                try persistSettings(fallback)
                return fallback
            }
        }

        let config = RuntimeConfig.default()
        try persistSettings(config)
        return config
    }

    @MainActor
    private func persistSettings(_ config: RuntimeConfig) throws {
        guard let settingsURL else {
            throw NSError(domain: appName, code: 2, userInfo: [NSLocalizedDescriptionKey: "settings.json 路径不可用"])
        }
        let data = try JSONEncoder().encode(config)
        try data.write(to: settingsURL, options: .atomic)
        currentConfig = config
        pushLocalSnapshotToStore()
        rebuildMenu()
    }

    private func resolveRuntimeRoot() throws -> URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("runtime", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        var candidate = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
        for _ in 0..<8 {
            let runtime = candidate.appendingPathComponent("vendor/runtime", isDirectory: true)
            if FileManager.default.fileExists(atPath: runtime.path) {
                return runtime
            }
            candidate.deleteLastPathComponent()
        }

        throw NSError(
            domain: appName,
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "未找到 runtime 目录，请先执行 scripts/sync-runtime.sh 或打包脚本"]
        )
    }

    @MainActor
    private func pushLocalSnapshotToStore() {
        let watchdog = collectWatchdogSummary()
        let snapshot = NativeLocalSnapshot(
            config: currentConfig,
            runtimeRootPath: runtimeRootURL?.path,
            settingsPath: settingsURL?.path,
            appSupportPath: appSupportURL?.path,
            apiBaseURL: currentApiPort.map { "http://127.0.0.1:\($0)/api" },
            callbackURL: currentCallbackPort.map { "http://localhost:\($0)/auth/callback" },
            watchdog: watchdog,
            gatewayLogPath: gatewayLogURL().path,
            watchdogLogPath: watchdogLogURL(using: watchdog.monitoredStateDir).path
        )
        store.applyLocalSnapshot(snapshot)
    }

    @MainActor
    private func configureStatusItem() {
        requireMainThread()
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }

        if let button = statusItem?.button {
            let symbolName = latestManagerSummary?.automation.enabled == true
                ? "arrow.triangle.2.circlepath.circle.fill"
                : "pause.circle"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: appName)
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.title = " \(menuBarButtonTitle())"
            button.toolTip = menuBarTooltip()
            button.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        }

        rebuildStatusItemMenu()
    }

    private func menuBarButtonTitle() -> String {
        guard let summary = latestManagerSummary else {
            return currentApiPort == nil ? "启动中" : "OCM"
        }

        if let active = summary.activeProfileName, !active.isEmpty {
            return truncatedLabel(active, maxLength: 10)
        }

        return summary.automation.enabled ? "在线" : "手动"
    }

    private func menuBarTooltip() -> String {
        if let summary = latestManagerSummary {
            let active = summary.activeProfileName ?? "未激活"
            let recommended = summary.recommendedProfileName ?? "无"
            let automation = summary.automation.enabled ? "已开启" : "已关闭"
            return "当前: \(active)\n推荐: \(recommended)\n自动切换: \(automation)"
        }

        if let lastMenuBarError, !lastMenuBarError.isEmpty {
            return "状态读取失败: \(lastMenuBarError)"
        }

        return appName
    }

    private func truncatedLabel(_ value: String, maxLength: Int) -> String {
        if value.count <= maxLength {
            return value
        }

        let prefix = value.prefix(max(3, maxLength - 1))
        return "\(prefix)…"
    }

    private func activeMenuBarProfile() -> ManagedProfileSnapshot? {
        guard let summary = latestManagerSummary else { return nil }
        return summary.profiles.first(where: { $0.isActive || $0.name == summary.activeProfileName })
    }

    private func makeStatusInfoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @MainActor
    private func rebuildStatusItemMenu() {
        requireMainThread()
        guard let statusItem else { return }

        let watchdog = collectWatchdogSummary()
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(makeStatusInfoItem(appName))

        if let summary = latestManagerSummary {
            let activeLabel = activeMenuBarProfile()?.accountEmail ?? summary.activeProfileName ?? "未激活"
            menu.addItem(makeStatusInfoItem("当前: \(summary.activeProfileName ?? "未激活")"))
            menu.addItem(makeStatusInfoItem("账号: \(activeLabel)"))
            menu.addItem(makeStatusInfoItem("推荐: \(summary.recommendedProfileName ?? "无")"))
            menu.addItem(makeStatusInfoItem("自动切换: \(summary.automation.enabled ? "已开启" : "已关闭")"))
            menu.addItem(makeStatusInfoItem("已发现 profile: \(summary.profiles.count)"))
            if let reason = summary.automation.lastAutoActivationReason, !reason.isEmpty {
                menu.addItem(makeStatusInfoItem("最近结果: \(reason)"))
            }
        } else if let lastMenuBarError, !lastMenuBarError.isEmpty {
            menu.addItem(makeStatusInfoItem("状态读取失败"))
            menu.addItem(makeStatusInfoItem(lastMenuBarError))
        } else {
            menu.addItem(makeStatusInfoItem("正在连接本地服务..."))
        }

        menu.addItem(.separator())

        let showWindowItem = menu.addItem(withTitle: "显示主窗口", action: #selector(showMainWindow(_:)), keyEquivalent: "")
        showWindowItem.target = self

        let recommendedItem = menu.addItem(withTitle: "切到推荐账号", action: #selector(activateRecommendedFromMenuBar(_:)), keyEquivalent: "")
        recommendedItem.target = self
        recommendedItem.isEnabled = latestManagerSummary?.recommendedProfileName != nil

        if let summary = latestManagerSummary, !summary.profiles.isEmpty {
            let quickSwitchItem = NSMenuItem()
            menu.addItem(quickSwitchItem)

            let quickSwitchMenu = NSMenu(title: "快速切换")
            quickSwitchItem.submenu = quickSwitchMenu

            let sortedProfiles = summary.profiles.sorted { left, right in
                let leftRank = left.isActive ? 0 : left.isRecommended ? 1 : 2
                let rightRank = right.isActive ? 0 : right.isRecommended ? 1 : 2
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }

            for profile in sortedProfiles {
                let email = profile.accountEmail ?? "未登录"
                let prefix = profile.isActive ? "当前" : profile.isRecommended ? "推荐" : "切换"
                let item = quickSwitchMenu.addItem(
                    withTitle: "\(prefix) · \(profile.name) · \(email)",
                    action: #selector(activateProfileFromMenuBar(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = profile.name
                item.isEnabled = !profile.isActive
            }
        }

        let automationEnabled = latestManagerSummary?.automation.enabled ?? false
        let toggleTitle = automationEnabled ? "关闭自动切换" : "开启自动切换"
        let toggleItem = menu.addItem(withTitle: toggleTitle, action: #selector(toggleAutomationFromMenuBar(_:)), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.isEnabled = latestManagerSummary != nil

        let tickItem = menu.addItem(withTitle: "立即执行一轮探测", action: #selector(runAutomationTickFromMenuBar(_:)), keyEquivalent: "")
        tickItem.target = self
        tickItem.isEnabled = latestManagerSummary != nil

        let refreshItem = menu.addItem(withTitle: "刷新菜单状态", action: #selector(refreshMenuBarNow(_:)), keyEquivalent: "")
        refreshItem.target = self

        menu.addItem(.separator())
        menu.addItem(makeStatusInfoItem("稳定守护: \(watchdog.statusLine)"))

        let restartItem = menu.addItem(withTitle: "重启服务并刷新窗口", action: #selector(restartServices(_:)), keyEquivalent: "")
        restartItem.target = self

        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp

        statusItem.menu = menu
        configureStatusItemButtonOnly()
    }

    @MainActor
    private func configureStatusItemButtonOnly() {
        requireMainThread()
        guard let button = statusItem?.button else { return }
        let symbolName = latestManagerSummary?.automation.enabled == true
            ? "arrow.triangle.2.circlepath.circle.fill"
            : "pause.circle"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: appName)
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.title = " \(menuBarButtonTitle())"
        button.toolTip = menuBarTooltip()
    }

    @MainActor
    private func applyRefreshedState(summary: ManagerSummary, supportSummary: SupportSummary?, machineSummary: MachineSummary?) {
        latestManagerSummary = summary
        latestSupportSummary = supportSummary
        if let machineSummary {
            latestMachineSummary = machineSummary
        }
        lastMenuBarError = nil
        pushLocalSnapshotToStore()
        rebuildStatusItemMenu()
        rebuildMenu()
        store.applyRefresh(summary: summary, supportSummary: supportSummary, machineSummary: machineSummary)
    }

    @MainActor
    private func applyMachineRefreshedState(_ machineSummary: MachineSummary) {
        latestMachineSummary = machineSummary
        lastMenuBarError = nil
        store.applyMachineRefresh(machineSummary)
    }

    @MainActor
    private func applySupportRefreshedState(_ supportSummary: SupportSummary) {
        latestSupportSummary = supportSummary
        lastMenuBarError = nil
        pushLocalSnapshotToStore()
        rebuildStatusItemMenu()
        rebuildMenu()
        store.applySupportRefresh(supportSummary)
    }

    @MainActor
    private func applySettingsRefreshedState(
        profileConfigDocument: OpenClawProfileConfigDocument?,
        skillsSummary: OpenClawSkillsSummary,
        skillsConfig: OpenClawSkillsConfigSummary
    ) {
        latestOpenClawProfileConfigDocument = profileConfigDocument
        latestOpenClawSkillsSummary = skillsSummary
        latestOpenClawSkillsConfig = skillsConfig
        lastMenuBarError = nil
        store.applySettingsRefresh(
            profileConfigDocument: profileConfigDocument,
            skillsSummary: skillsSummary,
            skillsConfig: skillsConfig
        )
    }

    @MainActor
    private func applySkillsRefreshedState(
        skillsSummary: OpenClawSkillsSummary,
        skillsConfig: OpenClawSkillsConfigSummary,
        marketSummary: OpenClawSkillsMarketSummary,
        inventory: OpenClawSkillsInventory
    ) {
        latestOpenClawSkillsSummary = skillsSummary
        latestOpenClawSkillsConfig = skillsConfig
        latestSkillsMarketSummary = marketSummary
        latestSkillsInventory = inventory
        lastMenuBarError = nil
        store.applySkillsRefresh(
            skillsSummary: skillsSummary,
            skillsConfig: skillsConfig,
            marketSummary: marketSummary,
            inventory: inventory
        )
    }

    @MainActor
    private func refreshStartupData(showErrorAlerts: Bool = false, silentForStore: Bool = true) {
        refreshManagerData(scope: .managerOnly, showErrorAlerts: showErrorAlerts, silentForStore: silentForStore)
        refreshManagerData(scope: .monitorOnly, silentForStore: true)
        if store.selectedSection == .diagnostics {
            refreshManagerData(scope: .supportOnly, showErrorAlerts: showErrorAlerts, silentForStore: silentForStore)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.store.selectedSection != .diagnostics else { return }
            self.refreshManagerData(scope: .supportOnly, silentForStore: true)
        }
    }

    @MainActor
    private func refreshManagerData(
        scope: NativeRefreshScope = .full,
        showErrorAlerts: Bool = false,
        silentForStore: Bool = true,
        busyKey: String? = nil
    ) {
        if let busyKey {
            store.setBusy(busyKey, active: true)
        }
        guard currentApiPort != nil else {
            latestManagerSummary = nil
            latestSupportSummary = nil
            latestMachineSummary = nil
            latestOpenClawProfileConfigDocument = nil
            latestOpenClawSkillsSummary = nil
            latestOpenClawSkillsConfig = nil
            latestSkillsMarketSummary = nil
            latestSkillsInventory = nil
            lastMenuBarError = "本地服务还没有启动完成"
            pushLocalSnapshotToStore()
            rebuildStatusItemMenu()
            rebuildMenu()
            store.applyRefreshError(lastMenuBarError ?? "本地服务还没有启动完成", silent: silentForStore)
            if let busyKey {
                store.setBusy(busyKey, active: false)
            }
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            do {
                let summaryBox = RequestResultBox<ManagerSummary>()
                let supportBox = RequestResultBox<SupportSummary>()
                let machineBox = RequestResultBox<MachineSummary>()
                let profileConfigBox = RequestResultBox<OpenClawProfileConfigDocument>()
                let skillsSummaryBox = RequestResultBox<OpenClawSkillsSummary>()
                let skillsConfigBox = RequestResultBox<OpenClawSkillsConfigSummary>()
                let skillsMarketBox = RequestResultBox<OpenClawSkillsMarketSummary>()
                let skillsInventoryBox = RequestResultBox<OpenClawSkillsInventory>()
                let includeManager = scope != .monitorOnly && scope != .supportOnly && scope != .settingsOnly && scope != .skillsOnly
                let includeSupport = scope == .full || scope == .supportOnly
                let includeMachine = scope == .full || scope == .monitorOnly
                let includeSettings = scope == .settingsOnly || scope == .skillsOnly
                let includeSkills = scope == .skillsOnly
                let supportPath = !silentForStore ? "/api/support/summary?fresh=1" : "/api/support/summary"
                let skillsPath = !silentForStore ? "/api/openclaw/skills?fresh=1" : "/api/openclaw/skills"
                let skillsMarketPath = !silentForStore ? "/api/openclaw/skills/market?fresh=1" : "/api/openclaw/skills/market"
                let skillsInventoryPath = !silentForStore ? "/api/openclaw/skills/inventory?fresh=1" : "/api/openclaw/skills/inventory"
                let group = DispatchGroup()

                if includeManager {
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        defer { group.leave() }
                        guard let self else { return }
                        do {
                            let summary: ManagerSummary = try self.performManagerRequest(path: "/api/openclaw/manager")
                            summaryBox.value = .success(summary)
                        } catch {
                            summaryBox.value = .failure(error)
                        }
                    }
                }

                if includeSupport {
                    group.enter()
                    DispatchQueue.global(qos: .utility).async { [weak self] in
                        defer { group.leave() }
                        guard let self else { return }
                        do {
                            let supportSummary: SupportSummary = try self.performManagerRequest(path: supportPath)
                            supportBox.value = .success(supportSummary)
                        } catch {
                            supportBox.value = .failure(error)
                        }
                    }
                }

                if includeMachine {
                    group.enter()
                    DispatchQueue.global(qos: .utility).async { [weak self] in
                        defer { group.leave() }
                        guard let self else { return }
                        do {
                            let machineSummary: MachineSummary = try self.performManagerRequest(path: "/api/machine/summary")
                            machineBox.value = .success(machineSummary)
                        } catch {
                            machineBox.value = .failure(error)
                        }
                    }
                }

                if includeSettings {
                    let focusProfileName = scope == .settingsOnly ? self.store.configFocusProfileName : nil

                    if let focusProfileName {
                        group.enter()
                        DispatchQueue.global(qos: .utility).async { [weak self] in
                            defer { group.leave() }
                            guard let self else { return }
                            let encoded = focusProfileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? focusProfileName
                            do {
                                let document: OpenClawProfileConfigDocument = try self.performManagerRequest(
                                    path: "/api/openclaw/profiles/\(encoded)/config/document"
                                )
                                profileConfigBox.value = .success(document)
                            } catch {
                                profileConfigBox.value = .failure(error)
                            }
                        }
                    }

                    group.enter()
                    DispatchQueue.global(qos: .utility).async { [weak self] in
                        defer { group.leave() }
                        guard let self else { return }
                        do {
                            let skillsSummary: OpenClawSkillsSummary = try self.performManagerRequest(path: skillsPath)
                            skillsSummaryBox.value = .success(skillsSummary)
                        } catch {
                            skillsSummaryBox.value = .failure(error)
                        }
                    }

                    group.enter()
                    DispatchQueue.global(qos: .utility).async { [weak self] in
                        defer { group.leave() }
                        guard let self else { return }
                        do {
                            let skillsConfig: OpenClawSkillsConfigSummary = try self.performManagerRequest(path: "/api/openclaw/skills/config")
                            skillsConfigBox.value = .success(skillsConfig)
                        } catch {
                            skillsConfigBox.value = .failure(error)
                        }
                    }

                    if includeSkills {
                        group.enter()
                        DispatchQueue.global(qos: .utility).async { [weak self] in
                            defer { group.leave() }
                            guard let self else { return }
                            do {
                                let marketSummary: OpenClawSkillsMarketSummary = try self.performManagerRequest(path: skillsMarketPath)
                                skillsMarketBox.value = .success(marketSummary)
                            } catch {
                                skillsMarketBox.value = .failure(error)
                            }
                        }

                        group.enter()
                        DispatchQueue.global(qos: .utility).async { [weak self] in
                            defer { group.leave() }
                            guard let self else { return }
                            do {
                                let inventory: OpenClawSkillsInventory = try self.performManagerRequest(path: skillsInventoryPath)
                                skillsInventoryBox.value = .success(inventory)
                            } catch {
                                skillsInventoryBox.value = .failure(error)
                            }
                        }
                    }
                }

                group.wait()

                if !includeManager {
                    if includeSkills {
                        guard let skillsSummaryResult = skillsSummaryBox.value else {
                            throw NSError(domain: self.appName, code: 30, userInfo: [NSLocalizedDescriptionKey: "本地 skills 摘要为空"])
                        }
                        guard let skillsConfigResult = skillsConfigBox.value else {
                            throw NSError(domain: self.appName, code: 31, userInfo: [NSLocalizedDescriptionKey: "本地 skills 配置摘要为空"])
                        }
                        guard let marketResult = skillsMarketBox.value else {
                            throw NSError(domain: self.appName, code: 32, userInfo: [NSLocalizedDescriptionKey: "技能市场摘要为空"])
                        }
                        guard let inventoryResult = skillsInventoryBox.value else {
                            throw NSError(domain: self.appName, code: 33, userInfo: [NSLocalizedDescriptionKey: "已安装技能库存为空"])
                        }

                        let skillsSummary = try skillsSummaryResult.get()
                        let skillsConfig = try skillsConfigResult.get()
                        let marketSummary = try marketResult.get()
                        let inventory = try inventoryResult.get()
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.applySkillsRefreshedState(
                                skillsSummary: skillsSummary,
                                skillsConfig: skillsConfig,
                                marketSummary: marketSummary,
                                inventory: inventory
                            )
                            if let busyKey {
                                self.store.setBusy(busyKey, active: false)
                            }
                        }
                        return
                    }

                    if includeSettings {
                        guard let skillsSummaryResult = skillsSummaryBox.value else {
                            throw NSError(domain: self.appName, code: 28, userInfo: [NSLocalizedDescriptionKey: "本地 skills 摘要为空"])
                        }
                        guard let skillsConfigResult = skillsConfigBox.value else {
                            throw NSError(domain: self.appName, code: 29, userInfo: [NSLocalizedDescriptionKey: "本地 skills 配置摘要为空"])
                        }

                        let skillsSummary = try skillsSummaryResult.get()
                        let skillsConfig = try skillsConfigResult.get()
                        let profileConfigDocument = try? profileConfigBox.value?.get()
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.applySettingsRefreshedState(
                                profileConfigDocument: profileConfigDocument,
                                skillsSummary: skillsSummary,
                                skillsConfig: skillsConfig
                            )
                            if let busyKey {
                                self.store.setBusy(busyKey, active: false)
                            }
                        }
                        return
                    }

                    if includeMachine {
                        guard let machineResult = machineBox.value else {
                            throw NSError(domain: self.appName, code: 26, userInfo: [NSLocalizedDescriptionKey: "本地机器监控摘要为空"])
                        }

                        let machineSummary = try machineResult.get()
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.applyMachineRefreshedState(machineSummary)
                            if let busyKey {
                                self.store.setBusy(busyKey, active: false)
                            }
                        }
                        return
                    }

                    guard let supportResult = supportBox.value else {
                        throw NSError(domain: self.appName, code: 27, userInfo: [NSLocalizedDescriptionKey: "本地诊断摘要为空"])
                    }

                    let supportSummary = try supportResult.get()
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.applySupportRefreshedState(supportSummary)
                        if let busyKey {
                            self.store.setBusy(busyKey, active: false)
                        }
                    }
                    return
                }

                guard let summaryResult = summaryBox.value else {
                    throw NSError(domain: self.appName, code: 25, userInfo: [NSLocalizedDescriptionKey: "本地 manager 摘要为空"])
                }

                let summary = try summaryResult.get()
                let supportSummary = includeSupport ? (try? supportBox.value?.get()) : self.latestSupportSummary
                let machineSummary = includeMachine ? (try? machineBox.value?.get()) : self.latestMachineSummary
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.applyRefreshedState(summary: summary, supportSummary: supportSummary, machineSummary: machineSummary)
                    if let busyKey {
                        self.store.setBusy(busyKey, active: false)
                    }
                }
            } catch {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.lastMenuBarError = error.localizedDescription
                    if scope == .monitorOnly {
                        self.latestMachineSummary = nil
                        self.store.applyRefreshError(error.localizedDescription, silent: silentForStore)
                        if let busyKey {
                            self.store.setBusy(busyKey, active: false)
                        }
                        if showErrorAlerts {
                            self.showError(error)
                        }
                        return
                    }
                    if scope == .supportOnly {
                        self.store.applyRefreshError(error.localizedDescription, silent: silentForStore)
                        if let busyKey {
                            self.store.setBusy(busyKey, active: false)
                        }
                        if showErrorAlerts {
                            self.showError(error)
                        }
                        return
                    }
                    if scope == .settingsOnly {
                        self.latestOpenClawProfileConfigDocument = nil
                        self.latestOpenClawSkillsSummary = nil
                        self.latestOpenClawSkillsConfig = nil
                        self.store.applyRefreshError(error.localizedDescription, silent: silentForStore)
                        if let busyKey {
                            self.store.setBusy(busyKey, active: false)
                        }
                        if showErrorAlerts {
                            self.showError(error)
                        }
                        return
                    }
                    if scope == .skillsOnly {
                        self.latestOpenClawSkillsSummary = nil
                        self.latestOpenClawSkillsConfig = nil
                        self.latestSkillsMarketSummary = nil
                        self.latestSkillsInventory = nil
                        self.store.applyRefreshError(error.localizedDescription, silent: silentForStore)
                        if let busyKey {
                            self.store.setBusy(busyKey, active: false)
                        }
                        if showErrorAlerts {
                            self.showError(error)
                        }
                        return
                    }
                    self.latestManagerSummary = nil
                    self.latestSupportSummary = nil
                    self.latestMachineSummary = nil
                    self.latestOpenClawProfileConfigDocument = nil
                    self.latestOpenClawSkillsSummary = nil
                    self.latestOpenClawSkillsConfig = nil
                    self.latestSkillsMarketSummary = nil
                    self.latestSkillsInventory = nil
                    self.pushLocalSnapshotToStore()
                    self.rebuildStatusItemMenu()
                    self.rebuildMenu()
                    self.store.applyRefreshError(error.localizedDescription, silent: silentForStore)
                    if let busyKey {
                        self.store.setBusy(busyKey, active: false)
                    }
                    if showErrorAlerts {
                        self.showError(error)
                    }
                }
            }
        }
    }

    private func performManagerRequest<T: Decodable & Sendable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        timeout: TimeInterval = 8
    ) throws -> T {
        guard let currentApiPort else {
            throw NSError(domain: appName, code: 20, userInfo: [NSLocalizedDescriptionKey: "本地 API 端口不可用"])
        }

        let url = URL(string: "http://127.0.0.1:\(currentApiPort)\(path)")!
        let semaphore = DispatchSemaphore(value: 0)
        let output = RequestResultBox<T>()
        let appName = self.appName

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error {
                output.value = .failure(error)
                return
            }

            guard let http = response as? HTTPURLResponse else {
                output.value = .failure(NSError(domain: appName, code: 21, userInfo: [NSLocalizedDescriptionKey: "本地 API 没有返回有效响应"]))
                return
            }

            guard (200..<300).contains(http.statusCode) else {
                let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(http.statusCode)"
                output.value = .failure(NSError(domain: appName, code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message]))
                return
            }

            guard let data else {
                output.value = .failure(NSError(domain: appName, code: 22, userInfo: [NSLocalizedDescriptionKey: "本地 API 返回了空响应"]))
                return
            }

            do {
                output.value = .success(try JSONDecoder().decode(T.self, from: data))
            } catch {
                output.value = .failure(error)
            }
        }.resume()

        if semaphore.wait(timeout: .now() + timeout + 2) == .timedOut {
            throw NSError(domain: appName, code: 23, userInfo: [NSLocalizedDescriptionKey: "本地 API 请求超时"])
        }

        guard let output = output.value else {
            throw NSError(domain: appName, code: 24, userInfo: [NSLocalizedDescriptionKey: "本地 API 请求失败"])
        }

        return try output.get()
    }

    @MainActor
    private func performBackgroundUIRequest<T: Sendable>(
        key: String? = nil,
        errorTitle: String = "操作失败",
        request: @escaping @Sendable () throws -> T,
        onSuccess: @escaping @MainActor @Sendable (T) -> Void
    ) {
        if let key {
            store.setBusy(key, active: true)
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            do {
                let result = try request()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let key {
                        self.store.setBusy(key, active: false)
                    }
                    onSuccess(result)
                }
            } catch {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let key {
                        self.store.setBusy(key, active: false)
                    }
                    self.store.showNotice(.error, title: errorTitle, detail: error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    private func createProfile(_ profileName: String) {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        performBackgroundUIRequest(key: "create", errorTitle: "创建 profile 失败", request: {
            let body = try JSONSerialization.data(withJSONObject: ["profileName": trimmed])
            return try self.performManagerRequest(path: "/api/openclaw/profiles", method: "POST", body: body) as ManagedProfileSnapshot
        }, onSuccess: { _ in
            self.store.showNotice(.success, title: "已创建 \(trimmed)")
            self.store.selectProfile(trimmed)
            self.refreshManagerData(scope: .managerOnly, silentForStore: true)
        })
    }

    @MainActor
    private func loginProfile(_ profileName: String) {
        performBackgroundUIRequest(key: "login:\(profileName)", errorTitle: "启动登录流程失败", request: {
            try self.performManagerRequest(path: "/api/openclaw/profiles/\(profileName)/login", method: "POST") as LoginFlowSnapshot
        }, onSuccess: { flow in
            self.store.applyLoginFlow(flow)
            let detail = flow.browserOpened ? "浏览器已自动打开" : "浏览器未自动打开，可在原生界面里手动打开登录页"
            self.store.showNotice(.success, title: "已开始 \(profileName) 的登录流程", detail: detail)
            self.store.selectedSection = .profiles
            self.showMainWindow(nil)
        })
    }

    @MainActor
    private func pollLoginFlow(_ flowId: String) {
        performBackgroundUIRequest(errorTitle: "读取登录流程失败", request: {
            try self.performManagerRequest(path: "/api/openclaw/login-flows/\(flowId)") as LoginFlowSnapshot
        }, onSuccess: { flow in
            self.store.applyLoginFlow(flow)
        })
    }

    @MainActor
    private func probeProfile(_ profileName: String) {
        performBackgroundUIRequest(key: "probe:\(profileName)", errorTitle: "账号探测失败", request: {
            try self.performManagerRequest(path: "/api/openclaw/profiles/\(profileName)/probe", method: "POST") as ManagedProfileSnapshot
        }, onSuccess: { _ in
            self.store.showNotice(.success, title: "\(profileName) 探测完成")
            self.refreshManagerData(scope: .managerOnly, silentForStore: true)
        })
    }

    @MainActor
    private func activateProfile(_ profileName: String) {
        performBackgroundUIRequest(key: "activate:\(profileName)", errorTitle: "切换账号失败", request: {
            try self.performManagerRequest(path: "/api/openclaw/profiles/\(profileName)/activate", method: "POST") as ManagerSummary
        }, onSuccess: { summary in
            self.applyRefreshedState(summary: summary, supportSummary: self.latestSupportSummary, machineSummary: self.latestMachineSummary)
            self.store.showNotice(.success, title: "已切换到 \(profileName)")
        })
    }

    @MainActor
    private func activateRecommended() {
        performBackgroundUIRequest(key: "activate:recommended", errorTitle: "切换推荐账号失败", request: {
            try self.performManagerRequest(path: "/api/openclaw/activate-recommended", method: "POST") as ManagerSummary
        }, onSuccess: { summary in
            self.applyRefreshedState(summary: summary, supportSummary: self.latestSupportSummary, machineSummary: self.latestMachineSummary)
            self.store.showNotice(.success, title: "已切换到推荐账号")
        })
    }

    @MainActor
    private func validateProfileConfig(_ profileName: String) {
        performBackgroundUIRequest(
            key: "profile-config:validate:\(profileName)",
            errorTitle: "配置校验失败",
            request: {
                try self.performManagerRequest(
                    path: "/api/openclaw/profiles/\(profileName)/config/validate",
                    method: "POST"
                ) as OpenClawProfileConfigValidationResult
            },
            onSuccess: { result in
                self.store.applyProfileConfigValidation(result)
                self.refreshManagerData(scope: .settingsOnly, silentForStore: true)
                if result.valid {
                    self.store.showNotice(.success, title: "\(profileName) 配置校验通过", detail: result.detail)
                } else {
                    self.store.showNotice(.error, title: "\(profileName) 配置未通过校验", detail: result.detail)
                }
            }
        )
    }

    @MainActor
    private func previewProfileConfig(_ profileName: String, request: OpenClawProfileConfigEditRequest) {
        performBackgroundUIRequest(
            key: "profile-config:preview:\(profileName)",
            errorTitle: "预览配置失败",
            request: {
                let body = try JSONEncoder().encode(request)
                return try self.performManagerRequest(
                    path: "/api/openclaw/profiles/\(profileName)/config/preview",
                    method: "POST",
                    body: body
                ) as OpenClawProfileConfigPreviewResult
            },
            onSuccess: { result in
                self.store.selectedSection = .profiles
                self.store.applyProfileConfigPreview(result)
                self.store.showNotice(.success, title: "已生成变更预览", detail: result.message)
            }
        )
    }

    @MainActor
    private func applyProfileConfig(_ profileName: String, request: OpenClawProfileConfigEditRequest) {
        performBackgroundUIRequest(
            key: "profile-config:apply:\(profileName)",
            errorTitle: "应用配置失败",
            request: {
                let body = try JSONEncoder().encode(request)
                return try self.performManagerRequest(
                    path: "/api/openclaw/profiles/\(profileName)/config/apply",
                    method: "POST",
                    body: body
                ) as OpenClawProfileConfigApplyResult
            },
            onSuccess: { result in
                self.store.selectedSection = .profiles
                self.store.applyProfileConfigValidation(result.validation)
                self.store.clearProfileConfigPreview()
                self.store.showNotice(.success, title: "配置已应用", detail: result.message)
                self.refreshManagerData(scope: .managerOnly, silentForStore: true)
                self.refreshManagerData(scope: .settingsOnly, silentForStore: false)
            }
        )
    }

    @MainActor
    private func saveAutomation(_ patch: AutomationSettingsPatch) {
        performBackgroundUIRequest(key: "automation:save", errorTitle: "保存自动切换设置失败", request: {
            let body = try JSONEncoder().encode(patch)
            return try self.performManagerRequest(path: "/api/openclaw/settings", method: "PATCH", body: body) as ManagerSummary
        }, onSuccess: { summary in
            self.applyRefreshedState(summary: summary, supportSummary: self.latestSupportSummary, machineSummary: self.latestMachineSummary)
            self.store.showNotice(.success, title: "自动化设置已保存")
        })
    }

    @MainActor
    private func saveSkillsConfig(_ patch: OpenClawSkillsConfigPatch) {
        performBackgroundUIRequest(key: "skills:config:save", errorTitle: "保存 Skills 配置失败", request: {
            let body = try JSONEncoder().encode(patch)
            return try self.performManagerRequest(path: "/api/openclaw/skills/config", method: "PATCH", body: body) as OpenClawSkillsConfigMutationResult
        }, onSuccess: { result in
            self.store.selectedSection = .settings
            self.store.showNotice(.success, title: "Skills 配置已保存", detail: result.message)
            self.refreshManagerData(scope: .settingsOnly, silentForStore: false)
        })
    }

    @MainActor
    private func runAutomationTick() {
        performBackgroundUIRequest(key: "automation:tick", errorTitle: "执行自动探测失败", request: {
            try self.performManagerRequest(path: "/api/openclaw/automation/tick", method: "POST") as AutomationTickResult
        }, onSuccess: { result in
            self.applyRefreshedState(summary: result.summary, supportSummary: self.latestSupportSummary, machineSummary: self.latestMachineSummary)
            if result.switched {
                self.store.showNotice(.success, title: "自动切换 \(result.fromProfileName ?? "none") -> \(result.toProfileName ?? "none")")
            } else {
                self.store.showNotice(.info, title: "本轮未切换", detail: result.reason)
            }
        })
    }

    @MainActor
    private func runSupportRepair(_ action: SupportRepairAction) {
        performBackgroundUIRequest(
            key: "support:\(action.rawValue)",
            errorTitle: "执行诊断修复失败",
            request: {
                let body = try JSONEncoder().encode(["action": action.rawValue])
                return try self.performManagerRequest(path: "/api/support/repair", method: "POST", body: body) as SupportRepairResult
            },
            onSuccess: { result in
                self.latestSupportSummary = result.summary
                self.store.applySupportRepairResult(result)
                if let summary = self.latestManagerSummary {
                    self.applyRefreshedState(summary: summary, supportSummary: result.summary, machineSummary: self.latestMachineSummary)
                } else {
                    self.pushLocalSnapshotToStore()
                    self.rebuildStatusItemMenu()
                    self.rebuildMenu()
                }

                self.store.selectedSection = .diagnostics
                self.showMainWindow(nil)
                let detail = result.output?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? result.output
                    : result.message
                self.store.showNotice(.success, title: "诊断操作已执行", detail: detail)
            }
        )
    }

    @MainActor
    private func loadSkillMarketDetail(_ slug: String) {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        performBackgroundUIRequest(key: "skill:detail:\(trimmed)", errorTitle: "读取技能详情失败", request: {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
            return try self.performManagerRequest(path: "/api/openclaw/skills/market/\(encoded)") as OpenClawSkillMarketDetail
        }, onSuccess: { detail in
            self.store.applySkillMarketDetail(detail)
        })
    }

    @MainActor
    private func installSkill(_ slug: String) {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        performBackgroundUIRequest(key: "skill:install:\(trimmed)", errorTitle: "安装技能失败", request: {
            let body = try JSONEncoder().encode(["slug": trimmed])
            return try self.performManagerRequest(
                path: "/api/openclaw/skills/install",
                method: "POST",
                body: body,
                timeout: 95
            ) as OpenClawSkillMutationResult
        }, onSuccess: { result in
            self.store.selectedSection = .skills
            self.store.showNotice(.success, title: "技能已安装", detail: result.message)
            self.refreshManagerData(scope: .skillsOnly, silentForStore: false)
        })
    }

    @MainActor
    private func uninstallSkill(_ slug: String) {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        performBackgroundUIRequest(key: "skill:uninstall:\(trimmed)", errorTitle: "卸载技能失败", request: {
            let body = try JSONEncoder().encode(["slug": trimmed])
            return try self.performManagerRequest(path: "/api/openclaw/skills/uninstall", method: "POST", body: body) as OpenClawSkillMutationResult
        }, onSuccess: { result in
            self.store.selectedSection = .skills
            self.store.showNotice(.success, title: "技能已卸载", detail: result.message)
            self.refreshManagerData(scope: .skillsOnly, silentForStore: false)
        })
    }

    @MainActor
    private func setSkillEnabled(_ slug: String, enabled: Bool, bundled: Bool) {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let action = enabled ? "enable" : "disable"
        let title = enabled ? "启用技能失败" : "停用技能失败"
        performBackgroundUIRequest(key: "skill:\(action):\(trimmed)", errorTitle: title, request: {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
            let body = try JSONEncoder().encode(["bundled": bundled])
            return try self.performManagerRequest(
                path: "/api/openclaw/skills/\(encoded)/\(action)",
                method: "POST",
                body: body
            ) as OpenClawSkillMutationResult
        }, onSuccess: { result in
            self.store.selectedSection = .skills
            self.store.showNotice(.success, title: enabled ? "技能已更新" : "技能已停用", detail: result.message)
            self.refreshManagerData(scope: .skillsOnly, silentForStore: false)
        })
    }

    @MainActor
    private func selectSkillsExtraDir() {
        let initialPath = store.openClawSkillsConfig?.extraDirs.last ?? currentConfig.openclawHomeDir
        selectDirectory(title: "选择要挂载的 Skills 目录", initialPath: initialPath) { [weak self] path in
            self?.addSkillsExtraDir(path)
        }
    }

    @MainActor
    private func addSkillsExtraDir(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        performBackgroundUIRequest(key: "skills:add-extra-dir", errorTitle: "新增挂载目录失败", request: {
            let body = try JSONEncoder().encode(OpenClawSkillsConfigPatch(
                addExtraDir: trimmed,
                removeExtraDir: nil,
                watch: nil,
                watchDebounceMs: nil,
                installPreferBrew: nil,
                clearInstallPreferBrew: nil,
                installNodeManager: nil,
                clearInstallNodeManager: nil
            ))
            return try self.performManagerRequest(
                path: "/api/openclaw/skills/config",
                method: "PATCH",
                body: body
            ) as OpenClawSkillsConfigMutationResult
        }, onSuccess: { result in
            self.store.selectedSection = .settings
            self.store.showNotice(.success, title: "挂载目录已加入", detail: result.message)
            self.refreshManagerData(scope: .settingsOnly, silentForStore: false)
        })
    }

    @MainActor
    private func removeSkillsExtraDir(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        performBackgroundUIRequest(key: "skills:remove-extra-dir:\(trimmed)", errorTitle: "移除挂载目录失败", request: {
            let body = try JSONEncoder().encode(OpenClawSkillsConfigPatch(
                addExtraDir: nil,
                removeExtraDir: trimmed,
                watch: nil,
                watchDebounceMs: nil,
                installPreferBrew: nil,
                clearInstallPreferBrew: nil,
                installNodeManager: nil,
                clearInstallNodeManager: nil
            ))
            return try self.performManagerRequest(
                path: "/api/openclaw/skills/config",
                method: "PATCH",
                body: body
            ) as OpenClawSkillsConfigMutationResult
        }, onSuccess: { result in
            self.store.selectedSection = .settings
            self.store.showNotice(.success, title: "挂载目录已移除", detail: result.message)
            self.refreshManagerData(scope: .settingsOnly, silentForStore: false)
        })
    }

    @MainActor
    @objc private func refreshMenuBarNow(_ sender: Any?) {
        refreshManagerData(showErrorAlerts: true, silentForStore: false)
    }

    @MainActor
    @objc private func activateRecommendedFromMenuBar(_ sender: Any?) {
        performBackgroundUIRequest(errorTitle: "切换推荐账号失败", request: {
            try self.performManagerRequest(path: "/api/openclaw/activate-recommended", method: "POST") as ManagerSummary
        }, onSuccess: { summary in
            self.applyRefreshedState(summary: summary, supportSummary: self.latestSupportSummary, machineSummary: self.latestMachineSummary)
            self.store.showNotice(.success, title: "已切换到推荐账号")
        })
    }

    @MainActor
    @objc private func activateProfileFromMenuBar(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let profileName = item.representedObject as? String, !profileName.isEmpty else {
            return
        }

        performBackgroundUIRequest(errorTitle: "切换账号失败", request: {
            try self.performManagerRequest(path: "/api/openclaw/profiles/\(profileName)/activate", method: "POST") as ManagerSummary
        }, onSuccess: { summary in
            self.applyRefreshedState(summary: summary, supportSummary: self.latestSupportSummary, machineSummary: self.latestMachineSummary)
            self.store.showNotice(.success, title: "已切换到 \(profileName)")
        })
    }

    @MainActor
    @objc private func toggleAutomationFromMenuBar(_ sender: Any?) {
        let nextEnabled = !(latestManagerSummary?.automation.enabled ?? false)

        performBackgroundUIRequest(errorTitle: "更新自动切换失败", request: {
            let body = try JSONSerialization.data(withJSONObject: ["autoActivateEnabled": nextEnabled])
            return try self.performManagerRequest(path: "/api/openclaw/settings", method: "PATCH", body: body) as ManagerSummary
        }, onSuccess: { summary in
            self.applyRefreshedState(summary: summary, supportSummary: self.latestSupportSummary, machineSummary: self.latestMachineSummary)
            self.store.showNotice(.success, title: nextEnabled ? "已开启自动切换" : "已关闭自动切换")
        })
    }

    @MainActor
    @objc private func runAutomationTickFromMenuBar(_ sender: Any?) {
        performBackgroundUIRequest(errorTitle: "执行自动探测失败", request: {
            try self.performManagerRequest(path: "/api/openclaw/automation/tick", method: "POST") as AutomationTickResult
        }, onSuccess: { result in
            self.applyRefreshedState(summary: result.summary, supportSummary: self.latestSupportSummary, machineSummary: self.latestMachineSummary)
            self.store.showNotice(.info, title: result.switched ? "本轮已完成切换" : "本轮未切换", detail: result.reason)
        })
    }

    @MainActor
    private func rebuildMenu() {
        requireMainThread()
        let watchdog = collectWatchdogSummary()
        let menu = NSMenu()

        let appItem = NSMenuItem()
        menu.addItem(appItem)

        let appMenu = NSMenu(title: appName)
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "查看当前配置", action: #selector(showCurrentConfig(_:)), keyEquivalent: "i").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp

        let configItem = NSMenuItem()
        menu.addItem(configItem)

        let configMenu = NSMenu(title: "配置")
        configItem.submenu = configMenu
        let openclawInfo = NSMenuItem(title: "OpenClaw 根目录: \(shortPath(currentConfig.openclawHomeDir))", action: nil, keyEquivalent: "")
        openclawInfo.isEnabled = false
        configMenu.addItem(openclawInfo)
        configMenu.addItem(withTitle: "选择 OpenClaw 根目录...", action: #selector(selectOpenClawRoot(_:)), keyEquivalent: "o").target = self
        configMenu.addItem(withTitle: "重置 OpenClaw 根目录为当前用户 Home", action: #selector(resetOpenClawRoot(_:)), keyEquivalent: "").target = self
        configMenu.addItem(.separator())
        let codexInfo = NSMenuItem(title: "可选 Codex 根目录: \(shortPath(currentConfig.codexHomeDir))", action: nil, keyEquivalent: "")
        codexInfo.isEnabled = false
        configMenu.addItem(codexInfo)
        configMenu.addItem(withTitle: "选择 Codex 根目录...", action: #selector(selectCodexRoot(_:)), keyEquivalent: "c").target = self
        configMenu.addItem(withTitle: "重置 Codex 根目录为当前用户 Home", action: #selector(resetCodexRoot(_:)), keyEquivalent: "").target = self
        configMenu.addItem(.separator())
        configMenu.addItem(withTitle: "打开设置文件", action: #selector(openSettingsFile(_:)), keyEquivalent: "").target = self
        configMenu.addItem(withTitle: "打开应用数据目录", action: #selector(openAppSupportDirectory(_:)), keyEquivalent: "").target = self
        configMenu.addItem(withTitle: "打开 Manager 状态目录", action: #selector(openManagerStateDirectory(_:)), keyEquivalent: "").target = self
        configMenu.addItem(.separator())
        configMenu.addItem(withTitle: "重启服务并刷新窗口", action: #selector(restartServices(_:)), keyEquivalent: "r").target = self

        let watchdogItem = NSMenuItem()
        menu.addItem(watchdogItem)

        let watchdogMenu = NSMenu(title: "稳定守护")
        watchdogItem.submenu = watchdogMenu
        let watchdogInfo = NSMenuItem(title: "状态: \(watchdog.statusLine)", action: nil, keyEquivalent: "")
        watchdogInfo.isEnabled = false
        watchdogMenu.addItem(watchdogInfo)
        if let monitoredStateDir = watchdog.monitoredStateDir {
            let monitoredInfo = NSMenuItem(title: "监控目录: \(shortPath(monitoredStateDir))", action: nil, keyEquivalent: "")
            monitoredInfo.isEnabled = false
            watchdogMenu.addItem(monitoredInfo)
        }
        watchdogMenu.addItem(.separator())
        let enableTitle = watchdog.installed ? "按当前目录重新启用稳定守护" : "启用稳定守护"
        watchdogMenu.addItem(withTitle: enableTitle, action: #selector(enableWatchdog(_:)), keyEquivalent: "").target = self
        let disableItem = watchdogMenu.addItem(withTitle: "停用稳定守护", action: #selector(disableWatchdog(_:)), keyEquivalent: "")
        disableItem.target = self
        disableItem.isEnabled = watchdog.installed
        watchdogMenu.addItem(withTitle: "查看守护状态", action: #selector(showWatchdogStatus(_:)), keyEquivalent: "").target = self
        watchdogMenu.addItem(withTitle: "立即巡检并恢复", action: #selector(runWatchdogCheckNow(_:)), keyEquivalent: "").target = self
        watchdogMenu.addItem(withTitle: "打开守护日志", action: #selector(openWatchdogLog(_:)), keyEquivalent: "").target = self
        watchdogMenu.addItem(withTitle: "打开守护状态目录", action: #selector(openWatchdogStateDirectory(_:)), keyEquivalent: "").target = self

        let supportItem = NSMenuItem()
        menu.addItem(supportItem)

        let supportMenu = NSMenu(title: "诊断与修复")
        supportItem.submenu = supportMenu
        let supportStatus = latestSupportSummary?.discord.status ?? "unknown"
        let supportStatusTitle: String
        switch supportStatus {
        case "healthy":
            supportStatusTitle = "Discord 状态: 正常"
        case "unstable":
            supportStatusTitle = "Discord 状态: 不稳定"
        case "offline":
            supportStatusTitle = "Discord 状态: 离线"
        default:
            supportStatusTitle = "Discord 状态: 读取中"
        }
        let supportStatusItem = NSMenuItem(title: supportStatusTitle, action: nil, keyEquivalent: "")
        supportStatusItem.isEnabled = false
        supportMenu.addItem(supportStatusItem)
        let gatewayStatusTitle = latestSupportSummary?.gateway.reachable == true
            ? "OpenClaw 服务: 可达"
            : "OpenClaw 服务: 不可达"
        let gatewayStatusItem = NSMenuItem(title: gatewayStatusTitle, action: nil, keyEquivalent: "")
        gatewayStatusItem.isEnabled = false
        supportMenu.addItem(gatewayStatusItem)
        supportMenu.addItem(.separator())
        supportMenu.addItem(withTitle: "打开诊断中心", action: #selector(openSupportCenter(_:)), keyEquivalent: "d").target = self
        supportMenu.addItem(withTitle: "一键修复", action: #selector(runOneClickRepair(_:)), keyEquivalent: "").target = self
        supportMenu.addItem(withTitle: "重启 OpenClaw 服务", action: #selector(restartGatewayFromSupport(_:)), keyEquivalent: "").target = self
        supportMenu.addItem(withTitle: "打开 Gateway 日志", action: #selector(openGatewayLog(_:)), keyEquivalent: "").target = self
        supportMenu.addItem(withTitle: "打开守护日志", action: #selector(openWatchdogLog(_:)), keyEquivalent: "").target = self

        let windowItem = NSMenuItem()
        menu.addItem(windowItem)

        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "显示主窗口", action: #selector(showMainWindow(_:)), keyEquivalent: "1").target = self
        windowMenu.addItem(withTitle: "刷新状态", action: #selector(refreshMenuBarNow(_:)), keyEquivalent: "l").target = self

        NSApp.mainMenu = menu
        rebuildStatusItemMenu()
    }

    private func shortPath(_ raw: String) -> String {
        if raw.count <= 56 {
            return raw
        }
        return "...\(raw.suffix(53))"
    }

    @MainActor
    @objc private func showCurrentConfig(_ sender: Any?) {
        let watchdog = collectWatchdogSummary()
        var details: [String] = []
        details.append("OpenClaw 根目录: \(currentConfig.openclawHomeDir)")
        details.append("可选 Codex 根目录: \(currentConfig.codexHomeDir)")
        details.append("稳定守护: \(watchdog.statusLine)")
        details.append("期望监控目录: \(expectedWatchdogStateDirPath())")
        if let monitoredStateDir = watchdog.monitoredStateDir {
            details.append("实际监控目录: \(monitoredStateDir)")
        }
        if let lastLoopResult = watchdog.state?.lastLoopResult {
            details.append("守护最近结果: \(lastLoopResult)")
        }
        if let restartCount = watchdog.state?.restartCount {
            details.append("守护累计恢复: \(restartCount) 次")
        }
        if let lastRestartReason = watchdog.state?.lastRestartReason {
            details.append("守护最近恢复原因: \(lastRestartReason)")
        }
        if let lastRestartAt = formatUnixMilliseconds(watchdog.state?.lastRestartAtMs) {
            details.append("守护最近恢复时间: \(lastRestartAt)")
        }
        if let settingsURL {
            details.append("设置文件: \(settingsURL.path)")
        }
        if let runtimeRootURL {
            details.append("Runtime 目录: \(runtimeRootURL.path)")
        }
        if let stateURL = watchdogStateFileURL() {
            details.append("守护状态文件: \(stateURL.path)")
        }
        details.append("守护日志文件: \(watchdogLogURL(using: watchdog.monitoredStateDir).path)")
        if let currentApiPort {
            details.append("本地 API: http://127.0.0.1:\(currentApiPort)/api")
        }
        if let currentCallbackPort {
            details.append("回调地址: http://localhost:\(currentCallbackPort)/auth/callback")
        }
        showInfo(message: "当前配置", detail: details.joined(separator: "\n"))
    }

    @MainActor
    @objc private func selectOpenClawRoot(_ sender: Any?) {
        selectDirectory(title: "选择 OpenClaw 根目录", initialPath: currentConfig.openclawHomeDir) { [weak self] path in
            self?.updateConfig(target: .openclaw, value: path, reason: "选择 OpenClaw 根目录")
        }
    }

    @MainActor
    @objc private func resetOpenClawRoot(_ sender: Any?) {
        updateConfig(target: .openclaw, value: NSHomeDirectory(), reason: "reset-openclaw")
    }

    @MainActor
    @objc private func selectCodexRoot(_ sender: Any?) {
        selectDirectory(title: "选择可选 Codex 根目录", initialPath: currentConfig.codexHomeDir) { [weak self] path in
            self?.updateConfig(target: .codex, value: path, reason: "选择可选 Codex 根目录")
        }
    }

    @MainActor
    @objc private func resetCodexRoot(_ sender: Any?) {
        updateConfig(target: .codex, value: NSHomeDirectory(), reason: "reset-codex")
    }

    @MainActor
    @objc private func openSettingsFile(_ sender: Any?) {
        guard let settingsURL else { return }
        NSWorkspace.shared.open(settingsURL)
    }

    @MainActor
    @objc private func openAppSupportDirectory(_ sender: Any?) {
        guard let appSupportURL else { return }
        NSWorkspace.shared.open(appSupportURL)
    }

    @MainActor
    @objc private func openManagerStateDirectory(_ sender: Any?) {
        guard let appSupportURL else { return }
        NSWorkspace.shared.open(appSupportURL.appendingPathComponent("manager-state", isDirectory: true))
    }

    @MainActor
    private func openActivityMonitor() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.open(appURL)
            return
        }

        let fallbackURL = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        if FileManager.default.fileExists(atPath: fallbackURL.path) {
            NSWorkspace.shared.open(fallbackURL)
            return
        }

        store.showNotice(.error, title: "找不到活动监视器", detail: "系统没有返回 Activity Monitor 的应用路径。")
    }

    @MainActor
    @objc private func restartServices(_ sender: Any?) {
        do {
            try restartRuntime(reason: "manual")
            refreshStartupData(showErrorAlerts: true, silentForStore: false)
            store.showNotice(.success, title: "服务已重启")
        } catch {
            showError(error)
        }
    }

    @MainActor
    @objc private func openSupportCenter(_ sender: Any?) {
        store.selectedSection = .diagnostics
        showMainWindow(nil)
    }

    @MainActor
    @objc private func showMainWindow(_ sender: Any?) {
        presentMainWindow()
    }

    @MainActor
    @objc private func runOneClickRepair(_ sender: Any?) {
        runSupportRepair(.runWatchdogCheck)
    }

    @MainActor
    @objc private func restartGatewayFromSupport(_ sender: Any?) {
        runSupportRepair(.restartGateway)
    }

    @MainActor
    @objc private func enableWatchdog(_ sender: Any?) {
        do {
            let scriptURL = try bundledScriptURL(named: "install-watchdog.sh")
            let result = try runCommand(
                executableURL: URL(fileURLWithPath: "/bin/bash"),
                arguments: [scriptURL.path],
                environment: try watchdogScriptEnvironment()
            )
            try requireSuccess(result, context: "启用稳定守护失败")
            pushLocalSnapshotToStore()
            rebuildMenu()
            store.showNotice(.success, title: "稳定守护已启用", detail: commandDetail(result, fallback: "watchdog 已按当前 OpenClaw 根目录部署。"))
        } catch {
            showError(error)
        }
    }

    @MainActor
    @objc private func disableWatchdog(_ sender: Any?) {
        do {
            let scriptURL = try bundledScriptURL(named: "uninstall-watchdog.sh")
            let result = try runCommand(
                executableURL: URL(fileURLWithPath: "/bin/bash"),
                arguments: [scriptURL.path]
            )
            try requireSuccess(result, context: "停用稳定守护失败")
            pushLocalSnapshotToStore()
            rebuildMenu()
            store.showNotice(.success, title: "稳定守护已停用", detail: commandDetail(result, fallback: "watchdog 已停用。"))
        } catch {
            showError(error)
        }
    }

    @MainActor
    @objc private func showWatchdogStatus(_ sender: Any?) {
        let watchdog = collectWatchdogSummary()
        var details: [String] = []
        details.append("状态: \(watchdog.statusLine)")
        details.append("当前 OpenClaw 根目录: \(currentConfig.openclawHomeDir)")
        details.append("期望监控目录: \(expectedWatchdogStateDirPath())")
        if let monitoredStateDir = watchdog.monitoredStateDir {
            details.append("实际监控目录: \(monitoredStateDir)")
        }
        if let lastLoopResult = watchdog.state?.lastLoopResult {
            details.append("最近巡检结果: \(lastLoopResult)")
        }
        if let restartCount = watchdog.state?.restartCount {
            details.append("累计自动恢复: \(restartCount) 次")
        }
        if let lastRestartReason = watchdog.state?.lastRestartReason {
            details.append("最近恢复原因: \(lastRestartReason)")
        }
        if let lastRestartAt = formatUnixMilliseconds(watchdog.state?.lastRestartAtMs) {
            details.append("最近恢复时间: \(lastRestartAt)")
        }
        if let lastHealthyAt = watchdog.state?.lastHealthyAt {
            details.append("最近健康时间: \(lastHealthyAt)")
        }
        if let stateURL = watchdogStateFileURL() {
            details.append("状态文件: \(stateURL.path)")
        }
        details.append("日志文件: \(watchdogLogURL(using: watchdog.monitoredStateDir).path)")
        if !watchdog.installed {
            details.append("尚未启用，可从“稳定守护 -> 启用稳定守护”完成安装。")
        } else if !watchdog.configuredForCurrentRoot {
            details.append("watchdog 监控目录不一致，重新执行“启用稳定守护”即可。")
        }
        showInfo(message: "稳定守护状态", detail: details.joined(separator: "\n"))
    }

    @MainActor
    @objc private func runWatchdogCheckNow(_ sender: Any?) {
        do {
            let result = try runCommand(
                executableURL: try bundledRuntimeExecutableURL(named: "openclaw-watchdog"),
                arguments: ["--once"],
                environment: try watchdogScriptEnvironment()
            )
            try requireSuccess(result, context: "执行守护巡检失败")
            pushLocalSnapshotToStore()
            rebuildMenu()
            store.showNotice(.success, title: "稳定守护已完成巡检", detail: commandDetail(result, fallback: "巡检已完成，如果 gateway 掉线会自动尝试恢复。"))
        } catch {
            showError(error)
        }
    }

    @MainActor
    @objc private func openWatchdogLog(_ sender: Any?) {
        let watchdog = collectWatchdogSummary()
        let logURL = watchdogLogURL(using: watchdog.monitoredStateDir)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: logURL.path) {
            NSWorkspace.shared.open(logURL)
            return
        }

        let directoryURL = logURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directoryURL.path) {
            NSWorkspace.shared.open(directoryURL)
            return
        }

        showInfo(message: "守护日志不存在", detail: "当前还没有生成守护日志：\n\(logURL.path)")
    }

    @MainActor
    @objc private func openGatewayLog(_ sender: Any?) {
        let logURL = gatewayLogURL()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: logURL.path) {
            NSWorkspace.shared.open(logURL)
            return
        }

        let directoryURL = logURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directoryURL.path) {
            NSWorkspace.shared.open(directoryURL)
            return
        }

        showInfo(message: "Gateway 日志不存在", detail: "当前还没有生成 gateway 日志：\n\(logURL.path)")
    }

    @MainActor
    @objc private func openWatchdogStateDirectory(_ sender: Any?) {
        guard let supportURL = watchdogSupportDirectoryURL() else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: supportURL.path) {
            NSWorkspace.shared.open(supportURL)
            return
        }
        showInfo(message: "守护状态目录不存在", detail: "当前还没有生成守护状态目录：\n\(supportURL.path)")
    }

    @MainActor
    private func selectDirectory(title: String, initialPath: String, onPick: @escaping @MainActor (String) -> Void) {
        requireMainThread()
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: (initialPath as NSString).expandingTildeInPath)

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        onPick(url.path)
    }

    @MainActor
    private func updateConfig(target: RuntimeRootTarget, value: String, reason: String) {
        do {
            var next = currentConfig
            switch target {
            case .openclaw:
                next.openclawHomeDir = value
            case .codex:
                next.codexHomeDir = value
            }
            try persistSettings(next)
            try restartRuntime(reason: reason)
            refreshStartupData(showErrorAlerts: true, silentForStore: false)
            store.showNotice(.success, title: "本地目录已更新")
        } catch {
            showError(error)
        }
    }

    private func expectedWatchdogStateDirPath() -> String {
        URL(fileURLWithPath: currentConfig.openclawHomeDir, isDirectory: true)
            .appendingPathComponent(".openclaw", isDirectory: true)
            .path
    }

    private func openclawStateDirectoryURL() -> URL {
        URL(fileURLWithPath: expectedWatchdogStateDirPath(), isDirectory: true)
    }

    private func watchdogPlistURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/LaunchAgents/ai.openclaw.watchdog.plist")
    }

    private func watchdogStateFileURL() -> URL? {
        appSupportURL?.appendingPathComponent("watchdog/state.json")
    }

    private func watchdogSupportDirectoryURL() -> URL? {
        appSupportURL?.appendingPathComponent("watchdog", isDirectory: true)
    }

    private func watchdogLogURL(using monitoredStateDir: String? = nil) -> URL {
        let stateDir = monitoredStateDir ?? expectedWatchdogStateDirPath()
        return URL(fileURLWithPath: stateDir, isDirectory: true)
            .appendingPathComponent("logs/watchdog.log")
    }

    private func gatewayLogURL() -> URL {
        openclawStateDirectoryURL()
            .appendingPathComponent("logs/gateway.log")
    }

    private func loadWatchdogLaunchEnvironment() -> [String: String] {
        let plistURL = watchdogPlistURL()
        guard FileManager.default.fileExists(atPath: plistURL.path),
              let data = try? Data(contentsOf: plistURL),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let plist = object as? [String: Any],
              let environment = plist["EnvironmentVariables"] as? [String: Any]
        else {
            return [:]
        }

        var result: [String: String] = [:]
        for (key, value) in environment {
            if let string = value as? String {
                result[key] = string
            }
        }
        return result
    }

    private func loadWatchdogState() -> WatchdogState? {
        guard let stateURL = watchdogStateFileURL(),
              let data = try? Data(contentsOf: stateURL) else {
            return nil
        }
        return try? JSONDecoder().decode(WatchdogState.self, from: data)
    }

    private func collectWatchdogSummary() -> WatchdogSummary {
        let installed = FileManager.default.fileExists(atPath: watchdogPlistURL().path)
        let monitoredStateDir = loadWatchdogLaunchEnvironment()["OPENCLAW_STATE_DIR"]
        return WatchdogSummary(
            installed: installed,
            configuredForCurrentRoot: monitoredStateDir == expectedWatchdogStateDirPath(),
            monitoredStateDir: monitoredStateDir,
            state: loadWatchdogState()
        )
    }

    private func bundledScriptURL(named name: String) throws -> URL {
        guard let resourceURL = Bundle.main.resourceURL else {
            throw NSError(domain: appName, code: 7, userInfo: [NSLocalizedDescriptionKey: "未找到 app 资源目录"])
        }
        let scriptURL = resourceURL.appendingPathComponent("scripts/\(name)")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw NSError(domain: appName, code: 8, userInfo: [NSLocalizedDescriptionKey: "缺少资源脚本: \(name)"])
        }
        return scriptURL
    }

    private func bundledRuntimeExecutableURL(named name: String) throws -> URL {
        guard let resourceURL = Bundle.main.resourceURL else {
            throw NSError(domain: appName, code: 9, userInfo: [NSLocalizedDescriptionKey: "未找到 app 资源目录"])
        }
        let executableURL = resourceURL.appendingPathComponent("runtime/\(name)")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw NSError(domain: appName, code: 10, userInfo: [NSLocalizedDescriptionKey: "缺少内置运行时: \(name)"])
        }
        return executableURL
    }

    private func watchdogScriptEnvironment() throws -> [String: String] {
        [
            "OPENCLAW_WATCHDOG_OPENCLAW_ROOT": currentConfig.openclawHomeDir,
            "OPENCLAW_STATE_DIR": expectedWatchdogStateDirPath()
        ]
    }

    private func runCommand(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:],
        currentDirectoryURL: URL? = nil
    ) throws -> ShellCommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let currentDirectoryURL {
            process.currentDirectoryURL = currentDirectoryURL
        }

        var env = ProcessInfo.processInfo.environment
        environment.forEach { env[$0.key] = $0.value }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let outputGroup = DispatchGroup()
        let outputQueue = DispatchQueue.global(qos: .utility)
        let stdoutBox = RequestResultBox<Data>()
        let stderrBox = RequestResultBox<Data>()

        outputGroup.enter()
        outputQueue.async {
            stdoutBox.value = .success(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            outputGroup.leave()
        }

        outputGroup.enter()
        outputQueue.async {
            stderrBox.value = .success(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            outputGroup.leave()
        }

        try process.run()
        process.waitUntilExit()
        outputGroup.wait()

        let stdoutData = (try? stdoutBox.value?.get()) ?? Data()
        let stderrData = (try? stderrBox.value?.get()) ?? Data()

        return ShellCommandResult(
            status: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    private func commandDetail(_ result: ShellCommandResult, fallback: String) -> String {
        var sections: [String] = []
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdout.isEmpty {
            sections.append(stdout)
        }
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            sections.append(stderr)
        }
        if sections.isEmpty {
            sections.append(fallback)
        }
        return sections.joined(separator: "\n\n")
    }

    private func requireSuccess(_ result: ShellCommandResult, context: String) throws {
        guard result.status == 0 else {
            throw NSError(
                domain: appName,
                code: 11,
                userInfo: [
                    NSLocalizedDescriptionKey: "\(context)\n\n\(commandDetail(result, fallback: "无更多输出"))"
                ]
            )
        }
    }

    private func formatUnixMilliseconds(_ milliseconds: Int?) -> String? {
        guard let milliseconds else {
            return nil
        }
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        return ISO8601DateFormatter().string(from: date)
    }

    @MainActor
    private func ensureWindow() {
        requireMainThread()
        if window != nil {
            return
        }

        let hostingController = NSHostingController(rootView: NativeRootView(store: store).preferredColorScheme(.dark))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 920),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = appName
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unifiedCompact
        window.minSize = NSSize(width: 1120, height: 760)
        window.center()
        window.delegate = self
        window.contentViewController = hostingController
        window.makeKeyAndOrderFront(nil)

        self.window = window
    }

    @MainActor
    private func presentMainWindow() {
        requireMainThread()
        ensureWindow()
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func restartRuntime(reason: String) throws {
        guard let runtimeRootURL else {
            throw NSError(domain: appName, code: 4, userInfo: [NSLocalizedDescriptionKey: "Runtime 目录不可用"])
        }

        isRestarting = true
        defer { isRestarting = false }

        appendLifecycleLog("restart runtime begin reason=\(reason)")
        terminateProcesses()
        appendLifecycleLog("restart runtime after terminate tracked processes")
        terminateStaleBundledBackends()
        appendLifecycleLog("restart runtime after terminate stale bundled backends")

        let apiPort = try findFreePort(preferred: apiPreferredPort)
        let callbackPort = try findFreePort(preferred: callbackPreferredPort)
        appendLifecycleLog("restart runtime reserved ports api=\(apiPort) callback=\(callbackPort)")

        let daemonURL = runtimeRootURL.appendingPathComponent("openclaw-manager-daemon")
        let stateURL = appSupportURL!.appendingPathComponent("manager-state", isDirectory: true)

        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)
        appendLifecycleLog("restart runtime prepared state directory path=\(stateURL.path)")

        var environment: [String: String] = [
            "OPENCLAW_MANAGER_RUNTIME_MODE": "native",
            "HOST": "127.0.0.1",
            "PORT": String(apiPort),
            "HOME": NSHomeDirectory(),
            "PATH": daemonLaunchPATH(),
            "OPENCLAW_HOME_DIR": currentConfig.openclawHomeDir,
            "OPENCLAW_CODEX_HOME_DIR": currentConfig.codexHomeDir,
            "OPENCLAW_MANAGER_DIR": stateURL.path,
            "OPENCLAW_OAUTH_CALLBACK_PORT": String(callbackPort),
            "OPENCLAW_OAUTH_CALLBACK_BIND_HOST": "127.0.0.1",
            "OPENCLAW_OAUTH_CALLBACK_PUBLIC_HOST": "localhost",
            "OPENCLAW_AUTH_OPEN_MODE": "auto"
        ]
        if let openclawBin = preferredOpenClawBin() {
            environment["OPENCLAW_BIN"] = openclawBin
        }

        appendLifecycleLog("restart runtime launching daemon path=\(daemonURL.path)")
        backendProcess = try launchProcess(
            executableURL: daemonURL,
            arguments: [],
            environment: environment,
            currentDirectoryURL: stateURL,
            logPrefix: "manager-api"
        )
        appendLifecycleLog("restart runtime launched daemon pid=\(backendProcess?.processIdentifier ?? 0)")

        appendLifecycleLog("restart runtime waiting for health api=\(apiPort)")
        try waitUntilReachable(url: URL(string: "http://127.0.0.1:\(apiPort)/api/health")!, expectedStatus: 200, timeout: 30)

        currentApiPort = apiPort
        currentCallbackPort = callbackPort
        pushLocalSnapshotToStore()
        rebuildMenu()

        appendLifecycleLog("runtime ready reason=\(reason) api=\(apiPort) callback=\(callbackPort)")
        print("[native] runtime ready (\(reason)) api=\(apiPort) callback=\(callbackPort)")
    }

    private func preferredOpenClawBin() -> String? {
        let explicit = ProcessInfo.processInfo.environment["OPENCLAW_BIN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit, !explicit.isEmpty, FileManager.default.isExecutableFile(atPath: explicit) {
            return explicit
        }

        let local = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("openclaw")

        if FileManager.default.isExecutableFile(atPath: local.path) {
            return local.path
        }

        return nil
    }

    private func daemonLaunchPATH() -> String {
        let preferred = [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin", isDirectory: true).path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let existing = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        var merged: [String] = []
        var seen = Set<String>()
        for entry in preferred + existing {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                merged.append(trimmed)
            }
        }
        return merged.joined(separator: ":")
    }

    private func launchProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL,
        logPrefix: String
    ) throws -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        var env = ProcessInfo.processInfo.environment
        environment.forEach { env[$0.key] = $0.value }
        process.environment = env

        let stdout = Pipe()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            FileHandle.standardOutput.write(Data("[\(logPrefix)] \(text)".utf8))
        }
        process.standardOutput = stdout

        let stderr = Pipe()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            FileHandle.standardError.write(Data("[\(logPrefix)] \(text)".utf8))
        }
        process.standardError = stderr

        process.terminationHandler = { terminated in
            let code = terminated.terminationStatus
            let reason = terminated.terminationReason == .exit ? "exit" : "uncaught signal"
            FileHandle.standardError.write(Data("[\(logPrefix)] terminated status=\(code) reason=\(reason)\n".utf8))
            self.appendLifecycleLog("\(logPrefix) terminated status=\(code) reason=\(reason)")
        }

        try process.run()
        return process
    }

    @MainActor
    private func terminateProcesses() {
        stopProcess(&backendProcess)
        currentApiPort = nil
        currentCallbackPort = nil
        pushLocalSnapshotToStore()
    }

    private func stopProcess(_ process: inout Process?) {
        guard let runningProcess = process else { return }
        runningProcess.terminationHandler = nil
        if runningProcess.isRunning {
            runningProcess.terminate()
            let timeout = Date().addingTimeInterval(5)
            while runningProcess.isRunning && Date() < timeout {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if runningProcess.isRunning {
                kill(runningProcess.processIdentifier, SIGKILL)
            }
        }
        process = nil
    }

    private func terminateStaleBundledBackends() {
        let stalePIDs = discoverStaleBundledBackendPIDs()
        guard !stalePIDs.isEmpty else { return }
        appendLifecycleLog("terminating stale bundled backends count=\(stalePIDs.count)")
        for pid in stalePIDs {
            terminateExternalProcess(pid)
        }
    }

    private func discoverStaleBundledBackendPIDs() -> [pid_t] {
        let psURL = URL(fileURLWithPath: "/bin/ps")
        guard let result = try? runCommand(executableURL: psURL, arguments: ["-axo", "pid=,command="]),
              result.status == 0 else {
            return []
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let trackedBackendPID = backendProcess?.processIdentifier
        let bundledRuntimeMarker = "OpenClaw Manager Native.app/Contents/Resources/runtime/"
        var matches: [pid_t] = []

        for line in result.stdout.split(whereSeparator: \.isNewline) {
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let parts = text.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2, let pidValue = Int32(parts[0]) else { continue }
            guard pidValue != currentPID, pidValue != trackedBackendPID else { continue }

            let command = String(parts[1])
            guard command.contains(bundledRuntimeMarker) else { continue }

            let isBundledDaemon = command.contains("/openclaw-manager-daemon")
            let isLegacyNodeAPI = command.contains("/node_modules/node/bin/node") && command.contains("/apps/api/dist/server.js")
            guard isBundledDaemon || isLegacyNodeAPI else { continue }

            matches.append(pidValue)
        }

        return matches
    }

    private func terminateExternalProcess(_ pid: pid_t) {
        guard pid > 0 else { return }
        if kill(pid, SIGTERM) != 0 && errno == ESRCH {
            return
        }

        let deadline = Date().addingTimeInterval(3)
        while processExists(pid), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        if processExists(pid) {
            _ = kill(pid, SIGKILL)
        }
    }

    private func processExists(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private func waitUntilReachable(url: URL, expectedStatus: Int, timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let status = httpStatus(for: url), status == expectedStatus {
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        throw NSError(
            domain: appName,
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "服务健康检查超时: \(url.absoluteString)"]
        )
    }

    private func httpStatus(for url: URL) -> Int? {
        let semaphore = DispatchSemaphore(value: 0)
        let result = StatusCodeBox()
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                result.value = http.statusCode
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 2)
        return result.value
    }

    private func findFreePort(preferred: UInt16) throws -> UInt16 {
        if canBind(port: preferred) {
            return preferred
        }
        return try bindEphemeralPort()
    }

    private func canBind(port: UInt16) -> Bool {
        socketPort(port: port) != nil
    }

    private func bindEphemeralPort() throws -> UInt16 {
        if let port = socketPort(port: 0) {
            return port
        }
        throw NSError(domain: appName, code: 6, userInfo: [NSLocalizedDescriptionKey: "无法分配本地端口"])
    }

    private func socketPort(port: UInt16) -> UInt16? {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        if socketFD < 0 {
            return nil
        }
        defer { close(socketFD) }

        var value: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        address.sin_port = CFSwapInt16HostToBig(port)

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                Darwin.bind(socketFD, pointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if bindResult != 0 {
            return nil
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        var boundAddress = sockaddr_in()
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                getsockname(socketFD, pointer, &length)
            }
        }

        if nameResult != 0 {
            return nil
        }

        return CFSwapInt16BigToHost(boundAddress.sin_port)
    }

    @MainActor
    private func showInfo(message: String, detail: String) {
        requireMainThread()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }

    @MainActor
    private func showError(_ error: Error) {
        showInfo(message: "操作失败", detail: error.localizedDescription)
    }

    @MainActor
    private func showFatalError(_ error: Error) {
        requireMainThread()
        appendLifecycleLog("fatal error: \(error.localizedDescription)")
        showInfo(message: "桌面版启动失败", detail: error.localizedDescription)
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppController()
app.delegate = delegate
app.run()
