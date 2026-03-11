import SwiftUI

private struct SectionDescriptor: Identifiable {
    var section: NativeSection
    var title: String
    var caption: String
    var symbol: String

    var id: NativeSection { section }
}

private struct StatusPresentation {
    var label: String
    var tint: Color
}

private enum NativePalette {
    static let accent = Color(red: 0.29, green: 0.52, blue: 0.98)
    static let mint = Color(red: 0.20, green: 0.76, blue: 0.63)
    static let amber = Color(red: 0.96, green: 0.69, blue: 0.24)
    static let rose = Color(red: 0.95, green: 0.40, blue: 0.46)
    static let ink = Color(red: 0.93, green: 0.95, blue: 0.98)
    static let sidebarTop = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let sidebarBottom = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let canvasTop = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let canvasBottom = Color(red: 0.05, green: 0.06, blue: 0.08)
    static let surface = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let surfaceRaised = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let surfaceAlt = Color(red: 0.15, green: 0.17, blue: 0.21)
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.14)
}

private struct SectionNarrative {
    var eyebrow: String
    var title: String
    var detail: String
}

private let autoSwitchStatusOptions: [ProfileStatus] = [
    .draining,
    .cooldown,
    .exhausted,
    .reauthRequired,
    .unknown
]

private func statusPresentation(for status: ProfileStatus) -> StatusPresentation {
    switch status {
    case .healthy:
        return StatusPresentation(label: "可用", tint: .green)
    case .draining:
        return StatusPresentation(label: "预警", tint: .orange)
    case .cooldown:
        return StatusPresentation(label: "冷却", tint: .yellow)
    case .exhausted:
        return StatusPresentation(label: "耗尽", tint: .red)
    case .reauthRequired:
        return StatusPresentation(label: "需重登", tint: .red)
    case .unknown:
        return StatusPresentation(label: "未知", tint: .secondary)
    }
}

private func supportStatusPresentation(_ status: String) -> StatusPresentation {
    switch status {
    case "healthy":
        return StatusPresentation(label: "正常", tint: .green)
    case "unstable":
        return StatusPresentation(label: "不稳定", tint: .orange)
    case "offline":
        return StatusPresentation(label: "离线", tint: .red)
    default:
        return StatusPresentation(label: "读取中", tint: .secondary)
    }
}

private func riskPresentation(_ risk: String) -> StatusPresentation {
    switch risk {
    case "none":
        return StatusPresentation(label: "正常", tint: .green)
    case "watch":
        return StatusPresentation(label: "观察", tint: .orange)
    case "high":
        return StatusPresentation(label: "高风险", tint: .red)
    default:
        return StatusPresentation(label: "未知", tint: .secondary)
    }
}

private func runtimeModeLabel(_ mode: RuntimeMode?) -> String {
    switch mode {
    case .native:
        return "mac 原生"
    case .desktop:
        return "桌面壳"
    case .docker:
        return "Docker"
    case .web, .none:
        return "Web / Server"
    }
}

private func activationTriggerLabel(_ trigger: ActivationTrigger?) -> String {
    switch trigger {
    case .manual:
        return "手动"
    case .auto:
        return "自动"
    case .recommended:
        return "推荐切换"
    case .none:
        return "尚未触发"
    }
}

private func formatDate(_ raw: String?) -> String {
    guard let raw, let date = ISO8601DateFormatter().date(from: raw) else {
        return "未记录"
    }

    return date.formatted(
        Date.FormatStyle()
            .year(.defaultDigits)
            .month(.twoDigits)
            .day(.twoDigits)
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
    )
}

private func formatDuration(ms: Int?) -> String {
    guard let ms else { return "未提供" }
    if ms <= 0 { return "现在" }

    let totalMinutes = ms / 60_000
    let days = totalMinutes / (60 * 24)
    let hours = (totalMinutes % (60 * 24)) / 60
    let minutes = totalMinutes % 60

    if days > 0 {
        return "\(days)天 \(hours)小时"
    }
    if hours > 0 {
        return "\(hours)小时 \(minutes)分钟"
    }
    return "\(minutes)分钟"
}

private func formatMillis(_ value: Int?) -> String {
    guard let value else { return "未提供" }
    if value >= 1000 {
        return String(format: "%.2fs", Double(value) / 1000)
    }
    return "\(value)ms"
}

private func formatProbeWindow(minMs: Int?, maxMs: Int?) -> String {
    guard let minMs, let maxMs else { return "未配置" }
    let lower = max(30, minMs / 1000)
    let upper = max(lower, maxMs / 1000)
    if lower == upper {
        return "\(lower) 秒"
    }
    return "\(lower) - \(upper) 秒"
}

private func shortAccountId(_ value: String?) -> String {
    guard let value else { return "未绑定" }
    if value.count <= 12 { return value }
    return "\(value.prefix(6))...\(value.suffix(4))"
}

private func providerLabel(_ providerId: String?) -> String {
    guard let providerId, !providerId.isEmpty else { return "未配置" }
    switch providerId {
    case "openai-codex":
        return "Codex"
    case "openai":
        return "OpenAI"
    case "anthropic":
        return "Anthropic"
    case "openrouter":
        return "OpenRouter"
    case "ollama":
        return "Ollama"
    case "gemini", "google":
        return "Gemini"
    default:
        return providerId
    }
}

private func profileSupportsCodexLogin(_ profile: ManagedProfileSnapshot) -> Bool {
    if let providerId = profile.primaryProviderId, !providerId.isEmpty {
        return providerId == "openai-codex"
    }
    if profile.configuredProviderIds.contains("openai-codex") {
        return true
    }
    return profile.primaryModelId == nil
}

private func present(_ value: String?, fallback: String = "未提供") -> String {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return fallback
    }
    return value
}

private func sectionNarrative(for section: NativeSection) -> SectionNarrative {
    switch section {
    case .overview:
        return SectionNarrative(
            eyebrow: "OVERVIEW",
            title: "当前状态",
            detail: "看当前账号、推荐切换和守护状态。"
        )
    case .profiles:
        return SectionNarrative(
            eyebrow: "PROFILES",
            title: "查看和切换 profile",
            detail: "登录、探测和激活都放在这里。"
        )
    case .settings:
        return SectionNarrative(
            eyebrow: "SETTINGS",
            title: "目录和自动化",
            detail: "改根目录、探测窗口和切换阈值。"
        )
    case .diagnostics:
        return SectionNarrative(
            eyebrow: "DIAGNOSTICS",
            title: "排查问题",
            detail: "看状态、原因和修复动作。"
        )
    case .deployment:
        return SectionNarrative(
            eyebrow: "ACCESS",
            title: "命令和目录",
            detail: "这里只看命令和路径。"
        )
    }
}

private func readinessPresentation(runtime: RuntimeOverview?) -> StatusPresentation {
    guard let runtime else {
        return StatusPresentation(label: "连接中", tint: NativePalette.amber)
    }

    if runtime.switching.healthyProfiles >= 2 {
        return StatusPresentation(label: "已就绪", tint: NativePalette.mint)
    }
    if runtime.switching.healthyProfiles == 1 {
        return StatusPresentation(label: "单账号运行", tint: NativePalette.amber)
    }
    return StatusPresentation(label: "需处理", tint: NativePalette.rose)
}

private func diagnosticsPresentation(summary: SupportSummary?) -> StatusPresentation {
    guard let summary else {
        return StatusPresentation(label: "等待诊断", tint: NativePalette.amber)
    }

    if summary.discord.status == "offline" || summary.environment.riskLevel == "high" {
        return StatusPresentation(label: "高风险", tint: NativePalette.rose)
    }
    if summary.discord.status == "unstable" || summary.environment.riskLevel == "watch" {
        return StatusPresentation(label: "观察中", tint: NativePalette.amber)
    }
    return StatusPresentation(label: "稳定", tint: NativePalette.mint)
}

private func profileCapabilitySummary(_ profile: ManagedProfileSnapshot) -> String {
    let provider = providerLabel(profile.primaryProviderId)
    let quota = profile.supportsQuota ? "支持额度探测" : "不探测额度"
    return "主 provider: \(provider) · \(quota)"
}

