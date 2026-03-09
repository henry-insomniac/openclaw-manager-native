# OpenClaw Manager Native Alpha 内测说明

这是一份给 alpha 内测用户的简版说明。

目标只有一个：让你第一次拿到安装包后，能顺利安装、打开并看到自己的 profile。

## 适用范围

- macOS 13 及以上
- Apple Silicon / arm64
- 接受首次打开时需要在 macOS 里手动允许一次

## 你会拿到什么

通常会收到这些文件中的一部分：

- `OpenClaw Manager Native-*.dmg`
- `OpenClaw Manager Native-*-mac.zip`
- `INSTALL.md`
- `ALPHA-TEST.md`

优先使用 `dmg`。如果没有 `dmg`，再使用 `zip`。

## 安装步骤

### 方式一：DMG

1. 双击打开 `dmg`
2. 将 `OpenClaw Manager Native.app` 拖到 `Applications`
3. 从 `Applications` 中启动

### 方式二：ZIP

1. 解压 `zip`
2. 将 `OpenClaw Manager Native.app` 拖到 `Applications`
3. 从 `Applications` 中启动

## 第一次打开如果被 macOS 拦截

这是当前 alpha 版本的正常现象。

处理方式：

1. 打开 `系统设置 -> 隐私与安全性`
2. 找到与 `OpenClaw Manager Native` 相关的提示
3. 选择允许打开
4. 回到 `Applications` 再次启动

通常只需要处理一次。

## 第一次启动后要做什么

正常情况下，应用打开后会自动加载界面。

请先看页面上是否已经出现 profile 卡片。

### 如果已经出现 profile

说明应用已经找到你本机的 OpenClaw / Codex 配置，通常可以直接开始使用。

### 如果没有出现 profile

请在应用菜单里设置根目录：

```text
配置 -> 选择 OpenClaw 根目录...
配置 -> 选择 Codex 根目录...
```

然后执行：

```text
配置 -> 重启服务并刷新窗口
```

## 根目录怎么选

这个是第一次最容易选错的地方。

规则很简单：

- OpenClaw 根目录：选“包含 `.openclaw` 或 `.openclaw-*` 的父目录”
- Codex 根目录：选“包含 `.codex` 或 `.codex-*` 的父目录”

例子：

如果你的目录是：

```text
/Users/你的用户名/.openclaw
/Users/你的用户名/.openclaw-acct-b
/Users/你的用户名/.codex
/Users/你的用户名/.codex-acct-b
```

那两个根目录都选：

```text
/Users/你的用户名
```

不要直接选 `.openclaw` 或 `.codex` 本身，要选它们的父目录。

## 如何判断已经配置成功

出现下面这些情况，就说明第一次接入基本成功：

- 页面里出现 profile 卡片
- 能看到 active profile
- 能看到 OpenClaw 状态
- 能看到 Codex 配置区块
- 页面不再是空白或持续报错

## 已知限制

当前 alpha 版仍有这些限制：

- 只支持 Apple Silicon / arm64
- 首次安装可能需要手动允许打开
- 还没有 Developer ID 公证后的无感安装体验
- 如果你已经开着旧的 `openclaw` 命令行会话，切换账号后建议关闭旧会话再重新打开

## 如果遇到问题，请反馈这些信息

请把下面内容一起发回：

1. 你使用的是 `dmg` 还是 `zip`
2. 你的 macOS 版本
3. 你的 Mac 是 Apple Silicon 还是 Intel
4. 问题发生在哪一步
5. 问题截图
6. 如果页面能打开，请补一张主界面截图

如果是“找不到 profile”类问题，请额外说明：

- 你的 `.openclaw` 在哪个父目录下
- 你的 `.codex` 在哪个父目录下

## 推荐给内测用户的一句话

如果你只想把一句话发给测试者，可以直接复制这段：

```text
请先把 OpenClaw Manager Native.app 拖到 Applications，再打开。如果第一次被 macOS 拦截，到“系统设置 -> 隐私与安全性”里允许一次。打开后如果没看到 profile，请在菜单里设置 OpenClaw 根目录和 Codex 根目录，然后点“重启服务并刷新窗口”。
```
