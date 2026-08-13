# LUNA_MAX Host Enablement Contract

This package can require and verify a host capability; it cannot change the
host's model allowlist from a skill file. Source/runtime synchronization is not
host enablement. The host owner or host capability layer must perform the
enablement, then return evidence that Sol can verify.

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

## Host enablement request

Send this compact request to the host capability owner or host control plane:

```text
Task ID: <stable id>
Capability requirement: LUNA_MAX_REQUIRED
Requested model/effort: gpt-5.6-luna / max
Allowed surface: NATIVE_GENERIC | CUSTOM_ROLE | HOST_MANAGED
Execution context: FRESH
Controller history: EXCLUDED
Required receipt: task-bound HOST_RECEIPT
Required identity evidence: HOST_OBSERVED_MODEL_EFFORT or authoritative role launch record
Fallback: BLOCKED
No user-owned task: true
```

For `NATIVE_GENERIC`, the host must add the exact Luna/max pair to the
surface's advertised allowlist and document its declared request fields. The
adapter maps the normalized fresh-context requirement to that schema, such as
`fork_turns: none` when the surface explicitly declares that field. For
`CUSTOM_ROLE` or `HOST_MANAGED`, the host must expose an authoritative role or
launch mapping; a `.codex/agents/*.toml` file alone is not enablement.

## Required host response

The host must return these facts without asking a child to self-prove model
identity:

```text
Enablement status: ENABLED | NOT_ENABLED | UNKNOWN
Surface: NATIVE_GENERIC | CUSTOM_ROLE | HOST_MANAGED
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

## Acceptance gate

Luna enablement is complete only when:

1. The selected host surface advertises `gpt-5.6-luna / max`.
2. The surface declares the fresh-context and controller-history semantics.
3. A task-bound `HOST_RECEIPT` is supported.
4. The host can observe and return `gpt-5.6-luna` plus `max` independently of
   worker self-report.
5. The bounded identity handshake passes before implementation starts.
