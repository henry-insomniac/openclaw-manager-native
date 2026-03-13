# Local API

OpenClaw Manager Native 的本地 API 由 `openclaw-manager-daemon` 提供，默认监听在：

```text
http://127.0.0.1:3311
```

这套 API 的定位是：

- 给原生 SwiftUI 界面使用
- 给本机菜单栏动作、诊断页和维护动作使用
- 给本机调试和自动化脚本使用

它不是公网服务，也不是稳定对外承诺的 SaaS API。默认假设运行环境是本机 `localhost`。

## 路由列表

### `GET /api/health`

作用：

- 健康检查
- 给原生壳判断 daemon 是否启动成功

返回：

- `{"ok": true}`

### `GET /api/openclaw/manager`

作用：

- 返回主控制台摘要
- 提供当前 active profile、recommended profile、automation 状态、runtime 概览和所有已发现 profile 的快照

主要用于：

- 首页
- 账号池/切换面板
- 菜单栏状态

### `GET /api/openclaw/system`

作用：

- 返回 runtime 级别概览
- 聚合当前根目录、daemon 运行参数、切换统计和兼容性信息

主要用于：

- 调试
- 系统概览
- 运行时自检

### `GET /api/openclaw/profiles/{profileName}/config/summary`

作用：

- 返回指定 profile 的本地配置摘要
- 聚合 `openclaw.json` 与 `auth-profiles.json` 的存在性、可读性、更新时间，以及当前主 provider / 主模型 / 登录方式判断

主要用于：

- Profiles 页的配置中心卡片
- Profile 级配置排查
- 只读配置可视化入口

返回字段重点：

- `configPath` / `authStorePath`
- `configExists` / `authStoreExists`
- `configValid` / `authStoreValid`
- `configDetail` / `authStoreDetail`
- `primaryProviderId` / `primaryModelId`
- `configuredProviderIds`
- `authModes`
- `loginKind`
- `companionRuntimeKind`

### `GET /api/openclaw/profiles/{profileName}/config/document`

作用：

- 返回指定 profile 的配置摘要和原始文件内容
- 在摘要之外附带 `openclaw.json` / `auth-profiles.json` 的原始文本与内容哈希

主要用于：

- 配置详情展开
- 本地问题排查
- 后续差异预览与回滚能力的基础数据源

返回字段重点：

- `summary`
- `rawConfig`
- `rawAuthStore`
- `configHash`
- `authStoreHash`

说明：

- 当前是只读接口，不负责写回
- 哈希用于后续比对，不暴露任何额外密钥明文

### `POST /api/openclaw/profiles/{profileName}/config/validate`

作用：

- 对指定 profile 显式执行一次 OpenClaw CLI 配置校验
- 复用 `openclaw --profile <name> config validate`，不把重校验塞回常规 settings 刷新

主要用于：

- Profiles 页“校验这个配置”按钮
- active profile 安全编辑前的手动校验链路
- 后续 preview / apply 前的统一校验基线

返回字段重点：

- `profileName`
- `configPath`
- `valid`
- `detail`
- `output`

说明：

- 该接口是显式动作，不参与后台常规轮询
- 输出会过滤已知的 Node deprecation 噪音，尽量只保留真实校验结果

### `POST /api/openclaw/profiles/{profileName}/config/preview`

作用：

- 对当前激活中的 profile 生成一份安全编辑预览
- 只允许白名单字段 patch，不开放通用 JSON 任意写

主要用于：

- Profiles 页 active profile 的“安全编辑”预览按钮
- 在应用前先看字段级差异和完整 `openclaw.json` 预览

请求体：

- `baseHash`
  - 来自 `GET /api/openclaw/profiles/{profileName}/config/document`
- `patch.primaryProviderId`
- `patch.primaryModelId`
- `patch.authMode`

说明：

- 当前只允许编辑激活中的 profile
- 当前白名单仅覆盖 `primaryProviderId`、`primaryModelId`、`authMode`
- `primaryModelId` 必须是 `provider/model` 形式
- `primaryProviderId` 必须与 `primaryModelId` 的 provider 前缀一致
- `baseHash` 不匹配时返回 `409`，避免把旧草稿覆盖到新配置

返回字段重点：

- `baseHash` / `nextHash`
- `changed`
- `message`
- `changes`
  - 字段级差异，当前包含“主 Provider / 主模型 / 认证模式”
- `previewConfig`
  - 预览后的完整 `openclaw.json`

### `POST /api/openclaw/profiles/{profileName}/config/apply`

作用：

- 把 active profile 的安全编辑预览真正写回 `openclaw.json`
- 写回后立即执行一次 profile config validate

主要用于：

