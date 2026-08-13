---
name: sol-reliable-control
description: Use when the user explicitly invokes $sol-reliable-control or needs a token-conscious standalone Sol controller for multi-agent routing, worker handshakes, identity gates, compact evidence review, and safe failure handling.
---

# Sol Reliable Control

## Purpose

This skill owns only Sol-specific control decisions:

- Sol is one clean controller and the final reviewer.
- Execution lanes do bounded work; they never become controllers or approve the whole task.
- The controller receives compact packets and evidence paths, not private reasoning or full transcripts.
- A missing or failed handshake blocks execution; the controller does not silently take over implementation.

This skill is self-contained for Sol routing and review. Unrelated environment management is outside its scope and is not required for its decisions.

Use it for work large enough to justify delegation. Keep a small, clear, single-step request Direct.

## Route selection

Choose the cheapest route that satisfies the task:

- `Direct`: The request is small enough to complete without a worker.
- `Sol-only`: Sol plans, inspects, or reviews without dispatching an executor.
- `Sol -> luna-max`: Default for clear, bounded, independently verifiable work and difficult work whose scope remains narrow. Request `gpt-5.6-luna / max`.
- `Sol -> sol-xhigh`: Difficult work requiring deeper reasoning, cross-cutting planning, arbitration, or final review. Request `gpt-5.6-sol / xhigh`.
- `luna-max -> sol-xhigh`: Escalate only when task fit or acceptance requires stronger Sol reasoning. A lane failure alone is not a reason to escalate.
- `LUNA_MAX` capability is mandatory for a conforming Sol deployment. The host must expose `gpt-5.6-luna / max` on a verified dispatch surface; a missing capability is a host enablement blocker, not an acceptable normal state.
- Escalation gate: if the same issue has been rejected more than twice under `luna-max`, or unclear business semantics repeatedly cause regressions, stop retrying `luna-max` and submit the issue to `sol-xhigh` with the failure evidence.
- `Fallback`: Use only when the requested lane cannot run and the plan explicitly permits a safe compatibility lane. The compatibility lane may be any available lane, must be labeled unverified, and may not silently replace normal routing.

Normal execution has only the `luna-max` and `sol-xhigh` lanes. Do not select a lane by name, price, or prestige; use task fit and acceptance evidence.

## Controller state

Use this compact state machine:

```text
PLANNED
  -> HANDSHAKE_PENDING
  -> EXECUTING
  -> RESULT_PENDING
  -> REVIEW_PENDING
  -> ACCEPTED
  -> FIX_PENDING -> EXECUTING
Any state -> BLOCKED
```

- `HANDSHAKE_PENDING` means no implementation has been authorized.
- `EXECUTING` requires host dispatch, transport, scope, and the applicable identity gate.
- `RESULT_PENDING` means the lane has stopped and returned its structured result.
- `REVIEW_PENDING` means Sol is checking acceptance and evidence.
- `BLOCKED` is terminal for the current dispatch; do not retry an identical packet.

## Controller workflow

1. State the goal, observable `done_when`, exclusions, dependencies, risk, task scope, owner, route, identity gate, and verification.
2. Send the compact plan packet from [references/protocol.md](references/protocol.md).
3. Require `LUNA_MAX` host enablement preflight; use [references/enablement.md](references/enablement.md) and the step-by-step [registration guide](references/registration.md) when the host does not advertise the required pair.
4. Start a fresh execution context when the host supports it; exclude controller history unless a deliberate continuation is required.
5. Require the handshake packet before allowing implementation. A transport response alone is not permission to execute.
6. Receive only the structured result, verification output, and evidence/artifact paths. Do not import the worker's full reasoning.
7. Review the result against `done_when`, scope, contradictions, regressions, and evidence freshness.
8. Allow at most one focused correction with the original scope and owner. Re-review the corrected result.
9. Return `PASS`, `FIX`, or `BLOCKED`; Sol alone decides the overall result.

## Handshake gates

Keep these facts separate:

- `transport_verified`: the dispatch mechanism delivered a response.
- `host_dispatch_verified`: the host accepted the requested lane/model and returned a task-bound receipt.
- `identity_verified`: the host observed the requested lane/model/effort and matched the dispatch request.
- `scope_verified`: the worker accepted the exact task boundary.
- `self_report_consistent`: the worker's self-reported identity happens to match host facts; this is advisory.
- `evidence_verified`: the result is bound to the final candidate and its verification.

For low-risk work, a valid host receipt may satisfy `HOST_DISPATCH` even when runtime identity is unavailable; record `HOST_DISPATCHED_UNATTESTED`. High-risk work requires `HOST_VERIFIED`. An explicit host mismatch or missing receipt is `BLOCKED`. A worker's self-report alone never proves identity and never creates a routing gate.

## Native worker launch

Prefer the host's native generic worker surface and a fresh context, but run
the capability preflight in [references/runtime-adapters.md](references/runtime-adapters.md)
before dispatch:

```text
agent role: generic worker
route: LUNA_MAX | SOL_XHIGH
requested model/effort: <from plan packet>
fresh context: true
controller history: excluded
prompt: the compact plan packet plus the result-packet rules
```

`LUNA_MAX` and `SOL_XHIGH` are logical lanes. The surface adapter resolves a
logical route to a host schema; never assume that a lane name is a registered
agent type. `NATIVE_GENERIC`, `CUSTOM_ROLE`, and `HOST_MANAGED` are separate
adapters with separate evidence rules.

