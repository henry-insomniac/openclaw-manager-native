# OpenClaw Manager Native 使用说明

这份文档面向第一次接触 `OpenClaw Manager Native` 的用户。

目标不是解释内部实现，而是让你在第一次安装之后，能顺利完成下面这件事：

- 正常打开软件
- 让软件找到你本机的 OpenClaw / Codex 配置
- 在主界面里看到正确的 profile 和状态

## 先知道它是什么

`OpenClaw Manager Native` 是一个运行在你自己 Mac 上的本地管理工具。

它主要负责：

- 统一查看和管理本机的 OpenClaw 配置目录
- 统一查看和管理本机的 Codex 配置目录
- 让 profile、状态和切换逻辑集中展示在一个界面里

它不是远程托管服务，也不是共享账号平台。你的目录、配置和状态都保留在本机。

## 适用环境

- macOS 13 及以上
- 当前构建版本为 Apple Silicon / arm64

## 第一次安装前，你只需要确认一件事

你本机里是否已经有这些目录中的至少一部分：

- `.openclaw`
- `.openclaw-某个名字`
- `.codex`
- `.codex-某个名字`

如果你之前已经在这台机器上使用过 OpenClaw 或 Codex，大概率已经有。

如果你不确定这些目录在哪，先不用紧张，软件安装后也可以通过菜单慢慢指定根目录。

## 安装方式

你会拿到其中一种分发包：

- `OpenClaw Manager Native.dmg`
- `OpenClaw Manager Native-*.zip`

推荐优先使用 `dmg`。

### 如果你拿到的是 DMG

1. 双击打开 `dmg`
2. 将 `OpenClaw Manager Native.app` 拖到 `Applications`
3. 再从 `Applications` 里启动软件

### 如果你拿到的是 ZIP

1. 先解压 `zip`
2. 将 `OpenClaw Manager Native.app` 拖到 `Applications`
3. 再从 `Applications` 里启动软件

## 第一次打开时可能遇到的提示

如果 macOS 提示应用无法直接打开：

1. 打开 `系统设置 -> 隐私与安全性`
2. 找到与该 app 对应的安全提示
3. 选择允许打开
4. 再回到 `Applications` 重新启动

如果你已经允许过一次，后面一般不需要重复处理。

## 第一次启动后会发生什么

正常情况下，软件打开后会自动做这几件事：

1. 启动本地运行环境
2. 启动本地 manager 服务
3. 打开主界面
4. 尝试扫描并读取你本机的 OpenClaw / Codex 配置

第一次启动时，界面可能会有几秒加载时间，这属于正常现象。

## 第一次使用，最推荐的操作顺序

### 第 1 步：先看主界面有没有直接出现 profile

如果你本机的 `.openclaw` 和 `.codex` 本来就在默认 Home 根目录下，软件很可能已经能直接找到它们。

你可以先看主界面是否已经出现：

- 一个或多个 profile 卡片
- active profile
- OpenClaw 状态
- Codex 对应状态

如果这些内容已经出现，说明第一步基本成功。

### 第 2 步：如果没显示正确内容，先检查根目录

如果主界面没有显示 profile，或者显示得不对，最常见原因是：

- OpenClaw 根目录不对
- Codex 根目录不对

这时用菜单设置：

```text
配置 -> 选择 OpenClaw 根目录...
配置 -> 选择 Codex 根目录...
```

### 第 3 步：根目录应该怎么选

这个点最容易让第一次使用的人困惑，直接按下面理解：

- **OpenClaw 根目录**：应该选“包含 `.openclaw` 或 `.openclaw-*` 的父目录”
- **Codex 根目录**：应该选“包含 `.codex` 或 `.codex-*` 的父目录”

举例：

如果你的目录结构是：

```text
/Users/你的用户名/.openclaw
/Users/你的用户名/.openclaw-acct-b
/Users/你的用户名/.codex
/Users/你的用户名/.codex-acct-b
```

那两个根目录都直接选：

```text
/Users/你的用户名
```

如果你的目录结构是：

