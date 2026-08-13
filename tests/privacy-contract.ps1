[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Reason)
    if (-not $Condition) { throw "Privacy contract assertion failed: $Reason" }
}

function Assert-NotMatch {
    param([string]$Text, [string]$Pattern, [string]$Reason)
    Assert-True (-not [regex]::IsMatch($Text, $Pattern)) $Reason
}

$brokerPath = Join-Path $Root 'scripts/sol-luna-broker.ps1'
Assert-True (Test-Path -LiteralPath $brokerPath -PathType Leaf) 'broker script must exist'
$broker = Get-Content -Raw -LiteralPath $brokerPath
Assert-True ($broker.Contains('Protect-OutputText')) 'broker must define an output redaction function'
Assert-True ($broker.Contains("redaction = [ordered]@{")) 'broker must publish redaction status'
Assert-True ($broker.Contains('<user>')) 'broker must redact user identities'
Assert-True ($broker.Contains('<host>')) 'broker must redact host identities'
Assert-True ($broker.Contains('<redacted>')) 'broker must redact credential-shaped values'
Assert-True ($broker.Contains('SOL_LUNA_ALLOWED_ROOTS must be configured')) 'broker must not use implicit filesystem roots'
Assert-True ($broker.Contains('AKIA[0-9A-Z]{16}')) 'broker must redact AWS key-shaped values'
Assert-True ($broker.Contains('eyJ[A-Za-z0-9_-]{20,}')) 'broker must redact JWT-shaped values'
Assert-True ($broker.Contains('PRIVATE KEY')) 'broker must redact private-key blocks'
Assert-True ($broker.Contains("(?!Users\\)")) 'broker must redact arbitrary drive paths while preserving only a placeholder for user-home paths'

$docFiles = @(
    (Join-Path $Root 'README.md'),
    (Join-Path $Root 'README.en.md'),
    (Join-Path $Root 'SKILL.md'),
    (Join-Path $Root 'agents/openai.yaml'),
    (Join-Path $Root 'SECURITY.md'),
    (Join-Path $Root 'CONTRIBUTING.md'),
    (Join-Path $Root 'CHANGELOG.md')
) + @(Get-ChildItem -LiteralPath (Join-Path $Root 'references') -File -Filter '*.md' | Select-Object -ExpandProperty FullName)
$docs = (($docFiles | Where-Object { Test-Path -LiteralPath $_ }) | ForEach-Object { Get-Content -Raw -LiteralPath $_ }) -join "`n"
Assert-NotMatch $docs '(?i)C:\\Users\\(?!<)' 'documentation must not contain a concrete Windows user path'
Assert-NotMatch $docs '(?i)C:/Users/(?!<)' 'documentation must not contain a concrete slash-style user path'
Assert-NotMatch $docs '(?i)E:\\Sources|E:/Sources' 'documentation must not contain a machine-specific worktree root'
Assert-NotMatch $docs '(?i)\bsk-[A-Za-z0-9]{20,}\b' 'documentation must not contain an OpenAI-style API key'
Assert-NotMatch $docs '(?i)\bgh[pousr]_[A-Za-z0-9]{20,}\b' 'documentation must not contain a GitHub token'
Assert-NotMatch $docs '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{20,}' 'documentation must not contain a bearer token'
Assert-NotMatch $docs '(?i)-----BEGIN\s+(?:RSA|OPENSSH|EC|DSA)?\s*PRIVATE KEY-----' 'documentation must not contain a private key'

$oldRoots = $env:SOL_LUNA_ALLOWED_ROOTS
$probeUserPath = Join-Path $env:USERPROFILE 'sol-luna-privacy-probe\missing'
$probeHostPath = Join-Path $Root ("privacy-probe-$($env:COMPUTERNAME)-missing")
$requests = @(
    @{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = @{ name = 'sol_luna_exec'; arguments = @{ task_id = 'privacy-user-path'; workdir = $probeUserPath; prompt = 'HANDSHAKE_ONLY' } } },
    @{ jsonrpc = '2.0'; id = 2; method = 'tools/call'; params = @{ name = 'sol_luna_exec'; arguments = @{ task_id = 'privacy-host-name'; workdir = $probeHostPath; prompt = 'HANDSHAKE_ONLY' } } }
)
try {
    $env:SOL_LUNA_ALLOWED_ROOTS = $Root
    $jsonInput = ($requests | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 12 }) -join "`n"
    $output = $jsonInput | & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $brokerPath
    $exitCode = $LASTEXITCODE
} finally {
    if ($null -eq $oldRoots) { Remove-Item Env:SOL_LUNA_ALLOWED_ROOTS -ErrorAction SilentlyContinue }
    else { $env:SOL_LUNA_ALLOWED_ROOTS = $oldRoots }
}

Assert-True ($exitCode -eq 0) 'broker privacy probe must exit cleanly'
$records = @($output | ConvertFrom-Json)
Assert-True ($records.Count -eq 2) 'broker privacy probe must return two responses'
$userMessage = [string](($records | Where-Object { $_.id -eq 1 }).error.message)
$hostMessage = [string](($records | Where-Object { $_.id -eq 2 }).error.message)
if ($env:USERNAME) { Assert-True (-not $userMessage.Contains($env:USERNAME)) 'user name must not appear in broker errors' }
if ($env:COMPUTERNAME) { Assert-True (-not $hostMessage.Contains($env:COMPUTERNAME)) 'host name must not appear in broker errors' }
Assert-True (-not $userMessage.Contains($probeUserPath)) 'arbitrary user paths must never be echoed in broker errors'
Assert-True (-not $hostMessage.Contains($probeHostPath)) 'arbitrary host paths must never be echoed in broker errors'

Write-Output 'PASS: Sol privacy contract'
