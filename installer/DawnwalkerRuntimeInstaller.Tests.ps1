[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory)][string]$ModuleName)
}

cyberfox1337x -ModuleName 'dawnwalker_runtime_installer_tests'

$helperPath = Join-Path $PSScriptRoot 'DawnwalkerRuntimeInstaller.ps1'
$runtimeRoot = Join-Path $PSScriptRoot 'runtime'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    throw "Runtime installer helper is missing: $helperPath"
}
if (-not (Test-Path -LiteralPath (Join-Path $runtimeRoot 'payload-manifest.json') -PathType Leaf)) {
    throw "Prepared runtime payload is missing. Run npm run prepare:runtime first: $runtimeRoot"
}

$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$wrapperOutput = (& $windowsPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helperPath -Action VerifyPayload 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $wrapperOutput -notmatch 'Verified \d+ (discovery|production)-phase runtime payload files with \d+ compiled gameplay capabilities') {
    throw "Default workspace payload resolution failed through powershell.exe -File: $wrapperOutput"
}

# Dot-sourcing loads the helper functions without invoking its Steam/game entry point.
. $helperPath -Action VerifyPayload -PayloadRoot $runtimeRoot

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param(
        [AllowNull()]$Actual,
        [AllowNull()]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected='$Expected' Actual='$Actual'"
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$Message
    )

    $threw = $false
    try { $null = & $Action }
    catch { $threw = $true }
    if (-not $threw) { throw $Message }
}

$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'

function Assert-SafeTemporaryPath {
    param([Parameter(Mandatory)][string]$LiteralPath)

    $resolvedPath = [IO.Path]::GetFullPath($LiteralPath)
    if (-not $resolvedPath.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing unsafe test path: $resolvedPath"
    }
    return $resolvedPath
}

function Remove-SafeTestTree {
    param([Parameter(Mandatory)][string]$LiteralPath)

    $resolvedPath = Assert-SafeTemporaryPath -LiteralPath $LiteralPath
    if (Test-Path -LiteralPath $resolvedPath) {
        Remove-Item -LiteralPath $resolvedPath -Recurse -Force
    }
}

function Add-IniEntry {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )

    $header = "[$Section]"
    $sectionIndex = -1
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index].Trim().Equals($header, [StringComparison]::OrdinalIgnoreCase)) {
            $sectionIndex = $index
            break
        }
    }
    if ($sectionIndex -lt 0) {
        $Lines.Add($header)
        $Lines.Add("$Key = $Value")
        return
    }

    $insertionIndex = $Lines.Count
    for ($index = $sectionIndex + 1; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match '^\s*\[[^\]]+\]\s*$') {
            $insertionIndex = $index
            break
        }
    }
    $Lines.Insert($insertionIndex, "$Key = $Value")
}

