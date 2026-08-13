#!/usr/bin/env pwsh

[CmdletBinding()]
param(
    [switch]$Worker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:BrokerName = 'sol-luna-broker'
$script:BrokerVersion = '1.1.0'
$script:BrokerScriptPath = $PSCommandPath
$script:FixedModel = 'gpt-5.6-luna'
$script:FixedEffort = 'max'
$script:CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$script:LocalHostName = [string]$env:COMPUTERNAME
$script:LocalUserName = [string]$env:USERNAME
$script:AsyncChildren = @{}
$script:Transport = if ($env:SOL_LUNA_TRANSPORT) { $env:SOL_LUNA_TRANSPORT.ToLowerInvariant() } else { 'app-server' }
if ($script:Transport -notin @('app-server', 'cli')) {
    throw 'SOL_LUNA_TRANSPORT must be app-server or cli'
}

function Protect-OutputText {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Text
    )

    if ($null -eq $Text) { return $null }
    $safe = $Text
    # Keep evidence useful while hiding local usernames, host names, and
    # credential-shaped values before anything crosses the MCP boundary.
    $safe = [regex]::Replace($safe, '(?i)([A-Z]:\\Users\\)[^\\\r\n]+', '$1<user>')
    $safe = [regex]::Replace($safe, '(?i)(/home/)[^/\r\n]+', '$1<user>')
    $safe = [regex]::Replace($safe, '(?i)\bDESKTOP-[A-Z0-9-]+\b', '<host>')
    if ($script:LocalHostName) {
        $safe = [regex]::Replace($safe, "(?i)(?<![A-Za-z0-9_-])$([regex]::Escape($script:LocalHostName))(?![A-Za-z0-9_-])", '<host>')
    }
    if ($script:LocalUserName) {
        $safe = [regex]::Replace($safe, "(?i)(?<![A-Za-z0-9_-])$([regex]::Escape($script:LocalUserName))(?![A-Za-z0-9_-])", '<user>')
    }
    $safe = [regex]::Replace($safe, '(?i)\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+', '$1 <redacted>')
    $safe = [regex]::Replace($safe, '(?i)\b(api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|passwd|secret)\b\s*[:=]\s*["'']?[^\s,;]+["'']?', '$1=<redacted>')
    return $safe
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
                message = Protect-OutputText ([string]$Result)
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

function Get-IntegerProperty {
    param(
        [Parameter(Mandatory = $true)] [object] $Object,
        [Parameter(Mandatory = $true)] [string] $Name,
        [int] $Default = 0
    )

    $property = $Object.PSObject.Properties[$Name]
    if (-not $property -or $null -eq $property.Value) { return $Default }
    $parsed = 0
    if (-not [int]::TryParse([string]$property.Value, [ref]$parsed)) {
        throw "$Name must be an integer"
    }
    return $parsed
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
    if (-not $env:SOL_LUNA_ALLOWED_ROOTS) {
        throw 'SOL_LUNA_ALLOWED_ROOTS must be configured; no implicit filesystem roots are used'
    }
    $raw = $env:SOL_LUNA_ALLOWED_ROOTS

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

function Get-AppServerExecutionFailure {
    param(
        [AllowNull()] [AllowEmptyString()] [string] $Text,
        [AllowNull()] [AllowEmptyString()] [string] $Stderr
    )

    $evidence = @($Text, $Stderr) -join "`n"
    if ($evidence -match '(?i)SetNamedSecurityInfoW\s+failed\s*:\s*5\b') {
        return [ordered]@{
            code = 'WINDOWS_SANDBOX_ACL_FAILED'
            blocker = 'Windows sandbox ACL setup failed with access denied'
        }
    }
    if ($evidence -match '(?i)(CreateProcessAsUserW\s+failed\s*:\s*5\b|Windows sandbox denied process creation|command could not execute)') {
        return [ordered]@{
            code = 'PROCESS_CREATION_DENIED'
            blocker = 'Windows sandbox denied process creation'
        }
    }
    return $null
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
        $stderr = $stderrTask.Result
        $executionFailure = Get-AppServerExecutionFailure -Text '' -Stderr $stderr
        return [ordered]@{
            exit_code = 1; timed_out = $false; events = @(); raw_lines = @(); thread_id = $null
            host_model = $null; host_effort = $null; host_launch_record = $false; rerouted = @()
            execution_status = 'BLOCKED'
            execution_blocker_code = if ($executionFailure) { $executionFailure.code } else { 'APP_SERVER_INITIALIZE_FAILED' }
            execution_blocker = if ($executionFailure) { $executionFailure.blocker } else { 'Codex app-server initialization failed' }
            text = ''; stderr = $stderr
        }
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
    $executionFailure = Get-AppServerExecutionFailure -Text $text -Stderr $stderr
    $executionStatus = 'BLOCKED'
    $executionBlockerCode = $null
    $executionBlocker = $null
    if ($timedOut) {
        $executionBlockerCode = 'BROKER_TIMEOUT'
        $executionBlocker = 'Codex app-server exceeded the broker timeout'
    } elseif ($executionFailure) {
        $executionBlockerCode = $executionFailure.code
        $executionBlocker = $executionFailure.blocker
    } elseif ($turnError) {
        $executionBlockerCode = 'TURN_ERROR'
        $executionBlocker = "Codex turn failed: $turnError"
    } elseif ($null -eq $turnCompletedEvent -or $turnStatus -ne 'completed') {
        $executionBlockerCode = 'TURN_NOT_COMPLETED'
        $executionBlocker = 'Codex app-server turn did not complete successfully'
    } else {
        $executionStatus = 'COMPLETED'
    }
    $exitCode = if ($timedOut) { $null } elseif ($executionStatus -eq 'COMPLETED') { 0 } else { 1 }
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
        execution_status = $executionStatus
        execution_blocker_code = $executionBlockerCode
        execution_blocker = $executionBlocker
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

    $lines = @($Stderr -split "`r?`n" | Where-Object { $_ -and $_.Length -lt 500 } | ForEach-Object { Protect-OutputText $_ })
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

function Get-JobRoot {
    $root = if ($env:SOL_LUNA_JOB_ROOT) {
        $env:SOL_LUNA_JOB_ROOT
    } else {
        Join-Path ([System.IO.Path]::GetTempPath()) 'sol-luna-broker'
    }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($root) | Out-Null
    }
    return (Resolve-Path -LiteralPath $root).Path.TrimEnd('\')
}

function Write-JobStateAtomic {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [object] $State
    )

    $tempPath = "$Path.$PID.tmp"
    $json = $State | ConvertTo-Json -Compress -Depth 60
    [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
}

function Read-JobState {
    param([Parameter(Mandatory = $true)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json) }
    catch { return $null }
}

function Start-AsyncLunaJob {
    param([Parameter(Mandatory = $true)] [object] $Arguments)

    $taskId = Get-TextProperty $Arguments 'task_id'
    $jobId = [Guid]::NewGuid().ToString('N')
    $jobRoot = Get-JobRoot
    $jobPath = Join-Path $jobRoot "$jobId.json"
    $receiptId = "sol-luna-broker:${taskId}:$jobId"
    $startedAt = [DateTime]::UtcNow.ToString('o')
    $initialState = [ordered]@{
        schema = 1
        status = 'QUEUED'
        task_id = $taskId
        job_id = $jobId
        receipt_id = $receiptId
        receipt_kind = 'HOST_JOB_RECEIPT'
        submitted_at = $startedAt
        updated_at = $startedAt
        pid = $null
        result = $null
        error = $null
    }
    Write-JobStateAtomic -Path $jobPath -State $initialState

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = Join-Path $PSHOME 'pwsh.exe'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:BrokerScriptPath, '-Worker')) {
        $psi.ArgumentList.Add([string]$argument)
    }
    $psi.Environment['SOL_LUNA_WORKER_JOB_FILE'] = $jobPath
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    if (-not $process.Start()) {
        $initialState.status = 'FAILED'
        $initialState.error = 'Worker process failed to start'
        $initialState.updated_at = [DateTime]::UtcNow.ToString('o')
        Write-JobStateAtomic -Path $jobPath -State $initialState
        throw 'Failed to start asynchronous Luna worker'
    }

    $initialState.pid = $process.Id
    $initialState.status = 'RUNNING'
    $initialState.updated_at = [DateTime]::UtcNow.ToString('o')
    Write-JobStateAtomic -Path $jobPath -State $initialState
    $childArguments = [ordered]@{}
    foreach ($property in $Arguments.PSObject.Properties) {
        if ($property.Name -ne 'execution_mode') { $childArguments[$property.Name] = $property.Value }
    }
    $childArguments.execution_mode = 'sync'
    $process.StandardInput.WriteLine(($childArguments | ConvertTo-Json -Compress -Depth 40))
    $process.StandardInput.Close()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $script:AsyncChildren[$jobId] = [ordered]@{ process = $process; stdout = $stdoutTask; stderr = $stderrTask }

    return (New-ToolResult -Payload ([ordered]@{
        status = 'QUEUED'
        surface = 'HOST_MANAGED'
        task_id = $taskId
        transport = $script:Transport
        execution_mode = 'async'
        receipt_kind = 'HOST_JOB_RECEIPT'
        receipt_id = $receiptId
        job_id = $jobId
        poll_tool = 'sol_luna_poll'
        submitted_at = $startedAt
        requested_model = $script:FixedModel
        requested_effort = $script:FixedEffort
        fresh = $true
        history = 'EXCLUDED'
        identity = 'PENDING'
        execution_status = 'PENDING'
        execution_blocker_code = $null
        execution_blocker = $null
        blocker = 'Worker is running asynchronously; poll the task-bound job receipt for the result'
        redaction = [ordered]@{
            status = 'APPLIED'
            scope = 'MCP output only'
            local_paths = 'user-home redacted'
            host_names = 'DESKTOP-* redacted'
            credential_like_values = 'redacted'
        }
    }))
}

function Invoke-PollTool {
    param([Parameter(Mandatory = $true)] [object] $Arguments)

    $taskId = Get-TextProperty $Arguments 'task_id'
    $jobId = Get-TextProperty $Arguments 'job_id'
    $waitSeconds = Get-IntegerProperty $Arguments 'wait_seconds' 0
    if (-not $taskId -or $taskId -notmatch '^[A-Za-z0-9._-]{1,128}$') {
        throw 'task_id must match ^[A-Za-z0-9._-]{1,128}$'
    }
    if (-not $jobId -or $jobId -notmatch '^[a-f0-9]{32}$') { throw 'job_id must be a 32-character hexadecimal id' }
    if ($waitSeconds -lt 0 -or $waitSeconds -gt 30) { throw 'wait_seconds must be an integer from 0 to 30' }

    $jobPath = Join-Path (Get-JobRoot) "$jobId.json"
    $deadline = [DateTime]::UtcNow.AddSeconds($waitSeconds)
    $state = $null
    do {
        $state = Read-JobState -Path $jobPath
        if ($state -and [string]$state.task_id -ne $taskId) { throw 'job receipt does not match task_id' }
        if ($state -and [string]$state.status -notin @('QUEUED', 'RUNNING')) { break }
        if ($state -and $state.pid -and -not (Get-Process -Id ([int]$state.pid) -ErrorAction SilentlyContinue)) {
            $state = [ordered]@{
                schema = 1; status = 'FAILED'; task_id = $taskId; job_id = $jobId
                receipt_id = [string]$state.receipt_id; receipt_kind = 'HOST_JOB_RECEIPT'
                submitted_at = [string]$state.submitted_at; updated_at = [DateTime]::UtcNow.ToString('o')
                pid = [int]$state.pid; result = $null; error = 'Worker exited without a task-bound result'
            }
            Write-JobStateAtomic -Path $jobPath -State $state
            break
        }
        if ([DateTime]::UtcNow -ge $deadline) { break }
        Start-Sleep -Milliseconds 250
    } while ($true)

    if ($null -eq $state) { throw 'job receipt was not found' }
    $status = [string]$state.status
    $completedPayload = if ($status -eq 'COMPLETED' -and $state.result -and $state.result.structuredContent) { $state.result.structuredContent } else { $null }
    $payload = [ordered]@{
        status = if ($status -eq 'COMPLETED') { 'COMPLETED' } elseif ($status -eq 'FAILED') { 'FAILED' } else { 'PENDING' }
        surface = 'HOST_MANAGED'
        task_id = $taskId
        execution_mode = 'async'
        receipt_kind = [string]$state.receipt_kind
        receipt_id = [string]$state.receipt_id
        job_id = $jobId
        submitted_at = [string]$state.submitted_at
        updated_at = [string]$state.updated_at
        fresh = $true
        history = 'EXCLUDED'
        identity = if ($completedPayload) { [string]$completedPayload.identity } else { 'PENDING' }
        execution_status = if ($completedPayload) { Get-TextProperty $completedPayload 'execution_status' } elseif ($status -eq 'FAILED') { 'BLOCKED' } else { 'PENDING' }
        execution_blocker_code = if ($completedPayload) { Get-TextProperty $completedPayload 'execution_blocker_code' } elseif ($status -eq 'FAILED') { 'BROKER_WORKER_FAILED' } else { $null }
        execution_blocker = if ($completedPayload) { Protect-OutputText (Get-TextProperty $completedPayload 'execution_blocker') } elseif ($status -eq 'FAILED') { Protect-OutputText ([string]$state.error) } else { $null }
        requested_model = $script:FixedModel
        requested_effort = $script:FixedEffort
        result = $state.result
        blocker = if ($status -eq 'FAILED') { Protect-OutputText ([string]$state.error) } elseif ($status -in @('QUEUED', 'RUNNING')) { 'Worker is still running; poll again with the same task_id and job_id' } else { $null }
        redaction = [ordered]@{
            status = 'APPLIED'
            scope = 'MCP output only'
            local_paths = 'user-home redacted'
            host_names = 'DESKTOP-* redacted'
            credential_like_values = 'redacted'
        }
    }
    return (New-ToolResult -Payload $payload -IsError:($status -eq 'FAILED'))
}

function Invoke-LunaTool {
    param([Parameter(Mandatory = $true)] [object] $Arguments)

    $taskId = Get-TextProperty $Arguments 'task_id'
    $workdirInput = Get-TextProperty $Arguments 'workdir'
    $prompt = Get-TextProperty $Arguments 'prompt'
    $sandbox = Get-TextProperty $Arguments 'sandbox'
    if (-not $sandbox) { $sandbox = 'read-only' }
    $handshakeOnly = Get-BoolProperty $Arguments 'handshake_only' $true
    $executionMode = Get-TextProperty $Arguments 'execution_mode'
    if (-not $executionMode) { $executionMode = 'sync' }

    if (-not $taskId -or $taskId -notmatch '^[A-Za-z0-9._-]{1,128}$') {
        throw 'task_id must match ^[A-Za-z0-9._-]{1,128}$'
    }
    if (-not $workdirInput) { throw 'workdir is required' }
    if (-not $prompt -or $prompt.Length -gt 20000) { throw 'prompt is required and must be <= 20000 characters' }
    if ($sandbox -notin @('read-only', 'workspace-write')) { throw 'sandbox must be read-only or workspace-write' }
    if ($handshakeOnly -and $sandbox -ne 'read-only') { throw 'handshake_only requires read-only sandbox' }
    if ($executionMode -notin @('sync', 'async')) { throw 'execution_mode must be sync or async' }
    if ($executionMode -eq 'async' -and $handshakeOnly) {
        throw 'async execution is for implementation packets; run the identity-only handshake synchronously first'
    }

    $workdir = Resolve-AllowedWorkdir $workdirInput
    if ($executionMode -eq 'async') {
        return (Start-AsyncLunaJob -Arguments $Arguments)
    }
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
    $identityBlocker = 'Self-report matches, but no host-observed identity telemetry was returned'
    $executionStatus = if ($run.timed_out -or $run.exit_code -ne 0) { 'BLOCKED' } else { 'COMPLETED' }
    $executionBlockerCode = if ($run.timed_out) { 'BROKER_TIMEOUT' } elseif ($run.exit_code -ne 0) { 'RUNTIME_EXIT_NONZERO' } else { $null }
    $executionBlocker = if ($run.timed_out) { 'Codex runtime exceeded the broker timeout' } elseif ($run.exit_code -ne 0) { "Codex runtime exited with code $($run.exit_code)" } else { $null }
    if ($script:Transport -eq 'app-server') {
        $hostObservedModel = $run.host_model
        $hostObservedEffort = $run.host_effort
        $identityProofKind = 'ROLE_MAPPING_AND_LAUNCH_RECORD'
        $receiptKind = 'HOST_LAUNCH_RECORD'
        $executionStatus = [string]$run.execution_status
        $executionBlockerCode = $run.execution_blocker_code
        $executionBlocker = $run.execution_blocker
        if (@($run.rerouted).Count -gt 0) {
            $identity = 'FAIL'
            $identityBlocker = 'Host emitted model/rerouted during the Luna turn'
        } elseif (-not $run.host_launch_record) {
            $identity = 'FAIL'
            $identityBlocker = "Host launch record did not match requested model/effort: model=$hostObservedModel effort=$hostObservedEffort"
        } else {
            $identity = 'VERIFIED'
            $identityBlocker = 'Fresh app-server launch record matched gpt-5.6-luna/max and no host reroute was observed'
        }
    } elseif ($selfModel -and $selfModel.ToLowerInvariant() -ne $script:FixedModel) {
        $identity = 'FAIL'
        $identityBlocker = "Worker self-report mismatch: model=$selfModel effort=$selfEffort"
    } elseif ($selfEffort -and $selfEffort.ToLowerInvariant() -ne $script:FixedEffort) {
        $identity = 'FAIL'
        $identityBlocker = "Worker self-report mismatch: model=$selfModel effort=$selfEffort"
    } elseif (-not $selfModel -or -not $selfEffort) {
        $identityBlocker = 'Effective model/effort was not observable in the worker response'
    }

    $status = if ($identity -eq 'VERIFIED' -and $executionStatus -eq 'COMPLETED') { 'HOST_VERIFIED' } elseif ($identity -eq 'FAIL' -or $executionStatus -eq 'BLOCKED') { 'BLOCKED' } else { 'STARTED_UNVERIFIED' }
    $blocker = if ($executionStatus -eq 'BLOCKED') { $executionBlocker } else { $identityBlocker }
    $blocker = Protect-OutputText $blocker
    $payload = [ordered]@{
        status = $status
        surface = 'HOST_MANAGED'
        task_id = $taskId
        transport = $script:Transport
        receipt_kind = $receiptKind
        receipt_id = if ($threadId) { "sol-luna-broker:${taskId}:$threadId" } else { $null }
        thread_id = $threadId
        runtime = Protect-OutputText $runtime
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
        execution_status = $executionStatus
        execution_blocker_code = $executionBlockerCode
        execution_blocker = Protect-OutputText $executionBlocker
        blocker = $blocker
        output = Protect-OutputText $text
        redaction = [ordered]@{
            status = 'APPLIED'
            scope = 'MCP output only'
            local_paths = 'user-home redacted'
            host_names = 'DESKTOP-* redacted'
            credential_like_values = 'redacted'
        }
        stderr_summary = @(Get-ShortStderr $run.stderr)
    }
    return (New-ToolResult -Payload $payload -IsError:($status -eq 'BLOCKED'))
}

function Get-ToolList {
    $tool = [ordered]@{
        name = 'sol_luna_exec'
        description = 'Launch a fresh ephemeral host-managed Codex worker fixed to gpt-5.6-luna/max. Use execution_mode=async for long-running implementation packets, then poll the task-bound job receipt with sol_luna_poll. The default app-server transport returns a task-bound launch record and rejects host reroutes; set SOL_LUNA_TRANSPORT=cli only for legacy diagnostic mode.'
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
                execution_mode = @{ type = 'string'; enum = @('sync', 'async'); default = 'sync' }
            }
        }
    }
    $pollTool = [ordered]@{
        name = 'sol_luna_poll'
        description = 'Poll a task-bound asynchronous Sol Luna job until it returns the worker result. The nested result carries the app-server launch record and HOST_VERIFIED/BLOCKED identity state.'
        inputSchema = [ordered]@{
            type = 'object'
            additionalProperties = $false
            required = @('task_id', 'job_id')
            properties = [ordered]@{
                task_id = @{ type = 'string'; pattern = '^[A-Za-z0-9._-]{1,128}$' }
                job_id = @{ type = 'string'; pattern = '^[a-f0-9]{32}$' }
                wait_seconds = @{ type = 'integer'; minimum = 0; maximum = 30; default = 0 }
            }
        }
    }
    $list = [System.Collections.ArrayList]::new()
    [void]$list.Add($tool)
    [void]$list.Add($pollTool)
    return ,$list
}

