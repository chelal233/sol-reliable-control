# Reference Catalog and Key Controls

本文件是 Sol 的集中式参考清单。它记录外部项目、官方协议/宿主资料、
运行时问题的证据来源，以及本仓库实际采用的控制要点。所有链接仅用于
设计与核验；Sol 不在运行时下载、复制凭据、读取旧 worktree 或依赖这些
项目才能运行。

This is the canonical reference catalog for Sol. Links are design and verification
references only. Sol does not download them at runtime, copy credentials, read
legacy worktrees, or depend on them for execution.

## 1. Public reference projects

### DannyMac180/sol-advisor

- Project: [sol-advisor](https://github.com/DannyMac180/sol-advisor)
- Orchestration contract: [orchestration/SKILL.md](https://raw.githubusercontent.com/DannyMac180/sol-advisor/main/plugins/sol-advisor/skills/orchestration/SKILL.md)
- MCP configuration server: [server.ts](https://raw.githubusercontent.com/DannyMac180/sol-advisor/main/plugins/sol-advisor/mcp/server.ts)
- Native Sol reviewer role: [sol-advisor-sol-reviewer.toml](https://raw.githubusercontent.com/DannyMac180/sol-advisor/main/plugins/sol-advisor/agents/sol-advisor-sol-reviewer.toml)
- Native Terra implementer role: [sol-advisor-terra-implementer.toml](https://raw.githubusercontent.com/DannyMac180/sol-advisor/main/plugins/sol-advisor/agents/sol-advisor-terra-implementer.toml)

Sol uses this project as the reference for:

1. Keeping architecture, decomposition, implementation, and review ownership
   separate.
2. Treating Luna as an explicit, visible Codex app-task lane rather than
   pretending that a native Sol/Terra role is Luna.
3. Keeping MCP configuration/consent management separate from task execution.
4. Loading a role only when the host reports that the role is actually
   registered.

Sol does **not** copy its credentials, private data, native role files, or
   fallback semantics. Its Luna task lane is adapted to the current Desktop
`codex_app__create_thread` / `wait` / `read` / `send` surface and Sol's own
identity gates.

### yehyakin/codex-sol-control

- Project: [codex-sol-control](https://github.com/yehyakin/codex-sol-control)

This is the earlier Codex Sol control design reference. Sol adopts the useful
controller/reviewer separation and bounded evidence mindset, but reimplements
the host adapter, model identity gate, task receipt, privacy redaction, and
Desktop-task route for the current host. No old branch, archive, ZIP, or local
worktree is a runtime dependency.

## 2. Official OpenAI and Codex documentation

### Host surfaces and protocols

- [MCP](https://learn.chatgpt.com/docs/extend/mcp): external tool-server
  registration and tool-call boundary.
- [App Server](https://learn.chatgpt.com/docs/app-server): host-managed task and
  turn transport concepts.
- [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents):
  native role/subagent configuration concepts.
- [Codex repository](https://github.com/openai/codex): upstream implementation
  context; not a local Sol dependency.

### Model and effort binding

- [GPT-5.6 Luna model reference](https://developers.openai.com/api/docs/models/gpt-5.6-luna):
  model identity and supported API surface.
- [Latest model guidance](https://developers.openai.com/api/docs/guides/latest-model):
  current model-selection guidance.

Sol binds its normal lanes as follows:

| Logical lane | Exact request | Rule |
| --- | --- | --- |
| `LUNA_MAX` | `gpt-5.6-luna / max` | required for the Luna lane; never silently substituted |
| `SOL_XHIGH` | `gpt-5.6-sol / xhigh` | normal replan/escalation lane; not an implicit Luna fallback |

### Windows sandbox and runtime evidence

- [Building Codex for Windows sandbox](https://openai.com/index/building-codex-windows-sandbox/):
  explains the elevated helper, sandbox users, profile-root read ACL setup, and
  process creation path.
- [Windows sandbox setup source](https://raw.githubusercontent.com/openai/codex/main/codex-rs/windows-sandbox-rs/src/setup.rs):
  the upstream setup/profile-root implementation reference.
- [Native Luna allowlist issue #34399](https://github.com/openai/codex/issues/34399):
  operational evidence that a native spawn surface can advertise only a subset
  of models even when a separate host task surface accepts Luna. This issue is
  evidence, not a normative Sol contract.

These references explain why a host execution can report
`WINDOWS_SANDBOX_ACL_FAILED` or `PROCESS_CREATION_DENIED`. They do **not** grant
Sol permission to change ACLs, invoke administrative setup, or touch unrelated
user directories.

## 3. Local Sol implementation map

| File | Responsibility | Required reading |
| --- | --- | --- |
| [`SKILL.md`](../SKILL.md) | controller identity, route order, state machine, gates | every dispatch |
| [`protocol.md`](protocol.md) | compact plan/handshake/result packets and evidence states | packet construction and review |
| [`runtime-adapters.md`](runtime-adapters.md) | Native, Desktop-task, and custom-role adapter contracts | capability preflight |
| [`desktop-task-lane.md`](desktop-task-lane.md) | Desktop Luna task schema, project/worktree modes, receipt and no-ACL rules | Desktop route |
| [`enablement.md`](enablement.md) | host registration/config boundary and bounded recovery | missing capability or permission |
| [`registration.md`](registration.md) | exact registration, refresh, ordered attempts, and approval packet | host unblock |
| [`../tests/protocol-contract.ps1`](../tests/protocol-contract.ps1) | routing and documentation contract | every documentation change |
| [`../tests/privacy-contract.ps1`](../tests/privacy-contract.ps1) | path, credential-shape, and output-redaction contract | every source/runtime sync |

The canonical source is the repository root. The installed runtime copy is
synchronized from that source and is never edited as an independent source.

## 4. Current route order and selection rules

The default Luna order is:

```text
1. NATIVE_GENERIC / CUSTOM_ROLE native surface
2. USER_VISIBLE_TASK Desktop task (only with explicit user approval)
3. Host registration/rebind after both eligible surfaces fail
```

The second step is conditional, not an automatic user-task creation. If the
plan says `User-owned task: DENIED`, Sol skips it. If authorization is
`UNSPECIFIED`, Sol requests confirmation rather than synthesizing a denial.
`EXPLICIT_USER_VISIBLE_TASK` is reserved for
an operator-selected override and still requires the same approval and identity
gates.

`SOL_XHIGH` is a normal replan selected by task fit or the escalation rule. It
is not a silent compatibility fallback for an unavailable Luna route.

## 5. Evidence and failure controls

Sol keeps these facts separate:

1. `TRANSPORT_VERIFIED`: the selected surface returned a task-bound result.
2. `HOST_LAUNCH_RECORDED`: the host reported exact effective Luna/max for the
   fresh task.
3. `HOST_VERIFIED`: launch identity, freshness, history exclusion, no reroute,
   scope, and completed execution all pass.
4. Worker self-report, UI model selection, and a bare `agent_id` are advisory.
5. `PROCESS_CREATION_DENIED` and `WINDOWS_SANDBOX_ACL_FAILED` are execution
   blockers; they do not erase an independently verified host identity.

High-risk implementation remains blocked until the required identity and
execution gates pass. A timeout, pending job, or failed handshake never
authorizes resubmitting the same implementation packet.

## 6. Permission, privacy, and scope boundaries

- Sol may read/write only its declared source repository and synchronized
  runtime copy for a requested documentation or code change.
- Sol never repairs broad user-root ACLs, grants full control, invokes `setupStart`,
  or modifies unrelated directories as part of a Luna route.
- Workdir and project targets must be explicit; projectless Desktop tasks are
  handshake-only and cannot access a local repository.
- Broker output redacts user-home paths, host names, and credential-shaped
  values before crossing a task boundary.
- Packets contain compact scope, exclusions, verification, and evidence paths;
  they do not contain private reasoning, full transcripts, credentials, or old
  worktree history.

## 7. Change and review checklist

When changing a route or host adapter, verify all of the following:

1. The requested model/effort remains exact and no silent fallback appears.
2. The route order and user-owned-task gate are updated in both language docs.
3. Fresh/history, receipt, identity, and execution evidence remain independent.
4. ACL/token remediation is not introduced into a normal route.
5. Source and runtime hashes match after synchronization.
6. `protocol-contract.ps1`, `privacy-contract.ps1`, and
   the protocol and privacy contracts pass on both copies.
7. The final packet reports outcome, changed paths, verification, blocker, and
   next action without leaking secrets or private worker reasoning.

## 8. Route trade-offs, known problems, and mitigations

The route order is a policy choice, not a guarantee that every host can execute
every route. The following matrix must be read before selecting a surface:

| Route | Advantages | Costs / failure modes | Required mitigation |
| --- | --- | --- | --- |
| Native subagent | Lowest visibility overhead; no user-owned task; best controller-context isolation | Current-thread tool may be absent; model allowlist may expose only Sol/Terra; custom role metadata may disagree with the host | Enumerate the current thread; verify exact schema, fresh semantics, receipt, and host-observed Luna/max; never borrow sibling evidence |
| Desktop task | Uses the host's explicit Luna task surface; visible and easy for a user to inspect | Creates a user-owned task; projectless mode cannot touch a repo; project/local mode may have host sandbox limits; effective model telemetry may be absent | Require explicit approval; call `list_projects` first; prefer a fresh worktree; retain `threadId` + `hostId`; classify missing telemetry as `HOST_MODEL_UNOBSERVABLE`; use `OPERATOR_UI_ATTESTED` only under an explicit operator-attested gate and never call it `HOST_VERIFIED` |

### Problem and solution catalog

#### A. Native surface is missing or model-restricted

**Symptom:** `multi_agent_v1__spawn_agent` is absent, or
`collaboration.spawn_agent` rejects `gpt-5.6-luna` and lists only other models.

**Risk:** treating a sibling thread's model list, UI picker, role file, or
`agent_id` as proof; silently substituting Sol/Terra; or repeatedly resubmitting
the same packet.

**Solution:** classify the result as thread-bound surface mismatch, record the
exact schema, evaluate the approved Desktop task route at priority 2, and use
request host registration when Desktop is not eligible or fails. Keep
`LUNA_MAX` and `Fallback: BLOCKED` unchanged unless the plan explicitly allows
a compatibility lane.

#### B. Desktop task is created in the wrong place

**Symptom:** a projectless task starts in a temporary output directory, or a
worktree task is based on the wrong project/state.

**Risk:** Luna cannot read the intended repository, changes land in an
unexpected worktree, or a direct-local task races with another task.

**Solution:** call `codex_app__list_projects` first; verify the selected project
and `isGitRepository`; use a fresh worktree and an explicit starting state for
implementation; use projectless only for handshake-only probes. Use `local`
only after an explicit user request for direct shared-directory work.

#### C. Desktop task has no authoritative model telemetry

**Symptom:** creation returns `threadId`/`hostId`, but no host-observed effective
model/effort; the worker says only `unobservable`.

**Risk:** treating the requested model field or UI picker as `HOST_VERIFIED`.

**Solution:** classify the result as `HOST_MODEL_UNOBSERVABLE`, not
`HOST_MODEL_MISMATCH`. Keep `HOST_LAUNCH_RECORDED` and `HOST_VERIFIED` closed
until the host reports effective Luna/max, fresh context, history exclusion, and
no reroute/conflict. If the user explicitly selects `Identity gate:
OPERATOR_ATTESTED`, the live GUI confirmation may produce
`OPERATOR_UI_ATTESTED` with `Identity: ATTESTED`; it remains a separate,
weaker evidence tier and must carry residual-risk and scope controls.
For `HIGH` work, that explicit exception additionally requires an isolated
worktree, no secrets/destructive/ACL/external side effects or descendants, and
Sol review before commit or merge; otherwise keep the task blocked.

#### D. Windows sandbox ACL or process creation failure

**Symptom:** `WINDOWS_SANDBOX_ACL_FAILED` or `PROCESS_CREATION_DENIED`, often
before PowerShell can run.

**Risk:** broadening permissions, changing unrelated user-root ACLs, or blaming
the Luna model when the failure is in the host sandbox/token path.

**Solution:** keep identity and execution facts separate; stop the implementation
packet; do not call `setupStart`, `icacls`, `Set-Acl`, `takeown`, or equivalent
from Sol. If a host owner chooses remediation, request only the smallest
official host change and require a new minimal read-only probe before retrying.

#### E. Host timeout or asynchronous ambiguity

**Symptom:** a host call times out while the worker may still be running, or the
task status remains pending.

**Risk:** launching a duplicate implementation packet and producing conflicting
edits or receipts.

**Solution:** retain the task-bound receipt, treat a timeout or pending state as
unknown, and do not resubmit the packet. Request the host's completion record
or a fresh bounded handshake after an external host state change.

#### F. Model reroute or effort mismatch

**Symptom:** host reports a different effective model/effort or emits a
`model/rerouted` event.

**Risk:** claiming Luna/max work when the host actually ran another lane.

**Solution:** classify `HOST_MODEL_MISMATCH`, keep high-risk work blocked, and
request host enablement or a new approved surface. Never silently downgrade.

#### G. Source/runtime drift

**Symptom:** the repository has a newer protocol but the installed skill still
exposes the old route order or schema.

**Risk:** different threads follow different policies and evidence rules.

**Solution:** synchronize only from the canonical repository, compare SHA-256
per file, run the three contract tests on both copies, and record the source
commit in the release evidence.

#### H. Privacy and prompt leakage

**Symptom:** a packet contains user-home paths, host names, credentials, full
transcripts, or private worker reasoning.

**Risk:** publishing sensitive data to GitHub or crossing a task boundary.

**Solution:** use compact packets and placeholders, keep raw logs outside the
repository, apply output sanitization, run `privacy-contract.ps1`, and
manually review diffs before publication.

## 9. GitHub publication risks and release checklist

This repository is intended to be publishable, but publication is a separate
action from local implementation. Before pushing a branch or opening a PR:

1. Confirm the diff contains no secrets, tokens, cookies, credentials, host
   names, user-home paths, private task ids, old worktree paths, or raw logs.
2. Keep all machine-specific values as placeholders such as
   `<CODEX_HOME>` and `<approved-worktree-root>`.
3. Inspect both tracked and untracked files; `git diff` alone does not show an
   untracked artifact.
4. Run `git diff --check`, `protocol-contract.ps1`, and `privacy-contract.ps1`
   from the source checkout.
5. Synchronize the runtime copy only after the source commit is reviewed, then
   verify the per-file SHA-256 set with `tests/runtime-sync-contract.ps1`.
6. Review the license/attribution obligations of every linked project before
   copying code, role files, or assets. This repository currently links and
   paraphrases; it does not vendor their implementation.
7. Describe the host/version assumptions and the known limitation that Desktop
   task effective model telemetry may be unavailable.
8. Do not commit generated reports, sandbox logs, or task
   transcripts unless they have been deliberately sanitized and are required
   as a public fixture.
9. Push only the intended branch. Do not force-push or rewrite shared history
   without explicit authorization.
10. Select and add a repository license before public distribution. No license
    is inferred from the linked projects; until the owner chooses one, treat
    publication as legally incomplete and do not present the repository as
    reusable under an assumed MIT/Apache/GPL grant.

### Public-release acceptance

The release is ready for review only when the source worktree is clean, the
route order is documented in both languages, all external references are listed
here, tests pass on source and runtime, and the final evidence states what is
still host-dependent, and an owner-selected `LICENSE` file is present. A green
documentation test does not prove that the
current host can execute Luna; it proves that the controller will fail safely
and tell the caller what to do.
