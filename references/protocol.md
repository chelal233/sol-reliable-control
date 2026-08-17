# Sol Reliable Control Protocol

These compact packets are exchanged between the Sol controller and an execution lane. Do not copy private reasoning or full transcripts. This protocol defines Sol routing, handshake, identity, fallback, and review only.

## Controller plan packet

```text
Task ID: <stable id>
Goal: <one sentence>
Done when: <observable acceptance conditions>
Controller: SOL
Route: DIRECT | SOL_ONLY | LUNA_MAX | SOL_XHIGH | FALLBACK
Execution context: FRESH | CURRENT
Requested model/effort: <for example gpt-5.6-luna / max or gpt-5.6-sol / xhigh>
Surface: AUTO | NATIVE_GENERIC | CUSTOM_ROLE | USER_VISIBLE_TASK
Dispatch priority: NATIVE_FIRST_THEN_DESKTOP | EXPLICIT_USER_VISIBLE_TASK
User-owned task: DENIED | ALLOWED | UNSPECIFIED
User approval: REQUIRED | GRANTED | NOT_REQUIRED | UNKNOWN
Dispatch tool/schema: <exact callable tool and declared fields, or UNKNOWN>
Recovery policy: BOUNDED_HOST_REMEDIATION | NONE
Luna enablement: REQUIRED | VERIFIED | NOT_ENABLED | UNKNOWN
Registration action: NONE | REQUEST_HOST_ENABLEMENT | REGISTER_CUSTOM_ROLE | REFRESH_PREFLIGHT
Capability preflight: REQUIRED
Task risk: LOW | HIGH
Identity gate: HOST_ACCEPTED | HOST_DISPATCH | OPERATOR_ATTESTED | HOST_VERIFIED
Operator attestation: REQUIRED | GRANTED | NOT_REQUIRED | UNKNOWN
Task scope: <exact files, components, or behaviors owned by this task>
Do not touch: <paths, behaviors, or systems excluded>
Dependencies: <ordered prerequisites or None>
Expected result: <artifact or behavior>
Verification: <commands or checks>
Fallback: <one safe compatibility lane or BLOCKED>
Lane rationale: <task-fit reason; do not use model prestige>
Quality basis: <fresh evidence, prior accepted result, or None>
```

Do not dispatch a packet with a missing goal, acceptance condition, scope, owner, verification, risk, or identity gate.

`Route` is a logical lane and `Surface` is a host adapter. `AUTO` means that
Sol must select an adapter only after capability preflight. The route binding
is fixed: `LUNA_MAX` requests `gpt-5.6-luna / max`, and `SOL_XHIGH` requests
`gpt-5.6-sol / xhigh`. A surface may reject that request; it may not silently
rewrite it.

For a normal `LUNA_MAX` packet, `NATIVE_FIRST_THEN_DESKTOP` is an
ordered contract:

1. Preflight and use the current-thread native subagent surface when its own
   declared schema, exact model/effort request, fresh-context semantics, and
   acceptance contract match the packet. Under the default native
   `HOST_ACCEPTED` gate, the exact spawn call must be accepted and return a
   task-bound handle or receipt; effective model telemetry is optional.
   `multi_agent_v1__spawn_agent` is canonical; a future equivalent must be
   explicitly declared native and independently verifiable.
2. If native preflight fails, select `USER_VISIBLE_TASK` only when the plan
   explicitly allows a user-owned task with `User approval: GRANTED`, and run
   its handshake. `UNSPECIFIED` requires an explicit confirmation; `DENIED`
   skips Desktop. Never create a task implicitly.
3. If Desktop is unavailable, not authorized, or fails, return `BLOCKED` with
   all surface failures and keep the requested `gpt-5.6-luna / max` binding. No
   silent model fallback or hidden transport is permitted.

The Desktop app task lane is therefore the conditional priority-2 step, not an
implicit task creation. It requires `Surface: USER_VISIBLE_TASK`,
`User-owned task: ALLOWED`, and `User approval: GRANTED`; it must never be
created merely to prove host enablement or bypass an explicit user-owned-task
packet. See [references/desktop-task-lane.md](desktop-task-lane.md).

