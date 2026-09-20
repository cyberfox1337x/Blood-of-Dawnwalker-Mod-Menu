[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory)][string]$ModuleName)
    return $ModuleName
}

$null = cyberfox1337x -ModuleName 'dawnwalker_packaging_contract_tests'

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Rejected {
    param(
        [Parameter(Mandatory)][scriptblock]$Operation,
        [Parameter(Mandatory)][string]$ExpectedMessage,
        [Parameter(Mandatory)][string]$Label
    )

    $caught = $null
    try { & $Operation | Out-Null } catch { $caught = $_ }
    Assert-True -Condition ($null -ne $caught) -Message "$Label was accepted"
    Assert-True -Condition ($caught.Exception.Message -match $ExpectedMessage) -Message "$Label returned the wrong rejection: $($caught.Exception.Message)"
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$LiteralPath)

    $stream = [IO.File]::OpenRead($LiteralPath)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '')
    }
    finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$packagePath = Join-Path $projectRoot 'package.json'
$installerIncludePath = Join-Path $projectRoot 'installer\installer.nsh'
$luaValidatorPath = Join-Path $PSScriptRoot 'Test-DawnwalkerLua.ps1'
$packagedValidatorPath = Join-Path $PSScriptRoot 'Assert-DawnwalkerPackagedInstaller.ps1'
$package = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json

Assert-True -Condition ($package.cyberfox1337x -ceq 'function(package_manifest)') -Message 'package signature is invalid'
$windowsTargets = @($package.build.win.target)
Assert-True -Condition ($windowsTargets.Count -eq 1 -and [string]$windowsTargets[0].target -ceq 'nsis') -Message 'Windows build exposes a non-NSIS target'
Assert-True -Condition (@($windowsTargets[0].arch).Count -eq 1 -and [string]$windowsTargets[0].arch[0] -ceq 'x64') -Message 'Windows build architecture is not exactly x64'
Assert-True -Condition (-not ($package.build.PSObject.Properties.Name -contains 'portable')) -Message 'portable build configuration returned'
Assert-True -Condition ([string]$package.scripts.'package:win' -notmatch '(?i)\bportable\b') -Message 'package:win requests a portable artifact'
Assert-True -Condition ([string]$package.scripts.'package:qa' -notmatch '(?i)\bportable\b') -Message 'package:qa requests a portable artifact'
Assert-True -Condition ([string]$package.scripts.'verify:packaged-installer' -match 'Assert-DawnwalkerPackagedInstaller\.ps1.+production') -Message 'production post-build validator is not configured'
Assert-True -Condition ([string]$package.scripts.'prepare:runtime' -match 'Prepare-DawnwalkerRuntimePayload\.ps1.+-PayloadPhase production') -Message 'production payload preparation is not explicitly phase-locked'
Assert-True -Condition ([string]$package.scripts.'prepare:runtime:qa' -match 'Prepare-DawnwalkerRuntimePayload\.ps1.+-PayloadPhase discovery') -Message 'QA payload preparation is not explicitly discovery-locked'
Assert-True -Condition ([string]$package.scripts.'test:lua:qa' -match 'Test-DawnwalkerLua\.ps1.+installer/templates/ue4ss/Mods/DawnwalkerModBridge/Scripts/main\.lua') -Message 'QA Lua validation does not use the inert discovery source'

$packageWin = [string]$package.scripts.'package:win'
$orderedStages = @(
    'npm run lint',
    'npm test',
    'npm run test:package-contract',
    'npm run prepare:runtime',
    'npm run test:lua',
    'npm run test:runtime-installer',
    'npm run test:release-gate',
    'npm run build',
    'npm run verify:release-ready',
    'electron-builder --win nsis',
    'npm run verify:packaged-installer'
)
$previousIndex = -1
foreach ($stage in $orderedStages) {
    $stageIndex = $packageWin.IndexOf($stage, [StringComparison]::Ordinal)
    Assert-True -Condition ($stageIndex -gt $previousIndex) -Message "package:win is missing or misorders '$stage'"
    $previousIndex = $stageIndex
}

