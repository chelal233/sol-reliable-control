# Sol Runtime Surface Adapters

Sol routes are logical policy labels. A host surface is the mechanism that may
or may not be able to realize the requested model, effort, context, receipt,
and identity evidence. The controller must select a surface only after a
capability preflight; it must never infer a surface from the lane name.

## Normalized dispatch contract

Every dispatch is evaluated with this normalized input:

```text
Task ID: <stable id>
Route: LUNA_MAX | TERRA_XHIGH | SOL_XHIGH | AUTO
Requested model/effort: <route binding>
Selected capability: NONE | LUNA_MAX | TERRA_XHIGH | SOL_XHIGH | HOST_DEFAULT
Luna enablement: REQUIRED | VERIFIED | NOT_ENABLED | NOT_REQUIRED | UNKNOWN
Execution context: FRESH
Controller history: EXCLUDED
Task difficulty: SIMPLE | HARD | UNKNOWN
Context profile: SMALL | LARGE | UNKNOWN
Mutation policy: READ_ONLY | WRITE_ALLOWED
Context sources: <explicit paths, attachment handles, or resource refs>
Identity gate: HOST_ACCEPTED | HOST_DISPATCH | OPERATOR_ATTESTED | HOST_VERIFIED
Operator attestation: REQUIRED | GRANTED | NOT_REQUIRED | UNKNOWN
Task packet: <bounded plan packet>
```

The adapter returns these facts before execution is authorized:

```text
Surface: NATIVE_GENERIC | CUSTOM_ROLE | USER_VISIBLE_TASK | UNKNOWN
Capability verdict: AVAILABLE | UNKNOWN | UNAVAILABLE
Capability evidence: <host metadata or receipt reference>
Host acceptance: ACCEPTED | REJECTED | UNKNOWN
Fresh-context proof: VERIFIED | UNVERIFIED | FAIL
Controller-history proof: EXCLUDED | UNKNOWN | FAIL
Dispatch tool/schema: <exact callable tool and declared fields, or UNKNOWN>
Dispatch receipt kind: HOST_RECEIPT | AGENT_HANDLE | UNKNOWN
Identity proof kind: HOST_REQUEST_ACCEPTED | HOST_OBSERVED_MODEL_EFFORT | ROLE_MAPPING_AND_LAUNCH_RECORD | OPERATOR_UI_ATTESTATION | SELF_REPORT_ONLY | UNKNOWN
Identity: ASSUMED | VERIFIED | ATTESTED | UNVERIFIED | FAIL
Operator attestation: GRANTED | NOT_GRANTED | UNKNOWN
Operator evidence: <exact task/thread confirmation and UI-observed model/effort, or NONE>
```

`AVAILABLE` means the host says the request can be submitted. For the default
native `HOST_ACCEPTED` gate, the stronger runtime condition is an accepted
exact spawn with a task-bound handle/receipt, fresh/history/scope facts, and no
rejection or reroute. Record `Identity: ASSUMED` and
`Identity proof kind: HOST_REQUEST_ACCEPTED`; effective telemetry remains
optional. `HOST_VERIFIED` still requires independent host identity proof.

When the selected capability and exact model/effort pair are rejected, return
`NOT_ENABLED` / `HOST_ENABLEMENT_REQUIRED` before implementation. For
`LUNA_MAX`, this is also recorded as `Luna enablement: NOT_ENABLED`; for
`TERRA_XHIGH` and `SOL_XHIGH`, Luna remains `NOT_REQUIRED`. An incomplete static
model list is not by itself a rejection when the exact call is accepted. That
state is not a compatibility fallback and must not substitute another model.

## Logical route bindings

| Route | Required model | Required effort | Normal use |
| --- | --- | --- | --- |
| `LUNA_MAX` | `gpt-5.6-luna` | `max` | Bounded, independently verifiable execution |
| `TERRA_XHIGH` | `gpt-5.6-terra` | `xhigh` | Large-context, read-only retrieval and synthesis |
| `SOL_XHIGH` | `gpt-5.6-sol` | `xhigh` | Deep reasoning, arbitration, cross-cutting planning, or final review |

These are the normal Sol worker lanes. `SOL_XHIGH` is selected directly for
difficult work and is also the fresh-worker takeover after two lower-lane
attempts cannot complete or cannot pass Sol review; it is not an implicit
compatibility fallback.

### `TERRA_XHIGH` (`TERRA/XHIGH`) read-only contract

`TERRA_XHIGH` is a normal native worker route, not a Luna fallback. It requires
an exact `gpt-5.6-terra / xhigh` request, `Context profile: LARGE`,
`Mutation policy: READ_ONLY`, and explicit context sources. The worker may read
those sources and return a compact evidence packet, but it must not edit files,
approve the overall task, or create descendants. If the large-context task also
requires difficult judgment, send the evidence packet to a fresh `SOL_XHIGH`
worker and keep Sol controller review as the final gate.

## Surface discovery, priority, and thread binding

