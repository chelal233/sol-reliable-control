# Sol Reliable Control Protocol

Use these compact packets only between the Sol controller and isolated execution lanes. Do not copy private reasoning or full transcripts. The generic `codex-skills` pack owns lifecycle routing, local verification, handoff formatting, and selective memory; this protocol owns Sol-specific orchestration only.

## Controller plan packet

```text
Task ID: <stable id>
Goal: <one sentence>
Done when: <observable acceptance conditions>
Lifecycle owner: generic codex-skills | None
Isolation: WORKTREE | CONTEXT_ONLY | DIRECT_OPT_OUT
Phase ID: <phase id or None>
Base ref: <commit or branch>
Branch: <codex branch or None>
Worktree: <absolute path or None>
Route: DIRECT | SOL_ONLY | LUNA_MAX | SOL_HIGH
Spawn surface: native generic worker | registered custom agent | compatibility | None
Requested model/effort: <for example gpt-5.6-luna / max or sol-high / xhigh>
Task risk: LOW | HIGH
Identity gate: HOST_DISPATCH | HOST_VERIFIED
Dependencies: <ordered prerequisites or None>
Write scope: <exact paths/globs owned by this task>
Do not touch: <paths or behavior excluded>
Expected result: <artifact or behavior>
Verification: <commands/checks>
Fallback: <one safe compatibility lane or BLOCKED>
Lane rationale: <task-fit reason; do not use model prestige as the reason>
Quality basis: <fresh evidence, prior accepted result, or None>
```

Do not dispatch a packet with a missing scope, ambiguous owner, missing verification, missing lifecycle owner, or missing isolation declaration.

## Controller states

```text
PLANNED -> BASELINE_VERIFIED -> WORKTREE_READY -> HANDSHAKE_PENDING
         -> EXECUTING -> COMMIT_PENDING -> REVIEW_PENDING
         -> ACCEPTED -> MERGED | PRESERVED | DISCARDED
Any state -> BLOCKED
```

`FAILED` means the lane ran but the result did not satisfy acceptance. `BLOCKED` means the lane could not be trusted or started. A failed handshake must never be represented as a worker result.

## Handshake packet

Ask the lane to return only:

```text
Task ID: <same id>
Phase ID: <same phase>
Agent: <configured name or UNKNOWN>
Host requested model: <canonical request or UNKNOWN>
Host observed model: <host observation or UNKNOWN>
Worker self-report model: <reported model or UNKNOWN>
Sandbox: <reported boundary or UNKNOWN>
Branch: <reported branch or None>
Worktree: <reported absolute path or None>
Worktree verified: PASS | FAIL | NOT_REQUIRED
Transport: PASS | FAIL
Dispatch receipt: <host receipt id/path or UNKNOWN>
Identity: VERIFIED | UNVERIFIED | FAIL
Self-report warning: NONE | MISMATCH | UNKNOWN
Routing verdict: HOST_VERIFIED | HOST_DISPATCHED_UNATTESTED | HOST_MODEL_MISMATCH | DISPATCH_UNCONFIRMED
Scope accepted: YES | NO
Blocker: <None or concrete reason>
```

`Host requested model`, `Host observed model`, and `Dispatch receipt` are host facts. `Worker self-report model` remains advisory. `Transport=PASS` is not sufficient for `Identity=VERIFIED`, and a model self-report mismatch is not a blocker when the declared identity gate is satisfied. Only fields defined here participate in routing; extra runtime/UI fields are advisory and cannot add a gate. Do not invent missing fields.

Use `Identity gate: HOST_DISPATCH` for low-risk bounded work and `HOST_VERIFIED` for high-risk work. With a valid dispatch receipt and no explicit host mismatch, unavailable host identity is `UNVERIFIED` and the low-risk route may continue as `HOST_DISPATCHED_UNATTESTED`. An explicit host mismatch or a missing receipt is `BLOCKED`; do not silently reroute.

Treat secrets, destructive or irreversible changes, security decisions, and shared-interface ownership as `HIGH`; other narrow, reversible, independently verifiable work may be `LOW`. The worker must never set `Identity=FAIL` from its own self-report alone.

After handshake, use this model decision order: valid receipt plus matching host observation => `HOST_VERIFIED`; valid receipt plus unavailable host observation under `HOST_DISPATCH` => `HOST_DISPATCHED_UNATTESTED`; a model self-report mismatch alone => continue with `Self-report warning: MISMATCH`; explicit host mismatch or no receipt => `BLOCKED`.

