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
- `USER_VISIBLE_TASK`: An explicit Desktop app task lane based on the host's
  `codex_app__create_thread` surface. It is permitted only when the user has
  explicitly authorized a user-owned task in the current plan; it is never an
  automatic fallback and never a way to register Luna.

Normal execution has only the `luna-max` and `sol-xhigh` lanes. Do not select a lane by name, price, or prestige; use task fit and acceptance evidence.

For every normal `LUNA_MAX` dispatch, use this Native-first dispatch ladder:

1. Use a current-thread native subagent surface whose declared schema, exact
   Luna/max pair, fresh-context semantics, and host evidence satisfy the plan.
   `multi_agent_v1__spawn_agent` is canonical; a future equivalent qualifies
   only when the host declares it native and its contract can be verified.
2. Use the `HOST_MANAGED` `sol_luna_broker` MCP only when no qualifying native
   surface is visible, the visible native schema/model does not match, or native
   preflight cannot obtain the required host evidence.
3. If neither route passes its own preflight, preserve `LUNA_MAX` and return
   `BLOCKED` under the existing fail-closed rules. Do not switch models.

The explicit Desktop task lane is outside this normal ladder. Select it only
when the plan sets `Surface: USER_VISIBLE_TASK`,
`Dispatch priority: EXPLICIT_USER_VISIBLE_TASK`, `User-owned task: ALLOWED`,
and records the user's approval. This opt-in route is useful when the local MCP
broker would invoke a Windows sandbox that the user has forbidden Sol to repair;
it does not grant Sol permission to create a visible task by itself.

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
- `BLOCKED` is terminal for the current implementation dispatch; do not retry an identical packet.

`BLOCKED` does not end host recovery. When a preflight or execution probe
fails, return a concrete recovery action and ask the caller to perform the
required host operation. Resume only after an external state change and a new
task-bound probe; never loop on an unchanged failure.

## Bounded recovery loop

Use this recovery order for a Luna task that has not reached `HOST_VERIFIED`:

1. Run a native, handshake-only probe on the current thread.
2. If native preflight is unavailable or lacks host evidence, run the MCP
   broker handshake as priority 2 and record the native failure reason.
3. If either route reports `WINDOWS_SANDBOX_ACL_FAILED`,
   `PROCESS_CREATION_DENIED`, or a model/role registration mismatch, return
   `HOST_REMEDIATION_REQUIRED` with an exact permission/host-registration
   request. Ask the user or host owner to approve the smallest official
   remediation; do not issue broad ACL/full-control commands from the skill.
4. After the approved host change, refresh/rebind the worker registry and run
   a new minimal read-only PowerShell probe. Only a successful probe permits a
   fresh identity handshake and then the implementation packet.

Each recovery step must have a new task id, an external state-change record,
and a bounded stop condition. The caller-facing packet must include the
failure code, requested host action, approval status, probe command class, and
next action. If the probe still fails, preserve `LUNA_MAX` and report
`BLOCKED`/`HOST_REMEDIATION_REQUIRED`; do not substitute a model or resubmit
the implementation packet.

## Controller workflow

1. State the goal, observable `done_when`, exclusions, dependencies, risk, task scope, owner, route, identity gate, and verification.
2. Send the compact plan packet from [references/protocol.md](references/protocol.md).
3. Require `LUNA_MAX` host enablement preflight; use [references/enablement.md](references/enablement.md) and the step-by-step [registration guide](references/registration.md) when the host does not advertise the required pair or when recovery needs a host permission request.
4. Start a fresh execution context when the host supports it; exclude controller history unless a deliberate continuation is required.
5. Require the handshake packet before allowing implementation. A transport response alone is not permission to execute.
6. Receive only the structured result, verification output, and evidence/artifact paths. Do not import the worker's full reasoning.
7. Review the result against `done_when`, scope, contradictions, regressions, and evidence freshness.
8. Allow at most one focused correction with the original scope and owner. Re-review the corrected result.
9. Return `PASS`, `FIX`, `BLOCKED`, or `HOST_REMEDIATION_REQUIRED`; Sol alone decides the overall result and the next recovery action.

