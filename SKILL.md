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
- An explicit dispatch rejection or failed handshake blocks execution; an
  accepted native dispatch may proceed under the `HOST_ACCEPTED` policy while
  the controller still waits for the worker result and performs final review.

This skill is self-contained for Sol routing and review. Unrelated environment management is outside its scope and is not required for its decisions.

The complete external-reference, trade-off, failure-mode, mitigation, and
public-release catalog is [references/sources.md](references/sources.md). Use it
when changing a route, reviewing host behavior, or preparing a GitHub release.

Use it for work large enough to justify delegation. Keep a small, clear, single-step request Direct.

## Route selection

Choose the cheapest route that satisfies the task:

- `Direct`: The request is small enough to complete without a worker.
- `Sol-only`: Sol plans, inspects, or reviews without dispatching an executor.
- `Sol -> luna-max`: Default for clear, bounded, independently verifiable work and difficult work whose scope remains narrow. Request `gpt-5.6-luna / max`.
- `Sol -> sol-xhigh`: Difficult work requiring deeper reasoning, cross-cutting planning, arbitration, or final review. Request `gpt-5.6-sol / xhigh`.
- `luna-max -> sol-xhigh`: Escalate only when task fit or acceptance requires stronger Sol reasoning. A lane failure alone is not a reason to escalate.
- `LUNA_MAX` capability is mandatory for a conforming Sol deployment. The host
  must accept `gpt-5.6-luna / max` on the selected dispatch surface; effective
  model telemetry is optional under the default native `HOST_ACCEPTED` policy.
  An explicit rejection remains a host enablement blocker.
- Escalation gate: if the same issue has been rejected more than twice under `luna-max`, or unclear business semantics repeatedly cause regressions, stop retrying `luna-max` and submit the issue to `sol-xhigh` with the failure evidence.
- `Fallback`: Use only when the requested lane cannot run and the plan explicitly permits a safe compatibility lane. The compatibility lane may be any available lane, must be labeled unverified, and may not silently replace normal routing.
- `USER_VISIBLE_TASK`: An explicit Desktop app task lane based on the host's
  `codex_app__create_thread` surface. It is permitted only when the user has
  explicitly authorized a user-owned task in the current plan; it is never an
  automatic fallback and never a way to register Luna.

Normal execution has only the `luna-max` and `sol-xhigh` lanes. Do not select a lane by name, price, or prestige; use task fit and acceptance evidence.

For every normal `LUNA_MAX` dispatch, use this Native-first -> Desktop
dispatch ladder:

1. Use a current-thread native subagent surface whose declared schema, exact
   Luna/max pair, fresh-context semantics, and selected acceptance gate satisfy
   the plan. Native `HOST_ACCEPTED` treats a successful exact spawn as the
   selected executor even when effective model telemetry is unavailable.
   `multi_agent_v1__spawn_agent` is canonical; a future equivalent qualifies
   only when the host declares it native and its contract can be verified.
2. If native preflight fails, consider the explicit Desktop task adapter only
   when the plan sets `Surface: USER_VISIBLE_TASK`, `User-owned task: ALLOWED`,
   and records the user's approval. If authorization is `UNSPECIFIED`, ask for
   confirmation; if it is `DENIED`, skip Desktop. Never create a user-owned
   task implicitly.
3. If Desktop is not eligible or its handshake fails, preserve `LUNA_MAX` and
   return `BLOCKED` under the existing fail-closed rules. Do not switch models.

The Desktop task is now the conditional priority-2 route. Its exact fields are
defined in [references/desktop-task-lane.md](references/desktop-task-lane.md);
the route remains user-visible and never grants Sol permission to create a task
without explicit approval.
`EXPLICIT_USER_VISIBLE_TASK` remains an operator-selected override for a task
that intentionally bypasses the normal ladder; it still requires the same
user-owned-task approval and identity gates.

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

Use this recovery order for a Luna task that has not reached `HOST_ACCEPTED` or
the optional strict `HOST_VERIFIED` gate:

1. Run a native, handshake-only probe on the current thread.
2. If native preflight is unavailable or lacks host evidence, evaluate the
   Desktop task handshake only after explicit user-owned-task approval; record
   the authorization state and do not create a task implicitly. Desktop remains
   subject to its own receipt/attestation rules.
3. If Desktop is unavailable, not authorized, or fails, return
   `HOST_REMEDIATION_REQUIRED` with an exact host-registration request. Ask the
   user or host owner to approve the smallest official registry/role change;
   do not issue broad ACL/full-control commands from the skill.
