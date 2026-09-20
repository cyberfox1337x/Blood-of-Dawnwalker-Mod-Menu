[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory = $true)][string]$ModuleName)
    return $ModuleName
}

$null = cyberfox1337x -ModuleName 'dawnwalker_reflection_tools_tests'

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

$kitRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $kitRoot 'DawnwalkerReflectionTools.psm1') -Force
$contractPath = Join-Path $kitRoot 'official-build.json'
$contract = Read-DawnwalkerJsonFile -LiteralPath $contractPath
$matrix = Read-DawnwalkerJsonFile -LiteralPath (Join-Path $kitRoot 'feature-contract-matrix.json')

$utcTimestamp = [DateTime]::SpecifyKind([DateTime]::new(2026, 9, 3, 0, 30, 43, 887), [DateTimeKind]::Utc)
Assert-True ((ConvertTo-DawnwalkerUtcDateTime -Value $utcTimestamp) -eq $utcTimestamp) 'JSON-materialized UTC timestamps are not offset twice'
Assert-True ((ConvertTo-DawnwalkerUtcDateTime -Value '2026-09-03T00:30:43.8870000Z') -eq $utcTimestamp) 'ISO UTC timestamp strings preserve their instant'
$unspecifiedTimestampRejected = $false
try { $null = ConvertTo-DawnwalkerUtcDateTime -Value ([DateTime]::new(2026, 9, 3, 0, 30, 43)) } catch { $unspecifiedTimestampRejected = $true }
Assert-True $unspecifiedTimestampRejected 'ambiguous timestamps are rejected'

Assert-True ($contract.cyberfox1337x -eq 'function(dawnwalker_official_build_contract)') 'official contract signature'
Assert-True ($matrix.cyberfox1337x -eq 'function(dawnwalker_feature_contract_matrix)') 'feature matrix signature'
Assert-True (($matrix.categories.id | Sort-Object) -join ',' -eq 'combat,inventory,npc,player,quests,settings,teleport,visuals,world') 'all nine requested categories'
$navigationShellEntries = @($matrix.appShell | Where-Object { $_.control -eq 'navigation' })
Assert-True ($navigationShellEntries.Count -eq 8) 'eight isolated app navigation pages'
Assert-True ('nav-inventory' -notin @($navigationShellEntries.id)) 'Inventory is not a duplicate standalone navigation page'
$playerNavigation = @($navigationShellEntries | Where-Object { $_.id -eq 'nav-player' })
Assert-True ($playerNavigation.Count -eq 1 -and $playerNavigation[0].localAction -match 'Inventory section') 'Player page owns the Inventory section'
Assert-True (($matrix.policy.liveGate.requiredEvidence).Count -eq 5) 'five-part live evidence gate'

$allStatuses = @($matrix.categories.features.status) + @($matrix.appShell.status) + @($matrix.hotkeys.status)
$allowedStatuses = @('pending-reflection', 'local-only', 'pilot-static-only', 'pilot-live-verified', 'blocked-missing-asset-pair', 'unsupported-concept')
Assert-True (@($allStatuses | Where-Object { $_ -notin $allowedStatuses }).Count -eq 0) 'feature matrix uses only reviewed status vocabulary'
Assert-True (@($allStatuses | Where-Object { $_ -eq 'pilot-static-only' }).Count -eq 8) 'exactly eight presented controls remain static-only pilots'
Assert-True (@($allStatuses | Where-Object { $_ -eq 'pilot-live-verified' }).Count -eq 9) 'exactly nine complete capability promises or hotkeys have pilot live verification'
Assert-True (@($allStatuses | Where-Object { $_ -eq 'unsupported-concept' }).Count -gt 0) 'unsupported concepts stay explicitly disclosed'
Assert-True (@($allStatuses | Where-Object { $_ -eq 'blocked-missing-asset-pair' }).Count -gt 0) 'asset-dependent controls stay explicitly blocked'
$inventoryWeight = @($matrix.categories | Where-Object { $_.id -eq 'inventory' } | ForEach-Object { $_.features } | Where-Object { $_.id -eq 'unlimited-weight' })
Assert-True ($inventoryWeight.Count -eq 1) 'Unlimited Weight has one inventory presentation record'
Assert-True ($inventoryWeight[0].status -eq 'pending-reflection' -and $inventoryWeight[0].disposition -eq 'withdrawn-feasibility-probe') 'Unlimited Weight is withdrawn to a feasibility probe'
Assert-True ($inventoryWeight[0].control -eq 'none' -and $inventoryWeight[0].visibleInRelease -eq $false) 'withdrawn Unlimited Weight exposes no release control'
$requiredFeatures = @('god-mode', 'infinite-health', 'unlimited-stamina', 'rpg-difficulty', 'action-difficulty', 'kill-all-enemies', 'clear-fog-of-war', 'add-gold', 'teleport-waypoint', 'spawn-horse', 'quest-journal-readback', 'f10-menu-toggle')
$allIds = @($matrix.categories.features.id) + @($matrix.appShell.id) + @($matrix.hotkeys.id)
foreach ($featureId in $requiredFeatures) {
    Assert-True ($featureId -in $allIds) "matrix includes $featureId"
}