Capability snapshots are thread- and host-bound. Enumerate worker tools from
the same controller thread that will dispatch the packet. The preferred native
surface is `multi_agent_v1__spawn_agent` when visible:

```text
multi_agent_v1__spawn_agent({
  fork_context: false,
  model: "gpt-5.6-luna",
  reasoning_effort: "max",
  message: <identity-only handshake or bounded packet>
})
```

`collaboration.spawn_agent` is a distinct schema. If it declares
`task_name`, `fork_turns`, `model`, `reasoning_effort`, and `message`, use its
own exact-call result as the authority for the current thread: an accepted
`gpt-5.6-luna / max` request can satisfy `HOST_ACCEPTED` even when the static
model list is incomplete. An explicit `Unknown model` rejection remains
unavailable. Do not conclude that Luna is globally unavailable if
`multi_agent_v1__spawn_agent` is visible under another thread binding. If no
eligible native surface is visible in the current thread, record
    `THREAD_SURFACE_NOT_VISIBLE` and evaluate the priority-2 Desktop gate.
   Return `HOST_REGISTRATION_REQUIRED` and request surface migration/rebind or a
   fresh controller thread when no eligible surface remains.

The older `collaboration.spawn_agent` schema cannot identify itself as
`multi_agent_v1__spawn_agent`, borrow the canonical wrapper's model matrix, or
reuse its receipt/evidence. It qualifies as native only under its own explicit
host declaration and verifiable contract; otherwise record the mismatch and
advance to the priority-2 Desktop gate; if it is not eligible or fails, return
`BLOCKED`.

`Luna enablement: REQUIRED` is the default deployment requirement. It means
the host must expose the normal Luna capability even when a particular packet
is independently routed to `SOL_XHIGH`; it does not force every task to use
Luna. Use [references/enablement.md](enablement.md) for the host request and
evidence contract.

When enablement is missing, set `Registration action` to the next concrete
host operation. Do not leave the caller with an unclassified `BLOCKED`: use
[references/registration.md](registration.md) for the exact native/custom-role
steps and the post-registration refresh check.

Every multi-route attempt must return a compact `route_trace` in the same task
packet. Each entry records `surface`, `priority`, `decision` (`SELECTED`,
`SKIPPED`, `FAILED`), `reason_code`, and a task-bound receipt when one exists.
For example, a legacy `collaboration.spawn_agent` allowlist mismatch is a
failed native candidate. Desktop is recorded as `SKIPPED` with
`USER_OWNED_TASK_UNSPECIFIED` when approval is not yet present; the route then
remains `BLOCKED` until the user grants or denies the Desktop task explicitly.
This prevents a policy sentence such as “do not use a user-owned task as an
enablement bypass” from being mis-normalized into an implicit approval.

## Controller states

```text
PLANNED -> HANDSHAKE_PENDING -> EXECUTING -> RESULT_PENDING
          -> REVIEW_PENDING -> ACCEPTED
          -> FIX_PENDING -> EXECUTING
Any state -> BLOCKED
```

`BLOCKED` means the lane could not be trusted or started. A failed handshake must never be represented as a worker result. `FIX_PENDING` allows one focused correction with the original scope and owner.

## Handshake packet

Ask the lane to return only:

