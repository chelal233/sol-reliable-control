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
Identity gate: HOST_DISPATCH | HOST_VERIFIED
Task packet: <bounded plan packet>
```

The adapter returns these facts before execution is authorized:

```text
Surface: NATIVE_GENERIC | CUSTOM_ROLE | HOST_MANAGED | USER_VISIBLE_TASK | UNKNOWN
Capability verdict: AVAILABLE | UNKNOWN | UNAVAILABLE
Capability evidence: <host metadata or receipt reference>
Fresh-context proof: VERIFIED | UNVERIFIED | FAIL
Controller-history proof: EXCLUDED | UNKNOWN | FAIL
Dispatch tool/schema: <exact callable tool and declared fields, or UNKNOWN>
Dispatch receipt kind: HOST_RECEIPT | HOST_JOB_RECEIPT | AGENT_HANDLE | UNKNOWN
Identity proof kind: HOST_OBSERVED_MODEL_EFFORT | ROLE_MAPPING_AND_LAUNCH_RECORD | SELF_REPORT_ONLY | UNKNOWN
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
2. **Priority 2: HOST_MANAGED MCP.** Use `sol_luna_broker` only when priority 1
   is not visible, its declared schema/model cannot express Luna/max, or its
   preflight cannot supply the required host evidence. Record the exact native
   failure condition before broker preflight.

A separately registered `CUSTOM_ROLE` remains an explicit specialized route;
it does not reorder this normal-dispatch ladder. If both ladder candidates fail
their own preflight, preserve the requested model and return `BLOCKED`.

If a thread exposes only `collaboration.spawn_agent` with
`gpt-5.6-sol`/`gpt-5.6-terra`, that candidate is unavailable, but the result
must not be promoted to a global host verdict until all visible candidates have
been checked. If `multi_agent_v1__spawn_agent` is visible on a sibling thread
but not this controller, use `THREAD_SURFACE_NOT_VISIBLE` and request a host
surface migration/rebind or a fresh controller thread only if priority-2 MCP is
also unavailable. Never transplant a sibling's `agent_id`, receipt, or
self-report.

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

## Adapter: HOST_MANAGED

Some hosts launch the selected worker internally from the Sol plan instead of
exposing either a generic model override or a custom role. This adapter is
valid only when the host returns the same normalized evidence: a task-bound
`HOST_RECEIPT`, fresh-context proof, controller-history proof, and host-owned
identity evidence. It is an internal dispatch surface, not permission to
create a new user-owned Codex task merely to obtain a model.

## Adapter: USER_VISIBLE_TASK

This is an explicit Desktop app task adapter, based on the route documented by
`sol-advisor`. It is outside the normal native-first -> MCP-second ladder and
requires all of the following plan facts:

