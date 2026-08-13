# LUNA_MAX Registration and Unblock Guide

Use this guide when a caller has a valid `LUNA_MAX` plan but the selected host
surface rejects `gpt-5.6-luna / max` before a worker is created. It separates
what the caller can configure locally from what only the host capability owner
can register.

## The three registration layers

| Layer | What it controls | Can it register Luna for `collaboration.spawn_agent`? |
| --- | --- | --- |
| `config.toml` | The top-level Codex session's model and effort | No |
| `.codex/agents/*.toml` | A CLI/custom-role description, if the host loads custom roles | Only on a verified `CUSTOM_ROLE` surface |
| Host capability registry | Native worker model allowlist, schema, receipt, and identity telemetry | Yes; this is the required path for `NATIVE_GENERIC` |

`gpt-5.6-luna` is a real model and supports `max` reasoning. A host rejection
means that the selected worker surface has not registered the model, not that
the model name is invalid. The model and reasoning support are documented by
the official model catalog; the registration and receipt requirements below
are Sol's host contract.

Official references: [GPT-5.6 Luna model reference](https://developers.openai.com/api/docs/models/gpt-5.6-luna)
and [GPT-5.6 model guidance](https://developers.openai.com/api/docs/guides/latest-model).

## Step 1: classify the current surface

Read the capability metadata from the same host and controller thread that will
launch the worker. Do not reuse a model list from another thread, CLI session,
or parent host. Enumerate all callable worker tools before classifying the host
as globally unavailable.

```text
Surface: NATIVE_GENERIC | CUSTOM_ROLE | HOST_MANAGED | USER_VISIBLE_TASK | UNKNOWN
Schema fields: <exact host-declared fields>
Advertised models: <exact host list>
Advertised efforts: <exact host list or per-model matrix>
Candidate tools: <all visible worker tool names>
```

If `multi_agent_v1__spawn_agent` is visible and contains `gpt-5.6-luna / max`,
use the native call in Step 2A. A future native equivalent is eligible only
when the current thread exposes an explicit, verifiable native contract. If
only `collaboration.spawn_agent` is visible, inspect it independently in Step
2B; the older schema must not masquerade as canonical native v1. If its schema
or Luna/max matrix does not match, or native preflight cannot obtain the
required host evidence, record that failure and proceed to the priority-2 MCP
path below. Consider the conditional Desktop task path only as priority 3
after MCP is unavailable or fails and user-owned-task approval is present. If a
sibling thread can see the native Luna surface but this thread cannot, record
`THREAD_SURFACE_NOT_VISIBLE`; surface migration/rebind is required only if MCP
is also unavailable and the Desktop route is not eligible. Never call the
sibling's agent id from this thread.

## Step 2A: use the canonical native wrapper

When the current thread exposes the following tool, no model registration is
needed in `config.toml`:

```text
multi_agent_v1__spawn_agent({
  fork_context: false,
  model: "gpt-5.6-luna",
  reasoning_effort: "max",
  message: <identity-only handshake or bounded packet>
})
```

Run the identity-only handshake first. The returned `agent_id` is an
`AGENT_HANDLE` unless the host explicitly labels it a task-bound receipt. Keep
the high-risk gate closed until host-owned model/effort evidence is returned.

## Step 2B: register the alternate generic surface

For the `collaboration.spawn_agent` family, the host owner must add
the exact model/effort pair to the host-owned capability registry:

```text
Surface: NATIVE_GENERIC
Tool: collaboration.spawn_agent
Required model: gpt-5.6-luna
Required reasoning effort: max
Fresh-context field: fork_turns = "none"  # only if the schema declares it
No controller history: true
Task-bound receipt: required
Host-observed identity: gpt-5.6-luna / max
```

The host must preserve the schema's actual field names. A host whose declared
fields are `task_name`, `fork_turns`, `model`, `reasoning_effort`, and `message`
must accept this normalized request:

```text
collaboration.spawn_agent({
  task_name: <stable task id or host task name>,
  fork_turns: "none",
  model: "gpt-5.6-luna",
  reasoning_effort: "max",
  message: <bounded Sol packet>
})
```

If a different host schema declares `fork_context` instead, use
`fork_context: false`; do not send both fields unless the schema explicitly
declares both. `fork_turns = "none"` and `fork_context = false` are adapter
spellings of the same normalized requirement: fresh context with controller
history excluded.

This legacy schema cannot impersonate `multi_agent_v1__spawn_agent`, inherit
its allowlist, or turn an `agent_id` into native-v1 evidence. It qualifies only
when its own host declaration, exact Luna/max support, receipt, and identity
evidence satisfy preflight.

For a host that exposes the `multi_agent_v1__spawn_agent` wrapper, the declared
native variant may be:

```text
multi_agent_v1__spawn_agent({
  fork_context: false,
  model: "gpt-5.6-luna",
  reasoning_effort: "max",
  message: <identity-only handshake or bounded packet>
})
```

This variant may return an `agent_id`. Treat that value as `AGENT_HANDLE` unless
the host contract explicitly labels it a task-bound `HOST_RECEIPT`. A successful
safe probe plus a worker self-report proves that a worker started, but it does
not prove `HOST_VERIFIED` for a high-risk task. The caller must record the
distinction and require independent host-observed model/effort evidence before
implementation.

The host registration is not complete until it also supports a task-bound
`HOST_RECEIPT`. The receipt or authoritative host launch record must bind the
task, surface, requested model/effort, fresh-context setting, controller
history exclusion, and host-observed model/effort. An advertised allowlist or
returned `agent_id` alone is not enough.

Do not infer from this alternate schema that the host has no Luna capability
when `multi_agent_v1__spawn_agent` is visible on the same Desktop host. Schema
visibility is thread-bound and must be recorded in the capability snapshot.

## Priority 3 adapter: explicit Desktop Luna task lane

This section is intentionally shown before the broker details because it
documents the separate host-owned API. Policy order is still Native → MCP
(priority 2) → Desktop (priority 3); do not invoke this section before the MCP
preflight unless the caller has selected the explicit override.

Some clients expose Luna through a user-visible app task rather than a native
worker surface. The [desktop task lane](desktop-task-lane.md) is the conditional priority-3
route when the caller explicitly accepts a visible user-owned task and forbids
Sol from touching Windows ACLs or starting a local broker. It is not an
enablement registration step. The plan must contain:

```text
Surface: USER_VISIBLE_TASK
Dispatch priority: NATIVE_FIRST_THEN_MCP_THEN_DESKTOP
User-owned task: ALLOWED
User approval: GRANTED
Requested model/effort: gpt-5.6-luna / max
Execution context: FRESH
Controller history: EXCLUDED
```

Use the host-owned Codex app tools, not PowerShell or the Sol broker:

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

Keep the returned `threadId` and `hostId` together. Wait and read only that
task; use a follow-up message only after the handshake is accepted and the user
has approved implementation. A ready receipt proves transport, not identity.
Require host-observed effective Luna/max and fresh/history evidence before
`HOST_VERIFIED`. A pending `clientThreadId`, UI model selection, or worker
self-report is insufficient. If the task reports `PROCESS_CREATION_DENIED` or
`WINDOWS_SANDBOX_ACL_FAILED`, stop with an execution blocker; do not request
or perform broad ACL/token changes.

## Priority 2 adapter: register the Sol Luna MCP broker

Use this explicit priority-2 `HOST_MANAGED` adapter when the current Desktop
thread does not expose a qualifying native worker surface, the native schema/model
mismatches Luna/max, or native preflight cannot obtain the required host evidence.
Install the
skill first, then add the server to the host's
`config.toml`:

```toml
[mcp_servers.sol_luna_broker]
command = "<trusted-pwsh-path>"
args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "<CODEX_HOME>\\skills\\sol-reliable-control\\scripts\\sol-luna-broker.ps1"]
enabled = true

[mcp_servers.sol_luna_broker.env]
SOL_LUNA_ALLOWED_ROOTS = "<approved-phase-worktree>"
SOL_LUNA_RUNTIME_PATH = "<trusted-codex-executable>"
SOL_LUNA_RUNTIME_SHA256 = "<64-hex-approved-sha256>"
```

Replace every angle-bracket placeholder with an approved path before saving.
There are no implicit filesystem roots and no machine-specific paths in this
repository. Set `SOL_LUNA_ALLOWED_ROOTS` in the server environment when the
configured roots do not contain the target worktree. Broker responses redact
user-home paths, host names, and credential-shaped values before crossing the
MCP boundary. The broker's only tool is:

```text
sol_luna_exec({
  task_id: <stable id>,
  workdir: <approved worktree>,
  prompt: <bounded Sol packet>,
  sandbox: "read-only" | "workspace-write",
  handshake_only: true | false
})
```

The first call must use `handshake_only=true` and `sandbox="read-only"`. The
default broker pins `gpt-5.6-luna / max`, starts a fresh ephemeral app-server
thread, and returns a `HOST_LAUNCH_RECORD` containing the runtime version/hash,
task-bound thread id, and host model/effort. Record `HOST_LAUNCH_RECORDED`
before the turn check; if the same turn has no `model/rerouted` event, the
result can be `HOST_VERIFIED` with `ROLE_MAPPING_AND_LAUNCH_RECORD`. Worker
self-report remains advisory. Set `SOL_LUNA_TRANSPORT=cli` only for legacy
diagnostics; it returns a `BROKER_RUN_RECEIPT` and remains
`STARTED_UNVERIFIED`.

For a host-managed app-server retest, capture the fresh ephemeral
`thread/start` response instead of relying on the worker's self-report. The
response is usable as `HOST_LAUNCH_RECORDED` only when its task-bound thread id
reports exact `gpt-5.6-luna` and `max`. Continue the same turn and reject the
record if a `model/rerouted` notification appears. A launch assignment is not
the same as effective turn identity; keep the high-risk gate closed until this
check completes.

The broker contract can be checked without launching a worker:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File `
  "$CODEX_HOME/skills/sol-reliable-control/tests/broker-contract.ps1"
```

This route is an operational Luna path, not a new user-owned Codex task and not
permission to silently replace the native surface's identity evidence. Do not register the broker as a native surface: it remains `HOST_MANAGED`, does
not change the requested model, and cannot turn worker self-report into
`HOST_VERIFIED`.

For a bounded implementation packet that may exceed the caller's MCP deadline,
keep the identity handshake synchronous, then set `execution_mode="async"` on
the implementation call. The broker returns a task-bound `HOST_JOB_RECEIPT`
and `job_id` immediately; poll it with the second tool:

```text
sol_luna_poll({
  task_id: <same stable id>,
  job_id: <returned 32-character id>,
  wait_seconds: 0..30
})
```

The poll result is `PENDING`, `COMPLETED`, or `FAILED`. On `COMPLETED`, inspect
the nested `result.structuredContent` and require its app-server
`HOST_LAUNCH_RECORD`/`HOST_VERIFIED` evidence before accepting the worker
result. A submission deadline or a `PENDING` poll is not a worker failure;
do not resubmit the same packet.

## Step 3: optional CLI custom-role registration

Use this path only when the host explicitly supports and reports a
`CUSTOM_ROLE` surface. The caller may place this file in the calling project:

```text
<caller-repository>/.codex/agents/luna-max-worker.toml
```

or in the global path only when that host/version documents global custom-role
discovery:

```text
<CODEX_HOME>/agents/luna-max-worker.toml
```

File contents:

```toml
name = "luna-max-worker"
model = "gpt-5.6-luna"
model_reasoning_effort = "max"
sandbox_mode = "workspace-write"
```

This file is a role request, not proof that the host registered the role. Do
not put it in the Sol source repository or runtime skill copy as a substitute
for host registration. The host must report all of the following before the
caller may use the role:

```text
Surface: CUSTOM_ROLE
agent_type: luna-max-worker
fork_turns: none
model: gpt-5.6-luna
reasoning_effort: max
Task-bound HOST_RECEIPT: present
Authoritative role launch record: present
```

If the host says `agent type is currently not available`, the role is not
registered on that host. Do not retry the same packet through the generic
surface and do not replace the role with Terra or Sol.

## Bounded recovery and permission request

`BLOCKED` is the result for the current implementation packet, not a reason
to stop helping the caller. When a real host action can change the state, use
this bounded sequence and report each transition:

| Attempt | Caller action | Required evidence | If it fails |
| --- | --- | --- | --- |
| 1 | Native handshake-only probe on the current thread | native schema, fresh receipt, Luna/max host identity | record native failure and continue to MCP |
| 2 | MCP `sol_luna_exec(handshake_only=true)` | host launch record and execution status | evaluate the explicitly approved Desktop task gate |
| 3 | Approved Desktop task handshake through `codex_app__create_thread` | ready task receipt, fresh/history facts, host launch evidence | issue host remediation request |
| 4 | User/host owner approves the smallest official registry or sandbox repair, then reload/restart | approval plus setup/reload record | remain `HOST_REMEDIATION_REQUIRED` |
| 5 | New minimal read-only PowerShell probe | `PROCESS_START=YES`, `EXECUTION=COMPLETED` | remain `BLOCKED`; do not send implementation |

Use a new task id for every probe after an external state change. Do not repeat
the same implementation packet, guess an ACL command, or silently widen the
sandbox. The permission request must identify the exact host component and
scope, for example:

```text
Status: HOST_REMEDIATION_REQUIRED
Task ID: <probe task id>
Failure code: PROCESS_CREATION_DENIED | WINDOWS_SANDBOX_ACL_FAILED | model/role mismatch
Observed: <one redacted host error and receipt>
Requested action: <refresh native role allowlist, reload worker registry, or repair the official sandbox helper/token>
Scope: approved Codex runtime and declared worktree only; no broad user-root/full-control ACL
Approval: REQUIRED
After approval: restart/rebind the owning host, then run a minimal read-only PowerShell probe
Acceptance: PROCESS_START=YES; EXECUTION=COMPLETED; fresh Luna/max handshake still matches
```

The caller should present this packet to the user or host/capability owner and
ask for explicit approval before any administrative, ACL, token, or registry
change. Sol may perform the new read-only probe after approval, but must not
claim success from approval alone. If the host refuses or the probe remains
denied, return both the implementation verdict `BLOCKED` and the next safe
action rather than retrying indefinitely.

## Step 4: refresh and verify registration

After the host owner changes its registry, the caller must refresh the host
capability snapshot. The exact reload action is host-specific; use the
following sequence:

1. Restart or reload the process that owns the worker tool registry.
2. Re-enumerate all worker tools in the current controller thread; a full
   Desktop restart alone does not prove that the existing thread was rebound.
3. If the canonical wrapper is still absent, record the native failure and use
    the priority-2 broker when it passes preflight; otherwise start a fresh
   controller thread or request explicit surface migration/rebind.
4. Read the selected surface metadata again and record the model/effort list.
5. Do not dispatch until `gpt-5.6-luna / max` is present on that surface.
6. Send the identity-only handshake and require the receipt/identity evidence
   before sending implementation instructions.

A successful top-level Luna session does not replace this refresh. Likewise,
the presence of a TOML role file does not replace host evidence.

## Step 5: execute the caller's bounded packet

Only after registration is verified, use the exact schema-specific call:

```text
Route: LUNA_MAX
Requested model/effort: gpt-5.6-luna / max
Execution context: FRESH
Controller history: EXCLUDED
Identity gate: HOST_VERIFIED
Fallback: BLOCKED
```

For the canonical native schema:

```text
multi_agent_v1__spawn_agent({
  fork_context: false,
  model: "gpt-5.6-luna",
  reasoning_effort: "max",
  message: <compact plan packet plus handshake/result rules>
})
```

For the alternate schema, only when its own model matrix contains Luna:

```text
collaboration.spawn_agent({
  task_name: <stable task id>,
  fork_turns: "none",
  model: "gpt-5.6-luna",
  reasoning_effort: "max",
  message: <compact plan packet plus handshake/result rules>
})
```

The first response must be treated as a handshake, not implementation. The
caller records:

```text
Capability verdict: AVAILABLE
Dispatch receipt kind: HOST_RECEIPT
Fresh-context proof: VERIFIED
Controller-history proof: EXCLUDED
Host-observed model: gpt-5.6-luna
Observed effort: max
Identity proof kind: HOST_OBSERVED_MODEL_EFFORT | ROLE_MAPPING_AND_LAUNCH_RECORD
Identity: VERIFIED
```

Only then may the bounded task packet authorize implementation.

## `config.toml` boundary and safe smoke test

`config.toml` can select the top-level session model:

```toml
model = "gpt-5.6-luna"
model_reasoning_effort = "max"
```

That changes the controller session. It does not add Luna to the native worker
allowlist, modify `collaboration.spawn_agent`, create a task-bound receipt, or
prove child identity. Do not change the Sol controller to Luna to unblock a
child; that silently changes the controller identity.

If the host policy allows a disposable top-level smoke test, this only tests
whether the current CLI session can request the model; it is not a worker
registration test and must not be used as `HOST_VERIFIED` evidence:

```powershell
codex exec -c 'model="gpt-5.6-luna"' -c 'model_reasoning_effort="max"' --ephemeral "Return SMOKE_OK only. Do not edit files."
```

## Recovery packet when registration is still missing

Return this packet to the host/capability owner; do not leave the caller with
an unclassified generic block:

```text
Status: HOST_REGISTRATION_REQUIRED
Capability: LUNA_MAX_REQUIRED
Surface: <surface>
Tool/schema: <tool and exact fields>
Requested model/effort: gpt-5.6-luna / max
Required context: FRESH; controller history EXCLUDED
Required evidence: task-bound HOST_RECEIPT + host-observed model/effort
Current advertised models: <host list>
Dispatch: NOT_RUN
Fallback: BLOCKED
Next action: host owner registers the pair, reloads the surface, and returns a new capability snapshot
```

If the host still advertises only `gpt-5.6-sol` and `gpt-5.6-terra`, the
correct status remains `HOST_ENABLEMENT_REQUIRED`; the caller must not create a
user-owned task, silently change the controller model, retry an identical
packet, or claim that a local config file registered Luna.