```text
Task ID: <same id>
Route: <requested route>
Surface: NATIVE_GENERIC | CUSTOM_ROLE | USER_VISIBLE_TASK | UNKNOWN
Dispatch tool/schema: <exact callable tool and declared fields, or UNKNOWN>
Capability verdict: AVAILABLE | UNKNOWN | UNAVAILABLE
Capability evidence: <host metadata or receipt reference>
Host acceptance: ACCEPTED | REJECTED | UNKNOWN
Luna enablement: VERIFIED | NOT_ENABLED | UNKNOWN
Enablement evidence: <host allowlist/schema or launch capability reference>
Host requested model: <host fact or UNKNOWN>
Host observed model: <host fact or UNKNOWN>
Worker self-report model: <advisory claim or UNKNOWN>
Requested effort: <host fact or UNKNOWN>
Observed effort: <host fact or UNKNOWN>
Execution context: FRESH | CURRENT | UNKNOWN
Fresh-context proof: VERIFIED | UNVERIFIED | FAIL
Controller-history proof: EXCLUDED | UNKNOWN | FAIL
Transport: PASS | FAIL
Dispatch receipt: <host receipt id/path or UNKNOWN>
Dispatch receipt kind: HOST_RECEIPT | AGENT_HANDLE | UNKNOWN
Identity proof kind: HOST_REQUEST_ACCEPTED | HOST_OBSERVED_MODEL_EFFORT | ROLE_MAPPING_AND_LAUNCH_RECORD | OPERATOR_UI_ATTESTATION | SELF_REPORT_ONLY | UNKNOWN
Identity: ASSUMED | VERIFIED | ATTESTED | UNVERIFIED | FAIL
Operator evidence: <exact task/thread confirmation and UI-observed model/effort, or NONE>
Self-report warning: NONE | MISMATCH | UNKNOWN
Scope accepted: YES | NO
Blocker: <None or concrete reason>
```

`Host requested model`, `Host observed model`, `Requested effort`, `Observed effort`, and `Dispatch receipt` are host facts. Worker self-report fields are advisory. Transport success is not identity proof. An `AGENT_HANDLE` is not a `HOST_RECEIPT` unless the host contract says it is task-bound, but a task-bound handle is sufficient for the default native `HOST_ACCEPTED` gate. Extra runtime or UI fields are advisory and cannot add a `HOST_VERIFIED` gate.

For `Identity gate: HOST_ACCEPTED`, an exact native request accepted by the
selected surface, a task-bound `AGENT_HANDLE` or `HOST_RECEIPT`, fresh context,
history exclusion, scope acceptance, and no explicit rejection/mismatch/reroute
continue as `Routing verdict: HOST_ACCEPTED`, `Identity: ASSUMED`, and
`Identity proof kind: HOST_REQUEST_ACCEPTED`. Missing effective telemetry is
`HOST_MODEL_UNOBSERVABLE`, not a blocker for this default native gate. For
`Identity gate: HOST_DISPATCH`, a valid `HOST_RECEIPT` with no explicit host
mismatch may continue as `HOST_DISPATCHED_UNATTESTED`. For
`Identity gate: OPERATOR_ATTESTED`, a user-owned Desktop task may continue as
`OPERATOR_UI_ATTESTED` only when the plan explicitly requests that gate, `User
approval: GRANTED`, `Operator attestation: GRANTED`, and the operator confirms
the live GUI for the exact task/thread shows `gpt-5.6-luna / max`. The operator
evidence is not host telemetry and must be recorded as `Identity: ATTESTED`;
it never upgrades to `HOST_LAUNCH_RECORDED` or `HOST_VERIFIED`. For
`HOST_VERIFIED`, host-observed model/effort or an authoritative custom-role
launch record must match the request; unavailable proof is `BLOCKED`. An
explicit host rejection, mismatch, reroute, missing task handle/receipt, or
scope failure is always `BLOCKED`; do not silently change the requested gate.

`HOST_MODEL_UNOBSERVABLE` means that the host did not expose effective model/effort telemetry. It is not `HOST_MODEL_MISMATCH` and must not be reported as proof that the worker is not Luna. A UI picker, a request parameter, or a worker self-report remains advisory unless the caller explicitly selects the operator-attested gate.

The complete adapter contract and normalized field mapping are in
[references/runtime-adapters.md](runtime-adapters.md).

The registration guide and unblock procedure are in
[references/registration.md](registration.md). It is part of the protocol
contract for callers that cannot start `LUNA_MAX`.

## Mandatory Luna enablement gate

Before a normal dispatch, a plan with `Luna enablement: REQUIRED` must either
receive `Luna enablement: VERIFIED` or pass the default native
`HOST_ACCEPTED` gate for `gpt-5.6-luna / max`. If the selected surface
explicitly rejects the pair, returns no task-bound handle/receipt, or reports a
mismatch/reroute, set `Luna enablement: NOT_ENABLED`, return
`HOST_ENABLEMENT_REQUIRED` with failure class `runtime` / `model_identity`,
and do not create a worker. A static model list that is incomplete is not by
itself a rejection when the exact call is accepted.