private func profileFactItems(_ profile: ManagedProfileSnapshot) -> [(String, String)] {
    var items: [(String, String)] = [
        ("主 provider", providerLabel(profile.primaryProviderId)),
        ("主模型", present(profile.primaryModelId)),
        ("配置 provider", profile.configuredProviderIds.isEmpty ? "未提供" : profile.configuredProviderIds.joined(separator: " · ")),
        ("令牌剩余", formatDuration(ms: profile.tokenExpiresInMs)),
        ("账号 ID", shortAccountId(profile.accountId)),
        ("状态目录", profile.stateDir)
    ]

    if profile.supportsQuota {
        items.insert(("套餐", present(profile.quota.plan)), at: 3)
    }

    if profile.codexAccountId != nil || profile.hasCodexAuth {
        items.append(("Codex 账号", shortAccountId(profile.codexAccountId)))
        items.append(("最近刷新", formatDate(profile.codexLastRefreshAt)))
    }

    return items
}

private struct GatewayDiagnosis {
    var headline: String
    var detail: String
    var rawError: String?
    var prefersSettings: Bool
    var prefersRestartServices: Bool
}

private enum DiagnosticActionKind {
    case openSettings
    case restartServices
    case support(SupportRepairAction)
    case openGatewayLog
    case openWatchdogLog
}

private struct DiagnosticActionPlan {
    var title: String
    var systemImage: String
    var action: DiagnosticActionKind
    var prominent: Bool
}

private struct DiagnosticPlan {
    var headline: String
    var impact: String
    var detail: String
    var accent: Color
    var primary: DiagnosticActionPlan?
    var secondary: DiagnosticActionPlan?
    var tertiary: DiagnosticActionPlan?
}

private func gatewayDiagnosis(summary: SupportSummary?) -> GatewayDiagnosis {
    guard let summary else {
        return GatewayDiagnosis(
            headline: "等待网关诊断",
            detail: "daemon 还没返回网关状态。",
            rawError: nil,
            prefersSettings: false,
            prefersRestartServices: false
        )
    }

    if summary.gateway.reachable {
        return GatewayDiagnosis(
            headline: "Gateway 正常响应",
            detail: "OpenClaw gateway 已经可达，当前不需要额外修复动作。",
            rawError: nil,
            prefersSettings: false,
            prefersRestartServices: false
        )
    }

    let rawError = summary.gateway.error?.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = rawError?.lowercased() ?? ""

    if normalized.contains("enoent") && normalized.contains("openclaw") {
        return GatewayDiagnosis(
            headline: "未找到 OpenClaw CLI",
            detail: "原生 app 当前无法调用 OpenClaw 命令。先确认已安装，并保证环境包含 ~/.local/bin/openclaw。",
            rawError: rawError,
            prefersSettings: true,
            prefersRestartServices: true
        )
    }

    if normalized.contains("invalid json") {
        return GatewayDiagnosis(
            headline: "Gateway 返回异常输出",
            detail: "gateway 返回的状态不是有效 JSON。先重启服务，再看日志。",
            rawError: rawError,
            prefersSettings: false,
            prefersRestartServices: true
        )
    }

    if normalized.contains("timed out") || normalized.contains("econnrefused") || normalized.contains("connect") || normalized.contains("status failed") {
        return GatewayDiagnosis(
            headline: "Gateway 没有正常响应",
            detail: "gateway 当前没有正常响应。先重启 OpenClaw 服务。",
            rawError: rawError,
            prefersSettings: false,
            prefersRestartServices: true
        )
    }

    return GatewayDiagnosis(
        headline: "Gateway 当前不可达",
        detail: "当前拿不到稳定的网关响应。先重启 OpenClaw 服务，再看日志。",
        rawError: rawError,
        prefersSettings: false,
        prefersRestartServices: true
    )
}

private func primaryRecommendation(summary: SupportSummary?) -> String {
    guard let summary else {
        return "等待诊断数据。"
    }

    if summary.discord.status == "offline" {
        return summary.discord.recommendation
    }
    if summary.environment.riskLevel == "high" || summary.environment.riskLevel == "watch" {
        return summary.environment.recommendation
    }
    if !summary.gateway.reachable {
        return gatewayDiagnosis(summary: summary).detail
    }
    return "当前没有明显故障。保持自动切换和 watchdog 即可。"
}

private func diagnosticPlan(summary: SupportSummary?) -> DiagnosticPlan {
    guard let summary else {
        return DiagnosticPlan(
            headline: "等待诊断数据",
            impact: "daemon 还没返回完整诊断结果。",
            detail: "本地服务可能刚启动。",
            accent: NativePalette.amber,
            primary: nil,
            secondary: nil,
            tertiary: nil
        )
    }

    if !summary.gateway.reachable {
        let issue = gatewayDiagnosis(summary: summary)
        let primary: DiagnosticActionPlan? = issue.prefersSettings
            ? DiagnosticActionPlan(
                title: "检查安装",
                systemImage: "gearshape",
                action: .openSettings,
                prominent: true
            )
            : issue.prefersRestartServices
                ? DiagnosticActionPlan(
                    title: "重启服务",
                    systemImage: "arrow.clockwise",
                    action: .restartServices,
                    prominent: true
                )
                : DiagnosticActionPlan(
                    title: "一键修复",
                    systemImage: "wrench.and.screwdriver",
                    action: .support(.runWatchdogCheck),
                    prominent: true
                )

        let secondary: DiagnosticActionPlan? = issue.prefersSettings && issue.prefersRestartServices
            ? DiagnosticActionPlan(
                title: "重启服务",
                systemImage: "arrow.clockwise",
                action: .restartServices,
                prominent: false
            )
            : DiagnosticActionPlan(
                title: "打开网关日志",
                systemImage: "doc.text.magnifyingglass",
                action: .openGatewayLog,
                prominent: false
            )

        let tertiary: DiagnosticActionPlan? = issue.prefersSettings
            ? DiagnosticActionPlan(
                title: "打开网关日志",
                systemImage: "doc.text.magnifyingglass",
                action: .openGatewayLog,
                prominent: false
            )
            : nil

        return DiagnosticPlan(
            headline: issue.headline,
            impact: "OpenClaw gateway 当前不可用，额度探测、推荐切换和 Discord 连通性判断都会一起失真。",
            detail: issue.detail,
            accent: NativePalette.rose,
            primary: primary,
            secondary: secondary,
            tertiary: tertiary
        )
    }

    if !summary.watchdog.installed {
        return DiagnosticPlan(
            headline: "稳定守护未部署",
            impact: "一旦 Discord 断连或 gateway 卡住，当前机器不会自动恢复。",
            detail: "未启用 watchdog。先部署，再跑无人值守。",
            accent: NativePalette.amber,
            primary: DiagnosticActionPlan(
                title: "部署守护",
                systemImage: "shield.badge.plus",
                action: .support(.reinstallWatchdog),
                prominent: true
            ),
            secondary: DiagnosticActionPlan(
                title: "打开守护日志",
                systemImage: "doc.text",
                action: .openWatchdogLog,
                prominent: false
            ),
            tertiary: nil
        )
    }

    if summary.discord.status == "offline" || summary.discord.status == "unstable" {
        return DiagnosticPlan(
            headline: summary.discord.status == "offline" ? "Discord 当前离线" : "Discord 长连接不稳定",
            impact: "自动切换仍可继续，但推荐判断、在线状态和后台恢复的可靠性会明显下降。",
            detail: summary.discord.recommendation,
            accent: supportStatusPresentation(summary.discord.status).tint,
            primary: DiagnosticActionPlan(
                title: "执行修复",
                systemImage: "wrench.and.screwdriver",
                action: .support(.runWatchdogCheck),
                prominent: true
            ),
            secondary: DiagnosticActionPlan(
                title: "重启网关",
                systemImage: "arrow.counterclockwise.circle",
                action: .support(.restartGateway),
                prominent: false
            ),
            tertiary: DiagnosticActionPlan(
                title: "打开网关日志",
                systemImage: "doc.text.magnifyingglass",
                action: .openGatewayLog,
                prominent: false
            )
        )
    }

    if summary.environment.riskLevel == "high" || summary.environment.riskLevel == "watch" {
        return DiagnosticPlan(
            headline: summary.environment.riskLevel == "high" ? "环境风险正在放大断连概率" : "环境存在波动迹象",
            impact: "代理、VPN 或睡眠恢复会让 Discord 长连接更容易抖动，自动切换会因此更频繁触发诊断。",
            detail: summary.environment.recommendation,
            accent: riskPresentation(summary.environment.riskLevel).tint,
            primary: DiagnosticActionPlan(
                title: "执行巡检",
                systemImage: "stethoscope",
                action: .support(.runWatchdogCheck),
                prominent: true
            ),
            secondary: DiagnosticActionPlan(
                title: "打开网关日志",
                systemImage: "doc.text.magnifyingglass",
                action: .openGatewayLog,
                prominent: false
            ),
            tertiary: nil
        )
    }

    return DiagnosticPlan(
        headline: "诊断稳定",
        impact: "当前网关、Discord 和稳定守护都处于健康范围，没有阻塞自动切换的故障。",
        detail: "保留随机探测窗口，让 watchdog 持续运行。",
        accent: NativePalette.mint,
        primary: DiagnosticActionPlan(
            title: "执行巡检",
            systemImage: "stethoscope",
            action: .support(.runWatchdogCheck),
            prominent: true
        ),
        secondary: DiagnosticActionPlan(
            title: "打开网关日志",
            systemImage: "doc.text.magnifyingglass",
            action: .openGatewayLog,
            prominent: false
        ),
        tertiary: nil
    )
}

