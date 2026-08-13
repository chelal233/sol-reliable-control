# sol-reliable-control

An installable Codex Sol controller skill for lane routing, worker handshakes,
identity gates, compact evidence collection, and final review.

Language: [简体中文](README.md) · [English](README.en.md)

## Normal lanes

- `LUNA_MAX`: bounded, independently verifiable work; requests
  `gpt-5.6-luna / max`.
- `SOL_XHIGH`: cross-cutting planning, arbitration, or final review; requests
  `gpt-5.6-sol / xhigh`.

`BLOCKED` terminates the current implementation dispatch, not the recovery
workflow. When a safe host repair remains possible, return
`HOST_REMEDIATION_REQUIRED` with the exact permission request, external-change
evidence, minimal read-only probe, and next action. Do not leave the caller
with only “blocked” or loop on an unchanged packet.

The recovery order is fixed: native handshake -> (if explicitly authorized)
Desktop task handshake -> MCP handshake -> explicit user or host-owner approval
for the smallest registry/sandbox/token repair -> refresh/rebind. A repair still
requires a new task's minimal PowerShell read-only probe. Do not retry the
implementation packet until the selected probe succeeds.

`LUNA_MAX` uses **Native-first -> Desktop-task -> MCP** routing. Priority 1 is a native
subagent surface that is visible to the current thread and matches the worker
contract. The canonical surface is `multi_agent_v1__spawn_agent`; a future equivalent
qualifies only if the host declares and verifies its contract, schema, requested
model, effort, and identity evidence.

After native preflight fails, use the explicit Desktop task as Priority 2 only
when the plan permits a user-owned task and the user has approved it. Otherwise
skip it without creating a task. Use
`mcp__sol_luna_broker__sol_luna_exec` as Priority 3 only when native fails and
the Desktop task is skipped or fails. This MCP route is `HOST_MANAGED`: MCP is not a native subagent. It is not a silent model fallback. If all three routes
fail, retain the requested `gpt-5.6-luna / max` and return `BLOCKED` under the
existing failure rules.
The MCP trigger includes the case where native preflight cannot obtain the required host evidence; record that failure before selecting Priority 3.

The conditional `USER_VISIBLE_TASK` route follows the approach in
`sol-advisor`: use the host-owned `codex_app__create_thread` surface with
`gpt-5.6-luna / max` to create a visible task after native preflight fails. It
is not a native sub-agent or a Luna enablement mechanism. It is attempted only
when the plan permits a user-owned task and the user has explicitly approved it;
otherwise the controller proceeds to MCP Priority 3.

This Desktop task route does not start the local Sol broker, call `setupStart`,
run PowerShell, or change ACLs. If the host still reports
`PROCESS_CREATION_DENIED` or a sandbox permission error, record the execution
blocker and stop; do not broaden permissions.

The managed MCP broker starts a fresh ephemeral app-server thread, captures
the host launch record, and rejects `model/rerouted` events. The legacy CLI
transport is diagnostic only (`SOL_LUNA_TRANSPORT=cli`) and remains
`STARTED_UNVERIFIED`.

## Three-layer verification

1. `TRANSPORT_VERIFIED`: the broker answered and returned a task-bound result.
2. `HOST_LAUNCH_RECORDED`: app-server `thread/start` reported the requested
   model and effort for a fresh task-bound thread.
3. `HOST_VERIFIED`: `identity=VERIFIED` and `execution_status=COMPLETED` are
   both true. A matching launch record with no reroute keeps identity verified
   even when execution is independently blocked.

Worker self-report, UI model pickers, and agent handles are advisory unless the
host contract supplies authoritative evidence.

The MCP payload reports redacted `execution_status`, `execution_blocker_code`,
and `execution_blocker` facts. Windows sandbox ACL failures and denied process
creation are classified as `WINDOWS_SANDBOX_ACL_FAILED` and
`PROCESS_CREATION_DENIED`; neither execution failure changes verified host
identity into an identity failure.

## Installation and MCP registration

Install this directory under `$CODEX_HOME/skills/sol-reliable-control`, then add
the following to `$CODEX_HOME/config.toml`. Replace every angle-bracket
placeholder before saving; no machine-specific paths are stored in this repo.

```toml
[mcp_servers.sol_luna_broker]
command = "pwsh"
args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "<CODEX_HOME>\\skills\\sol-reliable-control\\scripts\\sol-luna-broker.ps1"]
enabled = true

[mcp_servers.sol_luna_broker.env]
SOL_LUNA_ALLOWED_ROOTS = "<approved-worktree-root>;<sol-reliable-control-worktree-root>;<sol-reliable-control-root>"
```

The broker requires explicit allowed roots and has no implicit filesystem
roots. Restart Codex, then call `sol_luna_exec` first with
`handshake_only=true` and `sandbox="read-only"`. MCP output redacts user-home
paths, `DESKTOP-*` host names, and credential-shaped values.

For implementation packets that may exceed the caller's MCP deadline, keep the
identity handshake synchronous, then submit the packet with
`execution_mode="async"`. Submission immediately returns a task-bound
`HOST_JOB_RECEIPT` and `job_id` while a fresh Luna/max worker continues in the
background. Poll with `sol_luna_poll(task_id, job_id, wait_seconds)`. Only the
nested worker payload is the final result; evaluate its `HOST_LAUNCH_RECORD`,
`HOST_VERIFIED`, or `BLOCKED` state using the normal identity gate. A single
`tools/call` timeout is not proof that the worker failed, and the same packet
must not be submitted again.

## Reference projects and official documentation

This project is conceptually informed by these public projects, but does not
depend on them at runtime and does not copy credentials, user data, or old
worktrees:

- [DannyMac180/sol-advisor](https://github.com/DannyMac180/sol-advisor) — Sol advisor orchestration and review ideas.
- [yehyakin/codex-sol-control](https://github.com/yehyakin/codex-sol-control) — early Codex Sol control design reference; this repository reimplements the host adapter for the current Desktop app-server/MCP surface.

Host behavior is governed by the official [MCP](https://learn.chatgpt.com/docs/extend/mcp),
[App Server](https://learn.chatgpt.com/docs/app-server), and
[Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
documentation.

## Verification

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/broker-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/protocol-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/privacy-contract.ps1
```

See [SKILL.md](SKILL.md) and the files under `references/` for the complete
protocol and registration rules, including
[references/desktop-task-lane.md](references/desktop-task-lane.md) for the
explicit Desktop Luna task route. The broker implementation is
[`scripts/sol-luna-broker.ps1`](scripts/sol-luna-broker.ps1); its `sol_luna_exec`
and `sol_luna_poll` tools share task-bound receipts and the same redaction gate.
