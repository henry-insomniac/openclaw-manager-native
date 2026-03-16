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
    static let accent = Color(red: 0.46, green: 0.52, blue: 0.42)
    static let mint = Color(red: 0.33, green: 0.63, blue: 0.50)
    static let amber = Color(red: 0.71, green: 0.57, blue: 0.33)
    static let rose = Color(red: 0.74, green: 0.41, blue: 0.38)
    static let ink = Color(red: 0.92, green: 0.93, blue: 0.90)
    static let sidebarTop = Color(red: 0.07, green: 0.08, blue: 0.08)
    static let sidebarBottom = Color(red: 0.05, green: 0.06, blue: 0.06)
    static let canvasTop = Color(red: 0.09, green: 0.10, blue: 0.10)
    static let canvasBottom = Color(red: 0.06, green: 0.07, blue: 0.07)
    static let surface = Color(red: 0.11, green: 0.12, blue: 0.12)
    static let surfaceRaised = Color(red: 0.14, green: 0.15, blue: 0.15)
    static let surfaceAlt = Color(red: 0.17, green: 0.18, blue: 0.18)
    static let border = Color.white.opacity(0.07)
    static let borderStrong = Color.white.opacity(0.12)
}

private struct SectionNarrative {
    var eyebrow: String?
    var title: String
    var detail: String?
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
    case "notice":
        return StatusPresentation(label: "提示", tint: NativePalette.accent)
    case "watch":
        return StatusPresentation(label: "观察", tint: .orange)
    case "high":
        return StatusPresentation(label: "高风险", tint: .red)
    default:
        return StatusPresentation(label: "未知", tint: .secondary)
    }
}

private func machinePressurePresentation(_ pressure: String) -> StatusPresentation {
    switch pressure {
    case "high":
        return StatusPresentation(label: "偏高", tint: NativePalette.rose)
    case "watch":
        return StatusPresentation(label: "观察", tint: NativePalette.amber)
    case "normal":
        return StatusPresentation(label: "正常", tint: NativePalette.mint)
    default:
        return StatusPresentation(label: "等待采样", tint: .secondary)
    }
}

private func openClawAvailabilityPresentation(_ openClaw: MachineSummary.OpenClaw?) -> StatusPresentation {
    guard let openClaw else {
        return StatusPresentation(label: "等待检测", tint: NativePalette.amber)
    }
    if openClaw.available {
        return StatusPresentation(label: "已发现", tint: NativePalette.mint)
    }
    return StatusPresentation(label: "未发现", tint: NativePalette.amber)
}

private func processRunningPresentation(_ snapshot: MachineSummary.ProcessGroup.Snapshot) -> StatusPresentation {
    snapshot.running
        ? StatusPresentation(label: "运行中", tint: NativePalette.mint)
        : StatusPresentation(label: "未运行", tint: NativePalette.amber)
}

private func configValidationPresentation(_ valid: Bool) -> StatusPresentation {
    valid
        ? StatusPresentation(label: "有效", tint: .green)
        : StatusPresentation(label: "需修复", tint: .red)
}

private func profileConfigValidationDetail(_ result: OpenClawProfileConfigValidationResult) -> String {
    let checkedAt = formatDate(result.collectedAt)
    if result.valid {
        return "已按 OpenClaw CLI 校验 · \(checkedAt)"
    }
    return "\(result.detail) · \(checkedAt)"
}

private func gatewayServicePresentation(_ summary: SupportSummary.Maintenance.GatewayService) -> StatusPresentation {
    if let issue = summary.issue, !issue.isEmpty {
        return StatusPresentation(label: "需处理", tint: .red)
    }
    if !summary.installed {
        return StatusPresentation(label: "未安装", tint: .orange)
    }
    if let probeStatus = summary.probeStatus?.lowercased(), probeStatus.contains("failed") {
        return StatusPresentation(label: "待检查", tint: .orange)
    }
    return StatusPresentation(label: "正常", tint: .green)
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

private func formatBytes(_ value: Int?) -> String {
    guard let value else { return "未提供" }
    return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
}

private func formatByteRate(_ value: Int?) -> String {
    guard let value else { return "等待采样" }
    return "\(ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary))/s"
}

private func formatCPUPercent(_ value: Double?) -> String {
    guard let value else { return "未提供" }
    return String(format: "%.1f%%", value)
}

private func formatUptimeSeconds(_ value: Int?) -> String {
    guard let value else { return "未提供" }
    if value <= 0 { return "刚启动" }

    let days = value / 86_400
    let hours = (value % 86_400) / 3_600
    let minutes = (value % 3_600) / 60

    if days > 0 {
        return "\(days)天 \(hours)小时"
    }
    if hours > 0 {
        return "\(hours)小时 \(minutes)分钟"
    }
    return "\(minutes)分钟"
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

private func loginKindLabel(_ loginKind: String?) -> String {
    switch loginKind {
    case "codex-oauth":
        return "支持浏览器登录"
    default:
        return "不提供内置登录"
    }
}

private func loginActionLabel(_ loginKind: String?) -> String? {
    switch loginKind {
    case "codex-oauth":
        return "登录 Codex"
    default:
        return nil
    }
}

private func companionRuntimeLabel(_ runtimeKind: String?) -> String? {
    switch runtimeKind {
    case "codex":
        return "Codex 命令行"
    default:
        return nil
    }
}

private func present(_ value: String?, fallback: String = "未提供") -> String {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return fallback
    }
    return value
}

private func containsChinese(_ text: String) -> Bool {
    text.range(of: "\\p{Script=Han}", options: .regularExpression) != nil
}

private func functionalText(_ value: String?, fallback: String) -> String {
    guard let value else { return fallback }

    let lines = value
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter {
            !$0.isEmpty
                && !$0.lowercased().contains("docs:")
                && !$0.contains("http://")
                && !$0.contains("https://")
                && !$0.lowercased().contains("gateway#")
        }

    guard let first = lines.first, !first.isEmpty else {
        return fallback
    }

    if !containsChinese(first), first.count > 32 {
        return fallback
    }

    return first
}

private func sectionNarrative(for section: NativeSection) -> SectionNarrative {
    switch section {
    case .overview:
        return SectionNarrative(
            eyebrow: nil,
            title: "总览",
            detail: nil
        )
    case .monitor:
        return SectionNarrative(
            eyebrow: nil,
            title: "监控",
            detail: nil
        )
    case .profiles:
        return SectionNarrative(
            eyebrow: nil,
            title: "账号池",
            detail: nil
        )
    case .skills:
        return SectionNarrative(
            eyebrow: nil,
            title: "技能",
            detail: nil
        )
    case .settings:
        return SectionNarrative(
            eyebrow: nil,
            title: "设置",
            detail: nil
        )
    case .diagnostics:
        return SectionNarrative(
            eyebrow: nil,
            title: "诊断",
            detail: nil
        )
    case .deployment:
        return SectionNarrative(
            eyebrow: nil,
            title: "命令",
            detail: nil
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
    if summary.environment.riskLevel == "notice" {
        return StatusPresentation(label: "有提示", tint: NativePalette.accent)
    }
    return StatusPresentation(label: "稳定", tint: NativePalette.mint)
}

private func profileCapabilitySummary(_ profile: ManagedProfileSnapshot) -> String {
    let provider = providerLabel(profile.primaryProviderId)
    let quota = profile.supportsQuota ? "可看剩余额度" : "不显示额度"
    return "模型来源: \(provider) · \(quota) · \(loginKindLabel(profile.loginKind))"
}

private func profileFactItems(_ profile: ManagedProfileSnapshot) -> [(String, String)] {
    var items: [(String, String)] = [
        ("模型来源", providerLabel(profile.primaryProviderId)),
        ("主模型", present(profile.primaryModelId)),
        ("已配置来源", profile.configuredProviderIds.isEmpty ? "未提供" : profile.configuredProviderIds.joined(separator: " · ")),
        ("登录方式", loginKindLabel(profile.loginKind))
    ]

    if let companion = companionRuntimeLabel(profile.companionRuntimeKind) {
        items.append(("外部命令行", companion))
    }

    if profile.supportsQuota {
        items.insert(("账号类型", present(profile.quota.plan)), at: 3)
    }

    if profile.tokenExpiresInMs != nil || profile.tokenExpiresAt != nil {
        items.append(("认证剩余", formatDuration(ms: profile.tokenExpiresInMs)))
        items.append(("认证到期", formatDate(profile.tokenExpiresAt)))
    }

    items.append(("账号 ID", shortAccountId(profile.accountId)))
    items.append(("状态目录", profile.stateDir))

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
    case openPath(String)
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
            detail: "正在读取网关状态。",
            rawError: nil,
            prefersSettings: false,
            prefersRestartServices: false
        )
    }

    if summary.gateway.reachable {
        return GatewayDiagnosis(
            headline: "Gateway 正常响应",
            detail: "当前不需要处理。",
            rawError: nil,
            prefersSettings: false,
            prefersRestartServices: false
        )
    }

    let rawError = summary.gateway.error?.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = rawError?.lowercased() ?? ""

    if normalized.contains("uv_cwd") || normalized.contains("getcwd") || normalized.contains("cannot access parent directories") {
        return GatewayDiagnosis(
            headline: "服务运行目录失效",
            detail: "先重启服务。",
            rawError: rawError,
            prefersSettings: false,
            prefersRestartServices: true
        )
    }

    if normalized.contains("enoent") && normalized.contains("openclaw") {
        return GatewayDiagnosis(
            headline: "未找到 OpenClaw CLI",
            detail: "先检查安装和目录设置。",
            rawError: rawError,
            prefersSettings: true,
            prefersRestartServices: true
        )
    }

    if normalized.contains("invalid json") {
        return GatewayDiagnosis(
            headline: "Gateway 返回异常输出",
            detail: "先重启服务。",
            rawError: rawError,
            prefersSettings: false,
            prefersRestartServices: true
        )
    }

    if normalized.contains("timed out") || normalized.contains("econnrefused") || normalized.contains("connect") || normalized.contains("status failed") {
        return GatewayDiagnosis(
            headline: "Gateway 没有正常响应",
            detail: "先重启服务。",
            rawError: rawError,
            prefersSettings: false,
            prefersRestartServices: true
        )
    }

    return GatewayDiagnosis(
        headline: "Gateway 当前不可达",
        detail: "先重启服务。",
        rawError: rawError,
        prefersSettings: false,
        prefersRestartServices: true
    )
}

private func maintenanceHeadline(summary: SupportSummary?) -> String {
    guard let summary else {
        return "等待诊断数据。"
    }

    if !summary.maintenance.config.valid {
        return "OpenClaw 配置没有通过校验。"
    }
    if let serviceIssue = summary.maintenance.gatewayService.issue, !serviceIssue.isEmpty {
        _ = serviceIssue
        return "Gateway 服务配置需要处理。"
    }
    if summary.discord.status == "offline" {
        return "Discord 当前离线。"
    }
    if summary.environment.riskLevel == "high" {
        return "当前网络环境异常，会直接影响稳定性。"
    }
    if summary.environment.riskLevel == "watch" {
        return "检测到多条环境信号，可能放大断连概率。"
    }
    if summary.environment.riskLevel == "notice" {
        return "检测到环境提示，不一定需要立刻处理。"
    }
    if !summary.gateway.reachable {
        return gatewayDiagnosis(summary: summary).headline
    }
    return "当前没有明显故障。"
}

private func primaryRecommendation(summary: SupportSummary?) -> String {
    guard let summary else {
        return "等待状态。"
    }

    if !summary.maintenance.config.valid {
        return "先执行“官方修复”。"
    }
    if let recommendation = summary.maintenance.gatewayService.recommendation,
       !recommendation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return functionalText(recommendation, fallback: "先执行“重装服务”。")
    }
    if let serviceIssue = summary.maintenance.gatewayService.issue, !serviceIssue.isEmpty {
        return "先执行“重装服务”。"
    }
    if summary.discord.status == "offline" {
        return functionalText(summary.discord.recommendation, fallback: "先执行“一键修复”。")
    }
    if summary.environment.riskLevel == "high" || summary.environment.riskLevel == "watch" {
        return functionalText(summary.environment.recommendation, fallback: "先检查代理、VPN 和睡眠恢复因素。")
    }
    if summary.environment.riskLevel == "notice" {
        return "当前先观察；如果继续断连，再排查环境因素。"
    }
    if !summary.gateway.reachable {
        return gatewayDiagnosis(summary: summary).detail
    }
    return "当前不需要修复。"
}

private func supportRepairTitle(_ action: SupportRepairAction) -> String {
    switch action {
    case .validateConfig:
        return "校验配置"
    case .runOpenClawDoctor:
        return "官方体检"
    case .runOpenClawDoctorFix:
        return "官方修复"
    case .reinstallGatewayService:
        return "重装 Gateway 服务"
    case .runWatchdogCheck:
        return "一键修复"
    case .restartGateway:
        return "重启 OpenClaw 服务"
    case .reinstallWatchdog:
        return "重新部署稳定守护"
    case .openGatewayLog:
        return "打开 Gateway 日志"
    case .openWatchdogLog:
        return "打开守护日志"
    }
}

private func supportRepairSummary(_ result: SupportRepairResult) -> String {
    functionalText(result.message, fallback: result.ok ? "已完成。" : "未完成。")
}

private func supportRepairFollowUp(_ result: SupportRepairResult) -> String {
    result.ok ? "" : "继续执行上面的下一步。"
}

