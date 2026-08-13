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

$scriptPath = Join-Path $Root 'scripts/sol-luna-broker.ps1'
Assert-True (Test-Path -LiteralPath $scriptPath -PathType Leaf) 'broker script must exist'
$scriptText = Get-Content -Raw -LiteralPath $scriptPath
Assert-Contains $scriptText 'gpt-5.6-luna' 'broker must pin the Luna model'
Assert-Contains $scriptText 'model_reasoning_effort="max"' 'broker must pin max effort'
Assert-Contains $scriptText '--ephemeral' 'broker must use an ephemeral worker'
Assert-Contains $scriptText '--ignore-user-config' 'broker must isolate model selection from user config'
Assert-Contains $scriptText '--strict-config' 'broker must reject unknown runtime configuration'
Assert-Contains $scriptText 'BROKER_RUN_RECEIPT' 'broker must label its receipt separately from HOST_RECEIPT'
Assert-Contains $scriptText 'SELF_REPORT_ONLY' 'broker must keep self-report identity advisory'
Assert-Contains $scriptText 'Effective model' 'broker must parse labeled effective-model self-reports'

$requests = @(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
    '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}',
    '{"jsonrpc":"2.0","id":3,"method":"ping","params":{}}',
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"sol_luna_exec","arguments":{"task_id":"invalid-root","workdir":"C:\\Windows","prompt":"DO NOT RUN"}}}'
)
$output = ($requests -join "`n") | & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath
Assert-True ($LASTEXITCODE -eq 0) 'broker must exit cleanly when the input stream closes'
$records = @($output | ConvertFrom-Json)
Assert-True ($records.Count -eq 4) 'broker must return one response for each request'

$initialize = $records | Where-Object { $_.id -eq 1 }
Assert-True ($initialize.result.serverInfo.name -eq 'sol-luna-broker') 'initialize must identify the broker'
Assert-Contains $initialize.result.instructions 'gpt-5.6-luna/max' 'initialize must publish the fixed lane'

$list = $records | Where-Object { $_.id -eq 2 }
Assert-True ($list.result.tools -is [array]) 'tools/list must return a JSON array'
Assert-True ($list.result.tools.Count -eq 1) 'tools/list must expose exactly one broker tool'
Assert-True ($list.result.tools[0].name -eq 'sol_luna_exec') 'broker tool name must be stable'
Assert-True ($list.result.tools[0].inputSchema.required -contains 'task_id') 'task_id must be required'
Assert-True ($list.result.tools[0].inputSchema.required -contains 'workdir') 'workdir must be required'
Assert-True ($list.result.tools[0].inputSchema.required -contains 'prompt') 'prompt must be required'

$ping = $records | Where-Object { $_.id -eq 3 }
Assert-True ($null -ne $ping.result) 'ping must return a result'

$invalid = $records | Where-Object { $_.id -eq 4 }
Assert-True ($null -ne $invalid.error) 'broker must reject a workdir outside the allowed roots'

Write-Output 'PASS: Sol Luna broker contract'
