# Contributing

1. Work from an isolated Git worktree and keep changes bounded to the declared
   phase.
2. Do not add real paths, usernames, host names, credentials, worker prompts,
   receipts, or private transcripts. Use placeholders and synthetic probes.
3. Do not change host ACLs, `config.toml`, custom-role files, or the installed
   runtime copy in a source change. Runtime synchronization happens only after
   review and merge.
4. Preserve the route order: native -> MCP -> explicitly approved Desktop task.
   Do not silently substitute a model or turn an unspecified user-task decision
   into a denial.
5. Run on Windows PowerShell:

   ```powershell
   & .\tests\protocol-contract.ps1
   & .\tests\privacy-contract.ps1
   & .\tests\broker-contract.ps1
   ```

   After merging to the source repository, verify the installed copy with
   `& .\tests\runtime-sync-contract.ps1 -RuntimeRoot <CODEX_HOME>\skills\sol-reliable-control`.

6. Review the diff for privacy, execution-status separation, and fail-closed
   identity gates before committing. Do not rewrite existing author history.
