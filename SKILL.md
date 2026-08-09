---
name: sol-reliable-control
description: Use when the user explicitly invokes $sol-reliable-control or asks for a token-conscious, reliable multi-agent workflow with a clean Sol controller, isolated luna-max/sol-high execution with xhigh reasoning for Sol, final evidence review, and safe handling of worker handshake failures. This is a specialized controller skill, not the generic Codex lifecycle pack.
---

# Sol Reliable Control

## Role

Act as one clean Sol controller and final reviewer. Keep planning, routing, and audit reasoning separate from implementation contexts. Treat luna-max and sol-high with xhigh reasoning as replaceable execution lanes, never as controllers.

This skill is the inner controller layer. The generic `codex-skills` pack remains responsible for lifecycle routing, worktree/branch isolation, bounded I/O, local verification, handoff formatting, and selective project memory. Do not copy generic lifecycle rules here, and do not put luna-max/sol-high behavior into the generic pack.

Use this skill only for work large enough to justify delegation. Keep small, clear, single-file work Direct and do not load this skill into that work.

## Non-negotiable separation

- Do not implement, debug, or run exploratory commands in the controller context.
- Do not paste worker transcripts, large logs, or broad source dumps into the controller context.
- Do not let a worker approve the overall task.
- Do not let a handshake failure cause the controller to take over implementation.
- Keep one owner per file and one exact `write_scope` per task.
- Pass compact packets and artifact paths; pass only the evidence needed for the next decision.

## Route selection

Choose the cheapest safe route:

- `Direct`: Use only when the task is small enough that no controller/executor split is needed. Do not use this Skill for it.
- `Sol-only`: Plan, inspect, or review without changing files. Keep the controller read-only.
- `Sol -> luna-max`: Use as the default for clear, bounded, independently verifiable work and for difficult tasks whose scope remains narrow. Prefer this route for token savings while retaining maximum Luna reasoning.
- `Sol -> sol-high`: Use for difficult tasks that need deeper Sol reasoning, cross-cutting planning, arbitration, or review than a bounded luna-max task. Request xhigh reasoning and keep the exact scope and evidence contract.
- `luna-max -> sol-high`: Escalate only when task fit or acceptance requires stronger Sol reasoning; never escalate merely because the first lane failed or another name sounds stronger.
- Judge all execution lanes by acceptance results, regression evidence, and review history—not by model name, price, or reasoning label.
- Start luna-max through the host's native generic worker spawn when available: request `gpt-5.6-luna` with `max` reasoning and start without forked controller history. Do not require a registered `luna-max-worker` or `luna-worker` agent type.
- Start sol-high through the host's native generic worker spawn when available; request xhigh reasoning, and treat `sol-high` as a logical lane label, not a required registered agent type. If xhigh is unavailable, report the runtime/model mismatch instead of silently downgrading the lane.
- Treat `luna-worker` as a logical role and packet contract, not as a runtime registration. A missing custom agent type is not fixed by retrying the same type.
- For every write route, use the generic `worktree-flow` by default; use context-only isolation for read-only work. A direct main-worktree write requires an explicit user opt-out.
- Parallelize only tasks whose file scopes, dependencies, and validation surfaces do not overlap.

Never choose a worker because a fixed worker count is available. Choose the minimum number of lanes that preserves ownership and evidence quality.

## Controller state machine

Use these states and transitions for every delegated task:

```text
PLANNED
  -> BASELINE_VERIFIED
  -> WORKTREE_READY
  -> HANDSHAKE_PENDING
  -> EXECUTING                 (host dispatch + transport + scope pass)
  -> COMMIT_PENDING
  -> REVIEW_PENDING            (committed diff received)
  -> ACCEPTED -> MERGED | PRESERVED | DISCARDED
  -> FAILED -> PRESERVED | DISCARDED
Any state -> BLOCKED -> PRESERVED | DISCARDED
```

- `transport=PASS` alone never advances past `HANDSHAKE_PENDING`.
- A write task cannot advance past `BASELINE_VERIFIED` without a verified worktree and branch, unless the user explicitly opted out.
- `model_identity` or `runtime` failure goes to `BLOCKED` only for a host dispatch failure, an explicit host-observed model mismatch, or an unavailable required attestation gate. A worker's generic or self-reported model never blocks by itself.
- A low-risk, bounded task may execute with `Identity: UNVERIFIED` when the host accepted the requested lane, returned a task-bound dispatch receipt, and the packet uses `Identity gate: HOST_DISPATCH`. A high-risk task must use `Identity gate: HOST_VERIFIED` and stop when host observation is unavailable.
- A non-Git repository goes to `BLOCKED` with `Failure class: git_unavailable`; do not silently write in the main directory.
- `COMMIT_PENDING` requires the worker to commit only its declared scope before controller review.
- `verification` failure may enter one focused correction, then returns to `REVIEW_PENDING`.
- The controller never moves to `EXECUTING` without a declared owner, write scope, verification command, worktree handshake, host dispatch receipt, and applicable identity gate.

## Controller workflow

