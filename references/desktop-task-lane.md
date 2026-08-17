# Explicit Desktop Luna Task Lane

This adapter documents the route used by clients such as
[sol-advisor](https://github.com/DannyMac180/sol-advisor): Luna is started as an
explicit, user-visible Codex task through the Codex app task surface instead of
as a hidden local child process. It is a separate host surface, not a native
subagent and not an enablement workaround.

## When it is allowed

The normal Sol ladder is **native Luna -> Desktop task**. The
Desktop step is conditional: after native preflight fails, it is attempted only
when all of these fields are present in the plan:

```text
Surface: USER_VISIBLE_TASK
Dispatch priority: NATIVE_FIRST_THEN_DESKTOP
User-owned task: ALLOWED
User approval: GRANTED
Requested model/effort: gpt-5.6-luna / max
Execution context: FRESH
Controller history: EXCLUDED
```

Do not create this task merely to register or prove that Luna exists. A packet
with `User-owned task: DENIED` must not use this adapter. If authorization is
`UNSPECIFIED`, pause and request confirmation; only `ALLOWED` plus
`User approval: GRANTED` is eligible. The native contract stays in force until
that confirmation exists; when the gate is not granted, the task remains
`BLOCKED`.

## Host call sequence

The app surface is host-owned. Sol does not shell out, does not call `setupStart`,
change ACLs, or start another local app-server. The caller uses the exact app tools
exposed by the current Desktop host:

```text
codex_app__list_projects({})

codex_app__create_thread({
  target: {
    type: "project",
    projectId: <selected project id>,
    environment: {
      type: "worktree",
      startingState: { type: "working-tree" }
    }
  },
  model: "gpt-5.6-luna",
  thinking: "max",
  title: <short task title>,
  prompt: <handshake-only packet>
})
```

`list_projects` is required before a project target is selected. The caller
must confirm the returned project is the intended Git repository. A projectless
task is acceptable for an identity-only probe, but cannot read or modify a local
repository. Do not invent a project id or pass a pending `clientThreadId` to a
tool that requires a ready `threadId`.

After the host returns a ready task, retain both `threadId` and `hostId` as the
task-bound receipt. Use `codex_app__wait_threads` and then
`codex_app__read_thread` for the same pair. Follow-up work, if explicitly
authorized, uses `codex_app__send_message_to_thread` with the same ids and
`model="gpt-5.6-luna"`, `thinking="max"`; never continue an unrelated thread.

## Evidence gates

The app task surface has independent transport, identity, execution, freshness,
and history gates, plus one explicit operator attestation tier:

1. `TRANSPORT_VERIFIED`: `create_thread` returned a ready `threadId` and
   `hostId`, and the task can be observed by the host.
2. `HOST_LAUNCH_RECORDED`: the host's task/turn record reports the exact
   requested `gpt-5.6-luna / max` pair for that task. The model selector, prompt,
   or worker self-report is not enough.
3. `HOST_VERIFIED`: the launch record is exact, the task is fresh, controller
   history is excluded, no reroute/model conflict is observed, and the requested
   handshake/turn completed successfully.
4. `OPERATOR_UI_ATTESTED` (explicit alternative): when the host omits effective
   model/effort telemetry, the user may attest that the live GUI for this exact
   task/thread displays `gpt-5.6-luna / max`. This requires an explicit plan
   `Identity gate: OPERATOR_ATTESTED`, `User approval: GRANTED`, and
   `Operator attestation: GRANTED`; retain `threadId`/`hostId`, fresh task
   evidence, history exclusion, and no explicit host mismatch/reroute. Record
   `Identity: ATTESTED` and keep the residual risk visible. It is not a host
   launch record and never upgrades to `HOST_VERIFIED`.

If the app surface returns only a task id and no host-observed model/effort,
report `HOST_MODEL_UNOBSERVABLE`, not `HOST_MODEL_MISMATCH`. Under the normal
`HOST_VERIFIED` gate, stop at `TRANSPORT_VERIFIED` and report `IDENTITY_UNVERIFIED`;
do not silently infer Luna from the UI. If the plan explicitly selects the
operator-attested gate, the live user confirmation may produce
`OPERATOR_UI_ATTESTED` as described above. If the task reports `PROCESS_CREATION_DENIED`,
`WINDOWS_SANDBOX_ACL_FAILED`, or another runtime permission error, keep the
identity facts separate, mark execution blocked, and stop. This adapter never
requests or performs an ACL repair.

For a `HIGH` task, `OPERATOR_UI_ATTESTED` is an explicit exception to the normal
host-identity gate, never an automatic downgrade. The plan must name the exact
isolated worktree and exclusions, forbid secrets, ACL/token changes, destructive
operations, external side effects, and descendant creation, and require Sol's
independent review before commit or merge. If those limits are not present, the
task remains `BLOCKED` until `HOST_VERIFIED` is available.

## Freshness and privacy

Freshness comes only from a newly created task; a fork or an existing thread is
not fresh evidence. The initial prompt must contain the compact plan and the
handshake-only rules, not controller history or private reasoning. Keep the
task scope to the approved project/worktree and do not include credentials,
user-home paths, host names, or full transcripts.

This route is intentionally visible in the user's task list. That visibility is
the trade-off for avoiding a hidden local process. It is not a background
subagent. If the user-owned-task gate is denied, the controller skips this
conditional priority-2 step. If the Desktop handshake fails, return `BLOCKED`
with a host-registration action.