private func quotaValue(_ window: UsageWindow?) -> Double {
    Double(window?.leftPercent ?? 0) / 100
}

private func appReleaseLabel() -> String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    return version.map { "v\($0)" } ?? "本地构建"
}

struct NativeRootView: View {
    @ObservedObject var store: NativeAppStore

    private let sections: [SectionDescriptor] = [
        SectionDescriptor(section: .overview, title: "总览", caption: "当前状态", symbol: "rectangle.grid.2x2"),
        SectionDescriptor(section: .profiles, title: "账号池", caption: "切换和登录", symbol: "person.3"),
        SectionDescriptor(section: .settings, title: "设置", caption: "目录和自动化", symbol: "slider.horizontal.3"),
        SectionDescriptor(section: .diagnostics, title: "诊断", caption: "网关、守护、环境", symbol: "stethoscope"),
        SectionDescriptor(section: .deployment, title: "命令", caption: "命令和目录", symbol: "shippingbox")
    ]

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            store.start()
        }
    }

    private var sidebar: some View {
        ZStack {
            LinearGradient(
                colors: [NativePalette.sidebarTop, NativePalette.sidebarBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                sidebarBrand

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(sections) { item in
                            sidebarRow(item)
                        }
                    }
                    .padding(.vertical, 4)
                }

                sidebarFooter
            }
            .padding(18)
        }
        .frame(minWidth: 300, idealWidth: 320)
    }

    private var sidebarBrand: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(NativePalette.accent)
                        .frame(width: 52, height: 52)

                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenClaw Manager")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(NativePalette.ink)
                    Text(appReleaseLabel())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NativePalette.accent)
                }
            }

            HStack(spacing: 8) {
                TonePill(text: runtimeModeLabel(store.runtime?.mode), tint: NativePalette.accent)
                TonePill(text: store.automation?.enabled == true ? "自动切换已开启" : "自动切换待机", tint: store.automation?.enabled == true ? NativePalette.mint : .secondary)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(NativePalette.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(NativePalette.borderStrong, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func sidebarRow(_ item: SectionDescriptor) -> some View {
        let selected = store.selectedSection == item.section
        let hasDiagnosticWarning = item.section == .diagnostics
            && store.supportSummary?.discord.status != nil
            && store.supportSummary?.discord.status != "healthy"

        Button {
            store.selectedSection = item.section
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? NativePalette.accent.opacity(0.18) : NativePalette.surfaceAlt)
                        .frame(width: 34, height: 34)

                    Image(systemName: item.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? .white : NativePalette.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? .white : NativePalette.ink)
                    Text(item.caption)
                        .font(.caption)
                        .foregroundStyle(selected ? Color.white.opacity(0.84) : .secondary)
                }

                Spacer()

                if hasDiagnosticWarning {
                    Circle()
                        .fill(supportStatusPresentation(store.supportSummary?.discord.status ?? "").tint)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        selected
                            ? AnyShapeStyle(NativePalette.accent.opacity(0.20))
                            : AnyShapeStyle(NativePalette.surface)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? NativePalette.accent.opacity(0.24) : NativePalette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("原生运行状态")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(store.runtime == nil ? "连接中" : "在线")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(store.runtime == nil ? NativePalette.amber : NativePalette.mint)
            }

            VStack(alignment: .leading, spacing: 6) {
                KeyValueLine(label: "当前账号", value: store.activeProfile?.name ?? "未激活")
                KeyValueLine(label: "推荐目标", value: store.recommendedProfile?.name ?? "暂无推荐")
                KeyValueLine(label: "探测窗口", value: store.runtime.map { formatProbeWindow(minMs: $0.daemon.probeIntervalMinMs, maxMs: $0.daemon.probeIntervalMaxMs) } ?? "等待 daemon")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(NativePalette.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(NativePalette.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var detailView: some View {
        ZStack {
            LinearGradient(
                colors: [NativePalette.canvasTop, NativePalette.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color(red: 0.12, green: 0.13, blue: 0.15), NativePalette.canvasTop],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 118)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 1),
                    alignment: .bottom
                )

                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    NativeHeaderView(store: store)

                    if let notice = store.notice {
                        NoticeBanner(notice: notice) {
                            store.dismissNotice()
                        }
                    }

                    if store.isLoading && store.summary == nil {
                        GridCard(title: "正在连接本地服务", subtitle: "首次启动时会等待 daemon 就绪", systemImage: "hourglass.and.lock") {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("正在读取本地 manager、账号池与诊断状态")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        switch store.selectedSection {
                        case .overview:
                            OverviewSection(store: store)
                        case .profiles:
                            ProfilesSection(store: store)
                        case .settings:
                            SettingsSection(store: store)
                        case .diagnostics:
                            DiagnosticsSection(store: store)
                        case .deployment:
                            DeploymentSection(store: store)
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 1260, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct NativeHeaderView: View {
    @ObservedObject var store: NativeAppStore

    var body: some View {
        let runtime = store.runtime
        let support = store.supportSummary
        let narrative = sectionNarrative(for: store.selectedSection)

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    heroLayout(horizontal: true, runtime: runtime, support: support, narrative: narrative)
                    heroLayout(horizontal: false, runtime: runtime, support: support, narrative: narrative)
                }

                heroStats(runtime: runtime, support: support)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.10, green: 0.14, blue: 0.23), Color(red: 0.07, green: 0.09, blue: 0.13)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(NativePalette.borderStrong, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func heroLayout(horizontal: Bool, runtime: RuntimeOverview?, support: SupportSummary?, narrative: SectionNarrative) -> some View {
        if horizontal {
            HStack(alignment: .top, spacing: 20) {
                heroCopy(runtime: runtime, support: support, narrative: narrative)
                Spacer(minLength: 0)
                heroMeta(runtime: runtime)
                    .frame(width: 320)
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                heroCopy(runtime: runtime, support: support, narrative: narrative)
                heroMeta(runtime: runtime)
            }
        }
    }

    private func heroCopy(runtime: RuntimeOverview?, support: SupportSummary?, narrative: SectionNarrative) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(narrative.eyebrow)
                .font(.caption.weight(.semibold))
                .kerning(1.2)
                .foregroundStyle(Color.white.opacity(0.76))

            Text(narrative.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(narrative.detail)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)

            AdaptiveLine(spacing: 8) {
                TonePill(text: runtimeModeLabel(runtime?.mode), tint: NativePalette.accent.opacity(0.22), foreground: .white)
                TonePill(text: store.automation?.enabled == true ? "自动切换进行中" : "自动切换已暂停", tint: NativePalette.surfaceAlt, foreground: .white)
                if let support {
                    let presentation = supportStatusPresentation(support.discord.status)
                    TonePill(text: "诊断 \(presentation.label)", tint: presentation.tint.opacity(0.22), foreground: .white)
                }
            }

            AdaptiveLine(spacing: 10) {
                ActionButton("刷新状态", systemImage: "arrow.clockwise", busy: false) {
                    store.refreshAll()
                }
                Button("账号池") {
                    store.selectedSection = .profiles
                }
                .buttonStyle(NativeSecondaryButtonStyle())
                Button("诊断") {
                    store.selectedSection = .diagnostics
                }
                .buttonStyle(NativeSecondaryButtonStyle())
            }
        }
    }

    private func heroMeta(runtime: RuntimeOverview?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CompactMetaRow(label: "API 地址", value: present(runtime?.daemon.apiBaseUrl, fallback: "等待本地 API"))
            CompactMetaRow(label: "回调地址", value: present(store.localSnapshot.callbackURL ?? runtime?.roots.oauthCallbackUrl))
            CompactMetaRow(label: "最新切换", value: formatDate(runtime?.switching.lastActivationAt), detail: present(runtime?.switching.lastActivationReason, fallback: "还没有切换记录"))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func heroStats(runtime: RuntimeOverview?, support: SupportSummary?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                CompactMetricCell(
                    title: "当前账号",
                    value: store.activeProfile?.name ?? "未激活",
                    caption: present(store.activeProfile?.accountEmail, fallback: "当前没有接管任何账号"),
                    accent: NativePalette.accent
                )
                CompactMetricCell(
                    title: "推荐账号",
                    value: store.recommendedProfile?.name ?? "暂无推荐",
                    caption: present(store.recommendedProfile?.accountEmail, fallback: "当前没有更优切换目标"),
                    accent: NativePalette.mint
                )
                CompactMetricCell(
                    title: "切换耗时",
                    value: formatMillis(runtime?.switching.lastActivationDurationMs),
                    caption: "平均 \(formatMillis(runtime?.switching.averageActivationDurationMs))",
                    accent: NativePalette.amber
                )
                CompactMetricCell(
                    title: "守护状态",
                    value: runtime?.daemon.loopRunning == true ? "巡检中" : runtime?.daemon.loopScheduled == true ? "已驻留" : "等待启动",
                    caption: store.localSnapshot.watchdog.statusLine,
                    accent: support?.watchdog.installed == true ? NativePalette.mint : NativePalette.amber
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                CompactMetricCell(
                    title: "当前账号",
                    value: store.activeProfile?.name ?? "未激活",
                    caption: present(store.activeProfile?.accountEmail, fallback: "当前没有接管任何账号"),
                    accent: NativePalette.accent
                )
                CompactMetricCell(
                    title: "推荐账号",
                    value: store.recommendedProfile?.name ?? "暂无推荐",
                    caption: present(store.recommendedProfile?.accountEmail, fallback: "当前没有更优切换目标"),
                    accent: NativePalette.mint
                )
                CompactMetricCell(
                    title: "切换耗时",
                    value: formatMillis(runtime?.switching.lastActivationDurationMs),
                    caption: "平均 \(formatMillis(runtime?.switching.averageActivationDurationMs))",
                    accent: NativePalette.amber
                )
                CompactMetricCell(
                    title: "守护状态",
                    value: runtime?.daemon.loopRunning == true ? "巡检中" : runtime?.daemon.loopScheduled == true ? "已驻留" : "等待启动",
                    caption: store.localSnapshot.watchdog.statusLine,
                    accent: support?.watchdog.installed == true ? NativePalette.mint : NativePalette.amber
                )
            }
        }
    }
}

private struct OverviewSection: View {
    @ObservedObject var store: NativeAppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLead(
                title: "总览",
                detail: "先看状态，再决定动作。"
            )

            let readiness = readinessPresentation(runtime: store.runtime)
            let diagnostics = diagnosticsPresentation(summary: store.supportSummary)

            GridCard(title: "状态摘要", subtitle: "三项核心状态", systemImage: "gauge.with.dots.needle.33percent", accent: NativePalette.accent) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        CompactMetricCell(
                            title: "切换准备度",
                            value: readiness.label,
                            caption: store.runtime.map { "健康账号 \($0.switching.healthyProfiles) / 总数 \($0.switching.totalProfiles)" } ?? "等待 runtime 返回账号池状态",
                            accent: readiness.tint
                        )
                        CompactMetricCell(
                            title: "自动巡检",
                            value: store.automation?.enabled == true ? "已开启" : "已暂停",
                            caption: store.automation.map { "随机窗口 \(formatProbeWindow(minMs: $0.probeIntervalMinMs, maxMs: $0.probeIntervalMaxMs))" } ?? "等待自动化配置载入",
                            accent: store.automation?.enabled == true ? NativePalette.accent : NativePalette.amber
                        )
                        CompactMetricCell(
                            title: "稳定性判断",
                            value: diagnostics.label,
                            caption: store.supportSummary.map { "Discord \(supportStatusPresentation($0.discord.status).label) · 环境 \(riskPresentation($0.environment.riskLevel).label)" } ?? "等待诊断摘要返回",
                            accent: diagnostics.tint
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        CompactMetricCell(
                            title: "切换准备度",
                            value: readiness.label,
                            caption: store.runtime.map { "健康账号 \($0.switching.healthyProfiles) / 总数 \($0.switching.totalProfiles)" } ?? "等待 runtime 返回账号池状态",
                            accent: readiness.tint
                        )
                        CompactMetricCell(
                            title: "自动巡检",
                            value: store.automation?.enabled == true ? "已开启" : "已暂停",
                            caption: store.automation.map { "随机窗口 \(formatProbeWindow(minMs: $0.probeIntervalMinMs, maxMs: $0.probeIntervalMaxMs))" } ?? "等待自动化配置载入",
                            accent: store.automation?.enabled == true ? NativePalette.accent : NativePalette.amber
                        )
                        CompactMetricCell(
                            title: "稳定性判断",
                            value: diagnostics.label,
                            caption: store.supportSummary.map { "Discord \(supportStatusPresentation($0.discord.status).label) · 环境 \(riskPresentation($0.environment.riskLevel).label)" } ?? "等待诊断摘要返回",
                            accent: diagnostics.tint
                        )
                    }
                }
            }

            GridCard(title: "运行摘要", subtitle: "关键结果", systemImage: "list.bullet.rectangle", accent: NativePalette.mint) {
                TwoColumnFacts(items: overviewSummaryItems)
            }
        }
    }

    private var overviewSummaryItems: [(String, String)] {
        var items: [(String, String)] = [
            ("当前账号", store.activeProfile?.name ?? "未激活"),
            ("推荐账号", store.recommendedProfile?.name ?? "暂无推荐")
        ]

        if let runtime = store.runtime {
            items += [
                ("总账号数", "\(runtime.switching.totalProfiles)"),
                ("健康账号", "\(runtime.switching.healthyProfiles)"),
                ("最近切换", formatDate(runtime.switching.lastActivationAt)),
                ("切换触发", activationTriggerLabel(runtime.switching.lastActivationTrigger)),
                ("下一次探测", formatDate(runtime.daemon.nextProbeAt)),
                ("Daemon", runtime.daemon.loopRunning ? "执行中" : runtime.daemon.loopScheduled ? "已驻留" : "等待启动")
            ]
        }

        if let supportSummary = store.supportSummary {
            items += [
                ("Discord", supportStatusPresentation(supportSummary.discord.status).label),
                ("环境风险", riskPresentation(supportSummary.environment.riskLevel).label),
                ("Watchdog", supportSummary.watchdog.statusLine),
                ("最近断线", formatDate(supportSummary.discord.lastDisconnectAt))
            ]
        }

        return items
    }
}

private struct ProfilesSection: View {
    @ObservedObject var store: NativeAppStore
    @State private var newProfileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLead(
                title: "账号池",
                detail: "看 profile 状态并直接切换。"
            )

            VStack(alignment: .leading, spacing: 14) {
                InsightTile(
                    title: "当前激活",
                    value: store.activeProfile?.name ?? "未激活",
                    detail: present(store.activeProfile?.accountEmail, fallback: "当前没有激活的账号"),
                    systemImage: "person.crop.circle.badge.checkmark",
                    accent: NativePalette.mint
                )
                InsightTile(
                    title: "推荐目标",
                    value: store.recommendedProfile?.name ?? "暂无推荐",
                    detail: present(store.recommendedProfile?.statusReason, fallback: "等待探测计算更优目标"),
                    systemImage: "sparkles.rectangle.stack",
                    accent: NativePalette.accent
                )
                InsightTile(
                    title: "账号池规模",
                    value: "\(store.profiles.count) 个槽位",
                    detail: store.runtime.map { "健康 \($0.switching.healthyProfiles) · 风险 \($0.switching.riskyProfiles)" } ?? "等待 runtime 汇总",
                    systemImage: "person.3.sequence",
                    accent: NativePalette.amber
                )
            }

            GridCard(title: "新建账号槽位", subtitle: "创建一个新的 profile", systemImage: "plus.circle", accent: NativePalette.accent) {
                AdaptiveLine(spacing: 12) {
                    TextField("profile 名称，例如 team-a / backup-b", text: $newProfileName)
                        .textFieldStyle(.roundedBorder)
                    ActionButton("创建", systemImage: "plus", busy: store.isBusy("create")) {
                        let trimmed = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        store.createProfile(named: trimmed)
                        newProfileName = ""
                    }
                }
            }

            if let loginFlow = store.loginFlow {
                GridCard(title: "Codex 登录流程", subtitle: "等待浏览器回调完成", systemImage: "person.crop.circle.badge.checkmark", accent: NativePalette.amber) {
                    VStack(alignment: .leading, spacing: 10) {
                        KeyValueLine(label: "账号槽位", value: loginFlow.profileName)
                        KeyValueLine(label: "流程状态", value: loginFlow.status.rawValue)
                        KeyValueLine(label: "开始时间", value: formatDate(loginFlow.startedAt))
                        KeyValueLine(label: "过期时间", value: formatDate(loginFlow.expiresAt))

                        if let error = loginFlow.error, !error.isEmpty {
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(NativePalette.rose)
                        }

                        AdaptiveLine(spacing: 10) {
                            Button("打开登录页") {
                                store.openPendingLoginInBrowser()
                            }
                            .buttonStyle(NativeSecondaryButtonStyle(prominent: true))
                            if loginFlow.status != .pending {
                                Button("清除流程") {
                                    store.clearLoginFlow()
                                }
                                .buttonStyle(NativeSecondaryButtonStyle())
                            }
                        }
                    }
                }
            }

            if let spotlight = store.selectedProfile ?? store.activeProfile ?? store.recommendedProfile {
                GridCard(title: "账号聚焦", subtitle: "查看当前选中的 profile", systemImage: "viewfinder.circle", accent: statusPresentation(for: spotlight.status).tint) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(spotlight.name)
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(NativePalette.ink)
                                Text(spotlight.accountEmail ?? present(spotlight.primaryModelId, fallback: providerLabel(spotlight.primaryProviderId)))
                                    .font(.headline)
                                Text(profileCapabilitySummary(spotlight))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 8) {
                                TonePill(text: statusPresentation(for: spotlight.status).label, tint: statusPresentation(for: spotlight.status).tint)
                                if spotlight.isActive {
                                    TonePill(text: "当前激活", tint: NativePalette.mint)
                                }
                                if spotlight.isRecommended {
                                    TonePill(text: "推荐目标", tint: NativePalette.accent)
                                }
                            }
                        }

                        if spotlight.supportsQuota {
                            AdaptiveLine(spacing: 16) {
                                spotlightGauge(
                                    title: "5 小时额度",
                                    value: quotaValue(spotlight.quota.fiveHour),
                                    label: spotlight.quota.fiveHour.map { "\($0.leftPercent)%" } ?? "未提供",
                                    caption: formatDuration(ms: spotlight.quota.fiveHour?.resetInMs),
                                    tint: NativePalette.accent
                                )
                                spotlightGauge(
                                    title: "周额度",
                                    value: quotaValue(spotlight.quota.week),
                                    label: spotlight.quota.week.map { "\($0.leftPercent)%" } ?? "未提供",
                                    caption: formatDuration(ms: spotlight.quota.week?.resetInMs),
                                    tint: NativePalette.mint
                                )
                            }
                        }

                        TwoColumnFacts(items: [("状态说明", spotlight.statusReason)] + profileFactItems(spotlight))

                        AdaptiveLine(spacing: 10) {
                            if profileSupportsCodexLogin(spotlight) {
                                ActionButton("登录 Codex", systemImage: "person.badge.key", busy: store.isBusy("login:\(spotlight.name)")) {
                                    store.login(profileName: spotlight.name)
                                }
                            }
                            ActionButton("探测这个账号", systemImage: "scope", busy: store.isBusy("probe:\(spotlight.name)")) {
                                store.probe(profileName: spotlight.name)
                            }
                            ActionButton("切到这个账号", systemImage: "arrow.triangle.swap", busy: store.isBusy("activate:\(spotlight.name)")) {
                                store.activate(profileName: spotlight.name)
                            }
                            .disabled(spotlight.isActive)
                        }
                    }
                }
            }

            if !store.profiles.isEmpty {
                GridCard(title: "快速选中账号", subtitle: "先切换焦点，再决定登录 / 探测 / 激活", systemImage: "line.3.horizontal.decrease.circle", accent: NativePalette.amber) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(store.profiles) { profile in
                                ProfileSelectionChip(
                                    profile: profile,
                                    isSelected: store.selectedProfile?.name == profile.name,
                                    action: { store.selectProfile(profile.name) }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if store.profiles.isEmpty {
                GridCard(title: "账号池还是空的", subtitle: "先创建一个槽位，然后进入登录流程", systemImage: "tray", accent: NativePalette.amber) {
                    Text("当前没有 profile。先建一个主账号，再建一个备用账号。")
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(store.profiles) { profile in
                        ProfileCardView(profile: profile, store: store)
                    }
                }
            }
        }
    }

    private func spotlightGauge(title: String, value: Double, label: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(label)
                    .font(.headline.weight(.semibold))
            }
            ProgressView(value: value)
                .tint(tint)
                .progressViewStyle(.linear)
            Text("预计重置剩余 \(caption)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NativePalette.surfaceAlt)
        )
    }
}

