# Changelog

## Unreleased

- Improve Luna handshakes across Windows/Linux/macOS with platform temp workdirs,
  PATH-resolved runtimes, and structured host diagnostics.
- Make the synchronous read-only app-server handshake return its task-bound
  `HOST_LAUNCH_RECORD` at `thread/start` without waiting for a worker turn.
- Add an explicit operator-attested Desktop evidence tier for hosts that omit
  effective model/effort telemetry; keep `HOST_VERIFIED` strict.
- Make native -> explicitly approved Desktop the documented Luna route.
- Add tri-state user-owned-task authorization so missing approval is not silently
  normalized to `DENIED`.
- Require an explicitly pinned Codex executable path and SHA-256 before launch.
- Separate host identity, context/policy proof, and execution status; classify
  Windows sandbox ACL and process-creation failures without masking identity.
- Bound host event/output volume and asynchronous task retention.
- Reject reparse-point roots and redact arbitrary paths, token-shaped values, JWTs,
  and private-key blocks before task output.
- Add Windows contract CI and contributor/security guidance.