private func diagnosticPlan(summary: SupportSummary?) -> DiagnosticPlan {
    guard let summary else {
        return DiagnosticPlan(
            headline: "等待诊断数据",
            impact: "",
            detail: "正在读取本地状态。",
            accent: NativePalette.amber,
            primary: nil,
            secondary: nil,
            tertiary: nil
        )
    }

    if !summary.maintenance.config.valid {
        return DiagnosticPlan(
            headline: "OpenClaw 配置需要修复",
            impact: "",
            detail: "先执行“官方修复”，再校验配置。",
            accent: NativePalette.rose,
            primary: DiagnosticActionPlan(
                title: "官方修复",
                systemImage: "cross.case",
                action: .support(.runOpenClawDoctorFix),
                prominent: true
            ),
            secondary: DiagnosticActionPlan(
                title: "重新校验",
                systemImage: "checklist",
                action: .support(.validateConfig),
                prominent: false
            ),
            tertiary: DiagnosticActionPlan(
                title: "打开配置",
                systemImage: "doc.text",
                action: .openPath(summary.maintenance.config.path),
                prominent: false
            )
        )
    }

    if let serviceIssue = summary.maintenance.gatewayService.issue, !serviceIssue.isEmpty {
        return DiagnosticPlan(
            headline: "Gateway 服务需要维护",
            impact: "",
            detail: "先执行“重装服务”。",
            accent: NativePalette.rose,
            primary: DiagnosticActionPlan(
                title: "重装服务",
                systemImage: "shippingbox.circle",
                action: .support(.reinstallGatewayService),
                prominent: true
            ),
            secondary: DiagnosticActionPlan(
                title: "官方体检",
                systemImage: "stethoscope",
                action: .support(.runOpenClawDoctor),
                prominent: false
            ),
            tertiary: summary.maintenance.gatewayService.serviceFile.map {
                DiagnosticActionPlan(
                    title: "打开服务文件",
                    systemImage: "doc.text.magnifyingglass",
                    action: .openPath($0),
                    prominent: false
                )
            }
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
            impact: "",
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
            impact: "",
            detail: "先部署守护。",
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
            impact: "",
            detail: functionalText(summary.discord.recommendation, fallback: "先执行“一键修复”。"),
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
            headline: summary.environment.riskLevel == "high" ? "环境因素正在放大断连概率" : "检测到多条环境波动信号",
            impact: "",
            detail: functionalText(summary.environment.recommendation, fallback: "先检查网络环境。"),
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
        impact: "",
        detail: "当前没有需要处理的问题。",
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
        SectionDescriptor(section: .overview, title: "总览", caption: "", symbol: "rectangle.grid.2x2"),
        SectionDescriptor(section: .monitor, title: "监控", caption: "", symbol: "waveform.path.ecg.rectangle"),
        SectionDescriptor(section: .profiles, title: "账号池", caption: "", symbol: "person.3"),
        SectionDescriptor(section: .skills, title: "技能", caption: "", symbol: "square.stack.3d.up.fill"),
        SectionDescriptor(section: .settings, title: "设置", caption: "", symbol: "slider.horizontal.3"),
        SectionDescriptor(section: .diagnostics, title: "诊断", caption: "", symbol: "stethoscope"),
        SectionDescriptor(section: .deployment, title: "命令", caption: "", symbol: "shippingbox")
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
                        .fill(NativePalette.surfaceAlt)
                        .frame(width: 52, height: 52)

                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(NativePalette.accent)
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
                TonePill(text: runtimeModeLabel(store.runtime?.mode), tint: NativePalette.surfaceAlt, foreground: NativePalette.ink)
                TonePill(text: store.automation?.enabled == true ? "巡检 开" : "巡检 关", tint: store.automation?.enabled == true ? NativePalette.mint.opacity(0.18) : NativePalette.surfaceAlt, foreground: store.automation?.enabled == true ? NativePalette.mint : NativePalette.ink)
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
        let hasMonitorWarning = item.section == .monitor
            && (store.machineSummary?.memory.pressure == "high" || (store.machineSummary?.swap.usedPercent ?? 0) >= 5)

        Button {
            store.selectedSection = item.section
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? NativePalette.surfaceAlt : NativePalette.surfaceAlt.opacity(0.88))
                        .frame(width: 34, height: 34)

                    Image(systemName: item.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? NativePalette.accent : NativePalette.accent.opacity(0.86))
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NativePalette.ink)
                }

                Spacer()

                if hasDiagnosticWarning {
                    Circle()
                        .fill(supportStatusPresentation(store.supportSummary?.discord.status ?? "").tint)
                        .frame(width: 8, height: 8)
                } else if hasMonitorWarning {
                    Circle()
                        .fill(machinePressurePresentation(store.machineSummary?.memory.pressure ?? "").tint)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        selected
                            ? AnyShapeStyle(NativePalette.surfaceRaised)
                            : AnyShapeStyle(NativePalette.surface)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? NativePalette.borderStrong : NativePalette.border, lineWidth: 1)
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
                KeyValueLine(label: "检查窗口", value: store.runtime.map { formatProbeWindow(minMs: $0.daemon.probeIntervalMinMs, maxMs: $0.daemon.probeIntervalMaxMs) } ?? "等待 daemon")
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
                    colors: [Color(red: 0.13, green: 0.12, blue: 0.11), NativePalette.canvasTop],
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
                    if let notice = store.notice {
                        NoticeBanner(notice: notice) {
                            store.dismissNotice()
                        }
                    }

                    if store.isLoading && store.summary == nil {
                        GridCard(title: "正在连接", systemImage: "hourglass.and.lock") {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("读取中。")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        switch store.selectedSection {
                        case .overview:
                            OverviewSection(store: store)
                        case .monitor:
                            MonitorSection(store: store)
                        case .profiles:
                            ProfilesSection(store: store)
                        case .skills:
                            SkillsSection(store: store)
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

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    heroLayout(horizontal: true, runtime: runtime)
                    heroLayout(horizontal: false, runtime: runtime)
                }

                heroStats(runtime: runtime, support: store.supportSummary)

                if let machineSummary = store.machineSummary {
                    headerMonitorStrip(summary: machineSummary)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.14, green: 0.15, blue: 0.13), Color(red: 0.08, green: 0.09, blue: 0.09)],
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
    private func heroLayout(horizontal: Bool, runtime: RuntimeOverview?) -> some View {
        if horizontal {
            HStack(alignment: .top, spacing: 20) {
                heroCopy(runtime: runtime)
                Spacer(minLength: 0)
                heroMeta(runtime: runtime)
                    .frame(width: 320)
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                heroCopy(runtime: runtime)
                heroMeta(runtime: runtime)
            }
        }
    }

    private func heroCopy(runtime: RuntimeOverview?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("运行状态")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            AdaptiveLine(spacing: 8) {
                TonePill(text: runtimeModeLabel(runtime?.mode), tint: NativePalette.accent.opacity(0.22), foreground: .white)
                TonePill(text: store.automation?.enabled == true ? "巡检 开" : "巡检 关", tint: NativePalette.surfaceAlt, foreground: .white)
            }

            AdaptiveLine(spacing: 10) {
                ActionButton("刷新", systemImage: "arrow.clockwise", busy: false) {
                    let scope: NativeRefreshScope
                    switch store.selectedSection {
                    case .diagnostics:
                        scope = .full
                    case .monitor:
                        scope = .monitorOnly
                    case .skills:
                        scope = .skillsOnly
                    case .settings:
                        scope = .settingsOnly
                    default:
                        scope = .managerOnly
                    }
                    store.refreshAll(scope: scope)
                }
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

    private func headerMonitorStrip(summary: MachineSummary) -> some View {
        let pressure = machinePressurePresentation(summary.memory.pressure)
        let manager = processRunningPresentation(summary.processes.manager)
        let trafficHistory = store.machineHistory.map { $0.receivedBytesPerSec + $0.sentBytesPerSec }
        let totalRate = (summary.network.receivedBytesPerSec ?? 0) + (summary.network.sentBytesPerSec ?? 0)

        return VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    headerMonitorSummary(summary: summary, pressure: pressure, manager: manager)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 10) {
                        HeaderMonitorTrendChip(
                            title: "CPU",
                            value: "\(summary.cpu.activePercent)%",
                            detail: "User \(summary.cpu.userPercent)% · Sys \(summary.cpu.systemPercent)%",
                            values: store.machineHistory.map(\.cpuActivePercent),
                            accent: NativePalette.accent
                        )
                        HeaderMonitorTrendChip(
                            title: "内存",
                            value: "\(summary.memory.pressurePercent)%",
                            detail: pressure.label,
                            values: store.machineHistory.map(\.memoryPressurePercent),
                            accent: pressure.tint
                        )
                        HeaderMonitorTrendChip(
                            title: "网络",
                            value: formatByteRate(totalRate),
                            detail: "↓ \(formatByteRate(summary.network.receivedBytesPerSec)) · ↑ \(formatByteRate(summary.network.sentBytesPerSec))",
                            values: trafficHistory,
                            accent: NativePalette.mint
                        )
                    }
                    .frame(width: 560)
                }

                VStack(alignment: .leading, spacing: 12) {
                    headerMonitorSummary(summary: summary, pressure: pressure, manager: manager)
                    AdaptiveLine(spacing: 10) {
                        HeaderMonitorTrendChip(
                            title: "CPU",
                            value: "\(summary.cpu.activePercent)%",
                            detail: "User \(summary.cpu.userPercent)% · Sys \(summary.cpu.systemPercent)%",
                            values: store.machineHistory.map(\.cpuActivePercent),
                            accent: NativePalette.accent
                        )
                        HeaderMonitorTrendChip(
                            title: "内存",
                            value: "\(summary.memory.pressurePercent)%",
                            detail: pressure.label,
                            values: store.machineHistory.map(\.memoryPressurePercent),
                            accent: pressure.tint
                        )
                        HeaderMonitorTrendChip(
                            title: "网络",
                            value: formatByteRate(totalRate),
                            detail: "↓ \(formatByteRate(summary.network.receivedBytesPerSec)) · ↑ \(formatByteRate(summary.network.sentBytesPerSec))",
                            values: trafficHistory,
                            accent: NativePalette.mint
                        )
                    }
                }
            }
        }
    }

    private func headerMonitorSummary(
        summary: MachineSummary,
        pressure: StatusPresentation,
        manager: StatusPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(pressure.tint)
                    .frame(width: 8, height: 8)
                Text("监控速览")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.76))
            }

            Text("CPU \(summary.cpu.activePercent)% · 压力 \(summary.memory.pressurePercent)% · Swap \(summary.swap.usedPercent)%")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(headerMonitorDetail(summary: summary, pressure: pressure, manager: manager))
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.70))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func headerMonitorDetail(
        summary: MachineSummary,
        pressure: StatusPresentation,
        manager: StatusPresentation
    ) -> String {
        let openClaw = summary.openClaw.available ? "OpenClaw 已发现" : "机器监控模式"
        let managerLine = "Manager \(manager.label)"
        let interfaceLine = summary.network.primaryInterface ?? "未识别接口"
        let trafficLine = "↓ \(formatByteRate(summary.network.receivedBytesPerSec)) · ↑ \(formatByteRate(summary.network.sentBytesPerSec))"
        return "\(openClaw) · 内存 \(pressure.label) · \(managerLine) · \(interfaceLine) · \(trafficLine)"
    }
}

private struct HeaderMonitorTrendChip: View {
    var title: String
    var value: String
    var detail: String
    var values: [Double]
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.74))
                Spacer(minLength: 0)
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            TrendSparkline(values: values, accent: accent)
                .frame(height: 34)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.66))
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct OverviewSection: View {
    @ObservedObject var store: NativeAppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLead(
                title: "总览",
                detail: ""
            )

            let readiness = readinessPresentation(runtime: store.runtime)
            let diagnostics = diagnosticsPresentation(summary: store.supportSummary)
            let accent = overviewAccent

            GridCard(title: "当前状态", systemImage: "scope", accent: accent) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(overviewHeadline)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(NativePalette.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(overviewDetail)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    AdaptiveLine(spacing: 18) {
                        InlineStatusColumn(
                            title: "切换准备度",
                            value: readiness.label,
                            detail: store.runtime.map { "健康 \($0.switching.healthyProfiles) / 总数 \($0.switching.totalProfiles)" } ?? "等待状态",
                            accent: readiness.tint
                        )
                        InlineStatusColumn(
                            title: "自动巡检",
                            value: store.automation?.enabled == true ? "已开启" : "已暂停",
                            detail: store.automation.map { "窗口 \(formatProbeWindow(minMs: $0.probeIntervalMinMs, maxMs: $0.probeIntervalMaxMs))" } ?? "等待状态",
                            accent: store.automation?.enabled == true ? NativePalette.accent : NativePalette.amber
                        )
                        InlineStatusColumn(
                            title: "稳定性判断",
                            value: diagnostics.label,
                            detail: store.supportSummary.map { "Discord \(supportStatusPresentation($0.discord.status).label) · 环境 \(riskPresentation($0.environment.riskLevel).label)" } ?? "等待状态",
                            accent: diagnostics.tint
                        )
                    }

                    CalloutBlock(
                        label: "下一步",
                        value: overviewNextStep,
                        detail: nil
                    )
                }
            }

            GridCard(title: "摘要", systemImage: "list.bullet.rectangle", accent: NativePalette.mint) {
                TwoColumnFacts(items: overviewSummaryItems)
            }
        }
    }

    private var overviewHeadline: String {
        if let supportSummary = store.supportSummary {
            if !supportSummary.maintenance.config.valid {
                return "先修本地配置，再看运行状态。"
            }
            if let serviceIssue = supportSummary.maintenance.gatewayService.issue, !serviceIssue.isEmpty {
                return "Gateway 服务需要先处理。"
            }
            if !supportSummary.gateway.reachable {
                return gatewayDiagnosis(summary: supportSummary).headline
            }
            if supportSummary.discord.status == "offline" {
                return "连接已经掉线，先恢复本地连通。"
            }
        }

        if let runtime = store.runtime {
            if runtime.switching.healthyProfiles >= 2 {
                return "本地运行稳定，可以继续自动切换。"
            }
            if runtime.switching.healthyProfiles == 1 {
                return "当前还能运行，但切换余量不足。"
            }
            return "当前没有可稳定接管的健康账号。"
        }

        return "正在读取本地状态。"
    }

    private var overviewDetail: String {
        if let supportSummary = store.supportSummary {
            if !supportSummary.maintenance.config.valid {
                return supportSummary.maintenance.config.detail
            }
            if let serviceIssue = supportSummary.maintenance.gatewayService.issue, !serviceIssue.isEmpty {
                return present(supportSummary.maintenance.gatewayService.recommendation, fallback: serviceIssue)
            }
            if !supportSummary.gateway.reachable {
                return gatewayDiagnosis(summary: supportSummary).detail
            }
        }

        if let runtime = store.runtime {
            return "当前账号 \(store.activeProfile?.name ?? "未激活") · 推荐 \(store.recommendedProfile?.name ?? "暂无推荐") · 最近切换 \(formatMillis(runtime.switching.lastActivationDurationMs))"
        }

        return "daemon 还在返回账号池、检查结果和诊断摘要。"
    }

    private var overviewNextStep: String {
        primaryRecommendation(summary: store.supportSummary)
    }

    private var overviewAccent: Color {
        if let supportSummary = store.supportSummary {
            if !supportSummary.maintenance.config.valid || !supportSummary.gateway.reachable || supportSummary.discord.status == "offline" || supportSummary.environment.riskLevel == "high" {
                return NativePalette.rose
            }
            if supportSummary.environment.riskLevel == "watch" {
                return NativePalette.amber
            }
        }

        guard let runtime = store.runtime else {
            return NativePalette.amber
        }

        return runtime.switching.healthyProfiles >= 2 ? NativePalette.mint : NativePalette.amber
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
                ("下一次检查", formatDate(runtime.daemon.nextProbeAt)),
                ("Daemon", runtime.daemon.loopRunning ? "执行中" : runtime.daemon.loopScheduled ? "已驻留" : "等待启动")
            ]
        }

        if let supportSummary = store.supportSummary {
            items += [
                ("Discord", supportStatusPresentation(supportSummary.discord.status).label),
                ("环境因素", riskPresentation(supportSummary.environment.riskLevel).label),
                ("Watchdog", supportSummary.watchdog.statusLine),
                ("最近断线", formatDate(supportSummary.discord.lastDisconnectAt))
            ]
        }

        return items
    }
}

private struct MonitorSection: View {
    @ObservedObject var store: NativeAppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLead(
                title: "监控",
                detail: ""
            )

