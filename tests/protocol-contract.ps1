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
$registration = Get-Content -Raw -LiteralPath (Join-Path $Root 'references/registration.md')
$readme = Get-Content -Raw -LiteralPath (Join-Path $Root 'README.md')
$readmeEn = Get-Content -Raw -LiteralPath (Join-Path $Root 'README.en.md')

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
Assert-Contains $skill 'multi_agent_v1__spawn_agent' 'canonical native Luna surface must be documented'
Assert-Contains $skill 'THREAD_SURFACE_NOT_VISIBLE' 'thread-bound surface gaps must be classified'
Assert-Contains $skill 'Native-first dispatch ladder' 'Luna dispatch must define an operational priority ladder'
Assert-Contains $skill 'native preflight cannot obtain the required host evidence' 'managed MCP must require a concrete native-preflight failure'
Assert-Contains $skill 'MCP is not a native subagent' 'managed MCP must not be represented as native execution'

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
Assert-Contains $protocol 'Registration action:' 'plan must tell the caller what registration action is next'
Assert-Contains $protocol 'Dispatch tool/schema:' 'plan and handshake must bind the selected tool schema'
Assert-Contains $protocol 'THREAD_SURFACE_NOT_VISIBLE' 'protocol must distinguish thread surface visibility'
Assert-Contains $protocol 'HOST_JOB_RECEIPT' 'protocol must define asynchronous broker submission evidence'
Assert-Contains $protocol 'sol_luna_poll' 'protocol must define asynchronous broker result retrieval'
Assert-Contains $protocol 'Dispatch priority: NATIVE_FIRST_THEN_MCP' 'plan must bind Luna to native-first then MCP-second routing'
Assert-Contains $protocol 'MCP is not native evidence' 'protocol must keep managed transport evidence distinct from native evidence'
Assert-Contains $protocol 'No silent model fallback' 'route failure must never silently replace the requested model'

Assert-Contains $adapters 'multi_agent_v1__spawn_agent' 'native adapter must name the generic worker surface'
Assert-Contains $adapters 'fork_context: false' 'native adapter must exclude controller history'
Assert-Contains $adapters 'agent_type: luna-max-worker' 'custom role adapter must name the role explicitly'
Assert-Contains $adapters 'fork_turns: none' 'custom role adapter must require a fresh fork'
Assert-Contains $adapters 'HOST_OBSERVED_MODEL_EFFORT' 'native identity must come from host observation'
Assert-Contains $adapters 'ROLE_MAPPING_AND_LAUNCH_RECORD' 'custom identity must come from host launch evidence'
Assert-Contains $adapters 'AGENT_HANDLE' 'agent handles must not be treated as identity proof'
Assert-Contains $adapters 'TOML/config alone is not proof' 'local role configuration must not self-authorize dispatch'
Assert-Contains $adapters 'MCP broker variant' 'managed Luna broker adapter must be documented'
Assert-Contains $adapters 'BROKER_RUN_RECEIPT' 'broker receipt must remain distinct from host receipt'
Assert-Contains $adapters 'STARTED_UNVERIFIED' 'broker self-report must remain unverified'
Assert-Contains $adapters 'ROLE_MAPPING_AND_LAUNCH_RECORD' 'app-server launch record must be a distinct identity proof kind'
Assert-Contains $adapters 'model/rerouted' 'app-server reroutes must invalidate launch identity'
Assert-Contains $adapters 'HOST_JOB_RECEIPT' 'managed broker must define asynchronous submission evidence'
Assert-Contains $adapters 'sol_luna_poll' 'managed broker must define asynchronous result retrieval'
Assert-Contains $protocol 'HOST_LAUNCH_RECORDED' 'protocol must distinguish host launch from effective verification'
Assert-Contains $adapters 'Priority 1: current-thread native' 'adapter order must make current-thread native primary'
Assert-Contains $adapters 'Priority 2: HOST_MANAGED MCP' 'adapter order must make the broker secondary'
Assert-Contains $adapters 'cannot impersonate `multi_agent_v1__spawn_agent`' 'legacy collaboration schema must not masquerade as canonical native v1'

Assert-Contains $enablement 'LUNA_MAX_REQUIRED' 'enablement packet must identify the required capability'
Assert-Contains $enablement 'gpt-5.6-luna / max' 'enablement packet must bind the Luna model and effort'
Assert-Contains $enablement 'NOT_ENABLED' 'host must report a missing capability explicitly'
Assert-Contains $enablement 'HOST_ENABLEMENT_REQUIRED' 'enablement failure must be actionable'
Assert-Contains $enablement 'no user-owned task' 'enablement must not use a user-owned task as a substitute'
Assert-Contains $enablement 'config.toml' 'config boundary must be documented'
Assert-Contains $enablement 'top-level Codex session' 'config.toml must be scoped to the top-level session'
Assert-Contains $enablement 'does not add a model' 'config.toml must not be treated as a worker allowlist'
Assert-Contains $enablement 'collaboration.spawn_agent' 'host-owned surface must be named explicitly'
Assert-Contains $enablement 'execution_mode="async"' 'enablement guide must define asynchronous implementation submission'
Assert-Contains $enablement 'sol_luna_poll' 'enablement guide must define asynchronous result retrieval'
Assert-Contains $enablement 'Native-first -> MCP-second' 'enablement must preserve the route priority ladder'
Assert-Contains $protocol 'configuration boundary' 'protocol must explain config versus host ownership'
Assert-Contains $protocol 'registration guide' 'protocol must link the registration procedure'

