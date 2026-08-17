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
- 恢复顺序固定为：native 握手 →（用户明确允许时）Desktop task 握手 → 用户/宿主批准最小注册或角色修复 → 刷新/重绑；新握手成功前不重试实现包。
- `LUNA_MAX` 正常调度采用“原生优先、Desktop task 次选”（native-first -> Desktop-task）：第一优先使用当前线程可见且契约匹配的 `multi_agent_v1__spawn_agent`，或未来等价、由宿主声明且可验证的 native surface。
- native 失败后，只有在计划允许 user-owned task 且用户明确批准时，才使用第二优先 Desktop task；Desktop 未获批准或握手失败后保持原模型并返回 `BLOCKED`，不启动隐藏 transport。
- `USER_VISIBLE_TASK` 参考 `sol-advisor` 的做法，但它不是启用 Luna 的手段；它仍需独立的 host-observed identity evidence。
- 该桌面任务路线不调用 `setupStart`、不执行 PowerShell、不修改任何 ACL；若宿主仍报告 `PROCESS_CREATION_DENIED` 或 sandbox 权限错误，只记录执行阻塞并停止，不申请扩大权限。
- `collaboration.spawn_agent` 是独立的旧/兼容 schema，不能冒充 canonical `multi_agent_v1__spawn_agent`、混用字段、借用其 capability/receipt，或把自身的 Sol/Terra 枚举当成全局能力结论。
- capability snapshot 绑定当前 host 与 controller thread；兄弟线程能看到 Luna 而当前线程看不到时，记录 `THREAD_SURFACE_NOT_VISIBLE`，先评估第二优先 Desktop task；两者都不可用时才要求 surface migration/rebind 或 fresh controller thread。
- `FALLBACK` 是显式恢复分支：允许任意安全兼容 lane，但必须标记 `UNVERIFIED`，且只用于低风险、窄范围、可独立验证的任务。
- 只传结构化 packet、验证摘要和 evidence 路径，不导入 worker 全量推理，避免污染主控上下文。
- 不包含仓库操作、部署流程、项目记忆或其他 skill 的生命周期；本包可单独安装，不要求额外 skill 才能理解自身协议。

## 包内容

- `SKILL.md`：主控角色、路由、状态机、握手和审核规则。
- `references/protocol.md`：计划、握手、结果和 fallback packet schema。
- `references/runtime-adapters.md`：Native generic、custom role 和 Desktop task 运行面及 capability preflight / receipt / identity 证据契约。
- `references/enablement.md`：LUNA_MAX 必须由宿主启用的请求、响应、验收门禁，以及 `config.toml` 与 host surface 的边界。
- `references/registration.md`：调用者被卡在 Luna/max 前置检查时的注册、刷新、精确调用和恢复步骤。
- `references/registration.md` 同时区分 native worker、CLI custom-role 和显式 user-visible app task；后者不是 native sub-agent，也不能绕过 `No user-owned task` 约束。
- `references/desktop-task-lane.md`：显式 Desktop Luna task 的调用字段、fresh/history、receipt/identity 门禁与 ACL 禁止边界。
- `tests/protocol-contract.ps1`：不依赖宿主的协议契约回归检查。
- `tests/privacy-contract.ps1`：源码路径、凭据形态和公开证据脱敏契约检查。
- `README.en.md`：English installation, routing, verification, and reference guide。
- `references/sources.md`：完整参考项目、官方资料、关键原则、利弊/陷阱/解决方案及 GitHub 发布门禁清单。
- `agents/openai.yaml`：Codex skill 列表的界面元数据。

## 参考项目与官方文档

完整清单（包括两个参考项目的具体编排文件、官方 App Server/Subagents、
Luna 模型资料、Windows sandbox 说明、上游 setup 源码和运行问题证据）见
[references/sources.md](references/sources.md)。本项目只借鉴公开设计，不运行时依赖
这些项目，也不复制凭据、用户数据或工作树。
公开参考项目包括 [sol-advisor](https://github.com/DannyMac180/sol-advisor) 和
[codex-sol-control](https://github.com/yehyakin/codex-sol-control)。

## 主要事项与关键要点

1. 路由顺序固定为 Native →（明确批准时）Desktop task；未批准时不创建 user-owned task。
2. `LUNA_MAX` 始终绑定 `gpt-5.6-luna / max`，`SOL_XHIGH` 绑定 `gpt-5.6-sol / xhigh`，不静默换模型。
3. `TRANSPORT_VERIFIED`、`HOST_LAUNCH_RECORDED`、`HOST_VERIFIED` 分层；`HOST_MODEL_UNOBSERVABLE` 不等于 `HOST_MODEL_MISMATCH`。
4. Desktop GUI 默认不能证明 `HOST_VERIFIED`；用户明确批准 `OPERATOR_ATTESTED` 后，可记录 `OPERATOR_UI_ATTESTED`，并保留 `Identity: ATTESTED` 与残余风险。
5. Desktop task 必须选择正确项目/工作树；projectless 只用于握手，local 目录必须显式授权。
6. Windows sandbox ACL/进程创建失败是宿主执行故障；Sol 不调用 `setupStart`、`icacls`、`Set-Acl` 或扩大权限。
7. Desktop/宿主超时或权限故障必须绑定原 task 证据，不重复提交实现包；身份与执行失败分离记录。
8. 发布 GitHub 前必须检查未跟踪文件、秘密、机器路径、旧 worktree、原始日志和许可证归属，并运行协议与隐私契约测试。

## 安装

将仓库目录复制到 `$CODEX_HOME/skills/sol-reliable-control`，或使用 Codex skill 安装器从本仓库安装。

运行时仍由宿主提供 native worker dispatch、模型身份和 `HOST_RECEIPT`；默认按 Native → Desktop task 选择 Luna/max 路线。UI 选择器和 worker 自报不能替代宿主启动记录。

## 宿主配置与调用

Luna/max 的模型目录和宿主 worker 注册属于 Codex 宿主配置，不由本 skill
伪造或替代。当前线程必须先显示可调用的 native worker surface，并在新任务
握手中返回 task-bound receipt、fresh/history 事实和有效模型/effort；否则在
获得用户批准后使用 Desktop task，仍无法满足门禁时保持 `BLOCKED`。

不要在 `$CODEX_HOME/config.toml` 注册已删除的本地 transport。任何角色注册、
model catalog 或 host registry 修改都必须由宿主提供官方入口，并在重载后
重新枚举当前线程的 surface；本地配置文件本身不是身份证据。

公开发布前仍需由仓库所有者选择并加入 `LICENSE`；本项目不会根据参考项目
自动推断许可证，也不会把未选择许可证的仓库标成可复用发行版。
