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
$desktopTask = Get-Content -Raw -LiteralPath (Join-Path $Root 'references/desktop-task-lane.md')
$sources = Get-Content -Raw -LiteralPath (Join-Path $Root 'references/sources.md')
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
Assert-Contains $skill 'OPERATOR_ATTESTED' 'operator-attested identity gate must be explicit'
Assert-Contains $skill 'OPERATOR_UI_ATTESTED' 'operator-attested Desktop result must be explicit'
Assert-Contains $skill 'HOST_MODEL_UNOBSERVABLE' 'missing host telemetry must be distinct from mismatch'
Assert-Contains $skill 'BLOCKED' 'unproven execution must fail closed'
Assert-Contains $skill '`LUNA_MAX` capability is mandatory' 'Luna must be a required host capability'
Assert-Contains $skill 'HOST_ENABLEMENT_REQUIRED' 'missing Luna capability must request host enablement'
Assert-Contains $skill 'multi_agent_v1__spawn_agent' 'canonical native Luna surface must be documented'
Assert-Contains $skill 'THREAD_SURFACE_NOT_VISIBLE' 'thread-bound surface gaps must be classified'
Assert-Contains $skill 'USER_VISIBLE_TASK' 'explicit Desktop Luna task adapter must be documented'
Assert-Contains $skill 'EXPLICIT_USER_VISIBLE_TASK' 'Desktop task lane must require an explicit plan override'
Assert-Contains $skill 'codex_app__create_thread' 'Desktop task lane must name the host app surface'
Assert-Contains $skill 'does not call `setupStart`' 'Desktop task lane must avoid setup/ACL remediation'
Assert-Contains $skill 'Bounded recovery loop' 'skill must define a bounded recovery workflow after a block'
Assert-Contains $skill 'HOST_REMEDIATION_REQUIRED' 'skill must return an actionable host remediation state'
Assert-Contains $skill 'smallest official' 'skill must require minimal approved host changes'
Assert-Contains $skill 'minimal read-only probe' 'skill must require a post-remediation execution probe'

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
Assert-Contains $protocol 'Dispatch priority: NATIVE_FIRST_THEN_DESKTOP' 'plan must bind Luna to native-first then Desktop routing'
Assert-Contains $protocol 'Identity gate: HOST_DISPATCH | OPERATOR_ATTESTED | HOST_VERIFIED' 'protocol must expose the operator-attested identity gate'
Assert-Contains $protocol 'Operator attestation: REQUIRED | GRANTED | NOT_REQUIRED | UNKNOWN' 'protocol must record operator attestation state'
Assert-Contains $protocol 'OPERATOR_UI_ATTESTATION' 'protocol must classify operator UI evidence separately'
Assert-Contains $protocol 'Operator attestation: GRANTED | NOT_GRANTED | UNKNOWN' 'result packet must carry attestation state'
Assert-Contains $protocol 'Operator evidence:' 'result packet must carry operator evidence'
Assert-Contains $protocol 'HOST_MODEL_UNOBSERVABLE' 'protocol must distinguish missing telemetry from mismatch'
Assert-Contains $protocol 'Surface: AUTO | NATIVE_GENERIC | CUSTOM_ROLE | USER_VISIBLE_TASK' 'protocol must expose the explicit Desktop task surface'
Assert-Contains $protocol 'Dispatch priority: NATIVE_FIRST_THEN_DESKTOP | EXPLICIT_USER_VISIBLE_TASK' 'protocol must separate the normal ladder from the explicit task route'
Assert-Contains $protocol 'User-owned task: DENIED | ALLOWED | UNSPECIFIED' 'protocol must gate user-owned Desktop tasks'
Assert-Contains $protocol 'User approval: REQUIRED | GRANTED | NOT_REQUIRED | UNKNOWN' 'protocol must record explicit task approval'
Assert-Contains $protocol 'codex_app__create_thread' 'protocol must define the Desktop task invocation'
Assert-Contains $protocol 'silent model fallback' 'route failure must never silently replace the requested model'
Assert-Contains $protocol 'Recovery policy: BOUNDED_HOST_REMEDIATION' 'plan must declare bounded host recovery policy'
Assert-Contains $protocol 'Permission request:' 'protocol must carry an explicit permission request'
Assert-Contains $protocol 'External change evidence:' 'protocol must require evidence of host state change'
Assert-Contains $protocol 'route_trace' 'protocol must preserve every route decision and skip reason'
Assert-Contains $protocol 'Do not leave the caller' 'protocol must provide a next action when recovery remains possible'

