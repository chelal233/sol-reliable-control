#!/usr/bin/env pwsh

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:BrokerName = 'sol-luna-broker'
$script:BrokerVersion = '1.0.0'
$script:FixedModel = 'gpt-5.6-luna'
$script:FixedEffort = 'max'
$script:CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }

function Send-JsonLine {
    param([Parameter(Mandatory = $true)] [object] $Value)

    [Console]::Out.WriteLine(($Value | ConvertTo-Json -Compress -Depth 40))
    [Console]::Out.Flush()
}

function Send-Result {
    param(
        [Parameter(Mandatory = $true)] [object] $Id,
        [Parameter(Mandatory = $true)] [object] $Result,
        [switch] $IsError
    )

    if ($IsError) {
        Send-JsonLine ([ordered]@{
            jsonrpc = '2.0'
            id = $Id
            error = [ordered]@{
                code = -32000
                message = [string]$Result
            }
        })
        return
    }

    Send-JsonLine ([ordered]@{
        jsonrpc = '2.0'
        id = $Id
        result = $Result
    })
}

function Get-TextProperty {
    param(
        [Parameter(Mandatory = $true)] [object] $Object,
        [Parameter(Mandatory = $true)] [string] $Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if (-not $property -or $null -eq $property.Value) { return $null }
    return [string]$property.Value
}

function Get-BoolProperty {
    param(
        [Parameter(Mandatory = $true)] [object] $Object,
        [Parameter(Mandatory = $true)] [string] $Name,
        [bool] $Default = $false
    )

    $property = $Object.PSObject.Properties[$Name]
    if (-not $property) { return $Default }
    return [bool]$property.Value
}

function Get-RuntimePath {
    if ($env:SOL_LUNA_RUNTIME_PATH) {
        if (-not (Test-Path -LiteralPath $env:SOL_LUNA_RUNTIME_PATH -PathType Leaf)) {
            throw "SOL_LUNA_RUNTIME_PATH is not a file: $($env:SOL_LUNA_RUNTIME_PATH)"
        }
        return (Resolve-Path -LiteralPath $env:SOL_LUNA_RUNTIME_PATH).Path
    }

    $root = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Codex runtime root is missing: $root"
    }

    $found = Get-ChildItem -LiteralPath $root -Directory |
        ForEach-Object { Join-Path $_.FullName 'codex.exe' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        ForEach-Object { Get-Item -LiteralPath $_ } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $found) { throw "No Codex runtime was found under $root" }
    return $found.FullName
}