function Update-TestOverlayMetadata {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$RuntimeRoot,
        [Parameter(Mandatory)][string]$TargetPath
    )

    $overlays = @($Manifest.overlays | Where-Object { ([string]$_.targetPath).Replace('\', '/') -eq $TargetPath })
    if ($overlays.Count -ne 1) { throw "Synthetic payload is missing overlay metadata for $TargetPath" }
    $overlayPath = Get-SafeChildPath -Root $RuntimeRoot -RelativePath ([string]$overlays[0].packagePath)
    $overlays[0].sha256 = Get-Sha256 -LiteralPath $overlayPath

    $payloadEntries = @($Manifest.payloadFiles | Where-Object { ([string]$_.relativePath).Replace('\', '/') -eq $TargetPath })
    if ($payloadEntries.Count -ne 1) { throw "Synthetic payload is missing file metadata for $TargetPath" }
    $payloadEntries[0].bytes = (Get-Item -LiteralPath $overlayPath).Length
    $payloadEntries[0].sha256 = Get-Sha256 -LiteralPath $overlayPath
}

$testRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('dawnwalker-installer-tests-' + [guid]::NewGuid().ToString('N'))))
$null = Assert-SafeTemporaryPath -LiteralPath $testRoot

$originalProgramData = $env:ProgramData
$originalStateRoot = $script:StateRoot
$originalStatePath = $script:StatePath
$originalBaselineRoot = $script:BaselineRoot
$payload = $null
$productionPayload = $null

New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
    Assert-Throws -Action { Get-SafeChildPath -Root $testRoot -RelativePath '..\escape.txt' } -Message 'Traversal was not rejected.'
    Assert-Throws -Action { Get-SafeChildPath -Root $testRoot -RelativePath 'nested\..\escape.txt' } -Message 'Nested traversal was not rejected.'
    Assert-Throws -Action { Get-SafeChildPath -Root $testRoot -RelativePath 'C:\absolute.txt' } -Message 'A rooted path was not rejected.'
    $safeNestedPath = Get-SafeChildPath -Root $testRoot -RelativePath 'ue4ss/Mods/mods.txt'
    Assert-True -Condition $safeNestedPath.StartsWith($testRoot + '\', [StringComparison]::OrdinalIgnoreCase) -Message 'A valid nested path escaped the test root.'

    $payload = New-ValidatedPayloadStaging -Root $runtimeRoot
    Assert-Equal -Actual $payload.manifest.cyberfox1337x -Expected 'function(dawnwalker_runtime_payload_manifest)' -Message 'Unexpected payload manifest identity.'
    $preparedBridgePath = Get-SafeChildPath -Root $payload.root -RelativePath 'ue4ss/Mods/DawnwalkerModBridge/Scripts/main.lua'
    $preparedBridgeMetadata = Read-DawnwalkerBridgeSourceMetadata -LiteralPath $preparedBridgePath -AllowLegacyDiscovery
    Assert-Equal -Actual ([string]$payload.manifest.phase) -Expected ([string]$preparedBridgeMetadata.phase) -Message 'Payload phase does not match its compiled bridge.'
    Assert-Equal -Actual ([string]$payload.manifest.bridgeVersion) -Expected ([string]$preparedBridgeMetadata.bridgeVersion) -Message 'Payload bridge version does not match its compiled bridge.'
    Assert-Equal -Actual (@($payload.manifest.gameplayCapabilities) -join ',') -Expected (@($preparedBridgeMetadata.gameplayCapabilities) -join ',') -Message 'Payload capabilities do not match its compiled bridge.'
    Assert-Equal -Actual ([string]$payload.manifest.steamAppId) -Expected ([string]$payload.contract.steam.appId) -Message 'Payload and official-build contracts disagree on Steam App ID.'
    Assert-Equal -Actual ([string]$payload.manifest.steamBuildId) -Expected ([string]$payload.contract.steam.buildId) -Message 'Payload and official-build contracts disagree on Steam build ID.'

    $requiredDependencies = @($payload.manifest.requiredRuntimeDependencies)
    Assert-Equal -Actual $requiredDependencies.Count -Expected 1 -Message 'Payload does not declare exactly one pinned runtime dependency.'
    Assert-Equal -Actual ([string]$requiredDependencies[0].relativePath) -Expected 'ue4ss/Mods/shared/UEHelpers/UEHelpers.lua' -Message 'Payload declares the wrong UEHelpers dependency path.'
    Assert-Equal -Actual ([long]$requiredDependencies[0].bytes) -Expected 10237 -Message 'Payload declares the wrong UEHelpers dependency size.'
    Assert-Equal -Actual ([string]$requiredDependencies[0].sha256) -Expected '7476F02EEF0C87BFEAB169F2FFE2E704363FAEAAE4BF9F1BDA574B1E34F4A0E9' -Message 'Payload declares the wrong UEHelpers dependency hash.'
    $stagedUEHelpersPath = Get-SafeChildPath -Root $payload.root -RelativePath ([string]$requiredDependencies[0].relativePath)
    Assert-Equal -Actual (Get-Sha256 -LiteralPath $stagedUEHelpersPath) -Expected ([string]$requiredDependencies[0].sha256) -Message 'Staged UEHelpers dependency bytes do not match their pin.'

    foreach ($relativePath in @('dwmapi.dll', 'ue4ss/UE4SS.dll')) {
        $entryCount = @($payload.manifest.payloadFiles | Where-Object { ([string]$_.relativePath).Replace('\', '/') -eq $relativePath }).Count
        Assert-Equal -Actual $entryCount -Expected 1 -Message "Payload manifest does not own exactly one $relativePath entry."
        $stagedPath = Get-SafeChildPath -Root $payload.root -RelativePath $relativePath
        Assert-True -Condition (Test-Path -LiteralPath $stagedPath -PathType Leaf) -Message "Staged nested loader file is missing: $relativePath"
    }
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $payload.root 'UE4SS.dll') -PathType Leaf)) -Message 'UE4SS.dll was incorrectly flattened beside the game executable.'

    $tamperedRuntimeRoot = Join-Path $testRoot 'tampered-runtime'
    Copy-Item -LiteralPath $runtimeRoot -Destination $tamperedRuntimeRoot -Recurse
    $tamperedManifest = Get-Content -LiteralPath (Join-Path $tamperedRuntimeRoot 'payload-manifest.json') -Raw | ConvertFrom-Json
    $tamperRelativePath = $null
    if (@($tamperedManifest.overlays).Count -gt 0) {
        $tamperRelativePath = [string]@($tamperedManifest.overlays)[0].packagePath
    }
    else {
        $tamperRelativePath = [string]$tamperedManifest.ue4ssArchive.packagePath
    }
    $tamperPath = Get-SafeChildPath -Root $tamperedRuntimeRoot -RelativePath $tamperRelativePath
    Add-Content -LiteralPath $tamperPath -Value 'dawnwalker-installer-test-tamper' -Encoding ascii
    Assert-Throws -Action { New-ValidatedPayloadStaging -Root $tamperedRuntimeRoot } -Message 'A tampered runtime package was accepted.'

    $tamperedDependencyRoot = Join-Path $testRoot 'tampered-dependency-metadata'
    Copy-Item -LiteralPath $runtimeRoot -Destination $tamperedDependencyRoot -Recurse
    $tamperedDependencyManifestPath = Join-Path $tamperedDependencyRoot 'payload-manifest.json'
    $tamperedDependencyManifest = Get-Content -LiteralPath $tamperedDependencyManifestPath -Raw | ConvertFrom-Json
    $tamperedDependencyManifest.requiredRuntimeDependencies[0].sha256 = ('0' * 64)
    $tamperedDependencyManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tamperedDependencyManifestPath -Encoding utf8
    Assert-Throws -Action { Read-PayloadMetadata -Root $tamperedDependencyRoot } -Message 'Tampered UEHelpers dependency metadata was accepted.'

    $missingDependencyRoot = Join-Path $testRoot 'missing-dependency-metadata'
    Copy-Item -LiteralPath $runtimeRoot -Destination $missingDependencyRoot -Recurse
    $missingDependencyManifestPath = Join-Path $missingDependencyRoot 'payload-manifest.json'
    $missingDependencyManifest = Get-Content -LiteralPath $missingDependencyManifestPath -Raw | ConvertFrom-Json
    $missingDependencyManifest.PSObject.Properties.Remove('requiredRuntimeDependencies')
    $missingDependencyManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $missingDependencyManifestPath -Encoding utf8
    Assert-Throws -Action { Read-PayloadMetadata -Root $missingDependencyRoot } -Message 'Missing UEHelpers dependency metadata was accepted.'

    $productionRuntimeRoot = Join-Path $testRoot 'synthetic-production-runtime'
    Copy-Item -LiteralPath $runtimeRoot -Destination $productionRuntimeRoot -Recurse
    $productionManifestPath = Join-Path $productionRuntimeRoot 'payload-manifest.json'
    $productionManifest = Get-Content -LiteralPath $productionManifestPath -Raw | ConvertFrom-Json
    $productionBridgeOverlay = @($productionManifest.overlays | Where-Object { ([string]$_.targetPath).Replace('\', '/') -eq 'ue4ss/Mods/DawnwalkerModBridge/Scripts/main.lua' })
    Assert-Equal -Actual $productionBridgeOverlay.Count -Expected 1 -Message 'Synthetic production bridge overlay is not unique.'
    $productionBridgePath = Get-SafeChildPath -Root $productionRuntimeRoot -RelativePath ([string]$productionBridgeOverlay[0].packagePath)
    $productionBridgeSource = Get-Content -LiteralPath $productionBridgePath -Raw
    if ($productionBridgeSource -match '(?m)^\s*local\s+BRIDGE_PHASE\s*=') {
        $productionBridgeSource = [regex]::Replace($productionBridgeSource, '(?m)^\s*local\s+BRIDGE_PHASE\s*=\s*"[^"\r\n]*"\s*$', 'local BRIDGE_PHASE = "production"')
    }
    else {
        $versionDeclaration = [regex]::Match($productionBridgeSource, '(?m)^\s*local\s+BRIDGE_VERSION\s*=')
        Assert-True -Condition $versionDeclaration.Success -Message 'Synthetic source has no BRIDGE_VERSION insertion point.'
        $productionBridgeSource = $productionBridgeSource.Insert($versionDeclaration.Index, "local BRIDGE_PHASE = `"production`"`r`n")
    }
    $productionBridgeSource = [regex]::Replace($productionBridgeSource, '(?m)^\s*local\s+BRIDGE_VERSION\s*=\s*"[^"\r\n]*"\s*$', 'local BRIDGE_VERSION = "1.0.0-synthetic-verified"')
    $productionBridgeSource = [regex]::Replace($productionBridgeSource, '(?m)^\s*local\s+CAPABILITIES\s*=\s*"[^"\r\n]*"\s*$', 'local CAPABILITIES = "player:infinite-health,player:unlimited-stamina"')
    Set-Content -LiteralPath $productionBridgePath -Value $productionBridgeSource -NoNewline -Encoding utf8

    $productionModsOverlay = @($productionManifest.overlays | Where-Object { ([string]$_.targetPath).Replace('\', '/') -eq 'ue4ss/Mods/mods.txt' })
    Assert-Equal -Actual $productionModsOverlay.Count -Expected 1 -Message 'Synthetic production mods overlay is not unique.'
    $productionModsPath = Get-SafeChildPath -Root $productionRuntimeRoot -RelativePath ([string]$productionModsOverlay[0].packagePath)
    $productionModsSource = Get-Content -LiteralPath $productionModsPath -Raw
    $productionModsSource = [regex]::Replace($productionModsSource, '(?m)^\s*DawnwalkerModBridge\s*:\s*[01]\s*$', 'DawnwalkerModBridge : 1')
    Set-Content -LiteralPath $productionModsPath -Value $productionModsSource -NoNewline -Encoding utf8

    $productionManifest.phase = 'production'
    $productionManifest.bridgeVersion = '1.0.0-synthetic-verified'
    $productionManifest.gameplayCapabilities = @('player:infinite-health', 'player:unlimited-stamina')
    $productionHookSetting = @($productionManifest.requiredSettings | Where-Object { [string]$_.section -ieq 'Hooks' -and [string]$_.key -ieq 'HookEngineTick' })
    Assert-Equal -Actual $productionHookSetting.Count -Expected 1 -Message 'Synthetic production HookEngineTick setting is not unique.'
    $productionHookSetting[0].value = '1'
    $productionSettingsOverlay = @($productionManifest.overlays | Where-Object { ([string]$_.targetPath).Replace('\', '/') -eq 'ue4ss/UE4SS-settings.ini' })
    Assert-Equal -Actual $productionSettingsOverlay.Count -Expected 1 -Message 'Synthetic production settings overlay is not unique.'
    $productionSettingsPath = Get-SafeChildPath -Root $productionRuntimeRoot -RelativePath ([string]$productionSettingsOverlay[0].packagePath)
    $productionSettingsSource = Get-Content -LiteralPath $productionSettingsPath -Raw
    $productionSettingsSource = [regex]::Replace($productionSettingsSource, '(?m)^\s*HookEngineTick\s*=\s*[01]\s*$', 'HookEngineTick = 1')
    Set-Content -LiteralPath $productionSettingsPath -Value $productionSettingsSource -NoNewline -Encoding utf8
    $productionBridgeMod = @($productionManifest.requiredModRegistry | Where-Object { [string]$_.name -ieq 'DawnwalkerModBridge' })
    Assert-Equal -Actual $productionBridgeMod.Count -Expected 1 -Message 'Synthetic production required bridge entry is not unique.'
    $productionBridgeMod[0].value = '1'
    Update-TestOverlayMetadata -Manifest $productionManifest -RuntimeRoot $productionRuntimeRoot -TargetPath 'ue4ss/Mods/DawnwalkerModBridge/Scripts/main.lua'
    Update-TestOverlayMetadata -Manifest $productionManifest -RuntimeRoot $productionRuntimeRoot -TargetPath 'ue4ss/Mods/mods.txt'
    Update-TestOverlayMetadata -Manifest $productionManifest -RuntimeRoot $productionRuntimeRoot -TargetPath 'ue4ss/UE4SS-settings.ini'
    $productionManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $productionManifestPath -Encoding utf8

    $productionPayload = New-ValidatedPayloadStaging -Root $productionRuntimeRoot
    Assert-Equal -Actual ([string]$productionPayload.manifest.phase) -Expected 'production' -Message 'A consistent synthetic production payload was not accepted.'
    Assert-Equal -Actual @($productionPayload.manifest.gameplayCapabilities).Count -Expected 2 -Message 'Synthetic production capabilities were not preserved.'
    Remove-ValidatedPayloadStaging -Payload $productionPayload
    $productionPayload = $null

    $metadataMismatchRoot = Join-Path $testRoot 'production-metadata-mismatch'
    Copy-Item -LiteralPath $productionRuntimeRoot -Destination $metadataMismatchRoot -Recurse
    $metadataMismatchManifestPath = Join-Path $metadataMismatchRoot 'payload-manifest.json'
    $metadataMismatchManifest = Get-Content -LiteralPath $metadataMismatchManifestPath -Raw | ConvertFrom-Json
    $metadataMismatchManifest.gameplayCapabilities = @('player:infinite-health', 'world:weather')
    $metadataMismatchManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $metadataMismatchManifestPath -Encoding utf8
    Assert-Throws -Action { Read-PayloadMetadata -Root $metadataMismatchRoot } -Message 'Production manifest/bridge capability mismatch was accepted.'

    $unapprovedModRoot = Join-Path $testRoot 'production-unapproved-mod'
    Copy-Item -LiteralPath $productionRuntimeRoot -Destination $unapprovedModRoot -Recurse
    $unapprovedModManifestPath = Join-Path $unapprovedModRoot 'payload-manifest.json'
    $unapprovedModManifest = Get-Content -LiteralPath $unapprovedModManifestPath -Raw | ConvertFrom-Json
    $unapprovedKeybind = @($unapprovedModManifest.requiredModRegistry | Where-Object { [string]$_.name -ieq 'Keybinds' })
    Assert-Equal -Actual $unapprovedKeybind.Count -Expected 1 -Message 'Synthetic Keybinds registry entry is not unique.'
    $unapprovedKeybind[0].value = '1'
    $unapprovedModManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $unapprovedModManifestPath -Encoding utf8
    Assert-Throws -Action { Read-PayloadMetadata -Root $unapprovedModRoot } -Message 'A production payload enabling an unapproved second UE4SS mod was accepted.'

    $disabledExecutorRoot = Join-Path $testRoot 'production-disabled-executor'
    Copy-Item -LiteralPath $productionRuntimeRoot -Destination $disabledExecutorRoot -Recurse
    $disabledExecutorManifestPath = Join-Path $disabledExecutorRoot 'payload-manifest.json'
    $disabledExecutorManifest = Get-Content -LiteralPath $disabledExecutorManifestPath -Raw | ConvertFrom-Json
    $disabledExecutorSetting = @($disabledExecutorManifest.requiredSettings | Where-Object { [string]$_.section -ieq 'Hooks' -and [string]$_.key -ieq 'HookEngineTick' })
    Assert-Equal -Actual $disabledExecutorSetting.Count -Expected 1 -Message 'Synthetic disabled-executor setting is not unique.'
    $disabledExecutorSetting[0].value = '0'
    $disabledExecutorManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $disabledExecutorManifestPath -Encoding utf8
    Assert-Throws -Action { Read-PayloadMetadata -Root $disabledExecutorRoot } -Message 'A production payload without the approved game-thread executor was accepted.'

    $freshWin64 = Join-Path $testRoot 'loader-mode-fresh'
    New-Item -ItemType Directory -Path $freshWin64 -Force | Out-Null
    Assert-Equal -Actual (Get-LoaderMode -Win64Path $freshWin64 -Manifest $payload.manifest) -Expected 'Fresh' -Message 'An empty Win64 folder was not detected as a fresh install.'

    $partialWin64 = Join-Path $testRoot 'loader-mode-partial'
    New-Item -ItemType Directory -Path $partialWin64 -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $payload.root 'dwmapi.dll') -Destination (Join-Path $partialWin64 'dwmapi.dll')
    Assert-Throws -Action { Get-LoaderMode -Win64Path $partialWin64 -Manifest $payload.manifest } -Message 'A partial nested loader installation was accepted.'

    $exactWin64 = Join-Path $testRoot 'loader-mode-exact'
    New-Item -ItemType Directory -Path (Join-Path $exactWin64 'ue4ss') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $payload.root 'dwmapi.dll') -Destination (Join-Path $exactWin64 'dwmapi.dll')
    Copy-Item -LiteralPath (Join-Path $payload.root 'ue4ss\UE4SS.dll') -Destination (Join-Path $exactWin64 'ue4ss\UE4SS.dll')
    Assert-Equal -Actual (Get-LoaderMode -Win64Path $exactWin64 -Manifest $payload.manifest) -Expected 'ExistingExact' -Message 'The exact nested loader layout was not recognized.'
    Set-Content -LiteralPath (Join-Path $exactWin64 'ue4ss\UE4SS.dll') -Value 'tampered-loader' -NoNewline -Encoding ascii
    Assert-Throws -Action { Get-LoaderMode -Win64Path $exactWin64 -Manifest $payload.manifest } -Message 'A modified nested UE4SS.dll was accepted.'

    $conflictWin64 = Join-Path $testRoot 'loader-mode-conflict'
    New-Item -ItemType Directory -Path $conflictWin64 -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $conflictWin64 'xinput1_3.dll') -Value 'conflict' -NoNewline -Encoding ascii
    Assert-Throws -Action { Get-LoaderMode -Win64Path $conflictWin64 -Manifest $payload.manifest } -Message 'A conflicting proxy loader was accepted.'

    $requiredSettings = @($payload.manifest.requiredSettings)
    Assert-True -Condition ($requiredSettings.Count -ge 2) -Message 'The payload needs at least two required settings for semantic merge/rollback coverage.'
    $originalSettingValue = if ([string]$requiredSettings[0].value -eq '1') { '0' } else { '1' }
    $settingsExisting = Join-Path $testRoot 'existing-settings.ini'
    $settingsMerged = Join-Path $testRoot 'merged-settings.ini'
    $settingsLines = [Collections.Generic.List[string]]::new()
    $settingsLines.Add('; preserve this comment')
    Add-IniEntry -Lines $settingsLines -Section ([string]$requiredSettings[0].section) -Key ([string]$requiredSettings[0].key) -Value $originalSettingValue
    Add-IniEntry -Lines $settingsLines -Section 'ThirdPartyTest' -Key 'CustomSetting' -Value 'keep-me'
    Set-Content -LiteralPath $settingsExisting -Value $settingsLines -Encoding utf8
    New-MergedSettingsFile -ExistingPath $settingsExisting -Manifest $payload.manifest -OutputPath $settingsMerged
    foreach ($setting in $requiredSettings) {
        $settingState = Get-IniValueState -LiteralPath $settingsMerged -Section ([string]$setting.section) -Key ([string]$setting.key)
        Assert-True -Condition ([bool]$settingState.present) -Message "Required setting was not added: [$($setting.section)] $($setting.key)"
        Assert-Equal -Actual ([string]$settingState.value) -Expected ([string]$setting.value) -Message "Required setting has the wrong value: [$($setting.section)] $($setting.key)"
    }
    Assert-Equal -Actual (Get-IniValueState -LiteralPath $settingsMerged -Section 'ThirdPartyTest' -Key 'CustomSetting').value -Expected 'keep-me' -Message 'The semantic INI merge removed an unrelated setting.'

    $requiredMods = @($payload.manifest.requiredModRegistry)
    Assert-True -Condition ($requiredMods.Count -ge 2) -Message 'The payload needs at least two required mod entries for semantic merge/rollback coverage.'
    $originalModValue = if ([string]$requiredMods[0].value -eq '1') { '0' } else { '1' }
    $modsExisting = Join-Path $testRoot 'existing-mods.txt'
    $modsMerged = Join-Path $testRoot 'merged-mods.txt'
    @(
        '; preserve this registry comment',
        'UnrelatedTestMod : 1',
        "$($requiredMods[0].name) : $originalModValue"
    ) | Set-Content -LiteralPath $modsExisting -Encoding utf8
    New-MergedModRegistryFile -ExistingPath $modsExisting -Manifest $payload.manifest -OutputPath $modsMerged
    foreach ($requiredMod in $requiredMods) {
        $modState = Get-ModRegistryValueState -LiteralPath $modsMerged -Name ([string]$requiredMod.name)
        Assert-True -Condition ([bool]$modState.present) -Message "Required mod entry was not added: $($requiredMod.name)"
        Assert-Equal -Actual ([string]$modState.value) -Expected ([string]$requiredMod.value) -Message "Required mod entry has the wrong value: $($requiredMod.name)"
    }
    Assert-Equal -Actual (Get-ModRegistryValueState -LiteralPath $modsMerged -Name 'UnrelatedTestMod').value -Expected '1' -Message 'The semantic mod-registry merge removed an unrelated entry.'

    $originalProgramDataPath = [IO.Path]::GetFullPath($originalProgramData).TrimEnd('\')
    $originalStateRootPath = [IO.Path]::GetFullPath($originalStateRoot)
    Assert-True -Condition $originalStateRootPath.StartsWith($originalProgramDataPath + '\', [StringComparison]::OrdinalIgnoreCase) -Message 'The helper state root is not anchored below ProgramData.'
    $stateRelativePath = $originalStateRootPath.Substring($originalProgramDataPath.Length).TrimStart('\')
    $sandboxProgramData = Join-Path $testRoot 'ProgramData'
    $env:ProgramData = $sandboxProgramData
    $script:StateRoot = [IO.Path]::GetFullPath((Join-Path $sandboxProgramData $stateRelativePath))
    $script:StatePath = Join-Path $script:StateRoot 'install-state.json'
    $script:BaselineRoot = Join-Path $script:StateRoot 'baseline'
    New-Item -ItemType Directory -Path $script:StateRoot -Force | Out-Null

    $baselineWin64 = Join-Path $testRoot 'baseline-game\Dawnwalker\Binaries\Win64'
    $baselineSettingsPath = Join-Path $baselineWin64 'ue4ss\UE4SS-settings.ini'
    New-Item -ItemType Directory -Path (Split-Path -Parent $baselineSettingsPath) -Force | Out-Null
    $baselineSettingsLines = [Collections.Generic.List[string]]::new()
    Add-IniEntry -Lines $baselineSettingsLines -Section ([string]$requiredSettings[0].section) -Key ([string]$requiredSettings[0].key) -Value ([string]$requiredSettings[0].value)
    Add-IniEntry -Lines $baselineSettingsLines -Section ([string]$requiredSettings[1].section) -Key ([string]$requiredSettings[1].key) -Value ([string]$requiredSettings[1].value)
    Add-IniEntry -Lines $baselineSettingsLines -Section 'ThirdPartyAfterInstall' -Key 'Keep' -Value 'yes'
    Set-Content -LiteralPath $baselineSettingsPath -Value $baselineSettingsLines -Encoding utf8
    $settingsRecord = [pscustomobject]@{
        relativePath = 'ue4ss/UE4SS-settings.ini'
        installedSha256 = 'SEMANTIC-NOT-A-WHOLE-FILE-HASH'
        originalKind = 'file'
        originalSha256 = $null
        backupRelativePath = $null
        ownership = 'semantic-ini'
        semanticEntries = @(
            [pscustomobject]@{
                section = [string]$requiredSettings[0].section
                key = [string]$requiredSettings[0].key
                originalPresent = $true
                originalValue = $originalSettingValue
                installedValue = [string]$requiredSettings[0].value
            },
            [pscustomobject]@{
                section = [string]$requiredSettings[1].section
                key = [string]$requiredSettings[1].key
                originalPresent = $false
                originalValue = $null
                installedValue = [string]$requiredSettings[1].value
            }
        )
    }
    Restore-BaselineRecord -Record $settingsRecord -Win64Path $baselineWin64
    Assert-Equal -Actual (Get-IniValueState -LiteralPath $baselineSettingsPath -Section ([string]$requiredSettings[0].section) -Key ([string]$requiredSettings[0].key)).value -Expected $originalSettingValue -Message 'Semantic rollback did not restore the original owned setting.'
    Assert-True -Condition (-not (Get-IniValueState -LiteralPath $baselineSettingsPath -Section ([string]$requiredSettings[1].section) -Key ([string]$requiredSettings[1].key)).present) -Message 'Semantic rollback did not remove a newly owned setting.'
    Assert-Equal -Actual (Get-IniValueState -LiteralPath $baselineSettingsPath -Section 'ThirdPartyAfterInstall' -Key 'Keep').value -Expected 'yes' -Message 'Semantic rollback removed a later unrelated INI edit.'

    $baselineModsPath = Join-Path $baselineWin64 'ue4ss\Mods\mods.txt'
    New-Item -ItemType Directory -Path (Split-Path -Parent $baselineModsPath) -Force | Out-Null
    @(
        'UnrelatedLaterMod : 1',
        "$($requiredMods[0].name) : $($requiredMods[0].value)",
        "$($requiredMods[1].name) : $($requiredMods[1].value)"
    ) | Set-Content -LiteralPath $baselineModsPath -Encoding utf8
    $modsRecord = [pscustomobject]@{
        relativePath = 'ue4ss/Mods/mods.txt'
        installedSha256 = 'SEMANTIC-NOT-A-WHOLE-FILE-HASH'
        originalKind = 'file'
        originalSha256 = $null
        backupRelativePath = $null
        ownership = 'semantic-mod-registry'
        semanticEntries = @(
            [pscustomobject]@{
                name = [string]$requiredMods[0].name
                originalPresent = $true
                originalValue = $originalModValue
                installedValue = [string]$requiredMods[0].value
            },
            [pscustomobject]@{
                name = [string]$requiredMods[1].name
                originalPresent = $false
                originalValue = $null
                installedValue = [string]$requiredMods[1].value
            }
        )
    }
    Restore-BaselineRecord -Record $modsRecord -Win64Path $baselineWin64
    Assert-Equal -Actual (Get-ModRegistryValueState -LiteralPath $baselineModsPath -Name ([string]$requiredMods[0].name)).value -Expected $originalModValue -Message 'Semantic rollback did not restore the original mod entry.'
    Assert-True -Condition (-not (Get-ModRegistryValueState -LiteralPath $baselineModsPath -Name ([string]$requiredMods[1].name)).present) -Message 'Semantic rollback did not remove a newly owned mod entry.'
    Assert-Equal -Actual (Get-ModRegistryValueState -LiteralPath $baselineModsPath -Name 'UnrelatedLaterMod').value -Expected '1' -Message 'Semantic rollback removed a later unrelated mod entry.'

    # Unchanged semantic files must recover their original encoding and line endings.
    foreach ($fixture in @(
        @{ path = 'ue4ss/UE4SS-settings.ini'; ownership = 'semantic-ini'; text = "[Original]`nEnabled = 0" },
        @{ path = 'ue4ss/Mods/mods.txt'; ownership = 'semantic-mod-registry'; text = "OriginalMod : 0`n" }
    )) {
        $destination = Get-SafeChildPath -Root $baselineWin64 -RelativePath $fixture.path
        $backupRelative = 'exact-baseline/' + $fixture.path
        $backup = Get-SafeChildPath -Root $script:StateRoot -RelativePath $backupRelative
        New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
        [IO.File]::WriteAllText($backup, $fixture.text, [Text.UTF8Encoding]::new($false))
        Set-Content -LiteralPath $destination -Value ($fixture.text + "`n; installed") -Encoding utf8
        $exactRecord = [pscustomobject]@{
            relativePath = $fixture.path
            ownership = $fixture.ownership
            originalKind = 'file'
            originalSha256 = Get-Sha256 -LiteralPath $backup
            backupRelativePath = $backupRelative
            installedSha256 = Get-Sha256 -LiteralPath $destination
            exactRestoreAllowed = $true
            semanticEntries = @()
        }
        Restore-BaselineRecord -Record $exactRecord -Win64Path $baselineWin64
        Assert-Equal -Actual (Get-Sha256 -LiteralPath $destination) -Expected $exactRecord.originalSha256 -Message 'Unchanged semantic file did not restore exact original bytes.'

        Set-Content -LiteralPath $destination -Value '; installed again' -Encoding utf8
        $exactRecord.installedSha256 = Get-Sha256 -LiteralPath $destination
        Set-Content -LiteralPath $backup -Value '; corrupt backup' -Encoding utf8
        Assert-Throws -Action { Restore-BaselineRecord -Record $exactRecord -Win64Path $baselineWin64 } -Message 'Corrupt exact semantic backup was accepted.'
        Assert-Equal -Actual (Get-Sha256 -LiteralPath $destination) -Expected $exactRecord.installedSha256 -Message 'Corrupt backup changed the destination.'
        Remove-Item -LiteralPath $backup -Force
        Assert-Throws -Action { Restore-BaselineRecord -Record $exactRecord -Win64Path $baselineWin64 } -Message 'Missing exact semantic backup was accepted.'
        Assert-Equal -Actual (Get-Sha256 -LiteralPath $destination) -Expected $exactRecord.installedSha256 -Message 'Missing backup changed the destination.'
    }

    $exactBaselineRoot = Join-Path $script:StateRoot 'exact-baseline'
    Assert-SafeTemporaryPath -LiteralPath $exactBaselineRoot
    Remove-Item -LiteralPath $exactBaselineRoot -Recurse -Force

    $integrationSteamAppsRoot = Join-Path $testRoot 'integration-library\steamapps'
    $integrationGameRoot = Join-Path $integrationSteamAppsRoot 'common\The Blood of Dawnwalker'
    $integrationWin64 = Join-Path $integrationGameRoot 'Dawnwalker\Binaries\Win64'
    $integrationSettingsPath = Join-Path $integrationWin64 'ue4ss\UE4SS-settings.ini'
    $integrationModsPath = Join-Path $integrationWin64 'ue4ss\Mods\mods.txt'
    $integrationUEHelpersPath = Join-Path $integrationWin64 'ue4ss\Mods\shared\UEHelpers\UEHelpers.lua'
    New-Item -ItemType Directory -Path (Split-Path -Parent $integrationModsPath) -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path -Parent $integrationUEHelpersPath) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $payload.root 'dwmapi.dll') -Destination (Join-Path $integrationWin64 'dwmapi.dll')
    Copy-Item -LiteralPath (Join-Path $payload.root 'ue4ss\UE4SS.dll') -Destination (Join-Path $integrationWin64 'ue4ss\UE4SS.dll')
    $originalUEHelpersText = 'pre-existing third-party helper baseline'
    Set-Content -LiteralPath $integrationUEHelpersPath -Value $originalUEHelpersText -NoNewline -Encoding utf8
    $originalUEHelpersSha256 = Get-Sha256 -LiteralPath $integrationUEHelpersPath
    $integrationSettingsLines = [Collections.Generic.List[string]]::new()
    $integrationSettingsLines.Add('; exact pre-install test baseline')
    Add-IniEntry -Lines $integrationSettingsLines -Section ([string]$requiredSettings[0].section) -Key ([string]$requiredSettings[0].key) -Value $originalSettingValue
    Add-IniEntry -Lines $integrationSettingsLines -Section 'ExistingThirdParty' -Key 'Keep' -Value 'before-install'
    Set-Content -LiteralPath $integrationSettingsPath -Value $integrationSettingsLines -Encoding utf8
    @(
        'UnrelatedTestMod : 1',
        "$($requiredMods[0].name) : $originalModValue"
    ) | Set-Content -LiteralPath $integrationModsPath -Encoding utf8

    $fakeManifestPath = Join-Path $integrationSteamAppsRoot 'appmanifest_3751260.acf'
    New-Item -ItemType Directory -Path $integrationSteamAppsRoot -Force | Out-Null
    @(
        '"AppState"',
        '{',
        '  "appid" "3751260"',
        '  "buildid" "25107392"',
        '  "StateFlags" "4"',
        '  "installdir" "The Blood of Dawnwalker"',
        '}'
    ) | Set-Content -LiteralPath $fakeManifestPath -Encoding utf8
    $fakeExecutablePath = Join-Path $integrationWin64 'Dawnwalker.exe'
    Set-Content -LiteralPath $fakeExecutablePath -Value 'isolated-test-executable' -NoNewline -Encoding ascii
    $fakeGameInstall = [pscustomobject]@{
        manifestPath = $fakeManifestPath
        buildId = [string]$payload.contract.steam.buildId
        installPath = $integrationGameRoot
        executablePath = $fakeExecutablePath
        executableSha256 = [string]$payload.contract.executable.sha256
        win64Path = $integrationWin64
    }

    Install-Runtime -GameInstall $fakeGameInstall -Payload $payload -ApplicationVersion '0.1.0' | Out-Null
    $installedState = Read-InstallState
    Assert-True -Condition ($null -ne $installedState) -Message 'Install-Runtime did not write an install state.'
    Assert-Equal -Actual ([string]$installedState.win64Path) -Expected ([IO.Path]::GetFullPath($integrationWin64)) -Message 'Install state targets the wrong fake Win64 folder.'
    Assert-Equal -Actual ([string]$installedState.phase) -Expected ([string]$payload.manifest.phase) -Message 'Install state did not preserve the payload phase.'
    Assert-Equal -Actual (@($installedState.gameplayCapabilities) -join ',') -Expected (@($payload.manifest.gameplayCapabilities) -join ',') -Message 'Install state did not preserve compiled payload capabilities.'
    $managedGameInstall = Get-ManagedGameInstallFromState -State $installedState -Contract $payload.contract
    Assert-Equal -Actual ([string]$managedGameInstall.win64Path) -Expected ([IO.Path]::GetFullPath($integrationWin64)) -Message 'Managed-state uninstall resolution changed the recorded Win64 target.'
    $invalidTargetState = $installedState | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $invalidTargetState.win64Path = Join-Path $testRoot 'unsafe-target'
    Assert-Throws -Action { Get-ManagedGameInstallFromState -State $invalidTargetState -Contract $payload.contract } -Message 'A managed uninstall state with the wrong Win64 suffix was accepted.'
    $runtimeStatus = Get-RuntimeStatus -GameInstall $fakeGameInstall -Manifest $payload.manifest -Contract $payload.contract
    Assert-Equal -Actual ([string]$runtimeStatus.phase) -Expected ([string]$payload.manifest.phase) -Message 'Runtime status did not carry the payload phase.'
    Assert-Equal -Actual (@($runtimeStatus.gameplayCapabilities) -join ',') -Expected (@($payload.manifest.gameplayCapabilities) -join ',') -Message 'Runtime status did not carry compiled payload capabilities.'
    Assert-Equal -Actual ([string]$runtimeStatus.installedPhase) -Expected ([string]$payload.manifest.phase) -Message 'Runtime status did not carry the installed phase.'
    foreach ($relativePath in @('dwmapi.dll', 'ue4ss/UE4SS.dll')) {
        $installedPath = Get-SafeChildPath -Root $integrationWin64 -RelativePath $relativePath
        $payloadPath = Get-SafeChildPath -Root $payload.root -RelativePath $relativePath
        Assert-True -Condition (Test-Path -LiteralPath $installedPath -PathType Leaf) -Message "Install-Runtime omitted $relativePath."
        Assert-Equal -Actual (Get-Sha256 -LiteralPath $installedPath) -Expected (Get-Sha256 -LiteralPath $payloadPath) -Message "Install-Runtime wrote the wrong $relativePath bytes."
    }
    Assert-Equal -Actual (Get-Sha256 -LiteralPath $integrationUEHelpersPath) -Expected '7476F02EEF0C87BFEAB169F2FFE2E704363FAEAAE4BF9F1BDA574B1E34F4A0E9' -Message 'ExistingExact installation did not deploy the exact pinned UEHelpers dependency.'
    $ueHelpersStateRecord = @($installedState.files | Where-Object { ([string]$_.relativePath).Replace('\', '/') -eq 'ue4ss/Mods/shared/UEHelpers/UEHelpers.lua' })
    Assert-Equal -Actual $ueHelpersStateRecord.Count -Expected 1 -Message 'ExistingExact installation did not record UEHelpers rollback ownership.'
    Assert-Equal -Actual ([string]$ueHelpersStateRecord[0].ownership) -Expected 'whole-file' -Message 'UEHelpers dependency is not whole-file rollback owned.'
    $settingsStateRecord = @($installedState.files | Where-Object { ([string]$_.relativePath).Replace('\', '/') -eq 'ue4ss/UE4SS-settings.ini' })
    $modsStateRecord = @($installedState.files | Where-Object { ([string]$_.relativePath).Replace('\', '/') -eq 'ue4ss/Mods/mods.txt' })
    Assert-Equal -Actual $settingsStateRecord.Count -Expected 1 -Message 'Nested settings state record is missing.'
    Assert-Equal -Actual ([string]$settingsStateRecord[0].ownership) -Expected 'semantic-ini' -Message 'Nested settings were not semantically owned.'
    Assert-Equal -Actual $modsStateRecord.Count -Expected 1 -Message 'Nested mod registry state record is missing.'
    Assert-Equal -Actual ([string]$modsStateRecord[0].ownership) -Expected 'semantic-mod-registry' -Message 'Nested mod registry was not semantically owned.'

    Add-Content -LiteralPath $integrationSettingsPath -Value "`n[LaterThirdParty]`nKeep = yes" -Encoding utf8
    Add-Content -LiteralPath $integrationModsPath -Value 'LaterUnrelatedMod : 1' -Encoding utf8
    $bridgeRelativePath = 'ue4ss/Mods/DawnwalkerModBridge/Scripts/main.lua'
    $bridgePath = Get-SafeChildPath -Root $integrationWin64 -RelativePath $bridgeRelativePath
    $stagedBridgePath = Get-SafeChildPath -Root $payload.root -RelativePath $bridgeRelativePath
    Set-Content -LiteralPath $bridgePath -Value 'repair-me' -NoNewline -Encoding ascii
    Set-Content -LiteralPath $integrationUEHelpersPath -Value 'repair-helper' -NoNewline -Encoding ascii
    Repair-Runtime -GameInstall $fakeGameInstall -Payload $payload -ApplicationVersion '0.1.0' | Out-Null
    Assert-Equal -Actual (Get-Sha256 -LiteralPath $bridgePath) -Expected (Get-Sha256 -LiteralPath $stagedBridgePath) -Message 'Repair-Runtime did not restore the managed bridge file.'
    Assert-Equal -Actual (Get-Sha256 -LiteralPath $integrationUEHelpersPath) -Expected '7476F02EEF0C87BFEAB169F2FFE2E704363FAEAAE4BF9F1BDA574B1E34F4A0E9' -Message 'Repair-Runtime did not restore the pinned UEHelpers dependency.'
    Assert-Equal -Actual (Get-IniValueState -LiteralPath $integrationSettingsPath -Section 'LaterThirdParty' -Key 'Keep').value -Expected 'yes' -Message 'Repair-Runtime removed a later unrelated INI edit.'
    Assert-Equal -Actual (Get-ModRegistryValueState -LiteralPath $integrationModsPath -Name 'LaterUnrelatedMod').value -Expected '1' -Message 'Repair-Runtime removed a later unrelated mod entry.'

    Uninstall-Runtime -GameInstall $fakeGameInstall | Out-Null
    Assert-True -Condition ($null -eq (Read-InstallState)) -Message 'Uninstall-Runtime left install state behind.'
    Assert-Equal -Actual (Get-Sha256 -LiteralPath (Join-Path $integrationWin64 'dwmapi.dll')) -Expected (Get-Sha256 -LiteralPath (Join-Path $payload.root 'dwmapi.dll')) -Message 'Uninstall-Runtime altered the pre-existing exact proxy loader.'
    Assert-Equal -Actual (Get-Sha256 -LiteralPath (Join-Path $integrationWin64 'ue4ss\UE4SS.dll')) -Expected (Get-Sha256 -LiteralPath (Join-Path $payload.root 'ue4ss\UE4SS.dll')) -Message 'Uninstall-Runtime altered the pre-existing exact nested UE4SS.dll.'
    Assert-True -Condition (-not (Test-Path -LiteralPath $bridgePath -PathType Leaf)) -Message 'Uninstall-Runtime left the originally absent managed bridge behind.'
    Assert-Equal -Actual (Get-Sha256 -LiteralPath $integrationUEHelpersPath) -Expected $originalUEHelpersSha256 -Message 'Uninstall-Runtime did not restore the pre-existing UEHelpers baseline.'
    Assert-Equal -Actual (Get-Content -LiteralPath $integrationUEHelpersPath -Raw) -Expected $originalUEHelpersText -Message 'Uninstall-Runtime restored the wrong UEHelpers baseline bytes.'
    Assert-Equal -Actual (Get-IniValueState -LiteralPath $integrationSettingsPath -Section ([string]$requiredSettings[0].section) -Key ([string]$requiredSettings[0].key)).value -Expected $originalSettingValue -Message 'Uninstall-Runtime did not restore the original INI value.'
    Assert-Equal -Actual (Get-IniValueState -LiteralPath $integrationSettingsPath -Section 'LaterThirdParty' -Key 'Keep').value -Expected 'yes' -Message 'Uninstall-Runtime removed a later unrelated INI edit.'
    Assert-Equal -Actual (Get-ModRegistryValueState -LiteralPath $integrationModsPath -Name ([string]$requiredMods[0].name)).value -Expected $originalModValue -Message 'Uninstall-Runtime did not restore the original mod-registry value.'
    Assert-Equal -Actual (Get-ModRegistryValueState -LiteralPath $integrationModsPath -Name 'LaterUnrelatedMod').value -Expected '1' -Message 'Uninstall-Runtime removed a later unrelated mod-registry edit.'

    $removedSteamAppsRoot = Join-Path $testRoot 'removed-library\steamapps'
    $removedInstallPath = Join-Path $removedSteamAppsRoot 'common\The Blood of Dawnwalker'
    $removedWin64Path = Join-Path $removedInstallPath 'Dawnwalker\Binaries\Win64'
    $removedState = [ordered]@{
        cyberfox1337x = 'function(dawnwalker_runtime_install_state)'
        schemaVersion = 1
        applicationVersion = '0.1.0'
        phase = $payload.manifest.phase
        bridgeVersion = $payload.manifest.bridgeVersion
        gameplayCapabilities = @($payload.manifest.gameplayCapabilities)
        installedAtUtc = [DateTime]::UtcNow.ToString('o')
        steamAppId = [string]$payload.contract.steam.appId
        steamBuildId = [string]$payload.contract.steam.buildId
        manifestPath = Join-Path $removedSteamAppsRoot 'appmanifest_3751260.acf'
        installPath = $removedInstallPath
        win64Path = $removedWin64Path
        loaderMode = 'Fresh'
        payloadManifestSha256 = Get-Sha256 -LiteralPath (Join-Path $runtimeRoot 'payload-manifest.json')
        files = @(
            [ordered]@{
                relativePath = 'ue4ss/Mods/DawnwalkerModBridge/Scripts/main.lua'
                installedSha256 = ('0' * 64)
                originalKind = 'absent'
                originalSha256 = $null
                backupRelativePath = $null
                ownership = 'whole-file'
                semanticEntries = @()
            }
        )
    }
    Write-InstallState -State $removedState
    $removedManagedInstall = Get-ManagedGameInstallFromState -State (Read-InstallState) -Contract $payload.contract
    Uninstall-Runtime -GameInstall $removedManagedInstall | Out-Null
    Assert-True -Condition ($null -eq (Read-InstallState)) -Message 'Removed-game uninstall left orphaned install state behind.'
    Assert-True -Condition (-not (Test-Path -LiteralPath $removedInstallPath)) -Message 'Removed-game uninstall recreated the absent game directory.'

    Write-Output 'Dawnwalker runtime installer tests passed.'
}
finally {
    if ($productionPayload -and $productionPayload.root -and (Test-Path -LiteralPath $productionPayload.root)) {
        Remove-SafeTestTree -LiteralPath ([string]$productionPayload.root)
    }
    if ($payload -and $payload.root -and (Test-Path -LiteralPath $payload.root)) {
        Remove-SafeTestTree -LiteralPath ([string]$payload.root)
    }
    $env:ProgramData = $originalProgramData
    $script:StateRoot = $originalStateRoot
    $script:StatePath = $originalStatePath
    $script:BaselineRoot = $originalBaselineRoot
    if (Test-Path -LiteralPath $testRoot) {
        Remove-SafeTestTree -LiteralPath $testRoot
    }
}
