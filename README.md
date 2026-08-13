# sol-reliable-control

一个可独立安装的 Codex Sol 主控 skill：负责多代理任务的规划、执行 lane 路由、握手/身份门禁、紧凑证据回收和最终审核。

## 功能说明

- 一个清晰的 Sol 主控负责计划和最终结论；执行 lane 不接管主控，也不能批准整体任务。
- 正常执行只有两条 lane：
  - `luna-max`：默认处理边界清晰、可独立验证，以及范围较窄的困难任务；请求 `gpt-5.6-luna / max`。
  - `sol-xhigh`：处理跨域规划、深度推理、仲裁或最终审核类困难任务；请求 `xhigh` reasoning。
- `sol-xhigh` 的 `xhigh` 不可用时不静默降级，按 `runtime`/`model_identity` 失败处理。
- 同一问题在 `luna-max` 下超过 2 次持续审核失败，或业务不清晰反复引发回归时，停止重试并提交 `sol-xhigh` 处理。
- 握手失败保持 `BLOCKED`，不会让 Sol 直接接管实现，也不会把失败伪装成 worker 结果。
- 原生 Luna 调度优先使用当前线程可见的 `multi_agent_v1__spawn_agent`（`fork_context=false`、`gpt-5.6-luna`、`max`）；`collaboration.spawn_agent` 是独立的旧/兼容 schema，不能混用字段或把它的 Sol/Terra 枚举当成全局能力结论。
- 原生 surface 不可见时，正式使用 `scripts/sol-luna-broker.ps1` 提供的 `HOST_MANAGED` MCP 主启动链路；它固定启动 fresh ephemeral `gpt-5.6-luna / max`，但 `BROKER_RUN_RECEIPT` 和 worker 自报仍不能替代 `HOST_RECEIPT` / `HOST_VERIFIED`。
- app-server 的 fresh `thread/start` 若返回精确 `model=gpt-5.6-luna`、`reasoningEffort=max`，可记录为 `HOST_LAUNCH_RECORDED`；只有同一 turn 没有 `model/rerouted` 且没有冲突的宿主有效身份证据，才升级为 `HOST_VERIFIED`。
- capability snapshot 绑定当前 host 与 controller thread；兄弟线程能看到 Luna 而当前线程看不到时，返回 `THREAD_SURFACE_NOT_VISIBLE`，要求 surface migration/rebind 或 fresh controller thread。
- `FALLBACK` 是显式恢复分支：允许任意安全兼容 lane，但必须标记 `UNVERIFIED`，且只用于低风险、窄范围、可独立验证的任务。
- 只传结构化 packet、验证摘要和 evidence 路径，不导入 worker 全量推理，避免污染主控上下文。
- 不包含仓库操作、部署流程、项目记忆或其他 skill 的生命周期；本包可单独安装，不要求额外 skill 才能理解自身协议。

## 包内容

- `SKILL.md`：主控角色、路由、状态机、握手和审核规则。
- `references/protocol.md`：计划、握手、结果和 fallback packet schema。
- `references/runtime-adapters.md`：Native generic、custom role、host-managed 三类运行面及 capability preflight / receipt / identity 证据契约。
- `references/enablement.md`：LUNA_MAX 必须由宿主启用的请求、响应、验收门禁，以及 `config.toml` 与 host surface 的边界。
- `references/registration.md`：调用者被卡在 Luna/max 前置检查时的注册、刷新、精确调用和恢复步骤。
- `references/registration.md` 同时区分 native worker、CLI custom-role 和显式 user-visible app task；后者不是 native sub-agent，也不能绕过 `No user-owned task` 约束。
- `scripts/sol-luna-broker.ps1`：固定 Luna/max 的本地 STDIO MCP broker，含 fresh/范围/sandbox/receipt 门禁。
- `tests/protocol-contract.ps1`：不依赖宿主的协议契约回归检查。
- `tests/broker-contract.ps1`：MCP initialize、tools/list、ping 和固定 lane 的 broker 契约检查。
- `agents/openai.yaml`：Codex skill 列表的界面元数据。

## 安装

将仓库目录复制到 `$CODEX_HOME/skills/sol-reliable-control`，或使用 Codex skill 安装器从本仓库安装。

运行时仍由宿主提供 native worker dispatch、模型身份和 `HOST_RECEIPT`；当 native surface 不可见时，可注册本包的 MCP broker 作为固定 Luna/max 的操作主链路。CLI broker 的 receipt 和 self-report 仍按 `STARTED_UNVERIFIED` 处理；app-server launch record 是独立的宿主证据层，不能把“分配到 Luna”与“turn 有效身份已验证”混为一谈。

## MCP broker 注册

在 `$CODEX_HOME/config.toml` 添加：

```toml
[mcp_servers.sol_luna_broker]
command = "pwsh"
args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:\\Users\\PC\\.codex\\skills\\sol-reliable-control\\scripts\\sol-luna-broker.ps1"]
enabled = true

[mcp_servers.sol_luna_broker.env]
SOL_LUNA_ALLOWED_ROOTS = "E:\\Sources\\.codex-worktrees;E:\\git\\sol-reliable-control-worktrees;E:\\git\\sol-reliable-control"
```

重启 Codex 后，先调用 `sol_luna_exec` 并保持 `handshake_only=true`；只有收到结构化结果后，Sol 才能决定是否继续。完整注册和证据规则见 [references/registration.md](references/registration.md)。