`SOL_XHIGH` remains a normal replan selected by task fit or the escalation
gate; it is not a mechanism for hiding a missing mandatory Luna capability.
When Luna enablement is required, `Fallback: BLOCKED` remains in force and a
new user-owned task must not be created solely as an enablement workaround.
That prohibition does not silently deny a legitimate Desktop route: after a
native failure, the priority-2 Desktop gate may pause for confirmation when
`User-owned task: UNSPECIFIED`; `ALLOWED` plus `GRANTED` is eligible. If the
gate is not granted, preserve the requested lane and return `BLOCKED`.

An explicitly approved Desktop task is a separate execution choice, not host
enablement evidence. It may be used after native preflight fails when the caller
records `User-owned task: ALLOWED` and
`User approval: GRANTED`; `UNSPECIFIED` is not permission and must not be
normalized to `DENIED`.

## Configuration boundary

`config.toml` controls the top-level Codex session's model/effort selection; it
does not extend the host-owned `multi_agent_v1__spawn_agent` or
`collaboration.spawn_agent` model allowlist or
produce worker receipt/identity evidence. Changing the Sol controller to Luna
would change the controller identity, not enable the child lane. The enablement
request must therefore be handled by the host capability registry or a host
surface that explicitly supports custom/managed role registration.

## Native worker launch

Use the host's native generic worker surface when available:

```text
agent role: generic worker
route: LUNA_MAX | SOL_XHIGH
requested model/effort: <from plan packet>
fresh context: true
controller history: excluded
prompt: the compact plan packet plus the result-packet rules
```

When the current thread exposes `multi_agent_v1__spawn_agent`, the concrete
native call is:

```text
multi_agent_v1__spawn_agent({
  fork_context: false,
  model: <required model>,
  reasoning_effort: <required effort>,
  message: <compact plan packet plus result-packet rules>
})
```

The adapter must use the selected surface's declared field names. A surface
that uses `fork_turns: none` may express the same fresh-context contract, but
that field must not be sent to a schema that only accepts `fork_context`.

Do not send the `multi_agent_v1__spawn_agent` fields to
`collaboration.spawn_agent`, or send `task_name`/`fork_turns` to the former.
These are different host schemas. A thread that exposes only the latter must
not retry with a Luna model that its own enum rejects.

`LUNA_MAX` and `SOL_XHIGH` are logical lane labels, not required custom
registrations. `SOL_XHIGH` requests `gpt-5.6-sol / xhigh`. If the host rejects
the requested lane/model/effort, reports it unavailable, or observes a
different model, classify the failure as `runtime` or `model_identity`. Do not
retry the identical unavailable packet.

The native surface's advertised model list is capability evidence only. It
does not replace the task-bound receipt and host-observed identity required by
the selected identity gate.

## Custom-role dispatch

If the host exposes a registered custom role, the normalized request is:

```text
agent_type: luna-max-worker
fork_turns: none
requested model/effort: gpt-5.6-luna / max
prompt: identity handshake followed by the same bounded task packet
```

The host must return an authoritative role mapping and launch record. The
child may report permission and that it has done no task/write/subagent work;
the child must not be used as the source of unobservable model identity. A
role file, agent name, or self-report alone is not evidence.

### Explicit Desktop Luna task dispatch

When the plan explicitly permits a visible user-owned task, use the Codex app
task surface described in [references/desktop-task-lane.md](desktop-task-lane.md):

```text
codex_app__list_projects({})
codex_app__create_thread({
  target: { type: "project", projectId: <selected project id>,
            environment: { type: "worktree",
                            startingState: { type: "working-tree" } } },
  model: "gpt-5.6-luna",
  thinking: "max",
  prompt: <fresh handshake-only packet>
})
```