$packageQa = [string]$package.scripts.'package:qa'
$orderedQaStages = @(
    'npm run lint',
    'npm test',
    'npm run test:package-contract',
    'npm run prepare:runtime:qa',
    'npm run test:lua:qa',
    'npm run test:runtime-installer',
    'npm run test:release-gate',
    'npm run build',
    'electron-builder --win nsis --config.directories.output=release-qa',
    'npm run verify:packaged-installer:qa'
)
$previousIndex = -1
foreach ($stage in $orderedQaStages) {
    $stageIndex = $packageQa.IndexOf($stage, [StringComparison]::Ordinal)
    Assert-True -Condition ($stageIndex -gt $previousIndex) -Message "package:qa is missing or misorders '$stage'"
    $previousIndex = $stageIndex
}

$installerInclude = Get-Content -LiteralPath $installerIncludePath -Raw -Encoding UTF8
Assert-True -Condition ($installerInclude -match '!macro cyberfox1337x_function') -Message 'NSIS signature macro is missing'
Assert-True -Condition ($installerInclude -match '!define DAWNWALKER_RUNTIME_HELPER .+DawnwalkerRuntimeInstaller\.ps1') -Message 'NSIS runtime helper path is missing'
Assert-True -Condition ($installerInclude -match '(?s)!macro customInstall.+DAWNWALKER_RUNTIME_HELPER.+-Action Install') -Message 'NSIS install hook no longer invokes the runtime installer'
Assert-True -Condition ($installerInclude -match '(?s)!macro customUnInstall.+DAWNWALKER_RUNTIME_HELPER.+-Action Uninstall') -Message 'NSIS uninstall hook no longer restores the runtime baseline'

$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$temporaryRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('dawnwalker-packaging-contract-test-' + [Guid]::NewGuid().ToString('N'))))
if (-not $temporaryRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe packaging-test directory: $temporaryRoot"
}

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null

    $luaSourcePath = Join-Path $temporaryRoot 'main.lua'
    $luaPreparedPath = Join-Path $temporaryRoot 'prepared-main.lua'
    $luaManifestPath = Join-Path $temporaryRoot 'payload-manifest.json'
    $luaSource = @'