Capability discovery is bound to the current controller thread and host. Before
returning `HOST_ENABLEMENT_REQUIRED`, enumerate all callable worker surfaces in
that same thread. Prefer `multi_agent_v1__spawn_agent` when it is exposed; its
native Luna call uses `fork_context=false`, `model="gpt-5.6-luna"`, and
`reasoning_effort="max"`. `collaboration.spawn_agent` is a separate generic
schema and may expose only Sol/Terra even when the other surface exposes Luna.
An absent surface on one thread is `THREAD_SURFACE_NOT_VISIBLE`, not proof that
Luna is globally unavailable. Do not copy a model list, agent id, or receipt
from another thread.

`LUNA_MAX` capability is mandatory. If its preflight returns `UNAVAILABLE` or
`UNKNOWN`, stop at the handshake gate and return `HOST_ENABLEMENT_REQUIRED`;
do not treat generic `BLOCKED` as a completed deployment, and do not substitute
another model. The skill and `config.toml` can state this requirement but cannot
register a model in the host-owned `collaboration.spawn_agent` surface; see
[references/enablement.md](references/enablement.md) for the configuration boundary.

When a caller is blocked before dispatch, follow
[references/registration.md](references/registration.md): identify the exact
surface, submit the host registration packet, refresh the capability snapshot,
then retry preflight only with new evidence. A safe low-risk probe may prove
that a surface can start Luna, but an `agent_id` and worker self-report alone
do not satisfy `HOST_VERIFIED` for high-risk work.

For `NATIVE_GENERIC`, `fork_context: false` means fresh context and excluded
controller history in the current generic spawn schema. A returned `agent_id`
is only an `AGENT_HANDLE` unless the host explicitly labels it a task-bound
receipt. It cannot prove model identity. `HOST_VERIFIED` requires host-observed
model/effort evidence; a worker self-report is advisory.

The canonical native probe is an identity-only message sent through the
currently visible `multi_agent_v1__spawn_agent` surface. If that tool is not
visible, inspect the exact schema of `collaboration.spawn_agent` before deciding
that registration is missing. A successful probe proves that the selected
surface can start a Luna worker; it does not by itself upgrade `AGENT_HANDLE`
and self-report evidence to `HOST_VERIFIED`.

For `CUSTOM_ROLE`, the host must prove the registered role and launch record
(`agent_type`, fresh fork, model, effort, and receipt). A TOML/config file alone
is not proof. `HOST_MANAGED` is valid only when the host returns the same
task-bound evidence. None of these adapters may be replaced by a new
user-owned task to obtain a model.

### MCP Luna broker

When the native worker surface is not injected into the current Desktop thread,
the installed `sol_luna_broker` MCP server is the explicit `HOST_MANAGED`
transport adapter. It is not a silent compatibility fallback and it is not a
native subagent. The broker must:

- launch a fresh ephemeral CLI process with `--ignore-user-config`,
  `--strict-config`, `gpt-5.6-luna`, and `max`;
- validate the task id, workdir, sandbox, prompt size, and allowed roots before
  starting the process;
- require `handshake_only=true` with `read-only` sandbox before implementation;
- return a task-bound `BROKER_RUN_RECEIPT`, runtime version/hash, fresh/history
  facts, and the worker result; and
- label model self-report as advisory. A broker receipt is not a `HOST_RECEIPT`
  and cannot satisfy `HOST_VERIFIED` without host-observed model/effort or an
  authoritative host launch record.

The caller invokes the fixed tool as:

```text
sol_luna_exec({
  task_id: <stable id>,
  workdir: <approved worktree>,
  prompt: <compact Sol packet>,
  sandbox: "read-only" | "workspace-write",
  handshake_only: true | false
})
```

Use the broker as the operational Luna path when the native surface is absent;
keep the high-risk identity gate closed until the host supplies independent
identity evidence. The broker implementation and contract test live under
`scripts/sol-luna-broker.ps1` and `tests/broker-contract.ps1` in the installed
skill.

The `SOL_XHIGH` lane must request `gpt-5.6-sol / xhigh`; if the host cannot
honor it, classify the failure as `runtime` or `model_identity` and do not
silently downgrade. If `LUNA_MAX` is unavailable, select `SOL_XHIGH` only when
the task-fit or repeated-failure escalation gate independently calls for it;
otherwise preserve the plan and return `BLOCKED`. Do not retry an unavailable
packet identically.

When the plan marks Luna enablement `REQUIRED`, the fallback field must remain
`BLOCKED` until the host proves enablement. Host enablement is a prerequisite,
not a compatibility fallback.

## Compatibility fallback

Fallback is explicit, bounded, and separate from normal route selection:

- It may use any available compatibility lane when the plan allows it.
- It is permitted only for low-risk, narrow, independently verifiable work.
- Its identity is `UNVERIFIED`; it cannot perform secrets, destructive changes, security decisions, irreversible data changes, or shared-interface ownership.
- If no task-bound host receipt exists, return `BLOCKED`.
- Never present fallback execution as proof that the requested lane ran.

## Context and token budget

- Keep the plan packet below roughly 800 words and each result packet below roughly 600 words unless evidence requires more.
- Ask workers not to repeat task background already present in the packet.
- Prefer one bounded dispatch over overlapping scouts.
- Keep full logs outside the controller response and return only relevant lines, exit status, and artifact paths.
- Do not relaunch an identical packet without new evidence.

## Review gate

Approve only when:

- The result satisfies `done_when` and stays within the declared scope.
- The host dispatch satisfies the declared identity gate.
- Required checks ran against the final result, not an earlier attempt.
- Evidence explains failures and business impact, not only exit codes.
- No worker has approved the overall task.

If a same-scope correction is credible, return `FIX` once. Otherwise return `BLOCKED` with the concrete failure class and next safe action.

## Result discipline

Use the exact result packet in [references/protocol.md](references/protocol.md). Keep the final response compact: outcome, route, evidence, verification, blocker, and residual risk. Claim a model or lane only from host facts; label worker claims as self-report.