$smokeSettings = Get-Content -LiteralPath (Join-Path $kitRoot 'templates\UE4SS-settings.ini') -Raw
$smokeMods = Get-Content -LiteralPath (Join-Path $kitRoot 'templates\Mods\mods.txt') -Raw
Assert-True ($smokeSettings -match '(?m)^UseCache = 0$') 'smoke cache disabled'
Assert-True ($smokeSettings -match '(?m)^MajorVersion = 5$' -and $smokeSettings -match '(?m)^MinorVersion = 5$') 'engine 5.5 override'
Assert-True ($smokeSettings -match '(?m)^ControllingModsTxt\s*=\s*$') 'smoke resolves the default Mods/mods.txt without a duplicated ue4ss path'
Assert-True (-not ($smokeSettings -match '(?m)^Hook[^=]+\s*=\s*1$')) 'every smoke hook disabled'
Assert-True (-not ($smokeMods -match '(?m)^\s*[^;\r\n]+\s*:\s*1\s*$')) 'every smoke mod disabled'

$dumpSettings = Get-Content -LiteralPath (Join-Path $kitRoot 'templates\dump\UE4SS-settings.ini') -Raw
$dumpMods = Get-Content -LiteralPath (Join-Path $kitRoot 'templates\dump\Mods\mods.txt') -Raw
$dumpKeys = Get-Content -LiteralPath (Join-Path $kitRoot 'templates\dump\Mods\Keybinds\Scripts\main.lua') -Raw
Assert-True ($dumpSettings -match '(?m)^bForceGUObjectArrayForIteration = true$') 'dump forces guarded UObject iteration'
Assert-True ($dumpSettings -match '(?m)^UseModuleOffsets = 1$') 'dump uses module-relative offsets'
Assert-True ($dumpSettings -match '(?m)^GuiConsoleEnabled = 0$' -and $dumpSettings -match '(?m)^GuiConsoleVisible = 0$') 'dump GUI remains disabled'
Assert-True ($dumpSettings -match '(?m)^GraphicsAPI = opengl$') 'disabled dump GUI retains the stable smoke renderer'
Assert-True (-not ($dumpSettings -match '(?m)^Hook[^=]+\s*=\s*1$')) 'every promoted dump hook remains disabled'
Assert-True ($dumpSettings -match '(?m)^ControllingModsTxt\s*=\s*$') 'dump resolves the default Mods/mods.txt without a duplicated ue4ss path'
Assert-True ($dumpMods -match '(?m)^Keybinds : 1$') 'restricted dump keys enabled after promotion'
Assert-True (-not ($dumpMods -match '(?im)^\s*(?!Keybinds\s*:)[^;\r\n]+\s*:\s*1\s*$')) 'no promoted action mod enabled'
Assert-True ($dumpKeys -notmatch 'DumpStaticMeshes|DumpAllActors|Key\.F10') 'no asset, actor, or F10 dump binding'
Assert-True ($dumpKeys -match 'cyberfox1337x\["function"\]\s*=\s*function') 'Lua signature uses valid indexed-function assignment syntax'
Assert-True ($dumpKeys -match 'local started_dumps = \{\}') 'restricted dump keybinds keep per-process one-shot state'
Assert-True ($dumpKeys -match 'if started_dumps\[name\] then' -and $dumpKeys -match 'started_dumps\[name\] = true') 'restricted dump keybinds suppress key-repeat duplicate runs'
$luaCompiler = Get-Command 'luac.exe' -ErrorAction SilentlyContinue
if ($luaCompiler) {
    & $luaCompiler.Source -p (Join-Path $kitRoot 'templates\dump\Mods\Keybinds\Scripts\main.lua')
    Assert-True ($LASTEXITCODE -eq 0) 'restricted dump keybind script passes luac syntax validation'
}
else {
    Write-Warning 'luac.exe is unavailable; the static Lua signature and binding assertions still ran.'
}

