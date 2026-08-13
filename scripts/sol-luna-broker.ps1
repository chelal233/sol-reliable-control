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
$script:Transport = if ($env:SOL_LUNA_TRANSPORT) { $env:SOL_LUNA_TRANSPORT.ToLowerInvariant() } else { 'app-server' }
if ($script:Transport -notin @('app-server', 'cli')) {
    throw 'SOL_LUNA_TRANSPORT must be app-server or cli'
}

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

function Send-AppServerJson {
    param(
        [Parameter(Mandatory = $true)] [System.Diagnostics.Process] $Process,
        [Parameter(Mandatory = $true)] [object] $Value
    )

    $Process.StandardInput.WriteLine(($Value | ConvertTo-Json -Compress -Depth 40))
    $Process.StandardInput.Flush()
}

function Read-AppServerJson {
    param(
        [Parameter(Mandatory = $true)] [System.Diagnostics.Process] $Process,
        [Parameter(Mandatory = $true)] [int] $TimeoutMs
    )

    $task = $Process.StandardOutput.ReadLineAsync()
    if (-not $task.Wait($TimeoutMs)) { return $null }
    $line = $task.Result
    if ($null -eq $line) { return $null }
    try { return ($line | ConvertFrom-Json) } catch { return $null }
}

function Stop-AppServerProcess {
    param([Parameter(Mandatory = $true)] [System.Diagnostics.Process] $Process)

    if (-not $Process.HasExited) {
        try { $Process.Kill($true) } catch { try { $Process.Kill() } catch { } }
    }
    try { $Process.WaitForExit() } catch { }
}

function Get-AppServerMessageText {
    param([Parameter(Mandatory = $true)] [object[]] $Events)

    $texts = [System.Collections.Generic.List[string]]::new()
    foreach ($event in $Events) {
        $method = Get-TextProperty $event 'method'
        if ($method -eq 'item/completed') {
            $paramsProperty = $event.PSObject.Properties['params']
            if ($paramsProperty) {
                $itemProperty = $paramsProperty.Value.PSObject.Properties['item']
                if ($itemProperty) {
                    $item = $itemProperty.Value
                    $itemType = Get-TextProperty $item 'type'
                    if ($itemType -in @('agentMessage', 'agent_message')) {
                        $text = Get-TextProperty $item 'text'
                        if ($text) { $texts.Add($text) }
                    }
                }
            }
        }
        if ($method -eq 'turn/completed') {
            $paramsProperty = $event.PSObject.Properties['params']
            if (-not $paramsProperty) { continue }
            $turnProperty = $paramsProperty.Value.PSObject.Properties['turn']
            if (-not $turnProperty) { continue }
            $itemsProperty = $turnProperty.Value.PSObject.Properties['items']
            if (-not $itemsProperty) { continue }
            foreach ($item in @($itemsProperty.Value)) {
                $itemType = Get-TextProperty $item 'type'
                if ($itemType -in @('agentMessage', 'agent_message')) {
                    $text = Get-TextProperty $item 'text'
                    if ($text -and -not $texts.Contains($text)) { $texts.Add($text) }
                }
            }
        }
    }
    return ($texts -join "`n")
}