Capability is scoped to the controller thread and host that will perform the
dispatch. A capability list captured in another thread, a UI picker, a role
file, or a worker's self-report cannot authorize this dispatch. For every
normal worker route, use the current-thread native surface first. Only
`LUNA_MAX` has the additional Desktop-task alternative:

1. **Priority 1: current-thread native.** Use
   `multi_agent_v1__spawn_agent` when an exact selected-route model/effort call is
   accepted and its preflight supplies fresh/history/scope facts and a
   task-bound handle/receipt. Effective model telemetry is optional under
   `HOST_ACCEPTED`; a future equivalent is eligible only when the host
   explicitly declares a native contract.
2. **Priority 2 for `LUNA_MAX`: USER_VISIBLE_TASK (conditional).** After native preflight
   fails, and only when the plan explicitly allows a user-owned task with user
   approval, use the Desktop task adapter. `UNSPECIFIED` requires confirmation;
   never synthesize `DENIED` or create a task implicitly.
3. If the selected native route is not eligible, preserve the requested lane
   and return a route-specific `BLOCKED`/`HOST_ENABLEMENT_REQUIRED` result. Do
   not start a hidden transport. A failed `LUNA_MAX` or `TERRA_XHIGH` result,
   after execution rather than preflight, consumes one lower-lane attempt; a
   second failed attempt may trigger the fresh `SOL_XHIGH` takeover.

A separately registered `CUSTOM_ROLE` remains an explicit specialized route;
it does not reorder this normal-dispatch ladder. If all eligible ladder
candidates fail their own preflight, preserve the requested model and return
`BLOCKED`.

If a thread exposes only `collaboration.spawn_agent` with
`gpt-5.6-sol`/`gpt-5.6-terra`, an explicit rejection of the exact Luna call is
unavailable, but the result must not be promoted to a global host verdict
until all visible candidates have been checked. If the exact call is accepted,
the candidate is eligible for `HOST_ACCEPTED` even if its static enum is stale
or incomplete. If `multi_agent_v1__spawn_agent` is visible on a sibling thread
but not this controller, use `THREAD_SURFACE_NOT_VISIBLE`, evaluate the
priority-2 Desktop gate. Request a host surface migration/rebind or a fresh
controller thread when no eligible surface remains. Never transplant a
sibling's `agent_id`, receipt, or self-report.

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

Use this form only when the current schema declares these fields and the exact
call accepts the Luna/max pair. A static advertised list is useful preflight
evidence but does not override an actual host acceptance or rejection. The two
schemas are not interchangeable. The older `collaboration.spawn_agent` schema
cannot impersonate `multi_agent_v1__spawn_agent`, borrow its capability
evidence, or be called with native-v1 fields; it must qualify independently
under its own host declaration and evidence contract.

Preflight must issue or observe the exact requested spawn. A host rejection
such as `Unknown model` is an explicit `UNAVAILABLE` result, not a reason to
retry the same packet or substitute a different model. An accepted exact call
is `AVAILABLE` for `HOST_ACCEPTED` even when effective identity telemetry is
unobservable.

The raw `agent_id` returned by a generic spawn is an `AGENT_HANDLE`, not
effective identity proof. When it binds the accepted task, it is sufficient
task-bound evidence for the default `HOST_ACCEPTED` gate; it becomes a usable
`HOST_RECEIPT` only when the host contract explicitly labels it that way. For
`HOST_VERIFIED`, identity proof must be `HOST_OBSERVED_MODEL_EFFORT` or an
authoritative role launch record; a worker self-report is advisory only.

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

The host launch record must accept and bind `agent_type`, `fork_turns`, model,
reasoning effort, and a task handle/receipt. Under `HOST_ACCEPTED`, an exact
accepted role launch with fresh/history/scope facts and no rejection/reroute
records `Identity: ASSUMED` and `Identity proof kind:
HOST_REQUEST_ACCEPTED`. Under `HOST_VERIFIED`, the authoritative role launch
record remains the required identity proof. The child handshake may prove
permission and the absence of task/write/subagent activity, but it must not be
asked to prove unobservable model identity.

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

`HOST_ACCEPTED` requires all of the following:

1. The selected native surface accepted the exact requested model/effort pair.
2. A task-bound `AGENT_HANDLE` or `HOST_RECEIPT` was returned.
3. Fresh context is `VERIFIED` and controller history is `EXCLUDED`.
4. Scope is accepted and no explicit rejection, mismatch, or reroute is
   present.
5. Record `Identity: ASSUMED` and `Identity proof kind:
   HOST_REQUEST_ACCEPTED`; missing effective telemetry is advisory.

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
semantics, or self-report-only identity yields `BLOCKED` for the applicable
gate. Missing effective telemetry alone yields `HOST_MODEL_UNOBSERVABLE` and
blocks only a strict `HOST_VERIFIED` plan, not an otherwise valid native
`HOST_ACCEPTED` dispatch. Keep the original route and owner in the blocker.