            if let summary = store.machineSummary {
                let openClaw = openClawAvailabilityPresentation(summary.openClaw)
                let pressure = machinePressurePresentation(summary.memory.pressure)
                let manager = processRunningPresentation(summary.processes.manager)

                GridCard(title: "当前判断", systemImage: "waveform.path.ecg", accent: monitorAccent(summary)) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(monitorHeadline(summary))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(NativePalette.ink)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(monitorDetail(summary))
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        AdaptiveLine(spacing: 18) {
                            InlineStatusColumn(
                                title: "OpenClaw",
                                value: openClaw.label,
                                detail: summary.openClaw.path ?? "当前没有发现 CLI",
                                accent: openClaw.tint
                            )
                            InlineStatusColumn(
                                title: "内存状态",
                                value: pressure.label,
                                detail: "当前压力 \(summary.memory.pressurePercent)% · 已用 Swap \(summary.swap.usedPercent)%",
                                accent: pressure.tint
                            )
                            InlineStatusColumn(
                                title: "Manager",
                                value: manager.label,
                                detail: processSummary(summary.processes.manager),
                                accent: manager.tint
                            )
                        }

                        CalloutBlock(
                            label: "下一步",
                            value: monitorNextStep(summary),
                            detail: nil
                        )

                        AdaptiveLine(spacing: 10) {
                            ActionButton("刷新监控", systemImage: "arrow.clockwise", busy: store.isBusy("monitor:refresh")) {
                                store.refreshAll(silent: false, scope: .monitorOnly, busyKey: "monitor:refresh")
                            }
                        }
                    }
                }

                GridCard(
                    title: "动态趋势",
                    subtitle: "最近 \(max(store.machineHistory.count, 1)) 个采样点",
                    systemImage: "chart.line.uptrend.xyaxis",
                    accent: NativePalette.accent
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        AdaptiveLine(spacing: 12) {
                            TrendTile(
                                title: "CPU",
                                value: "\(summary.cpu.activePercent)%",
                                caption: "User \(summary.cpu.userPercent)% · Sys \(summary.cpu.systemPercent)%",
                                values: store.machineHistory.map(\.cpuActivePercent),
                                accent: NativePalette.accent
                            )
                            TrendTile(
                                title: "内存压力",
                                value: "\(summary.memory.pressurePercent)%",
                                caption: "Wired + Active",
                                values: store.machineHistory.map(\.memoryPressurePercent),
                                accent: pressure.tint
                            )
                            TrendTile(
                                title: "Swap",
                                value: summary.swap.totalBytes > 0 ? "\(summary.swap.usedPercent)%" : "未启用",
                                caption: summary.swap.totalBytes > 0 ? "已用 \(formatBytes(summary.swap.usedBytes))" : "当前没有分配 swap",
                                values: store.machineHistory.map(\.swapUsedPercent),
                                accent: summary.swap.usedPercent >= 5 ? NativePalette.amber : NativePalette.accent
                            )
                        }

                        AdaptiveLine(spacing: 12) {
                            TrendTile(
                                title: "下载",
                                value: formatByteRate(summary.network.receivedBytesPerSec),
                                caption: summary.network.primaryInterface ?? "未识别接口",
                                values: store.machineHistory.map(\.receivedBytesPerSec),
                                accent: NativePalette.mint
                            )
                            TrendTile(
                                title: "上传",
                                value: formatByteRate(summary.network.sentBytesPerSec),
                                caption: summary.network.primaryInterface ?? "未识别接口",
                                values: store.machineHistory.map(\.sentBytesPerSec),
                                accent: NativePalette.accent
                            )
                        }
                    }
                }

                GridCard(title: "实时指标", systemImage: "gauge.with.dots.needle.67percent", accent: NativePalette.mint) {
                    VStack(alignment: .leading, spacing: 12) {
                        AdaptiveLine(spacing: 12) {
                            MetricTile(
                                title: "CPU",
                                value: "\(summary.cpu.activePercent)%",
                                caption: "User \(summary.cpu.userPercent)% · Sys \(summary.cpu.systemPercent)% · Idle \(summary.cpu.idlePercent)%",
                                accent: NativePalette.accent
                            )
                            MetricTile(
                                title: "内存压力",
                                value: "\(summary.memory.pressurePercent)%",
                                caption: "Wired \(formatBytes(summary.memory.wiredBytes)) + Active \(formatBytes(summary.memory.activeBytes))",
                                accent: pressure.tint
                            )
                            MetricTile(
                                title: "Swap",
                                value: summary.swap.totalBytes > 0 ? "\(summary.swap.usedPercent)%" : "未启用",
                                caption: summary.swap.totalBytes > 0
                                    ? "已用 \(formatBytes(summary.swap.usedBytes)) / \(formatBytes(summary.swap.totalBytes))"
                                    : "当前没有分配 swap",
                                accent: summary.swap.usedPercent >= 5 ? NativePalette.amber : NativePalette.accent
                            )
                        }

                        MemoryStructurePanel(
                            summary: summary.memory,
                            accent: pressure.tint
                        )

                        AdaptiveLine(spacing: 12) {
                            MetricTile(
                                title: "磁盘剩余",
                                value: formatBytes(summary.disk.freeBytes),
                                caption: "\(URL(fileURLWithPath: summary.disk.path).lastPathComponent) · 已用 \(summary.disk.usedPercent)%",
                                accent: summary.disk.usedPercent >= 90 ? NativePalette.rose : NativePalette.mint
                            )
                            MetricTile(
                                title: "下载",
                                value: formatByteRate(summary.network.receivedBytesPerSec),
                                caption: "\(summary.network.primaryInterface ?? "未识别接口") · 总收 \(formatBytes(summary.network.totalReceivedBytes))",
                                accent: NativePalette.mint
                            )
                            MetricTile(
                                title: "上传",
                                value: formatByteRate(summary.network.sentBytesPerSec),
                                caption: "\(summary.network.primaryInterface ?? "未识别接口") · 总发 \(formatBytes(summary.network.totalSentBytes))",
                                accent: NativePalette.accent
                            )
                        }
                    }
                }

                GridCard(title: "进程与入口", systemImage: "server.rack", accent: NativePalette.amber) {
                    TwoColumnFacts(items: [
                        ("OpenClaw CLI", summary.openClaw.path ?? "未发现"),
                        ("发现来源", openClawSource(summary.openClaw.source)),
                        ("Manager", processSummary(summary.processes.manager)),
                        ("Watchdog", processSummary(summary.processes.watchdog)),
                        ("采样时间", formatDate(summary.collectedAt)),
                        ("网络接口", summary.network.primaryInterface ?? "未识别"),
                        ("Manager CPU", formatCPUPercent(summary.processes.manager.cpuPercent)),
                        ("Manager RSS", formatBytes(summary.processes.manager.rssBytes))
                    ])
                }

                GridCard(
                    title: "占用前10",
                    subtitle: "按 CPU 排序，点一行打开活动监视器，再按 PID 继续查",
                    systemImage: "list.number",
                    accent: NativePalette.amber
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        AdaptiveLine(spacing: 10) {
                            ActionButton("打开活动监视器", systemImage: "arrow.up.forward.app", busy: false) {
                                store.openActivityMonitor()
                            }
                        }

                        if summary.topProcesses.isEmpty {
                            Text("当前没有可显示的进程采样。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(summary.topProcesses.enumerated()), id: \.element.id) { index, process in
                                ProcessLeaderboardRow(rank: index + 1, process: process) {
                                    store.openActivityMonitor()
                                }
                            }
                        }
                    }
                }
            } else {
                GridCard(title: "监控", systemImage: "waveform.path.ecg") {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("正在读取机器状态。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func monitorHeadline(_ summary: MachineSummary) -> String {
        if !summary.openClaw.available {
            return "当前没发现 OpenClaw，已退到机器监控模式。"
        }
        if summary.memory.pressure == "high" {
            return "当前内存压力偏高，先稳住系统再让 OpenClaw 常驻。"
        }
        if summary.swap.usedPercent >= 80 {
            return "当前内存压力不高，但 swap 占用还留得比较多。"
        }
        if !summary.processes.manager.running {
            return "OpenClaw 已发现，但 manager 没在运行。"
        }
        return "机器状态稳定，可以继续后台运行。"
    }

    private func monitorDetail(_ summary: MachineSummary) -> String {
        if !summary.openClaw.available {
            return "这里会持续显示 CPU、内存、swap、磁盘、网络和守护进程状态。"
        }
        if !summary.processes.manager.running {
            return "CLI 已发现，但当前 app 内 daemon 没跑起来。通常重开 app 就能恢复。"
        }
        if summary.memory.pressure == "high" {
            return "内存压力 \(summary.memory.pressurePercent)% · Swap \(summary.swap.usedPercent)% · 磁盘剩余 \(formatBytes(summary.disk.freeBytes))"
        }
        if summary.swap.usedPercent >= 80 {
            return "当前压力 \(summary.memory.pressurePercent)% · 已用 Swap \(summary.swap.usedPercent)% 。这更像历史挤压残留，不一定代表现在正在卡。"
        }
        return "CPU \(summary.cpu.activePercent)% · 压力 \(summary.memory.pressurePercent)% · 下载 \(formatByteRate(summary.network.receivedBytesPerSec))"
    }

    private func monitorNextStep(_ summary: MachineSummary) -> String {
        if !summary.openClaw.available {
            return "当前先把这里当作机器监控面板。需要接入时，再安装或补齐 OpenClaw CLI。"
        }
        if !summary.processes.manager.running {
            return "先重开 app，让本地 manager daemon 拉起来，再回来看状态。"
        }
        if summary.memory.pressure == "high" {
            return "这台机器当前真的在吃内存，先关掉高占用进程，再让 OpenClaw 常驻。"
        }
        if summary.swap.usedPercent >= 80 {
            return "如果机器没有明显卡顿，可以先继续观察；只有 swap 继续上涨或同时出现卡顿时，再处理高占用进程。"
        }
        if summary.swap.usedPercent >= 25 {
            return "这台机器近期吃过一段 swap，但当前压力不算高，先观察一会儿再决定要不要清进程。"
        }
        return "当前机器负载可接受，可以继续保持后台运行。"
    }

    private func monitorAccent(_ summary: MachineSummary) -> Color {
        if summary.memory.pressure == "high" {
            return NativePalette.rose
        }
        if !summary.openClaw.available || !summary.processes.manager.running || summary.memory.pressure == "watch" {
            return NativePalette.amber
        }
        return NativePalette.mint
    }

    private func processSummary(_ snapshot: MachineSummary.ProcessGroup.Snapshot) -> String {
        guard snapshot.running else {
            return "未运行"
        }
        return [
            snapshot.pid.map { "PID \($0)" },
            snapshot.cpuPercent.map { "CPU \(formatCPUPercent($0))" },
            snapshot.rssBytes.map { "RSS \(formatBytes($0))" },
            snapshot.uptimeSeconds.map { "已运行 \(formatUptimeSeconds($0))" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func openClawSource(_ value: String) -> String {
        switch value {
        case "env":
            return "环境变量"
        case "local":
            return "~/.local/bin"
        case "path":
            return "PATH"
        default:
            return "未发现"
        }
    }
}

private struct ProcessLeaderboardRow: View {
    var rank: Int
    var process: MachineSummary.TopProcess
    var action: () -> Void

    private var accent: Color {
        if process.cpuPercent >= 50 {
            return NativePalette.rose
        }
        if process.cpuPercent >= 20 {
            return NativePalette.amber
        }
        return NativePalette.mint
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.14))
                        .frame(width: 34, height: 34)
                    Text("\(rank)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(process.name)
                            .font(.headline)
                            .foregroundStyle(NativePalette.ink)
                            .lineLimit(1)
                        Text("PID \(process.pid)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(formatCPUPercent(process.cpuPercent))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(accent.opacity(0.14))
                            )
                    }

                    AdaptiveLine(spacing: 10) {
                        ProcessMetricPill(
                            label: "内存",
                            value: formatBytes(process.rssBytes),
                            accent: NativePalette.accent
                        )
                        ProcessMetricPill(
                            label: "运行时长",
                            value: formatUptimeSeconds(process.uptimeSeconds),
                            accent: NativePalette.mint
                        )
                    }

                    Text(process.command)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
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
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ProfilesSection: View {
    @ObservedObject var store: NativeAppStore
    @State private var newProfileName = ""
    @State private var showRawProfileConfig = false
    @State private var showPreviewProfileConfig = false
    @State private var profileConfigProviderId = ""
    @State private var profileConfigModelId = ""
    @State private var profileConfigAuthMode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLead(
                title: "账号池",
                detail: ""
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
                    detail: present(store.recommendedProfile?.statusReason, fallback: "等待状态"),
                    systemImage: "sparkles.rectangle.stack",
                    accent: NativePalette.accent
                )
                InsightTile(
                    title: "账号池规模",
                    value: "\(store.profiles.count) 个槽位",
                    detail: store.runtime.map { "健康 \($0.switching.healthyProfiles) · 风险 \($0.switching.riskyProfiles)" } ?? "等待状态",
                    systemImage: "person.3.sequence",
                    accent: NativePalette.amber
                )
            }

            GridCard(title: "新建账号", systemImage: "plus.circle", accent: NativePalette.accent) {
                AdaptiveLine(spacing: 12) {
                    TextField("账号名称", text: $newProfileName)
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
            GridCard(title: "登录", systemImage: "person.crop.circle.badge.checkmark", accent: NativePalette.amber) {
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
                GridCard(title: "当前账号", systemImage: "viewfinder.circle", accent: statusPresentation(for: spotlight.status).tint) {
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
                                    title: "5 小时剩余",
                                    value: quotaValue(spotlight.quota.fiveHour),
                                    label: spotlight.quota.fiveHour.map { "\($0.leftPercent)%" } ?? "未提供",
                                    caption: formatDuration(ms: spotlight.quota.fiveHour?.resetInMs),
                                    tint: NativePalette.accent
                                )
                                spotlightGauge(
                                    title: "本周剩余",
                                    value: quotaValue(spotlight.quota.week),
                                    label: spotlight.quota.week.map { "\($0.leftPercent)%" } ?? "未提供",
                                    caption: formatDuration(ms: spotlight.quota.week?.resetInMs),
                                    tint: NativePalette.mint
                                )
                            }
                        }

                        TwoColumnFacts(items: [("状态说明", spotlight.statusReason)] + profileFactItems(spotlight))
                        if spotlight.tokenExpiresInMs != nil || spotlight.tokenExpiresAt != nil {
                            CalloutBlock(
                                label: "认证说明",
                                value: "这里只显示当前登录令牌",
                                detail: "不是账号套餐时效；真正可用额度看上面的 5 小时剩余和本周剩余。"
                            )
                        }

                        AdaptiveLine(spacing: 10) {
                                if spotlight.supportsLogin, let loginLabel = loginActionLabel(spotlight.loginKind) {
                                    ActionButton(loginLabel, systemImage: "person.badge.key", busy: store.isBusy("login:\(spotlight.name)")) {
                                        store.login(profileName: spotlight.name)
                                    }
                                }
                            ActionButton("检查这个账号", systemImage: "scope", busy: store.isBusy("probe:\(spotlight.name)")) {
                                store.probe(profileName: spotlight.name)
                            }
                            ActionButton("切到这个账号", systemImage: "arrow.triangle.swap", busy: store.isBusy("activate:\(spotlight.name)")) {
                                store.activate(profileName: spotlight.name)
                            }
                            .disabled(spotlight.isActive)
                        }
                    }
                }

                GridCard(
                    title: "OpenClaw 配置",
                    systemImage: "doc.badge.gearshape",
                    accent: profileConfigAccent(store.openClawProfileConfigDocument, profileName: spotlight.name)
                ) {
                    if let document = store.openClawProfileConfigDocument, document.summary.profileName == spotlight.name {
                        let summary = document.summary
                        let currentProviderId = summary.primaryProviderId ?? ""
                        let currentModelId = summary.primaryModelId ?? ""
                        let currentAuthMode = resolvedProfileAuthMode(summary)
                        let trimmedDraftProviderId = profileConfigProviderId.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedDraftModelId = profileConfigModelId.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedDraftAuthMode = profileConfigAuthMode.trimmingCharacters(in: .whitespacesAndNewlines)
                        let configDraftReady = !trimmedDraftProviderId.isEmpty && !trimmedDraftModelId.isEmpty && !trimmedDraftAuthMode.isEmpty
                        let configDraftChanged = trimmedDraftProviderId != currentProviderId || trimmedDraftModelId != currentModelId || trimmedDraftAuthMode != currentAuthMode
                        let preview = store.openClawProfileConfigPreview?.profileName == spotlight.name ? store.openClawProfileConfigPreview : nil
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("状态")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(configValidationPresentation(summary.configValid).label)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(configValidationPresentation(summary.configValid).tint)
                                Text(summary.configDetail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            TwoColumnFacts(items: [
                                ("配置文件", summary.configPath),
                                ("配置更新时间", formatDate(summary.configUpdatedAt)),
                                ("认证文件", summary.authStorePath),
                                ("认证更新时间", formatDate(summary.authStoreUpdatedAt)),
                                ("主 Provider", present(summary.primaryProviderId, fallback: "未识别")),
                                ("主模型", present(summary.primaryModelId, fallback: "未识别")),
                                ("认证模式", currentAuthMode),
                                ("登录能力", present(summary.loginKind, fallback: "未识别")),
                                ("伴随运行时", present(summary.companionRuntimeKind, fallback: "未识别")),
                                ("认证文件状态", summary.authStoreValid ? "可读" : summary.authStoreDetail)
                            ])

                            if summary.configValid, document.configHash != nil {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text("受控编辑")
                                            .font(.headline)
                                        if configDraftChanged {
                                            TonePill(text: "有未保存变更", tint: NativePalette.amber.opacity(0.18), foreground: NativePalette.amber)
                                        }
                                        if !spotlight.isActive {
                                            TonePill(text: "未激活，切换后生效", tint: NativePalette.accent.opacity(0.18), foreground: NativePalette.accent)
                                        }
                                    }

                                    Text(profileConfigEditorIntro(profileName: spotlight.name, appliesNow: spotlight.isActive))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if !spotlight.isActive {
                                        CalloutBlock(
                                            label: "写入范围",
                                            value: "只改 \(spotlight.name) 的账号文件",
                                            detail: "不会立刻切换账号；下次切到这个账号时，才会按这里的配置运行。"
                                        )
                                    }

                                    AdaptiveLine(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("主 Provider")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            TextField("例如 openai-codex", text: $profileConfigProviderId)
                                                .textFieldStyle(.roundedBorder)
                                        }
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("主模型")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            TextField("例如 openai-codex/gpt-5", text: $profileConfigModelId)
                                                .textFieldStyle(.roundedBorder)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("认证模式")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        TextField("例如 chatgpt-oauth / api-key / configured", text: $profileConfigAuthMode)
                                            .textFieldStyle(.roundedBorder)
                                    }

                                    Text("如果你改了 Provider，主模型前缀也要一起对应；否则预览会直接拦下。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    AdaptiveLine(spacing: 10) {
                                        ActionButton(profileConfigPreviewButtonTitle(appliesNow: spotlight.isActive), systemImage: "eye", busy: store.isBusy("profile-config:preview:\(spotlight.name)")) {
                                            guard let configHash = document.configHash else { return }
                                            store.previewProfileConfig(
                                                profileName: spotlight.name,
                                                request: OpenClawProfileConfigEditRequest(
                                                    baseHash: configHash,
                                                    patch: OpenClawProfileConfigPatch(
                                                        primaryProviderId: trimmedDraftProviderId,
                                                        primaryModelId: trimmedDraftModelId,
                                                        authMode: trimmedDraftAuthMode
                                                    )
                                                )
                                            )
                                        }
                                        .disabled(!configDraftReady)

                                        ActionButton(profileConfigApplyButtonTitle(appliesNow: spotlight.isActive), systemImage: "checkmark.circle", busy: store.isBusy("profile-config:apply:\(spotlight.name)")) {
                                            guard let configHash = document.configHash else { return }
                                            store.applyProfileConfig(
                                                profileName: spotlight.name,
                                                request: OpenClawProfileConfigEditRequest(
                                                    baseHash: configHash,
                                                    patch: OpenClawProfileConfigPatch(
                                                        primaryProviderId: trimmedDraftProviderId,
                                                        primaryModelId: trimmedDraftModelId,
                                                        authMode: trimmedDraftAuthMode
                                                    )
                                                )
                                            )
                                        }
                                        .disabled(preview == nil || preview?.changed != true)

                                        Button("还原草稿") {
                                            profileConfigProviderId = currentProviderId
                                            profileConfigModelId = currentModelId
                                            profileConfigAuthMode = currentAuthMode
                                            store.clearProfileConfigPreview()
                                        }
                                        .buttonStyle(NativeSecondaryButtonStyle())
                                        .disabled(!configDraftChanged)
                                    }

                                    if let preview {
                                        CalloutBlock(
                                            label: "变更预览",
                                            value: profileConfigPreviewSummary(changed: preview.changed, changeCount: preview.changes.count, appliesNow: spotlight.isActive),
                                            detail: preview.message
                                        )

                                        if !preview.changes.isEmpty {
                                            ForEach(preview.changes) { change in
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text(change.label)
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(.secondary)
                                                    Text("\(change.before) -> \(change.after)")
                                                        .font(.callout)
                                                        .foregroundStyle(NativePalette.ink)
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

                                        Button {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                showPreviewProfileConfig.toggle()
                                            }
                                        } label: {
                                            Label(showPreviewProfileConfig ? "收起预览配置" : "展开预览配置", systemImage: showPreviewProfileConfig ? "chevron.up" : "chevron.down")
                                        }
                                        .buttonStyle(NativeSecondaryButtonStyle())

                                        if showPreviewProfileConfig {
                                            ConfigCodeBlock(title: "预览 openclaw.json", text: preview.previewConfig)
                                        }
                                    }
                                }
                            } else {
                                CalloutBlock(
                                    label: "受控编辑",
                                    value: "当前不能直接编辑",
                                    detail: "先把这个账号的 openclaw.json 修到可解析，再用这里预览和写入。"
                                )
                            }

                            AdaptiveLine(spacing: 10) {
                                ActionButton("刷新配置", systemImage: "arrow.clockwise", busy: store.isBusy("settings:refresh")) {
                                    store.refreshAll(silent: false, scope: .settingsOnly, busyKey: "settings:refresh")
                                }
                                ActionButton("校验这个配置", systemImage: "checklist", busy: store.isBusy("profile-config:validate:\(spotlight.name)")) {
                                    store.validateProfileConfig(profileName: spotlight.name)
                                }
                                Button("打开配置文件") {
                                    store.open(URL(fileURLWithPath: summary.configPath))
                                }
                                .buttonStyle(NativeSecondaryButtonStyle())
                                Button("打开认证文件") {
                                    store.open(URL(fileURLWithPath: summary.authStorePath))
                                }
                                .buttonStyle(NativeSecondaryButtonStyle())
                            }

                            if let validation = store.openClawProfileConfigValidation, validation.profileName == spotlight.name {
                                CalloutBlock(
                                    label: "最近校验",
                                    value: configValidationPresentation(validation.valid).label,
                                    detail: profileConfigValidationDetail(validation)
                                )
                            }

                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    showRawProfileConfig.toggle()
                                }
                            } label: {
                                Label(showRawProfileConfig ? "收起原始内容" : "展开原始内容", systemImage: showRawProfileConfig ? "chevron.up" : "chevron.down")
                            }
                            .buttonStyle(NativeSecondaryButtonStyle())

                            if showRawProfileConfig {
                                ConfigCodeBlock(title: "openclaw.json", text: document.rawConfig)
                                ConfigCodeBlock(title: "auth-profiles.json", text: document.rawAuthStore)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("等待读取 \(spotlight.name) 的配置摘要。")
                                .foregroundStyle(.secondary)
                            ActionButton("读取配置", systemImage: "arrow.clockwise", busy: store.isBusy("settings:refresh")) {
                                store.refreshAll(silent: false, scope: .settingsOnly, busyKey: "settings:refresh")
                            }
                        }
                    }
                }
            }

            if !store.profiles.isEmpty {
                GridCard(title: "切换", systemImage: "line.3.horizontal.decrease.circle", accent: NativePalette.amber) {
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
                GridCard(title: "没有账号", systemImage: "tray", accent: NativePalette.amber) {
                    Text("先创建账号。")
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
        .onAppear {
            syncProfileConfigDraft()
        }
        .onChange(of: store.selectedProfileName) { _ in
            syncProfileConfigDraft()
        }
        .onChange(of: store.openClawProfileConfigDocument?.configHash) { _ in
            syncProfileConfigDraft()
        }
        .onChange(of: profileConfigProviderId) { _ in
            store.clearProfileConfigPreview()
        }
        .onChange(of: profileConfigModelId) { _ in
            store.clearProfileConfigPreview()
        }
        .onChange(of: profileConfigAuthMode) { _ in
            store.clearProfileConfigPreview()
        }
    }

    private func syncProfileConfigDraft() {
        guard let document = store.openClawProfileConfigDocument else {
            profileConfigProviderId = ""
            profileConfigModelId = ""
            profileConfigAuthMode = ""
            showPreviewProfileConfig = false
            return
        }

        let summary = document.summary
        profileConfigProviderId = summary.primaryProviderId ?? ""
        profileConfigModelId = summary.primaryModelId ?? ""
        profileConfigAuthMode = resolvedProfileAuthMode(summary)
        showPreviewProfileConfig = false
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
            subtitle: present(profile.statusReason, fallback: "等待首次检查完成"),
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
                            title: "5 小时剩余",
                            value: quotaValue(profile.quota.fiveHour),
                            label: profile.quota.fiveHour.map { "\($0.leftPercent)%" } ?? "未提供",
                            caption: formatDuration(ms: profile.quota.fiveHour?.resetInMs),
                            tint: NativePalette.accent
                        )
                        quotaGauge(
                            title: "本周剩余",
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
                    if profile.supportsLogin, let loginLabel = loginActionLabel(profile.loginKind) {
                        ActionButton(loginLabel, systemImage: "person.badge.key", busy: store.isBusy("login:\(profile.name)")) {
                            store.login(profileName: profile.name)
                        }
                    }
                    ActionButton("检查", systemImage: "scope", busy: store.isBusy("probe:\(profile.name)")) {
                        store.probe(profileName: profile.name)
                    }
                    ActionButton("切换", systemImage: "arrow.triangle.swap", busy: store.isBusy("activate:\(profile.name)")) {
                        store.activate(profileName: profile.name)
                    }
                    .disabled(profile.isActive)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isSelected ? NativePalette.borderStrong : Color.clear, lineWidth: 1)
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

private func profileConfigAccent(_ document: OpenClawProfileConfigDocument?, profileName: String) -> Color {
    guard let document, document.summary.profileName == profileName else {
        return NativePalette.surfaceAlt
    }
    return configValidationPresentation(document.summary.configValid).tint
}

private func authModeSummary(_ authModes: [String: String]) -> String {
    if authModes.isEmpty {
        return "未识别"
    }
    return authModes
        .sorted { $0.key < $1.key }
        .map { "\($0.key): \($0.value)" }
        .joined(separator: " · ")
}

private func resolvedProfileAuthMode(_ summary: OpenClawProfileConfigSummary) -> String {
    if let provider = summary.primaryProviderId, let mode = summary.authModes[provider], !mode.isEmpty {
        return mode
    }
    if summary.primaryProviderId == "openai-codex" {
        return "chatgpt-oauth"
    }
    return "configured"
}

private func profileConfigEditorIntro(profileName: String, appliesNow: Bool) -> String {
    if appliesNow {
        return "只开放主模型、主 Provider、认证模式这三项。先预览，再应用；应用后会立刻校验，不通过就回滚。"
    }
    return "只开放主模型、主 Provider、认证模式这三项。这里先改 \(profileName) 的账号文件；通过预览后写入，等你切到这个账号时再生效。"
}

private func profileConfigPreviewButtonTitle(appliesNow: Bool) -> String {
    appliesNow ? "预览变更" : "预览写入"
}

private func profileConfigApplyButtonTitle(appliesNow: Bool) -> String {
    appliesNow ? "应用配置" : "写入账号"
}

private func profileConfigPreviewSummary(changed: Bool, changeCount: Int, appliesNow: Bool) -> String {
    guard changed else { return "没有变化" }
    if appliesNow {
        return "准备应用 \(changeCount) 项变更"
    }
    return "准备写入 \(changeCount) 项变更"
}

private func boolLabel(_ value: Bool?) -> String {
    guard let value else { return "未配置" }
    return value ? "开启" : "关闭"
}

private func skillsInstallPreferBrewSummary(_ value: Bool?) -> String {
    guard let value else { return "未配置" }
    return value ? "优先 Homebrew" : "不优先 Homebrew"
}

private func skillsInstallPreferBrewMode(_ value: Bool?) -> String {
    guard let value else { return "default" }
    return value ? "prefer-brew" : "prefer-direct"
}

private func skillsInstallPreferBrewValue(_ selection: String) -> Bool? {
    switch selection {
    case "prefer-brew":
        return true
    case "prefer-direct":
        return false
    default:
        return nil
    }
}

private func skillsInstallNodeManagerDraftValue(_ value: String?) -> String {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed
}

private func skillsInstallNodeManagerSummary(_ value: String?) -> String {
    let trimmed = skillsInstallNodeManagerDraftValue(value)
    return trimmed.isEmpty ? "未配置" : trimmed
}

private func skillsInstallNodeManagerOptions(selection: String) -> [String] {
    let common = ["npm", "pnpm", "yarn", "bun"]
    let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || common.contains(trimmed) {
        return common
    }
    return [trimmed] + common
}

private func bundledAllowlistSummary(_ values: [String]) -> String {
    if values.isEmpty {
        return "未限制"
    }
    if values.count <= 3 {
        return values.joined(separator: ", ")
    }
    return "\(values.prefix(3).joined(separator: ", ")) +\(values.count - 3)"
}

private func skillStatusTint(_ skill: OpenClawSkillsSummary.Skill) -> Color {
    switch skill.status {
    case "ready":
        return NativePalette.mint
    case "disabled":
        return NativePalette.surfaceAlt
    case "blocked":
        return NativePalette.rose
    default:
        return NativePalette.amber
    }
}

private func skillStatusLabel(_ skill: OpenClawSkillsSummary.Skill) -> String {
    switch skill.status {
    case "ready":
        return "可用"
    case "disabled":
        return "已禁用"
    case "blocked":
        return "受限"
    default:
        return "缺依赖"
    }
}

private func skillSummaryLine(_ skill: OpenClawSkillsSummary.Skill) -> String {
    let missing = [
        skill.missing.bins.isEmpty ? nil : "缺命令 \(skill.missing.bins.joined(separator: ", "))",
        skill.missing.anyBins.isEmpty ? nil : "缺任一命令 \(skill.missing.anyBins.joined(separator: ", "))",
        skill.missing.env.isEmpty ? nil : "缺环境变量 \(skill.missing.env.joined(separator: ", "))",
        skill.missing.config.isEmpty ? nil : "缺配置 \(skill.missing.config.joined(separator: ", "))",
        skill.primaryEnv
    ].compactMap { value -> String? in
        guard let value, !value.isEmpty else { return nil }
        return value
    }
    if !missing.isEmpty {
        return missing.joined(separator: " · ")
    }
    if let homepage = skill.homepage, !homepage.isEmpty {
        return homepage
    }
    return present(skill.description, fallback: "无附加说明")
}

private func skillsInventorySourceLabel(_ source: String) -> String {
    switch source {
    case "manager-installed":
        return "市场安装"
    case "personal":
        return "本地个人"
    case "workspace":
        return "项目技能"
    case "global":
        return "全局技能"
    case "bundled":
        return "Bundled"
    default:
        return "外部来源"
    }
}

private func skillsInventorySourceTint(_ source: String) -> Color {
    switch source {
    case "manager-installed":
        return NativePalette.accent
    case "personal":
        return NativePalette.mint
    case "workspace":
        return NativePalette.mint
    case "global":
        return NativePalette.amber
    case "bundled":
        return NativePalette.surfaceAlt
    default:
        return NativePalette.rose
    }
}

private func skillsMarketItemCategories(_ item: OpenClawSkillsMarketSummary.Item, categories: [String: String]) -> String {
    let titles = item.categoryIds.compactMap { categories[$0] }
    if !titles.isEmpty {
        if titles.count <= 2 {
            return titles.joined(separator: " · ")
        }
        return "\(titles.prefix(2).joined(separator: " · ")) +\(titles.count - 2)"
    }
    if item.tags.isEmpty {
        return "未分类"
    }
    if item.tags.count <= 3 {
        return item.tags.joined(separator: " · ")
    }
    return "\(item.tags.prefix(3).joined(separator: " · ")) +\(item.tags.count - 3)"
}

private func hasLocalizedMarketSummary(_ item: OpenClawSkillsMarketSummary.Item) -> Bool {
    guard let summaryZh = item.summaryZh?.trimmingCharacters(in: .whitespacesAndNewlines) else {
        return false
    }
    return !summaryZh.isEmpty && summaryZh != item.summary
}

private func skillModerationPresentation(_ moderation: OpenClawSkillMarketDetail.Moderation?) -> (label: String, tint: Color, foreground: Color) {
    guard let moderation else {
        return ("未读取", NativePalette.surfaceAlt, NativePalette.ink)
    }
    if moderation.isMalwareBlocked {
        return ("已拦截", NativePalette.rose, .white)
    }
    if moderation.isSuspicious || moderation.verdict == "suspicious" {
        return ("需复核", NativePalette.amber, .white)
    }
    return ("未见拦截", NativePalette.mint, .white)
}

private func skillRuntimeStatusLabel(_ item: OpenClawSkillsInventory.Item) -> String {
    if let runtimeStatus = item.runtimeStatus, !runtimeStatus.isEmpty {
        switch runtimeStatus {
        case "ready":
            return "运行可用"
        case "disabled":
            return "已禁用"
        case "blocked":
            return "被限制"
        case "missing_requirements":
            return "缺依赖"
        default:
            return runtimeStatus
        }
    }
    return item.visibleInRuntime ? "已加载" : "待刷新"
}

private func normalizedDisplayPath(_ path: String) -> String {
    let expanded = (path as NSString).expandingTildeInPath
    return expanded.isEmpty ? path : expanded
}

private func pathsReferToSameLocation(_ lhs: String, _ rhs: String?) -> Bool {
    guard let rhs else { return false }
    let left = URL(fileURLWithPath: normalizedDisplayPath(lhs)).standardizedFileURL.path
    let right = URL(fileURLWithPath: normalizedDisplayPath(rhs)).standardizedFileURL.path
    return left == right
}

private func skillTogglePresentation(_ item: OpenClawSkillsInventory.Item) -> (label: String, icon: String, enable: Bool) {
    if item.runtimeStatus == "blocked", item.bundled {
        return ("允许并启用", "checkmark.circle", true)
    }
    if item.runtimeStatus == "disabled" || item.enabled == false {
        return ("启用", "checkmark.circle", true)
    }
    return ("停用", "pause.circle", false)
}

private struct SkillsInventoryGroup: Identifiable {
    var id: String
    var title: String
    var detail: String
    var items: [OpenClawSkillsInventory.Item]
}

private enum SkillsWorkspace: String, CaseIterable, Identifiable {
    case market
    case inventory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .market:
            return "浏览市场"
        case .inventory:
            return "本地库存"
        }
    }

    var detail: String {
        switch self {
        case .market:
            return "查找、筛选、安装"
        case .inventory:
            return "查找、分组、卸载"
        }
    }

    var systemImage: String {
        switch self {
        case .market:
            return "sparkles.square.filled.on.square"
        case .inventory:
            return "shippingbox"
        }
    }
}

