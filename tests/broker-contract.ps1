[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Reason)
    if (-not $Condition) { throw "Broker contract assertion failed: $Reason" }
}

function Assert-Contains {
    param([string]$Text, [string]$Needle, [string]$Reason)
    Assert-True ($Text.IndexOf($Needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) $Reason
}

function Assert-NotContains {
    param([string]$Text, [string]$Needle, [string]$Reason)
    Assert-True (-not $Text.Contains($Needle)) $Reason
}

$scriptPath = Join-Path $Root 'scripts/sol-luna-broker.ps1'
Assert-True (Test-Path -LiteralPath $scriptPath -PathType Leaf) 'broker script must exist'
$scriptText = Get-Content -Raw -LiteralPath $scriptPath
Assert-Contains $scriptText 'gpt-5.6-luna' 'broker must pin the Luna model'
Assert-Contains $scriptText 'model_reasoning_effort="max"' 'broker must pin max effort'
Assert-Contains $scriptText '--ephemeral' 'broker must use an ephemeral worker'
Assert-Contains $scriptText 'app-server' 'broker must support the host-managed app-server transport'
Assert-Contains $scriptText 'thread/start' 'app-server transport must capture the host launch record'
Assert-Contains $scriptText 'model/rerouted' 'broker must reject a host model reroute'
Assert-Contains $scriptText 'ROLE_MAPPING_AND_LAUNCH_RECORD' 'app-server identity must use the authoritative launch record kind'
Assert-Contains $scriptText '--ignore-user-config' 'broker must isolate model selection from user config'
Assert-Contains $scriptText '--strict-config' 'broker must reject unknown runtime configuration'
Assert-Contains $scriptText 'SOL_LUNA_RUNTIME_PATH must be configured explicitly' 'broker must not auto-select an unpinned runtime'
Assert-Contains $scriptText 'SOL_LUNA_RUNTIME_SHA256' 'broker must require a runtime hash pin'
Assert-Contains $scriptText 'SOL_LUNA_RUNTIME_HASH_MISMATCH' 'broker must reject a runtime hash mismatch'
Assert-Contains $scriptText 'Test-NoReparsePoints' 'broker must reject reparse-point roots and runtimes'
Assert-Contains $scriptText 'BROKER_RUN_RECEIPT' 'broker must label its receipt separately from HOST_RECEIPT'
Assert-Contains $scriptText 'SELF_REPORT_ONLY' 'broker must keep self-report identity advisory'
Assert-Contains $scriptText 'Effective model' 'broker must parse labeled effective-model self-reports'
Assert-Contains $scriptText 'Normalize-ObservedValue' 'broker must treat explicit unknown self-report markers as unobserved'
Assert-Contains $scriptText 'selfModel -and $selfModel.ToLowerInvariant()' 'broker must block an explicit model mismatch even when effort is absent'
Assert-Contains $scriptText 'Protect-OutputText' 'broker must sanitize output before it crosses MCP'
Assert-Contains $scriptText 'redaction = [ordered]@{' 'broker must expose redaction status'
Assert-Contains $scriptText 'SOL_LUNA_ALLOWED_ROOTS must be configured' 'broker must require explicit filesystem roots'
Assert-Contains $scriptText 'HOST_JOB_RECEIPT' 'broker must expose a task-bound asynchronous receipt'
Assert-Contains $scriptText 'sol_luna_poll' 'broker must expose asynchronous result retrieval'
Assert-Contains $scriptText 'execution_mode' 'broker must expose synchronous/asynchronous execution modes'
Assert-Contains $scriptText 'WINDOWS_SANDBOX_ACL_FAILED' 'broker must classify Windows sandbox ACL failures'
Assert-Contains $scriptText 'PROCESS_CREATION_DENIED' 'broker must classify denied process creation'
Assert-Contains $scriptText 'SetNamedSecurityInfoW\s+failed' 'broker must recognize the Windows sandbox ACL error signature'
Assert-Contains $scriptText 'CreateProcessAsUserW\s+failed' 'broker must recognize the denied process creation signature'
Assert-Contains $scriptText 'command could not execute' 'broker must recognize denied command execution text'
Assert-Contains $scriptText 'command blocked' 'broker must recognize blocked command execution text'
Assert-Contains $scriptText 'HANDSHAKE_ACTIVITY_DETECTED' 'broker must reject activity during handshake-only probes'
Assert-Contains $scriptText 'OUTPUT_LIMIT_EXCEEDED' 'broker must cap worker output'
Assert-Contains $scriptText 'EVENT_LIMIT_EXCEEDED' 'broker must cap app-server events'
Assert-Contains $scriptText 'SOL_LUNA_MAX_ASYNC_JOBS' 'broker must bound asynchronous concurrency'
Assert-Contains $scriptText 'execution_status = $executionStatus' 'broker must return execution status independently from identity'
Assert-Contains $scriptText 'execution_blocker_code = $executionBlockerCode' 'broker must return an execution blocker code'
Assert-Contains $scriptText 'execution_blocker = Protect-OutputText $executionBlocker' 'broker must redact the execution blocker'
Assert-Contains $scriptText '$exitCode = if ($timedOut) { $null } elseif ($executionStatus -eq ''COMPLETED'') { 0 } else { 1 }' 'blocked app-server execution must not return exit code zero'
Assert-Contains $scriptText '$identity -eq ''VERIFIED'' -and $executionStatus -eq ''COMPLETED''' 'HOST_VERIFIED must require both verified identity and completed execution'
$appStart = $scriptText.IndexOf('function Invoke-AppServerWorker', [StringComparison]::Ordinal)
$appEnd = $scriptText.IndexOf('function ConvertFrom-CodexEvents', [StringComparison]::Ordinal)
$appSection = $scriptText.Substring($appStart, $appEnd - $appStart)
Assert-NotContains $appSection "'--ignore-user-config'" 'app-server must not receive CLI-only ignore-user-config flags'
Assert-NotContains $appSection "'--ignore-rules'" 'app-server must not receive CLI-only ignore-rules flags'

$requests = @(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
    '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}',
    '{"jsonrpc":"2.0","id":3,"method":"ping","params":{}}',
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"sol_luna_exec","arguments":{"task_id":"invalid-root","workdir":"C:\\Windows","prompt":"DO NOT RUN"}}}',
    ('{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"sol_luna_exec","arguments":{"task_id":"runtime-pin","workdir":"' + ($Root -replace '\\','\\\\') + '","prompt":"DO NOT RUN"}}}')
)
$oldRoots = $env:SOL_LUNA_ALLOWED_ROOTS
$oldRuntime = $env:SOL_LUNA_RUNTIME_PATH
$oldHash = $env:SOL_LUNA_RUNTIME_SHA256
try {
    $env:SOL_LUNA_ALLOWED_ROOTS = $Root
    $env:SOL_LUNA_RUNTIME_PATH = Join-Path $Root 'missing-codex.exe'
    $env:SOL_LUNA_RUNTIME_SHA256 = ('0' * 64)
    $output = ($requests -join "`n") | & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath
} finally {
    if ($null -eq $oldRoots) { Remove-Item Env:SOL_LUNA_ALLOWED_ROOTS -ErrorAction SilentlyContinue } else { $env:SOL_LUNA_ALLOWED_ROOTS = $oldRoots }
    if ($null -eq $oldRuntime) { Remove-Item Env:SOL_LUNA_RUNTIME_PATH -ErrorAction SilentlyContinue } else { $env:SOL_LUNA_RUNTIME_PATH = $oldRuntime }
    if ($null -eq $oldHash) { Remove-Item Env:SOL_LUNA_RUNTIME_SHA256 -ErrorAction SilentlyContinue } else { $env:SOL_LUNA_RUNTIME_SHA256 = $oldHash }
}
Assert-True ($LASTEXITCODE -eq 0) 'broker must exit cleanly when the input stream closes'
$records = @($output | ConvertFrom-Json)
Assert-True ($records.Count -eq 5) 'broker must return one response for each request'