private struct ProfileCardView: View {
    let profile: ManagedProfileSnapshot
    @ObservedObject var store: NativeAppStore

    var body: some View {
        let presentation = statusPresentation(for: profile.status)
        let isSelected = store.selectedProfile?.name == profile.name

        GridCard(
            title: profile.name,
            subtitle: present(profile.statusReason, fallback: "等待首次探测完成"),
            systemImage: "person.crop.rectangle.stack",
            accent: presentation.tint
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(presentation.tint.opacity(0.14))
                            .frame(width: 44, height: 44)
                        Text(String(profile.name.prefix(1)).uppercased())
                            .font(.headline.weight(.bold))
                            .foregroundStyle(presentation.tint)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile.accountEmail ?? present(profile.primaryModelId, fallback: providerLabel(profile.primaryProviderId)))
                            .font(.title3.weight(.semibold))
                        Text(profileCapabilitySummary(profile))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        TonePill(text: presentation.label, tint: presentation.tint)
                        if isSelected {
                            TonePill(text: "当前焦点", tint: NativePalette.amber)
                        }
                        if profile.isActive {
                            TonePill(text: "当前激活", tint: NativePalette.mint)
                        }
                        if profile.isRecommended {
                            TonePill(text: "推荐目标", tint: NativePalette.accent)
                        }
                        if profile.isDefault {
                            TonePill(text: "默认镜像", tint: .secondary)
                        }
                    }
                }

                if profile.supportsQuota {
                    AdaptiveLine(spacing: 16) {
                        quotaGauge(
                            title: "5 小时额度",
                            value: quotaValue(profile.quota.fiveHour),
                            label: profile.quota.fiveHour.map { "\($0.leftPercent)%" } ?? "未提供",
                            caption: formatDuration(ms: profile.quota.fiveHour?.resetInMs),
                            tint: NativePalette.accent
                        )
                        quotaGauge(
                            title: "周额度",
                            value: quotaValue(profile.quota.week),
                            label: profile.quota.week.map { "\($0.leftPercent)%" } ?? "未提供",
                            caption: formatDuration(ms: profile.quota.week?.resetInMs),
                            tint: NativePalette.mint
                        )
                    }
                }

                TwoColumnFacts(items: profileFactItems(profile))

                if let lastError = profile.lastError, !lastError.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(NativePalette.rose)
                        Text(lastError)
                            .font(.callout)
                            .foregroundStyle(NativePalette.rose)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(NativePalette.rose.opacity(0.10))
                    )
                }

                AdaptiveLine(spacing: 10) {
                    Button("聚焦查看") {
                        store.selectProfile(profile.name)
                    }
                    .buttonStyle(NativeSecondaryButtonStyle())
                    if profileSupportsCodexLogin(profile) {
                        ActionButton("登录 Codex", systemImage: "person.badge.key", busy: store.isBusy("login:\(profile.name)")) {
                            store.login(profileName: profile.name)
                        }
                    }
                    ActionButton("探测", systemImage: "scope", busy: store.isBusy("probe:\(profile.name)")) {
                        store.probe(profileName: profile.name)
                    }
                    ActionButton("激活", systemImage: "arrow.triangle.swap", busy: store.isBusy("activate:\(profile.name)")) {
                        store.activate(profileName: profile.name)
                    }
                    .disabled(profile.isActive)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isSelected ? NativePalette.amber.opacity(0.7) : Color.clear, lineWidth: 2)
        )
    }

    private func quotaGauge(title: String, value: Double, label: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(label)
                    .font(.headline.weight(.semibold))
            }
            ProgressView(value: value)
                .tint(tint)
                .progressViewStyle(.linear)
            Text("预计重置剩余 \(caption)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(NativePalette.surfaceAlt)
        )
    }
}