private func skillsInventoryGroupMeta(for source: String) -> (title: String, detail: String, rank: Int) {
    switch source {
    case "manager-installed":
        return ("市场安装", "可直接卸载", 0)
    case "personal":
        return ("本地个人", "当前机器已有的自定义 skills", 1)
    case "workspace":
        return ("项目技能", "来自当前工作区", 2)
    case "global":
        return ("全局技能", "来自 OpenClaw 全局目录", 3)
    case "external":
        return ("其他来源", "来源未完全识别", 4)
    case "bundled":
        return ("Bundled", "OpenClaw 自带，不建议删除", 5)
    default:
        return (skillsInventorySourceLabel(source), "来源未分类", 6)
    }
}

private struct ConfigCodeBlock: View {
    let title: String
    let text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: true) {
                Text(text ?? "未提供原始内容")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NativePalette.surfaceAlt)
            )
        }
    }
}

private struct SkillsSection: View {
    @ObservedObject var store: NativeAppStore
    @State private var activeWorkspace: SkillsWorkspace = .market
    @State private var marketSearchText = ""
    @State private var marketSort: SkillsMarketSort = .downloads
    @State private var inventorySearchText = ""
    @State private var selectedCategoryID = ""
    @State private var selectedSkillSlug: String?
    @State private var showBundledSkills = false
    @State private var showMarketEnvironment = false
    @State private var showDetailRequirements = false
    @State private var showDetailChangelog = false
    @State private var showDetailOriginalSummary = false
    @State private var expandedInventoryGroups: Set<String> = ["manager-installed", "personal"]
    @State private var marketDisplayLimit = 96
    @State private var marketSearchTask: Task<Void, Never>?

