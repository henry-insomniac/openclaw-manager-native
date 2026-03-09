import AppKit
import Darwin
import Foundation
import WebKit

struct RuntimeConfig: Codable {
    var openclawHomeDir: String
    var codexHomeDir: String

    static func `default`() -> RuntimeConfig {
        RuntimeConfig(
            openclawHomeDir: NSHomeDirectory(),
            codexHomeDir: NSHomeDirectory()
        )
    }
}

final class AppController: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private let appName = "OpenClaw Manager Native"
    private let uiPreferredPort: UInt16 = 3101
    private let apiPreferredPort: UInt16 = 3311
    private let callbackPreferredPort: UInt16 = 1455

    private var window: NSWindow?
    private var webView: WKWebView?
    private var backendProcess: Process?
    private var uiProcess: Process?
    private var runtimeRootURL: URL?
    private var settingsURL: URL?
    private var appSupportURL: URL?
    private var currentConfig = RuntimeConfig.default()
    private var currentUiPort: UInt16?
    private var currentCallbackPort: UInt16?
    private var isRestarting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        do {
            try initializeEnvironment()
            rebuildMenu()
            try restartRuntime(reason: "startup")
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            showFatalError(error)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        terminateProcesses()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            ensureWindow()
        }
        window?.makeKeyAndOrderFront(nil)
        return true
    }

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

    private func persistSettings(_ config: RuntimeConfig) throws {
        guard let settingsURL else {
            throw NSError(domain: appName, code: 2, userInfo: [NSLocalizedDescriptionKey: "settings.json 路径不可用"])
        }
        let data = try JSONEncoder().encode(config)
        try data.write(to: settingsURL, options: .atomic)
        currentConfig = config
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

    private func rebuildMenu() {
        let menu = NSMenu()

        let appItem = NSMenuItem()
        menu.addItem(appItem)

        let appMenu = NSMenu(title: appName)
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "查看当前配置", action: #selector(showCurrentConfig(_:)), keyEquivalent: "i").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

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
        let codexInfo = NSMenuItem(title: "Codex 根目录: \(shortPath(currentConfig.codexHomeDir))", action: nil, keyEquivalent: "")
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

        let windowItem = NSMenuItem()
        menu.addItem(windowItem)

        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "显示主窗口", action: #selector(showMainWindow(_:)), keyEquivalent: "1").target = self
        windowMenu.addItem(withTitle: "刷新页面", action: #selector(reloadWebView(_:)), keyEquivalent: "l").target = self

        NSApp.mainMenu = menu
    }

    private func shortPath(_ raw: String) -> String {
        if raw.count <= 56 {
            return raw
        }
        return "...\(raw.suffix(53))"
    }

    @objc private func showCurrentConfig(_ sender: Any?) {
        var details: [String] = []
        details.append("OpenClaw 根目录: \(currentConfig.openclawHomeDir)")
        details.append("Codex 根目录: \(currentConfig.codexHomeDir)")
        if let settingsURL {
            details.append("设置文件: \(settingsURL.path)")
        }
        if let runtimeRootURL {
            details.append("Runtime 目录: \(runtimeRootURL.path)")
        }
        if let currentUiPort {
            details.append("界面地址: http://127.0.0.1:\(currentUiPort)")
        }
        if let currentCallbackPort {
            details.append("OAuth 回调: http://localhost:\(currentCallbackPort)/auth/callback")
        }
        showInfo(message: "当前配置", detail: details.joined(separator: "\n"))
    }

    @objc private func selectOpenClawRoot(_ sender: Any?) {
        selectDirectory(title: "选择 OpenClaw 根目录", keyPath: \RuntimeConfig.openclawHomeDir)
    }

    @objc private func resetOpenClawRoot(_ sender: Any?) {
        updateConfig(keyPath: \RuntimeConfig.openclawHomeDir, value: NSHomeDirectory(), reason: "reset-openclaw")
    }

    @objc private func selectCodexRoot(_ sender: Any?) {
        selectDirectory(title: "选择 Codex 根目录", keyPath: \RuntimeConfig.codexHomeDir)
    }

    @objc private func resetCodexRoot(_ sender: Any?) {
        updateConfig(keyPath: \RuntimeConfig.codexHomeDir, value: NSHomeDirectory(), reason: "reset-codex")
    }

    @objc private func openSettingsFile(_ sender: Any?) {
        guard let settingsURL else { return }
        NSWorkspace.shared.open(settingsURL)
    }

    @objc private func openAppSupportDirectory(_ sender: Any?) {
        guard let appSupportURL else { return }
        NSWorkspace.shared.open(appSupportURL)
    }

    @objc private func openManagerStateDirectory(_ sender: Any?) {
        guard let appSupportURL else { return }
        NSWorkspace.shared.open(appSupportURL.appendingPathComponent("manager-state", isDirectory: true))
    }

    @objc private func restartServices(_ sender: Any?) {
        do {
            try restartRuntime(reason: "manual")
        } catch {
            showError(error)
        }
    }

    @objc private func showMainWindow(_ sender: Any?) {
        ensureWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func reloadWebView(_ sender: Any?) {
        webView?.reload()
    }

    private func selectDirectory(title: String, keyPath: WritableKeyPath<RuntimeConfig, String>) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: currentConfig[keyPath: keyPath])

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        updateConfig(keyPath: keyPath, value: url.path, reason: title)
    }

    private func updateConfig(keyPath: WritableKeyPath<RuntimeConfig, String>, value: String, reason: String) {
        do {
            var next = currentConfig
            next[keyPath: keyPath] = value
            try persistSettings(next)
            try restartRuntime(reason: reason)
        } catch {
            showError(error)
        }
    }

    private func ensureWindow() {
        if window != nil {
            return
        }

        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 960),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = appName
        window.minSize = NSSize(width: 1200, height: 820)
        window.center()
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)

        self.window = window
        self.webView = webView
    }

    private func restartRuntime(reason: String) throws {
        guard let runtimeRootURL else {
            throw NSError(domain: appName, code: 4, userInfo: [NSLocalizedDescriptionKey: "Runtime 目录不可用"])
        }

        isRestarting = true
        defer { isRestarting = false }

        terminateProcesses()

        let apiPort = try findFreePort(preferred: apiPreferredPort)
        let callbackPort = try findFreePort(preferred: callbackPreferredPort)
        let uiPort = try findFreePort(preferred: uiPreferredPort)

        let nodeURL = runtimeRootURL.appendingPathComponent("node_modules/node/bin/node")
        let backendScriptURL = runtimeRootURL.appendingPathComponent("apps/api/dist/server.js")
        let uiScriptURL = runtimeRootURL.appendingPathComponent("ui-server.mjs")
        let webRootURL = runtimeRootURL.appendingPathComponent("apps/web/dist", isDirectory: true)
        let stateURL = appSupportURL!.appendingPathComponent("manager-state", isDirectory: true)

        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)

        backendProcess = try launchProcess(
            executableURL: nodeURL,
            arguments: [backendScriptURL.path],
            environment: [
                "NODE_ENV": "production",
                "HOST": "127.0.0.1",
                "PORT": String(apiPort),
                "OPENCLAW_HOME_DIR": currentConfig.openclawHomeDir,
                "OPENCLAW_CODEX_HOME_DIR": currentConfig.codexHomeDir,
                "OPENCLAW_MANAGER_DIR": stateURL.path,
                "OPENCLAW_OAUTH_CALLBACK_PORT": String(callbackPort),
                "OPENCLAW_OAUTH_CALLBACK_BIND_HOST": "127.0.0.1",
                "OPENCLAW_OAUTH_CALLBACK_PUBLIC_HOST": "localhost",
                "OPENCLAW_AUTH_OPEN_MODE": "auto"
            ],
            currentDirectoryURL: runtimeRootURL,
            logPrefix: "manager-api"
        )

        try waitUntilReachable(url: URL(string: "http://127.0.0.1:\(apiPort)/api/health")!, expectedStatus: 200, timeout: 30)

        uiProcess = try launchProcess(
            executableURL: nodeURL,
            arguments: [uiScriptURL.path],
            environment: [
                "NATIVE_MANAGER_API_PORT": String(apiPort),
                "NATIVE_MANAGER_UI_PORT": String(uiPort),
                "NATIVE_MANAGER_WEB_ROOT": webRootURL.path
            ],
            currentDirectoryURL: runtimeRootURL,
            logPrefix: "manager-ui"
        )

        try waitUntilReachable(url: URL(string: "http://127.0.0.1:\(uiPort)/__native_ui_health")!, expectedStatus: 200, timeout: 15)

        currentUiPort = uiPort
        currentCallbackPort = callbackPort
        rebuildMenu()
        ensureWindow()
        webView?.load(URLRequest(url: URL(string: "http://127.0.0.1:\(uiPort)")!))

        print("[native] runtime ready (\(reason)) ui=\(uiPort) callback=\(callbackPort)")
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

        process.terminationHandler = { [weak self] terminated in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.isRestarting {
                    return
                }
                let code = terminated.terminationStatus
                let reason = terminated.terminationReason == .exit ? "exit" : "uncaught signal"
                self.showInfo(message: "本地服务已退出", detail: "\(logPrefix) 退出，状态: \(code) (\(reason))")
            }
        }

        try process.run()
        return process
    }

    private func terminateProcesses() {
        stopProcess(&uiProcess)
        stopProcess(&backendProcess)
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
        var result: Int?
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                result = http.statusCode
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 2)
        return result
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

    private func showInfo(message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }

    private func showError(_ error: Error) {
        showInfo(message: "操作失败", detail: error.localizedDescription)
    }

    private func showFatalError(_ error: Error) {
        showInfo(message: "桌面版启动失败", detail: error.localizedDescription)
        NSApp.terminate(nil)
    }

    @MainActor
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if url.host == "127.0.0.1", url.port == Int(currentUiPort ?? 0) {
            decisionHandler(.allow)
            return
        }

        if ["http", "https"].contains(url.scheme?.lowercased()) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}

@main
struct OpenClawManagerNativeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppController()
        app.delegate = delegate
        app.run()
    }
}
