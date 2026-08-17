[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$RuntimeRoot,
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RuntimeRoot -PathType Container)) {
    throw 'Runtime root does not exist'
}

$tracked = @(git -C $SourceRoot ls-files)
if ($LASTEXITCODE -ne 0 -or $tracked.Count -eq 0) { throw 'Unable to enumerate tracked source files' }
$missing = [System.Collections.Generic.List[string]]::new()
$mismatch = [System.Collections.Generic.List[string]]::new()
foreach ($relative in $tracked) {
    $sourcePath = Join-Path $SourceRoot $relative
    $runtimePath = Join-Path $RuntimeRoot $relative
    if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
        $missing.Add($relative)
        continue
    }
    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToUpperInvariant()
    $runtimeHash = (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($sourceHash -ne $runtimeHash) { $mismatch.Add($relative) }
}
if ($missing.Count -gt 0 -or $mismatch.Count -gt 0) {
    throw "Runtime sync mismatch: missing=$($missing.Count); mismatched=$($mismatch.Count)"
}
$runtimeFiles = @(Get-ChildItem -LiteralPath $RuntimeRoot -Recurse -File | ForEach-Object {
    $_.FullName.Substring($RuntimeRoot.Length + 1).Replace('\\', '/')
})
$unexpected = @($runtimeFiles | Where-Object { $_ -notin $tracked })
if ($unexpected.Count -gt 0) {
    throw "Runtime sync mismatch: unexpected=$($unexpected.Count)"
}
Write-Output "PASS: runtime sync contract ($($tracked.Count) tracked files)"
