# OpenClaw 配置中心状态跟踪（2026-03-13）

## 当前执行切片

- 范围：M1 只读配置中心 + M2 技能市场 MVP + skills 启停 / `extraDirs` / watcher / install 管理 + profile 受控编辑（active / inactive 第一批）
- 目标：
  - 先落 `skills` 只读管理面与配置中心骨架
  - 再补精选市场、托管安装、托管卸载
  - 补齐库存与详情页内的 skills 启用 / 停用闭环
  - 补齐设置页里 `extraDirs` 的新增 / 移除闭环
  - 补齐设置页里目录监听与防抖时间的保存闭环
  - 补齐设置页里安装工具偏好的保存闭环
  - 补齐 active profile 的 preview / apply 安全编辑闭环
  - 补齐 inactive profile 同白名单字段的 preview / apply / rollback 闭环
- 原则：
  - 功能测试必须覆盖
  - App 性能测试必须记录
  - 新增能力不得拖慢监控与诊断主链路

## 任务状态

- `TRACK-001` 状态跟踪器建立：已完成
- `M1-001` daemon：`GET /api/openclaw/skills`：已完成
- `M1-002` daemon：`GET /api/openclaw/skills/config`：已完成
- `M1-003` Swift：skills 只读数据模型与 bridge：已完成
- `M1-004` Swift：设置页接入全局 Skills 只读页：已完成
- `M1-005` 文档：本地 API 文档补齐：已完成
- `M1-006` 测试：功能测试与性能测试回填：已完成
- `M1-007` daemon/UI：`POST /api/openclaw/profiles/{profileName}/config/validate` 与 Profiles 配置卡校验动作：已完成
- `M2-001` daemon：`GET /api/openclaw/skills/market`：已完成
- `M2-002` daemon：`GET /api/openclaw/skills/market/{slug}`：已完成
- `M2-003` daemon：`GET /api/openclaw/skills/inventory`：已完成
- `M2-004` daemon：`POST /api/openclaw/skills/install`：已完成
- `M2-005` daemon：`POST /api/openclaw/skills/uninstall`：已完成
- `M2-006` Swift：新增顶级“技能”页面与安装/卸载动作：已完成
- `M2-007` 测试：market/install/uninstall 覆盖：已完成
- `M2-008` App 打包并覆盖 `/Applications`：已完成
- `M2-009` daemon：`POST /api/openclaw/skills/{skillKey}/enable|disable`：已完成
- `M2-010` Swift：库存 / 详情页接入 skills 启用 / 停用动作：已完成
- `M2-011` 测试：skills 启停配置写回覆盖：已完成
- `M2-012` daemon：`PATCH /api/openclaw/skills/config`（`extraDirs` 最小 patch）：已完成
- `M2-013` Swift：设置页接入 `extraDirs` 新增 / 移除：已完成
- `M2-014` 测试：`extraDirs` 配置写回覆盖：已完成
- `M2-015` daemon：`PATCH /api/openclaw/skills/config` 支持 `watch` / `watchDebounceMs`：已完成
- `M2-016` Swift：设置页接入目录监听与防抖时间保存：已完成
- `M2-017` 测试：watcher 配置写回覆盖：已完成
- `M2-018` daemon：`PATCH /api/openclaw/skills/config` 支持 `install.preferBrew` / `install.nodeManager`：已完成
- `M2-019` Swift：设置页接入安装工具偏好保存：已完成
- `M2-020` 测试：install 配置写回覆盖：已完成
- `M2-021` daemon：`POST /api/openclaw/profiles/{profileName}/config/preview|apply`：已完成
- `M2-022` Swift：Profiles 配置卡接入 active profile 安全编辑：已完成
- `M2-023` 测试：preview/apply、冲突控制与回滚 smoke：已完成
- `M3-001` daemon：inactive profile 受控编辑沿用同一 `preview|apply` 路由，改为文件级 patch + validate + rollback：已完成
- `M3-002` Swift：Profiles 配置卡开放 inactive profile 受控编辑，并明确“切换后生效”文案：已完成
- `M3-003` 测试：inactive profile preview/apply + 备份覆盖：已完成

## 测试门禁

- Go 构建：已通过
- Swift 构建：已通过
- 自动化测试：已通过（`go test ./cmd/openclaw-manager-daemon ./cmd/openclaw-watchdog`、`swift test`）
- 本地功能验证：M1 / M2 / M3 第一批已通过（自动化已覆盖 inactive profile `preview/apply`、备份与回滚；`bash ./scripts/build-app.sh` 已通过，最新 app 已写入 `.build/app` 与 `release/`）
- App 性能验证：已通过轻量验证（安装版 skills API 响应约 `0.75-5.96ms`）

## 性能门禁

- 监控页轮询频率不得增加
- 诊断页 `full` 刷新链路不得新增 skills 请求
- `skills` 数据加载仅允许挂在设置页、技能页或显式刷新链路
- 新增本地 API 需要有缓存或延迟加载策略

## 当前判断

- `openclaw skills list --json` 与 `openclaw skills check --json` 可直接提供稳定 JSON
- `openclaw --profile <name> config validate` 可直接覆盖 profile 级显式校验，不需要自己猜 state dir 环境变量
- `skills` 配置需要从 `openclaw.json` 读取，并对 `apiKey` / `env` 做摘要化展示
- `skills.allowBundled` 在当前 OpenClaw 实现中是 allowlist 数组，不是布尔值
- profile 受控编辑当前只开放白名单字段，并用 `baseHash + validate + rollback` 保守落地；active 立即生效并校验，inactive 先写账号文件、切换后生效
- 技能市场采用三层结构：
  - awesome repo 作为精选目录层
  - ClawHub 作为详情与下载层
  - 本地 inventory 作为真实安装状态层
- 市场安装写入 Manager 托管目录，并通过 `skills.load.extraDirs` 接入 OpenClaw