4. After the approved host change, refresh/rebind the worker registry and run
   a new minimal read-only probe. Only a successful probe permits a fresh
   identity handshake and then the implementation packet.

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
5. Require the handshake packet before allowing implementation. An exact native
   spawn accepted without an explicit rejection may authorize execution under
   `HOST_ACCEPTED`; the worker result and Sol review remain mandatory.
6. Receive only the structured result, verification output, and evidence/artifact paths. Do not import the worker's full reasoning.
7. Review the result against `done_when`, scope, contradictions, regressions, and evidence freshness.
8. Allow at most one focused correction with the original scope and owner. Re-review the corrected result.
9. Return `PASS`, `FIX`, `BLOCKED`, or `HOST_REMEDIATION_REQUIRED`; Sol alone decides the overall result and the next recovery action.

## Handshake gates

Keep these facts separate:

- `transport_verified`: the dispatch mechanism delivered a response.
- `host_dispatch_verified`: the host accepted the requested lane/model and returned a task-bound receipt.
- `host_acceptance_verified`: the selected native surface accepted the exact
  requested model/effort and returned a task-bound handle or receipt, with fresh
  context, history exclusion, scope acceptance, and no explicit rejection or
  reroute.
- `identity_verified`: the host observed the requested lane/model/effort and matched the dispatch request.
- `scope_verified`: the worker accepted the exact task boundary.
- `self_report_consistent`: the worker's self-reported identity happens to match host facts; this is advisory.
- `evidence_verified`: the result is bound to the final candidate and its verification.

For the normal native route, `HOST_ACCEPTED` is the default gate. It is satisfied
when the exact `gpt-5.6-luna / max` request is accepted by the selected spawn
surface, a task-bound `AGENT_HANDLE` or `HOST_RECEIPT` is returned, fresh context
and history exclusion are confirmed, scope is accepted, and no explicit
rejection, mismatch, or reroute is reported. Record `Identity: ASSUMED` and
`Identity proof kind: HOST_REQUEST_ACCEPTED`; missing effective model/effort
telemetry is recorded as `HOST_MODEL_UNOBSERVABLE`, but it is not a blocker for
this native gate. The worker result, verification, and Sol review remain
mandatory.

`HOST_VERIFIED` remains an optional strict gate for callers that require
host-observed effective identity. A Desktop task with no effective model
telemetry is `HOST_MODEL_UNOBSERVABLE`, not `HOST_MODEL_MISMATCH`. If the user
explicitly approves an `OPERATOR_ATTESTED` Desktop gate, the operator may
confirm the live GUI for the exact task/thread shows `gpt-5.6-luna / max`;
record `OPERATOR_UI_ATTESTED`, `Identity: ATTESTED`, and the attestation
evidence. This never becomes `HOST_LAUNCH_RECORDED` or `HOST_VERIFIED`.
An explicit host rejection, mismatch, reroute, missing task handle/receipt, or
scope failure is always `BLOCKED`. A worker's self-report alone never proves
effective identity and never creates a routing gate.

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
agent type. `NATIVE_GENERIC` and `CUSTOM_ROLE` are native adapters with
separate evidence rules. `USER_VISIBLE_TASK` is an explicitly user-owned
adapter with its own receipt and host-observation rules; it is not
interchangeable with a native worker.

The canonical native v1 contract is `multi_agent_v1__spawn_agent`. A future
native surface may take priority 1 only when it is visible in the current
thread, explicitly declared as native, schema-compatible with the normalized
request, and able to return a task-bound handle/receipt plus fresh/history/scope
facts. The older
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

`LUNA_MAX` capability is mandatory. Under the default native policy, an exact
spawn acceptance with a task-bound handle/receipt is an `AVAILABLE` preflight
even when effective model telemetry is unavailable. If the host rejects the
exact pair, returns no task handle/receipt, or reports a mismatch/reroute, stop
at the handshake gate and return `HOST_ENABLEMENT_REQUIRED`; do not substitute
another model. The skill and `config.toml` can state this requirement but cannot
register a model in the host-owned `collaboration.spawn_agent` surface; see
[references/enablement.md](references/enablement.md) for the configuration boundary.

When a caller is blocked before dispatch, follow
[references/registration.md](references/registration.md): identify the exact
surface, submit the host registration or remediation packet, obtain the
required user/host approval, refresh the capability snapshot, then retry
preflight only with new evidence. A safe probe that receives an accepted exact
spawn and a task-bound handle may authorize a bounded native task under
`HOST_ACCEPTED`; it does not upgrade the same evidence to strict
`HOST_VERIFIED`.

For `NATIVE_GENERIC`, `fork_context: false` means fresh context and excluded
controller history in the current generic spawn schema. A returned `agent_id`
is an `AGENT_HANDLE`; when it binds the accepted task it is sufficient for the
default `HOST_ACCEPTED` gate, but it is not effective-identity proof.
`HOST_VERIFIED` still requires host-observed model/effort evidence; a worker
self-report is advisory.