function Invoke-AppServerWorker {
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
    foreach ($argument in @('app-server', '--listen', 'stdio://', '--strict-config')) {
        $psi.ArgumentList.Add([string]$argument)
    }
    $psi.Environment['CODEX_HOME'] = $script:CodexHome
    $psi.Environment['SOL_LUNA_BROKER'] = "$($script:BrokerName)/$($script:BrokerVersion)"

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    if (-not $process.Start()) { throw "Failed to start Codex app-server: $RuntimePath" }
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $events = [System.Collections.Generic.List[object]]::new()
    $rawLines = [System.Collections.Generic.List[string]]::new()
    $timeoutMs = [int64](Get-TimeoutSeconds) * 1000
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $nextId = 1

    $initialize = [ordered]@{
        jsonrpc = '2.0'
        id = $nextId
        method = 'initialize'
        params = [ordered]@{
            clientInfo = [ordered]@{ name = 'sol-luna-broker'; title = 'Sol Luna broker'; version = $script:BrokerVersion }
            capabilities = @{}
        }
    }
    $nextId++
    Send-AppServerJson -Process $process -Value $initialize
    $initResponse = Read-AppServerJson -Process $process -TimeoutMs ([Math]::Min(30000, [int]$timeoutMs))
    $initError = if ($initResponse) { $initResponse.PSObject.Properties['error'] } else { $null }
    if ($null -eq $initResponse -or $null -ne $initError) {
        Stop-AppServerProcess $process
        return [ordered]@{ exit_code = 1; timed_out = $false; events = @(); raw_lines = @(); thread_id = $null; host_model = $null; host_effort = $null; host_launch_record = $false; rerouted = @(); text = ''; stderr = $stderrTask.Result }
    }

    Send-AppServerJson -Process $process -Value ([ordered]@{ jsonrpc = '2.0'; method = 'initialized'; params = @{} })
    $threadRequestId = $nextId
    $nextId++
    Send-AppServerJson -Process $process -Value ([ordered]@{
        jsonrpc = '2.0'
        id = $threadRequestId
        method = 'thread/start'
        params = [ordered]@{
            model = $script:FixedModel
            config = [ordered]@{ model_reasoning_effort = $script:FixedEffort }
            cwd = $Workdir
            ephemeral = $true
            allowProviderModelFallback = $false
            approvalPolicy = 'never'
            sandbox = $Sandbox
            sessionStartSource = 'startup'
            threadSource = 'sol-luna-broker'
        }
    })

    $startResponse = $null
    while ($null -eq $startResponse -and -not $process.HasExited) {
        $remaining = [int][Math]::Max(1, $timeoutMs - $watch.ElapsedMilliseconds)
        if ($remaining -le 0) { break }
        $event = Read-AppServerJson -Process $process -TimeoutMs $remaining
        if ($null -eq $event) { break }
        $events.Add($event)
        $rawLines.Add(($event | ConvertTo-Json -Compress -Depth 40))
        $idProperty = $event.PSObject.Properties['id']
        if ($idProperty -and [string]$idProperty.Value -eq [string]$threadRequestId) { $startResponse = $event }
    }

    $threadId = $null
    $hostModel = $null
    $hostEffort = $null
    $launchRecord = $false
    $startError = if ($startResponse) { $startResponse.PSObject.Properties['error'] } else { $null }
    if ($startResponse -and $null -eq $startError -and $startResponse.result) {
        $threadId = Get-TextProperty $startResponse.result.thread 'id'
        $hostModel = Normalize-ObservedValue (Get-TextProperty $startResponse.result 'model')
        $hostEffort = Normalize-ObservedValue (Get-TextProperty $startResponse.result 'reasoningEffort')
        $launchRecord = $threadId -and $hostModel -and $hostEffort -and
            $hostModel.ToLowerInvariant() -eq $script:FixedModel -and
            $hostEffort.ToLowerInvariant() -eq $script:FixedEffort
    }

    $turnCompletedEvent = $null
    if ($threadId -and -not $process.HasExited -and $watch.ElapsedMilliseconds -lt $timeoutMs) {
        $turnRequestId = $nextId
        $nextId++
        Send-AppServerJson -Process $process -Value ([ordered]@{
            jsonrpc = '2.0'
            id = $turnRequestId
            method = 'turn/start'
            params = [ordered]@{
                threadId = $threadId
                input = @([ordered]@{ type = 'text'; text = $Prompt })
                model = $script:FixedModel
                effort = $script:FixedEffort
            }
        })
        $turnCompleted = $false
        while (-not $turnCompleted -and -not $process.HasExited) {
            $remaining = [int][Math]::Max(1, $timeoutMs - $watch.ElapsedMilliseconds)
            if ($remaining -le 0) { break }
            $event = Read-AppServerJson -Process $process -TimeoutMs $remaining
            if ($null -eq $event) { break }
            $events.Add($event)
            $rawLines.Add(($event | ConvertTo-Json -Compress -Depth 40))
            if ((Get-TextProperty $event 'method') -eq 'turn/completed') {
                $turnCompletedEvent = $event
                $turnCompleted = $true
            }
        }
    }

    $timedOut = $watch.ElapsedMilliseconds -ge $timeoutMs
    $rerouted = @($events | Where-Object { (Get-TextProperty $_ 'method') -eq 'model/rerouted' })
    $text = Get-AppServerMessageText -Events $events.ToArray()
    Stop-AppServerProcess $process
    $stderr = $stderrTask.Result
    $turnStatus = $null
    $turnError = $null
    if ($turnCompletedEvent) {
        $turnProperty = $turnCompletedEvent.PSObject.Properties['params']
        if ($turnProperty) {
            $turn = $turnProperty.Value.PSObject.Properties['turn']
            if ($turn) {
                $turnStatus = Get-TextProperty $turn.Value 'status'
                $turnError = Get-TextProperty $turn.Value 'error'
            }
        }
    }
    $turnSucceeded = $null -ne $turnCompletedEvent -and $turnStatus -eq 'completed' -and -not $turnError
    $exitCode = if ($timedOut) { $null } elseif ($turnSucceeded) { 0 } else { 1 }
    return [ordered]@{
        exit_code = $exitCode
        timed_out = $timedOut
        events = $events.ToArray()
        raw_lines = $rawLines.ToArray()
        thread_id = $threadId
        host_model = $hostModel
        host_effort = $hostEffort
        host_launch_record = [bool]$launchRecord
        rerouted = $rerouted
        turn_completed = [bool]$turnCompletedEvent
        turn_status = $turnStatus
        turn_error = $turnError
        text = $text
        stderr = $stderr
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

function Normalize-ObservedValue {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $normalized = $Value.Trim()
    if ($normalized -match '^(?i:NOT[_ -]?OBSERVABLE|UNOBSERVABLE|UNKNOWN|N/?A|<[^>]+>)$') {
        return $null
    }
    return $normalized
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

    if ($script:Transport -eq 'app-server') {
        $run = Invoke-AppServerWorker -RuntimePath $runtime -Workdir $workdir -Prompt $guard -Sandbox $sandbox
        $text = [string]$run.text
        $threadId = $run.thread_id
        $events = @($run.events)
    } else {
        $run = Invoke-CodexWorker -RuntimePath $runtime -Workdir $workdir -Prompt $guard -Sandbox $sandbox
        $events = ConvertFrom-CodexEvents $run.stdout
        $text = Get-CodexMessageText $events
        $threadId = Get-ThreadId $events
    }

    $selfModel = Get-FirstField -Text $text -Field 'SELF_REPORTED_MODEL'
    if (-not $selfModel) { $selfModel = Get-FirstField -Text $text -Field 'MODEL' }
    if (-not $selfModel) { $selfModel = Get-FirstLabeledField -Text $text -Label 'Effective model' }
    $selfModel = Normalize-ObservedValue $selfModel
    $selfEffort = Get-FirstField -Text $text -Field 'SELF_REPORTED_EFFORT'
    if (-not $selfEffort) { $selfEffort = Get-FirstField -Text $text -Field 'EFFORT' }
    if (-not $selfEffort) { $selfEffort = Get-FirstLabeledField -Text $text -Label 'Effort' }
    $selfEffort = Normalize-ObservedValue $selfEffort

    $hostObservedModel = $null
    $hostObservedEffort = $null
    $identityProofKind = 'SELF_REPORT_ONLY'
    $receiptKind = 'BROKER_RUN_RECEIPT'
    $identity = 'UNVERIFIED'
    $blocker = 'Self-report matches, but no host-observed identity telemetry was returned'
    $status = 'STARTED_UNVERIFIED'
    if ($script:Transport -eq 'app-server') {
        $hostObservedModel = $run.host_model
        $hostObservedEffort = $run.host_effort
        $identityProofKind = 'ROLE_MAPPING_AND_LAUNCH_RECORD'
        $receiptKind = 'HOST_LAUNCH_RECORD'
        if ($run.timed_out) {
            $identity = 'FAIL'
            $status = 'BLOCKED'
            $blocker = 'Codex app-server exceeded the broker timeout'
        } elseif ($run.exit_code -ne 0) {
            $identity = 'FAIL'
            $status = 'BLOCKED'
            $blocker = if ($run.turn_error) { "Codex turn failed: $($run.turn_error)" } else { 'Codex app-server turn did not complete successfully' }
        } elseif (@($run.rerouted).Count -gt 0) {
            $identity = 'FAIL'
            $status = 'BLOCKED'
            $blocker = 'Host emitted model/rerouted during the Luna turn'
        } elseif (-not $run.host_launch_record) {
            $identity = 'FAIL'
            $status = 'BLOCKED'
            $blocker = "Host launch record did not match requested model/effort: model=$hostObservedModel effort=$hostObservedEffort"
        } else {
            $identity = 'VERIFIED'
            $status = 'HOST_VERIFIED'
            $blocker = 'Fresh app-server launch record matched gpt-5.6-luna/max and no host reroute was observed'
        }
    } elseif ($run.timed_out) {
        $identity = 'FAIL'
        $status = 'BLOCKED'
        $blocker = 'Codex runtime exceeded the broker timeout'
    } elseif ($run.exit_code -ne 0) {
        $identity = 'FAIL'
        $status = 'BLOCKED'
        $blocker = "Codex runtime exited with code $($run.exit_code)"
    } elseif ($selfModel -and $selfModel.ToLowerInvariant() -ne $script:FixedModel) {
        $identity = 'FAIL'
        $status = 'BLOCKED'
        $blocker = "Worker self-report mismatch: model=$selfModel effort=$selfEffort"
    } elseif ($selfEffort -and $selfEffort.ToLowerInvariant() -ne $script:FixedEffort) {
        $identity = 'FAIL'
        $status = 'BLOCKED'
        $blocker = "Worker self-report mismatch: model=$selfModel effort=$selfEffort"
    } elseif (-not $selfModel -or -not $selfEffort) {
        $blocker = 'Effective model/effort was not observable in the worker response'
    }

    $payload = [ordered]@{
        status = $status
        surface = 'HOST_MANAGED'
        task_id = $taskId
        transport = $script:Transport
        receipt_kind = $receiptKind
        receipt_id = if ($threadId) { "sol-luna-broker:${taskId}:$threadId" } else { $null }
        thread_id = $threadId
        runtime = $runtime
        runtime_version = $runtimeVersion
        runtime_sha256 = $runtimeHash
        requested_model = $script:FixedModel
        requested_effort = $script:FixedEffort
        host_observed_model = $hostObservedModel
        host_observed_effort = $hostObservedEffort
        self_reported_model = $selfModel
        self_reported_effort = $selfEffort
        identity_proof_kind = $identityProofKind
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
        description = 'Launch a fresh ephemeral host-managed Codex worker fixed to gpt-5.6-luna/max. The default app-server transport returns a task-bound launch record and rejects host reroutes; set SOL_LUNA_TRANSPORT=cli only for legacy diagnostic mode.'
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
        instructions = 'sol_luna_exec always launches fresh gpt-5.6-luna/max. The default app-server transport records host model/effort at thread/start and rejects model/rerouted events. Run handshake_only=true first. Worker self-report is advisory; the legacy CLI transport remains STARTED_UNVERIFIED.'
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