Assert-Contains $registration 'HOST_REGISTRATION_REQUIRED' 'registration guide must classify the host action'
Assert-Contains $registration 'task_name' 'registration guide must show the native schema'
Assert-Contains $registration 'fork_turns = "none"' 'registration guide must show fresh context mapping'
Assert-Contains $registration 'gpt-5.6-luna' 'registration guide must bind Luna'
Assert-Contains $registration 'reasoning_effort = "max"' 'registration guide must bind max effort'
Assert-Contains $registration '.codex/agents/luna-max-worker.toml' 'registration guide must show custom-role location'
Assert-Contains $registration 'config.toml' 'registration guide must explain config limitation'
Assert-Contains $registration 'HOST_RECEIPT' 'registration guide must define success evidence'
Assert-Contains $registration 'HOST_ENABLEMENT_REQUIRED' 'registration guide must define blocked recovery'
Assert-Contains $registration 'refresh' 'registration guide must require capability refresh'
Assert-Contains $registration 'HOST_REGISTRATION_REQUIRED' 'registration guide must distinguish host registration from task block'
Assert-Contains $registration 'agent_id' 'registration guide must classify native agent handles'
Assert-Contains $registration 'HOST_VERIFIED' 'registration guide must retain the high-risk identity gate'
Assert-Contains $registration 'HOST_LAUNCH_RECORDED' 'registration guide must define the app-server launch retest state'
Assert-Contains $registration 'multi_agent_v1__spawn_agent' 'registration guide must cover the alternate native wrapper'
Assert-Contains $registration 'fork_context: false' 'registration guide must cover the alternate fresh-context field'
Assert-Contains $registration 'AGENT_HANDLE' 'registration guide must classify returned agent ids'
Assert-Contains $registration 'THREAD_SURFACE_NOT_VISIBLE' 'registration guide must handle per-thread surface gaps'
Assert-Contains $registration 'user-visible app task' 'registration guide must separate app tasks from native workers'
Assert-Contains $registration 'sol_luna_broker' 'registration guide must expose the operational broker'
Assert-Contains $registration 'broker-contract.ps1' 'registration guide must expose broker verification'
Assert-Contains $registration 'HOST_JOB_RECEIPT' 'registration guide must define asynchronous submission evidence'
Assert-Contains $registration 'sol_luna_poll' 'registration guide must define result polling'
Assert-Contains $registration 'execution_mode="async"' 'registration guide must define asynchronous execution'
Assert-Contains $registration 'Do not register the broker as a native surface' 'registration must keep MCP and native surfaces distinct'

Assert-Contains $readme 'README.en.md' 'README must expose the English companion'
Assert-Contains $readme 'sol-advisor' 'README must record the Sol advisor reference project'
Assert-Contains $readme 'codex-sol-control' 'README must record the Codex Sol control reference project'
Assert-Contains $readme 'MCP' 'README must describe the managed broker surface'
Assert-Contains $readme '原生优先、MCP 次选' 'README must state the native-first route in its existing Chinese style'

Assert-Contains $readmeEn 'Native-first -> MCP-second' 'English README must state the Luna route priority'
Assert-Contains $readmeEn 'multi_agent_v1__spawn_agent' 'English README must name the canonical native surface'
Assert-Contains $readmeEn 'future equivalent' 'English README must require host-declared and verified future native surfaces'
Assert-Contains $readmeEn 'native preflight cannot obtain the required host evidence' 'English README must bound use of the managed MCP route'
Assert-Contains $readmeEn 'HOST_MANAGED' 'English README must classify the MCP route as host-managed'
Assert-Contains $readmeEn 'MCP is not a native subagent' 'English README must keep MCP distinct from native execution'
Assert-Contains $readmeEn 'not a silent model fallback' 'English README must forbid silent model fallback'
Assert-Contains $readmeEn 'retain the requested `gpt-5.6-luna / max`' 'English README must preserve the requested Luna model and effort on route failure'
Assert-Contains $readmeEn 'BLOCKED' 'English README must fail closed when both Luna routes fail'

Assert-Contains $enablement 'BROKER_RUN_RECEIPT' 'enablement guide must classify broker receipts'
Assert-Contains $enablement 'STARTED_UNVERIFIED' 'enablement guide must keep broker identity unverified'

Assert-NotContains $skill 'gpt-5.6-terra' 'Terra must not become a normal Sol lane'
Assert-NotContains $protocol 'gpt-5.6-terra' 'Terra must not become a normal Sol lane'

Write-Output 'PASS: Sol runtime adapter protocol contract'
