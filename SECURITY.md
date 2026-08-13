# Security policy

## Scope

This repository contains a policy skill and a local STDIO MCP broker for
launching a fixed `gpt-5.6-luna / max` worker. It does not own Codex Desktop,
the app-server sandbox, host capability registries, or Windows ACLs.

## Safe defaults

- Pin both `SOL_LUNA_RUNTIME_PATH` and `SOL_LUNA_RUNTIME_SHA256`.
- Configure only the exact approved phase worktree in
  `SOL_LUNA_ALLOWED_ROOTS`; do not use a user profile or drive root.
- Keep handshake probes `read-only` and `handshake_only=true`.
- Treat worker self-report, UI selectors, role files, and bare agent handles as
  advisory; accept host identity only from a task-bound launch record.
- Never use this skill to widen ACLs, grant full control, or repair unrelated
  directories. A sandbox error is reported as an execution blocker.

## Reporting

Do not include credentials, private prompts, full transcripts, user-home paths,
or host-specific identifiers in a report. Describe the redacted blocker code,
task id, broker version, and reproducible contract-test command. For a suspected
secret disclosure or unsafe process launch, stop the route and report privately
to the repository owner before opening a public issue.

## Known limitations

The broker cannot prove host identity when the app-server omits launch telemetry,
and it cannot repair `CreateProcessAsUserW`/ACL failures. The result remains
`BLOCKED` until the host supplies independent evidence and a successful bounded
probe.
