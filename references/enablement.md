# LUNA_MAX Host Enablement Contract

This package can require and verify a host capability; it cannot change the
host's model allowlist from a skill file. Source/runtime synchronization is not
host enablement. The host owner or host capability layer must perform the
enablement, then return evidence that Sol can verify.

For a caller-facing registration sequence, use
[references/registration.md](registration.md). This document defines the
enablement request and acceptance facts; the registration guide explains where
to put a custom-role file, which native schema to call, and how to refresh the
host capability snapshot.

## Policy

`LUNA_MAX` capability is mandatory for a conforming Sol deployment. A task may
still select `SOL_XHIGH` for independent task-fit reasons, but the host must
not be accepted as a complete Sol runtime while the normal Luna lane is
absent. For a packet whose route is `LUNA_MAX`, absence of the capability is a
host configuration blocker, not permission to substitute another model.

The required binding is:

```text
Capability: LUNA_MAX_REQUIRED
Model/effort: gpt-5.6-luna / max
Fresh context: required
Controller history: excluded
Fallback: BLOCKED
```

Sol may request enablement and verify it. Sol must not claim enablement from a
worker self-report, a local role file, or a successful source/runtime sync.

Normal dispatch follows **Native-first -> Desktop-task**. First use a
native subagent surface visible in the current controller thread when its
declared schema, exact Luna/max pair, fresh/history semantics, and host evidence
pass preflight. `multi_agent_v1__spawn_agent` is canonical; a future equivalent
must be explicitly declared native and independently verifiable. If native
preflight fails, evaluate an explicitly approved `USER_VISIBLE_TASK` Desktop
route as priority 2. `UNSPECIFIED` authorization requires a fresh confirmation;
it is not `DENIED`. If Desktop is not eligible or fails, return `BLOCKED` and
do not change the model or start a hidden transport.

## Host enablement request

Send this compact request to the host capability owner or host control plane:

```text
Task ID: <stable id>
Capability requirement: LUNA_MAX_REQUIRED
Requested model/effort: gpt-5.6-luna / max
Allowed surface: NATIVE_GENERIC | CUSTOM_ROLE
Execution context: FRESH
Controller history: EXCLUDED
Required receipt: task-bound HOST_RECEIPT
Required identity evidence: HOST_OBSERVED_MODEL_EFFORT or authoritative role launch record
Fallback: BLOCKED
User-owned task: DENIED | ALLOWED | UNSPECIFIED
User approval: REQUIRED | GRANTED | NOT_REQUIRED | UNKNOWN
```

For `NATIVE_GENERIC`, first check whether the current controller thread already
exposes `multi_agent_v1__spawn_agent` with the exact Luna/max pair. If it does,
the caller uses that surface and records its declared fields; no
`collaboration.spawn_agent` registration is needed for that dispatch. If the
canonical wrapper is absent, the host must add the exact Luna/max pair to the
selected surface's advertised allowlist and document its declared request
fields. The adapter maps the normalized fresh-context requirement to that
schema, such as `fork_turns: none` when the surface explicitly declares that
field. For `CUSTOM_ROLE`, the host must expose an authoritative role and
launch mapping; a `.codex/agents/*.toml` file alone is not enablement.

The older `collaboration.spawn_agent` schema is not the canonical native v1
surface. It cannot borrow `multi_agent_v1__spawn_agent` fields, allowlists,
receipts, or evidence, and must pass preflight under its own declared contract.

## Required host response

The host must return these facts without asking a child to self-prove model
identity:

```text
Enablement status: ENABLED | NOT_ENABLED | UNKNOWN
Surface: NATIVE_GENERIC | CUSTOM_ROLE
Capability verdict: AVAILABLE | UNKNOWN | UNAVAILABLE
Advertised model/effort: <host fact>
Schema evidence: <host schema or capability reference>
Fresh-context proof: VERIFIED | UNVERIFIED | FAIL
Controller-history proof: EXCLUDED | UNKNOWN | FAIL
Dispatch receipt support: HOST_RECEIPT | UNKNOWN
Identity evidence support: HOST_OBSERVED_MODEL_EFFORT | ROLE_MAPPING_AND_LAUNCH_RECORD | UNKNOWN
Blocker: <None or concrete host reason>
```

`ENABLED` is accepted only when the exact model/effort pair, fresh/history
semantics, receipt support, and host-owned identity evidence are all present.
If the host advertises only other models, return:

```text
Enablement status: NOT_ENABLED
Capability verdict: UNAVAILABLE
Failure class: runtime / model_identity
Blocker: HOST_ENABLEMENT_REQUIRED
Dispatch: NOT_RUN
```

