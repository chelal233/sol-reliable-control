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
Surface: NATIVE_GENERIC | CUSTOM_ROLE | HOST_MANAGED | UNKNOWN
Schema fields: <exact host-declared fields>
Advertised models: <exact host list>
Advertised efforts: <exact host list or per-model matrix>
Candidate tools: <all visible worker tool names>
```

If `multi_agent_v1__spawn_agent` is visible and contains `gpt-5.6-luna / max`,
use the native call in Step 2A. If only a custom/managed role is visible, use
Step 3. If only `collaboration.spawn_agent` is visible and its pair is absent,
continue to Step 2B. If a sibling thread can see the native Luna surface but
this thread cannot, return `THREAD_SURFACE_NOT_VISIBLE` and request a fresh
controller thread or host surface migration/rebind; do not call the sibling's
agent id from this thread.

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

## Step 2C: register the Sol Luna MCP broker

Use this explicit `HOST_MANAGED` adapter when the current Desktop thread does
not expose a native worker surface. Install the skill first, then add the
server to the host's `config.toml`:

```toml
[mcp_servers.sol_luna_broker]
command = "pwsh"
args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:\\Users\\PC\\.codex\\skills\\sol-reliable-control\\scripts\\sol-luna-broker.ps1"]
enabled = true

[mcp_servers.sol_luna_broker.env]
SOL_LUNA_ALLOWED_ROOTS = "E:\\Sources\\.codex-worktrees;E:\\git\\sol-reliable-control-worktrees;E:\\git\\sol-reliable-control"
```

Set `SOL_LUNA_ALLOWED_ROOTS` in the server environment when the default roots
do not contain the target worktree. The broker's only tool is:

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
broker pins `gpt-5.6-luna / max`, starts a fresh ephemeral CLI process, and
returns a `BROKER_RUN_RECEIPT` containing the runtime version/hash and thread
id. This is a transport receipt, not a `HOST_RECEIPT`; worker self-report is
advisory. If host-observed model/effort is absent, record
`STARTED_UNVERIFIED` and keep `HOST_VERIFIED` closed for high-risk work.

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
permission to silently replace the native surface's identity evidence.

## Step 3: optional CLI custom-role registration

Use this path only when the host explicitly supports and reports a
`CUSTOM_ROLE` surface. The caller may place this file in the calling project:

```text
<caller-repository>/.codex/agents/luna-max-worker.toml
```

or in the global path only when that host/version documents global custom-role
discovery:

```text
C:/Users/PC/.codex/agents/luna-max-worker.toml
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

## Step 4: refresh and verify registration

After the host owner changes its registry, the caller must refresh the host
capability snapshot. The exact reload action is host-specific; use the
following sequence:

1. Restart or reload the process that owns the worker tool registry.
2. Re-enumerate all worker tools in the current controller thread; a full
   Desktop restart alone does not prove that the existing thread was rebound.
3. If the canonical wrapper is still absent, start a fresh controller thread
   on the host that exposes it or request explicit surface migration/rebind.
4. Read the selected surface metadata again and record the model/effort list.
5. Do not dispatch until `gpt-5.6-luna / max` is present on that surface.
6. Send the identity-only handshake and require the receipt/identity evidence
   before sending implementation instructions.

A successful top-level Luna session does not replace this refresh. Likewise,
the presence of a TOML role file does not replace host evidence.

Some clients expose Luna through an explicit user-visible app task instead of a
native worker surface. That route is separate, creates a user-owned task, and
is allowed only when the current plan explicitly permits it. It is not a way
to satisfy a `No user-owned task: true` packet or a substitute for native
subagent evidence.

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