```text
Surface: USER_VISIBLE_TASK
Dispatch priority: EXPLICIT_USER_VISIBLE_TASK
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
starts the local Sol broker, invokes `setupStart`, changes ACLs, or broadens
permissions. It is not a native subagent and it must not be silently selected
when `User-owned task` is denied.

### MCP broker variant

The Sol Luna broker is a local STDIO MCP server that provides the priority-2
`HOST_MANAGED` transport only when the current controller thread cannot see a
native worker tool, the visible native schema/model mismatches Luna/max, or the
native preflight cannot produce the required host evidence. Its stable tool
schema is:

```text
sol_luna_exec({
  task_id: <stable id>,
  workdir: <approved worktree>,
  prompt: <bounded packet>,
  sandbox: "read-only" | "workspace-write",
  handshake_only: true | false
})
```

The broker itself fixes `gpt-5.6-luna / max`, starts `codex exec --ephemeral`
with user configuration ignored and strict parsing enabled, and returns:

```text
surface: HOST_MANAGED
receipt kind: BROKER_RUN_RECEIPT
fresh: true
history: EXCLUDED
identity proof kind: SELF_REPORT_ONLY | UNKNOWN
host observed model/effort: UNKNOWN unless the host supplies telemetry
```

The default app-server broker fixes `gpt-5.6-luna / max` and starts a fresh
ephemeral thread. Its `thread/start` response is a task-bound
`HOST_LAUNCH_RECORD` containing host model/effort. When that record matches and
the same turn has no `model/rerouted` event, identity may be `VERIFIED` with
proof kind `ROLE_MAPPING_AND_LAUNCH_RECORD`; overall `HOST_VERIFIED` also
requires completed execution. Set
`SOL_LUNA_TRANSPORT=cli` only for legacy diagnostics; that route returns a
`BROKER_RUN_RECEIPT`, has no host telemetry, and remains
`STARTED_UNVERIFIED`. Neither route permits silent model substitution.

The app-server `thread/start` response is a distinct host-managed launch
record. It may be accepted as `ROLE_MAPPING_AND_LAUNCH_RECORD` only when all
of these fields are captured from the same fresh ephemeral launch: exact
requested `model`, exact `reasoningEffort`, task-bound thread id, and the
absence of a `model/rerouted` event for that turn. A launch record that says
Luna/max but is followed by a host reroute or another host-effective identity
fact is `HOST_MODEL_MISMATCH`, not verified. A worker's generic self-report is
advisory and does not override the host launch record.

The broker does not become a native surface and does not change the requested
model. Transport success, a broker receipt, or worker self-report alone is not
`HOST_VERIFIED`; apply the host-managed evidence and execution gates below.

Long-running implementation packets use the broker's asynchronous variant:
`sol_luna_exec(execution_mode=async)` returns a task-bound `HOST_JOB_RECEIPT`
and `job_id` without holding the MCP call open. `sol_luna_poll` retrieves the
completed nested worker payload. The job receipt proves submission and fresh
context only; the nested app-server launch record still must satisfy the normal
`HOST_VERIFIED` gate. A caller deadline therefore does not discard an already
submitted task or authorize a duplicate submission.

`HOST_JOB_RECEIPT` is a submission/lookup receipt only; it is not a substitute
for `HOST_RECEIPT` or for the nested worker's host identity evidence.

The app-server adapter keeps identity and execution as separate facts. A
matching launch record with no `model/rerouted` event yields
`identity=VERIFIED` even if execution is `BLOCKED`; the overall status is
`HOST_VERIFIED` only when `execution_status=COMPLETED` as well. Timeout and turn
errors remain execution blockers, and Windows sandbox evidence is classified as
`WINDOWS_SANDBOX_ACL_FAILED` or `PROCESS_CREATION_DENIED`. The MCP payload
returns `execution_status`, `execution_blocker_code`, and the output-redacted
`execution_blocker`.

The broker applies output-only privacy redaction before returning MCP content:
Windows and Unix user-home path segments, `DESKTOP-*` host names (and the
current host name when available), and credential-shaped values are replaced.
Raw runtime paths, stderr, prompts, and worker output are never returned
without this sanitization. Redaction does not store or transmit secrets and
does not weaken the workdir allowlist or identity gate.

## Gate evaluation

`HOST_VERIFIED` requires all of the following:

1. Capability is `AVAILABLE` for the exact requested model/effort pair.
2. The host returns a `HOST_RECEIPT` bound to the task packet.
3. Fresh context is `VERIFIED` and controller history is `EXCLUDED`.
4. Identity proof is `HOST_OBSERVED_MODEL_EFFORT` or
   `ROLE_MAPPING_AND_LAUNCH_RECORD`, and it matches the request. For an
   app-server record, no host reroute may be present.
5. Scope is accepted and no host mismatch is reported.

`HOST_DISPATCHED_UNATTESTED` is allowed only for a low-risk plan that asked
for `HOST_DISPATCH`, with a valid host receipt and no explicit mismatch. It is
not sufficient for high-risk work.

Any missing receipt, rejected model, observed mismatch, unknown context
semantics, or self-report-only identity yields `BLOCKED` for a
`HOST_VERIFIED` plan. Keep the original route and owner in the blocker.