private struct SettingsSection: View {
    @ObservedObject var store: NativeAppStore
    @State private var autoActivateEnabled = true
    @State private var probeWindowMinSeconds = 90
    @State private var probeWindowMaxSeconds = 180
    @State private var fiveHourDrainPercent = 15
    @State private var weekDrainPercent = 10
    @State private var autoStatuses: Set<ProfileStatus> = [.draining, .cooldown, .exhausted, .reauthRequired, .unknown]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLead(
                title: "设置",
                detail: "改根目录和自动切换参数。"
            )

            VStack(alignment: .leading, spacing: 14) {
                InsightTile(
                    title: "自动切换",
                    value: store.automation?.enabled == true ? "已开启" : "已关闭",
                    detail: store.automation.map { "随机窗口 \(formatProbeWindow(minMs: $0.probeIntervalMinMs, maxMs: $0.probeIntervalMaxMs))，触发状态 \($0.autoSwitchStatuses.count) 个" } ?? "等待自动化配置返回",
                    systemImage: "arrow.triangle.branch",
                    accent: store.automation?.enabled == true ? NativePalette.mint : NativePalette.amber
                )
                InsightTile(
                    title: "OpenClaw 根目录",
                    value: URL(fileURLWithPath: store.localSnapshot.config.openclawHomeDir).lastPathComponent,
                    detail: store.localSnapshot.config.openclawHomeDir,
                    systemImage: "folder.badge.person.crop",
                    accent: NativePalette.accent
                )
                InsightTile(
                    title: "可选 Codex 根目录",
                    value: URL(fileURLWithPath: store.localSnapshot.config.codexHomeDir).lastPathComponent,
                    detail: store.localSnapshot.config.codexHomeDir,
                    systemImage: "folder.badge.gear",
                    accent: NativePalette.amber
                )
            }

