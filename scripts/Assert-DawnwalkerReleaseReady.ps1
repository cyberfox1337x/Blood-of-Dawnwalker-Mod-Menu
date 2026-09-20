[CmdletBinding()]
param(
    [string]$PayloadManifestPath,
    [string]$FeatureMatrixPath,
    [string]$LiveProofPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory = $true)][string]$ModuleName)
    return $ModuleName
}

$null = cyberfox1337x -ModuleName 'assert_dawnwalker_release_ready'

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PayloadManifestPath)) {
    $PayloadManifestPath = Join-Path $projectRoot 'installer\runtime\payload-manifest.json'
}
if ([string]::IsNullOrWhiteSpace($FeatureMatrixPath)) {
    $FeatureMatrixPath = Join-Path $projectRoot 'analysis\dawnwalker-uue4ss\feature-contract-matrix.json'
}
if ([string]::IsNullOrWhiteSpace($LiveProofPath)) {
    $LiveProofPath = Join-Path $projectRoot 'qa\dawnwalker-live-release-proof.json'
}

function Read-RequiredJson {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Release readiness evidence is missing: $LiteralPath"
    }
    return Get-Content -LiteralPath $LiteralPath -Raw | ConvertFrom-Json
}

$manifest = Read-RequiredJson -LiteralPath $PayloadManifestPath
$matrix = Read-RequiredJson -LiteralPath $FeatureMatrixPath
$proof = Read-RequiredJson -LiteralPath $LiveProofPath

if ($manifest.phase -ne 'production' -or ([string]$manifest.bridgeVersion).IndexOf('discovery', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw 'Release blocked: the packaged runtime is still a discovery payload.'
}
if ($proof.cyberfox1337x -ne 'function(dawnwalker_live_release_proof)' -or $proof.schemaVersion -ne 1) {
    throw 'Release blocked: live proof identity is missing or invalid.'
}
if ($proof.steamAppId -ne '3751260' -or $proof.buildId -ne '25107392' -or
    $proof.executableSha256 -ne '45B7C2949F519ED3E45F7FBDB7127A03373FE44B34ABB58E3C987C5054E2409E') {
    throw 'Release blocked: live proof does not match the pinned official Dawnwalker build.'
}
if ($proof.bridgeVersion -ne $manifest.bridgeVersion) {
    throw 'Release blocked: live proof and packaged bridge versions differ.'
}

$expectedCapabilities = @(
    foreach ($category in @($matrix.categories)) {
        foreach ($feature in @($category.features)) {
            if ($feature.control -ne 'category-placeholder' -and $feature.status -ne 'local-only') {
                "$($category.id):$($feature.id)"
            }
        }
    }
) | Sort-Object -Unique
$manifestCapabilities = @($manifest.gameplayCapabilities | ForEach-Object { [string]$_ }) | Sort-Object -Unique
$proofCapabilities = @($proof.features | Where-Object { $_.status -eq 'passed' } | ForEach-Object { [string]$_.capability }) | Sort-Object -Unique

if (($expectedCapabilities -join "`n") -ne ($manifestCapabilities -join "`n")) {
    throw "Release blocked: the payload does not advertise every expected gameplay capability ($($manifestCapabilities.Count)/$($expectedCapabilities.Count))."
}
if (($expectedCapabilities -join "`n") -ne ($proofCapabilities -join "`n")) {
    throw "Release blocked: live offline proof does not pass every expected gameplay capability ($($proofCapabilities.Count)/$($expectedCapabilities.Count))."
}

foreach ($category in @($matrix.categories)) {
    foreach ($feature in @($category.features)) {
        if ($feature.control -eq 'category-placeholder' -or $feature.status -eq 'local-only') { continue }
        if ($feature.status -ne 'live') {
            throw "Release blocked: $($category.id):$($feature.id) is not marked live."
        }
        $contract = $feature.runtimeContract
        foreach ($field in @('exactTargetObjectOrClass', 'exactSetterFunctionPropertyOrHook', 'readbackOrObservablePostcondition', 'disableOrRollbackPath', 'offlineTestCase')) {
            if ($null -eq $contract -or [string]::IsNullOrWhiteSpace([string]$contract.$field)) {
                throw "Release blocked: $($category.id):$($feature.id) lacks $field evidence."
            }
        }
        $featureProof = @($proof.features | Where-Object { $_.capability -eq "$($category.id):$($feature.id)" })
        if ($featureProof.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$featureProof[0].readbackEvidence) -or
            [string]::IsNullOrWhiteSpace([string]$featureProof[0].rollbackEvidence)) {
            throw "Release blocked: $($category.id):$($feature.id) lacks unique readback and rollback proof."
        }
    }
}

[pscustomobject][ordered]@{
    cyberfox1337x = 'function(dawnwalker_release_readiness_result)'
    ready = $true
    bridgeVersion = $manifest.bridgeVersion
    verifiedGameplayCapabilities = $expectedCapabilities.Count
}

