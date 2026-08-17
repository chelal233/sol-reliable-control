# sol-reliable-control

An installable Codex Sol controller skill for lane routing, worker handshakes,
identity gates, compact evidence collection, and final review.

Language: [简体中文](README.md) · [English](README.en.md)

## Normal lanes

- `LUNA_MAX`: bounded, independently verifiable work; requests
  `gpt-5.6-luna / max`.
- `SOL_XHIGH`: cross-cutting planning, arbitration, or final review; requests
  `gpt-5.6-sol / xhigh`.

`BLOCKED` terminates the current implementation dispatch, not the recovery
workflow. When a safe host repair remains possible, return
`HOST_REMEDIATION_REQUIRED` with the exact permission request, external-change
evidence, minimal read-only probe, and next action. Do not leave the caller
with only “blocked” or loop on an unchanged packet.

The recovery order is fixed: native handshake -> (if explicitly authorized)
Desktop task handshake -> explicit user or host-owner approval for the smallest
role/registry repair -> refresh/rebind. A repair still requires a new task's
minimal read-only probe. Do not retry the implementation packet until the
selected probe succeeds.

`LUNA_MAX` uses **Native-first -> Desktop-task** routing. Priority 1 is a native
subagent surface that is visible to the current thread and matches the worker
contract. The canonical surface is `multi_agent_v1__spawn_agent`; a future equivalent
qualifies only if the host declares and verifies its contract, schema, requested
model, effort, and identity evidence.

After native preflight fails, use the explicitly approved Desktop task as Priority
2 when the plan permits a user-owned task. If Desktop is not authorized or fails,
retain the requested `gpt-5.6-luna / max` and return `BLOCKED` with a concrete
host-registration action. Never create a hidden or local alternate transport.

The conditional `USER_VISIBLE_TASK` route follows the approach in
`sol-advisor`: use the host-owned `codex_app__create_thread` surface with
`gpt-5.6-luna / max` to create a visible task after native preflight fails. It
is not a native sub-agent or a Luna enablement mechanism. It is attempted as
priority 2 when the plan permits a user-owned task and the user has explicitly
approved it; otherwise it is skipped and the task remains `BLOCKED`.

This Desktop task route does not call `setupStart`, run PowerShell, or change
ACLs. If the host still reports
`PROCESS_CREATION_DENIED` or a sandbox permission error, record the execution
blocker and stop; do not broaden permissions.

## Three-layer verification

1. `TRANSPORT_VERIFIED`: the native or Desktop surface returned a task-bound result.
2. `HOST_LAUNCH_RECORDED`: the host reported the requested model and effort for
   a fresh task-bound thread.
3. `HOST_VERIFIED`: identity and execution gates both pass. A matching launch
   record without effective telemetry remains `HOST_MODEL_UNOBSERVABLE`.

Worker self-report, UI model pickers, and agent handles are advisory unless the
host contract supplies authoritative evidence.

Execution blockers such as denied process creation remain separate from model
identity; they do not authorize a model substitution or a permission expansion.

## Installation and host registration

Install this directory under `$CODEX_HOME/skills/sol-reliable-control`. Luna/max
model availability and worker registration belong to the Codex host. The skill
does not register a local transport or alter filesystem permissions. After a
host-side role or model-registry change, reload the owning process, re-enumerate
the current thread's worker surface, and run a fresh handshake before sending
implementation instructions. A local TOML role file or UI picker is not a
task-bound identity receipt.

Before public distribution, the repository owner must choose and add a
`LICENSE`. This project does not infer a license from the reference projects or
present an unlicensed checkout as a reusable release.

## Reference projects and official documentation

The complete list of public projects, official host/model/sandbox sources,
operational evidence, local implementation files, trade-offs, pitfalls,
mitigations, and GitHub publication gates is in
[references/sources.md](references/sources.md). The repository links and
paraphrases these sources; it does not depend on them at runtime or copy
credentials, user data, or old worktrees.
The public reference projects are
[sol-advisor](https://github.com/DannyMac180/sol-advisor) and
[codex-sol-control](https://github.com/yehyakin/codex-sol-control).

Key controls are:

1. Native -> (explicitly approved) Desktop task; no implicit user-task creation.
2. Exact lane binding: `gpt-5.6-luna / max` and `gpt-5.6-sol / xhigh`; no silent model substitution.
3. Independent transport, launch-identity, execution, freshness, and history gates; `HOST_MODEL_UNOBSERVABLE` is not `HOST_MODEL_MISMATCH`.
4. A Desktop GUI picker is not host identity evidence by default; an explicitly approved `OPERATOR_ATTESTED` plan may record `OPERATOR_UI_ATTESTED` with `Identity: ATTESTED`, never `HOST_VERIFIED`.
5. Project selection before Desktop tasks; projectless is handshake-only.
6. No Sol-owned ACL/token repair or broad permission changes after sandbox failures.
7. Bind timeout recovery to the same task receipt; no duplicate implementation packet.
8. Source/runtime hash equality and privacy/protocol tests before publication.

## Verification

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/protocol-contract.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/privacy-contract.ps1
```

See [SKILL.md](SKILL.md) and the files under `references/` for the complete
protocol and registration rules, including
[references/desktop-task-lane.md](references/desktop-task-lane.md) for the
explicit Desktop Luna task route. No local alternate transport is installed by
this skill.

The complete reference catalog, trade-offs, failure modes, mitigations, and
GitHub publication checklist are in
[references/sources.md](references/sources.md).
