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

Assert-True (-not (Test-Path -LiteralPath (Join-Path $Root 'scripts/sol-luna-broker.ps1'))) 'removed broker script must stay absent'

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
Assert-NotMatch $docs '(?i)sol[_-]luna|HOST_MANAGED|HOST_JOB_RECEIPT|BROKER_RUN_RECEIPT' 'removed local transport identifiers must not return to the docs'

Write-Output 'PASS: Sol privacy contract'
