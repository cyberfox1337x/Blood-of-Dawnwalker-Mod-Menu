[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory = $true)][string]$ModuleName)
    return $ModuleName
}

$null = cyberfox1337x -ModuleName 'dawnwalker_bridge_pilot_promotion_tests'

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Rejected {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Operation,
        [Parameter(Mandatory = $true)][string]$ExpectedMessage,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $caught = $null
    try { & $Operation } catch { $caught = $_ }
    Assert-True ($null -ne $caught) "$Label is rejected"
    Assert-True ($caught.Exception.Message -match $ExpectedMessage) "$Label explains the failed invariant"
}

$kitRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = Split-Path -Parent (Split-Path -Parent $kitRoot)
$contractPath = Join-Path $kitRoot 'official-build.json'
$modulePath = Join-Path $kitRoot 'DawnwalkerReflectionTools.psm1'
$wrapperPath = Join-Path $kitRoot 'Install-DawnwalkerReflectionTools.ps1'
$pilotTemplates = Join-Path $kitRoot 'templates\bridge-pilot'
$bridgeSource = Join-Path $projectRoot 'integration\uue4ss\Mods\DawnwalkerModBridge\Scripts\main.lua'

Import-Module $modulePath -Force
$payload = Test-DawnwalkerBridgePilotPayload -ContractPath $contractPath
$approvedCapabilities = @(
    'player:infinite-health',
    'player:unlimited-stamina',
    'player:blood-energy',
    'player:god-mode',
    'player:player-info',
    'player:trait-points',
    'player:add-gold',
    'inventory:add-item',
    'player:add-level',
    'player:unblock-trait',
    'combat:infinite-blood-energy',
    'combat:rpg-difficulty',
    'combat:action-difficulty',
    'quests:journal-readback',
    'teleport:save-location',
    'teleport:teleport-saved-location',
    'visuals:hud-visible',
    'world:game-speed',
    'world:location-readback'
)
Assert-True $payload.valid 'the checked-in pilot payload passes all invariants'
Assert-True (($payload.enabledHooks -join ',') -ceq 'HookEngineTick') 'only HookEngineTick is enabled'
Assert-True (($payload.enabledMods -join ',') -ceq 'DawnwalkerModBridge') 'only DawnwalkerModBridge is enabled'
Assert-True ((@($payload.capabilities) -join ',') -ceq ($approvedCapabilities -join ',')) 'only the nineteen audited capabilities are present'
Assert-True ($payload.bridgeVersion -ceq '0.3.21-pilot') 'the payload pins the nil-return TMap-compatible two-axis difficulty, F9-enabled, teardown-safe, deferred-unblock-verified pilot version'
$auditedBridgeText = Get-Content -LiteralPath $bridgeSource -Raw -Encoding UTF8
foreach ($withdrawnWeightMarker in @(
    'player:unlimited-weight',
    '/Game/_Dawnwalker/Player/Effects/GE_EnableWeightLimitExceed.GE_EnableWeightLimitExceed_C',
    'ability_system:GetGameplayEffectCount(effect_class, nil, false)',
    'ability_system:MakeEffectContext()',
    'ability_system:BP_ApplyGameplayEffectToSelf(effect_class, 1.0, effect_context)',
    'snapshot.target:RemoveActiveGameplayEffect(snapshot.handle, -1)',
    'bPassedFiltersAndWasExecuted',
    'baseline_count',
    'baseline_can_exceed'
)) {
    Assert-True ($auditedBridgeText.IndexOf($withdrawnWeightMarker, [System.StringComparison]::Ordinal) -lt 0) "withdrawn Unlimited Weight marker is absent: $withdrawnWeightMarker"
}
Assert-True ($auditedBridgeText.IndexOf('RemoveActiveGameplayEffectBySourceEffect', [System.StringComparison]::Ordinal) -lt 0) 'bridge never removes gameplay effects by source class'
Assert-True ($payload.bridgeSourcePath -eq [System.IO.Path]::GetFullPath($bridgeSource)) 'the payload validator defaults to the current integration bridge'