Assert-Contains $adapters 'multi_agent_v1__spawn_agent' 'native adapter must name the generic worker surface'
Assert-Contains $adapters 'fork_context: false' 'native adapter must exclude controller history'
Assert-Contains $adapters 'agent_type: luna-max-worker' 'custom role adapter must name the role explicitly'
Assert-Contains $adapters 'fork_turns: none' 'custom role adapter must require a fresh fork'
Assert-Contains $adapters 'HOST_OBSERVED_MODEL_EFFORT' 'native identity must come from host observation'
Assert-Contains $adapters 'ROLE_MAPPING_AND_LAUNCH_RECORD' 'custom identity must come from host launch evidence'
Assert-Contains $adapters 'AGENT_HANDLE' 'agent handles must not be treated as identity proof'
Assert-Contains $adapters 'TOML/config alone is not proof' 'local role configuration must not self-authorize dispatch'
Assert-Contains $adapters 'ROLE_MAPPING_AND_LAUNCH_RECORD' 'custom-role launch record must be a distinct identity proof kind'
Assert-Contains $adapters 'reroute or conflicting' 'host reroutes must invalidate launch identity'
Assert-Contains $protocol 'HOST_LAUNCH_RECORDED' 'protocol must distinguish host launch from effective verification'
Assert-Contains $adapters 'Priority 1: current-thread native' 'adapter order must make current-thread native primary'
Assert-Contains $adapters 'Priority 2: USER_VISIBLE_TASK' 'adapter order must make Desktop task secondary'
Assert-Contains $adapters 'cannot impersonate `multi_agent_v1__spawn_agent`' 'legacy collaboration schema must not masquerade as canonical native v1'
Assert-Contains $adapters 'Adapter: USER_VISIBLE_TASK' 'runtime adapters must document the explicit Desktop task route'
Assert-Contains $adapters 'OPERATOR_UI_ATTESTED' 'runtime adapters must document operator-attested Desktop evidence'
Assert-Contains $adapters 'Identity: ATTESTED' 'runtime adapters must preserve the attested identity classification'
Assert-Contains $adapters 'User-owned task: ALLOWED' 'Desktop task adapter must require explicit user ownership permission'
Assert-Contains $adapters 'thinking="max"' 'Desktop task adapter must bind max effort'
Assert-Contains $adapters 'invokes `setupStart`' 'Desktop task adapter must prohibit setup/ACL remediation'

Assert-Contains $desktopTask 'codex_app__list_projects' 'Desktop task guide must require project discovery'
Assert-Contains $desktopTask 'codex_app__create_thread' 'Desktop task guide must define task creation'
Assert-Contains $desktopTask 'Dispatch priority: NATIVE_FIRST_THEN_DESKTOP' 'Desktop task guide must place the task route after native'
Assert-Contains $desktopTask 'model: "gpt-5.6-luna"' 'Desktop task guide must bind Luna'
Assert-Contains $desktopTask 'thinking: "max"' 'Desktop task guide must bind max effort'
Assert-Contains $desktopTask 'threadId' 'Desktop task guide must define a task-bound receipt'
Assert-Contains $desktopTask 'HOST_LAUNCH_RECORDED' 'Desktop task guide must gate host launch evidence'
Assert-Contains $desktopTask 'OPERATOR_UI_ATTESTED' 'Desktop task guide must document the explicit UI-attested gate'
Assert-Contains $desktopTask 'HOST_MODEL_UNOBSERVABLE' 'Desktop task guide must distinguish missing telemetry from mismatch'
Assert-Contains $desktopTask 'does not call `setupStart`' 'Desktop task guide must forbid sandbox setup/ACL changes'
Assert-Contains $desktopTask 'User-owned task: ALLOWED' 'Desktop task guide must honor the user-owned-task gate'

