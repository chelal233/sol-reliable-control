# Sol Runtime Surface Adapters

Sol routes are logical policy labels. A host surface is the mechanism that may
or may not be able to realize the requested model, effort, context, receipt,
and identity evidence. The controller must select a surface only after a
capability preflight; it must never infer a surface from the lane name.

## Normalized dispatch contract

Every dispatch is evaluated with this normalized input:

```text
Task ID: <stable id>
Route: LUNA_MAX | SOL_XHIGH
Requested model/effort: <route binding>
Luna enablement: REQUIRED
Execution context: FRESH
Controller history: EXCLUDED
Identity gate: HOST_DISPATCH | OPERATOR_ATTESTED | HOST_VERIFIED
Operator attestation: REQUIRED | GRANTED | NOT_REQUIRED | UNKNOWN
Task packet: <bounded plan packet>
```

The adapter returns these facts before execution is authorized:

```text
Surface: NATIVE_GENERIC | CUSTOM_ROLE | USER_VISIBLE_TASK | UNKNOWN
Capability verdict: AVAILABLE | UNKNOWN | UNAVAILABLE
Capability evidence: <host metadata or receipt reference>
Fresh-context proof: VERIFIED | UNVERIFIED | FAIL
Controller-history proof: EXCLUDED | UNKNOWN | FAIL
Dispatch tool/schema: <exact callable tool and declared fields, or UNKNOWN>
Dispatch receipt kind: HOST_RECEIPT | AGENT_HANDLE | UNKNOWN
Identity proof kind: HOST_OBSERVED_MODEL_EFFORT | ROLE_MAPPING_AND_LAUNCH_RECORD | OPERATOR_UI_ATTESTATION | SELF_REPORT_ONLY | UNKNOWN
Identity: VERIFIED | ATTESTED | UNVERIFIED | FAIL
Operator attestation: GRANTED | NOT_GRANTED | UNKNOWN
Operator evidence: <exact task/thread confirmation and UI-observed model/effort, or NONE>
```

`AVAILABLE` means the host says the request can be submitted. It does not
prove that the worker actually ran with the requested identity. Runtime
identity is gated separately by the receipt and identity-proof fields.

When `Luna enablement: REQUIRED` and the requested Luna pair is absent, the
adapter returns `NOT_ENABLED` / `HOST_ENABLEMENT_REQUIRED` before dispatch.
That state is not a compatibility fallback and must not create a worker.

## Logical route bindings

| Route | Required model | Required effort | Normal use |
| --- | --- | --- | --- |
| `LUNA_MAX` | `gpt-5.6-luna` | `max` | Bounded, independently verifiable execution |
| `SOL_XHIGH` | `gpt-5.6-sol` | `xhigh` | Deep reasoning, arbitration, cross-cutting planning, or final review |

These are the only normal Sol lanes. `SOL_XHIGH` is a normal replan when task
fit or the escalation gate selects it; it is not an implicit compatibility
fallback.

## Surface discovery, priority, and thread binding

Capability is scoped to the controller thread and host that will perform the
dispatch. A capability list captured in another thread, a UI picker, a role
file, or a worker's self-report cannot authorize this dispatch. For normal
`LUNA_MAX`, apply this two-level ladder:

1. **Priority 1: current-thread native.** Use
   `multi_agent_v1__spawn_agent` when its model/effort matrix contains
   `gpt-5.6-luna / max` and its preflight supplies the required host evidence.
   A future equivalent is eligible only when the host explicitly declares a
   native contract whose schema and evidence are verifiable.
2. **Priority 2: USER_VISIBLE_TASK (conditional).** After native preflight
   fails, and only when the plan explicitly allows a user-owned task with user
   approval, use the Desktop task adapter. `UNSPECIFIED` requires confirmation;
   never synthesize `DENIED` or create a task implicitly.
3. If Desktop is not eligible or fails, preserve the requested lane and return
   `BLOCKED` with a host-registration action. Do not start a hidden transport.

