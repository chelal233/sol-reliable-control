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
Surface: NATIVE_GENERIC | CUSTOM_ROLE | HOST_MANAGED | UNKNOWN
Capability verdict: AVAILABLE | UNKNOWN | UNAVAILABLE
Capability evidence: <host metadata or receipt reference>
Fresh-context proof: VERIFIED | UNVERIFIED | FAIL
Controller-history proof: EXCLUDED | UNKNOWN | FAIL
Dispatch tool/schema: <exact callable tool and declared fields, or UNKNOWN>
Dispatch receipt kind: HOST_RECEIPT | AGENT_HANDLE | UNKNOWN
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

## Surface discovery and thread binding

Capability is scoped to the controller thread and host that will perform the
dispatch. A capability list captured in another thread, a UI picker, a role
file, or a worker's self-report cannot authorize this dispatch. Enumerate the
current callable surfaces in this order:

1. `multi_agent_v1__spawn_agent` with a model/effort matrix that contains
   `gpt-5.6-luna / max`.
2. A `CUSTOM_ROLE` or `HOST_MANAGED` surface with an authoritative role/launch
   record for `luna-max-worker`.
3. The installed `sol_luna_broker` MCP surface as an explicit managed
   transport; it can start Luna but remains `STARTED_UNVERIFIED` without host
   identity telemetry.
4. `collaboration.spawn_agent` only when its declared schema and model matrix
   contain the required Luna pair.

If a thread exposes only `collaboration.spawn_agent` with
`gpt-5.6-sol`/`gpt-5.6-terra`, that candidate is unavailable, but the result
must not be promoted to a global host verdict until all visible candidates have
been checked. If `multi_agent_v1__spawn_agent` is visible on a sibling thread
but not this controller, use `THREAD_SURFACE_NOT_VISIBLE` and request a host
surface migration/rebind or a fresh controller thread. Never transplant a
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

Use this form only when the current schema declares these fields and advertises
the exact Luna/max pair. The two schemas are not interchangeable.

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

### MCP broker variant

The Sol Luna broker is a local STDIO MCP server that provides an explicit
`HOST_MANAGED` transport when the current controller thread cannot see a native
worker tool. Its stable tool schema is:

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

`BROKER_RUN_RECEIPT` is task-bound to the broker invocation but is not a
`HOST_RECEIPT`. A matching worker self-report proves only that the requested
prompt was answered; it does not prove the effective runtime identity. Treat a
successful broker run as `STARTED_UNVERIFIED` and keep `HOST_VERIFIED` closed
until the host returns independent model/effort evidence or an authoritative
launch record. This adapter may be the operational Luna path, but it must not
silently downgrade a high-risk plan.

## Gate evaluation

`HOST_VERIFIED` requires all of the following:

1. Capability is `AVAILABLE` for the exact requested model/effort pair.
2. The host returns a `HOST_RECEIPT` bound to the task packet.
3. Fresh context is `VERIFIED` and controller history is `EXCLUDED`.
4. Identity proof is `HOST_OBSERVED_MODEL_EFFORT` or
   `ROLE_MAPPING_AND_LAUNCH_RECORD`, and it matches the request.
5. Scope is accepted and no host mismatch is reported.

`HOST_DISPATCHED_UNATTESTED` is allowed only for a low-risk plan that asked
for `HOST_DISPATCH`, with a valid host receipt and no explicit mismatch. It is
not sufficient for high-risk work.

Any missing receipt, rejected model, observed mismatch, unknown context
semantics, or self-report-only identity yields `BLOCKED` for a
`HOST_VERIFIED` plan. Keep the original route and owner in the blocker.
