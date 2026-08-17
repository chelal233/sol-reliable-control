# Security policy

## Scope

This repository contains a policy skill for routing native and explicitly
user-approved Desktop Luna workers. It does not own Codex Desktop, host
capability registries, or Windows ACLs.

## Safe defaults

- Keep handshake probes read-only and bounded.
- Treat worker self-report, UI selectors, role files, and bare agent handles as
  advisory; accept host identity only from a task-bound launch record.
- Never use this skill to widen ACLs, grant full control, or repair unrelated
  directories. A sandbox error is reported as an execution blocker.

## Reporting

Do not include credentials, private prompts, full transcripts, user-home paths,
or host-specific identifiers in a report. Describe the redacted blocker code,
task id, host surface, and reproducible contract-test command. For a suspected
secret disclosure or unsafe process launch, stop the route and report privately
to the repository owner before opening a public issue.

## Known limitations

The host cannot prove effective identity when launch telemetry is absent, and
this skill cannot repair process-creation or ACL failures. The result remains
`BLOCKED` until the host supplies independent evidence and a successful bounded
probe.