    private var categoryLookup: [String: String] {
        Dictionary(uniqueKeysWithValues: (store.skillsMarketSummary?.categories ?? []).map { ($0.id, $0.title) })
    }

    private var marketLookup: [String: OpenClawSkillsMarketSummary.Item] {
        Dictionary(uniqueKeysWithValues: (store.skillsMarketSummary?.items ?? []).map { ($0.slug, $0) })
    }

    private var inventoryLookup: [String: OpenClawSkillsInventory.Item] {
        Dictionary(uniqueKeysWithValues: (store.skillsInventory?.items ?? []).map { ($0.slug, $0) })
    }

    private var filteredMarketItems: [OpenClawSkillsMarketSummary.Item] {
        guard let items = store.skillsMarketSummary?.items else { return [] }
        return items.filter { item in
            let matchesCategory = selectedCategoryID.isEmpty || item.categoryIds.contains(selectedCategoryID)
            return matchesCategory
        }
    }

    private var baseMarketDisplayLimit: Int {
        (!isMarketSearching && selectedCategoryID.isEmpty) ? 96 : 180
    }

    private var effectiveMarketDisplayLimit: Int {
        max(baseMarketDisplayLimit, marketDisplayLimit)
    }

    private var marketDisplayStep: Int {
        (!isMarketSearching && selectedCategoryID.isEmpty) ? 48 : 60
    }

    private var displayedMarketItems: [OpenClawSkillsMarketSummary.Item] {
        let items = filteredMarketItems
        let limit = effectiveMarketDisplayLimit
        guard items.count > limit else { return items }
        return Array(items.prefix(limit))
    }

    private var isClippingMarketItems: Bool {
        filteredMarketItems.count > displayedMarketItems.count
    }

    private var remainingMarketItemCount: Int {
        max(0, filteredMarketItems.count - displayedMarketItems.count)
    }