$payload = Test-DawnwalkerUe4ssArchive -ContractPath $contractPath -ArchivePath (Join-Path $kitRoot ([string]$contract.ue4ss.archiveRelativePath))
Assert-True $payload.valid 'pinned official zDEV payload verifies'
Assert-True ($payload.ueHelpers.relativePath -ceq 'ue4ss/Mods/shared/UEHelpers/UEHelpers.lua') 'pinned archive exposes the exact UEHelpers dependency path'
Assert-True ($payload.ueHelpers.bytes -eq 10237) 'pinned archive exposes the exact UEHelpers dependency size'
Assert-True ($payload.ueHelpers.sha256 -ceq '7476F02EEF0C87BFEAB169F2FFE2E704363FAEAAE4BF9F1BDA574B1E34F4A0E9') 'pinned archive exposes the exact UEHelpers dependency hash'

$official = Test-DawnwalkerOfficialBuild -ContractPath $contractPath
Assert-True $official.identityValid 'installed official Dawnwalker build matches the pin'
Assert-True ($official.installationEligible -eq (-not $official.gameRunning)) 'install eligibility follows the process gate'

$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Assert-True (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf) 'Windows PowerShell executable is available'
$verifyWrapper = Join-Path $kitRoot 'Verify-DawnwalkerOfficialBuild.ps1'
$installWrapper = Join-Path $kitRoot 'Install-DawnwalkerReflectionTools.ps1'

$verifyOutput = (& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $verifyWrapper -AsJson 2>&1 | Out-String)
$verifyExitCode = $LASTEXITCODE
Assert-True ($verifyExitCode -eq 0) "Verify wrapper succeeds via Windows PowerShell -File: $verifyOutput"
$verifyResult = $verifyOutput | ConvertFrom-Json
Assert-True $verifyResult.identityValid 'Windows PowerShell wrapper reports the pinned official build'

$payloadOutput = (& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $installWrapper -Action VerifyPayload 2>&1 | Out-String)
$payloadExitCode = $LASTEXITCODE
Assert-True ($payloadExitCode -eq 0) "VerifyPayload wrapper succeeds via Windows PowerShell -File: $payloadOutput"
$payloadResult = $payloadOutput | ConvertFrom-Json
Assert-True ($payloadResult.valid -and $payloadResult.sha256 -eq $contract.ue4ss.archiveSha256) 'Windows PowerShell wrapper verifies the pinned zDEV payload'