local cyberfox1337x = {}
function cyberfox1337x.function_signature(_) return true end
cyberfox1337x.function_signature("dawnwalker_mod_bridge")
local BRIDGE_VERSION = "0.0.0-discovery"
local BRIDGE_PHASE = "discovery"
local CAPABILITIES = ""
return { version = BRIDGE_VERSION, phase = BRIDGE_PHASE, capabilities = CAPABILITIES }
'@
    [IO.File]::WriteAllText($luaSourcePath, $luaSource, [Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath $luaSourcePath -Destination $luaPreparedPath
    $luaHash = Get-Sha256 -LiteralPath $luaSourcePath
    $luaManifest = [ordered]@{
        cyberfox1337x = 'function(dawnwalker_runtime_payload_manifest)'
        schemaVersion = 1
        phase = 'discovery'
        bridgeVersion = '0.0.0-discovery'
        gameplayCapabilities = @()
        overlays = @([ordered]@{
            targetPath = 'ue4ss/Mods/DawnwalkerModBridge/Scripts/main.lua'
            sha256 = $luaHash
        })
    }
    [IO.File]::WriteAllText($luaManifestPath, ($luaManifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    $luaResult = & $luaValidatorPath -BridgeSourcePath $luaSourcePath -PreparedBridgePath $luaPreparedPath -PayloadManifestPath $luaManifestPath | ConvertFrom-Json
    Assert-True -Condition ([bool]$luaResult.valid) -Message 'valid Lua fixture did not pass syntax and payload validation'

    [IO.File]::AppendAllText($luaSourcePath, [Environment]::NewLine + 'local = broken', [Text.UTF8Encoding]::new($false))
    Assert-Rejected -Operation {
        & $luaValidatorPath -BridgeSourcePath $luaSourcePath -SourceOnly
    } -ExpectedMessage 'luac rejected' -Label 'invalid Lua syntax'
    [IO.File]::WriteAllText($luaSourcePath, $luaSource.Replace('local BRIDGE_PHASE = "discovery"', 'local BRIDGE_PHASE = "pilot"'), [Text.UTF8Encoding]::new($false))
    Assert-Rejected -Operation {
        & $luaValidatorPath -BridgeSourcePath $luaSourcePath -SourceOnly
    } -ExpectedMessage 'phase is not packageable' -Label 'pilot Lua phase'

    $applicationRoot = Join-Path $temporaryRoot 'application'
    $applicationResources = Join-Path $applicationRoot 'resources'
    $packagedRuntimeRoot = Join-Path $applicationResources 'dawnwalker-runtime'
    New-Item -ItemType Directory -Path $applicationResources -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'installer\runtime') -Destination $packagedRuntimeRoot -Recurse
    Copy-Item -LiteralPath (Join-Path $projectRoot 'installer\DawnwalkerRuntimeInstaller.ps1') -Destination (Join-Path $packagedRuntimeRoot 'DawnwalkerRuntimeInstaller.ps1')
    $runtimeManifest = Get-Content -LiteralPath (Join-Path $packagedRuntimeRoot 'payload-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $fixturePhase = [string]$runtimeManifest.phase
    Assert-True -Condition ($fixturePhase -eq 'discovery' -or $fixturePhase -eq 'production') -Message 'prepared runtime fixture has an unsupported phase'
    $packagedDependencies = @($runtimeManifest.requiredRuntimeDependencies)
    Assert-True -Condition ($packagedDependencies.Count -eq 1) -Message 'packaged runtime does not declare exactly one required dependency'
    Assert-True -Condition (
        [string]$packagedDependencies[0].relativePath -ceq 'ue4ss/Mods/shared/UEHelpers/UEHelpers.lua' -and
        [long]$packagedDependencies[0].bytes -eq 10237 -and
        [string]$packagedDependencies[0].sha256 -ceq '7476F02EEF0C87BFEAB169F2FFE2E704363FAEAAE4BF9F1BDA574B1E34F4A0E9'
    ) -Message 'packaged runtime UEHelpers dependency identity differs from the reviewed pin'
    $packagedResult = & $packagedValidatorPath -ExtractedApplicationRoot $applicationRoot -ExpectedPhase $fixturePhase | ConvertFrom-Json
    Assert-True -Condition ([bool]$packagedResult.valid) -Message 'exact extracted runtime fixture failed package validation'

    $unexpectedRuntimeFile = Join-Path $packagedRuntimeRoot 'unexpected-portable-placeholder.bin'
    [IO.File]::WriteAllText($unexpectedRuntimeFile, 'runtime-less portable regression', [Text.UTF8Encoding]::new($false))
    Assert-Rejected -Operation {
        & $packagedValidatorPath -ExtractedApplicationRoot $applicationRoot -ExpectedPhase $fixturePhase
    } -ExpectedMessage 'inventory differs' -Label 'unexpected packaged runtime file'
    Remove-Item -LiteralPath $unexpectedRuntimeFile -Force

    $oppositePhase = if ($fixturePhase -eq 'production') { 'discovery' } else { 'production' }
    Assert-Rejected -Operation {
        & $packagedValidatorPath -ExtractedApplicationRoot $applicationRoot -ExpectedPhase $oppositePhase
    } -ExpectedMessage 'does not match required phase' -Label 'wrong packaged release phase'

    $releaseFixture = Join-Path $temporaryRoot 'release-with-portable'
    New-Item -ItemType Directory -Path $releaseFixture -Force | Out-Null
    $expectedSetupName = "$($package.build.productName)-Setup-$($package.version)-x64.exe"
    [IO.File]::WriteAllBytes((Join-Path $releaseFixture $expectedSetupName), [byte[]](0x4D, 0x5A))
    [IO.File]::WriteAllBytes(
        (Join-Path $releaseFixture "$($package.build.productName)-Portable-$($package.version)-x64.exe"),
        [byte[]](0x4D, 0x5A)
    )
    Assert-Rejected -Operation {
        & $packagedValidatorPath -ReleaseDirectory $releaseFixture -ExpectedPhase $fixturePhase
    } -ExpectedMessage 'exactly one top-level executable' -Label 'release output containing a portable executable'
}
finally {
    $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
    if (Test-Path -LiteralPath $resolvedTemporaryRoot) {
        if (-not $resolvedTemporaryRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unsafe packaging-test directory: $resolvedTemporaryRoot"
        }
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
    }
}

[pscustomobject]@{
    cyberfox1337x = 'function(dawnwalker_packaging_contract_test_result)'
    passed = $true
    target = 'nsis-x64-only'
    portable = $false
    pipelineStages = $orderedStages
} | ConvertTo-Json -Depth 5