The canonical native probe is an identity-only message sent through the
currently visible `multi_agent_v1__spawn_agent` surface. If that tool is not
visible, inspect the exact schema of `collaboration.spawn_agent` before deciding
that registration is missing. A successful probe proves that the selected
surface can start a Luna worker and, when the exact request is accepted, is
enough to authorize a bounded native task under `HOST_ACCEPTED`; it does not by
itself upgrade `AGENT_HANDLE` and self-report evidence to `HOST_VERIFIED`.

For `CUSTOM_ROLE`, the host must accept the registered role and return a
task-bound handle/receipt plus fresh/history/scope facts (`agent_type`, fresh
fork, model, effort, and receipt). This qualifies for `HOST_ACCEPTED`; a
strict `HOST_VERIFIED` plan still requires the authoritative role launch
record. A TOML/config file alone is not proof. A user-owned Desktop task is a separate explicit adapter;
it may be selected only when the plan and user approval allow it. It must never
be created merely to obtain a model or to bypass a `No user-owned task` gate.

### Explicit Desktop Luna task lane

Some clients expose Luna/max through a visible Codex task rather than a native
worker tool. Follow [references/desktop-task-lane.md](references/desktop-task-lane.md)
for the exact `codex_app__list_projects`, `codex_app__create_thread`,
`codex_app__wait_threads`, `codex_app__read_thread`, and
`codex_app__send_message_to_thread` sequence. The route uses the host's
`model="gpt-5.6-luna"` and `thinking="max"` fields, requires a fresh task, and
keeps controller history out of the initial prompt. This is priority 2: use it
after native preflight fails and only when the plan records
`User-owned task: ALLOWED` plus `User approval: GRANTED`. `UNSPECIFIED` requires
confirmation; it is not an implicit denial. If the gate is not granted, return
`BLOCKED` with the required host-registration action; do not create a task.

This route does not call `setupStart`, PowerShell, or ACL APIs. It is therefore
the safe alternative when the user forbids external
permission changes. It still runs under whatever execution policy the Desktop
host reports: a `PROCESS_CREATION_DENIED` result is an execution block, not a
reason to request broad ACL changes. The app task's `threadId`/`hostId` is a
transport receipt only until the host reports effective Luna/max. If telemetry
is absent, classify `HOST_MODEL_UNOBSERVABLE`; do not call it a mismatch. Only
an explicit `OPERATOR_ATTESTED` plan may use the user's live GUI confirmation as
`OPERATOR_UI_ATTESTED`, and that evidence remains separate from host identity.

### After native and Desktop preflight

If the native surface is unavailable and the explicitly approved Desktop task
cannot pass its own transport, freshness, scope, and identity gates, preserve
`LUNA_MAX` and return `HOST_REMEDIATION_REQUIRED` or `BLOCKED` with a concrete
host-registration request. Do not create an unapproved user-owned task, invoke
an alternate local transport, change the model, or widen permissions. Resume
only after the host registry changes and a new task-bound handshake succeeds.

The `SOL_XHIGH` lane must request `gpt-5.6-sol / xhigh`; if the host cannot
honor it, classify the failure as `runtime` or `model_identity` and do not
silently downgrade. If `LUNA_MAX` is unavailable, select `SOL_XHIGH` only when
the task-fit or repeated-failure escalation gate independently calls for it;
otherwise preserve the plan and return `BLOCKED`. Do not retry an unavailable
packet identically.

When the plan marks Luna enablement `REQUIRED`, the fallback field remains
`BLOCKED` until the host accepts the exact Luna/max request. An accepted native
dispatch satisfies the default enablement gate; strict host telemetry is an
optional stronger requirement, not a reason to block an otherwise accepted
native task. Host enablement is a prerequisite, not a compatibility fallback.

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
- The host dispatch satisfies the declared identity gate (`HOST_ACCEPTED` by
  default for native, or the explicitly selected stricter gate).
- Required checks ran against the final result, not an earlier attempt.
- Evidence explains failures and business impact, not only exit codes.
- No worker has approved the overall task.

If a same-scope correction is credible, return `FIX` once. Otherwise return `BLOCKED` with the concrete failure class and next safe action.

## Result discipline

Use the exact result packet in [references/protocol.md](references/protocol.md). Keep the final response compact: outcome, route, evidence, verification, blocker, and residual risk. Under `HOST_ACCEPTED`, claim that the requested native model/effort was accepted by the host and label effective telemetry as `ASSUMED`/`HOST_MODEL_UNOBSERVABLE`; do not claim host-observed effective identity. Label worker claims as self-report.
