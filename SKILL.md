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
- If a lower lane (`LUNA_MAX` or `TERRA_XHIGH`) cannot complete its task, or its
  result is not accepted by Sol review, allow a second lower-lane attempt with
  a new task id and focused correction. Only after two lower-lane attempts fail
  or are rejected, assign the work to a fresh `SOL_XHIGH` worker. The replacement
  worker never inherits the lower worker's handle or private reasoning, and Sol
  remains the final approver.

This skill is self-contained for Sol routing and review. Unrelated environment management is outside its scope and is not required for its decisions.

The complete external-reference, trade-off, failure-mode, mitigation, and
public-release catalog is [references/sources.md](references/sources.md). Use it
when changing a route, reviewing host behavior, or preparing a GitHub release.

Use it for work large enough to justify delegation. Keep only trivial
controller-only work Direct; a delegated task with a clear, bounded goal still
uses `LUNA_MAX`.

## Route selection

Choose the route by task shape first, then use cost and availability within the
chosen policy:

- `Direct`: A trivial controller-only request that does not justify a worker.
- `Sol-only`: Sol plans, inspects, or reviews without dispatching an executor.
- `Sol -> sol-xhigh`: Difficult, ambiguous, cross-domain, high-risk, or
  reasoning-heavy work. Request `gpt-5.6-sol / xhigh`.
- `Sol -> terra-xhigh` (`TERRA/XHIGH`): Large-context work whose main operation is read-only
  retrieval, organization, comparison, or compression. Request
  `gpt-5.6-terra / xhigh` and pass explicit context references.
- `Sol -> luna-max`: Clear, bounded, independently verifiable delegated work.
  Request `gpt-5.6-luna / max`.
- `AUTO`: The remaining tasks. Sol may select Direct, Luna, Terra, or Sol and
  must record the selected route and rationale; this is a normal route, not a
  failed-lane fallback.
- `FALLBACK`: Use only when the requested route cannot run and the plan
  explicitly permits a safe compatibility lane. Label it `UNVERIFIED`; never
  use it to represent ordinary AUTO selection.

Route precedence is `SOL_XHIGH` for difficult reasoning, then `TERRA_XHIGH` for
large read-only context work, then `LUNA_MAX` for clear bounded work. When a
task needs both large-context extraction and difficult judgment, Terra may
produce a read-only context packet for a fresh Sol/xhigh execution; the Sol
controller still approves the final result.

Capability is conditional on the selected route. `LUNA_MAX` requires an exact
`gpt-5.6-luna / max` acceptance, `TERRA_XHIGH` (`TERRA/XHIGH`) requires
`gpt-5.6-terra / xhigh`, and `SOL_XHIGH` requires `gpt-5.6-sol / xhigh`.
Effective model telemetry is optional only under the selected native
`HOST_ACCEPTED` policy; a missing unselected lane must not block the task.

When a lower lane fails to complete or Sol rejects its result, do not retry the
same worker indefinitely. Allow exactly one second lower-lane attempt when the
issue is local and credible; use a new task id and keep the original scope. If
the second lower-lane attempt cannot pass Sol review, start one fresh
`SOL_XHIGH` worker with the failure evidence. If that replacement cannot pass
Sol review, return `BLOCKED` or `FIX` with a concrete next action.
- `USER_VISIBLE_TASK`: An explicit Desktop app task lane based on the host's
  `codex_app__create_thread` surface. It is permitted only when the user has
  explicitly authorized a user-owned task in the current plan; it is never an
  automatic fallback and never a way to register Luna.

Normal execution has the logical lanes `luna-max`, `terra-xhigh`, and
`sol-xhigh`, plus `AUTO` for unclassified work. Do not select a lane by name,
price, or prestige; use task fit and acceptance evidence.

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
  REVIEW_PENDING -> FIX_PENDING -> EXECUTING
  REVIEW_PENDING -> ESCALATION_PENDING -> HANDSHAKE_PENDING
