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
Surface: AUTO | NATIVE_GENERIC | CUSTOM_ROLE | HOST_MANAGED
Capability preflight: REQUIRED
Task risk: LOW | HIGH
Identity gate: HOST_DISPATCH | HOST_VERIFIED
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
Surface: NATIVE_GENERIC | CUSTOM_ROLE | HOST_MANAGED | UNKNOWN
Capability verdict: AVAILABLE | UNKNOWN | UNAVAILABLE
Capability evidence: <host metadata or receipt reference>
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
Identity proof kind: HOST_OBSERVED_MODEL_EFFORT | ROLE_MAPPING_AND_LAUNCH_RECORD | SELF_REPORT_ONLY | UNKNOWN
Identity: VERIFIED | UNVERIFIED | FAIL
Self-report warning: NONE | MISMATCH | UNKNOWN
Scope accepted: YES | NO
Blocker: <None or concrete reason>
```

`Host requested model`, `Host observed model`, `Requested effort`, `Observed effort`, and `Dispatch receipt` are host facts. Worker self-report fields are advisory. Transport success is not identity proof. An `AGENT_HANDLE` is not a `HOST_RECEIPT` unless the host contract says it is task-bound. Extra runtime or UI fields are advisory and cannot add a gate.

For `Identity gate: HOST_DISPATCH`, a valid `HOST_RECEIPT` with no explicit host mismatch may continue as `HOST_DISPATCHED_UNATTESTED`. For `HOST_VERIFIED`, host-observed model/effort or an authoritative custom-role launch record must match the request; unavailable proof is `BLOCKED`. An explicit host mismatch or missing receipt is always `BLOCKED`; do not silently reroute.

The complete adapter contract and normalized field mapping are in
[references/runtime-adapters.md](runtime-adapters.md).

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

For the current `multi_agent_v1__spawn_agent` schema, the concrete normalized
call is:

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

`LUNA_MAX` and `SOL_XHIGH` are logical lane labels, not required custom
registrations. `SOL_XHIGH` requests `gpt-5.6-sol / xhigh`. If the host rejects
the requested lane/model/effort, reports it unavailable, or observes a
different model, classify the failure as `runtime` or `model_identity`. Do not
retry the identical unavailable packet.

The native surface's advertised model list is capability evidence only. It
does not replace the task-bound receipt and host-observed identity required by
the selected identity gate.

## Custom-role and host-managed dispatch

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
role file, agent name, or self-report alone is not evidence. `HOST_MANAGED`
dispatch follows the same receipt and proof requirements without creating a
new user-owned task.

## Lane selection

- Select `luna-max` by default for bounded work and difficult work whose scope remains narrow and independently verifiable.
- Select `sol-xhigh` for difficult reasoning, cross-cutting planning, arbitration, or final review; request `xhigh` effort.
- Do not escalate merely after a failure; identify the failure class and task-fit reason first.
- `SOL_XHIGH` is a normal replan, not an implicit fallback. Use it only when task fit or the repeated-failure escalation gate independently selects it.
- If the same issue has been rejected more than twice under `luna-max`, or unclear business semantics repeatedly cause regressions, stop retrying `luna-max` and route the issue to `sol-xhigh` with the failure evidence.
- `FALLBACK` is an explicit recovery route. It may name any safe compatible lane, but it is not a normal route and must be labeled `UNVERIFIED`.
- Fallback is limited to low-risk, narrow, independently verifiable work. High-risk work returns `BLOCKED` when the requested lane cannot be verified.

Do not encode a fixed quality ranking. Model names, cost, and effort settings are runtime facts; acceptance evidence is the quality basis.

## Worker result packet

```text
Task ID: <stable id>
Status: PASS | PASS_WITH_WARNING | BLOCKED
Summary: <what happened>
Changed or produced: <exact paths, artifacts, or None>
Verification: <checks, exit status, concise result>
Routing verdict: HOST_VERIFIED | HOST_DISPATCHED_UNATTESTED | HOST_MODEL_MISMATCH | DISPATCH_UNCONFIRMED
Self-report warning: NONE | MISMATCH | UNKNOWN
Evidence: <artifact or result path bound to the acceptance conditions>
Review verdict: PASS | FIX | BLOCKED | NOT_RUN
Failure class: runtime | model_identity | permission | dependency | scope | verification | conflict | none
Blocker: <None or concrete reason>
```

`PASS` requires `Changed or produced`, `Verification`, and `Evidence`. Use `PASS_WITH_WARNING` only when the host gate passed and the warning is limited to an advisory self-report mismatch. A worker may approve only its own result; Sol decides the overall task.

## Fallback and failure rules

When the requested lane cannot start, preserve the original plan and owner. Do not silently replace it. If the plan explicitly permits `FALLBACK`, select one compatible lane, record `Identity: UNVERIFIED`, and continue only when the risk and scope rules allow it. Otherwise return `BLOCKED` with the failure class and the missing host fact.

If a surface does not expose `gpt-5.6-luna`, do not automatically turn the
request into `SOL_XHIGH`: replan to `SOL_XHIGH` only when its normal task-fit or
escalation rule applies. Otherwise return `BLOCKED` with the original
`LUNA_MAX` request, the rejected surface, and the missing capability evidence.