Assert-Contains $sources 'https://github.com/DannyMac180/sol-advisor' 'reference catalog must list sol-advisor'
Assert-Contains $sources 'https://github.com/yehyakin/codex-sol-control' 'reference catalog must list codex-sol-control'
Assert-Contains $sources 'https://learn.chatgpt.com/docs/app-server' 'reference catalog must list App Server documentation'
Assert-Contains $sources 'https://learn.chatgpt.com/docs/agent-configuration/subagents' 'reference catalog must list Subagents documentation'
Assert-Contains $sources 'https://openai.com/index/building-codex-windows-sandbox/' 'reference catalog must list Windows sandbox evidence'
Assert-Contains $sources 'windows-sandbox-rs/src/setup.rs' 'reference catalog must list sandbox setup source'
Assert-Contains $sources 'https://developers.openai.com/api/docs/models/gpt-5.6-luna' 'reference catalog must list Luna model reference'
Assert-Contains $sources 'issues/34399' 'reference catalog must list native allowlist evidence'
Assert-Contains $sources 'Route trade-offs, known problems, and mitigations' 'reference catalog must document route trade-offs'
Assert-Contains $sources 'Problem and solution catalog' 'reference catalog must document failure solutions'
Assert-Contains $sources 'GitHub publication risks and release checklist' 'reference catalog must document release risks'
Assert-Contains $sources 'license/attribution' 'reference catalog must document attribution risk'
Assert-Contains $sources 'per-file SHA-256' 'reference catalog must document source/runtime verification'
Assert-Contains $sources 'PROCESS_CREATION_DENIED' 'reference catalog must document sandbox blockers'
Assert-Contains $sources 'OPERATOR_UI_ATTESTED' 'reference catalog must document the operator-attested Desktop option'

Assert-Contains $enablement 'LUNA_MAX_REQUIRED' 'enablement packet must identify the required capability'
Assert-Contains $enablement 'gpt-5.6-luna / max' 'enablement packet must bind the Luna model and effort'
Assert-Contains $enablement 'NOT_ENABLED' 'host must report a missing capability explicitly'
Assert-Contains $enablement 'HOST_ENABLEMENT_REQUIRED' 'enablement failure must be actionable'
Assert-Contains $enablement 'must not be created' 'enablement must not use a user-owned task as a substitute'
Assert-Contains $enablement 'config.toml' 'config boundary must be documented'
Assert-Contains $enablement 'top-level Codex session' 'config.toml must be scoped to the top-level session'
Assert-Contains $enablement 'does not add a model' 'config.toml must not be treated as a worker allowlist'
Assert-Contains $enablement 'collaboration.spawn_agent' 'host-owned surface must be named explicitly'
Assert-Contains $enablement 'Native-first -> Desktop-task' 'enablement must preserve the Native/Desktop route priority ladder'
Assert-Contains $enablement 'HOST_REMEDIATION_REQUIRED' 'enablement must return an actionable remediation state'
Assert-Contains $enablement 'smallest' 'enablement must request minimal approved host repair'
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
Assert-Contains $registration 'multi_agent_v1__spawn_agent' 'registration guide must cover the alternate native wrapper'
Assert-Contains $registration 'fork_context: false' 'registration guide must cover the alternate fresh-context field'
Assert-Contains $registration 'AGENT_HANDLE' 'registration guide must classify returned agent ids'
Assert-Contains $registration 'THREAD_SURFACE_NOT_VISIBLE' 'registration guide must handle per-thread surface gaps'
Assert-Contains $registration 'user-visible app task' 'registration guide must separate app tasks from native workers'
Assert-Contains $registration 'Bounded recovery and permission request' 'registration must define bounded recovery attempts'
Assert-Contains $registration 'Approval: REQUIRED' 'registration must require explicit host/admin approval'
Assert-Contains $registration 'PROCESS_START=YES' 'registration must define the successful execution probe'
Assert-Contains $registration 'no broad user-root/full-control ACL' 'registration must prohibit broad ACL requests'

