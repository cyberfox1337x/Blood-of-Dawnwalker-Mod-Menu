[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Verify', 'VerifyPayload', 'Install', 'PromoteDumpProfile', 'PromoteBridgePilot', 'Rollback')]
    [string]$Action = 'Verify',
    [string]$ContractPath,
    [string]$ArchivePath,
    [string]$SmokeLogPath,
    [switch]$ReplaceExisting,
    [switch]$ApproveCleanSmokeLog,
    [switch]$ApproveHookEngineTickPilot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory = $true)][string]$ModuleName)
    return $ModuleName
}

$null = cyberfox1337x -ModuleName 'install_dawnwalker_reflection_tools'
if ([string]::IsNullOrWhiteSpace($ContractPath)) {
    $ContractPath = Join-Path $PSScriptRoot 'official-build.json'
}
Import-Module (Join-Path $PSScriptRoot 'DawnwalkerReflectionTools.psm1') -Force
$contract = Read-DawnwalkerJsonFile -LiteralPath $ContractPath
if (-not $ArchivePath) {
    $ArchivePath = Join-Path $PSScriptRoot ([string]$contract.ue4ss.archiveRelativePath)
}

switch ($Action) {
    'Verify' {
        Test-DawnwalkerOfficialBuild -ContractPath $ContractPath | ConvertTo-Json -Depth 10
    }
    'VerifyPayload' {
        Test-DawnwalkerUe4ssArchive -ContractPath $ContractPath -ArchivePath $ArchivePath | ConvertTo-Json -Depth 10
    }
    'Install' {
        Invoke-DawnwalkerReflectionInstall -ContractPath $ContractPath -ArchivePath $ArchivePath -ReplaceExisting:$ReplaceExisting -WhatIf:$WhatIfPreference -Confirm:$false | ConvertTo-Json -Depth 10
    }
    'PromoteDumpProfile' {
        $parameters = @{
            ContractPath = $ContractPath
            ApproveCleanSmokeLog = $ApproveCleanSmokeLog
            WhatIf = $WhatIfPreference
            Confirm = $false
        }
        if ($SmokeLogPath) { $parameters.SmokeLogPath = $SmokeLogPath }
        Enable-DawnwalkerDumpProfile @parameters | ConvertTo-Json -Depth 10
    }
    'PromoteBridgePilot' {
        $parameters = @{
            ContractPath = $ContractPath
            ApproveCleanSmokeLog = $ApproveCleanSmokeLog
            ApproveHookEngineTickPilot = $ApproveHookEngineTickPilot
            WhatIf = $WhatIfPreference
            Confirm = $false
        }
        if ($SmokeLogPath) { $parameters.SmokeLogPath = $SmokeLogPath }
        Enable-DawnwalkerBridgePilot @parameters | ConvertTo-Json -Depth 12
    }
    'Rollback' {
        Invoke-DawnwalkerReflectionRollback -ContractPath $ContractPath -WhatIf:$WhatIfPreference -Confirm:$false | ConvertTo-Json -Depth 10
    }
}
