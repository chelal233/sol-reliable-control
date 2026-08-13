# sol-reliable-control

一个可独立安装的 Codex Sol 主控 skill：负责多代理任务的规划、执行 lane 路由、握手/身份门禁、紧凑证据回收和最终审核。

语言 / Language: [简体中文](README.md) · [English](README.en.md)

## 功能说明

- 一个清晰的 Sol 主控负责计划和最终结论；执行 lane 不接管主控，也不能批准整体任务。
- 正常执行只有两条 lane：
  - `luna-max`：默认处理边界清晰、可独立验证，以及范围较窄的困难任务；请求 `gpt-5.6-luna / max`。
  - `sol-xhigh`：处理跨域规划、深度推理、仲裁或最终审核类困难任务；请求 `xhigh` reasoning。
- `sol-xhigh` 的 `xhigh` 不可用时不静默降级，按 `runtime`/`model_identity` 失败处理。
- 同一问题在 `luna-max` 下超过 2 次持续审核失败，或业务不清晰反复引发回归时，停止重试并提交 `sol-xhigh` 处理。
- 握手失败保持 `BLOCKED`，不会让 Sol 直接接管实现，也不会把失败伪装成 worker 结果。
- `BLOCKED` 只终止当前实现派发；若仍有安全的宿主修复路径，必须向调用者返回 `HOST_REMEDIATION_REQUIRED`，明确权限申请、外部变更、最小 read-only 探针和下一步，而不是只说“等待”。
- 恢复顺序固定为：native 握手 →（用户明确允许时）Desktop task 握手 → MCP 握手 → 用户/宿主批准最小注册或 sandbox/token 修复 → 刷新/重绑 → 必要时的新 task 最小 PowerShell 探针；探针成功前不重试实现包。
- `LUNA_MAX` 正常调度采用“原生优先、Desktop task 次选、MCP 最后”（native-first -> Desktop-task -> MCP）：第一优先使用当前线程可见且契约匹配的 `multi_agent_v1__spawn_agent`，或未来等价、由宿主声明且可验证的 native surface。
- native 失败后，只有在计划允许 user-owned task 且用户明确批准时，才使用第二优先 Desktop task；Desktop 未获批准或握手失败后，使用第三优先 `HOST_MANAGED` MCP。MCP 不是 native subagent，也不是静默 model fallback；三条路线都不可用时保持原模型并按现有规则返回 `BLOCKED`。
- `USER_VISIBLE_TASK` 参考 `sol-advisor` 的做法，但它不是启用 Luna 的手段；它仍需独立的 host-observed identity evidence。
- 该桌面任务路线不启动 Sol 本地 broker、不调用 `setupStart`、不执行 PowerShell、不修改任何 ACL；若宿主仍报告 `PROCESS_CREATION_DENIED` 或 sandbox 权限错误，只记录执行阻塞并停止，不申请扩大权限。
- `collaboration.spawn_agent` 是独立的旧/兼容 schema，不能冒充 canonical `multi_agent_v1__spawn_agent`、混用字段、借用其 capability/receipt，或把自身的 Sol/Terra 枚举当成全局能力结论。
- broker 默认使用 app-server 的 fresh `thread/start`；若返回精确 `model=gpt-5.6-luna`、`reasoningEffort=max`，先记录为 `HOST_LAUNCH_RECORDED`，同一 turn 无 `model/rerouted` 时身份可升级为 `VERIFIED`。`SOL_LUNA_TRANSPORT=cli` 仅保留为旧版诊断路线。
- broker 将身份与执行分开报告：匹配的 launch record 且无 reroute 时 `identity=VERIFIED`，即使执行因 Windows sandbox ACL 或进程创建拒绝而 `BLOCKED`；只有 `identity=VERIFIED` 且 `execution_status=COMPLETED` 才返回整体 `HOST_VERIFIED`。MCP payload 会给出脱敏后的 `execution_blocker_code` 与 `execution_blocker`，其中明确区分 `WINDOWS_SANDBOX_ACL_FAILED` 和 `PROCESS_CREATION_DENIED`。
- capability snapshot 绑定当前 host 与 controller thread；兄弟线程能看到 Luna 而当前线程看不到时，记录 `THREAD_SURFACE_NOT_VISIBLE`，先评估第二优先 Desktop task；Desktop 未获批准或不可用时再检查第三优先 MCP；两者都不可用时才要求 surface migration/rebind 或 fresh controller thread。
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
- `references/desktop-task-lane.md`：显式 Desktop Luna task 的调用字段、fresh/history、receipt/identity 门禁与 ACL 禁止边界。
- `scripts/sol-luna-broker.ps1`：固定 Luna/max 的本地 STDIO MCP broker，含 fresh/范围/sandbox/receipt 门禁，以及长任务异步提交/轮询。
- `tests/protocol-contract.ps1`：不依赖宿主的协议契约回归检查。
- `tests/broker-contract.ps1`：MCP initialize、tools/list、ping 和固定 lane 的 broker 契约检查。
- `tests/privacy-contract.ps1`：源码路径、凭据形态和 broker 输出脱敏契约检查。
- `README.en.md`：English installation, routing, verification, and reference guide。
- `references/sources.md`：完整参考项目、官方资料、关键原则、利弊/陷阱/解决方案及 GitHub 发布门禁清单。
- `agents/openai.yaml`：Codex skill 列表的界面元数据。