- Profiles 页 active profile 的“应用配置”动作

请求体：

- 与 `POST /api/openclaw/profiles/{profileName}/config/preview` 相同

说明：

- 当前只允许编辑激活中的 profile
- 写回前会先备份原始 `openclaw.json`
- 应用后会立即执行 `openclaw --profile <name> config validate`
- 如果写回后的校验失败，会自动回滚原始文件

返回字段重点：

- `ok`
- `appliedHash`
- `changed`
- `message`
- `changes`
- `validation`
  - 应用后那次显式校验的结果

### `GET /api/openclaw/skills/config`

作用：

- 返回全局 `skills` 配置摘要
- 从默认 profile 的 `openclaw.json` 提取 `allowBundled`、`load`、`install` 与 `entries` 的非敏感摘要

主要用于：

- 设置页的全局 Skills 配置卡片
- 配置中心的只读技能设置入口

返回字段重点：

- `allowBundled`
  - bundled skills allowlist；为空数组表示未限制
- `extraDirs`
- `watch`
- `watchDebounceMs`
- `installPreferBrew`
- `installNodeManager`
- `entryCount`
- `entries`
  - 仅返回 `enabled`、是否存在 `env`、是否存在 `apiKey`，不回传敏感值

### `PATCH /api/openclaw/skills/config`

作用：

- 修改默认 profile `openclaw.json` 里的 `skills` 配置
- 当前支持 `skills.load.extraDirs`、`skills.load.watch` / `skills.load.watchDebounceMs`、`skills.install.preferBrew` / `skills.install.nodeManager` 的最小 patch

请求体：

- `addExtraDir`
  - 新增一个额外挂载目录
- `removeExtraDir`
  - 移除一个额外挂载目录
- `watch`
  - 是否开启目录监听
- `watchDebounceMs`
  - 目录监听触发后的防抖时间，单位毫秒
- `installPreferBrew`
  - 是否优先使用 Homebrew 安装依赖
- `clearInstallPreferBrew`
  - 清除 `skills.install.preferBrew`
- `installNodeManager`
  - 指定安装时优先使用的 Node 管理器
- `clearInstallNodeManager`
  - 清除 `skills.install.nodeManager`

说明：

- 一次请求只允许提交一组变更
- `addExtraDir` 和 `removeExtraDir` 不能同时提交
- 目录变更、监听配置变更、安装配置变更不能混在同一个请求里
- 写回前会先备份原始 `openclaw.json`
- 当前是最小 patch，不支持全量 `skills` 配置替换
- `watchDebounceMs` 必须大于 `0`
- `installPreferBrew` / `installNodeManager` 支持显式清空，回到“未配置”状态

返回字段重点：

- `ok`
- `action`
  - `add-extra-dir` / `remove-extra-dir` / `update-watch` / `update-install`
- `path`
- `message`
- `configPath`

### `GET /api/openclaw/skills`

作用：

- 返回当前本机 Skills 总览
- 聚合 `openclaw skills list --json` 的实时结果与本地 `skills` 配置摘要

查询参数：

- `fresh=1`
  - 强制重新执行 `openclaw skills list --json`
  - 不命中 daemon 的短 TTL 缓存

默认行为：

- 不带 `fresh=1` 时命中 daemon 的短缓存
- 仅供设置页或显式刷新使用，不挂到监控/诊断高频链路

返回字段重点：

- `workspaceDir`
- `managedSkillsDir`
- `totalSkills` / `readySkills` / `disabledSkills` / `blockedSkills` / `missingSkills`
- `configuredSkills`
- `skills`
  - 单项包含名称、来源、状态、缺失依赖摘要、配置是否已写入等

### `GET /api/openclaw/skills/market`

作用：

- 返回 skills 市场精选目录
- 数据源来自 `awesome-openclaw-skills` 的 README 与分类页
- 只返回精选卡片必需字段，不在列表页暴力拉取每个 ClawHub 详情

查询参数：

- `fresh=1`
  - 强制重新抓取 awesome 目录，不命中 daemon 内存缓存

返回字段重点：

- `sourceRepo`
- `managedDirectory`
- `totalItems`
- `categories`
  - 分类 ID、标题与数量
- `items`
  - 单项包含 `slug`、名称、简介、owner、GitHub 源链接、ClawHub 页面链接、所属分类

说明：

- 这是“精选目录层”，不是安装状态的权威来源
- 已安装状态请结合 `/api/openclaw/skills/inventory`

### `GET /api/openclaw/skills/market/{slug}`

作用：

- 返回单个 market skill 的详情
- 从 ClawHub 拉取版本、下载量、stars、moderation 和 metadata

主要用于：