## Native worker launch

Prefer the host's native generic worker spawn over a registered custom lane type:

```text
agent role: generic worker
route: LUNA_MAX | SOL_HIGH
requested model/effort: <from plan packet>
fork controller history: false
prompt: the bounded controller plan packet plus the leaf-worker rules
```

`luna-max` and `sol-high` describe logical execution roles and packet contracts; neither is a prerequisite runtime agent registration. Use the host's canonical model/effort for the selected route. The `sol-high` route must request `xhigh` reasoning; if xhigh is unavailable, classify the failure as `runtime` or `model_identity` and do not silently downgrade the request. If the native spawn surface rejects the requested model, reports the lane unavailable, or the host explicitly observes a different model, classify the failure as `runtime` or `model_identity`; do not retry the identical custom type. If dispatch is accepted but runtime identity is unavailable, apply the declared identity gate and record `HOST_DISPATCHED_UNATTESTED` for an allowed low-risk task.

Use the same native pattern for sol-high when the selected lane is justified by task fit. Do not claim either lane is higher quality without acceptance evidence.

## Lane selection

Do not encode a fixed quality ranking such as `sol-high > luna-max`. Treat the model name, cost, and reasoning setting as runtime facts, not quality evidence.

- Select luna-max by default for bounded work and for difficult tasks whose scope remains narrow and independently verifiable.
- Select sol-high with xhigh reasoning for difficult tasks that need deeper reasoning, cross-cutting planning, arbitration, or review.
- Do not switch lanes merely after a failure. Identify the failure class first; use sol-high with xhigh only when task fit or acceptance requires stronger Sol reasoning.
- If the lane has no trustworthy quality evidence and the task is high-risk, split the task smaller, run a read-only calibration, or return `BLOCKED`.
- Once a lane has written files, keep ownership with that lane for the one allowed focused correction; do not overwrite it with a presumed higher-quality lane.

## Worker result packet

```text
Task ID: <stable id>
Status: PASS | PASS_WITH_WARNING | BLOCKED
Summary: <what happened>
Changed: <exact files, or None>
Commit: <phase commit or None>
Verification: <commands, exit status, concise result>
Routing verdict: HOST_VERIFIED | HOST_DISPATCHED_UNATTESTED | HOST_MODEL_MISMATCH | DISPATCH_UNCONFIRMED
Self-report warning: NONE | MISMATCH | UNKNOWN
Evidence: <diff/test/build/log/artifact path bound to final candidate>
Diff reviewed: PASS | FAIL | NOT_RUN
Worktree disposition: MERGED_AND_REMOVED | PRESERVED | EXPLICIT_DISCARD | NONE
Failure class: git_unavailable | worktree | commit | merge | runtime | model_identity | permission | dependency | scope | verification | conflict | none
Blocker: <None or concrete blocker>
```

`PASS` and `PASS_WITH_WARNING` require `Changed`, `Verification`, and `Evidence`; use `PASS_WITH_WARNING` only when the host dispatch satisfies the declared identity gate and the warning is limited to a model self-report mismatch. A worker may approve only its own packet, never the overall task.

## Focused correction packet

```text
Task ID: <same id>
Original owner: <same owner>
Original scope: <same scope>
Failure class: <one class>
Delta: <one precise correction>
Verification: <same or narrower checks>
Do not broaden scope: true
```

Send at most one correction. If it fails, conflicts, broadens scope, or has no new evidence, return `BLOCKED`.

## Controller audit sequence

```text
baseline -> plan packet -> handshake -> bounded execution
        -> result packet -> real diff/scope check
        -> final verification check -> PASS | one FIX | BLOCKED
```

When host dispatch or a required host attestation fails, keep the plan and owner unchanged. Do not retry the identical packet. If only the model self-report conflicts with host facts, keep the owner and continue when the declared identity gate passes; record `Self-report warning: MISMATCH`.

## Evidence compression

Return only:

- changed paths;
- relevant diff summary or diff artifact path;
- command and exit status;
- failing or passing assertion lines;
- final artifact/log path;
- residual risk or blocker.

Keep large logs outside the controller conversation. The controller may read a narrow slice when a decision requires it.