if ($official.gameRunning) {
    $statePath = Join-Path $kitRoot 'state\install-state.json'
    $dwmapiPath = Join-Path $official.paths.win64 'dwmapi.dll'
    $ue4ssPath = Join-Path $official.paths.win64 'ue4ss'
    $beforeGate = @(
        Test-Path -LiteralPath $statePath
        Test-Path -LiteralPath $dwmapiPath
        Test-Path -LiteralPath $ue4ssPath
    )
    $previousErrorPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $installOutput = (& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $installWrapper -Action Install 2>&1 | Out-String)
        $installExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorPreference
    }
    $afterGate = @(
        Test-Path -LiteralPath $statePath
        Test-Path -LiteralPath $dwmapiPath
        Test-Path -LiteralPath $ue4ssPath
    )
    Assert-True ($installExitCode -ne 0) 'Install wrapper refuses through Windows PowerShell while Dawnwalker runs'
    Assert-True ($installOutput -match 'not eligible|running') 'Install refusal identifies the running-process gate'
    Assert-True (($beforeGate -join ',') -eq ($afterGate -join ',')) 'Install refusal creates no state or loader target'
}
else {
    $statePath = Join-Path $kitRoot 'state\install-state.json'
    $dwmapiPath = Join-Path $official.paths.win64 'dwmapi.dll'
    $ue4ssPath = Join-Path $official.paths.win64 'ue4ss'
    $beforePreview = @(
        Test-Path -LiteralPath $statePath
        Test-Path -LiteralPath $dwmapiPath
        Test-Path -LiteralPath $ue4ssPath
    )
    if (Test-Path -LiteralPath $statePath) {
        $previousErrorPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $previewOutput = (& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $installWrapper -Action Install -WhatIf 2>&1 | Out-String)
            $previewExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorPreference
        }
        Assert-True ($previewExitCode -ne 0) 'Install -WhatIf refuses to overlap an active stopped transaction'
        Assert-True ($previewOutput -match 'active install state') 'overlapping Install -WhatIf identifies the active transaction gate'
    }
    else {
        $previewLines = @(& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $installWrapper -Action Install -WhatIf 2>&1)
        $previewOutput = $previewLines | Out-String
        $previewExitCode = $LASTEXITCODE
        Assert-True ($previewExitCode -eq 0) "Install -WhatIf succeeds via Windows PowerShell without mutating targets: $previewOutput"
        $previewResult = $previewLines | Where-Object { [string]$_ -notmatch '^What if:' } | Out-String | ConvertFrom-Json
        Assert-True (-not $previewResult.installed -and $previewResult.whatIf) 'Install -WhatIf returns an explicit non-installed preview'
    }
    $afterPreview = @(
        Test-Path -LiteralPath $statePath
        Test-Path -LiteralPath $dwmapiPath
        Test-Path -LiteralPath $ue4ssPath
    )
    Assert-True (($beforePreview -join ',') -eq ($afterPreview -join ',')) 'Install -WhatIf never mutates state or loader targets'
}
$global:LASTEXITCODE = 0