- 技能详情卡片
- 安装前风险提示
- 打开源码 / ClawHub 落地页前的元数据展示

返回字段重点：

- `item`
- `stats`
- `latestVersion`
- `metadata`
- `owner`
- `moderation`

### `GET /api/openclaw/skills/inventory`

作用：

- 返回本机“可管理技能库存”
- 合并 OpenClaw 运行时可见 skills、Manager 自己的托管安装目录、`.clawhub/lock.json` 与 `origin.json`

查询参数：

- `fresh=1`
  - 强制重新读取 OpenClaw runtime skills 状态

返回字段重点：

- `managedDirectory`
- `lockPath`
- `runtimeError`
  - 运行时扫描失败时保留错误，但仍返回 manager-owned 安装记录
- `managerInstalled` / `personalInstalled` / `bundledInstalled` / `workspaceInstalled` / `globalInstalled` / `externalInstalled`
- `items`
  - 单项包含来源、是否 manager-owned、是否允许一键卸载、运行时状态、安装版本与安装时间

来源语义：

- `manager-installed`
  - 由 OpenClaw Manager Native 安装到托管目录，可一键卸载
- `personal`
  - 本机已有的个人 / 本地自定义 skills，只做可视化，不直接删除
- `bundled`
  - OpenClaw 自带技能，不提供删除

### `POST /api/openclaw/skills/install`

作用：

- 将指定 market skill 安装到 Manager 托管目录
- 自动把托管目录追加到默认 profile `openclaw.json` 的 `skills.load.extraDirs`
- 安装完成后写入 `.clawhub/origin.json` 与 `.clawhub/lock.json`

请求体：

- `slug`

返回字段重点：

- `ok`
- `action`
- `slug`
- `message`
- `installDirectory`
- `installedVersion`

说明：

- 当前是同步安装接口，前端直接等待完成
- 只写入 Manager 自己的托管目录，不直接覆盖用户手工安装目录

### `POST /api/openclaw/skills/uninstall`

作用：

- 从 Manager 托管目录卸载指定 skill
- 删除对应目录，并更新 `.clawhub/lock.json`

请求体：

- `slug`

说明：

- 只允许卸载 manager-owned skills
- 手工安装、workspace 技能和 bundled 技能不会被这个接口直接删除

### `POST /api/openclaw/skills/{skillKey}/enable`

作用：

- 启用指定 skill
- 直接写回默认 profile `openclaw.json` 里的 `skills.entries.<skillKey>.enabled`
- 如果请求体声明这是 bundled skill，会顺带补齐 `skills.allowBundled`

请求体：

- `bundled`
  - 布尔值；前端从 inventory 直接带入，避免 daemon 自己猜来源

返回字段重点：

- `ok`
- `action`
- `slug`
- `message`

说明：

- 只改 skills 配置，不直接做安装
- 写回前会给现有 `openclaw.json` 留本地备份
- 该接口设计给用户显式点击使用，不参与后台轮询

### `POST /api/openclaw/skills/{skillKey}/disable`

作用：

- 停用指定 skill
- 直接写回默认 profile `openclaw.json` 里的 `skills.entries.<skillKey>.enabled = false`

请求体：

- `bundled`
  - 当前只用于和启用接口保持统一请求形状

说明：

- 停用时不会直接删除 bundled allowlist 项，避免下一次刷新把“显式停用”误读成“未允许”
- 同样会在写回前保留本地备份

### `GET /api/machine/summary`

作用：

- 返回轻量机器监控摘要
- 聚合 CPU、内存、swap、磁盘剩余、网络吞吐，以及 manager / watchdog 进程状态
- 即使本机暂时没有 OpenClaw，也能返回 machine-only 模式需要的状态

查询参数：

- `fresh=1`
  - 跳过短 TTL 缓存，强制重新采样

默认行为：

- 不带 `fresh=1` 时走 daemon 的短缓存
- 适合监控页高频轮询，不会触发重诊断

返回字段重点：

- `openclaw`: 本机是否发现 OpenClaw CLI，以及发现路径 / 来源
- `cpu`: 当前机器 CPU 活跃度，以及 `user / system / idle` 口径
- `memory`: 内存结构和压力口径，包含 `wired / active / cache / free / other / compressed`
- `swap`: 当前 swap 总量、已用量和占比
- `disk`: 当前系统盘路径、总量、已用量和剩余量
- `network`: 主网卡、当前上下行速率、累计收发流量
- `processes.manager` / `processes.watchdog`: manager 与 watchdog 的运行状态、PID、CPU、RSS 和运行时长
- `topProcesses`: 当前按 CPU 排序的前 10 个进程，包含进程名、PID、CPU、RSS、运行时长和完整命令行