    private var filteredInventoryItems: [OpenClawSkillsInventory.Item] {
        guard let items = store.skillsInventory?.items else { return [] }
        let query = inventorySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            if !showBundledSkills && item.source == "bundled" {
                return false
            }
            if query.isEmpty {
                return true
            }
            return
                item.name.lowercased().contains(query) ||
                item.slug.lowercased().contains(query) ||
                item.summary.lowercased().contains(query) ||
                skillsInventorySourceLabel(item.source).lowercased().contains(query)
        }
    }

    private var inventoryGroups: [SkillsInventoryGroup] {
        var grouped: [String: [OpenClawSkillsInventory.Item]] = [:]
        for item in filteredInventoryItems {
            grouped[item.source, default: []].append(item)
        }
        return grouped.map { source, items in
            let meta = skillsInventoryGroupMeta(for: source)
            return SkillsInventoryGroup(
                id: source,
                title: meta.title,
                detail: meta.detail,
                items: items.sorted { left, right in
                    left.name.localizedLowercase < right.name.localizedLowercase
                }
            )
        }
        .sorted { left, right in
            skillsInventoryGroupMeta(for: left.id).rank < skillsInventoryGroupMeta(for: right.id).rank
        }
    }

    private var isInventoryFiltering: Bool {
        !inventorySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedDetail: OpenClawSkillMarketDetail? {
        guard let selectedSkillSlug else { return nil }
        guard let detail = store.skillMarketDetail, detail.item.slug == selectedSkillSlug else { return nil }
        return detail
    }

    private var selectedInventoryItem: OpenClawSkillsInventory.Item? {
        if let selectedSkillSlug {
            return inventoryLookup[selectedSkillSlug]
        }
        return nil
    }

    private var trimmedMarketSearchText: String {
        marketSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isMarketSearching: Bool {
        !trimmedMarketSearchText.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLead(
                title: "技能",
                detail: ""
            )

            skillsWorkbenchCard
            activeWorkspaceContent
        }
        .onAppear {
            resetMarketDisplayLimit()
            syncMarketSelection()
        }
        .onChange(of: store.skillsMarketSummary?.collectedAt) { _ in
            syncMarketSelection()
        }
    }

    private var skillsWorkbenchCard: some View {
        GridCard(title: "技能工作台", systemImage: activeWorkspace.systemImage, accent: NativePalette.accent) {
            VStack(alignment: .leading, spacing: 16) {
                AdaptiveLine(spacing: 14) {
                    InlineStatusColumn(
                        title: "精选市场",
                        value: "\(store.skillsMarketSummary?.totalItems ?? 0) 个",
                        detail: isMarketSearching ? "ClawHub 搜索结果" : "ClawHub \(marketSort.title) 排序",
                        accent: NativePalette.accent
                    )
                    InlineStatusColumn(
                        title: "托管安装",
                        value: "\(store.skillsInventory?.managerInstalled ?? 0) 个",
                        detail: present(store.skillsInventory?.managedDirectory, fallback: "等待库存"),
                        accent: NativePalette.mint
                    )
                    InlineStatusColumn(
                        title: "本地个人",
                        value: "\(store.skillsInventory?.personalInstalled ?? 0) 个",
                        detail: "Bundled \(store.skillsInventory?.bundledInstalled ?? 0) · 总计 \(store.skillsInventory?.totalItems ?? 0)",
                        accent: NativePalette.amber
                    )
                }

                AdaptiveLine(spacing: 10) {
                    ForEach(SkillsWorkspace.allCases) { workspace in
                        workspaceChip(workspace)
                    }
                    Spacer(minLength: 0)
                    ActionButton("刷新技能", systemImage: "arrow.clockwise", busy: store.isBusy("skills:refresh")) {
                        store.refreshAll(silent: false, scope: .skillsOnly, busyKey: "skills:refresh")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var activeWorkspaceContent: some View {
        switch activeWorkspace {
        case .market:
            marketWorkspace
        case .inventory:
            inventoryWorkspace
        }
    }

    private var marketWorkspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            marketControlsCard

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    marketListCard
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    marketDetailCard
                        .frame(width: 380, alignment: .topLeading)
                }
                VStack(alignment: .leading, spacing: 18) {
                    marketDetailCard
                    marketListCard
                }
            }
        }
    }

    private var inventoryWorkspace: some View {
        localInventoryCard
    }

    private func workspaceChip(_ workspace: SkillsWorkspace) -> some View {
        let selected = activeWorkspace == workspace
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                activeWorkspace = workspace
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: workspace.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(workspace.detail)
                        .font(.caption2)
                        .foregroundStyle(selected ? NativePalette.ink.opacity(0.78) : .secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? NativePalette.surfaceRaised : NativePalette.surfaceAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? NativePalette.borderStrong : NativePalette.border, lineWidth: 1)
            )
            .foregroundStyle(selected ? NativePalette.ink : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func categoryChip(title: String, id: String) -> some View {
        let selected = selectedCategoryID == id
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selectedCategoryID = id
            }
            resetMarketDisplayLimit()
            syncMarketSelection()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(selected ? NativePalette.surfaceRaised : NativePalette.surfaceAlt)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(selected ? NativePalette.borderStrong : NativePalette.border, lineWidth: 1)
                )
                .foregroundStyle(selected ? NativePalette.ink : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var marketControlsCard: some View {
        GridCard(title: "浏览与筛选", systemImage: "line.3.horizontal.decrease.circle", accent: NativePalette.accent) {
            VStack(alignment: .leading, spacing: 14) {
                AdaptiveLine(spacing: 12) {
                    TextField("搜索名称、slug 或用途", text: $marketSearchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            triggerMarketSearch(immediate: true)
                        }
                        .onChange(of: marketSearchText) { _ in
                            selectedCategoryID = ""
                            resetMarketDisplayLimit()
                            scheduleMarketSearch()
                        }
                    Picker("排序", selection: $marketSort) {
                        ForEach(SkillsMarketSort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .onChange(of: marketSort) { _ in
                        selectedCategoryID = ""
                        resetMarketDisplayLimit()
                        triggerMarketSearch(immediate: true)
                    }
                    if isMarketSearching {
                        Button("清空") {
                            marketSearchText = ""
                            selectedCategoryID = ""
                            resetMarketDisplayLimit()
                            triggerMarketSearch(immediate: true)
                        }
                        .buttonStyle(NativeSecondaryButtonStyle())
                    }
                    if let managedDirectory = store.skillsInventory?.managedDirectory {
                        Button("打开托管目录") {
                            store.open(URL(fileURLWithPath: managedDirectory))
                        }
                        .buttonStyle(NativeSecondaryButtonStyle())
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        categoryChip(title: "全部", id: "")
                        ForEach(store.skillsMarketSummary?.categories ?? []) { category in
                            categoryChip(title: "\(category.title) \(category.count)", id: category.id)
                        }
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    Text(isMarketSearching
                        ? "ClawHub 搜索返回 \(filteredMarketItems.count) 项"
                        : "当前列表 \(filteredMarketItems.count) 项，按 \(marketSort.title) 排序")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(isClippingMarketItems
                        ? "当前先显示 \(displayedMarketItems.count) / \(filteredMarketItems.count) 项，可继续展开"
                        : "支持粘贴后直接回车搜索")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup(isExpanded: $showMarketEnvironment) {
                    VStack(alignment: .leading, spacing: 12) {
                        TwoColumnFacts(items: [
                            ("市场来源", present(store.skillsMarketSummary?.sourceRepo)),
                            ("配置文件", present(store.openClawSkillsConfig?.configPath)),
                            ("托管目录", present(store.skillsInventory?.managedDirectory)),
                            ("库存文件", present(store.skillsInventory?.lockPath)),
                            ("Bundled 白名单", bundledAllowlistSummary(store.openClawSkillsConfig?.allowBundled ?? [])),
                            ("额外挂载目录", "\(store.openClawSkillsConfig?.extraDirs.count ?? 0)")
                        ])

                        AdaptiveLine(spacing: 10) {
                            if let configPath = store.openClawSkillsConfig?.configPath {
                                Button("打开配置文件") {
                                    store.open(URL(fileURLWithPath: configPath))
                                }
                                .buttonStyle(NativeSecondaryButtonStyle())
                            }
                            if let managedDirectory = store.skillsInventory?.managedDirectory {
                                Button("打开库存文件夹") {
                                    store.open(URL(fileURLWithPath: managedDirectory))
                                }
                                .buttonStyle(NativeSecondaryButtonStyle())
                            }
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    Text("环境与来源")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NativePalette.ink)
                }
                .tint(NativePalette.ink)
            }
        }
    }

    private var marketListCard: some View {
        GridCard(title: "结果列表", subtitle: "ClawHub", systemImage: "square.stack.3d.up.fill", accent: NativePalette.accent) {
            VStack(alignment: .leading, spacing: 14) {
                if let marketSummary = store.skillsMarketSummary {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(displayedMarketItems) { item in
                            marketRow(item, selected: selectedSkillSlug == item.slug)
                        }
                    }

                    if filteredMarketItems.isEmpty {
                        Text("当前筛选没有命中结果。")
                            .foregroundStyle(.secondary)
                    }

                    Text("市场快照: \(formatDate(marketSummary.collectedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isClippingMarketItems {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("为保证输入流畅，结果会先分批显示。继续筛选，或者直接展开更多结果。")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            AdaptiveLine(spacing: 10) {
                                Button("再显示 \(min(marketDisplayStep, remainingMarketItemCount)) 项") {
                                    showMoreMarketItems()
                                }
                                .buttonStyle(NativeSecondaryButtonStyle())

                                Button("显示全部 \(filteredMarketItems.count) 项") {
                                    showAllMarketItems()
                                }
                                .buttonStyle(NativeSecondaryButtonStyle())
                            }
                        }
                    }
                } else {
                    Text("等待技能市场摘要。")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func marketRow(_ item: OpenClawSkillsMarketSummary.Item, selected: Bool) -> some View {
        let installed = inventoryLookup[item.slug]
        return Button {
            activeWorkspace = .market
            focusMarketSkill(item.slug)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NativePalette.ink)
                    if let installed {
                        if installed.uninstallable {
                            TonePill(text: "已安装", tint: NativePalette.accent.opacity(0.20), foreground: NativePalette.accent)
                        } else {
                            TonePill(
                                text: skillsInventorySourceLabel(installed.source),
                                tint: skillsInventorySourceTint(installed.source).opacity(0.18),
                                foreground: skillsInventorySourceTint(installed.source)
                            )
                        }
                    }
                    Spacer(minLength: 0)
                    if let owner = item.owner, !owner.isEmpty {
                        Text(owner)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Text(item.preferredSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text(skillsMarketItemCategories(item, categories: categoryLookup))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if let downloads = item.downloads {
                        Text("下载 \(downloads)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let installed {
                        Text(installed.uninstallable ? "可卸载" : "本机已存在")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if store.isBusy("skill:detail:\(item.slug)") {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? NativePalette.surfaceRaised : NativePalette.surfaceAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? NativePalette.borderStrong : NativePalette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var marketDetailCard: some View {
        GridCard(title: "详情与操作", systemImage: "info.bubble", accent: NativePalette.amber) {
            if let detail = selectedDetail {
                let moderation = skillModerationPresentation(detail.moderation)
                let installed = selectedInventoryItem

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(detail.item.name)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(NativePalette.ink)
                            TonePill(text: moderation.label, tint: moderation.tint, foreground: moderation.foreground)
                        }

                        Text(detail.item.preferredSummary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if hasLocalizedMarketSummary(detail.item) {
                        DisclosureGroup(isExpanded: $showDetailOriginalSummary) {
                            Text(detail.item.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 10)
                        } label: {
                            Text("原文说明")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(NativePalette.ink)
                        }
                        .tint(NativePalette.ink)
                    }

                    if let installed {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: installed.uninstallable ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(installed.uninstallable ? NativePalette.mint : NativePalette.amber)
                            Text(installed.uninstallable
                                ? "这个 skill 已经安装在 Manager 托管目录里，可以直接卸载。"
                                : "这个 skill 在本机已经存在，但不属于 Manager 托管目录；这里不会直接删除外部目录。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill((installed.uninstallable ? NativePalette.mint : NativePalette.amber).opacity(0.10))
                        )
                    }

                    TwoColumnFacts(items: [
                        ("slug", detail.item.slug),
                        ("作者", present(detail.owner?.displayName ?? detail.owner?.handle, fallback: detail.item.owner ?? "未提供")),
                        ("最新版本", present(detail.latestVersion?.version)),
                        ("下载量", "\(detail.stats.downloads)"),
                        ("Stars", "\(detail.stats.stars)"),
                        ("最近更新", formatDate(detail.updatedAt))
                    ])

                    if let moderationSummary = detail.moderation?.summary, !moderationSummary.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: detail.moderation?.isMalwareBlocked == true ? "xmark.shield.fill" : "exclamationmark.shield.fill")
                                .foregroundStyle(detail.moderation?.isMalwareBlocked == true ? NativePalette.rose : NativePalette.amber)
                            Text(moderationSummary)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill((detail.moderation?.isMalwareBlocked == true ? NativePalette.rose : NativePalette.amber).opacity(0.12))
                        )
                    }

                    DisclosureGroup(isExpanded: $showDetailRequirements) {
                        TwoColumnFacts(items: [
                            ("OS", detail.metadata.os.isEmpty ? "未声明" : detail.metadata.os.joined(separator: ", ")),
                            ("系统能力", detail.metadata.systems.isEmpty ? "未声明" : detail.metadata.systems.joined(separator: ", "))
                        ])
                        .padding(.top, 10)
                    } label: {
                        Text("运行要求")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NativePalette.ink)
                    }
                    .tint(NativePalette.ink)

                    if let changelog = detail.latestVersion?.changelog, !changelog.isEmpty {
                        DisclosureGroup(isExpanded: $showDetailChangelog) {
                            Text(changelog)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 10)
                        } label: {
                            Text("版本说明")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(NativePalette.ink)
                        }
                        .tint(NativePalette.ink)
                    }

                    AdaptiveLine(spacing: 10) {
                        if let installed {
                            let toggle = skillTogglePresentation(installed)
                            ActionButton(toggle.label, systemImage: toggle.icon, busy: store.isBusy("skill:\(toggle.enable ? "enable" : "disable"):\(detail.item.slug)")) {
                                store.setSkillEnabled(slug: detail.item.slug, enabled: toggle.enable, bundled: installed.bundled)
                            }

                            if installed.uninstallable {
                                ActionButton("卸载", systemImage: "trash", busy: store.isBusy("skill:uninstall:\(detail.item.slug)")) {
                                    store.uninstallSkill(slug: detail.item.slug)
                                }
                            }
                        } else {
                            ActionButton("安装", systemImage: "square.and.arrow.down", busy: store.isBusy("skill:install:\(detail.item.slug)")) {
                                store.installSkill(slug: detail.item.slug)
                            }
                            .disabled(detail.moderation?.isMalwareBlocked == true)
                        }

                        if let url = URL(string: detail.item.registryUrl) {
                            Button("打开 ClawHub") {
                                store.open(url)
                            }
                            .buttonStyle(NativeSecondaryButtonStyle())
                        }
                        if let githubURL = detail.item.githubUrl, let url = URL(string: githubURL) {
                            Button("打开源码") {
                                store.open(url)
                            }
                            .buttonStyle(NativeSecondaryButtonStyle())
                        }
                    }
                    if store.isBusy("skill:install:\(detail.item.slug)") {
                        Text("如果刚好遇到 ClawHub 限流，安装会自动等待后继续，不需要重复点。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let selectedSkillSlug, store.isBusy("skill:detail:\(selectedSkillSlug)") {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("读取技能详情。")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("先在结果列表里选一个 skill，再决定是否安装。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var localInventoryCard: some View {
        GridCard(title: "本地库存", systemImage: "shippingbox", accent: NativePalette.mint) {
            if let inventory = store.skillsInventory {
                VStack(alignment: .leading, spacing: 16) {
                    AdaptiveLine(spacing: 14) {
                        InlineStatusColumn(
                            title: "市场安装",
                            value: "\(inventory.managerInstalled)",
                            detail: "可直接卸载",
                            accent: NativePalette.accent
                        )
                        InlineStatusColumn(
                            title: "本地个人",
                            value: "\(inventory.personalInstalled)",
                            detail: "当前用户已有 skills",
                            accent: NativePalette.mint
                        )
                        InlineStatusColumn(
                            title: "Bundled",
                            value: "\(inventory.bundledInstalled)",
                            detail: "总计 \(inventory.totalItems)",
                            accent: NativePalette.amber
                        )
                    }

                    AdaptiveLine(spacing: 12) {
                        TextField("在本地库存里查找名称、slug 或来源", text: $inventorySearchText)
                            .textFieldStyle(.roundedBorder)
                        Toggle("显示 Bundled", isOn: $showBundledSkills)
                            .toggleStyle(.switch)
                            .frame(width: 140)
                        if !inventory.managedDirectory.isEmpty {
                            Button("打开托管目录") {
                                store.open(URL(fileURLWithPath: inventory.managedDirectory))
                            }
                            .buttonStyle(NativeSecondaryButtonStyle())
                        }
                    }

                    if let runtimeError = inventory.runtimeError, !runtimeError.isEmpty {
                        Text(runtimeError)
                            .font(.caption)
                            .foregroundStyle(NativePalette.rose)
                    }

                    if inventoryGroups.isEmpty {
                        Text("当前筛选没有命中任何本地 skill。")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(inventoryGroups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            if isInventoryFiltering {
                                inventoryGroupHeader(group)
                                ForEach(group.items) { item in
                                    inventoryRow(item)
                                }
                            } else {
                                DisclosureGroup(isExpanded: inventoryGroupBinding(group.id)) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(group.items) { item in
                                            inventoryRow(item)
                                        }
                                    }
                                    .padding(.top, 10)
                                } label: {
                                    inventoryGroupHeader(group)
                                }
                                .tint(NativePalette.ink)
                            }
                        }

                        if group.id != inventoryGroups.last?.id {
                            Divider()
                                .overlay(NativePalette.border)
                        }
                    }
                }
            } else {
                Text("等待已安装技能库存。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func inventoryGroupBinding(_ groupID: String) -> Binding<Bool> {
        Binding(
            get: { expandedInventoryGroups.contains(groupID) },
            set: { expanded in
                if expanded {
                    expandedInventoryGroups.insert(groupID)
                } else {
                    expandedInventoryGroups.remove(groupID)
                }
            }
        )
    }

    private func inventoryGroupHeader(_ group: SkillsInventoryGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.title)
                    .font(.headline)
                Text(group.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(group.items.count) 项")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func inventoryRow(_ item: OpenClawSkillsInventory.Item) -> some View {
        let toggle = skillTogglePresentation(item)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NativePalette.ink)
                TonePill(
                    text: skillsInventorySourceLabel(item.source),
                    tint: skillsInventorySourceTint(item.source).opacity(0.18),
                    foreground: skillsInventorySourceTint(item.source)
                )
                Spacer(minLength: 0)
                Text(skillRuntimeStatusLabel(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(item.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            AdaptiveLine(spacing: 8) {
                Text(item.slug)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                if let version = item.installedVersion, !version.isEmpty {
                    TonePill(text: "v\(version)", tint: NativePalette.surfaceAlt, foreground: NativePalette.ink)
                }
                if let installedAt = item.installedAt, !installedAt.isEmpty {
                    TonePill(text: formatDate(installedAt), tint: NativePalette.surfaceAlt, foreground: NativePalette.ink)
                }
            }

            AdaptiveLine(spacing: 10) {
                ActionButton(toggle.label, systemImage: toggle.icon, busy: store.isBusy("skill:\(toggle.enable ? "enable" : "disable"):\(item.slug)")) {
                    store.setSkillEnabled(slug: item.slug, enabled: toggle.enable, bundled: item.bundled)
                }

                if item.managerOwned {
                    ActionButton("卸载", systemImage: "trash", busy: store.isBusy("skill:uninstall:\(item.slug)")) {
                        store.uninstallSkill(slug: item.slug)
                    }
                } else if marketLookup[item.slug] != nil {
                    Button("查看市场详情") {
                        activeWorkspace = .market
                        focusMarketSkill(item.slug)
                    }
                    .buttonStyle(NativeSecondaryButtonStyle())
                }

                if let homepage = item.homepage, let url = URL(string: homepage) {
                    Button("打开主页") {
                        store.open(url)
                    }
                    .buttonStyle(NativeSecondaryButtonStyle())
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(NativePalette.surfaceAlt)
        )
    }

    private func scheduleMarketSearch() {
        marketSearchTask?.cancel()
        let query = marketSearchText
        let sort = marketSort
        marketSearchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            store.loadSkillsMarket(query: query, sort: sort)
        }
    }

    private func triggerMarketSearch(immediate: Bool) {
        marketSearchTask?.cancel()
        if immediate {
            store.loadSkillsMarket(query: marketSearchText, sort: marketSort)
            return
        }
        scheduleMarketSearch()
    }

    private func resetMarketDisplayLimit() {
        marketDisplayLimit = baseMarketDisplayLimit
    }

    private func showMoreMarketItems() {
        marketDisplayLimit = min(filteredMarketItems.count, effectiveMarketDisplayLimit + marketDisplayStep)
    }

    private func showAllMarketItems() {
        marketDisplayLimit = filteredMarketItems.count
    }

    private func resetMarketDetailDisclosure() {
        showDetailRequirements = false
        showDetailChangelog = false
        showDetailOriginalSummary = false
    }

    private func focusMarketSkill(_ slug: String) {
        selectedSkillSlug = slug
        resetMarketDetailDisclosure()

        if let index = filteredMarketItems.firstIndex(where: { $0.slug == slug }), index >= effectiveMarketDisplayLimit {
            marketDisplayLimit = index + 1
        }

        if store.skillMarketDetail?.item.slug != slug {
            store.loadSkillMarketDetail(slug: slug)
        }
    }

    private func syncMarketSelection() {
        let items = filteredMarketItems
        guard !items.isEmpty else {
            selectedSkillSlug = nil
            return
        }

        if let selectedSkillSlug, let index = items.firstIndex(where: { $0.slug == selectedSkillSlug }) {
            if index >= effectiveMarketDisplayLimit {
                marketDisplayLimit = index + 1
            }
            if store.skillMarketDetail?.item.slug != selectedSkillSlug {
                store.loadSkillMarketDetail(slug: selectedSkillSlug)
            }
            return
        }

        if let first = items.first {
            focusMarketSkill(first.slug)
        }
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
    @State private var skillsWatchEnabled = false
    @State private var skillsWatchDebounceMs = 1500
    @State private var skillsInstallPreferBrewSelection = "default"
    @State private var skillsInstallNodeManagerSelection = ""
    @State private var showAllSkills = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLead(
                title: "设置",
                detail: ""
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
                GridCard(title: "本地根目录", systemImage: "folder.badge.gearshape", accent: NativePalette.accent) {
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

                GridCard(title: "OpenClaw Skills", systemImage: "square.stack.3d.up.fill", accent: NativePalette.amber) {
                    if let skillsSummary = store.openClawSkillsSummary, let skillsConfig = store.openClawSkillsConfig {
                        let visibleSkills = showAllSkills ? skillsSummary.skills : Array(skillsSummary.skills.prefix(12))
                        let currentSkillsWatch = skillsConfig.watch ?? false
                        let currentSkillsDebounceMs = max(100, skillsConfig.watchDebounceMs ?? 1500)
                        let skillsDraftChanged = skillsWatchEnabled != currentSkillsWatch || skillsWatchDebounceMs != currentSkillsDebounceMs
                        let currentInstallPreferBrewSelection = skillsInstallPreferBrewMode(skillsConfig.installPreferBrew)
                        let currentInstallNodeManagerSelection = skillsInstallNodeManagerDraftValue(skillsConfig.installNodeManager)
                        let installDraftChanged = skillsInstallPreferBrewSelection != currentInstallPreferBrewSelection || skillsInstallNodeManagerSelection != currentInstallNodeManagerSelection

                        VStack(alignment: .leading, spacing: 16) {
                            AdaptiveLine(spacing: 14) {
                                InlineStatusColumn(
                                    title: "可用",
                                    value: "\(skillsSummary.readySkills)",
                                    detail: "总数 \(skillsSummary.totalSkills)",
                                    accent: NativePalette.mint
                                )
                                InlineStatusColumn(
                                    title: "缺依赖",
                                    value: "\(skillsSummary.missingSkills)",
                                    detail: "禁用 \(skillsSummary.disabledSkills)",
                                    accent: NativePalette.amber
                                )
                                InlineStatusColumn(
                                    title: "已配置",
                                    value: "\(skillsSummary.configuredSkills)",
                                    detail: skillsConfig.exists ? "entries \(skillsConfig.entryCount)" : "未发现配置",
                                    accent: NativePalette.accent
                                )
                            }

                            TwoColumnFacts(items: [
                                ("配置文件", skillsConfig.configPath),
                                ("配置状态", skillsConfig.valid ? "可读" : skillsConfig.detail),
                                ("Bundled 白名单", bundledAllowlistSummary(skillsConfig.allowBundled)),
                                ("额外挂载目录", "\(skillsConfig.extraDirs.count)"),
                                ("目录监听", boolLabel(skillsConfig.watch)),
                                ("Homebrew 优先", skillsInstallPreferBrewSummary(skillsConfig.installPreferBrew)),
                                ("Node 管理器", skillsInstallNodeManagerSummary(skillsConfig.installNodeManager)),
                                ("工作区", present(skillsSummary.workspaceDir)),
                                ("托管目录", present(skillsSummary.managedSkillsDir))
                            ])

                            AdaptiveLine(spacing: 10) {
                                ActionButton("刷新 Skills", systemImage: "arrow.clockwise", busy: store.isBusy("settings:refresh")) {
                                    store.refreshAll(silent: false, scope: .settingsOnly, busyKey: "settings:refresh")
                                }
                                ActionButton("新增挂载目录", systemImage: "plus", busy: store.isBusy("skills:add-extra-dir")) {
                                    store.addSkillsExtraDir()
                                }
                                Button("打开配置文件") {
                                    store.open(URL(fileURLWithPath: skillsConfig.configPath))
                                }
                                .buttonStyle(NativeSecondaryButtonStyle())
                                if let managedSkillsDir = skillsSummary.managedSkillsDir {
                                    Button("打开托管目录") {
                                        store.open(URL(fileURLWithPath: managedSkillsDir))
                                    }
                                    .buttonStyle(NativeSecondaryButtonStyle())
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("额外挂载目录")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(skillsConfig.extraDirs.count) 项")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if skillsConfig.extraDirs.isEmpty {
                                    Text("现在没有额外挂载目录。要接入自己的 skills 目录，就把那个目录加进来。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(skillsConfig.extraDirs, id: \.self) { extraDir in
                                        let isManagedDir = pathsReferToSameLocation(extraDir, skillsSummary.managedSkillsDir)
                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                                Text(extraDir)
                                                    .font(.caption.monospaced())
                                                    .foregroundStyle(NativePalette.ink)
                                                    .textSelection(.enabled)
                                                    .lineLimit(2)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                if isManagedDir {
                                                    TonePill(text: "托管目录", tint: NativePalette.accent.opacity(0.18), foreground: NativePalette.accent)
                                                }
                                            }

                                            Text(isManagedDir ? "这个目录由安装功能自动维护，建议在技能页管理，不在这里移除。" : "这个目录里的 skills 会跟着 OpenClaw 一起读取。")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)

                                            AdaptiveLine(spacing: 10) {
                                                Button("打开目录") {
                                                    store.open(URL(fileURLWithPath: normalizedDisplayPath(extraDir)))
                                                }
                                                .buttonStyle(NativeSecondaryButtonStyle())
                                                if !isManagedDir {
                                                    ActionButton("移除目录", systemImage: "minus.circle", busy: store.isBusy("skills:remove-extra-dir:\(extraDir)")) {
                                                        store.removeSkillsExtraDir(path: extraDir)
                                                    }
                                                }
                                            }
                                        }
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(NativePalette.surfaceAlt)
                                        )
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("目录监听")
                                        .font(.headline)
                                    if skillsDraftChanged {
                                        TonePill(text: "有未保存变更", tint: NativePalette.amber.opacity(0.18), foreground: NativePalette.amber)
                                    }
                                }

                                Text(skillsWatchEnabled ? "检测到目录变化后，会按下面的防抖时间自动重读 skills。" : "现在只会在手动刷新时重读目录。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Toggle("检测目录变化", isOn: $skillsWatchEnabled)
                                    .toggleStyle(.switch)

                                Stepper(value: $skillsWatchDebounceMs, in: 100...10_000, step: 100) {
                                    KeyValueLine(label: "防抖时间", value: "\(skillsWatchDebounceMs) ms")
                                }

                                Text("目录变化频繁时，OpenClaw 会等这段时间后再重新读取，避免反复触发。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                AdaptiveLine(spacing: 10) {
                                    ActionButton("保存监听设置", systemImage: "square.and.arrow.down", busy: store.isBusy("skills:config:save")) {
                                        store.saveSkillsConfig(OpenClawSkillsConfigPatch(
                                            addExtraDir: nil,
                                            removeExtraDir: nil,
                                            watch: skillsWatchEnabled,
                                            watchDebounceMs: skillsWatchDebounceMs,
                                            installPreferBrew: nil,
                                            clearInstallPreferBrew: nil,
                                            installNodeManager: nil,
                                            clearInstallNodeManager: nil
                                        ))
                                    }
                                    .disabled(!skillsDraftChanged)

                                    Button("还原草稿") {
                                        skillsWatchEnabled = currentSkillsWatch
                                        skillsWatchDebounceMs = currentSkillsDebounceMs
                                    }
                                    .buttonStyle(NativeSecondaryButtonStyle())
                                    .disabled(!skillsDraftChanged)
                                }
                            }

                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("安装工具")
                                        .font(.headline)
                                    if installDraftChanged {
                                        TonePill(text: "有未保存变更", tint: NativePalette.amber.opacity(0.18), foreground: NativePalette.amber)
                                    }
                                }

                                Text("这里只影响后续从市场安装 skill 时优先用哪套工具；未配置时沿用 OpenClaw 默认行为。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                AdaptiveLine(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Homebrew")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Picker("Homebrew", selection: $skillsInstallPreferBrewSelection) {
                                            Text("未配置").tag("default")
                                            Text("优先 Homebrew").tag("prefer-brew")
                                            Text("不优先 Homebrew").tag("prefer-direct")
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Node 管理器")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Picker("Node 管理器", selection: $skillsInstallNodeManagerSelection) {
                                            Text("未配置").tag("")
                                            ForEach(skillsInstallNodeManagerOptions(selection: skillsInstallNodeManagerSelection), id: \.self) { value in
                                                Text(value).tag(value)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                Text("常见值是 `npm`、`pnpm`、`yarn`、`bun`。如果你没特别要求，保持未配置最稳妥。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                AdaptiveLine(spacing: 10) {
                                    ActionButton("保存安装设置", systemImage: "square.and.arrow.down", busy: store.isBusy("skills:config:save")) {
                                        let nextPreferBrew = skillsInstallPreferBrewValue(skillsInstallPreferBrewSelection)
                                        let nextNodeManager = skillsInstallNodeManagerSelection.trimmingCharacters(in: .whitespacesAndNewlines)
                                        store.saveSkillsConfig(OpenClawSkillsConfigPatch(
                                            addExtraDir: nil,
                                            removeExtraDir: nil,
                                            watch: nil,
                                            watchDebounceMs: nil,
                                            installPreferBrew: nextPreferBrew,
                                            clearInstallPreferBrew: nextPreferBrew == nil ? true : nil,
                                            installNodeManager: nextNodeManager.isEmpty ? nil : nextNodeManager,
                                            clearInstallNodeManager: nextNodeManager.isEmpty ? true : nil
                                        ))
                                    }
                                    .disabled(!installDraftChanged)

                                    Button("还原草稿") {
                                        skillsInstallPreferBrewSelection = currentInstallPreferBrewSelection
                                        skillsInstallNodeManagerSelection = currentInstallNodeManagerSelection
                                    }
                                    .buttonStyle(NativeSecondaryButtonStyle())
                                    .disabled(!installDraftChanged)
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Skills 列表")
                                    .font(.headline)

                                ForEach(visibleSkills) { skill in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                                            Text(skill.name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(NativePalette.ink)
                                            TonePill(
                                                text: skillStatusLabel(skill),
                                                tint: skillStatusTint(skill)
                                            )
                                            Spacer(minLength: 0)
                                            Text(skill.source)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Text(skillSummaryLine(skill))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(NativePalette.surfaceAlt)
                                    )
                                }

                                if skillsSummary.skills.count > 12 {
                                    Button(showAllSkills ? "收起列表" : "展开全部 \(skillsSummary.skills.count) 项") {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            showAllSkills.toggle()
                                        }
                                    }
                                    .buttonStyle(NativeSecondaryButtonStyle())
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("等待 OpenClaw Skills 摘要。")
                                .foregroundStyle(.secondary)
                            ActionButton("读取 Skills", systemImage: "arrow.clockwise", busy: store.isBusy("settings:refresh")) {
                                store.refreshAll(silent: false, scope: .settingsOnly, busyKey: "settings:refresh")
                            }
                        }
                    }
                }

                GridCard(title: "自动切换", systemImage: "arrow.triangle.branch", accent: NativePalette.mint) {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("启用自动切换", isOn: $autoActivateEnabled)
                            .toggleStyle(.switch)

                        Stepper(value: $probeWindowMinSeconds, in: 30...3600, step: 30) {
                            KeyValueLine(label: "检查窗口起点", value: "\(probeWindowMinSeconds) 秒")
                        }
                        .onChange(of: probeWindowMinSeconds) { nextValue in
                            if probeWindowMaxSeconds < nextValue {
                                probeWindowMaxSeconds = nextValue
                            }
                        }

                        Stepper(value: $probeWindowMaxSeconds, in: probeWindowMinSeconds...7200, step: 30) {
                            KeyValueLine(label: "检查窗口终点", value: "\(probeWindowMaxSeconds) 秒")
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
                            ActionButton("立即检查", systemImage: "play.circle", busy: store.isBusy("automation:tick")) {
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
        .onChange(of: store.openClawSkillsConfig?.collectedAt) { _ in
            syncDraft()
        }
    }

    private func syncDraft() {
        if let automation = store.automation {
            autoActivateEnabled = automation.enabled
            probeWindowMinSeconds = max(30, automation.probeIntervalMinMs / 1000)
            probeWindowMaxSeconds = max(probeWindowMinSeconds, automation.probeIntervalMaxMs / 1000)
            fiveHourDrainPercent = automation.fiveHourDrainPercent
            weekDrainPercent = automation.weekDrainPercent
            autoStatuses = Set(automation.autoSwitchStatuses)
        }

        if let skillsConfig = store.openClawSkillsConfig {
            skillsWatchEnabled = skillsConfig.watch ?? false
            skillsWatchDebounceMs = max(100, skillsConfig.watchDebounceMs ?? 1500)
            skillsInstallPreferBrewSelection = skillsInstallPreferBrewMode(skillsConfig.installPreferBrew)
            skillsInstallNodeManagerSelection = skillsInstallNodeManagerDraftValue(skillsConfig.installNodeManager)
        }
    }
}

private struct OpenClawSkillRow: View {
    let skill: OpenClawSkillsSummary.Skill

    var body: some View {
        let presentation = skillsStatusPresentation(skill.status)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("\(skill.emoji ?? "🧩") \(skill.name)")
                    .font(.headline)
                    .foregroundStyle(NativePalette.ink)
                Spacer(minLength: 0)
                TonePill(text: presentation.label, tint: presentation.tint, foreground: presentation.foreground)
            }

            if !skill.description.isEmpty {
                Text(skill.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            AdaptiveLine(spacing: 8) {
                TonePill(text: skillsSourceLabel(skill.source), tint: NativePalette.surfaceAlt, foreground: NativePalette.ink)
                if skill.configConfigured {
                    TonePill(
                        text: skill.configEnabled == false ? "本地配置 禁用" : "本地配置 已写入",
                        tint: NativePalette.accent.opacity(0.18),
                        foreground: NativePalette.accent
                    )
                }
                if skill.hasApiKeyConfig {
                    TonePill(text: "已配置密钥", tint: NativePalette.mint.opacity(0.18), foreground: NativePalette.mint)
                }
                if skill.hasEnvConfig {
                    TonePill(text: "含 env 覆盖", tint: NativePalette.amber.opacity(0.2), foreground: NativePalette.amber)
                }
            }

            if let missing = skillsMissingSummary(skill.missing) {
                Text(missing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(NativePalette.surfaceAlt)
        )
    }
}

private func triStateLabel(_ value: Bool?) -> String {
    guard let value else { return "默认" }
    return value ? "开" : "关"
}

private func skillsStatusPresentation(_ status: String) -> (label: String, tint: Color, foreground: Color) {
    switch status {
    case "ready":
        return ("Ready", NativePalette.mint.opacity(0.18), NativePalette.mint)
    case "disabled":
        return ("禁用", NativePalette.surfaceAlt, NativePalette.ink)
    case "blocked":
        return ("受限", NativePalette.amber.opacity(0.2), NativePalette.amber)
    default:
        return ("缺依赖", NativePalette.rose.opacity(0.18), NativePalette.rose)
    }
}

private func skillsSourceLabel(_ source: String) -> String {
    switch source {
    case "openclaw-bundled":
        return "Bundled"
    case "workspace":
        return "Workspace"
    case "managed":
        return "Managed"
    case "extra-dir":
        return "Extra Dir"
    default:
        return source.isEmpty ? "未知来源" : source
    }
}

private func skillsMissingSummary(_ missing: OpenClawSkillsSummary.Missing) -> String? {
    var parts: [String] = []
    if !missing.bins.isEmpty {
        parts.append("缺命令: \(missing.bins.joined(separator: ", "))")
    }
    if !missing.anyBins.isEmpty {
        parts.append("缺任一命令组: \(missing.anyBins.joined(separator: ", "))")
    }
    if !missing.env.isEmpty {
        parts.append("缺环境变量: \(missing.env.joined(separator: ", "))")
    }
    if !missing.config.isEmpty {
        parts.append("缺配置项: \(missing.config.joined(separator: ", "))")
    }
    if !missing.os.isEmpty {
        parts.append("系统不满足: \(missing.os.joined(separator: ", "))")
    }
    if parts.isEmpty {
        return nil
    }
    return parts.joined(separator: " · ")
}

private struct DiagnosticsSection: View {
    @ObservedObject var store: NativeAppStore
    @State private var showDetailedStatus = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLead(
                title: "诊断",
                detail: ""
            )

            if let summary = store.supportSummary {
                let gatewayIssue = gatewayDiagnosis(summary: summary)
                let plan = diagnosticPlan(summary: summary)
                GridCard(title: "当前判断", systemImage: "sparkles", accent: plan.accent) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(plan.headline)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(NativePalette.ink)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(plan.detail)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        AdaptiveLine(spacing: 18) {
                            InlineStatusColumn(
                                title: "网关",
                                value: summary.gateway.reachable ? "可达" : "不可达",
                                detail: summary.gateway.reachable
                                    ? "连接延迟 \(formatMillis(summary.gateway.connectLatencyMs))"
                                    : gatewayIssue.headline,
                                accent: summary.gateway.reachable ? NativePalette.mint : NativePalette.rose
                            )
                            InlineStatusColumn(
                                title: "Discord",
                                value: supportStatusPresentation(summary.discord.status).label,
                                detail: "15 分钟断线 \(summary.discord.disconnectCount15m) 次",
                                accent: supportStatusPresentation(summary.discord.status).tint
                            )
                            InlineStatusColumn(
                                title: "环境因素",
                                value: riskPresentation(summary.environment.riskLevel).label,
                                detail: present(summary.environment.recommendation),
                                accent: riskPresentation(summary.environment.riskLevel).tint
                            )
                        }

                        diagnosticsSummaryBlock(
                            label: "下一步",
                            value: primaryRecommendation(summary: summary),
                            detail: nil
                        )

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

                if let repairResult = store.lastSupportRepairResult {
                    GridCard(
                        title: "最近一次操作",
                        systemImage: repairResult.ok ? "checkmark.circle" : "exclamationmark.triangle",
                        accent: repairResult.ok ? NativePalette.mint : NativePalette.rose
                    ) {
                        diagnosticsSummaryBlock(
                            label: supportRepairTitle(repairResult.action),
                            value: supportRepairSummary(repairResult),
                            detail: repairResult.ok ? formatDate(repairResult.summary.collectedAt) : supportRepairFollowUp(repairResult)
                        )
                    }
                }

                GridCard(title: "OpenClaw 维护", systemImage: "wrench.adjustable", accent: NativePalette.accent) {
                    VStack(alignment: .leading, spacing: 14) {
                        let service = summary.maintenance.gatewayService
                        diagnosticsSummaryBlock(
                            label: "下一步",
                            value: primaryRecommendation(summary: summary),
                            detail: nil
                        )

                        diagnosticsSummaryBlock(
                            label: "状态",
                            value: maintenanceHeadline(summary: summary),
                            detail: !summary.maintenance.config.valid
                                ? summary.maintenance.config.detail
                                : present(service.issue, fallback: "")
                        )

                        TwoColumnFacts(items: [
                            ("CLI 路径", present(summary.maintenance.cliPath)),
                            ("状态目录", summary.maintenance.stateDir),
                            ("配置状态", configValidationPresentation(summary.maintenance.config.valid).label),
                            ("配置文件", summary.maintenance.config.path),
                            ("服务健康", gatewayServicePresentation(service).label),
                            ("Gateway 服务", service.status),
                            ("运行时", present(service.runtimeStatus)),
                            ("RPC 检查", present(service.probeStatus))
                        ])

                        AdaptiveLine(spacing: 10) {
                            ActionButton("校验配置", systemImage: "checklist", busy: store.isBusy("support:\(SupportRepairAction.validateConfig.rawValue)")) {
                                store.repair(.validateConfig)
                            }
                            ActionButton("官方体检", systemImage: "stethoscope", busy: store.isBusy("support:\(SupportRepairAction.runOpenClawDoctor.rawValue)")) {
                                store.repair(.runOpenClawDoctor)
                            }
                            ActionButton("官方修复", systemImage: "cross.case", busy: store.isBusy("support:\(SupportRepairAction.runOpenClawDoctorFix.rawValue)")) {
                                store.repair(.runOpenClawDoctorFix)
                            }
                            ActionButton("重装服务", systemImage: "shippingbox.circle", busy: store.isBusy("support:\(SupportRepairAction.reinstallGatewayService.rawValue)")) {
                                store.repair(.reinstallGatewayService)
                            }
                        }

                        AdaptiveLine(spacing: 10) {
                            Button("打开配置文件") {
                                store.open(URL(fileURLWithPath: summary.maintenance.config.path))
                            }
                            .buttonStyle(NativeSecondaryButtonStyle())

                            Button("打开状态目录") {
                                store.open(URL(fileURLWithPath: summary.maintenance.stateDir))
                            }
                            .buttonStyle(NativeSecondaryButtonStyle())

                            if let serviceFile = service.serviceFile {
                                Button("打开服务文件") {
                                    store.open(URL(fileURLWithPath: serviceFile))
                                }
                                .buttonStyle(NativeSecondaryButtonStyle())
                            }
                        }
                    }
                }

                GridCard(title: "详细状态", systemImage: "text.magnifyingglass", accent: NativePalette.surfaceAlt) {
                    VStack(alignment: .leading, spacing: 16) {
                        Button {
                            withAnimation(.easeOut(duration: 0.22)) {
                                showDetailedStatus.toggle()
                            }
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Text(showDetailedStatus ? "收起详细状态" : "展开详细状态")
                                    .font(.headline)
                                    .foregroundStyle(NativePalette.ink)
                                Spacer(minLength: 0)
                                Image(systemName: showDetailedStatus ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showDetailedStatus {
                            VStack(alignment: .leading, spacing: 22) {
                                DetailSectionBlock(title: "网关和 Discord") {
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

                                Divider()
                                    .overlay(NativePalette.border)

                                DetailSectionBlock(title: "稳定守护") {
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
                                            ActionButton("执行一键修复", systemImage: "wrench.and.screwdriver", busy: store.isBusy("support:\(SupportRepairAction.runWatchdogCheck.rawValue)")) {
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

                                Divider()
                                    .overlay(NativePalette.border)

                                DetailSectionBlock(title: "环境因素") {
                                    VStack(alignment: .leading, spacing: 14) {
                                        TwoColumnFacts(items: [
                                            ("提示级别", riskPresentation(summary.environment.riskLevel).label),
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
                                                Text("环境信号")
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
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            } else {
                GridCard(title: "诊断", systemImage: "stethoscope", accent: NativePalette.amber) {
                    Text("读取中。")
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
        case let .openPath(path):
            Button {
                store.open(URL(fileURLWithPath: path))
            } label: {
                Label(plan.title, systemImage: plan.systemImage)
            }
            .buttonStyle(NativeSecondaryButtonStyle(prominent: plan.prominent))
        }
    }

    private func diagnosticsSummaryBlock(label: String, value: String, detail: String?) -> some View {
        CalloutBlock(label: label, value: value, detail: detail)
    }
}

private struct DeploymentSection: View {
    @ObservedObject var store: NativeAppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLead(
                title: "命令",
                detail: ""
            )

            if let runtime = store.runtime {
                let hasCodexCompanion = store.profiles.contains { $0.companionRuntimeKind == "codex" }
                VStack(alignment: .leading, spacing: 18) {
                    GridCard(title: "运行模式", systemImage: "network", accent: NativePalette.accent) {
                        TwoColumnFacts(items: [
                            ("运行模式", runtimeModeLabel(runtime.mode)),
                            ("原生壳", runtime.compatibility.nativeShellRecommended ? "推荐" : "可选"),
                            ("支持浏览器壳", runtime.compatibility.browserShellSupported ? "支持" : "不支持"),
                            ("允许 localhost dev", runtime.compatibility.allowLocalhostDev ? "允许" : "关闭"),
                            ("允许来源", runtime.compatibility.allowedOrigins.isEmpty ? "仅同源 / 本地壳" : runtime.compatibility.allowedOrigins.joined(separator: " · ")),
                            ("回调地址", runtime.roots.oauthCallbackUrl)
                        ])
                    }

                    GridCard(title: "命令", systemImage: "terminal", accent: NativePalette.mint) {
                        VStack(alignment: .leading, spacing: 12) {
                            CommandBlock(title: "OpenClaw", value: runtime.compatibility.wrapperCommand)
                            if hasCodexCompanion {
                                CommandBlock(title: "Codex companion", value: runtime.compatibility.codexWrapperCommand)
                            }
                        }
                    }

                    GridCard(title: "目录", systemImage: "shippingbox", accent: NativePalette.amber) {
                        let items: [(String, String)] = {
                            var items: [(String, String)] = [
                                ("OpenClaw Home", runtime.roots.openclawHomeDir),
                                ("默认状态目录", runtime.roots.defaultOpenClawStateDir),
                                ("Manager 状态目录", runtime.roots.managerDir),
                                ("Runtime 目录", present(store.localSnapshot.runtimeRootPath))
                            ]
                            if hasCodexCompanion {
                                items.insert(("可选 Codex Home", runtime.roots.codexHomeDir), at: 1)
                                items.insert(("默认 Codex", runtime.roots.defaultCodexHome), at: 3)
                            }
                            return items
                        }()
                        TwoColumnFacts(items: items)
                    }
                }
            } else {
                GridCard(title: "命令", systemImage: "shippingbox", accent: NativePalette.amber) {
                    Text("读取中。")
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

private struct InlineStatusColumn: View {
    var title: String
    var value: String
    var detail: String
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
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NativePalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent.opacity(0.8))
                .frame(width: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CalloutBlock: View {
    var label: String
    var value: String
    var detail: String?

    var body: some View {
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
        .padding(.leading, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(NativePalette.borderStrong)
                .frame(width: 2)
        }
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
                        MiniTag(text: "当前", tint: isSelected ? NativePalette.mint.opacity(0.16) : NativePalette.mint.opacity(0.16), foreground: NativePalette.mint)
                    }
                    if profile.isRecommended {
                        MiniTag(text: "推荐", tint: isSelected ? NativePalette.accent.opacity(0.16) : NativePalette.accent.opacity(0.16), foreground: NativePalette.accent)
                    }
                }
            }
            .padding(14)
            .frame(width: 190, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(NativePalette.surfaceAlt)
                            : AnyShapeStyle(NativePalette.surfaceRaised)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? NativePalette.borderStrong : NativePalette.border, lineWidth: 1)
            )
            .foregroundStyle(NativePalette.ink)
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
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(NativePalette.ink)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
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

private struct DetailSectionBlock<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(NativePalette.ink)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
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
        .padding(.leading, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(NativePalette.borderStrong)
                .frame(width: 2)
        }
    }
}

private struct UsageSegment: Identifiable {
    var label: String
    var value: Int
    var tint: Color

    var id: String { label }
}

private struct MemoryStructurePanel: View {
    var summary: MachineSummary.Memory
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: "memorychip")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("内存结构")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("压力 \(summary.pressurePercent)% · 总占用 \(summary.usedPercent)%")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NativePalette.ink)
                }
            }

            SegmentedUsageBar(segments: [
                UsageSegment(label: "Wired", value: summary.wiredBytes, tint: NativePalette.rose),
                UsageSegment(label: "Used", value: summary.activeBytes, tint: NativePalette.amber),
                UsageSegment(label: "Cache", value: summary.cachedBytes, tint: NativePalette.accent),
                UsageSegment(label: "Free", value: summary.freeBytes, tint: NativePalette.mint),
                UsageSegment(label: "Other", value: summary.otherBytes, tint: NativePalette.surfaceAlt)
            ])

            AdaptiveLine(spacing: 10) {
                UsageLegend(label: "Wired", value: formatBytes(summary.wiredBytes), tint: NativePalette.rose)
                UsageLegend(label: "Used", value: formatBytes(summary.activeBytes), tint: NativePalette.amber)
                UsageLegend(label: "Cache", value: formatBytes(summary.cachedBytes), tint: NativePalette.accent)
            }
            AdaptiveLine(spacing: 10) {
                UsageLegend(label: "Free", value: formatBytes(summary.freeBytes), tint: NativePalette.mint)
                UsageLegend(label: "Other", value: formatBytes(summary.otherBytes), tint: NativePalette.surfaceAlt)
                UsageLegend(label: "Compressed", value: formatBytes(summary.compressedBytes), tint: accent)
            }
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

private struct SegmentedUsageBar: View {
    var segments: [UsageSegment]

    var body: some View {
        GeometryReader { geometry in
            let total = max(segments.reduce(0) { $0 + max($1.value, 0) }, 1)

            HStack(spacing: 1) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.tint)
                        .frame(width: max((CGFloat(segment.value) / CGFloat(total)) * geometry.size.width, segment.value > 0 ? 2 : 0))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(NativePalette.surfaceAlt)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(height: 16)
    }
}

private struct UsageLegend: View {
    var label: String
    var value: String
    var tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(NativePalette.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProcessMetricPill: View {
    var label: String
    var value: String
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativePalette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(NativePalette.border, lineWidth: 1)
        )
    }
}

private struct TrendTile: View {
    var title: String
    var value: String
    var caption: String
    var values: [Double]
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            TrendSparkline(values: values, accent: accent)
                .frame(height: 72)

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

private struct TrendSparkline: View {
    var values: [Double]
    var accent: Color

    var body: some View {
        GeometryReader { geometry in
            let points = chartPoints(in: geometry.size)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NativePalette.surfaceAlt.opacity(0.72))

                if points.count >= 2 {
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                        for point in points {
                            path.addLine(to: point)
                        }
                        if let last = points.last {
                            path.addLine(to: CGPoint(x: last.x, y: geometry.size.height))
                        }
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.24), accent.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                    if let last = points.last {
                        Circle()
                            .fill(accent)
                            .frame(width: 7, height: 7)
                            .position(last)
                    }
                } else if let point = points.first {
                    Capsule(style: .continuous)
                        .fill(accent.opacity(0.88))
                        .frame(width: max(geometry.size.width - 20, 8), height: 2.5)
                        .position(x: geometry.size.width / 2, y: point.y)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        let samples = values.isEmpty ? [0] : values
        let minValue = samples.min() ?? 0
        let maxValue = samples.max() ?? 0
        let range = max(maxValue - minValue, 1)
        let width = max(size.width, 1)
        let height = max(size.height, 1)

        return samples.enumerated().map { index, value in
            let x = samples.count == 1
                ? width / 2
                : (CGFloat(index) / CGFloat(samples.count - 1)) * width
            let normalized = (value - minValue) / range
            let y = height - (CGFloat(normalized) * (height - 10)) - 5
            return CGPoint(x: x, y: y)
        }
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
