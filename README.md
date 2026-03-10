# OpenClaw Manager Native

这是 `OpenClaw Manager 1.0` 的 macOS Swift 原生桌面版。

它不是 Electron 壳，而是：

1. 使用 `Swift + AppKit + WKWebView` 提供原生窗口和菜单
2. 在 app 内部自带 `Node` 运行时与 `manager` 后端
3. 在本机自动启动本地 API 和本地静态代理，再由 `WKWebView` 访问

## 目录

- `Sources/OpenClawManagerNative/main.swift`: 原生桌面壳
- `runtime/ui-server.mjs`: 本地静态代理和 `/api` 转发
- `scripts/sync-runtime.sh`: 构建并同步 `codex-pool-management`
- `scripts/build-app.sh`: 生成 `.app`
- `scripts/package-app.sh`: 生成 app zip
- `scripts/package-dmg.sh`: 生成 dmg 安装包
- `scripts/package-pkg.sh`: 生成 pkg 安装包
- `scripts/package-delivery.sh`: 生成可直接发人的完整交付包

## 使用

最终用户使用说明见 [USAGE.md](./USAGE.md)。

如果你要直接发给别人安装，优先附上 [QUICKSTART.md](./QUICKSTART.md)。

开发运行：

```bash
cd /Users/Zhuanz/work-space/openclaw-manager-native
bash ./scripts/sync-runtime.sh
swift run OpenClawManagerNative
```

打 app：

```bash
bash ./scripts/build-app.sh
```

打 app zip：

```bash
bash ./scripts/package-app.sh
```

打 dmg：

```bash
bash ./scripts/package-dmg.sh
```

打 pkg：

```bash
bash ./scripts/package-pkg.sh
```

做公证并重新封装 zip：

```bash
OPENCLAW_NOTARY_KEYCHAIN_PROFILE="你的 profile 名称" \
bash ./scripts/notarize-app.sh
```

打完整交付包：

```bash
bash ./scripts/package-delivery.sh
```

## 原生菜单

桌面版除了主窗口，还会在 macOS 顶部菜单栏放一个常驻小工具。

你可以直接从菜单栏里完成这些高频动作：

- 查看当前激活账号和推荐账号
- 查看自动切换是否开启
- 直接切到推荐账号
- 直接切到任意已发现账号
- 直接开启或关闭自动切换
- 立即执行一轮探测
- 打开主窗口

桌面版内也可以直接：

- 选择 `OpenClaw` 根目录
- 选择 `Codex` 根目录
- 打开设置文件
- 打开应用数据目录
- 打开 Manager 状态目录
- 重启本地服务并刷新窗口

## 当前边界

- 当前打包链路默认是 `Apple Silicon / arm64`
- 默认会自动签名：优先使用本机 `Developer ID Application`，找不到就退回 `ad-hoc` 签名
- 如果要在别人电脑上更顺利安装，仍建议使用 `Developer ID + notarization`
- 核心账号管理逻辑仍复用现有的 `codex-pool-management`
- Web 控制台兼容独立部署，native 版负责更快的本地体验和分发

## 签名与公证

- 本机如果没有 `Developer ID Application` 证书，构建脚本会自动使用 `ad-hoc` 签名，至少保证 `.app` 不是无效签名 bundle。
- 如果你已经安装了 `Developer ID Application` 证书，脚本会自动使用它，并启用 hardened runtime。
- 公证使用 `notarytool` 的 keychain profile。可先手动保存：

```bash
xcrun notarytool store-credentials "你的 profile 名称" \
  --apple-id "你的 Apple ID" \
  --team-id "你的 Team ID" \
  --password "app-specific password"
```


## Watchdog

如果你的 OpenClaw 对话偶发卡死，可以启用本机 watchdog 守护进程。它会持续监控 `gateway.log`、会话锁和 gateway 进程状态；检测到 `embedded run timeout`、`lane wait exceeded`、`Slow listener detected` 或长时间卡住的会话锁时，会自动重启 `ai.openclaw.gateway`。

最终用户优先直接在 app 菜单里操作：

```text
稳定守护 -> 启用稳定守护
稳定守护 -> 查看守护状态
稳定守护 -> 立即巡检并恢复
稳定守护 -> 停用稳定守护
```

如果你在源码目录里调试，也可以继续用脚本：

安装：

```bash
bash ./scripts/install-watchdog.sh
```

单次检查：

```bash
node ./scripts/openclaw-watchdog.mjs --once --check-only
```

查看守护状态：

```bash
bash ./scripts/watchdog-status.sh
```

卸载：

```bash
bash ./scripts/uninstall-watchdog.sh
```
