[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory = $true)][string]$ModuleName)
    return $ModuleName
}

$null = cyberfox1337x -ModuleName 'assert_dawnwalker_release_ready_tests'
$scriptPath = Join-Path $PSScriptRoot 'Assert-DawnwalkerReleaseReady.ps1'
$prepareScriptPath = Join-Path $PSScriptRoot 'Prepare-DawnwalkerRuntimePayload.ps1'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("dawnwalker-release-gate-test-{0}" -f [Guid]::NewGuid().ToString('N'))
$resolvedTemporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
if (-not $resolvedTemporaryRoot.StartsWith($resolvedTemporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe release-gate test path: $resolvedTemporaryRoot"
}

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) { throw $Message }
}

function Assert-ThrowsLike {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$ExpectedMessage,
        [Parameter(Mandatory)][string]$Message
    )

    try {
        $null = & $Action
    }
    catch {
        if ($_.Exception.Message -match $ExpectedMessage) { return }
        throw "$Message Unexpected error: $($_.Exception.Message)"
    }
    throw $Message
}

function Import-FunctionDefinition {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$FunctionName
    )

    $tokens = $null
    $parseErrors = $null
    $scriptAst = [Management.Automation.Language.Parser]::ParseFile($LiteralPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Unable to parse $LiteralPath for isolated function testing."
    }
    $functionAst = $scriptAst.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $FunctionName
    }, $true)
    if (-not $functionAst) { throw "Function $FunctionName was not found in $LiteralPath" }
    Set-Item -Path ("Function:\global:{0}" -f $FunctionName) -Value $functionAst.Body.GetScriptBlock()
}

