# sol-reliable-control

用于 Codex 的可靠多代理编排 skill：由一个清晰的 Sol 主控负责计划、路由和最终审核，把实现工作放进隔离执行上下文，并用紧凑证据包节约上下文 token。

## 功能说明

- 主控与执行 lane 分离：执行 lane 不能接管 Sol，也不能批准整体任务。
- 正常执行路由只有两条：
  - `luna-max`：默认处理边界清晰、可独立验证，以及范围较窄的困难任务；请求 `gpt-5.6-luna / max`。
  - `sol-high`：处理跨域规划、深度推理、仲裁或最终审核类困难任务；请求 `xhigh` reasoning。
- `sol-high` 的 `xhigh` 不可用时不静默降级，按 runtime/model-identity 失败处理。
- 握手失败保持 `BLOCKED`，不会静默切换到其他 lane，也不会让主控直接接管实现。
- Fallback 是独立分支：失败后可以使用任意安全兼容 lane，或返回 `BLOCKED`；它不改变正常路由规则。
- 写任务默认使用 `worktree-flow`：独立 branch/worktree、阶段 commit、主控 diff 审查和可保留的失败现场。
- 只传结构化结果、验证结果和 artifact 路径，不导入 worker 全量推理，避免污染主控上下文。
- 不包含 Faster/speed-control 门禁；速度状态不能成为额外路由或阻塞条件。

## 包内容

- `SKILL.md`：always-on 主控规则和最小工作流。
- `references/protocol.md`：计划、握手、结果包和状态机协议。
- `agents/openai.yaml`：Codex skill 列表的界面元数据。

## 安装

将仓库目录复制到 `$CODEX_HOME/skills/sol-reliable-control`，或使用 Codex 的 skill 安装器从本仓库安装。

该仓库只发布 skill 本身；运行时仍由宿主提供 native generic worker、模型身份和 dispatch receipt。