A separately registered `CUSTOM_ROLE` remains an explicit specialized route;
it does not reorder this normal-dispatch ladder. If all eligible ladder
candidates fail their own preflight, preserve the requested model and return
`BLOCKED`.

If a thread exposes only `collaboration.spawn_agent` with
`gpt-5.6-sol`/`gpt-5.6-terra`, that candidate is unavailable, but the result
must not be promoted to a global host verdict until all visible candidates have
been checked. If `multi_agent_v1__spawn_agent` is visible on a sibling thread
but not this controller, use `THREAD_SURFACE_NOT_VISIBLE`, evaluate the
priority-2 Desktop gate. Request a host surface migration/rebind or a fresh
controller thread when no eligible surface remains. Never
transplant a sibling's `agent_id`, receipt, or self-report.

## Adapter: NATIVE_GENERIC

Use this adapter when the current host exposes a generic worker surface with
model and effort overrides. The preferred native schema is
`multi_agent_v1__spawn_agent`:

```text
multi_agent_v1__spawn_agent({
  fork_context: false,
  model: <required model>,
  reasoning_effort: <required effort>,
  message: <compact task packet>
})
```

`fork_context: false` is the native-schema spelling of a fresh context with
controller history excluded. If another host surface uses `fork_turns: none`,
the adapter may map the same normalized meaning to that field; do not send a
field that the selected surface does not declare.

The alternate `collaboration.spawn_agent` schema must be inspected separately:

```text
collaboration.spawn_agent({
  task_name: <stable task id or host task name>,
  fork_turns: "none",
  model: "gpt-5.6-luna",
  reasoning_effort: "max",
  message: <compact task packet>
})
```

Use this form only when the current schema declares these fields and advertises
the exact Luna/max pair. The two schemas are not interchangeable. The older
`collaboration.spawn_agent` schema cannot impersonate `multi_agent_v1__spawn_agent`,
borrow its capability evidence, or be called with native-v1 fields; it must
qualify independently under its own host declaration and evidence contract.

Preflight must confirm that the host's advertised model/effort matrix contains
the required pair. A host rejection such as `Unknown model` is an explicit
`UNAVAILABLE` result, not a reason to retry the same packet or substitute a
different model.

The raw `agent_id` returned by a generic spawn is an `AGENT_HANDLE`, not a
task-bound host receipt and not identity proof. It becomes a usable
`HOST_RECEIPT` only when the host contract explicitly identifies it as a
task-bound dispatch receipt and exposes the requested/observed model and
effort. For `HOST_VERIFIED`, identity proof must be
`HOST_OBSERVED_MODEL_EFFORT`; a worker self-report is advisory only.

A successful native probe on one controller thread is evidence for that
thread's callable surface only. It is not a receipt or identity proof for a
different target thread.

## Adapter: CUSTOM_ROLE

Use this adapter only when the host confirms that the role is registered and
returns an authoritative launch record. The normalized role request is:

```text
agent_type: luna-max-worker
fork_turns: none
requested model/effort: gpt-5.6-luna / max
prompt: <identity handshake, then the same bounded task packet>
```

The host launch record must bind `agent_type`, `fork_turns`, model, reasoning
effort, and task receipt. The child handshake may prove permission and the
absence of task/write/subagent activity, but it must not be asked to prove
unobservable model identity. The required identity proof kind is
`ROLE_MAPPING_AND_LAUNCH_RECORD`.

The presence of `.codex/agents/*.toml`, a role name, or a child self-report is
not enough: TOML/config alone is not proof. A role that the current host does
not advertise is `UNAVAILABLE`, even if the file exists in a repository.

## Adapter: USER_VISIBLE_TASK

This is the conditional priority-2 Desktop app task adapter, based on the route
documented by `sol-advisor`. It is part of the normal native-first -> Desktop
ladder and requires all of the following plan facts:

