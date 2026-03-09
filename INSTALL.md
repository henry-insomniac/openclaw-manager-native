# OpenClaw Manager Native 安装说明

给 alpha 内测用户的简版说明见 [ALPHA-TEST.md](./ALPHA-TEST.md)。

更完整的首次使用流程见 [USAGE.md](./USAGE.md)。

## 适用范围

- macOS 13+
- Apple Silicon / arm64

## 推荐安装方式

优先使用 `dmg` 安装包。

### 如果你拿到的是 DMG

1. 双击打开 `dmg`
2. 将 `OpenClaw Manager Native.app` 拖到 `Applications`
3. 从 `Applications` 里启动

### 如果你拿到的是 ZIP

1. 先解压 `OpenClaw Manager Native-*.zip`
2. 将 `OpenClaw Manager Native.app` 拖到 `Applications`
3. 从 `Applications` 里启动

## 第一次打开

如果 macOS 拦截应用：

1. 打开 `系统设置 -> 隐私与安全性`
2. 允许该应用打开
3. 返回 `Applications` 再次启动

## 首次配置最短流程

1. 打开软件
2. 如果主界面已经显示 profile，可直接开始使用
3. 如果没有显示 profile，在菜单中设置：

```text
配置 -> 选择 OpenClaw 根目录...
配置 -> 选择 Codex 根目录...
```

4. 然后执行：

```text
配置 -> 重启服务并刷新窗口
```

5. 回到主界面，确认已经能看到 profile 和状态

## 根目录怎么选

- OpenClaw 根目录：选包含 `.openclaw` / `.openclaw-*` 的父目录
- Codex 根目录：选包含 `.codex` / `.codex-*` 的父目录

不要直接选 `.openclaw` 或 `.codex` 本身，要选它们的父目录。

## 应用数据目录

设置文件与本地 manager 状态保存在：

```text
~/Library/Application Support/OpenClaw Manager Native/
```

## 注意

- 当前构建默认会签名；如果分发给其他人，推荐再做 `Developer ID + notarization`
- 当前版本内置了 app 自己需要的 Node 运行时，不依赖用户本机单独安装 Node