The ready response's `threadId` and `hostId` form the task-bound transport
receipt. Use `codex_app__wait_threads` and `codex_app__read_thread` on that same
pair; use `codex_app__send_message_to_thread` only for an explicitly approved
follow-up. `HOST_LAUNCH_RECORDED` still requires host-observed effective
Luna/max, not the UI picker or worker self-report. A pending `clientThreadId`,
an existing thread, or a fork is not fresh evidence. This route never performs
ACL/token remediation; a process-creation failure remains an execution blocker.

When the Desktop host does not expose effective model/effort telemetry, classify
the result as `HOST_MODEL_UNOBSERVABLE`, not `HOST_MODEL_MISMATCH`. A caller may
explicitly replan a user-owned Desktop task with `Identity gate:
OPERATOR_ATTESTED` and `Operator attestation: REQUIRED`; after the user confirms
the live GUI for that exact task/thread shows `gpt-5.6-luna / max`, set
`Operator attestation: GRANTED`, `Identity: ATTESTED`, and
`Routing verdict: OPERATOR_UI_ATTESTED`. This is a deliberate evidence tier,
not a host launch record. It must never be silently substituted for a plan that
requires `HOST_VERIFIED`.

### After native and Desktop dispatch

If no eligible native surface is visible, or the approved Desktop task cannot
pass its own receipt, freshness, scope, and identity gates, preserve the exact
Luna/max request and return `HOST_REGISTRATION_REQUIRED` or `BLOCKED`. Include
the failed surface, host-observed error, requested registry/role change, user
approval state, and the new handshake required after reload. Do not start a
hidden local transport, silently change the model, or broaden permissions.

## Lane selection

- Select `luna-max` by default for bounded work and difficult work whose scope remains narrow and independently verifiable.
- Select `sol-xhigh` for difficult reasoning, cross-cutting planning, arbitration, or final review; request `xhigh` effort.
- Do not escalate merely after a failure; identify the failure class and task-fit reason first.
- `SOL_XHIGH` is a normal replan, not an implicit fallback. Use it only when task fit or the repeated-failure escalation gate independently selects it.
- If the same issue has been rejected more than twice under `luna-max`, or unclear business semantics repeatedly cause regressions, stop retrying `luna-max` and route the issue to `sol-xhigh` with the failure evidence.
- `FALLBACK` is an explicit recovery route. It may name any safe compatible lane, but it is not a normal route and must be labeled `UNVERIFIED`.
- Fallback is limited to low-risk, narrow, independently verifiable work. High-risk work returns `BLOCKED` when the requested lane cannot be verified, unless the plan explicitly selected `OPERATOR_ATTESTED` and satisfies that gate's isolated-worktree, no-side-effect, and Sol-review controls.

Do not encode a fixed quality ranking. Model names, cost, and effort settings are runtime facts; acceptance evidence is the quality basis.

## Worker result packet

```text
Task ID: <stable id>
Status: PASS | PASS_WITH_WARNING | BLOCKED | HOST_REMEDIATION_REQUIRED
Summary: <what happened>
Changed or produced: <exact paths, artifacts, or None>
Verification: <checks, exit status, concise result>
Routing verdict: HOST_ACCEPTED | HOST_VERIFIED | HOST_LAUNCH_RECORDED | OPERATOR_UI_ATTESTED | HOST_DISPATCHED_UNATTESTED | HOST_MODEL_UNOBSERVABLE | HOST_MODEL_MISMATCH | DISPATCH_UNCONFIRMED
Identity: ASSUMED | VERIFIED | ATTESTED | UNVERIFIED | FAIL
Operator attestation: GRANTED | NOT_GRANTED | UNKNOWN
Operator evidence: <exact task/thread confirmation and UI-observed model/effort, or NONE>
Self-report warning: NONE | MISMATCH | UNKNOWN
Evidence: <artifact or result path bound to the acceptance conditions>
Review verdict: PASS | FIX | BLOCKED | NOT_RUN
Failure class: runtime | model_identity | permission | dependency | scope | verification | conflict | none
Blocker: <None or concrete reason>
Recovery state: NONE | HOST_REMEDIATION_REQUIRED | PROBE_PENDING | READY | EXHAUSTED
Recovery attempt: <number/max or None>
Permission request: <smallest host/admin action or None>
Next action: <concrete user/host operation or None>
```