$traversalRejected = $false
try { $null = Resolve-DawnwalkerSafeChildPath -RootPath $kitRoot -RelativePath '..\escape.txt' } catch { $traversalRejected = $true }
Assert-True $traversalRejected 'path traversal rejected'

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('dawnwalker-tools-test-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $target = Join-Path $testRoot 'target'
    $backup = Join-Path $testRoot 'backup\target'
    New-Item -ItemType Directory -Path $target | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $target 'proof.txt'), 'before')
    $snapshot = New-DawnwalkerPathSnapshot -TargetPath $target -BackupPath $backup
    [System.IO.File]::WriteAllText((Join-Path $target 'proof.txt'), 'after')
    Restore-DawnwalkerPathSnapshot -Snapshot $snapshot
    Assert-True ((Get-Content -LiteralPath (Join-Path $target 'proof.txt') -Raw) -eq 'before') 'snapshot restores original bytes'

    if (-not $official.gameRunning) {
        $fakeGameRoot = Join-Path $testRoot 'fake-game'
        $fakeWin64 = Join-Path $fakeGameRoot 'Dawnwalker\Binaries\Win64'
        $fakeDwmapi = Join-Path $fakeWin64 'dwmapi.dll'
        $fakeUe4ss = Join-Path $fakeWin64 'ue4ss'
        New-Item -ItemType Directory -Path $fakeUe4ss -Force | Out-Null
        [System.IO.File]::WriteAllText($fakeDwmapi, 'installed proxy')
        [System.IO.File]::WriteAllText((Join-Path $fakeUe4ss 'proof.txt'), 'installed loader')

        $fakeStateRoot = Join-Path $testRoot 'state'
        $fakeTransactionId = '20260903T123456Z-abcdef12'
        $fakeTransactionRoot = Join-Path (Join-Path $fakeStateRoot 'backups') $fakeTransactionId
        New-Item -ItemType Directory -Path $fakeTransactionRoot -Force | Out-Null
        $fakeState = [pscustomobject]@{
            cyberfox1337x = 'function(dawnwalker_reflection_install_state)'
            schemaVersion = 1
            transactionId = $fakeTransactionId
            status = 'installed'
            win64Root = $fakeWin64
            saveBackup = [pscustomobject]@{
                targetPath = (Join-Path $testRoot 'missing-saves')
                kind = 'absent'
                backupPath = $null
                inventory = @()
            }
            targetBackups = @(
                [pscustomobject]@{ targetPath = $fakeDwmapi; kind = 'absent'; backupPath = $null; inventory = @() }
                [pscustomobject]@{ targetPath = $fakeUe4ss; kind = 'absent'; backupPath = $null; inventory = @() }
            )
        }
        $fakeStateJson = $fakeState | ConvertTo-Json -Depth 10
        New-Item -ItemType Directory -Path $fakeStateRoot -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $fakeStateRoot 'install-state.json'), $fakeStateJson)
        [System.IO.File]::WriteAllText((Join-Path $fakeTransactionRoot 'transaction-state.json'), $fakeStateJson)
        $fakeManifest = Join-Path $testRoot 'appmanifest_3751260.acf'
        [System.IO.File]::WriteAllText($fakeManifest, '"appid" "3751260"' + [Environment]::NewLine + '"installdir" "The Blood of Dawnwalker"')

        $rollbackResult = Invoke-DawnwalkerReflectionRollback -ContractPath $contractPath -StateRoot $fakeStateRoot -ManifestPath $fakeManifest -GameInstallRoot $fakeGameRoot -Confirm:$false
        $fakeHistoryPath = Join-Path (Join-Path $fakeStateRoot 'history') "$fakeTransactionId-rolled-back.json"
        $fakeHistory = Read-DawnwalkerJsonFile -LiteralPath $fakeHistoryPath
        $fakeTransactionState = Read-DawnwalkerJsonFile -LiteralPath (Join-Path $fakeTransactionRoot 'transaction-state.json')
        Assert-True $rollbackResult.rolledBack 'synthetic full rollback succeeds without a save backup path'
        Assert-True (-not (Test-Path -LiteralPath $fakeDwmapi) -and -not (Test-Path -LiteralPath $fakeUe4ss)) 'synthetic rollback restores originally absent loader targets'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $fakeStateRoot 'install-state.json'))) 'synthetic rollback removes the active state only after finalization'
        Assert-True ($fakeHistory.status -eq 'rolled-back' -and -not [string]::IsNullOrWhiteSpace([string]$fakeHistory.rolledBackAtUtc)) 'rollback history records the completed state and timestamp'
        Assert-True ($fakeTransactionState.status -eq 'rolled-back') 'transaction-local audit state records rollback completion'
    }

    $staging = Join-Path $testRoot 'stage'
    $null = New-DawnwalkerSafeStaging -ContractPath $contractPath -ArchivePath $payload.path -TemplatesRoot (Join-Path $kitRoot 'templates') -StagingRoot $staging
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $staging 'ue4ss\Mods\CheatManagerEnablerMod'))) 'action mod directory stripped'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $staging 'ue4ss\Mods\mods.json'))) 'conflicting JSON mod registry stripped'
    $stagedModsDirectories = @(Get-ChildItem -LiteralPath (Join-Path $staging 'ue4ss\Mods') -Directory -Force | Select-Object -ExpandProperty Name | Sort-Object)
    Assert-True (($stagedModsDirectories -join ',') -ceq 'Keybinds,shared') 'sanitized staging preserves only Keybinds and the shared dependency root'
    $stagedSharedInventory = @(Get-DawnwalkerFileInventory -RootPath (Join-Path $staging 'ue4ss\Mods\shared'))
    Assert-True ($stagedSharedInventory.Count -eq 1) 'sanitized shared root contains only one file'
    Assert-True ($stagedSharedInventory[0].relativePath -ceq 'UEHelpers/UEHelpers.lua') 'sanitized shared root contains only UEHelpers.lua'
    Assert-True ($stagedSharedInventory[0].bytes -eq 10237 -and $stagedSharedInventory[0].sha256 -ceq '7476F02EEF0C87BFEAB169F2FFE2E704363FAEAAE4BF9F1BDA574B1E34F4A0E9') 'sanitized staging preserves exact UEHelpers bytes'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $staging 'ue4ss\Mods\shared\Types.lua'))) 'unneeded shared Types.lua is stripped'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $staging 'ue4ss\Mods\shared\jsbProfiler'))) 'unneeded shared profiler directory is stripped'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

[pscustomobject]@{
    cyberfox1337x = 'function(dawnwalker_reflection_tools_test_result)'
    passed = $true
    officialBuildIdentityValid = $official.identityValid
    gameRunning = $official.gameRunning
    installationEligible = $official.installationEligible
    payloadSha256 = $payload.sha256
} | ConvertTo-Json -Depth 5