### `PATCH /api/openclaw/settings`

作用：

- 更新 manager 的自动切换和探测参数

支持字段：

- `autoActivateEnabled`
- `pollIntervalMs`
  - 兼容旧字段，后端会换算成 probe window
- `probeIntervalMinMs`
- `probeIntervalMaxMs`
- `fiveHourDrainPercent`
- `weekDrainPercent`
- `autoSwitchStatuses`

返回：

- 更新后的完整 `ManagerSummary`

### `POST /api/openclaw/automation/tick`

作用：

- 立即执行一轮自动切换判断
- 根据当前 profile 状态决定是否切换到 recommended profile

返回：

- `AutomationTickResult`
- 包含是否发生切换、从哪个 profile 切到哪个 profile、原因和最新 `ManagerSummary`

### `POST /api/openclaw/profiles`

作用：

- 创建一个新的 managed profile scaffold

请求体：

```json
{
  "profileName": "acct-a"
}
```

返回：

- 新建 profile 的 `ManagedProfileSnapshot`

### `POST /api/openclaw/profiles/{profileName}/probe`

作用：

- 单独重探测某个 profile
- 重新读取该 profile 的配置、provider、认证状态和 quota/health 信息

返回：

- 当前 profile 的最新 `ManagedProfileSnapshot`

### `POST /api/openclaw/profiles/{profileName}/login`

作用：

- 为支持内置登录的 profile 启动登录流程
- 当前主要用于支持 `codex-oauth` 的 profile

返回：

- `202 Accepted`
- `LoginFlowSnapshot`

说明：

- 如果当前 profile 不支持内置登录，会返回错误
- 非 Codex provider 不会被强行伪装成可登录

### `GET /api/openclaw/login-flows/{flowId}`

作用：

- 轮询某次登录流程的状态

返回：

- `LoginFlowSnapshot`

状态字段通常包括：

- `pending`
- `failed`
- `completed`

### `POST /api/openclaw/profiles/{profileName}/activate`

作用：

- 激活指定 profile
- 同步默认 `.openclaw` 槽位
- 更新 active/recommended 相关 runtime 状态

返回：

- 最新 `ManagerSummary`

### `POST /api/openclaw/activate-recommended`

作用：

- 直接激活当前推荐 profile

返回：

- 最新 `ManagerSummary`

### `GET /api/support/summary`

作用：

- 返回诊断中心摘要
- 汇总 gateway、Discord、watchdog、环境风险、OpenClaw 配置与服务维护状态

查询参数：

- `fresh=1`
  - 强制重跑深检查
  - 不走 support 缓存

默认行为：

- 不带 `fresh=1` 时优先命中 daemon 缓存
- 用于常驻轮询和低成本刷新

### `POST /api/support/repair`

作用：

- 执行诊断中心里的维护动作
- 动作完成后回收最新 `SupportSummary`

请求体：

```json
{
  "action": "validate_config"
}
```

当前支持动作：

- `validate_config`
  - 执行 `openclaw config validate`
- `run_openclaw_doctor`
  - 执行 `openclaw doctor --non-interactive`
- `run_openclaw_doctor_fix`
  - 执行 `openclaw doctor --fix --yes --non-interactive`
- `reinstall_gateway_service`
  - 执行 `openclaw gateway install --force`
- `run_watchdog_check`
  - 执行内置 watchdog 单次巡检
- `restart_gateway`
  - 重启 OpenClaw gateway
- `reinstall_watchdog`
  - 重新部署稳定守护

返回：

- `SupportRepairResult`
- 包含：
  - `ok`
  - `action`
  - `message`
  - `output`
  - `summary`

### `GET /auth/callback`

作用：

- OAuth 回调入口
- 给内置登录流程使用

说明：

- 这是登录链路的内部回调端点
- 不是给用户直接调用的业务 API

## 典型调用顺序

### 首页 / 账号池

1. `GET /api/health`
2. `GET /api/openclaw/manager`

### 手动切换 profile

1. `POST /api/openclaw/profiles/{profileName}/activate`
2. 读取返回的 `ManagerSummary`

### 诊断页常驻刷新

1. `GET /api/support/summary`

### 监控页常驻刷新

1. `GET /api/machine/summary`

### 诊断页手动强刷

1. `GET /api/support/summary?fresh=1`

### 执行维护动作

1. `POST /api/support/repair`
2. 读取返回的 `SupportRepairResult.summary`

## 说明

- 这套 API 运行在本机，主要面向桌面壳和本地自动化，不建议直接暴露到公网。
- 字段会随着 native app 和 daemon 一起演进；如果你要在外部脚本里用，建议优先依赖高层语义而不是把所有内部字段写死。