Any state -> BLOCKED
```

- `HANDSHAKE_PENDING` means no implementation has been authorized.
- `EXECUTING` requires host dispatch, transport, scope, and the applicable identity gate.
- `RESULT_PENDING` means the lane has stopped and returned its structured result.
- `REVIEW_PENDING` means Sol is checking acceptance and evidence.
- `FIX_PENDING` is the single second attempt for the same lower route; it uses
  a new task id and must not resend an unchanged packet.
- `ESCALATION_PENDING` means two lower-lane attempts were not accepted and a
  fresh Sol/xhigh worker is being assigned; the prior worker is not reused.
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
3. Require capability preflight for the selected route. Use the Luna-specific
   [enablement guide](references/enablement.md) and [registration guide](references/registration.md)
   only when the selected route is `LUNA_MAX` and the host does not advertise
   the required pair.
4. Start a fresh execution context when the host supports it; exclude controller history unless a deliberate continuation is required.
5. Require the handshake packet before allowing implementation. An exact native
   spawn accepted without an explicit rejection may authorize execution under
   `HOST_ACCEPTED`; the worker result and Sol review remain mandatory.
6. Receive only the structured result, verification output, and evidence/artifact paths. Do not import the worker's full reasoning.
7. Review the result against `done_when`, scope, contradictions, regressions, and evidence freshness.
8. Allow at most one focused correction as the second attempt for the original
   lower lane and owner. Re-review the corrected result.
9. If the second lower-lane attempt still fails, assign one fresh `SOL_XHIGH`
   replacement and review that result separately. Sol alone decides the overall
   result and the next recovery action.
10. Return `PASS`, `FIX`, `BLOCKED`, or `HOST_REMEDIATION_REQUIRED` only after
    the selected worker and any required Sol/xhigh replacement have been
    reviewed.

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

Start every normal worker dispatch at priority 1 of the native generic worker
surface when it is visible in the current thread, with a fresh context. Run the
selected-route capability preflight in
[references/runtime-adapters.md](references/runtime-adapters.md) before dispatch:

```text
agent role: generic worker
route: LUNA_MAX | TERRA_XHIGH | SOL_XHIGH | AUTO
requested model/effort: <from plan packet>
fresh context: true
controller history: excluded
mutation policy: READ_ONLY | WRITE_ALLOWED
context sources: <explicit paths, attachment handles, or resource refs>
prompt: the compact plan packet plus the result-packet rules
```

`LUNA_MAX`, `TERRA_XHIGH`, and `SOL_XHIGH` are logical lanes. `AUTO` is a
controller-selected normal route. The surface adapter resolves a logical route
to a host schema; never assume that a lane name is a registered agent type.
`NATIVE_GENERIC` and `CUSTOM_ROLE` are native adapters with separate evidence
rules. `USER_VISIBLE_TASK` is an explicitly user-owned adapter with its own
receipt and host-observation rules; it is not interchangeable with a native
worker.

The canonical native v1 contract is `multi_agent_v1__spawn_agent`. A future
native surface may take priority 1 only when it is visible in the current
thread, explicitly declared as native, schema-compatible with the normalized
request, and able to return a task-bound handle/receipt plus fresh/history/scope
facts. The older
`collaboration.spawn_agent` schema cannot impersonate the canonical v1 surface,
borrow its model matrix, or reuse its receipts. It is independently eligible
only if its own declared schema, selected model/effort support, and evidence contract pass
preflight.

Capability discovery is bound to the current controller thread and host. Before
returning a route-specific enablement error, enumerate all callable worker
surfaces in that same thread. Prefer `multi_agent_v1__spawn_agent` when it is
exposed; send the exact model/effort pair selected by the plan. A surface may
expose Sol/Terra without Luna or Luna without Sol/Terra; missing capability on
an unselected route is not a blocker. An absent surface on one thread is
`THREAD_SURFACE_NOT_VISIBLE`, not proof that a model is globally unavailable.
Do not copy a model list, agent id, or receipt from another thread.

Capability is mandatory only for the selected worker route. Under the default
native policy, an exact spawn acceptance with a task-bound handle/receipt is an
`AVAILABLE` preflight even when effective model telemetry is unavailable. If the
host rejects the selected exact pair, returns no task handle/receipt, or reports
a mismatch/reroute, stop at the handshake gate and return a route-specific
enablement blocker; do not silently substitute another model. The skill and
`config.toml` can state this requirement but cannot register a model in the
host-owned worker surface; see [references/enablement.md](references/enablement.md)
for the Luna-specific configuration boundary.

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
surface can start the requested route and, when the exact request is accepted,
is enough to authorize a bounded native task under `HOST_ACCEPTED`; it does not
by itself upgrade `AGENT_HANDLE` and self-report evidence to `HOST_VERIFIED`.

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

If the selected route is `LUNA_MAX`, and the native surface is unavailable or
the explicitly approved Desktop task cannot pass its own transport, freshness,
scope, and identity gates, preserve `LUNA_MAX` and return
`HOST_REMEDIATION_REQUIRED` or `BLOCKED` with a concrete host-registration
request. Do not create an unapproved user-owned task, invoke an alternate local
transport, change the model, or widen permissions. Resume only after the host
registry changes and a new task-bound handshake succeeds.

`TERRA_XHIGH` and `SOL_XHIGH` use the selected native or host-declared generic
surface directly. They do not enter the Luna Desktop ladder or require Luna
enablement. If either exact pair is unavailable, preserve the selected route and
return its route-specific blocker unless the lower-lane escalation rule selects
a fresh `SOL_XHIGH` replacement.

The `SOL_XHIGH` lane must request `gpt-5.6-sol / xhigh`; `TERRA_XHIGH` must
request `gpt-5.6-terra / xhigh`; if the host cannot honor the selected pair,
classify the failure as `runtime` or `model_identity` and do not silently
downgrade. Do not retry an unavailable packet identically.

When the plan marks `Luna enablement: REQUIRED`, that field applies only to a
`LUNA_MAX` selection. For `TERRA_XHIGH`, `SOL_XHIGH`, `AUTO`, `DIRECT`, and
`SOL_ONLY`, set it to `NOT_REQUIRED`; the selected capability field carries the
actual preflight requirement. An accepted native dispatch satisfies the
selected route's default enablement gate; strict host telemetry is an optional
stronger requirement, not a reason to block an otherwise accepted native task.

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
- For `TERRA_XHIGH`, declare `Context profile: LARGE`, `Mutation policy: READ_ONLY`,
  and explicit context sources. Fresh context excludes controller history; it
  does not grant access to unstated chat text or attachments.
- If a second lower-lane result is rejected, include both compact failure
  summaries in the fresh `SOL_XHIGH` packet without importing either worker's
  private reasoning.

## Review gate

Approve only when:

- The result satisfies `done_when` and stays within the declared scope.
- The host dispatch satisfies the declared identity gate (`HOST_ACCEPTED` by
  default for native, or the explicitly selected stricter gate).
- Required checks ran against the final result, not an earlier attempt.
- Evidence explains failures and business impact, not only exit codes.
- No worker has approved the overall task.

If the first lower-lane result has a credible same-scope correction, return
`FIX` once and consume the second lower-lane attempt. If that second attempt is
not accepted, enter `ESCALATION_PENDING` for the fresh `SOL_XHIGH` worker. If
the Sol/xhigh replacement is not accepted, return `BLOCKED` with the concrete
failure class and next safe action.

## Result discipline

Use the exact result packet in [references/protocol.md](references/protocol.md). Keep the final response compact: outcome, route, evidence, verification, blocker, and residual risk. Under `HOST_ACCEPTED`, claim that the requested native model/effort was accepted by the host and label effective telemetry as `ASSUMED`/`HOST_MODEL_UNOBSERVABLE`; do not claim host-observed effective identity. Label worker claims as self-report.
