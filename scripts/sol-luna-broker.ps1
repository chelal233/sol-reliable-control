#!/usr/bin/env pwsh

[CmdletBinding()]
param(
    [switch]$Worker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:BrokerName = 'sol-luna-broker'
$script:BrokerVersion = '1.3.0'
$script:BrokerScriptPath = $PSCommandPath
$script:FixedModel = 'gpt-5.6-luna'
$script:FixedEffort = 'max'
$script:UserHome = if ($env:USERPROFILE) { [string]$env:USERPROFILE } elseif ($env:HOME) { [string]$env:HOME } else { [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile) }
if (-not $script:UserHome) { $script:UserHome = [System.IO.Path]::GetTempPath() }
$script:CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $script:UserHome '.codex' }
$script:LocalHostName = if ($env:COMPUTERNAME) { [string]$env:COMPUTERNAME } else { [Environment]::MachineName }
$script:LocalUserName = if ($env:USERNAME) { [string]$env:USERNAME } else { [Environment]::UserName }
$script:AsyncChildren = @{}
$script:Transport = if ($env:SOL_LUNA_TRANSPORT) { $env:SOL_LUNA_TRANSPORT.ToLowerInvariant() } else { 'app-server' }
if ($script:Transport -notin @('app-server', 'cli')) {
    throw 'SOL_LUNA_TRANSPORT must be app-server or cli'
}

