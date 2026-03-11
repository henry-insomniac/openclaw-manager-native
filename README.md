# OpenClaw Manager Native

OpenClaw Manager Native 是面向 macOS 的 OpenClaw 本地管理桌面版。

它的目标很直接：

- 管理 `.openclaw` 和 `.openclaw-*` profile
- 用图形界面维护本地 OpenClaw 状态
- 直接在桌面端执行诊断、修复和服务重启
- 产出可分发的 `.app`、`.dmg`、`.pkg`、`.zip`

当前版本：`1.0.5`

## English

OpenClaw Manager Native is a macOS desktop app for managing local OpenClaw setups.

It is designed to:

- manage `.openclaw` and `.openclaw-*` profiles
- inspect and repair local OpenClaw state from a native UI
- restart services and run diagnostics without dropping into the terminal
- ship as a distributable `.app`, `.dmg`, `.pkg`, and release bundle

Architecture at a glance:

- Swift native shell for lifecycle, windowing, menu bar, and local runtime management
- SwiftUI-based interface for profile management and diagnostics
- bundled Go daemon for local APIs, provider-aware profile discovery, health checks, and repair actions
- bundled Go watchdog for optional gateway recovery and stability protection

## 技术架构

当前仓库已经不是旧的 `WKWebView + Node runtime` 方案，实际结构如下：

1. `macOS Native Shell`
   - `Sources/OpenClawManagerNative/main.swift`
   - 负责应用生命周期、窗口、菜单栏、安装态启动链和本地 runtime 管理

2. `Native UI`
   - `Sources/OpenClawManagerNative/NativeShellView.swift`
   - `Sources/OpenClawManagerNative/NativeStore.swift`
   - 使用 SwiftUI 渲染主界面，通过本地 HTTP API 拉取状态和触发动作

3. `Bundled Go Daemon`
   - `cmd/openclaw-manager-daemon/main.go`
   - 提供本地管理 API，负责 profile 发现、provider 识别、诊断摘要、修复动作、Gateway 服务检查和自动化状态

4. `Bundled Go Watchdog`
   - `cmd/openclaw-watchdog/main.go`
   - 用于安装可选的本机 watchdog，持续监控 OpenClaw gateway 卡死、超时和异常恢复

5. `Packaging / Delivery Pipeline`
   - `scripts/build-app.sh`
   - `scripts/package-app.sh`
   - `scripts/package-dmg.sh`
   - `scripts/package-pkg.sh`
   - `scripts/package-delivery.sh`
   - 负责构建原生 app、同步 bundled runtime、签名、封装和生成完整交付包

整体调用关系：

```text
Swift App / Menu Bar / SwiftUI
            |
            v
   localhost HTTP API
            |
            v
openclaw-manager-daemon (Go)
            |
            v
OpenClaw CLI / 本地配置 / launchd / gateway / watchdog
```

## 仓库结构

- `Sources/OpenClawManagerNative/`: 原生桌面壳和 UI
- `cmd/openclaw-manager-daemon/`: 本地管理 daemon
- `cmd/openclaw-watchdog/`: 本机 watchdog
- `scripts/`: 构建、打包、签名、公证和 watchdog 脚本
- `docs/releases/`: 每个版本的发布记录
- `assets/`: 图标、entitlements 等打包资源
- `vendor/runtime/`: 打包进 app 的 runtime 输出目录

## 使用

最终用户说明：

- [USAGE.md](./USAGE.md)
- [QUICKSTART.md](./QUICKSTART.md)
- [INSTALL.md](./INSTALL.md)

本地开发：

```bash
cd /Users/Zhuanz/work-space/openclaw-manager-native
swift run OpenClawManagerNative
```

构建原生 app：

```bash
bash ./scripts/build-app.sh
```

生成发布包：

```bash
bash ./scripts/package-delivery.sh
```

如果需要公证：

```bash
OPENCLAW_NOTARY_KEYCHAIN_PROFILE="你的 profile 名称" \
bash ./scripts/notarize-app.sh
```

## Watchdog

如果你的 OpenClaw gateway 偶发卡死，可以启用本机 watchdog。它会监控 gateway 日志、会话锁和进程状态，并在检测到超时或卡死时自动恢复。

最终用户优先直接在 app 菜单里操作：

```text
稳定守护 -> 启用稳定守护
稳定守护 -> 查看守护状态
稳定守护 -> 立即巡检并恢复
稳定守护 -> 停用稳定守护
```

源码目录下也可以直接调用脚本：

```bash
bash ./scripts/install-watchdog.sh
bash ./scripts/watchdog-status.sh
bash ./scripts/uninstall-watchdog.sh
```

## CHANGELOG

详细发布记录放在 `docs/releases/`：

- [1.0.5](./docs/releases/1.0.5.md) 诊断快路径、启动链死锁修复、后台空闲 CPU 继续收口
- [1.0.4](./docs/releases/1.0.4.md) 诊断中心稳定性和性能收口
- [1.0.3](./docs/releases/1.0.3.md) provider-aware 第一阶段和文案收紧

如果继续发版，这里保持最近几个版本入口，完整记录继续落在 `docs/releases/`。

## 签名与分发

- 默认目标平台：`Apple Silicon / arm64`
- 构建脚本会优先使用本机 `Developer ID Application`
- 没有证书时会退回 `ad-hoc` 签名
- 正式对外分发仍建议走 `Developer ID + notarization`

## License

本项目采用 [MIT License](./LICENSE)。