1. Read the task, repository instructions, and acceptance boundary. If the repository exposes codebase-memory tools, use graph discovery before text search; otherwise use the narrowest available read-only inspection. Leave generic lifecycle routing to the active `codex-skills` layer.
2. Define `goal`, observable `done_when`, exclusions, dependencies, task risk, identity gate, exact write scopes, owners, verification commands, and isolation mode.
3. Capture the baseline branch, `HEAD`, and changed-file state before dispatch. Do not modify files.
4. For a write route, invoke generic `worktree-flow` to create and verify the phase branch/worktree before worker dispatch. For read-only work, record context-only isolation.
5. Send each worker a bounded handshake packet containing the exact worktree path, branch, scope, and verification. Require worktree, host dispatch, applicable identity, and scope handshakes before granting execution or a write task.
6. Select the lane from task fit and available evidence. Start luna-max for bounded or difficult-but-narrow work, and sol-high with xhigh reasoning for difficult cross-cutting reasoning, planning, arbitration, or review; use native generic worker spawning and never prestige-based promotion.
7. Receive only the structured result packet, phase commit, compact verification output, and diff location. Do not import the worker's full reasoning.
8. Review the real final candidate: changed paths, scope ownership, committed diff, tests/builds, and evidence freshness.
9. Allow at most one focused correction to the original owner and original scope. Re-review the final candidate after correction.
10. Return `PASS`, `FIX`, or `BLOCKED`; only after `PASS` may the generic flow merge the phase. The controller alone decides the overall result.

Use the exact packet schemas in [references/protocol.md](references/protocol.md).

## Handshake and fallback

Treat these as separate facts:

- `transport_verified`: the dispatch mechanism delivered a response.
- `host_dispatch_verified`: the host accepted the requested role/model and returned a receipt bound to the task and phase.
- `identity_verified`: the host observed the requested agent/model/reasoning/sandbox and matched it to the dispatch request, when the host exposes those facts.
- `self_report_consistent`: the worker's model claim happens to match host facts; this is an audit signal, not an execution gate.
- `scope_verified`: the worker accepted the exact write boundary.
- `worktree_verified`: the worker is operating in the declared Git worktree and branch.
- `evidence_verified`: the result is bound to the final candidate after verification.

Do not treat transport completion as identity or work completion. Host dispatch, host attestation, and worker self-report are separate facts. Missing host identity is `UNVERIFIED`, not `FAIL`, when the declared gate is `HOST_DISPATCH`; a worker self-report mismatch is an audit warning and never a routing failure. Use `model_identity` only for an explicit host mismatch or when the plan requires `HOST_VERIFIED` and that gate cannot be met. Never substitute another model.

For a low-risk task, a successful host dispatch with unavailable runtime identity enters execution as `HOST_DISPATCHED_UNATTESTED`; it must not claim that Luna actually ran. For a high-risk task, missing host attestation remains `BLOCKED`.

When the host supports native generic subagent spawning, launch an isolated worker with the requested model and effort rather than a custom agent type. Use `fork_context=false` (or the host's equivalent of a fresh context) so the controller's history is not copied. Pass the full worktree boundary in the task packet and require the worker to return the handshake and result schemas.

If the native spawn surface rejects the requested Luna model, reports the agent type unavailable, or the host explicitly observes a different model, do not fall back to the removed `luna-worker` registration; treat the task as `BLOCKED`. If the host accepts the request and returns a dispatch receipt but does not expose runtime identity, apply the declared `HOST_DISPATCH` or `HOST_VERIFIED` gate instead.

If the host offers a separate compatibility execution lane, use it only for low-risk, narrow, independently verifiable tasks and label identity as `unverified`. Never use an unverified lane for secrets, destructive migration, security decisions, irreversible data changes, or shared-interface ownership. If no host dispatch receipt exists, return `BLOCKED`; do not implement in the controller context.

## Context and token budget

- Keep the plan packet below roughly 800 words and each result packet below roughly 600 words unless the evidence requires more.
- Summarize logs; retain full logs at an artifact path and quote only failing lines and relevant exit status.
- Ask workers to avoid repeating repository background already present in the task packet.
- Prefer one broad read-only scout followed by bounded execution over several overlapping scouts.
- Do not re-launch an identical packet without new evidence.

## Review gate

Approve only when all are true:

- Every changed path belongs to one declared owner and write scope.
- Every write phase has a verified worktree/branch unless the user explicitly declared `DIRECT_OPT_OUT`.
- Every write phase has a commit and a final committed diff review before merge.
- The final diff contains no unrelated edits.
- The host dispatch satisfies the declared identity gate; worker self-report mismatches are recorded as warnings only.
- Required tests/builds ran against the final candidate, not an earlier state.
- The evidence explains failures and business impact, not only exit codes.
- The result satisfies `done_when` and does not violate exclusions.

If any condition is false, return `FIX` once when a same-scope correction is credible; otherwise return `BLOCKED` with the concrete failure class and next safe action.

## Result discipline

Use structured results exactly as specified in the reference. Keep the controller's final response short: outcome, changed paths, verification, evidence, and blocker or residual risk. Claim a model only from host dispatch/observation fields; label worker claims as self-report. A model self-report mismatch may produce `PASS_WITH_WARNING`; the controller alone decides the overall result.