`PASS` requires `Changed or produced`, `Verification`, and `Evidence`. For an
operator-attested Desktop result, `OPERATOR_UI_ATTESTED` requires the explicit
`Identity gate: OPERATOR_ATTESTED`, `Operator attestation: GRANTED`, a
task-bound `threadId`/`hostId`, a fresh task, controller history excluded, no
explicit host model mismatch/reroute, and `Identity: ATTESTED`. It must include
the exact task/thread confirmation and the model/effort observed by the user.
It is not `HOST_LAUNCH_RECORDED` or `HOST_VERIFIED`; the residual identity risk
must remain in `Blocker` or `Next action`. For a native result,
`HOST_ACCEPTED` requires an exact accepted request, task-bound handle/receipt,
fresh context, history exclusion, scope acceptance, and no explicit rejection
or reroute; record `Identity: ASSUMED` and
`Identity proof kind: HOST_REQUEST_ACCEPTED`. It authorizes dispatch but does
not replace the result packet or Sol review. For a host result, `HOST_VERIFIED`
requires both `Identity: VERIFIED` and
`execution_status=COMPLETED`. `WINDOWS_SANDBOX_ACL_FAILED` and
`PROCESS_CREATION_DENIED` are execution blockers with failure class `runtime`
or `permission`; they do not change the independent identity fact, but they
keep high-risk work `BLOCKED`. Do not silently switch models or relax sandbox
or permission policy to turn either failure into a pass. Use `PASS_WITH_WARNING`
only when the host gate passed and the warning is limited to an advisory
self-report mismatch. A worker may approve only its own result; Sol decides the
overall task.

## Fallback and failure rules

When the requested lane cannot start, preserve the original plan and owner.
Do not silently replace it. If the plan explicitly permits `FALLBACK`, select
one compatible lane, record `Identity: UNVERIFIED`, and continue only when the
risk and scope rules allow it. Otherwise return `BLOCKED` for the current
dispatch plus `HOST_REMEDIATION_REQUIRED` and a concrete `Next action` when a
safe host repair or permission request remains. Do not leave the caller with
only the word `BLOCKED` when a bounded recovery step is available.

If the plan has `Luna enablement: REQUIRED` and the host does not expose the
required pair, return `HOST_ENABLEMENT_REQUIRED` and keep `Fallback: BLOCKED`.
This is a host configuration blocker that requires an enablement response; it
is not permission to switch identity or model.

If a surface does not expose `gpt-5.6-luna`, do not automatically turn the
request into `SOL_XHIGH`: replan to `SOL_XHIGH` only when its normal task-fit or
escalation rule applies. Otherwise return `BLOCKED` with the original
`LUNA_MAX` request, the rejected surface, and the missing capability evidence.

`BLOCKED` applies to the current implementation dispatch, not to the recovery
workflow. When the caller can safely change host state, return a bounded
remediation packet instead of an unexplained dead end:

```text
Recovery state: HOST_REMEDIATION_REQUIRED | PROBE_PENDING | READY | EXHAUSTED
Recovery attempt: <number and maximum, for example 2/3>
Failure code: <PROCESS_CREATION_DENIED | WINDOWS_SANDBOX_ACL_FAILED | model/role mismatch>
Permission request: <smallest host/admin action or NONE>
Approval: REQUIRED | GRANTED | NOT_GRANTED
External change evidence: <host receipt, restart/setup record, or None>
Next probe: <minimal read-only probe class>
Stop condition: <what keeps implementation BLOCKED>
```

The caller must tell the user or host owner exactly what action is needed and
obtain approval before an ACL, token, registry, or elevated setup change. Do
not prescribe broad root/full-control ACLs from this protocol. After approval,
refresh or rebind the worker surface and run a new minimal read-only
PowerShell probe. Only a successful probe plus a fresh identity handshake may
authorize implementation. Every retry must use a new task id and new external
state evidence; an unchanged `PROCESS_CREATION_DENIED` or model rejection is
not a reason to resubmit the implementation packet.