$initialize = $records | Where-Object { $_.id -eq 1 }
Assert-True ($initialize.result.serverInfo.name -eq 'sol-luna-broker') 'initialize must identify the broker'
Assert-Contains $initialize.result.instructions 'gpt-5.6-luna/max' 'initialize must publish the fixed lane'

$list = $records | Where-Object { $_.id -eq 2 }
Assert-True ($list.result.tools -is [array]) 'tools/list must return a JSON array'
Assert-True ($list.result.tools.Count -eq 2) 'tools/list must expose execution and polling broker tools'
$execTool = $list.result.tools | Where-Object { $_.name -eq 'sol_luna_exec' }
Assert-True ($null -ne $execTool) 'broker execution tool name must be stable'
Assert-True ($execTool.inputSchema.required -contains 'task_id') 'task_id must be required'
Assert-True ($execTool.inputSchema.required -contains 'workdir') 'workdir must be required'
Assert-True ($execTool.inputSchema.required -contains 'prompt') 'prompt must be required'
Assert-True ($execTool.inputSchema.properties.execution_mode.enum -contains 'async') 'execution tool must advertise async mode'
$pollTool = $list.result.tools | Where-Object { $_.name -eq 'sol_luna_poll' }
Assert-True ($null -ne $pollTool) 'broker polling tool name must be stable'
Assert-True ($pollTool.inputSchema.required -contains 'task_id') 'poll task_id must be required'
Assert-True ($pollTool.inputSchema.required -contains 'job_id') 'poll job_id must be required'

$ping = $records | Where-Object { $_.id -eq 3 }
Assert-True ($null -ne $ping.result) 'ping must return a result'

$invalid = $records | Where-Object { $_.id -eq 4 }
Assert-True ($null -ne $invalid.error) 'broker must reject a workdir outside the allowed roots'
$runtimePin = $records | Where-Object { $_.id -eq 5 }
Assert-True ($null -ne $runtimePin.error) 'broker must reject an untrusted runtime before starting a worker'
Assert-True ([string]$runtimePin.error.message -notmatch '(?i)missing-codex|[A-Z]:\\') 'runtime errors must not echo executable paths'

Write-Output 'PASS: Sol Luna broker contract'