try {
    $null = New-Item -ItemType Directory -Path $resolvedTemporaryRoot -Force
    $manifestPath = Join-Path $resolvedTemporaryRoot 'payload-manifest.json'
    $matrixPath = Join-Path $resolvedTemporaryRoot 'feature-matrix.json'
    $proofPath = Join-Path $resolvedTemporaryRoot 'proof.json'

    $runtimeContract = [ordered]@{
        exactTargetObjectOrClass = '/Script/Test.Target'
        exactSetterFunctionPropertyOrHook = 'SetHealthPercent'
        readbackOrObservablePostcondition = 'GetHealthPercentage'
        disableOrRollbackPath = 'UnlockHealth and restore captured percentage'
        offlineTestCase = 'isolated synthetic test contract'
    }
    [ordered]@{
        cyberfox1337x = 'function(dawnwalker_feature_contract_matrix)'
        schemaVersion = 1
        categories = @(
            [ordered]@{
                id = 'player'
                features = @(
                    [ordered]@{
                        id = 'infinite-health'
                        label = 'Infinite Health'
                        control = 'toggle'
                        status = 'live'
                        runtimeContract = $runtimeContract
                    },
                    [ordered]@{
                        id = 'unlimited-stamina'
                        label = 'Unlimited Stamina'
                        control = 'toggle'
                        status = 'live'
                        runtimeContract = $runtimeContract
                    }
                )
            }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $matrixPath -Encoding utf8

    $manifest = [ordered]@{
        cyberfox1337x = 'function(dawnwalker_runtime_payload_manifest)'
        schemaVersion = 1
        phase = 'discovery'
        bridgeVersion = '0.1.0-discovery'
        gameplayCapabilities = @()
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    $proof = [ordered]@{
        cyberfox1337x = 'function(dawnwalker_live_release_proof)'
        schemaVersion = 1
        steamAppId = '3751260'
        buildId = '25107392'
        executableSha256 = '45B7C2949F519ED3E45F7FBDB7127A03373FE44B34ABB58E3C987C5054E2409E'
        bridgeVersion = '0.1.0-discovery'
        features = @()
    }
    $proof | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $proofPath -Encoding utf8

    Assert-ThrowsLike `
        -Action { & $scriptPath -PayloadManifestPath $manifestPath -FeatureMatrixPath $matrixPath -LiveProofPath $proofPath } `
        -ExpectedMessage 'still a discovery payload' `
        -Message 'Release readiness gate did not reject the discovery payload.'

    $manifest.phase = 'production'
    $manifest.bridgeVersion = '1.0.0-synthetic-verified'
    $manifest.gameplayCapabilities = @('player:infinite-health', 'player:unlimited-stamina')
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    $proof.bridgeVersion = $manifest.bridgeVersion
    $proof.features = @(
        [ordered]@{
            capability = 'player:infinite-health'
            status = 'passed'
            readbackEvidence = 'health remained full during isolated synthetic damage probe'
            rollbackEvidence = 'health lock disabled and captured percentage restored'
        },
        [ordered]@{
            capability = 'player:unlimited-stamina'
            status = 'passed'
            readbackEvidence = 'stamina remained full during isolated synthetic action probe'
            rollbackEvidence = 'stamina lock disabled and captured percentage restored'
        }
    )
    $proof | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $proofPath -Encoding utf8
    $readyResult = & $scriptPath -PayloadManifestPath $manifestPath -FeatureMatrixPath $matrixPath -LiveProofPath $proofPath
    Assert-True -Condition ([bool]$readyResult.ready) -Message 'A complete internally consistent production proof did not pass the release gate.'
    Assert-True -Condition ([int]$readyResult.verifiedGameplayCapabilities -eq 2) -Message 'Release gate returned the wrong verified capability count.'

    $manifest.gameplayCapabilities = @('player:infinite-health', 'player:unlimited-stamina', 'world:weather')
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    Assert-ThrowsLike `
        -Action { & $scriptPath -PayloadManifestPath $manifestPath -FeatureMatrixPath $matrixPath -LiveProofPath $proofPath } `
        -ExpectedMessage 'does not advertise every expected gameplay capability' `
        -Message 'Release readiness gate accepted tampered production capability metadata.'

    $manifest.gameplayCapabilities = @('player:infinite-health', 'player:unlimited-stamina')
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    $proof.features[0].rollbackEvidence = ''
    $proof | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $proofPath -Encoding utf8
    Assert-ThrowsLike `
        -Action { & $scriptPath -PayloadManifestPath $manifestPath -FeatureMatrixPath $matrixPath -LiveProofPath $proofPath } `
        -ExpectedMessage 'lacks unique readback and rollback proof' `
        -Message 'Release readiness gate accepted production proof without rollback evidence.'

    Import-FunctionDefinition -LiteralPath $prepareScriptPath -FunctionName 'Get-DawnwalkerIniValue'
    Import-FunctionDefinition -LiteralPath $prepareScriptPath -FunctionName 'Assert-DawnwalkerProductionHookProof'
    $settingsPath = Join-Path $resolvedTemporaryRoot 'UE4SS-settings.ini'
    @('[Hooks]', 'HookEngineTick = 1') | Set-Content -LiteralPath $settingsPath -Encoding ascii
    $hookProofPath = Join-Path $resolvedTemporaryRoot 'hook-proof.json'
    $bridgeMetadata = [pscustomobject]@{
        phase = 'production'
        bridgeVersion = '1.0.0-synthetic-verified'
        gameplayCapabilities = @('player:infinite-health')
    }
    $contract = [pscustomobject]@{
        steam = [pscustomobject]@{ appId = '3751260'; buildId = '25107392' }
        executable = [pscustomobject]@{ sha256 = '45B7C2949F519ED3E45F7FBDB7127A03373FE44B34ABB58E3C987C5054E2409E' }
    }
    Assert-ThrowsLike `
        -Action { Assert-DawnwalkerProductionHookProof -BridgeMetadata $bridgeMetadata -Contract $contract -SettingsLiteralPath $settingsPath -ProofLiteralPath $hookProofPath } `
        -ExpectedMessage 'requires isolated HookEngineTick proof' `
        -Message 'Production payload metadata accepted a missing HookEngineTick proof marker.'

    $hookProof = [ordered]@{
        cyberfox1337x = 'function(dawnwalker_hook_engine_tick_live_proof)'
        schemaVersion = 1
        status = 'passed'
        hook = 'HookEngineTick'
        hookValue = '1'
        isolatedOffline = $true
        steamAppId = '3751260'
        buildId = '25107392'
        executableSha256 = '45B7C2949F519ED3E45F7FBDB7127A03373FE44B34ABB58E3C987C5054E2409E'
        bridgeVersion = 'wrong-bridge-version'
    }
    $hookProof | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $hookProofPath -Encoding utf8
    Assert-ThrowsLike `
        -Action { Assert-DawnwalkerProductionHookProof -BridgeMetadata $bridgeMetadata -Contract $contract -SettingsLiteralPath $settingsPath -ProofLiteralPath $hookProofPath } `
        -ExpectedMessage 'proof is invalid' `
        -Message 'Production payload metadata accepted HookEngineTick proof for another bridge.'

    $hookProof.bridgeVersion = $bridgeMetadata.bridgeVersion
    $hookProof | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $hookProofPath -Encoding utf8
    $hookValue = Assert-DawnwalkerProductionHookProof -BridgeMetadata $bridgeMetadata -Contract $contract -SettingsLiteralPath $settingsPath -ProofLiteralPath $hookProofPath
    Assert-True -Condition ($hookValue -eq '1') -Message 'Valid production HookEngineTick proof did not return the required hook value.'

    @('[Hooks]', 'HookEngineTick = 1', 'HookUObjectProcessEvent = 1') | Set-Content -LiteralPath $settingsPath -Encoding ascii
    Assert-ThrowsLike `
        -Action { Assert-DawnwalkerProductionHookProof -BridgeMetadata $bridgeMetadata -Contract $contract -SettingsLiteralPath $settingsPath -ProofLiteralPath $hookProofPath } `
        -ExpectedMessage 'sets only HookEngineTick=1' `
        -Message 'Production payload metadata accepted an unapproved second UE4SS hook.'
}
finally {
    if (Test-Path -LiteralPath $resolvedTemporaryRoot) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
    }
}

Write-Output 'Dawnwalker release readiness gate tests passed.'