function Get-AllowedRoots {
    $raw = if ($env:SOL_LUNA_ALLOWED_ROOTS) {
        $env:SOL_LUNA_ALLOWED_ROOTS
    } else {
        'E:\Sources\.codex-worktrees;E:\git\sol-reliable-control-worktrees;E:\git\sol-reliable-control'
    }

    $roots = @($raw -split ';' | Where-Object { $_ } | ForEach-Object {
        if (-not (Test-Path -LiteralPath $_ -PathType Container)) {
            throw "Configured broker root does not exist: $_"
        }
        (Resolve-Path -LiteralPath $_).Path.TrimEnd('\')
    })
    if ($roots.Count -eq 0) { throw 'SOL_LUNA_ALLOWED_ROOTS resolved to no directories' }
    return $roots
}

function Resolve-AllowedWorkdir {
    param([Parameter(Mandatory = $true)] [string] $Workdir)

    if (-not (Test-Path -LiteralPath $Workdir -PathType Container)) {
        throw "Workdir does not exist: $Workdir"
    }
    $resolved = (Resolve-Path -LiteralPath $Workdir).Path.TrimEnd('\')
    $matches = @(Get-AllowedRoots | Where-Object {
        $resolved.Equals($_, [StringComparison]::OrdinalIgnoreCase) -or
        $resolved.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase)
    })
    if ($matches.Count -eq 0) {
        throw "Workdir is outside SOL_LUNA_ALLOWED_ROOTS: $resolved"
    }
    return $resolved
}

function Get-TimeoutSeconds {
    $value = 900
    if ($env:SOL_LUNA_TIMEOUT_SECONDS) {
        $parsed = 0
        if (-not [int]::TryParse($env:SOL_LUNA_TIMEOUT_SECONDS, [ref]$parsed) -or $parsed -lt 10 -or $parsed -gt 86400) {
            throw 'SOL_LUNA_TIMEOUT_SECONDS must be an integer from 10 to 86400'
        }
        $value = $parsed
    }
    return $value
}

function Invoke-CodexWorker {
    param(
        [Parameter(Mandatory = $true)] [string] $RuntimePath,
        [Parameter(Mandatory = $true)] [string] $Workdir,
        [Parameter(Mandatory = $true)] [string] $Prompt,
        [Parameter(Mandatory = $true)] [ValidateSet('read-only', 'workspace-write')] [string] $Sandbox
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $RuntimePath
    $psi.WorkingDirectory = $Workdir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in @(
        '-a', 'never', 'exec', '--ephemeral', '--ignore-user-config',
        '--ignore-rules', '--strict-config', '--sandbox', $Sandbox,
        '--json', '-m', $script:FixedModel, '-c', 'model_reasoning_effort="max"',
        '-C', $Workdir, '-'
    )) {
        $psi.ArgumentList.Add([string]$argument)
    }
    $psi.Environment['CODEX_HOME'] = $script:CodexHome
    $psi.Environment['SOL_LUNA_BROKER'] = "$($script:BrokerName)/$($script:BrokerVersion)"

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    if (-not $process.Start()) { throw "Failed to start Codex runtime: $RuntimePath" }

    $process.StandardInput.Write($Prompt)
    $process.StandardInput.Close()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timeoutMs = [int64](Get-TimeoutSeconds) * 1000
    if (-not $process.WaitForExit($timeoutMs)) {
        try { $process.Kill($true) } catch { $process.Kill() }
        $process.WaitForExit()
        return [ordered]@{
            exit_code = $null
            timed_out = $true
            stdout = $stdoutTask.Result
            stderr = $stderrTask.Result
        }
    }

    return [ordered]@{
        exit_code = $process.ExitCode
        timed_out = $false
        stdout = $stdoutTask.Result
        stderr = $stderrTask.Result
    }
}

function ConvertFrom-CodexEvents {
    param([Parameter(Mandatory = $true)] [string] $Stdout)

    $events = [System.Collections.ArrayList]::new()
    foreach ($line in ($Stdout -split "`r?`n")) {
        if ([String]::IsNullOrWhiteSpace($line)) { continue }
        try { [void]$events.Add(($line | ConvertFrom-Json)) } catch { }
    }
    return $events.ToArray()
}

function Get-CodexMessageText {
    param([Parameter(Mandatory = $true)] [object[]] $Events)

    $texts = [System.Collections.Generic.List[string]]::new()
    foreach ($event in $Events) {
        if ((Get-TextProperty $event 'type') -ne 'item.completed') { continue }
        $itemProperty = $event.PSObject.Properties['item']
        if (-not $itemProperty) { continue }
        $item = $itemProperty.Value
        if ((Get-TextProperty $item 'type') -eq 'agent_message') {
            $text = Get-TextProperty $item 'text'
            if ($text) { $texts.Add($text) }
        }
    }
    return ($texts -join "`n")
}

function Get-FirstField {
    param(
        [Parameter(Mandatory = $true)] [string] $Text,
        [Parameter(Mandatory = $true)] [string] $Field
    )

    $pattern = "(?im)^\s*$([regex]::Escape($Field))\s*=\s*(.+?)\s*$"
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value.Trim()
}

function Get-FirstLabeledField {
    param(
        [Parameter(Mandatory = $true)] [string] $Text,
        [Parameter(Mandatory = $true)] [string] $Label
    )

    $pattern = "(?im)^\s*$([regex]::Escape($Label))\s*:\s*(.+?)\s*$"
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value.Trim()
}

function Get-ThreadId {
    param([Parameter(Mandatory = $true)] [object[]] $Events)

    foreach ($event in $Events) {
        if ((Get-TextProperty $event 'type') -eq 'thread.started') {
            $property = $event.PSObject.Properties['thread_id']
            if ($property) { return [string]$property.Value }
        }
    }
    return $null
}

function Get-ShortStderr {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Stderr
    )

    $lines = @($Stderr -split "`r?`n" | Where-Object { $_ -and $_.Length -lt 500 })
    if ($lines.Count -gt 12) { $lines = @($lines | Select-Object -First 12) }
    return $lines
}

