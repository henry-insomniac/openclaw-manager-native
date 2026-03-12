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