function Get-InitializeResult {
    return [ordered]@{
        protocolVersion = '2024-11-05'
        capabilities = @{ tools = @{ listChanged = $false } }
        serverInfo = @{ name = $script:BrokerName; version = $script:BrokerVersion }
        instructions = 'sol_luna_exec always launches fresh gpt-5.6-luna/max. Run handshake_only=true synchronously first. For implementation packets that may exceed an MCP caller deadline, set execution_mode=async and poll the returned job_id with sol_luna_poll. The nested result records host model/effort at thread/start and rejects model/rerouted events. Worker self-report is advisory; the legacy CLI transport remains STARTED_UNVERIFIED.'
    }
}

if ($Worker) {
    $jobPath = $env:SOL_LUNA_WORKER_JOB_FILE
    try {
        if (-not $jobPath) { throw 'SOL_LUNA_WORKER_JOB_FILE is required in worker mode' }
        $requestText = [Console]::In.ReadToEnd()
        $workerArguments = $requestText | ConvertFrom-Json
        $result = Invoke-LunaTool -Arguments $workerArguments
        $previous = Read-JobState -Path $jobPath
        $state = [ordered]@{
            schema = 1
            status = 'COMPLETED'
            task_id = Get-TextProperty $workerArguments 'task_id'
            job_id = if ($previous) { [string]$previous.job_id } else { $null }
            receipt_id = if ($previous) { [string]$previous.receipt_id } else { $null }
            receipt_kind = 'HOST_JOB_RECEIPT'
            submitted_at = if ($previous) { [string]$previous.submitted_at } else { $null }
            updated_at = [DateTime]::UtcNow.ToString('o')
            pid = $PID
            result = $result
            error = $null
        }
    } catch {
        $previous = if ($jobPath) { Read-JobState -Path $jobPath } else { $null }
        $state = [ordered]@{
            schema = 1
            status = 'FAILED'
            task_id = if ($previous) { [string]$previous.task_id } else { $null }
            job_id = if ($previous) { [string]$previous.job_id } else { $null }
            receipt_id = if ($previous) { [string]$previous.receipt_id } else { $null }
            receipt_kind = 'HOST_JOB_RECEIPT'
            submitted_at = if ($previous) { [string]$previous.submitted_at } else { $null }
            updated_at = [DateTime]::UtcNow.ToString('o')
            pid = $PID
            result = $null
            error = Protect-OutputText $_.Exception.Message
        }
    }
    if ($jobPath) { Write-JobStateAtomic -Path $jobPath -State $state }
    exit 0
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
                    $argumentsProperty = $params.PSObject.Properties['arguments']
                    if (-not $argumentsProperty) { throw 'arguments is required' }
                    if ($name -eq 'sol_luna_exec') {
                        Send-Result -Id $id -Result (Invoke-LunaTool $argumentsProperty.Value)
                    } elseif ($name -eq 'sol_luna_poll') {
                        Send-Result -Id $id -Result (Invoke-PollTool $argumentsProperty.Value)
                    } else {
                        throw "Unknown tool: $name"
                    }
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