Do not retry the same spawn packet after `NOT_ENABLED`. Re-run capability
preflight only after the host supplies new enablement evidence. A new
user-owned task is not an enablement mechanism and must not be created to
obtain Luna.

This is a recoverable host block, not a caller-facing dead end. Return
`HOST_REMEDIATION_REQUIRED` with the exact registration/permission request,
approval status, external change evidence, and the next minimal read-only
probe. The caller should ask the user or host owner to approve the smallest
official registry, reload, or sandbox/token repair. After approval, use a new
task id, refresh the surface, and run the probe before attempting any
implementation. Do not issue broad ACL/full-control commands, retry an
unchanged packet, or treat approval alone as enablement.

If another thread on the same Desktop host exposes `multi_agent_v1__spawn_agent`
with Luna/max while the current thread exposes only the Sol/Terra
`collaboration.spawn_agent` schema, classify the current result as
`THREAD_SURFACE_NOT_VISIBLE`, evaluate the explicit Desktop-task gate, and
request surface migration/rebind or a fresh controller thread when no eligible
surface remains. Do not substitute another model.

## Configuration boundary

`config.toml` is a top-level Codex session configuration. Its `model` and
`model_reasoning_effort` settings can select the current controller's model and
effort when the host permits that model. It does not add a model to the
`multi_agent_v1__spawn_agent` or `collaboration.spawn_agent` host allowlist,
change either tool's schema, or create
a task-bound `HOST_RECEIPT` and host-observed identity evidence.

Do not change the Sol controller's `model` to `gpt-5.6-luna` as a way to enable
the worker: that changes the controller identity and still does not enable the
child surface. A separate top-level CLI session selected with Luna is also not
a native Sol worker and cannot satisfy this protocol's no-user-owned-task
boundary.

`agents/openai.yaml` is skill UI metadata, not a host model registration.
`.codex/agents/*.toml` can describe a custom role only when the selected host
explicitly loads and reports that role; it does not change the current
`NATIVE_GENERIC` allowlist. When `collaboration.spawn_agent` exposes only
`gpt-5.6-sol` and `gpt-5.6-terra`, the required change belongs to the host
capability registry or an explicitly supported custom/managed surface. No
local Sol config key is evidence of that host-side enablement.

## Explicit Desktop task alternative

Some Desktop hosts expose Luna through a visible app task even when the native
worker registry is missing. This is the conditional priority-2
`USER_VISIBLE_TASK` adapter described in [desktop-task-lane.md](desktop-task-lane.md),
not a registration mechanism. It may be used only when the plan explicitly sets
`User-owned task: ALLOWED` and the user grants approval. It must not be created
to convert `NOT_ENABLED` into `VERIFIED`, and it cannot satisfy a packet that
forbids user-owned tasks.

The route uses the host's `codex_app__create_thread` with
`model="gpt-5.6-luna"` and `thinking="max"`, then retains the ready
`threadId`/`hostId` receipt. Require host-observed effective model/effort and
fresh/history evidence; UI selection and worker self-report are advisory. This
route does not perform ACL/token remediation. A process-creation or
sandbox-permission failure remains an execution blocker.

If the host does not expose effective model/effort, classify the result as
`HOST_MODEL_UNOBSERVABLE`, not `HOST_MODEL_MISMATCH`. The caller may use an
explicit `OPERATOR_ATTESTED` gate only after the user confirms the live GUI for
the exact task/thread shows `gpt-5.6-luna / max`; record
`OPERATOR_UI_ATTESTED` and `Identity: ATTESTED`. This is not host enablement,
not `HOST_LAUNCH_RECORDED`, and not `HOST_VERIFIED`. For `HIGH` work, retain an
isolated worktree, no secrets/destructive/ACL/external side effects or
descendants, and Sol review before commit or merge.

After the native and explicitly approved Desktop routes fail, the only safe
action is a host-registration request. Preserve `gpt-5.6-luna / max`, include
the exact missing surface/schema and the smallest requested registry change,
then refresh the owning host and run a new task-bound handshake. Do not start
an undocumented local transport, change ACLs, or substitute another model.

## Acceptance gate

Luna enablement is complete only when:

1. The selected host surface advertises `gpt-5.6-luna / max`.
2. The surface declares the fresh-context and controller-history semantics.
3. A task-bound `HOST_RECEIPT` is supported.
4. The host can observe and return `gpt-5.6-luna` plus `max` independently of
   worker self-report, either as `HOST_OBSERVED_MODEL_EFFORT` or an
   authoritative app-server launch record.
5. The bounded identity handshake passes before implementation starts.