```text
/Volumes/Data/AIProfiles/.openclaw
/Volumes/Data/AIProfiles/.openclaw-acct-b
/Volumes/Data/CodexProfiles/.codex
/Volumes/Data/CodexProfiles/.codex-acct-b
```

那就分别选：

```text
OpenClaw 根目录 -> /Volumes/Data/AIProfiles
Codex 根目录 -> /Volumes/Data/CodexProfiles
```

一句话判断方法：

- **不要选到 `.openclaw` 本身**
- **也不要选到 `.codex` 本身**
- **要选它们的父目录**

### 第 4 步：设置完目录后，执行一次重启

每次你修改完根目录，都执行一次：

```text
配置 -> 重启服务并刷新窗口
```

这样软件会重新加载本地运行环境，并重新扫描配置。

### 第 5 步：确认第一次配置是否成功

第一次配置成功，通常会有这些明显标志：

- 主界面开始出现 profile 卡片
- 你能看到 active profile
- 你能看到 OpenClaw 状态
- 你能看到 Codex 对应目录或 auth 状态
- 页面不再是空列表或明显错误状态

如果你看到这些内容，说明软件已经成功接上你本机的实际配置。

## 日常怎么使用

第一次配置好之后，平时主要做这些事情。

### 1. 查看当前配置

菜单：

```text
OpenClaw Manager Native -> 查看当前配置
```

这里可以看到：

- 当前 OpenClaw 根目录
- 当前 Codex 根目录
- 设置文件路径
- 当前本地界面地址
- OAuth callback 地址

### 2. 查看和管理 profile

在主界面里可以看到：

- active profile
- OpenClaw 状态
- Codex 对应目录与 auth 状态
- 自动切换相关状态

### 3. 变更目录时重新指定

如果你把 `.openclaw-*` 或 `.codex-*` 挪到了新位置，不需要手改配置文件，直接重新在菜单中选择根目录即可。

### 4. 页面状态不对时重启服务

如果你怀疑界面没有刷新，或者目录刚改完还没反映出来，执行：

```text
配置 -> 重启服务并刷新窗口
```

### 5. 打开本地数据目录

如果你要排查问题，可以在菜单里打开：

```text
配置 -> 打开设置文件
配置 -> 打开应用数据目录
配置 -> 打开 Manager 状态目录
```

## 设置文件和本地数据保存在哪里

默认位于：

```text
~/Library/Application Support/OpenClaw Manager Native/
```

其中最常用的是：

```text
~/Library/Application Support/OpenClaw Manager Native/settings.json
```

## 第一次使用最常见的问题

### 1. 软件能打开，但主界面没看到 profile

优先检查这两件事：

- 根目录有没有选对
- 选完后有没有执行 `配置 -> 重启服务并刷新窗口`

### 2. 我不知道自己的目录应该选哪里

直接记这条规则：

- 选“包含 `.openclaw` / `.openclaw-*` 的父目录”
- 选“包含 `.codex` / `.codex-*` 的父目录”

如果你把隐藏文件显示出来，一般就能很容易确认。

### 3. 页面有内容，但不是我想要的 profile

这通常说明软件找到了某个目录，但不是你真正想用的那组目录。重新检查根目录是否指向了正确的父目录。

### 4. 软件打不开

- 先检查系统安全设置是否允许打开
- 如果是测试包，尽量使用最新重新打包的版本

## 给第一次使用者的最短路径总结

如果你只想要最短版本，就按这个顺序来：

1. 安装 app 到 `Applications`
2. 打开软件
3. 如果看不到 profile，就设置：
   `配置 -> 选择 OpenClaw 根目录...`
   `配置 -> 选择 Codex 根目录...`
4. 再执行：
   `配置 -> 重启服务并刷新窗口`
5. 回到主界面，确认已经显示 profile 和状态

## 补充说明

`OpenClaw Manager Native` 是一个本地自托管的第三方工具。它的目标是统一管理你自己 Mac 上的 OpenClaw / Codex 本地环境，而不是替代官方服务或作为共享账号平台。