function Get-PathSeparators {
    return [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Trim-DirectorySeparators {
    param([Parameter(Mandatory = $true)] [string] $Path)
    $root = [System.IO.Path]::GetPathRoot($Path)
    $comparison = Get-PathComparison
    if ($root -and $Path.Equals($root, $comparison)) { return $root }
    $trimmed = $Path.TrimEnd((Get-PathSeparators))
    if (-not $trimmed -and $root) { return $root }
    return $trimmed
}

function Get-PathComparison {
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        return [StringComparison]::OrdinalIgnoreCase
    }
    return [StringComparison]::Ordinal
}

function Get-ConfiguredPathList {
    param([Parameter(Mandatory = $true)] [string] $Raw)
    $separator = [string][System.IO.Path]::PathSeparator
    return @($Raw -split [regex]::Escape($separator) | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Test-PathWithinRoot {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $Root
    )

    $comparison = Get-PathComparison
    if ($Path.Equals($Root, $comparison)) { return $true }
    foreach ($separator in (Get-PathSeparators)) {
        if ($Path.StartsWith($Root + [string]$separator, $comparison)) { return $true }
    }
    return $false
}

function Throw-BrokerDiagnostic {
    param(
        [Parameter(Mandatory = $true)] [string] $Code,
        [Parameter(Mandatory = $true)] [string] $Variable,
        [Parameter(Mandatory = $true)] [string] $Reason,
        [Parameter(Mandatory = $true)] [string] $Repair,
        [string] $Example,
        [string] $Path
    )

    $exception = [System.Exception]::new("$Code [$Variable] $Reason Fix: $Repair")
    $exception.Data['broker_error_code'] = $Code
    $exception.Data['configuration_variable'] = $Variable
    $exception.Data['reason'] = $Reason
    $exception.Data['repair'] = $Repair
    if ($Variable -eq 'SOL_LUNA_ALLOWED_ROOTS') {
        $exception.Data['path_separator'] = [string][System.IO.Path]::PathSeparator
        $exception.Data['reload_hint'] = 'Reload or restart the MCP server after changing SOL_LUNA_ALLOWED_ROOTS.'
    }
    if ($Example) { $exception.Data['example'] = $Example }
    if ($Path) { $exception.Data['path'] = $Path }
    throw $exception
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
    $safe = [regex]::Replace($safe, '(?<![:A-Za-z0-9/])/(?:[^/\r\n\s]+/)+[^/\r\n\s,;]+', '<path>')
    $safe = [regex]::Replace($safe, '(?i)\bDESKTOP-[A-Z0-9-]+\b', '<host>')
    if ($script:LocalHostName) {
        $safe = [regex]::Replace($safe, "(?i)(?<![A-Za-z0-9_-])$([regex]::Escape($script:LocalHostName))(?![A-Za-z0-9_-])", '<host>')
    }
    if ($script:LocalUserName) {
        $safe = [regex]::Replace($safe, "(?i)(?<![A-Za-z0-9_-])$([regex]::Escape($script:LocalUserName))(?![A-Za-z0-9_-])", '<user>')
    }
    $safe = [regex]::Replace($safe, '(?i)\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+', '$1 <redacted>')
    $safe = [regex]::Replace($safe, '(?i)\b(api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|passwd|secret)\b\s*[:=]\s*["'']?[^\s,;]+["'']?', '$1=<redacted>')
    $safe = [regex]::Replace($safe, '(?i)\b(?:sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})\b', '<redacted>')
    $safe = [regex]::Replace($safe, '(?i)\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b', '<redacted>')
    $safe = [regex]::Replace($safe, '(?ms)-----BEGIN\s+(?:RSA|OPENSSH|EC|DSA)?\s*PRIVATE KEY-----.*?-----END\s+(?:RSA|OPENSSH|EC|DSA)?\s*PRIVATE KEY-----', '<redacted>')
    $safe = [regex]::Replace($safe, '(?i)\\\\[^\s\\/]+\\[^\r\n\s]+', '<path>')
    $safe = [regex]::Replace($safe, '(?i)\b[A-Z]:\\(?!Users\\)[^\r\n\s,;]+', '<path>')
    return $safe
}

function Get-ConfiguredInteger {
    param(
        [Parameter(Mandatory = $true)] [string] $Name,
        [Parameter(Mandatory = $true)] [int] $Default,
        [Parameter(Mandatory = $true)] [int] $Minimum,
        [Parameter(Mandatory = $true)] [int] $Maximum
    )

    $value = [string]$Default
    $property = [System.Environment]::GetEnvironmentVariable($Name)
    if ($property) { $value = $property }
    $parsed = 0
    if (-not [int]::TryParse($value, [ref]$parsed) -or $parsed -lt $Minimum -or $parsed -gt $Maximum) {
        throw "$Name must be an integer from $Minimum to $Maximum"
    }
    return $parsed
}

function Get-MaxOutputBytes { return (Get-ConfiguredInteger -Name 'SOL_LUNA_MAX_OUTPUT_BYTES' -Default 1048576 -Minimum 4096 -Maximum 104857600) }
function Get-MaxEvents { return (Get-ConfiguredInteger -Name 'SOL_LUNA_MAX_EVENTS' -Default 20000 -Minimum 100 -Maximum 1000000) }
function Get-MaxAsyncJobs { return (Get-ConfiguredInteger -Name 'SOL_LUNA_MAX_ASYNC_JOBS' -Default 4 -Minimum 1 -Maximum 64) }
function Get-JobRetentionSeconds { return (Get-ConfiguredInteger -Name 'SOL_LUNA_JOB_RETENTION_SECONDS' -Default 86400 -Minimum 300 -Maximum 2592000) }

function Get-TextByteCount {
    param([AllowNull()] [AllowEmptyString()] [string] $Text)
    if ($null -eq $Text) { return 0 }
    return [System.Text.Encoding]::UTF8.GetByteCount($Text)
}

function Test-TextLimit {
    param([AllowNull()] [AllowEmptyString()] [string] $Text)
    return ((Get-TextByteCount $Text) -le (Get-MaxOutputBytes))
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
        $errorValue = if ($Result -is [System.Management.Automation.ErrorRecord]) { $Result.Exception } else { $Result }
        $errorMessage = if ($errorValue -is [System.Exception]) { $errorValue.Message } else { [string]$errorValue }
        $errorData = [ordered]@{}
        if ($errorValue -is [System.Exception]) {
            foreach ($key in @('broker_error_code', 'configuration_variable', 'reason', 'repair', 'example', 'path', 'path_separator', 'reload_hint')) {
                if ($errorValue.Data.Contains($key)) {
                    $errorData[$key] = Protect-OutputText ([string]$errorValue.Data[$key])
                }
            }
        }
        Send-JsonLine ([ordered]@{
            jsonrpc = '2.0'
            id = $Id
            error = [ordered]@{
                code = -32000
                message = Protect-OutputText $errorMessage
                data = $errorData
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
    $configured = [string]$env:SOL_LUNA_RUNTIME_PATH
    if (-not $configured) {
        Throw-BrokerDiagnostic -Code 'SOL_LUNA_RUNTIME_PATH_MISSING' `
            -Variable 'SOL_LUNA_RUNTIME_PATH' `
            -Reason 'No Codex executable path or PATH command name was configured.' `
            -Repair 'Set SOL_LUNA_RUNTIME_PATH to an absolute executable path or a command name resolvable on PATH, then set SOL_LUNA_RUNTIME_SHA256 to its approved SHA-256.' `
            -Example 'SOL_LUNA_RUNTIME_PATH=codex (Unix/macOS) or codex.exe (Windows)'
    }

    $candidate = $null
    if (Test-Path -LiteralPath $configured -PathType Leaf) {
        $candidate = $configured
    } else {
        $command = Get-Command -Name $configured -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { $candidate = $command.Source }
    }
    if (-not $candidate -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        Throw-BrokerDiagnostic -Code 'SOL_LUNA_RUNTIME_PATH_INVALID' `
            -Variable 'SOL_LUNA_RUNTIME_PATH' `
            -Reason "The configured executable '$configured' is not an existing file or PATH-resolvable application." `
            -Repair 'Correct SOL_LUNA_RUNTIME_PATH, verify the executable is installed and executable, then recompute SOL_LUNA_RUNTIME_SHA256.' `
            -Example 'Use an absolute path or a command name such as codex/codex.exe.' `
            -Path $configured
    }
    $resolved = (Resolve-Path -LiteralPath $candidate).Path
    if (-not (Test-NoReparsePoints -Path $resolved)) {
        Throw-BrokerDiagnostic -Code 'SOL_LUNA_RUNTIME_REPARSE_POINT' `
            -Variable 'SOL_LUNA_RUNTIME_PATH' `
            -Reason 'The resolved Codex executable or one of its parent directories is a reparse point or symlink.' `
            -Repair 'Use the real executable path, or install the runtime in a non-reparse directory, then update the SHA-256 pin.' `
            -Path $resolved
    }
    return $resolved
}

function Test-NoReparsePoints {
    param([Parameter(Mandatory = $true)] [string] $Path)

    $current = Get-Item -LiteralPath $Path -Force
    while ($current) {
        if (($current.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $parentProperty = $current.PSObject.Properties['Parent']
        $parent = if ($parentProperty) { $parentProperty.Value } else { $null }
        if ($null -eq $parent -or $parent.FullName -eq $current.FullName) { break }
        $current = $parent
    }
    return $true
}

function Get-AllowedRoots {
    if (-not $env:SOL_LUNA_ALLOWED_ROOTS) {
        Throw-BrokerDiagnostic -Code 'SOL_LUNA_ALLOWED_ROOTS_MISSING' `
            -Variable 'SOL_LUNA_ALLOWED_ROOTS' `
            -Reason 'No workspace roots were configured for a file-capable task.' `
            -Repair 'Set SOL_LUNA_ALLOWED_ROOTS to one or more dedicated workspace roots. Use the platform path separator: ; on Windows, : on Unix/macOS. Do not use a filesystem root or an entire user profile.' `
            -Example 'Windows: E:\Sources\.codex-worktrees;E:\git\repo | Unix/macOS: /srv/codex/worktrees:/workspace/repo'
    }
    $raw = $env:SOL_LUNA_ALLOWED_ROOTS

    $roots = @(Get-ConfiguredPathList -Raw $raw | ForEach-Object {
        if (-not (Test-Path -LiteralPath $_ -PathType Container)) {
            Throw-BrokerDiagnostic -Code 'SOL_LUNA_ALLOWED_ROOT_INVALID_ROOT' `
                -Variable 'SOL_LUNA_ALLOWED_ROOTS' `
                -Reason "Configured workspace root '$_' does not exist or is not a directory." `
                -Repair 'Create the dedicated workspace root or correct SOL_LUNA_ALLOWED_ROOTS, then restart/reload the MCP server.' `
                -Example 'Use an existing repository/worktree parent, not the filesystem root.' `
                -Path $_
        }
        $resolvedRootRaw = (Resolve-Path -LiteralPath $_).Path
        $rootItem = Get-Item -LiteralPath $resolvedRootRaw -Force
        $rootFullName = [string]$rootItem.FullName
        $filesystemRoot = if ($rootItem.PSObject.Properties['Root']) { [string]$rootItem.Root.FullName } else { [string][System.IO.Path]::GetPathRoot($rootFullName) }
        $comparison = Get-PathComparison
        $userHomeResolved = if ($script:UserHome -and (Test-Path -LiteralPath $script:UserHome -PathType Container)) { (Resolve-Path -LiteralPath $script:UserHome).Path } else { $null }
        if ($rootFullName.Equals($filesystemRoot, $comparison) -or ($userHomeResolved -and $rootFullName.Equals($userHomeResolved, $comparison))) {
            Throw-BrokerDiagnostic -Code 'SOL_LUNA_ALLOWED_ROOT_TOO_BROAD' `
                -Variable 'SOL_LUNA_ALLOWED_ROOTS' `
                -Reason "Configured workspace root '$rootFullName' is a filesystem root or the entire user profile." `
                -Repair 'Use a dedicated repository/worktree parent instead of a drive root, filesystem root, or user profile.' `
                -Example 'Windows: E:\Sources\.codex-worktrees | Unix/macOS: /srv/codex/worktrees' `
                -Path $rootFullName
        }
        $resolvedRoot = Trim-DirectorySeparators -Path $rootFullName
        if (-not (Test-NoReparsePoints -Path $resolvedRoot)) {
            Throw-BrokerDiagnostic -Code 'SOL_LUNA_ALLOWED_ROOT_REPARSE_POINT' `
                -Variable 'SOL_LUNA_ALLOWED_ROOTS' `
                -Reason "Configured workspace root '$resolvedRoot' or one of its parents contains a reparse point or symlink." `
                -Repair 'Use a real directory path without symlink/junction traversal, then update SOL_LUNA_ALLOWED_ROOTS.' `
                -Path $resolvedRoot
        }
        $resolvedRoot
    })
    if ($roots.Count -eq 0) {
        Throw-BrokerDiagnostic -Code 'SOL_LUNA_ALLOWED_ROOTS_EMPTY' `
            -Variable 'SOL_LUNA_ALLOWED_ROOTS' `
            -Reason 'The configured path list contained no usable directories.' `
            -Repair 'Set at least one existing dedicated workspace root using the platform path separator.' `
            -Example 'Windows: E:\Sources\.codex-worktrees | Unix/macOS: /srv/codex/worktrees'
    }
    return $roots
}

function Resolve-AllowedWorkdir {
    param([Parameter(Mandatory = $true)] [string] $Workdir)

    if (-not (Test-Path -LiteralPath $Workdir -PathType Container)) {
        Throw-BrokerDiagnostic -Code 'SOL_LUNA_WORKDIR_MISSING' `
            -Variable 'workdir' `
            -Reason "The requested workdir '$Workdir' does not exist or is not a directory." `
            -Repair 'Create the task worktree first, or pass an existing repository/worktree directory under SOL_LUNA_ALLOWED_ROOTS.' `
            -Path $Workdir
    }
    $resolved = Trim-DirectorySeparators -Path (Resolve-Path -LiteralPath $Workdir).Path
    if (-not (Test-NoReparsePoints -Path $resolved)) {
        Throw-BrokerDiagnostic -Code 'SOL_LUNA_WORKDIR_REPARSE_POINT' `
            -Variable 'workdir' `
            -Reason "The requested workdir '$resolved' or one of its parents contains a reparse point or symlink." `
            -Repair 'Use the real repository/worktree path rather than a symlink or junction.' `
            -Path $resolved
    }
    $matches = @(Get-AllowedRoots | Where-Object { Test-PathWithinRoot -Path $resolved -Root $_ })
    if ($matches.Count -eq 0) {
        Throw-BrokerDiagnostic -Code 'SOL_LUNA_WORKDIR_OUTSIDE_ALLOWED_ROOTS' `
            -Variable 'SOL_LUNA_ALLOWED_ROOTS' `
            -Reason "The requested workdir '$resolved' is outside every configured allowed root." `
            -Repair 'Add the worktree parent to SOL_LUNA_ALLOWED_ROOTS using the platform path separator, or pass a workdir below an existing configured root; then reload the MCP server.' `
            -Example 'Windows: E:\Sources\.codex-worktrees;E:\git\repo | Unix/macOS: /srv/codex/worktrees:/workspace/repo' `
            -Path $resolved
    }
    return $resolved
}

function New-HandshakeWorkdir {
    $tempRoot = [System.IO.Path]::GetTempPath()
    if (-not (Test-Path -LiteralPath $tempRoot -PathType Container)) {
        Throw-BrokerDiagnostic -Code 'SOL_LUNA_HANDSHAKE_TEMP_UNAVAILABLE' `
            -Variable 'workdir' `
            -Reason "The platform temporary directory '$tempRoot' does not exist." `
            -Repair 'Create or configure a usable system temporary directory, then restart the MCP server.' `
            -Path $tempRoot
    }
    $resolvedTempRoot = Trim-DirectorySeparators -Path (Resolve-Path -LiteralPath $tempRoot).Path
    if (-not (Test-NoReparsePoints -Path $resolvedTempRoot)) {
        Throw-BrokerDiagnostic -Code 'SOL_LUNA_HANDSHAKE_TEMP_REPARSE_POINT' `
            -Variable 'workdir' `
            -Reason 'The platform temporary directory contains a reparse point or symlink.' `
            -Repair 'Configure the platform temporary directory as a real directory, then restart the MCP server.' `
            -Path $resolvedTempRoot
    }
    $name = "sol-luna-broker-handshake-$([Guid]::NewGuid().ToString('N'))"
    $created = Join-Path $resolvedTempRoot $name
    try {
        [System.IO.Directory]::CreateDirectory($created) | Out-Null
    } catch {
        Throw-BrokerDiagnostic -Code 'SOL_LUNA_HANDSHAKE_TEMP_CREATE_FAILED' `
            -Variable 'workdir' `
            -Reason "The broker could not create its private handshake directory '$created'." `
            -Repair 'Check the platform temporary directory permissions or provide an explicit workdir under SOL_LUNA_ALLOWED_ROOTS.' `
            -Path $created
    }
    if (-not (Test-NoReparsePoints -Path $created)) {
        Throw-BrokerDiagnostic -Code 'SOL_LUNA_HANDSHAKE_TEMP_REPARSE_POINT' `
            -Variable 'workdir' `
            -Reason 'The newly created handshake directory resolved through a reparse point or symlink.' `
            -Repair 'Use a real platform temporary directory or provide an explicit allowlisted workdir.' `
            -Path $created
    }
    return (Resolve-Path -LiteralPath $created).Path
}

function Get-PowerShellExecutable {
    $configured = [string]$env:SOL_LUNA_POWERSHELL_PATH
    if ($configured) {
        if (Test-Path -LiteralPath $configured -PathType Leaf) {
            return (Resolve-Path -LiteralPath $configured).Path
        }
        Throw-BrokerDiagnostic -Code 'SOL_LUNA_POWERSHELL_PATH_INVALID' `
            -Variable 'SOL_LUNA_POWERSHELL_PATH' `
            -Reason "The configured PowerShell executable '$configured' does not exist." `
            -Repair 'Set SOL_LUNA_POWERSHELL_PATH to pwsh/pwsh.exe, or remove it to use PATH discovery.' `
            -Path $configured
    }

    $candidates = @('pwsh', 'powershell')
    foreach ($name in $candidates) {
        $command = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
    }
    Throw-BrokerDiagnostic -Code 'SOL_LUNA_POWERSHELL_UNAVAILABLE' `
        -Variable 'SOL_LUNA_POWERSHELL_PATH' `
        -Reason 'No PowerShell executable was found for the asynchronous broker worker.' `
        -Repair 'Install PowerShell 7 and ensure pwsh is on PATH, or set SOL_LUNA_POWERSHELL_PATH to its executable.' `
        -Example 'Unix/macOS: /usr/bin/pwsh | Windows: C:\Program Files\PowerShell\7\pwsh.exe'
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

function Get-VerifiedRuntime {
    $path = Get-RuntimePath
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    $expected = [string]$env:SOL_LUNA_RUNTIME_SHA256
    if (-not $expected -or $expected -notmatch '^[A-Fa-f0-9]{64}$') {
        throw 'SOL_LUNA_RUNTIME_SHA256 must be configured with the approved Codex executable SHA-256'
    }
    if ($hash -ne $expected.ToUpperInvariant()) {
        throw 'SOL_LUNA_RUNTIME_HASH_MISMATCH'
    }
    return [ordered]@{ path = $path; sha256 = $hash }
}

function Invoke-CodexWorker {
    param(
        [Parameter(Mandatory = $true)] [string] $RuntimePath,
        [Parameter(Mandatory = $true)] [string] $Workdir,
        [Parameter(Mandatory = $true)] [string] $Prompt,
        [Parameter(Mandatory = $true)] [ValidateSet('read-only', 'workspace-write')] [string] $Sandbox,
        [bool] $HandshakeOnly = $false
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
            activity_violation = $null
            output_limited = $false
            read_failure_kind = 'TIMEOUT'
        }
    }

    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    $events = ConvertFrom-CodexEvents $stdout
    $activityViolation = if ($HandshakeOnly) { Get-AppServerActivityViolation -Events $events } else { $null }
    $outputLimited = -not (Test-TextLimit $stdout) -or -not (Test-TextLimit $stderr)

    return [ordered]@{
        exit_code = $process.ExitCode
        timed_out = $false
        stdout = $stdout
        stderr = $stderr
        activity_violation = $activityViolation
        output_limited = $outputLimited
        read_failure_kind = $null
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
    if (-not $task.Wait($TimeoutMs)) { return [ordered]@{ kind = 'TIMEOUT'; value = $null; raw = $null } }
    $line = $task.Result
    if ($null -eq $line) { return [ordered]@{ kind = 'EOF'; value = $null; raw = $null } }
    try {
        return [ordered]@{ kind = 'MESSAGE'; value = ($line | ConvertFrom-Json); raw = $line }
    } catch {
        return [ordered]@{ kind = 'PARSE_ERROR'; value = $null; raw = (Protect-OutputText $line) }
    }
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

function Get-NullableBoolProperty {
    param(
        [AllowNull()] [object] $Object,
        [Parameter(Mandatory = $true)] [string] $Name
    )

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if (-not $property -or $null -eq $property.Value) { return $null }
    $parsed = $false
    if ([bool]::TryParse([string]$property.Value, [ref]$parsed)) { return $parsed }
    return $null
}

function Get-FirstPropertyValue {
    param(
        [Parameter(Mandatory = $true)] [object[]] $Objects,
        [Parameter(Mandatory = $true)] [string[]] $Names
    )

    foreach ($object in $Objects) {
        if ($null -eq $object) { continue }
        foreach ($name in $Names) {
            $property = $object.PSObject.Properties[$name]
            if ($property -and $null -ne $property.Value) { return $property.Value }
        }
    }
    return $null
}

function Get-NullableBoolAny {
    param(
        [Parameter(Mandatory = $true)] [object[]] $Objects,
        [Parameter(Mandatory = $true)] [string[]] $Names
    )

    $value = Get-FirstPropertyValue -Objects $Objects -Names $Names
    if ($null -eq $value) { return $null }
    $parsed = $false
    if ([bool]::TryParse([string]$value, [ref]$parsed)) { return $parsed }
    return $null
}

function Get-AppServerActivityViolation {
    param([Parameter(Mandatory = $true)] [object[]] $Events)

    foreach ($event in $Events) {
        $method = Get-TextProperty $event 'method'
        if ($method -match '(?i)(command|file|mcp|tool|shell|terminal|patch|computer)') {
            return "host activity event: $method"
        }
        $itemProperty = $event.PSObject.Properties['item']
        if (-not $itemProperty) {
            $paramsProperty = $event.PSObject.Properties['params']
            if ($paramsProperty) { $itemProperty = $paramsProperty.Value.PSObject.Properties['item'] }
        }
        if ($itemProperty) {
            $itemType = Get-TextProperty $itemProperty.Value 'type'
            if ($itemType -match '(?i)(command|file|mcp|tool|shell|terminal|patch|computer)') {
                return "host activity item: $itemType"
            }
        }
    }
    return $null
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
    if ($evidence -match '(?i)(CreateProcessAsUserW\s+failed\s*:\s*5\b|Windows sandbox denied process creation|command could not execute|command blocked|PROCESS_CREATION_DENIED)') {
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
        [Parameter(Mandatory = $true)] [ValidateSet('read-only', 'workspace-write')] [string] $Sandbox,
        [bool] $HandshakeOnly = $false
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $RuntimePath
    $psi.WorkingDirectory = $Workdir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # app-server exposes strict-config but not the CLI-only ignore-user-config
    # or ignore-rules flags. Keep its request policy
    # explicit in thread/start instead of sending unsupported options.
    foreach ($argument in @('app-server', '--listen', 'stdio://', '--strict-config')) {
        $psi.ArgumentList.Add([string]$argument)
    }
    $psi.Environment['CODEX_HOME'] = $script:CodexHome
    $psi.Environment['SOL_LUNA_BROKER'] = "$($script:BrokerName)/$($script:BrokerVersion)"

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    if (-not $process.Start()) { throw 'Failed to start Codex app-server' }
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $events = [System.Collections.Generic.List[object]]::new()
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
    $initRead = Read-AppServerJson -Process $process -TimeoutMs ([Math]::Min(30000, [int]$timeoutMs))
    $initResponse = $initRead.value
    $initError = if ($initResponse) { $initResponse.PSObject.Properties['error'] } else { $null }
    if ($initRead.kind -ne 'MESSAGE' -or $null -eq $initResponse -or $null -ne $initError) {
        Stop-AppServerProcess $process
        $stderr = $stderrTask.Result
        $executionFailure = Get-AppServerExecutionFailure -Text $initRead.raw -Stderr $stderr
        return [ordered]@{
            exit_code = 1; timed_out = $false; events = @(); raw_lines = @(); thread_id = $null
            host_model = $null; host_effort = $null; host_launch_record = $false; rerouted = @()
            host_fresh = $null; host_history_excluded = $null; host_cwd = $null
            host_sandbox = $null; host_approval = $null; host_fallback_allowed = $null
            context_verified = $false; policy_verified = $false
            execution_status = 'BLOCKED'
            execution_blocker_code = if ($executionFailure) { $executionFailure.code } elseif ($initRead.kind -eq 'TIMEOUT') { 'APP_SERVER_INITIALIZE_TIMEOUT' } elseif ($initRead.kind -eq 'PARSE_ERROR') { 'APP_SERVER_INITIALIZE_PARSE_ERROR' } else { 'APP_SERVER_INITIALIZE_FAILED' }
            execution_blocker = if ($executionFailure) { $executionFailure.blocker } else { 'Codex app-server initialization did not return a valid response' }
            read_failure_kind = $initRead.kind
            activity_violation = $null
            output_limited = $false
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
    $readFailureKind = $null
    while ($null -eq $startResponse -and -not $process.HasExited) {
        $remaining = [int][Math]::Max(1, $timeoutMs - $watch.ElapsedMilliseconds)
        if ($remaining -le 0) { break }
        $read = Read-AppServerJson -Process $process -TimeoutMs $remaining
        if ($read.kind -ne 'MESSAGE') { $readFailureKind = $read.kind; break }
        $event = $read.value
        if ($null -eq $event) { $readFailureKind = 'PARSE_ERROR'; break }
        $events.Add($event)
        if ($events.Count -gt (Get-MaxEvents)) { $readFailureKind = 'EVENT_LIMIT'; break }
        $idProperty = $event.PSObject.Properties['id']
        if ($idProperty -and [string]$idProperty.Value -eq [string]$threadRequestId) { $startResponse = $event }
    }

    $threadId = $null
    $hostModel = $null
    $hostEffort = $null
    $launchRecord = $false
    $hostFresh = $null
    $hostHistoryExcluded = $null
    $hostCwd = $null
    $hostSandbox = $null
    $hostApproval = $null
    $hostFallbackAllowed = $null
    $startError = if ($startResponse) { $startResponse.PSObject.Properties['error'] } else { $null }
    if ($startResponse -and $null -eq $startError -and $startResponse.result) {
        $threadResult = if ($startResponse.result.PSObject.Properties['thread']) { $startResponse.result.thread } else { $null }
        $threadId = Get-TextProperty $threadResult 'id'
        if (-not $threadId) { $threadId = Get-TextProperty $startResponse.result 'threadId' }
        $hostObjects = @($startResponse.result, $threadResult)
        $hostModel = Normalize-ObservedValue ([string](Get-FirstPropertyValue -Objects $hostObjects -Names @('model', 'effectiveModel')))
        $hostEffort = Normalize-ObservedValue ([string](Get-FirstPropertyValue -Objects $hostObjects -Names @('reasoningEffort', 'effort', 'effectiveEffort')))
        $hostFresh = Get-NullableBoolAny -Objects $hostObjects -Names @('ephemeral', 'fresh', 'freshContext')
        $hostHistoryExcluded = Get-NullableBoolAny -Objects $hostObjects -Names @('historyExcluded', 'controllerHistoryExcluded')
        $hostCwd = [string](Get-FirstPropertyValue -Objects $hostObjects -Names @('cwd', 'workingDirectory'))
        $hostSandbox = [string](Get-FirstPropertyValue -Objects $hostObjects -Names @('sandbox', 'sandboxMode'))
        $hostApproval = [string](Get-FirstPropertyValue -Objects $hostObjects -Names @('approvalPolicy', 'approval'))
        $hostFallbackAllowed = Get-NullableBoolAny -Objects $hostObjects -Names @('allowProviderModelFallback')
        $launchRecord = $threadId -and $hostModel -and $hostEffort -and
            $hostModel.ToLowerInvariant() -eq $script:FixedModel -and
            $hostEffort.ToLowerInvariant() -eq $script:FixedEffort
    }
    # Some app-server versions put launch facts on a notification instead of
    # the thread/start result. Accept only host-emitted fields from this same
    # task-bound stream; never infer them from the worker text.
    if (-not $hostModel -or -not $hostEffort -or $null -eq $hostFresh -or $null -eq $hostHistoryExcluded) {
        foreach ($candidate in @($events)) {
            $paramsValue = if ($candidate.PSObject.Properties['params']) { $candidate.params } else { $null }
            $resultValue = if ($candidate.PSObject.Properties['result']) { $candidate.result } else { $null }
            $threadValue = if ($paramsValue -and $paramsValue.PSObject.Properties['thread']) { $paramsValue.thread } else { $null }
            $objects = @($candidate, $paramsValue, $resultValue, $threadValue)
            if (-not $threadId) { $threadId = Get-TextProperty $threadValue 'id' }
            if (-not $hostModel) { $hostModel = Normalize-ObservedValue ([string](Get-FirstPropertyValue -Objects $objects -Names @('model', 'effectiveModel'))) }
            if (-not $hostEffort) { $hostEffort = Normalize-ObservedValue ([string](Get-FirstPropertyValue -Objects $objects -Names @('reasoningEffort', 'effort', 'effectiveEffort'))) }
            if ($null -eq $hostFresh) { $hostFresh = Get-NullableBoolAny -Objects $objects -Names @('ephemeral', 'fresh', 'freshContext') }
            if ($null -eq $hostHistoryExcluded) { $hostHistoryExcluded = Get-NullableBoolAny -Objects $objects -Names @('historyExcluded', 'controllerHistoryExcluded') }
            if (-not $hostCwd) { $hostCwd = [string](Get-FirstPropertyValue -Objects $objects -Names @('cwd', 'workingDirectory')) }
            if (-not $hostSandbox) { $hostSandbox = [string](Get-FirstPropertyValue -Objects $objects -Names @('sandbox', 'sandboxMode')) }
            if (-not $hostApproval) { $hostApproval = [string](Get-FirstPropertyValue -Objects $objects -Names @('approvalPolicy', 'approval')) }
            if ($null -eq $hostFallbackAllowed) { $hostFallbackAllowed = Get-NullableBoolAny -Objects $objects -Names @('allowProviderModelFallback') }
        }
        $launchRecord = [bool]($threadId -and $hostModel -and $hostEffort -and
            $hostModel.ToLowerInvariant() -eq $script:FixedModel -and
            $hostEffort.ToLowerInvariant() -eq $script:FixedEffort)
    }
    $contextVerified = $hostFresh -eq $true -and $hostHistoryExcluded -eq $true
    $comparison = Get-PathComparison
    $normalizedHostCwd = if ($hostCwd) { Trim-DirectorySeparators -Path $hostCwd } else { $null }
    $normalizedWorkdir = Trim-DirectorySeparators -Path $Workdir
    $policyVerified = $normalizedHostCwd -and
        $normalizedHostCwd.Equals($normalizedWorkdir, $comparison) -and
        $hostSandbox -eq $Sandbox -and $hostApproval -eq 'never' -and
        $hostFallbackAllowed -eq $false

    # An identity-only handshake must finish at thread/start. Do not send a
    # turn/start for the read-only probe: a worker turn can block on a host
    # sandbox/process-creation defect and hide the task-bound launch record
    # until the outer broker deadline. A launch record is deliberately not a
    # completed turn, so the caller must keep HOST_VERIFIED closed.
    if ($HandshakeOnly) {
        $rerouted = @($events | Where-Object { (Get-TextProperty $_ 'method') -eq 'model/rerouted' })
        $timedOut = $watch.ElapsedMilliseconds -ge $timeoutMs
        $stderr = $null
        Stop-AppServerProcess $process
        $stderr = $stderrTask.Result
        $text = Get-AppServerMessageText -Events $events.ToArray()
        $activityViolation = Get-AppServerActivityViolation -Events $events.ToArray()
        $outputLimited = (-not (Test-TextLimit $text) -or -not (Test-TextLimit $stderr))
        $executionStatus = if ($timedOut -or $null -eq $startResponse -or -not $launchRecord -or $activityViolation -or $outputLimited) { 'BLOCKED' } else { 'NOT_STARTED' }
        $executionBlockerCode = if ($timedOut) {
            'BROKER_TIMEOUT'
        } elseif ($null -eq $startResponse) {
            'HOST_LAUNCH_RECORD_UNAVAILABLE'
        } elseif (-not $launchRecord) {
            'HOST_LAUNCH_RECORD_MISMATCH'
        } elseif ($outputLimited) {
            'OUTPUT_LIMIT_EXCEEDED'
        } elseif ($activityViolation) {
            'HANDSHAKE_ACTIVITY_DETECTED'
        } else {
            'HANDSHAKE_ONLY_NO_TURN'
        }
        $executionBlocker = if ($timedOut) {
            'Codex app-server did not return a task-bound launch record before the broker deadline'
        } elseif ($null -eq $startResponse) {
            'Codex app-server did not return a task-bound thread/start response'
        } elseif (-not $launchRecord) {
            'Codex app-server launch record did not match the requested model and effort'
        } elseif ($outputLimited) {
            'Codex app-server output exceeded the broker limit'
        } elseif ($activityViolation) {
            'Handshake-only worker emitted a command, file, tool, or shell activity event'
        } else {
            'Identity-only handshake captured the task-bound launch record; no turn was dispatched'
        }
        return [ordered]@{
            exit_code = if ($executionStatus -eq 'BLOCKED') { 1 } else { 0 }
            timed_out = $timedOut
            events = $events.ToArray()
            raw_lines = @()
            thread_id = $threadId
            host_model = $hostModel
            host_effort = $hostEffort
            host_launch_record = [bool]$launchRecord
            host_fresh = $hostFresh
            host_history_excluded = $hostHistoryExcluded
            host_cwd = $hostCwd
            host_sandbox = $hostSandbox
            host_approval = $hostApproval
            host_fallback_allowed = $hostFallbackAllowed
            context_verified = [bool]$contextVerified
            policy_verified = [bool]$policyVerified
            rerouted = $rerouted
            activity_violation = $activityViolation
            output_limited = $outputLimited
            read_failure_kind = $readFailureKind
            turn_completed = $false
            turn_status = $null
            turn_error = $null
            execution_status = $executionStatus
            execution_blocker_code = $executionBlockerCode
            execution_blocker = $executionBlocker
            text = $text
            stderr = $stderr
        }
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
            $read = Read-AppServerJson -Process $process -TimeoutMs $remaining
            if ($read.kind -ne 'MESSAGE') { $readFailureKind = $read.kind; break }
            $event = $read.value
            if ($null -eq $event) { $readFailureKind = 'PARSE_ERROR'; break }
            $events.Add($event)
            if ($events.Count -gt (Get-MaxEvents)) { $readFailureKind = 'EVENT_LIMIT'; break }
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
    $activityViolation = if ($HandshakeOnly) { Get-AppServerActivityViolation -Events $events.ToArray() } else { $null }
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
    } elseif (-not (Test-TextLimit $text) -or -not (Test-TextLimit $stderr)) {
        $executionBlockerCode = 'OUTPUT_LIMIT_EXCEEDED'
        $executionBlocker = 'Codex app-server output exceeded the broker limit'
    } elseif ($activityViolation) {
        $executionBlockerCode = 'HANDSHAKE_ACTIVITY_DETECTED'
        $executionBlocker = 'Handshake-only worker emitted a command, file, tool, or shell activity event'
    } elseif ($readFailureKind -eq 'EVENT_LIMIT') {
        $executionBlockerCode = 'EVENT_LIMIT_EXCEEDED'
        $executionBlocker = 'Codex app-server emitted too many events'
    } elseif ($readFailureKind -and $readFailureKind -ne 'EOF') {
        $executionBlockerCode = "APP_SERVER_$readFailureKind"
        $executionBlocker = 'Codex app-server stream ended without a complete task result'
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
        raw_lines = @()
        thread_id = $threadId
        host_model = $hostModel
        host_effort = $hostEffort
        host_launch_record = [bool]$launchRecord
        host_fresh = $hostFresh
        host_history_excluded = $hostHistoryExcluded
        host_cwd = $hostCwd
        host_sandbox = $hostSandbox
        host_approval = $hostApproval
        host_fallback_allowed = $hostFallbackAllowed
        context_verified = [bool]$contextVerified
        policy_verified = [bool]$policyVerified
        rerouted = $rerouted
        activity_violation = $activityViolation
        output_limited = (-not (Test-TextLimit $text) -or -not (Test-TextLimit $stderr))
        read_failure_kind = $readFailureKind
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
        [Parameter(Mandatory = $true)] [AllowNull()] [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory = $true)] [string] $Field
    )

    $pattern = "(?im)^\s*$([regex]::Escape($Field))\s*=\s*(.+?)\s*$"
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value.Trim()
}

function Get-FirstLabeledField {
    param(
        [Parameter(Mandatory = $true)] [AllowNull()] [AllowEmptyString()] [string] $Text,
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
    $resolved = Trim-DirectorySeparators -Path (Resolve-Path -LiteralPath $root).Path
    if (-not (Test-NoReparsePoints -Path $resolved)) { throw 'SOL_LUNA_JOB_ROOT contains a reparse point' }
    return $resolved
}

function Prune-AsyncJobs {
    param([Parameter(Mandatory = $true)] [string] $Root)

    $now = [DateTime]::UtcNow
    $retention = [TimeSpan]::FromSeconds((Get-JobRetentionSeconds))
    foreach ($entry in @($script:AsyncChildren.GetEnumerator())) {
        $child = $entry.Value.process
        if ($child.HasExited) { $script:AsyncChildren.Remove([string]$entry.Key) }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        if ($file.BaseName -notmatch '^[a-f0-9]{32}$') { continue }
        if (($now - $file.LastWriteTimeUtc) -gt $retention) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
        }
    }
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
    $workerShell = Get-PowerShellExecutable
    $jobId = [Guid]::NewGuid().ToString('N')
    $jobRoot = Get-JobRoot
    Prune-AsyncJobs -Root $jobRoot
    $activeJobs = @(
        Get-ChildItem -LiteralPath $jobRoot -Filter '*.json' -File -ErrorAction SilentlyContinue |
            ForEach-Object { Read-JobState -Path $_.FullName } |
            Where-Object { $_ -and [string]$_.status -in @('QUEUED', 'RUNNING') }
    )
    if ($activeJobs.Count -ge (Get-MaxAsyncJobs)) { throw 'SOL_LUNA_MAX_ASYNC_JOBS has been reached' }
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
    $psi.FileName = $workerShell
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $workerArguments = @('-NoProfile', '-NonInteractive')
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        $workerArguments += @('-ExecutionPolicy', 'Bypass')
    }
    $workerArguments += @('-File', $script:BrokerScriptPath, '-Worker')
    foreach ($argument in $workerArguments) {
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
        fresh = $null
        history = $null
        context_verified = $false
        policy_verified = $false
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
        fresh = if ($completedPayload) { Get-NullableBoolProperty $completedPayload 'fresh' } else { $null }
        history = if ($completedPayload -and (Get-TextProperty $completedPayload 'history')) { Get-TextProperty $completedPayload 'history' } else { $null }
        context_verified = if ($completedPayload) { [bool](Get-BoolProperty $completedPayload 'context_verified' $false) } else { $false }
        policy_verified = if ($completedPayload) { [bool](Get-BoolProperty $completedPayload 'policy_verified' $false) } else { $false }
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
    if (-not $prompt -or $prompt.Length -gt 20000) { throw 'prompt is required and must be <= 20000 characters' }
    if ($sandbox -notin @('read-only', 'workspace-write')) { throw 'sandbox must be read-only or workspace-write' }
    if ($handshakeOnly -and $sandbox -ne 'read-only') { throw 'handshake_only requires read-only sandbox' }
    if ($executionMode -notin @('sync', 'async')) { throw 'execution_mode must be sync or async' }
    if ($executionMode -eq 'async' -and $handshakeOnly) {
        throw 'async execution is for implementation packets; run the identity-only handshake synchronously first'
    }

    $workdirMode = 'ALLOWLISTED'
    if ($workdirInput) {
        $workdir = Resolve-AllowedWorkdir $workdirInput
    } elseif ($handshakeOnly) {
        $workdir = New-HandshakeWorkdir
        $workdirMode = 'HANDSHAKE_TEMP'
    } else {
        Throw-BrokerDiagnostic -Code 'SOL_LUNA_WORKDIR_REQUIRED' `
            -Variable 'workdir' `
            -Reason 'Implementation packets need an explicit task workdir; only read-only identity handshakes may omit it.' `
            -Repair 'Create or select the task worktree, pass it as workdir, and add its parent to SOL_LUNA_ALLOWED_ROOTS using the platform path separator.' `
            -Example 'Windows: E:\Sources\.codex-worktrees\task | Unix/macOS: /srv/codex/worktrees/task'
    }
    # Verify the pinned runtime before either synchronous execution or queueing
    # an asynchronous child; a job receipt must never hide a hash mismatch.
    $runtimeInfo = Get-VerifiedRuntime
    if ($executionMode -eq 'async') {
        return (Start-AsyncLunaJob -Arguments $Arguments)
    }
    $runtime = $runtimeInfo.path
    $runtimeHash = $runtimeInfo.sha256
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
        $run = Invoke-AppServerWorker -RuntimePath $runtime -Workdir $workdir -Prompt $guard -Sandbox $sandbox -HandshakeOnly:$handshakeOnly
        $text = [string]$run.text
        $threadId = $run.thread_id
        $events = @($run.events)
    } else {
        $run = Invoke-CodexWorker -RuntimePath $runtime -Workdir $workdir -Prompt $guard -Sandbox $sandbox -HandshakeOnly:$handshakeOnly
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
    $hostFresh = $null
    $hostHistoryExcluded = $null
    $hostCwd = $null
    $hostSandbox = $null
    $hostApproval = $null
    $hostFallbackAllowed = $null
    $contextVerified = $false
    $policyVerified = $false
    $identityProofKind = 'SELF_REPORT_ONLY'
    $receiptKind = 'BROKER_RUN_RECEIPT'
    $identity = 'UNVERIFIED'
    $identityBlocker = 'Self-report matches, but no host-observed identity telemetry was returned'
    $executionStatus = if ($run.timed_out -or $run.exit_code -ne 0) { 'BLOCKED' } else { 'COMPLETED' }
    $executionBlockerCode = if ($run.timed_out) { 'BROKER_TIMEOUT' } elseif ($run.exit_code -ne 0) { 'RUNTIME_EXIT_NONZERO' } else { $null }
    $executionBlocker = if ($run.timed_out) { 'Codex runtime exceeded the broker timeout' } elseif ($run.exit_code -ne 0) { "Codex runtime exited with code $($run.exit_code)" } else { $null }
    $executionFailure = Get-AppServerExecutionFailure -Text $text -Stderr ([string]$run.stderr)
    if ($executionFailure -and $executionStatus -eq 'COMPLETED') {
        $executionStatus = 'BLOCKED'
        $executionBlockerCode = $executionFailure.code
        $executionBlocker = $executionFailure.blocker
    }
    if ($run.output_limited) {
        $executionStatus = 'BLOCKED'; $executionBlockerCode = 'OUTPUT_LIMIT_EXCEEDED'; $executionBlocker = 'Codex runtime output exceeded the broker limit'
    } elseif ($run.activity_violation) {
        $executionStatus = 'BLOCKED'; $executionBlockerCode = 'HANDSHAKE_ACTIVITY_DETECTED'; $executionBlocker = 'Handshake-only worker emitted a prohibited activity event'
    }
    if ($script:Transport -eq 'app-server') {
        $hostObservedModel = $run.host_model
        $hostObservedEffort = $run.host_effort
        $hostFresh = $run.host_fresh
        $hostHistoryExcluded = $run.host_history_excluded
        $hostCwd = $run.host_cwd
        $hostSandbox = $run.host_sandbox
        $hostApproval = $run.host_approval
        $hostFallbackAllowed = $run.host_fallback_allowed
        $contextVerified = [bool]$run.context_verified
        $policyVerified = [bool]$run.policy_verified
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
            $identityBlocker = 'Host launch record did not match the requested model and effort'
        } else {
            $identity = 'VERIFIED'
            $identityBlocker = 'Host launch record matched gpt-5.6-luna/max and no host reroute was observed'
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

    $status = if ($identity -eq 'VERIFIED' -and $executionStatus -eq 'COMPLETED' -and $contextVerified -and $policyVerified) { 'HOST_VERIFIED' } elseif ($identity -eq 'FAIL' -or $executionStatus -eq 'BLOCKED') { 'BLOCKED' } else { 'STARTED_UNVERIFIED' }
    $blocker = if ($executionStatus -eq 'BLOCKED') { $executionBlocker } elseif (-not $contextVerified) { 'Host did not prove fresh context with controller history excluded' } elseif (-not $policyVerified) { 'Host did not prove the requested workdir, sandbox, approval, and no-fallback policy' } else { $identityBlocker }
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
        runtime_trust = 'PINNED_SHA256'
        requested_model = $script:FixedModel
        requested_effort = $script:FixedEffort
        host_observed_model = $hostObservedModel
        host_observed_effort = $hostObservedEffort
        self_reported_model = $selfModel
        self_reported_effort = $selfEffort
        identity_proof_kind = $identityProofKind
        fresh = if ($contextVerified) { $true } else { $null }
        history = if ($hostHistoryExcluded -eq $true) { 'EXCLUDED' } else { $null }
        context_verified = $contextVerified
        policy_verified = $policyVerified
        host_cwd = Protect-OutputText $hostCwd
        host_sandbox = $hostSandbox
        host_approval = $hostApproval
        host_fallback_allowed = $hostFallbackAllowed
        sandbox = $sandbox
        workdir_mode = $workdirMode
        workdir = Protect-OutputText $workdir
        exit_code = $run.exit_code
        timed_out = $run.timed_out
        identity = $identity
        execution_status = $executionStatus
        execution_blocker_code = $executionBlockerCode
        execution_blocker = Protect-OutputText $executionBlocker
        activity_violation = Protect-OutputText $run.activity_violation
        output_limited = [bool]$run.output_limited
        read_failure_kind = $run.read_failure_kind
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
        description = 'Launch a fresh ephemeral host-managed Codex worker fixed to gpt-5.6-luna/max. Read-only handshake_only requests may omit workdir and use a private platform temp directory; implementation requests require an explicit allowlisted workdir. Runtime path/command and SHA-256 remain pinned. Use execution_mode=async for long-running implementation packets, then poll the task-bound job receipt with sol_luna_poll. This broker never changes ACLs.'
        inputSchema = [ordered]@{
            type = 'object'
            additionalProperties = $false
            required = @('task_id', 'prompt')
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
        instructions = 'sol_luna_exec launches fresh gpt-5.6-luna/max with a pinned runtime. Run handshake_only=true synchronously first; workdir may be omitted because the broker uses a private platform temp directory and returns HOST_LAUNCH_RECORD without a worker turn. Implementation packets require an explicit workdir under SOL_LUNA_ALLOWED_ROOTS. For long-running implementation, set execution_mode=async and poll the returned job_id with sol_luna_poll. Configuration errors return a diagnostic code, variable, reason, repair, and example. The broker never repairs ACLs or broadens permissions.'
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
                    Send-Result -Id $id -Result $_ -IsError
                }
            }
            default {
                if ($hasId) { Send-Result -Id $id -Result "Unsupported method: $method" -IsError }
            }
        }
    } catch {
        if ($hasId) { Send-Result -Id $id -Result $_ -IsError }
    }
}