function New-ToolResult {
    param(
        [Parameter(Mandatory = $true)] [object] $Payload,
        [bool] $IsError = $false
    )

    return [ordered]@{
        isError = $IsError
        content = @([ordered]@{
            type = 'text'
            text = ($Payload | ConvertTo-Json -Depth 40)
        })
        structuredContent = $Payload
    }
}

function Invoke-LunaTool {
    param([Parameter(Mandatory = $true)] [object] $Arguments)

    $taskId = Get-TextProperty $Arguments 'task_id'
    $workdirInput = Get-TextProperty $Arguments 'workdir'
    $prompt = Get-TextProperty $Arguments 'prompt'
    $sandbox = Get-TextProperty $Arguments 'sandbox'
    if (-not $sandbox) { $sandbox = 'read-only' }
    $handshakeOnly = Get-BoolProperty $Arguments 'handshake_only' $true

    if (-not $taskId -or $taskId -notmatch '^[A-Za-z0-9._-]{1,128}$') {
        throw 'task_id must match ^[A-Za-z0-9._-]{1,128}$'
    }
    if (-not $workdirInput) { throw 'workdir is required' }
    if (-not $prompt -or $prompt.Length -gt 20000) { throw 'prompt is required and must be <= 20000 characters' }
    if ($sandbox -notin @('read-only', 'workspace-write')) { throw 'sandbox must be read-only or workspace-write' }
    if ($handshakeOnly -and $sandbox -ne 'read-only') { throw 'handshake_only requires read-only sandbox' }

    $workdir = Resolve-AllowedWorkdir $workdirInput
    $runtime = Get-RuntimePath
    $runtimeHash = (Get-FileHash -LiteralPath $runtime -Algorithm SHA256).Hash
    $runtimeVersion = ((& $runtime --version 2>$null | Select-Object -First 1) -join '').Trim()
    $guard = @(
        'SOL LUNA BROKER CONTROL HEADER',
        "Task ID: $taskId",
        "Requested model: $script:FixedModel",
        "Requested effort: $script:FixedEffort",
        'Fresh context: required',
        'Controller history: excluded',
        'Do not create descendants.',
        $(if ($handshakeOnly) { 'Identity-only handshake: do not inspect or modify files and do not run commands.' } else { 'Stay within the supplied task scope and workdir.' }),
        '',
        'CALLER PACKET:',
        $prompt
    ) -join "`n"

    $run = Invoke-CodexWorker -RuntimePath $runtime -Workdir $workdir -Prompt $guard -Sandbox $sandbox
    $events = ConvertFrom-CodexEvents $run.stdout
    $text = Get-CodexMessageText $events
    $threadId = Get-ThreadId $events
    $selfModel = Get-FirstField -Text $text -Field 'SELF_REPORTED_MODEL'
    if (-not $selfModel) { $selfModel = Get-FirstField -Text $text -Field 'MODEL' }
    if (-not $selfModel) { $selfModel = Get-FirstLabeledField -Text $text -Label 'Effective model' }
    $selfEffort = Get-FirstField -Text $text -Field 'SELF_REPORTED_EFFORT'
    if (-not $selfEffort) { $selfEffort = Get-FirstField -Text $text -Field 'EFFORT' }
    if (-not $selfEffort) { $selfEffort = Get-FirstLabeledField -Text $text -Label 'Effort' }

    $identity = 'UNVERIFIED'
    $blocker = 'Self-report matches, but no host-observed identity telemetry was returned'
    if ($run.timed_out) {
        $identity = 'FAIL'
        $blocker = 'Codex runtime exceeded the broker timeout'
    } elseif ($run.exit_code -ne 0) {
        $identity = 'FAIL'
        $blocker = "Codex runtime exited with code $($run.exit_code)"
    } elseif (-not $selfModel -or -not $selfEffort) {
        $blocker = 'Effective model/effort was not observable in the worker response'
    } elseif ($selfModel.ToLowerInvariant() -ne $script:FixedModel -or $selfEffort.ToLowerInvariant() -ne $script:FixedEffort) {
        $identity = 'FAIL'
        $blocker = "Worker self-report mismatch: model=$selfModel effort=$selfEffort"
    }

    $status = if ($identity -eq 'FAIL') { 'BLOCKED' } else { 'STARTED_UNVERIFIED' }
    $payload = [ordered]@{
        status = $status
        surface = 'HOST_MANAGED'
        task_id = $taskId
        receipt_kind = 'BROKER_RUN_RECEIPT'
        receipt_id = if ($threadId) { "sol-luna-broker:${taskId}:$threadId" } else { $null }
        thread_id = $threadId
        runtime = $runtime
        runtime_version = $runtimeVersion
        runtime_sha256 = $runtimeHash
        requested_model = $script:FixedModel
        requested_effort = $script:FixedEffort
        host_observed_model = $null
        host_observed_effort = $null
        self_reported_model = $selfModel
        self_reported_effort = $selfEffort
        identity_proof_kind = 'SELF_REPORT_ONLY'
        fresh = $true
        history = 'EXCLUDED'
        sandbox = $sandbox
        exit_code = $run.exit_code
        timed_out = $run.timed_out
        identity = $identity
        blocker = $blocker
        output = $text
        stderr_summary = @(Get-ShortStderr $run.stderr)
    }
    return (New-ToolResult -Payload $payload -IsError:($identity -eq 'FAIL'))
}