            VStack(alignment: .leading, spacing: 18) {
                GridCard(title: "本地根目录", subtitle: "OpenClaw 必填，Codex 可选", systemImage: "folder.badge.gearshape", accent: NativePalette.accent) {
                    VStack(alignment: .leading, spacing: 14) {
                        PathHighlight(
                            title: "OpenClaw 根目录",
                            path: store.localSnapshot.config.openclawHomeDir,
                            tint: NativePalette.accent
                        )
                        AdaptiveLine(spacing: 10) {
                            Button("选择 OpenClaw 根目录") {
                                store.pickOpenClawRoot()
                            }
                            .buttonStyle(NativeSecondaryButtonStyle(prominent: true))
                            Button("重置为 Home") {
                                store.resetOpenClawRoot()
                            }
                            .buttonStyle(NativeSecondaryButtonStyle())
                        }

                        Divider()

                        PathHighlight(
                            title: "可选 Codex 根目录",
                            path: store.localSnapshot.config.codexHomeDir,
                            tint: NativePalette.amber
                        )
                        AdaptiveLine(spacing: 10) {
                            Button("选择 Codex 根目录") {
                                store.pickCodexRoot()
                            }
                            .buttonStyle(NativeSecondaryButtonStyle(prominent: true))
                            Button("重置为 Home") {
                                store.resetCodexRoot()
                            }
                            .buttonStyle(NativeSecondaryButtonStyle())
                        }

                        Divider()

                        TwoColumnFacts(items: [
                            ("设置文件", present(store.localSnapshot.settingsPath)),
                            ("应用数据目录", present(store.localSnapshot.appSupportPath)),
                            ("Manager 状态目录", present(store.runtime?.roots.managerDir)),
                            ("Runtime 目录", present(store.localSnapshot.runtimeRootPath)),
                            ("本地 API", present(store.localSnapshot.apiBaseURL, fallback: "等待启动")),
                            ("回调地址", present(store.localSnapshot.callbackURL))
                        ])

                        AdaptiveLine(spacing: 10) {
                            Button("打开设置文件") {
                                store.openSettingsFile()
                            }
                            .buttonStyle(NativeSecondaryButtonStyle())
                            Button("打开应用数据目录") {
                                store.openAppSupportDirectory()
                            }
                            .buttonStyle(NativeSecondaryButtonStyle())
                            Button("打开状态目录") {
                                store.openManagerStateDirectory()
                            }
                            .buttonStyle(NativeSecondaryButtonStyle())
                        }
                    }
                }

                GridCard(title: "自动切换策略", subtitle: "探测窗口、阈值和触发状态", systemImage: "arrow.triangle.branch", accent: NativePalette.mint) {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("启用自动切换", isOn: $autoActivateEnabled)
                            .toggleStyle(.switch)

                        Stepper(value: $probeWindowMinSeconds, in: 30...3600, step: 30) {
                            KeyValueLine(label: "探测窗口起点", value: "\(probeWindowMinSeconds) 秒")
                        }
                        .onChange(of: probeWindowMinSeconds) { nextValue in
                            if probeWindowMaxSeconds < nextValue {
                                probeWindowMaxSeconds = nextValue
                            }
                        }

                        Stepper(value: $probeWindowMaxSeconds, in: probeWindowMinSeconds...7200, step: 30) {
                            KeyValueLine(label: "探测窗口终点", value: "\(probeWindowMaxSeconds) 秒")
                        }
                        Stepper(value: $fiveHourDrainPercent, in: 0...100, step: 1) {
                            KeyValueLine(label: "5 小时预警阈值", value: "\(fiveHourDrainPercent)%")
                        }
                        Stepper(value: $weekDrainPercent, in: 0...100, step: 1) {
                            KeyValueLine(label: "周预警阈值", value: "\(weekDrainPercent)%")
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("触发自动切换的状态")
                                .font(.headline)
                            ForEach(autoSwitchStatusOptions) { status in
                                Toggle(statusPresentation(for: status).label, isOn: Binding(
                                    get: { autoStatuses.contains(status) },
                                    set: { enabled in
                                        if enabled {
                                            autoStatuses.insert(status)
                                        } else {
                                            autoStatuses.remove(status)
                                        }
                                    }
                                ))
                            }
                        }

                        AdaptiveLine(spacing: 10) {
                            ActionButton("保存设置", systemImage: "square.and.arrow.down", busy: store.isBusy("automation:save")) {
                                let patch = AutomationSettingsPatch(
                                    autoActivateEnabled: autoActivateEnabled,
                                    probeIntervalMinMs: probeWindowMinSeconds * 1000,
                                    probeIntervalMaxMs: probeWindowMaxSeconds * 1000,
                                    fiveHourDrainPercent: fiveHourDrainPercent,
                                    weekDrainPercent: weekDrainPercent,
                                    autoSwitchStatuses: autoSwitchStatusOptions.filter { autoStatuses.contains($0) }
                                )
                                store.saveAutomation(patch)
                            }
                            ActionButton("立即探测", systemImage: "play.circle", busy: store.isBusy("automation:tick")) {
                                store.runAutomationTick()
                            }
                            Button("重启服务") {
                                store.restartServices()
                            }
                            .buttonStyle(NativeSecondaryButtonStyle())
                        }
                    }
                }
            }
        }
        .onAppear {
            syncDraft()
        }
        .onChange(of: store.summary?.generatedAt) { _ in
            syncDraft()
        }
    }

    private func syncDraft() {
        guard let automation = store.automation else { return }
        autoActivateEnabled = automation.enabled
        probeWindowMinSeconds = max(30, automation.probeIntervalMinMs / 1000)
        probeWindowMaxSeconds = max(probeWindowMinSeconds, automation.probeIntervalMaxMs / 1000)
        fiveHourDrainPercent = automation.fiveHourDrainPercent
        weekDrainPercent = automation.weekDrainPercent
        autoStatuses = Set(automation.autoSwitchStatuses)
    }
}