Assert-Contains $registration 'Priority 2 adapter: explicit Desktop Luna task lane' 'registration must document the priority-2 Desktop task route'
Assert-Contains $registration 'codex_app__create_thread' 'registration must define the Desktop task call'
Assert-Contains $registration 'User approval: GRANTED' 'registration must require explicit user approval'
Assert-Contains $registration 'OPERATOR_UI_ATTESTED' 'registration guide must document the operator-attested Desktop result'
Assert-Contains $registration 'HOST_MODEL_UNOBSERVABLE' 'registration guide must distinguish missing telemetry from mismatch'
Assert-Contains $registration 'do not request' 'registration must prohibit ACL remediation on this route'

Assert-Contains $readme 'README.en.md' 'README must expose the English companion'
Assert-Contains $readme 'sol-advisor' 'README must record the Sol advisor reference project'
Assert-Contains $readme 'codex-sol-control' 'README must record the Codex Sol control reference project'
Assert-Contains $readme 'USER_VISIBLE_TASK' 'README must document the explicit Desktop task alternative'
Assert-Contains $readme '不修改任何 ACL' 'README must document the no-ACL boundary'
Assert-Contains $readme '原生优先、Desktop task 次选' 'README must state the Native/Desktop route in its existing Chinese style'
Assert-Contains $readme 'HOST_REMEDIATION_REQUIRED' 'README must explain actionable recovery after a block'
Assert-Contains $readme 'OPERATOR_UI_ATTESTED' 'README must document the operator-attested Desktop option'
Assert-Contains $readme 'HOST_MODEL_UNOBSERVABLE' 'README must distinguish missing telemetry from mismatch'
Assert-Contains $readme '最小 read-only 探针' 'README must mention the post-permission probe'
Assert-Contains $readme 'references/sources.md' 'README must expose the complete reference catalog'
Assert-Contains $readme '主要事项与关键要点' 'README must summarize the main controls'

Assert-Contains $readmeEn 'Native-first -> Desktop-task' 'English README must state the Native/Desktop route priority'
Assert-Contains $readmeEn 'multi_agent_v1__spawn_agent' 'English README must name the canonical native surface'
Assert-Contains $readmeEn 'future equivalent' 'English README must require host-declared and verified future native surfaces'
Assert-Contains $readmeEn 'Never create a hidden or local alternate transport' 'English README must forbid hidden alternate transport'
Assert-Contains $readmeEn 'retain the requested `gpt-5.6-luna / max`' 'English README must preserve the requested Luna model and effort on route failure'
Assert-Contains $readmeEn 'BLOCKED' 'English README must fail closed when both Luna routes fail'
Assert-Contains $readmeEn 'USER_VISIBLE_TASK' 'English README must document the explicit Desktop task alternative'
Assert-Contains $readmeEn 'do not broaden permissions' 'English README must document the no-ACL boundary'
Assert-Contains $readmeEn 'HOST_REMEDIATION_REQUIRED' 'English README must expose actionable host recovery'
Assert-Contains $readmeEn 'OPERATOR_UI_ATTESTED' 'English README must document the operator-attested Desktop option'
Assert-Contains $readmeEn 'HOST_MODEL_UNOBSERVABLE' 'English README must distinguish missing telemetry from mismatch'
Assert-Contains $readmeEn 'minimal read-only probe' 'English README must require the post-repair probe'
Assert-Contains $readmeEn 'references/sources.md' 'English README must expose the complete reference catalog'
Assert-Contains $readmeEn 'GitHub publication gates' 'English README must summarize publication controls'

Assert-Contains $enablement 'USER_VISIBLE_TASK' 'enablement guide must separate the explicit Desktop task route'
Assert-Contains $enablement 'OPERATOR_ATTESTED' 'enablement guide must document the explicit operator-attested gate'
Assert-Contains $enablement 'HOST_MODEL_UNOBSERVABLE' 'enablement guide must distinguish missing telemetry from mismatch'
Assert-Contains $enablement 'User-owned task: ALLOWED' 'enablement guide must require explicit ownership permission'
Assert-Contains $enablement 'does not perform ACL/token remediation' 'enablement guide must prohibit ACL/token remediation'

Assert-NotContains $skill 'gpt-5.6-terra' 'Terra must not become a normal Sol lane'
Assert-NotContains $protocol 'gpt-5.6-terra' 'Terra must not become a normal Sol lane'

Write-Output 'PASS: Sol runtime adapter protocol contract'
