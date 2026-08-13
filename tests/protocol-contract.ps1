[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Reason
    )

    if ($Text.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "Contract assertion failed: $Reason (missing '$Needle')"
    }
}

function Assert-NotContains {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Reason
    )

    if ($Text.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Contract assertion failed: $Reason (found '$Needle')"
    }
}

$skill = Get-Content -Raw -LiteralPath (Join-Path $Root 'SKILL.md')
$protocol = Get-Content -Raw -LiteralPath (Join-Path $Root 'references/protocol.md')
$adaptersPath = Join-Path $Root 'references/runtime-adapters.md'
$adapters = Get-Content -Raw -LiteralPath $adaptersPath
$enablement = Get-Content -Raw -LiteralPath (Join-Path $Root 'references/enablement.md')

Assert-Contains $skill 'LUNA_MAX' 'logical Luna route must be explicit'
Assert-Contains $skill 'gpt-5.6-luna / max' 'Luna route must bind its requested model and effort'
Assert-Contains $skill 'SOL_XHIGH' 'logical Sol-XHigh route must be explicit'
Assert-Contains $skill 'gpt-5.6-sol / xhigh' 'Sol-XHigh route must bind its requested model and effort'
Assert-Contains $skill 'NATIVE_GENERIC' 'native surface adapter must be documented'
Assert-Contains $skill 'CUSTOM_ROLE' 'custom-role surface adapter must be documented'
Assert-Contains $skill 'capability preflight' 'dispatch must be gated by capability preflight'
Assert-Contains $skill 'AGENT_HANDLE' 'agent handles must be distinguished from host receipts'
Assert-Contains $skill 'HOST_VERIFIED' 'verified identity gate must remain explicit'
Assert-Contains $skill 'BLOCKED' 'unproven execution must fail closed'
Assert-Contains $skill '`LUNA_MAX` capability is mandatory' 'Luna must be a required host capability'
Assert-Contains $skill 'HOST_ENABLEMENT_REQUIRED' 'missing Luna capability must request host enablement'

Assert-Contains $protocol 'Surface:' 'plan packet must identify the execution surface'
Assert-Contains $protocol 'Capability verdict:' 'handshake must carry capability evidence'
Assert-Contains $protocol 'Fresh-context proof:' 'handshake must prove fresh context separately'
Assert-Contains $protocol 'Controller-history proof:' 'handshake must prove controller history exclusion separately'
Assert-Contains $protocol 'Dispatch receipt kind:' 'handshake must classify the receipt'
Assert-Contains $protocol 'Identity proof kind:' 'handshake must classify identity evidence'
Assert-Contains $protocol 'normal replan, not an implicit fallback' 'Sol-XHigh must not be an implicit fallback'
Assert-Contains $protocol 'retry the identical unavailable packet' 'an unavailable packet must not be retried verbatim'
Assert-Contains $protocol 'Luna enablement: REQUIRED' 'plan must require Luna enablement'
Assert-Contains $protocol 'Enablement evidence:' 'handshake must carry Luna enablement evidence'
Assert-Contains $protocol 'HOST_ENABLEMENT_REQUIRED' 'missing Luna must be a host enablement blocker'

Assert-Contains $adapters 'multi_agent_v1__spawn_agent' 'native adapter must name the generic worker surface'
Assert-Contains $adapters 'fork_context: false' 'native adapter must exclude controller history'
Assert-Contains $adapters 'agent_type: luna-max-worker' 'custom role adapter must name the role explicitly'
Assert-Contains $adapters 'fork_turns: none' 'custom role adapter must require a fresh fork'
Assert-Contains $adapters 'HOST_OBSERVED_MODEL_EFFORT' 'native identity must come from host observation'
Assert-Contains $adapters 'ROLE_MAPPING_AND_LAUNCH_RECORD' 'custom identity must come from host launch evidence'
Assert-Contains $adapters 'AGENT_HANDLE' 'agent handles must not be treated as identity proof'
Assert-Contains $adapters 'TOML/config alone is not proof' 'local role configuration must not self-authorize dispatch'

Assert-Contains $enablement 'LUNA_MAX_REQUIRED' 'enablement packet must identify the required capability'
Assert-Contains $enablement 'gpt-5.6-luna / max' 'enablement packet must bind the Luna model and effort'
Assert-Contains $enablement 'NOT_ENABLED' 'host must report a missing capability explicitly'
Assert-Contains $enablement 'HOST_ENABLEMENT_REQUIRED' 'enablement failure must be actionable'
Assert-Contains $enablement 'no user-owned task' 'enablement must not use a user-owned task as a substitute'
Assert-Contains $enablement 'config.toml' 'config boundary must be documented'
Assert-Contains $enablement 'top-level Codex session' 'config.toml must be scoped to the top-level session'
Assert-Contains $enablement 'does not add a model' 'config.toml must not be treated as a worker allowlist'
Assert-Contains $enablement 'collaboration.spawn_agent' 'host-owned surface must be named explicitly'
Assert-Contains $protocol 'configuration boundary' 'protocol must explain config versus host ownership'

Assert-NotContains $skill 'gpt-5.6-terra' 'Terra must not become a normal Sol lane'
Assert-NotContains $protocol 'gpt-5.6-terra' 'Terra must not become a normal Sol lane'

Write-Output 'PASS: Sol runtime adapter protocol contract'