## Handshake gates

Keep these facts separate:

- `transport_verified`: the dispatch mechanism delivered a response.
- `host_dispatch_verified`: the host accepted the requested lane/model and returned a task-bound receipt.
- `identity_verified`: the host observed the requested lane/model/effort and matched the dispatch request.
- `scope_verified`: the worker accepted the exact task boundary.
- `self_report_consistent`: the worker's self-reported identity happens to match host facts; this is advisory.
- `evidence_verified`: the result is bound to the final candidate and its verification.

For low-risk work, a valid host receipt may satisfy `HOST_DISPATCH` even when runtime identity is unavailable; record `HOST_DISPATCHED_UNATTESTED`. High-risk work requires `HOST_VERIFIED`. An explicit host mismatch or missing receipt is `BLOCKED`. A worker's self-report alone never proves identity and never creates a routing gate.

An app-server `thread/start` launch record is stronger host evidence, but it is
not automatically effective identity. Accept it only when the same fresh
ephemeral launch records the exact requested model/effort and the subsequent
turn has no `model/rerouted` event or conflicting effective identity.

## Native worker launch

Start every normal `LUNA_MAX` dispatch at priority 1 of the Native-first
dispatch ladder: a current-thread native generic worker surface and a fresh
context. Run the capability preflight in
[references/runtime-adapters.md](references/runtime-adapters.md) before dispatch:

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
adapters with separate evidence rules. `USER_VISIBLE_TASK` is a fourth,
explicitly user-owned adapter with its own receipt and host-observation rules;
it is not interchangeable with a native worker or the MCP broker.

The canonical native v1 contract is `multi_agent_v1__spawn_agent`. A future
native surface may take priority 1 only when it is visible in the current
thread, explicitly declared as native, schema-compatible with the normalized
request, and able to return the required host evidence. The older
`collaboration.spawn_agent` schema cannot impersonate the canonical v1 surface,
borrow its model matrix, or reuse its receipts. It is independently eligible
only if its own declared schema, Luna/max support, and evidence contract pass
preflight.

Capability discovery is bound to the current controller thread and host. Before
returning `HOST_ENABLEMENT_REQUIRED`, enumerate all callable worker surfaces in
that same thread. Prefer `multi_agent_v1__spawn_agent` when it is exposed; its
native Luna call uses `fork_context=false`, `model="gpt-5.6-luna"`, and
`reasoning_effort="max"`. `collaboration.spawn_agent` is a separate generic
schema and may expose only Sol/Terra even when the other surface exposes Luna.
An absent surface on one thread is `THREAD_SURFACE_NOT_VISIBLE`, not proof that
Luna is globally unavailable. Do not copy a model list, agent id, or receipt
from another thread.

`LUNA_MAX` capability is mandatory. If neither priority route can return an
`AVAILABLE` preflight, stop at the handshake gate and return
`HOST_ENABLEMENT_REQUIRED`;
do not treat generic `BLOCKED` as a completed deployment, and do not substitute
another model. The skill and `config.toml` can state this requirement but cannot
register a model in the host-owned `collaboration.spawn_agent` surface; see
[references/enablement.md](references/enablement.md) for the configuration boundary.

When a caller is blocked before dispatch, follow
[references/registration.md](references/registration.md): identify the exact
surface, submit the host registration or remediation packet, obtain the
required user/host approval, refresh the capability snapshot, then retry
preflight only with new evidence. A safe low-risk probe may prove that a
surface can start Luna, but an `agent_id` and worker self-report alone do not
satisfy `HOST_VERIFIED` for high-risk work.

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
task-bound evidence. A user-owned Desktop task is a separate explicit adapter;
it may be selected only when the plan and user approval allow it. It must never
be created merely to obtain a model or to bypass a `No user-owned task` gate.