function Get-ToolList {
    $tool = [ordered]@{
        name = 'sol_luna_exec'
        description = 'Launch a fresh ephemeral Codex CLI worker fixed to gpt-5.6-luna/max. Returns a broker receipt; identity remains unverified without host telemetry.'
        inputSchema = [ordered]@{
            type = 'object'
            additionalProperties = $false
            required = @('task_id', 'workdir', 'prompt')
            properties = [ordered]@{
                task_id = @{ type = 'string'; pattern = '^[A-Za-z0-9._-]{1,128}$' }
                workdir = @{ type = 'string' }
                prompt = @{ type = 'string'; maxLength = 20000 }
                sandbox = @{ type = 'string'; enum = @('read-only', 'workspace-write'); default = 'read-only' }
                handshake_only = @{ type = 'boolean'; default = $true }
            }
        }
    }
    $list = [System.Collections.ArrayList]::new()
    [void]$list.Add($tool)
    return ,$list
}

function Get-InitializeResult {
    return [ordered]@{
        protocolVersion = '2024-11-05'
        capabilities = @{ tools = @{ listChanged = $false } }
        serverInfo = @{ name = $script:BrokerName; version = $script:BrokerVersion }
        instructions = 'sol_luna_exec always launches fresh gpt-5.6-luna/max. Run handshake_only=true first. A BROKER_RUN_RECEIPT and worker self-report never satisfy HOST_VERIFIED without host-observed identity telemetry.'
    }
}

while ($null -ne ($line = [Console]::In.ReadLine())) {
    if ([String]::IsNullOrWhiteSpace($line)) { continue }
    $hasId = $false
    $id = $null
    try {
        $request = $line | ConvertFrom-Json
        $idProperty = $request.PSObject.Properties['id']
        $hasId = $null -ne $idProperty
        if ($hasId) { $id = $idProperty.Value }
        $method = Get-TextProperty $request 'method'
        switch ($method) {
            'initialize' {
                if ($hasId) { Send-Result -Id $id -Result (Get-InitializeResult) }
            }
            'notifications/initialized' { }
            'ping' {
                if ($hasId) { Send-Result -Id $id -Result @{} }
            }
            'tools/list' {
                if ($hasId) { Send-Result -Id $id -Result ([ordered]@{ tools = (Get-ToolList) }) }
            }
            'tools/call' {
                if (-not $hasId) { continue }
                try {
                    $paramsProperty = $request.PSObject.Properties['params']
                    if (-not $paramsProperty) { throw 'params is required' }
                    $params = $paramsProperty.Value
                    $name = Get-TextProperty $params 'name'
                    if ($name -ne 'sol_luna_exec') { throw "Unknown tool: $name" }
                    $argumentsProperty = $params.PSObject.Properties['arguments']
                    if (-not $argumentsProperty) { throw 'arguments is required' }
                    Send-Result -Id $id -Result (Invoke-LunaTool $argumentsProperty.Value)
                } catch {
                    Send-Result -Id $id -Result $_.Exception.Message -IsError
                }
            }
            default {
                if ($hasId) { Send-Result -Id $id -Result "Unsupported method: $method" -IsError }
            }
        }
    } catch {
        if ($hasId) { Send-Result -Id $id -Result $_.Exception.Message -IsError }
    }
}