$luaInterpreter = Get-Command lua -ErrorAction Stop
$weightHarnessPath = Join-Path $PSScriptRoot 'DawnwalkerUnlimitedWeightPilot.Tests.lua'
$weightHarnessTemp = Join-Path ([System.IO.Path]::GetTempPath()) ('dawnwalker-weight-harness-' + [Guid]::NewGuid().ToString('N'))
$weightBridgeRoot = Join-Path $weightHarnessTemp 'DawnwalkerModMenuBridge'
New-Item -ItemType Directory -Force -Path $weightBridgeRoot | Out-Null
$previousTemp = $env:TEMP
try {
    $env:TEMP = $weightHarnessTemp
    $weightHarnessOutput = @(& $luaInterpreter.Source $weightHarnessPath $bridgeSource 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "Unlimited Weight withdrawal harness exits successfully: $(($weightHarnessOutput | Out-String).Trim())"
    Assert-True ((($weightHarnessOutput | Out-String) -match 'Unlimited Weight withdrawal harness passed')) 'Unlimited Weight is not advertised and is rejected by the bridge'
}
finally {
    $env:TEMP = $previousTemp
    Remove-Item -LiteralPath $weightHarnessTemp -Recurse -Force -ErrorAction SilentlyContinue
}

$questHarnessPath = Join-Path $PSScriptRoot 'DawnwalkerQuestJournalPilot.Tests.lua'
$questHarnessTemp = Join-Path ([System.IO.Path]::GetTempPath()) ('dawnwalker-quest-harness-' + [Guid]::NewGuid().ToString('N'))
$questBridgeRoot = Join-Path $questHarnessTemp 'DawnwalkerModMenuBridge'
New-Item -ItemType Directory -Force -Path $questBridgeRoot | Out-Null
$previousTemp = $env:TEMP
try {
    $env:TEMP = $questHarnessTemp
    $questHarnessOutput = @(& $luaInterpreter.Source $questHarnessPath $bridgeSource 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "Quest Journal read-only harness exits successfully: $(($questHarnessOutput | Out-String).Trim())"
    Assert-True ((($questHarnessOutput | Out-String) -match 'Quest Journal read-only harness passed')) 'Quest Journal readback is bounded, encoded, and non-mutating'
}
finally {
    $env:TEMP = $previousTemp
    Remove-Item -LiteralPath $questHarnessTemp -Recurse -Force -ErrorAction SilentlyContinue
}

$goldHarnessPath = Join-Path $PSScriptRoot 'DawnwalkerAddGoldPilot.Tests.lua'
$goldHarnessTemp = Join-Path ([System.IO.Path]::GetTempPath()) ('dawnwalker-gold-harness-' + [Guid]::NewGuid().ToString('N'))
$goldBridgeRoot = Join-Path $goldHarnessTemp 'DawnwalkerModMenuBridge'
New-Item -ItemType Directory -Force -Path $goldBridgeRoot | Out-Null
$previousTemp = $env:TEMP
try {
    $env:TEMP = $goldHarnessTemp
    $goldHarnessOutput = @(& $luaInterpreter.Source $goldHarnessPath $bridgeSource 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "Add Gold harness exits successfully: $(($goldHarnessOutput | Out-String).Trim())"
    Assert-True ((($goldHarnessOutput | Out-String) -match 'Add Gold pilot harness passed')) 'Add Gold enforces exact component identity, bounds, readback, and observed-delta rollback'
}
finally {
    $env:TEMP = $previousTemp
    Remove-Item -LiteralPath $goldHarnessTemp -Recurse -Force -ErrorAction SilentlyContinue
}

$teardownHarnessPath = Join-Path $PSScriptRoot 'DawnwalkerBridgeTeardownState.Tests.lua'
$teardownHarnessTemp = Join-Path ([System.IO.Path]::GetTempPath()) ('dawnwalker-teardown-harness-' + [Guid]::NewGuid().ToString('N'))
$teardownBridgeRoot = Join-Path $teardownHarnessTemp 'DawnwalkerModMenuBridge'
New-Item -ItemType Directory -Force -Path $teardownBridgeRoot | Out-Null
$previousTemp = $env:TEMP
try {
    $env:TEMP = $teardownHarnessTemp
    $teardownHarnessOutput = @(& $luaInterpreter.Source $teardownHarnessPath $bridgeSource 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "Teardown-state harness exits successfully: $(($teardownHarnessOutput | Out-String).Trim())"
    Assert-True ((($teardownHarnessOutput | Out-String) -match 'Dawnwalker bridge teardown-state harness passed')) 'failed resource and snapshot restores retain their handles, block new sessions, and retry safely'
}
finally {
    $env:TEMP = $previousTemp
    Remove-Item -LiteralPath $teardownHarnessTemp -Recurse -Force -ErrorAction SilentlyContinue
}

$difficultyHarnessPath = Join-Path $PSScriptRoot 'DawnwalkerDifficultyPilot.Tests.lua'
$difficultyHarnessTemp = Join-Path ([System.IO.Path]::GetTempPath()) ('dawnwalker-difficulty-harness-' + [Guid]::NewGuid().ToString('N'))
$difficultyBridgeRoot = Join-Path $difficultyHarnessTemp 'DawnwalkerModMenuBridge'
New-Item -ItemType Directory -Force -Path $difficultyBridgeRoot | Out-Null
$previousTemp = $env:TEMP
try {
    $env:TEMP = $difficultyHarnessTemp
    $difficultyHarnessOutput = @(& $luaInterpreter.Source $difficultyHarnessPath $bridgeSource 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "Two-axis difficulty harness exits successfully: $(($difficultyHarnessOutput | Out-String).Trim())"
    Assert-True ((($difficultyHarnessOutput | Out-String) -match 'two-axis difficulty pilot harness passed')) 'difficulty axes enforce exact config, owner, identity, readback, and retained rollback contracts'
}
finally {
    $env:TEMP = $previousTemp
    Remove-Item -LiteralPath $difficultyHarnessTemp -Recurse -Force -ErrorAction SilentlyContinue
}

$wrapperText = Get-Content -LiteralPath $wrapperPath -Raw -Encoding UTF8
Assert-True ($wrapperText -match "'PromoteBridgePilot'") 'wrapper exposes the pilot promotion action'
Assert-True ($wrapperText -match 'ApproveCleanSmokeLog' -and $wrapperText -match 'ApproveHookEngineTickPilot') 'wrapper carries both explicit approvals'

Assert-Rejected -Operation {
    Enable-DawnwalkerBridgePilot -ContractPath $contractPath -ErrorAction Stop
} -ExpectedMessage 'ApproveCleanSmokeLog' -Label 'promotion without clean-log approval'
Assert-Rejected -Operation {
    Enable-DawnwalkerBridgePilot -ContractPath $contractPath -ApproveCleanSmokeLog -ErrorAction Stop
} -ExpectedMessage 'ApproveHookEngineTickPilot' -Label 'promotion without HookEngineTick approval'

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('dawnwalker-bridge-pilot-test-' + [Guid]::NewGuid().ToString('N'))
try {
    $testTemplates = Join-Path $testRoot 'templates'
    $testSource = Join-Path $testRoot 'main.lua'
    Copy-Item -LiteralPath $pilotTemplates -Destination $testTemplates -Recurse
    Copy-Item -LiteralPath $bridgeSource -Destination $testSource

    $settingsPath = Join-Path $testTemplates 'UE4SS-settings.ini'
    $originalSettings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8
    [System.IO.File]::WriteAllText(
        $settingsPath,
        $originalSettings.Replace('HookUObjectProcessEvent = 0', 'HookUObjectProcessEvent = 1'),
        [System.Text.UTF8Encoding]::new($false)
    )
    Assert-Rejected -Operation {
        Test-DawnwalkerBridgePilotPayload -ContractPath $contractPath -TemplatesRoot $testTemplates -BridgeSourcePath $testSource
    } -ExpectedMessage 'HookUObjectProcessEvent must equal 0' -Label 'second enabled hook'
    [System.IO.File]::WriteAllText($settingsPath, $originalSettings, [System.Text.UTF8Encoding]::new($false))

    [System.IO.File]::WriteAllText(
        $settingsPath,
        $originalSettings + [Environment]::NewLine + 'GuiConsoleEnabled = 1' + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
    Assert-Rejected -Operation {
        Test-DawnwalkerBridgePilotPayload -ContractPath $contractPath -TemplatesRoot $testTemplates -BridgeSourcePath $testSource
    } -ExpectedMessage "exactly one 'GuiConsoleEnabled'" -Label 'duplicate GUI-console override'
    [System.IO.File]::WriteAllText(
        $settingsPath,
        [Regex]::Replace($originalSettings, '(?m)^[ \t]*HookProcessInternal[ \t]*=[^\r\n]*(?:\r?\n)?', ''),
        [System.Text.UTF8Encoding]::new($false)
    )
    Assert-Rejected -Operation {
        Test-DawnwalkerBridgePilotPayload -ContractPath $contractPath -TemplatesRoot $testTemplates -BridgeSourcePath $testSource
    } -ExpectedMessage 'approved Hook\* assignments' -Label 'missing explicit disabled hook'
    [System.IO.File]::WriteAllText($settingsPath, $originalSettings, [System.Text.UTF8Encoding]::new($false))

    $modsPath = Join-Path $testTemplates 'Mods\mods.txt'
    $originalMods = Get-Content -LiteralPath $modsPath -Raw -Encoding UTF8
    [System.IO.File]::WriteAllText(
        $modsPath,
        $originalMods.Replace('Keybinds : 0', 'Keybinds : 1'),
        [System.Text.UTF8Encoding]::new($false)
    )
    Assert-Rejected -Operation {
        Test-DawnwalkerBridgePilotPayload -ContractPath $contractPath -TemplatesRoot $testTemplates -BridgeSourcePath $testSource
    } -ExpectedMessage 'Only DawnwalkerModBridge' -Label 'second enabled mod'
    [System.IO.File]::WriteAllText($modsPath, $originalMods, [System.Text.UTF8Encoding]::new($false))

    $originalSource = Get-Content -LiteralPath $testSource -Raw -Encoding UTF8
    [System.IO.File]::WriteAllText(
        $testSource,
        $originalSource.Replace('    "world:location-readback",', '    "world:location-readback",' + [Environment]::NewLine + '    "world:weather",'),
        [System.Text.UTF8Encoding]::new($false)
    )
    Assert-Rejected -Operation {
        Test-DawnwalkerBridgePilotPayload -ContractPath $contractPath -TemplatesRoot $testTemplates -BridgeSourcePath $testSource
    } -ExpectedMessage 'nineteen audited controls' -Label 'unreviewed twentieth capability'

    $fakeGameRoot = Join-Path $testRoot 'fake-game'
    $fakeWin64 = Join-Path $fakeGameRoot 'Dawnwalker\Binaries\Win64'
    $fakeUe4ss = Join-Path $fakeWin64 'ue4ss'
    $fakeDwmapi = Join-Path $fakeWin64 'dwmapi.dll'
    $fakeSettings = Join-Path $fakeUe4ss 'UE4SS-settings.ini'
    $fakeMods = Join-Path $fakeUe4ss 'Mods\mods.txt'
    $fakeUEHelpers = Join-Path $fakeUe4ss 'Mods\shared\UEHelpers\UEHelpers.lua'
    $fakeLog = Join-Path $fakeUe4ss 'UE4SS.log'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fakeMods) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fakeUEHelpers) | Out-Null
    [System.IO.File]::WriteAllText($fakeDwmapi, 'synthetic pinned proxy', [System.Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath (Join-Path $kitRoot 'templates\UE4SS-settings.ini') -Destination $fakeSettings
    Copy-Item -LiteralPath (Join-Path $kitRoot 'templates\Mods\mods.txt') -Destination $fakeMods
    $pinnedArchivePath = Join-Path $kitRoot ([string](Read-DawnwalkerJsonFile -LiteralPath $contractPath).ue4ss.archiveRelativePath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $pinnedArchive = [System.IO.Compression.ZipFile]::OpenRead($pinnedArchivePath)
    try {
        $helperEntries = @($pinnedArchive.Entries | Where-Object { $_.FullName -ceq 'ue4ss/Mods/shared/UEHelpers/UEHelpers.lua' })
        Assert-True ($helperEntries.Count -eq 1) 'test fixture locates exactly one pinned UEHelpers archive entry'
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($helperEntries[0], $fakeUEHelpers, $true)
    }
    finally {
        $pinnedArchive.Dispose()
    }
    Assert-True ((Get-DawnwalkerSha256 -LiteralPath $fakeUEHelpers) -ceq '7476F02EEF0C87BFEAB169F2FFE2E704363FAEAAE4BF9F1BDA574B1E34F4A0E9') 'synthetic inert install uses exact pinned UEHelpers bytes'

    $fakeInstalledAt = [DateTime]::UtcNow.AddMinutes(-10)
    [System.IO.File]::WriteAllText(
        $fakeLog,
        '[UE4SS] synthetic clean inert-smoke startup completed successfully',
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::SetLastWriteTimeUtc($fakeLog, [DateTime]::UtcNow.AddMinutes(-1))

    $fakeStateRoot = Join-Path $testRoot 'state'
    $fakeTransactionId = '20260903T223344Z-abcdef12'
    $fakeTransactionRoot = Join-Path (Join-Path $fakeStateRoot 'backups') $fakeTransactionId
    $fakeTransactionStatePath = Join-Path $fakeTransactionRoot 'transaction-state.json'
    $fakeCurrentStatePath = Join-Path $fakeStateRoot 'install-state.json'
    New-Item -ItemType Directory -Force -Path $fakeTransactionRoot | Out-Null
    $fakeInstalledInventory = @(
        Get-DawnwalkerFileInventory -RootPath $fakeDwmapi
        Get-DawnwalkerFileInventory -RootPath $fakeUe4ss | Where-Object { $_.relativePath -cne 'UE4SS.log' }
    )
    $fakeState = [ordered]@{
        cyberfox1337x = 'function(dawnwalker_reflection_install_state)'
        schemaVersion = 1
        transactionId = $fakeTransactionId
        status = 'installed'
        createdAtUtc = $fakeInstalledAt.AddMinutes(-1).ToString('o')
        installedAtUtc = $fakeInstalledAt.ToString('o')
        contractPath = [System.IO.Path]::GetFullPath($contractPath)
        manifestPath = (Join-Path $testRoot 'appmanifest_3751260.acf')
        gameInstallRoot = $fakeGameRoot
        win64Root = $fakeWin64
        executableSha256 = 'SYNTHETIC-EXECUTABLE-HASH'
        buildId = '25014996'
        archive = $null
        saveBackup = [pscustomobject]@{ targetPath = (Join-Path $testRoot 'saves'); kind = 'absent'; backupPath = $null; inventory = @() }
        targetBackups = @(
            [pscustomobject]@{ targetPath = $fakeDwmapi; kind = 'absent'; backupPath = $null; inventory = @() }
            [pscustomobject]@{ targetPath = $fakeUe4ss; kind = 'absent'; backupPath = $null; inventory = @() }
        )
        installedInventory = $fakeInstalledInventory
    }
    $fakeStateJson = $fakeState | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($fakeCurrentStatePath, $fakeStateJson, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($fakeTransactionStatePath, $fakeStateJson, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText(
        $fakeState.manifestPath,
        '"appid" "3751260"' + [Environment]::NewLine + '"installdir" "The Blood of Dawnwalker"',
        [System.Text.UTF8Encoding]::new($false)
    )

    $mockVerification = [pscustomobject]@{
        installationEligible = $true
        errors = @()
        paths = [pscustomobject]@{ win64 = $fakeWin64 }
        executable = [pscustomobject]@{ sha256 = 'SYNTHETIC-EXECUTABLE-HASH' }
        manifest = [pscustomobject]@{ buildId = '25014996' }
    }
    $reflectionModule = Get-Module DawnwalkerReflectionTools
    & $reflectionModule {
        param($Verification)
        $script:BridgePilotSyntheticVerification = $Verification
        Set-Item -Path Function:\script:Test-DawnwalkerOfficialBuild -Value {
            param($ContractPath, $ManifestPath, $GameInstallRoot, [switch]$RequireStopped)
            return $script:BridgePilotSyntheticVerification
        }
        Set-Item -Path Function:\script:Get-DawnwalkerRunningProcesses -Value {
            param([object[]]$ProcessNames)
            return @()
        }
    } $mockVerification

    try {
        Remove-Item -LiteralPath $fakeUEHelpers -Force
        Assert-Rejected -Operation {
            Enable-DawnwalkerBridgePilot `
                -ContractPath $contractPath `
                -StateRoot $fakeStateRoot `
                -SmokeLogPath $fakeLog `
                -ApproveCleanSmokeLog `
                -ApproveHookEngineTickPilot `
                -Confirm:$false
        } -ExpectedMessage 'UEHelpers dependency is missing' -Label 'promotion with missing UEHelpers dependency'

        $pinnedArchive = [System.IO.Compression.ZipFile]::OpenRead($pinnedArchivePath)
        try {
            $helperEntry = @($pinnedArchive.Entries | Where-Object { $_.FullName -ceq 'ue4ss/Mods/shared/UEHelpers/UEHelpers.lua' })[0]
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($helperEntry, $fakeUEHelpers, $true)
        }
        finally {
            $pinnedArchive.Dispose()
        }
        [System.IO.File]::WriteAllText($fakeUEHelpers, 'tampered helper', [System.Text.UTF8Encoding]::new($false))
        Assert-Rejected -Operation {
            Enable-DawnwalkerBridgePilot `
                -ContractPath $contractPath `
                -StateRoot $fakeStateRoot `
                -SmokeLogPath $fakeLog `
                -ApproveCleanSmokeLog `
                -ApproveHookEngineTickPilot `
                -Confirm:$false
        } -ExpectedMessage 'UEHelpers dependency length mismatch' -Label 'promotion with tampered UEHelpers dependency'

        $pinnedArchive = [System.IO.Compression.ZipFile]::OpenRead($pinnedArchivePath)
        try {
            $helperEntry = @($pinnedArchive.Entries | Where-Object { $_.FullName -ceq 'ue4ss/Mods/shared/UEHelpers/UEHelpers.lua' })[0]
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($helperEntry, $fakeUEHelpers, $true)
        }
        finally {
            $pinnedArchive.Dispose()
        }
        $promotionResult = Enable-DawnwalkerBridgePilot `
            -ContractPath $contractPath `
            -StateRoot $fakeStateRoot `
            -SmokeLogPath $fakeLog `
            -ApproveCleanSmokeLog `
            -ApproveHookEngineTickPilot `
            -Confirm:$false
    }
    finally {
        Import-Module $modulePath -Force
    }

    $promotedState = Read-DawnwalkerJsonFile -LiteralPath $fakeCurrentStatePath
    $promotedSettings = Get-Content -LiteralPath $fakeSettings -Raw -Encoding UTF8
    $promotedMods = Get-Content -LiteralPath $fakeMods -Raw -Encoding UTF8
    $installedBridge = Join-Path $fakeUe4ss 'Mods\DawnwalkerModBridge\Scripts\main.lua'
    Assert-True $promotionResult.promoted 'synthetic exact inert-smoke transaction promotes successfully'
    Assert-True ($promotedState.status -ceq 'bridge-pilot') 'active state records the bridge-pilot profile'
    Assert-True (@($promotedState.bridgePilot.snapshots).Count -eq 5) 'all five changed paths have transaction snapshots'
    Assert-True ($promotedSettings -match '(?m)^HookEngineTick = 1$') 'promoted settings enable HookEngineTick'
    Assert-True (-not ($promotedSettings -match '(?m)^Hook(?!EngineTick)[^=]+\s*=\s*1$')) 'promoted settings leave every other hook disabled'
    Assert-True ($promotedMods -match '(?m)^DawnwalkerModBridge : 1$') 'promoted registry enables the bridge'
    Assert-True (-not ($promotedMods -match '(?im)^\s*(?!DawnwalkerModBridge\s*:)[^;\r\n]+\s*:\s*1\s*$')) 'promoted registry enables no second mod'
    Assert-True ((Get-DawnwalkerSha256 -LiteralPath $installedBridge) -ceq (Get-DawnwalkerSha256 -LiteralPath $bridgeSource)) 'promotion copies the current integration bridge exactly'

    $reflectionModule = Get-Module DawnwalkerReflectionTools
    & $reflectionModule {
        Set-Item -Path Function:\script:Get-DawnwalkerRunningProcesses -Value {
            param([object[]]$ProcessNames)
            return @()
        }
    }
    try {
        $rollbackResult = Invoke-DawnwalkerReflectionRollback `
            -ContractPath $contractPath `
            -StateRoot $fakeStateRoot `
            -ManifestPath $fakeState.manifestPath `
            -GameInstallRoot $fakeGameRoot `
            -Confirm:$false
    }
    finally {
        Import-Module $modulePath -Force
    }
    Assert-True $rollbackResult.rolledBack 'existing transaction rollback accepts and reverses bridge-pilot state'
    Assert-True (-not (Test-Path -LiteralPath $fakeDwmapi) -and -not (Test-Path -LiteralPath $fakeUe4ss)) 'rollback restores the synthetic pre-install loader baseline'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

[pscustomobject]@{
    cyberfox1337x = 'function(dawnwalker_bridge_pilot_promotion_test_result)'
    passed = $true
    settingsSha256 = $payload.settingsSha256
    modsSha256 = $payload.modsSha256
    bridgeSourceSha256 = $payload.bridgeSourceSha256
    capabilities = @($payload.capabilities)
} | ConvertTo-Json -Depth 5