```text
Surface: USER_VISIBLE_TASK
Dispatch priority: NATIVE_FIRST_THEN_DESKTOP
User-owned task: ALLOWED
User approval: GRANTED
Requested model/effort: gpt-5.6-luna / max
Execution context: FRESH
Controller history: EXCLUDED
```

The host tools are `codex_app__list_projects`,
`codex_app__create_thread`, `codex_app__wait_threads`,
`codex_app__read_thread`, and (only for an approved continuation)
`codex_app__send_message_to_thread`. The create call uses
`model="gpt-5.6-luna"` and `thinking="max"`; a ready `threadId` plus `hostId`
is the transport receipt. A pending `clientThreadId`, an existing thread, a
fork, a UI picker, or worker self-report cannot prove freshness or identity.

The app task host must independently report effective model/effort and the
fresh/history facts before the result can reach `HOST_VERIFIED`. If it reports
`PROCESS_CREATION_DENIED`, `WINDOWS_SANDBOX_ACL_FAILED`, or another permission
failure, keep identity and execution separate and stop. This adapter never
invokes `setupStart`, changes ACLs, or broadens permissions. It is not a native
subagent and it must not be silently selected
when `User-owned task` is denied.

If the Desktop host omits effective model/effort telemetry, return
`HOST_MODEL_UNOBSERVABLE`, not `HOST_MODEL_MISMATCH`. The caller may select the
explicit `OPERATOR_ATTESTED` gate only after a user-owned task is approved. The
user must confirm the live GUI for the exact `threadId`/`hostId` shows
`gpt-5.6-luna / max`; record `Identity proof kind: OPERATOR_UI_ATTESTATION`,
`Identity: ATTESTED`, `Operator attestation: GRANTED`, and
`Routing verdict: OPERATOR_UI_ATTESTED`. This evidence tier never satisfies
`HOST_VERIFIED` and cannot be silently substituted for it.

## After native and Desktop preflight

If no eligible native surface is visible, or the approved Desktop task cannot
pass its own receipt, freshness, scope, and identity gates, preserve the exact
Luna/max request and return `HOST_REGISTRATION_REQUIRED` or `BLOCKED`. Include
the failed surface, host-observed error, requested registry/role change, user
approval state, and the new handshake required after reload. Do not start a
hidden local transport, silently change the model, or broaden permissions.

## Gate evaluation

`HOST_VERIFIED` requires all of the following:

1. Capability is `AVAILABLE` for the exact requested model/effort pair.
2. The host returns a `HOST_RECEIPT` bound to the task packet.
3. Fresh context is `VERIFIED` and controller history is `EXCLUDED`.
4. Identity proof is `HOST_OBSERVED_MODEL_EFFORT` or
   `ROLE_MAPPING_AND_LAUNCH_RECORD`, and it matches the request. No host
   reroute or conflicting effective identity may be present.
5. Scope is accepted and no host mismatch is reported.

`OPERATOR_UI_ATTESTED` is a separate explicit gate for a user-owned Desktop
task. It requires `Identity gate: OPERATOR_ATTESTED`,
`Operator attestation: GRANTED`, `User approval: GRANTED`, a task-bound
`threadId`/`hostId`, fresh context, controller history excluded, no explicit
host mismatch/reroute, and a written operator confirmation that the live GUI
for that exact task displays `gpt-5.6-luna / max`. Use
`Identity proof kind: OPERATOR_UI_ATTESTATION` and `Identity: ATTESTED`.
This is not `HOST_LAUNCH_RECORDED` or `HOST_VERIFIED`. For `HIGH` work it also
requires an isolated worktree, no secrets/destructive/ACL/external side effects,
no descendants, and Sol review before commit or merge.

`HOST_DISPATCHED_UNATTESTED` is allowed only for a low-risk plan that asked
for `HOST_DISPATCH`, with a valid host receipt and no explicit mismatch. It is
not sufficient for high-risk work.

Any missing receipt, rejected model, observed mismatch, unknown context
semantics, or self-report-only identity yields `BLOCKED` for a
`HOST_VERIFIED` plan. Keep the original route and owner in the blocker.