### Explicit Desktop Luna task lane

Some clients expose Luna/max through a visible Codex task rather than a native
worker tool. Follow [references/desktop-task-lane.md](references/desktop-task-lane.md)
for the exact `codex_app__list_projects`, `codex_app__create_thread`,
`codex_app__wait_threads`, `codex_app__read_thread`, and
`codex_app__send_message_to_thread` sequence. The route uses the host's
`model="gpt-5.6-luna"` and `thinking="max"` fields, requires a fresh task, and
keeps controller history out of the initial prompt.

This route does not call the local Sol broker, `setupStart`, PowerShell, or ACL
APIs. It is therefore the safe alternative when the user forbids external
permission changes. It still runs under whatever execution policy the Desktop
host reports: a `PROCESS_CREATION_DENIED` result is an execution block, not a
reason to request broad ACL changes. The app task's `threadId`/`hostId` is a
transport receipt only until the host reports effective Luna/max; UI selection
and worker self-report remain advisory.

### MCP Luna broker

At priority 2, use the installed `sol_luna_broker` MCP server as the explicit
`HOST_MANAGED` transport adapter only when the native surface is not visible in
the current Desktop thread, its schema/model cannot express the requested
Luna/max contract, or native preflight cannot obtain the required host evidence.
This changes the transport surface, not the requested model. It is not a silent
model fallback. MCP is not a native subagent, and MCP evidence must never be
labeled native. The broker must:

- launch a fresh ephemeral app-server thread with `gpt-5.6-luna` and `max`;
- capture the task-bound `thread/start` model/effort record and reject any
  `model/rerouted` event;
- validate the task id, workdir, sandbox, prompt size, and allowed roots before
  starting the process;
- require `handshake_only=true` with `read-only` sandbox before implementation;
- return a task-bound `HOST_LAUNCH_RECORD`, runtime version/hash,
  fresh/history facts, and the worker result; and
- label model self-report as advisory. The app-server launch record can satisfy
  `identity=VERIFIED` only when it matches and no host reroute is observed.
  Overall `HOST_VERIFIED` additionally requires `execution_status=COMPLETED`.

Keep broker identity and execution facts independent. In particular,
`WINDOWS_SANDBOX_ACL_FAILED` and `PROCESS_CREATION_DENIED` are execution
blockers classified as `runtime` or `permission`; they do not erase an already
verified host identity. They do keep the overall result below `HOST_VERIFIED`,
and high-risk work remains `BLOCKED`. Do not respond by silently changing the
model or relaxing the sandbox or permissions.

For implementation packets that may exceed the MCP caller deadline, the broker
supports an explicit asynchronous `HOST_JOB_RECEIPT` plus `sol_luna_poll`.
Submit only after the synchronous identity handshake passes; poll the same
task-bound job until its nested worker payload is `COMPLETED` or `FAILED`. A
caller timeout or `PENDING` result is not permission to resubmit the packet and
is not evidence that the worker failed.

Broker output is sanitized before it crosses the MCP boundary: user-home
paths, host names, and credential-shaped values are redacted. This is an
output privacy guard, not a substitute for the explicit allowed-root,
handshake, or identity gates.

`SOL_LUNA_TRANSPORT=cli` is retained for legacy diagnostics. It launches the
isolated CLI process and returns `BROKER_RUN_RECEIPT`, but remains
`STARTED_UNVERIFIED` because it has no host identity telemetry.

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

Use the broker only after recording the native candidate and one of the three
priority-2 trigger conditions above. Keep the high-risk identity gate closed
until the host supplies independent identity evidence; a worker self-report
never creates `HOST_VERIFIED`. If broker preflight also fails, return
`HOST_REMEDIATION_REQUIRED` with the exact next host action; the implementation
remains `BLOCKED` without changing the model. The broker implementation and
contract test live under
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
