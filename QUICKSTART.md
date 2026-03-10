# OpenClaw Manager Native 1.0 快速上手

这份文档给第一次拿到安装包的人。

目标只有一个：尽快装好、打开，并看到自己的 profile。

## 适用范围

- macOS 13+
- Apple Silicon / arm64

## 你会拿到什么

通常会收到这些文件中的一部分：

- `OpenClaw Manager Native-*.dmg`
- `OpenClaw Manager Native-*.pkg`
- `OpenClaw Manager Native-*-mac.zip`
- `INSTALL.md`
- `QUICKSTART.md`

优先级建议：`DMG > PKG > ZIP`。

## 安装步骤

### 方式一：DMG

1. 双击打开 `dmg`
2. 将 `OpenClaw Manager Native.app` 拖到 `Applications`
3. 从 `Applications` 启动

### 方式二：PKG

1. 双击打开 `pkg`
2. 按安装向导完成安装
3. 从 `Applications` 启动

### 方式三：ZIP

1. 解压 `zip`
2. 将 `OpenClaw Manager Native.app` 拖到 `Applications`
3. 从 `Applications` 启动

## 第一次打开如果被 macOS 拦截

如果系统阻止打开：

1. 打开 `系统设置 -> 隐私与安全性`
2. 找到与 `OpenClaw Manager Native` 对应的提示
3. 允许打开
4. 回到 `Applications` 再次启动

通常只需要处理一次。

## 第一次启动后要做什么

请先看页面上是否已经出现 profile 卡片。

### 如果已经出现 profile

说明 app 已经找到你本机的 OpenClaw / Codex 配置，可以直接开始使用。

### 如果没有出现 profile

请在菜单里设置根目录：

```text
配置 -> 选择 OpenClaw 根目录...
配置 -> 选择 Codex 根目录...
```

然后执行：

```text
配置 -> 重启服务并刷新窗口
```

## 根目录怎么选

规则很简单：

- OpenClaw 根目录：选“包含 `.openclaw` 或 `.openclaw-*` 的父目录”
- Codex 根目录：选“包含 `.codex` 或 `.codex-*` 的父目录”

例子：

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

出现下面这些情况，就说明第一次接入成功：

- 页面里出现 profile 卡片
- 能看到 active profile
- 能看到 OpenClaw 状态
- 能看到 Codex 配置区块
- 页面不再是空白或持续报错

## 已知边界

- 当前正式包仍只支持 Apple Silicon / arm64
- 如果没有做 `Developer ID + notarization`，首次安装仍可能需要手动允许打开
- 如果你已经开着旧的 `openclaw` 或 `codex` 会话，切换账号后建议关闭旧会话再重新打开

## 快速反馈时请附带这些信息

1. 你使用的是 `dmg`、`pkg` 还是 `zip`
2. 你的 macOS 版本
3. 你的机器是 Apple Silicon 还是 Intel
4. 问题发生在哪一步
5. 问题截图

如果是“找不到 profile”，请额外说明：

- `.openclaw` 的父目录在哪里
- `.codex` 的父目录在哪里

## 一句话发给使用者

```text
请先把 OpenClaw Manager Native.app 安装到 Applications，再打开。如果第一次被 macOS 拦截，到“系统设置 -> 隐私与安全性”里允许一次。打开后如果没看到 profile，请在菜单里设置 OpenClaw 根目录和 Codex 根目录，然后点“重启服务并刷新窗口”。
```