private struct DiagnosticsSection: View {
    @ObservedObject var store: NativeAppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLead(
                title: "诊断",
                detail: "看状态，点修复。"
            )

            if let summary = store.supportSummary {
                let gatewayIssue = gatewayDiagnosis(summary: summary)
                let plan = diagnosticPlan(summary: summary)
                VStack(alignment: .leading, spacing: 14) {
                    InsightTile(
                        title: "网关状态",
                        value: summary.gateway.reachable ? "可达" : "不可达",
                        detail: summary.gateway.reachable
                            ? "连接延迟 \(formatMillis(summary.gateway.connectLatencyMs))"
                            : gatewayIssue.headline,
                        systemImage: "dot.radiowaves.left.and.right",
                        accent: summary.gateway.reachable ? NativePalette.mint : NativePalette.rose
                    )
                    InsightTile(
                        title: "Discord",
                        value: supportStatusPresentation(summary.discord.status).label,
                        detail: "15 分钟断线 \(summary.discord.disconnectCount15m) 次",
                        systemImage: "bubble.left.and.bubble.right",
                        accent: supportStatusPresentation(summary.discord.status).tint
                    )
                    InsightTile(
                        title: "环境风险",
                        value: riskPresentation(summary.environment.riskLevel).label,
                        detail: present(summary.environment.recommendation),
                        systemImage: "exclamationmark.shield",
                        accent: riskPresentation(summary.environment.riskLevel).tint
                    )
                }

                GridCard(title: "修复面板", subtitle: "当前判断和可执行动作", systemImage: "sparkles", accent: plan.accent) {
                    VStack(alignment: .leading, spacing: 12) {
                        diagnosticsSummaryBlock(
                            label: "当前判断",
                            value: plan.headline,
                            detail: plan.detail
                        )

                        diagnosticsSummaryBlock(
                            label: "影响范围",
                            value: plan.impact,
                            detail: nil
                        )

                        if let rawError = gatewayIssue.rawError, !summary.gateway.reachable {
                            diagnosticsSummaryBlock(
                                label: "原始错误",
                                value: rawError,
                                detail: "保留原始报错。"
                            )
                        }

                        AdaptiveLine(spacing: 10) {
                            if let primary = plan.primary {
                                diagnosticsActionButton(primary)
                            }
                            if let secondary = plan.secondary {
                                diagnosticsActionButton(secondary)
                            }
                            if let tertiary = plan.tertiary {
                                diagnosticsActionButton(tertiary)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 18) {
                    GridCard(title: "网关和 Discord", subtitle: "连接状态", systemImage: "wave.3.right.circle", accent: NativePalette.accent) {
                        let baseItems: [(String, String)] = [
                            ("网关可达", summary.gateway.reachable ? "可达" : "不可达"),
                            ("网关延迟", formatMillis(summary.gateway.connectLatencyMs)),
                            ("网关版本", present(summary.gateway.version)),
                            ("网关地址", present(summary.gateway.url)),
                            ("Discord", supportStatusPresentation(summary.discord.status).label),
                            ("最近登录", formatDate(summary.discord.lastLoggedInAt)),
                            ("最近断线", formatDate(summary.discord.lastDisconnectAt)),
                            ("15 分钟断线", "\(summary.discord.disconnectCount15m)"),
                            ("60 分钟断线", "\(summary.discord.disconnectCount60m)"),
                            ("建议", present(summary.discord.recommendation))
                        ]
                        let gatewayItems = summary.gateway.reachable
                            ? baseItems
                            : baseItems + [
                                ("根因判断", gatewayIssue.headline),
                                ("原始错误", present(gatewayIssue.rawError, fallback: "未提供"))
                            ]
                        TwoColumnFacts(items: gatewayItems)
                    }

                    GridCard(title: "稳定守护", subtitle: "看目录和最近恢复", systemImage: "shield", accent: NativePalette.mint) {
                        VStack(alignment: .leading, spacing: 14) {
                            TwoColumnFacts(items: [
                                ("状态", summary.watchdog.statusLine),
                                ("监控目录", present(summary.watchdog.monitoredStateDir)),
                                ("最近结果", present(summary.watchdog.lastLoopResult, fallback: "未记录")),
                                ("最近健康", formatDate(summary.watchdog.lastHealthyAt)),
                                ("最近恢复", formatDate(summary.watchdog.lastRestartAt)),
                                ("累计恢复", summary.watchdog.restartCount.map(String.init) ?? "未记录"),
                                ("状态文件", summary.watchdog.statePath),
                                ("日志文件", summary.watchdog.logPath)
                            ])

                            AdaptiveLine(spacing: 10) {
                                ActionButton("一键修复", systemImage: "wrench.and.screwdriver", busy: store.isBusy("support:\(SupportRepairAction.runWatchdogCheck.rawValue)")) {
                                    store.repair(.runWatchdogCheck)
                                }
                                ActionButton("重启网关", systemImage: "arrow.counterclockwise.circle", busy: store.isBusy("support:\(SupportRepairAction.restartGateway.rawValue)")) {
                                    store.repair(.restartGateway)
                                }
                            }

                            AdaptiveLine(spacing: 10) {
                                Button("打开 Gateway 日志") {
                                    store.openGatewayLog()
                                }
                                .buttonStyle(NativeSecondaryButtonStyle())
                                Button("打开守护日志") {
                                    store.openWatchdogLog()
                                }
                                .buttonStyle(NativeSecondaryButtonStyle())
                            }
                        }
                    }

                    GridCard(title: "环境风险", subtitle: "VPN、代理、唤醒风险", systemImage: "exclamationmark.triangle", accent: NativePalette.rose) {
                        VStack(alignment: .leading, spacing: 14) {
                            TwoColumnFacts(items: [
                                ("风险等级", riskPresentation(summary.environment.riskLevel).label),
                                ("主要网卡", present(summary.environment.primaryInterface)),
                                ("Gateway 地址", present(summary.environment.gatewayAddress)),
                                ("VPN 迹象", summary.environment.vpnLikelyActive ? "可能启用" : "未发现"),
                                ("代理迹象", summary.environment.proxyLikelyEnabled ? "可能启用" : "未发现"),
                                ("代理摘要", present(summary.environment.proxySummary)),
                                ("最近睡眠", formatDate(summary.environment.lastSleepAt)),
                                ("最近唤醒", formatDate(summary.environment.lastWakeAt)),
                                ("60 分钟唤醒次数", "\(summary.environment.sleepWakeCount60m)")
                            ])

                            if !summary.environment.riskySignals.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("风险信号")
                                        .font(.headline)
                                    ForEach(summary.environment.riskySignals, id: \.self) { signal in
                                        Text("• \(signal)")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            if !summary.discord.recentEvents.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("最近事件")
                                        .font(.headline)
                                    ForEach(summary.discord.recentEvents.prefix(6)) { event in
                                        Text("\(formatDate(event.timestamp)) · \(event.line)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                GridCard(title: "诊断数据加载中", subtitle: "等待 daemon 返回诊断结果", systemImage: "stethoscope", accent: NativePalette.amber) {
                    Text("当前还没有拿到诊断摘要。")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func diagnosticsActionButton(_ plan: DiagnosticActionPlan) -> some View {
        switch plan.action {
        case .openSettings:
            Button {
                store.selectedSection = .settings
            } label: {
                Label(plan.title, systemImage: plan.systemImage)
            }
            .buttonStyle(NativeSecondaryButtonStyle(prominent: plan.prominent))
        case .restartServices:
            Button {
                store.restartServices()
            } label: {
                Label(plan.title, systemImage: plan.systemImage)
            }
            .buttonStyle(NativeSecondaryButtonStyle(prominent: plan.prominent))
        case let .support(action):
            ActionButton(plan.title, systemImage: plan.systemImage, busy: store.isBusy("support:\(action.rawValue)")) {
                store.repair(action)
            }
        case .openGatewayLog:
            Button {
                store.openGatewayLog()
            } label: {
                Label(plan.title, systemImage: plan.systemImage)
            }
            .buttonStyle(NativeSecondaryButtonStyle(prominent: plan.prominent))
        case .openWatchdogLog:
            Button {
                store.openWatchdogLog()
            } label: {
                Label(plan.title, systemImage: plan.systemImage)
            }
            .buttonStyle(NativeSecondaryButtonStyle(prominent: plan.prominent))
        }
    }

    private func diagnosticsSummaryBlock(label: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(NativePalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NativePalette.surfaceAlt)
        )
    }
}

private struct DeploymentSection: View {
    @ObservedObject var store: NativeAppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLead(
                title: "命令",
                detail: "看命令和目录。"
            )

            if let runtime = store.runtime {
                VStack(alignment: .leading, spacing: 18) {
                    GridCard(title: "兼容性", subtitle: "当前支持范围", systemImage: "network", accent: NativePalette.accent) {
                        TwoColumnFacts(items: [
                            ("运行模式", runtimeModeLabel(runtime.mode)),
                            ("原生壳", runtime.compatibility.nativeShellRecommended ? "推荐" : "可选"),
                            ("支持浏览器壳", runtime.compatibility.browserShellSupported ? "支持" : "不支持"),
                            ("允许 localhost dev", runtime.compatibility.allowLocalhostDev ? "允许" : "关闭"),
                            ("允许来源", runtime.compatibility.allowedOrigins.isEmpty ? "仅同源 / 本地壳" : runtime.compatibility.allowedOrigins.joined(separator: " · ")),
                            ("回调地址", runtime.roots.oauthCallbackUrl)
                        ])
                    }

                    GridCard(title: "命令", subtitle: "常用入口", systemImage: "terminal", accent: NativePalette.mint) {
                        VStack(alignment: .leading, spacing: 12) {
                            CommandBlock(title: "OpenClaw", value: runtime.compatibility.wrapperCommand)
                            CommandBlock(title: "Codex", value: runtime.compatibility.codexWrapperCommand)
                        }
                    }

                    GridCard(title: "目录", subtitle: "当前使用的路径", systemImage: "shippingbox", accent: NativePalette.amber) {
                        TwoColumnFacts(items: [
                            ("OpenClaw Home", runtime.roots.openclawHomeDir),
                            ("可选 Codex Home", runtime.roots.codexHomeDir),
                            ("默认状态目录", runtime.roots.defaultOpenClawStateDir),
                            ("默认 Codex", runtime.roots.defaultCodexHome),
                            ("Manager 状态目录", runtime.roots.managerDir),
                            ("Runtime 目录", present(store.localSnapshot.runtimeRootPath))
                        ])
                    }
                }
            } else {
                GridCard(title: "等待 runtime", subtitle: "runtime 就绪后展示命令和目录", systemImage: "shippingbox", accent: NativePalette.amber) {
                    Text("当前还没有可展示的数据。")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct HeroInfoTile: View {
    var title: String
    var value: String
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.74))
            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
                .textSelection(.enabled)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.68))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NativePalette.surfaceAlt)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(NativePalette.border, lineWidth: 1)
        )
    }
}

private struct CompactMetaRow: View {
    var label: String
    var value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.70))
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .lineLimit(1)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AdaptiveLine<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    init(spacing: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct InsightTile: View {
    var title: String
    var value: String
    var detail: String
    var systemImage: String
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(NativePalette.ink)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NativePalette.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(NativePalette.border, lineWidth: 1)
        )
    }
}

private struct PathHighlight: View {
    var title: String
    var path: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(URL(fileURLWithPath: path).lastPathComponent)
                .font(.headline)
                .foregroundStyle(NativePalette.ink)
            Text(path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NativePalette.surfaceAlt)
        )
    }
}

private struct ProfileSelectionChip: View {
    let profile: ManagedProfileSnapshot
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let presentation = statusPresentation(for: profile.status)

        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(presentation.tint)
                        .frame(width: 8, height: 8)
                    Text(profile.name)
                        .font(.system(size: 13, weight: .semibold))
                }