## 参考项目与官方文档

完整清单（包括两个参考项目的具体编排文件、官方 MCP/App Server/Subagents、
Luna 模型资料、Windows sandbox 说明、上游 setup 源码和运行问题证据）见
[references/sources.md](references/sources.md)。本项目只借鉴公开设计，不运行时依赖
这些项目，也不复制凭据、用户数据或工作树。
公开参考项目包括 [sol-advisor](https://github.com/DannyMac180/sol-advisor) 和
[codex-sol-control](https://github.com/yehyakin/codex-sol-control)。

## 主要事项与关键要点

1. 路由顺序固定为 Native →（明确批准时）Desktop task → MCP；未批准时不创建 user-owned task。
2. `LUNA_MAX` 始终绑定 `gpt-5.6-luna / max`，`SOL_XHIGH` 绑定 `gpt-5.6-sol / xhigh`，不静默换模型。
3. `TRANSPORT_VERIFIED`、`HOST_LAUNCH_RECORDED`、`HOST_VERIFIED` 分层；UI、self-report、裸 `agent_id` 不能单独证明身份。
4. Desktop task 必须选择正确项目/工作树；projectless 只用于握手，local 目录必须显式授权。
5. Windows sandbox ACL/进程创建失败是宿主执行故障；Sol 不调用 `setupStart`、`icacls`、`Set-Acl` 或扩大权限。
6. MCP 超时使用同一 `job_id` 轮询，禁止重复提交实现包；身份与执行失败分离记录。
7. 发布 GitHub 前必须检查未跟踪文件、秘密、机器路径、旧 worktree、原始日志和许可证归属，并在源/运行时两端运行三组契约测试。

## 安装

将仓库目录复制到 `$CODEX_HOME/skills/sol-reliable-control`，或使用 Codex skill 安装器从本仓库安装。

运行时仍由宿主提供 native worker dispatch、模型身份和 `HOST_RECEIPT`；默认按 Native → Desktop task → MCP 选择 Luna/max 路线。默认 app-server 路线返回宿主 launch record；CLI 诊断路线的 receipt 和 self-report 仍按 `STARTED_UNVERIFIED` 处理，不能把“分配到 Luna”与“turn 有效身份已验证”混为一谈。

## MCP broker 注册

在 `$CODEX_HOME/config.toml` 添加：

```toml
[mcp_servers.sol_luna_broker]
command = "<trusted-pwsh-path>"
args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "<CODEX_HOME>\\skills\\sol-reliable-control\\scripts\\sol-luna-broker.ps1"]
enabled = true

[mcp_servers.sol_luna_broker.env]
SOL_LUNA_ALLOWED_ROOTS = "<approved-phase-worktree>"
SOL_LUNA_RUNTIME_PATH = "<trusted-codex-executable>"
SOL_LUNA_RUNTIME_SHA256 = "<64-hex-approved-sha256>"
```

保存前将尖括号占位符替换为本机实际路径；broker 不再内置任何默认文件系统根目录。
运行时路径和 SHA-256 必须成对固定，不能让 broker 自动选择“最新”可执行文件。
app-server 只使用它公开的 `--strict-config`；CLI 专用的 ignore-config/rules
参数不会误传给 app-server，模型、sandbox、approval 和 no-fallback 约束由
`thread/start` 的宿主字段核验。
重启 Codex 后，先调用 `sol_luna_exec` 并保持 `handshake_only=true`；只有收到结构化结果后，Sol 才能决定是否继续。broker 会对 MCP 输出中的用户目录、主机名和凭据形态值做脱敏。完整注册和证据规则见 [references/registration.md](references/registration.md)。

对于可能超过调用方 MCP deadline 的实现任务，握手通过后将实现包提交为
`execution_mode="async"`；提交会立即返回 `HOST_JOB_RECEIPT` 和 `job_id`，后台继续运行 fresh Luna/max。
随后使用 `sol_luna_poll(task_id, job_id, wait_seconds)` 轮询。只有轮询结果中的嵌套
worker payload 才是最终结果；其中的 `HOST_LAUNCH_RECORD`、`HOST_VERIFIED` 或
`BLOCKED` 仍按原身份门禁处理。不要把一次 `tools/call` 超时当作 worker 失败，也不要重复提交相同 packet。

公开发布前仍需由仓库所有者选择并加入 `LICENSE`；本项目不会根据参考项目
自动推断许可证，也不会把未选择许可证的仓库标成可复用发行版。
