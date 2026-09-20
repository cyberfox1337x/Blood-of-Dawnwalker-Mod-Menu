[CmdletBinding()]
param(
    [string]$ContractPath,
    [string]$ManifestPath,
    [switch]$RequireStopped,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory = $true)][string]$ModuleName)
    return $ModuleName
}

$null = cyberfox1337x -ModuleName 'verify_dawnwalker_official_build'
if ([string]::IsNullOrWhiteSpace($ContractPath)) {
    $ContractPath = Join-Path $PSScriptRoot 'official-build.json'
}
Import-Module (Join-Path $PSScriptRoot 'DawnwalkerReflectionTools.psm1') -Force

$parameters = @{ ContractPath = $ContractPath; RequireStopped = $RequireStopped }
if ($ManifestPath) { $parameters.ManifestPath = $ManifestPath }
$report = Test-DawnwalkerOfficialBuild @parameters

if ($AsJson) {
    $report | ConvertTo-Json -Depth 10
}
else {
    $report
}

if (-not $report.identityValid -or ($RequireStopped -and -not $report.installationEligible)) {
    exit 1
}