                Text(profile.accountEmail ?? "未绑定")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.86) : .secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if profile.isActive {
                        MiniTag(text: "当前", tint: isSelected ? Color.white.opacity(0.14) : NativePalette.mint.opacity(0.16), foreground: isSelected ? .white : NativePalette.mint)
                    }
                    if profile.isRecommended {
                        MiniTag(text: "推荐", tint: isSelected ? Color.white.opacity(0.14) : NativePalette.accent.opacity(0.16), foreground: isSelected ? .white : NativePalette.accent)
                    }
                }
            }
            .padding(14)
            .frame(width: 190, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(NativePalette.accent.opacity(0.18))
                            : AnyShapeStyle(NativePalette.surfaceRaised)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? NativePalette.accent.opacity(0.24) : NativePalette.border, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? Color.white : NativePalette.ink)
        }
        .buttonStyle(.plain)
    }
}

private struct MiniTag: View {
    var text: String
    var tint: Color
    var foreground: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint, in: Capsule())
            .foregroundStyle(foreground)
    }
}

private struct SectionLead: View {
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(NativePalette.ink)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

private struct GridCard<Content: View>: View {
    var title: String
    var subtitle: String?
    var systemImage: String
    var accent: Color
    @ViewBuilder var content: Content

    init(title: String, subtitle: String? = nil, systemImage: String, accent: Color = NativePalette.accent, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(NativePalette.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(NativePalette.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(NativePalette.border, lineWidth: 1)
        )
    }
}

private struct FactEntry: Identifiable {
    var label: String
    var value: String

    var id: String { label }
}

private struct TwoColumnFacts: View {
    var items: [(String, String)]

    private var entries: [FactEntry] {
        items.map { FactEntry(label: $0.0, value: $0.1) }
    }

    private var rows: [[FactEntry]] {
        stride(from: 0, to: entries.count, by: 2).map { start in
            Array(entries[start..<min(start + 2, entries.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(row) { entry in
                            FactTile(entry: entry)
                        }
                        if row.count == 1 {
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(row) { entry in
                            FactTile(entry: entry)
                        }
                    }
                }
            }
        }
    }
}

private struct FactTile: View {
    var entry: FactEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(entry.value)
                .foregroundStyle(NativePalette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(NativePalette.surfaceAlt)
        )
    }
}

private struct MetricTile: View {
    var title: String
    var value: String
    var caption: String
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(NativePalette.ink)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NativePalette.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(NativePalette.border, lineWidth: 1)
        )
    }
}

private struct CompactMetricCell: View {
    var title: String
    var value: String
    var caption: String
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(NativePalette.ink)
                .lineLimit(1)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NativePalette.surfaceAlt)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(NativePalette.border, lineWidth: 1)
        )
    }
}

private struct TonePill: View {
    var text: String
    var tint: Color
    var foreground: Color = .primary

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
            .foregroundStyle(foreground)
    }
}

private struct NoticeBanner: View {
    var notice: NativeNotice
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(notice.title)
                    .font(.headline)
                if let detail = notice.detail, !detail.isEmpty {
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .padding(8)
                    .background(NativePalette.surfaceAlt, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(NativePalette.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        )
    }

    private var tint: Color {
        switch notice.tone {
        case .info:
            return NativePalette.accent
        case .success:
            return NativePalette.mint
        case .warning:
            return NativePalette.amber
        case .error:
            return NativePalette.rose
        }
    }

    private var symbol: String {
        switch notice.tone {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }
}

private struct ActionButton: View {
    var title: String
    var systemImage: String
    var busy: Bool
    var action: () -> Void

    init(_ title: String, systemImage: String, busy: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.busy = busy
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if busy {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("处理中")
                }
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .buttonStyle(NativeSecondaryButtonStyle(prominent: true))
        .disabled(busy)
    }
}

private struct NativeSecondaryButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(background(configuration: configuration))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(border(configuration: configuration), lineWidth: 1)
            )
            .foregroundStyle(foreground)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }

    private var foreground: Color {
        prominent ? .white : NativePalette.ink
    }

    private func background(configuration: Configuration) -> Color {
        if prominent {
            return configuration.isPressed
                ? NativePalette.accent.opacity(0.88)
                : NativePalette.accent
        }
        return configuration.isPressed
            ? NativePalette.surfaceAlt
            : NativePalette.surfaceRaised
    }

    private func border(configuration: Configuration) -> Color {
        prominent
            ? NativePalette.accent.opacity(configuration.isPressed ? 0.30 : 0.24)
            : NativePalette.border
    }
}

private struct KeyValueLine: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .foregroundStyle(NativePalette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CommandBlock: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(NativePalette.surfaceAlt)
                )
        }
    }
}
