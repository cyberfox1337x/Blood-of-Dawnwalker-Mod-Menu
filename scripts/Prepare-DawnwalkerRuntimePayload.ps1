[CmdletBinding()]
param(
    [ValidateSet('discovery', 'production')]
    [string]$PayloadPhase = 'production'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory)][string]$ModuleName)
}

cyberfox1337x -ModuleName 'prepare_dawnwalker_runtime_payload'

$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$analysisRoot = Join-Path $projectRoot 'analysis\dawnwalker-uue4ss'
$sourceContractPath = Join-Path $analysisRoot 'official-build.json'
$runtimeRoot = Join-Path $projectRoot 'installer\runtime'
$runtimeVendorRoot = Join-Path $runtimeRoot 'vendor'
$runtimeOverridesRoot = Join-Path $runtimeRoot 'overrides'
$runtimeContractPath = Join-Path $runtimeRoot 'official-build.json'
$manifestPath = Join-Path $runtimeRoot 'payload-manifest.json'
$archiveDownloadUrl = 'https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental-latest/zDEV-UE4SS_v3.0.1-1111-g97b7e501.zip'
$bridgeSourcePath = if ($PayloadPhase -eq 'discovery') {
    Join-Path $projectRoot 'installer\templates\ue4ss\Mods\DawnwalkerModBridge\Scripts\main.lua'
}
else {
    Join-Path $projectRoot 'integration\uue4ss\Mods\DawnwalkerModBridge\Scripts\main.lua'
}
$settingsTemplatePath = Join-Path $projectRoot 'installer\templates\ue4ss\UE4SS-settings.ini'
$modsTemplatePath = Join-Path $projectRoot 'installer\templates\ue4ss\Mods\mods.txt'
$hookEngineTickProofPath = Join-Path $projectRoot 'qa\dawnwalker-hook-engine-tick-proof.json'

$expectedAppId = '3751260'
$expectedBuildId = '25107392'
$expectedExecutableSha256 = '45B7C2949F519ED3E45F7FBDB7127A03373FE44B34ABB58E3C987C5054E2409E'
$expectedArchiveBytes = 44605660
$expectedArchiveSha256 = '8C2E28BB1479CBEA7BF5A3C16E027580D9E71D21606971B5BD103A20BA94C617'
$expectedRelease = 'v3.0.1-1111-g97b7e501'
$requiredUEHelpersRelativePath = 'ue4ss/Mods/shared/UEHelpers/UEHelpers.lua'
$requiredUEHelpersBytes = 10237
$requiredUEHelpersSha256 = '7476F02EEF0C87BFEAB169F2FFE2E704363FAEAAE4BF9F1BDA574B1E34F4A0E9'

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

function Get-ArchiveEntryIdentity {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $archive = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($ArchivePath))
    try {
        $normalizedPath = $RelativePath.Replace('\', '/')
        $entries = @($archive.Entries | Where-Object {
            $_.FullName.Replace('\', '/').TrimEnd('/').Equals($normalizedPath, [StringComparison]::OrdinalIgnoreCase)
        })
        if ($entries.Count -ne 1) {
            throw "Pinned archive must contain exactly one $normalizedPath entry; found $($entries.Count)."
        }
        $entry = $entries[0]
        $stream = $entry.Open()
        try {
            $algorithm = [Security.Cryptography.SHA256]::Create()
            try {
                $hash = [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '')
            }
            finally {
                $algorithm.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }
        return [pscustomobject]@{
            relativePath = $normalizedPath
            bytes = [int64]$entry.Length
            sha256 = $hash
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Assert-UEHelpersIdentity {
    param([Parameter(Mandatory)]$Identity)

    if ([string]$Identity.relativePath -cne $requiredUEHelpersRelativePath -or
        [int64]$Identity.bytes -ne [int64]$requiredUEHelpersBytes -or
        [string]$Identity.sha256 -cne $requiredUEHelpersSha256) {
        throw 'The pinned UEHelpers dependency failed its exact path/size/hash identity check.'
    }
}

function Assert-SafeRelativePath {
    param([Parameter(Mandatory)][string]$RelativePath)

    $normalized = $RelativePath.Replace('/', '\').TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($normalized) -or [IO.Path]::IsPathRooted($normalized) -or
        $normalized -match '(^|\\)\.\.(\\|$)' -or $normalized.Contains(':')) {
        throw "Unsafe runtime path: $RelativePath"
    }
    return $normalized.TrimStart('\')
}

function Assert-AllowedRuntimeTarget {
    param([Parameter(Mandatory)][string]$RelativePath)

    $normalized = (Assert-SafeRelativePath -RelativePath $RelativePath).Replace('\', '/')
    if ($normalized -ne 'dwmapi.dll' -and $normalized -ne 'ue4ss' -and -not $normalized.StartsWith('ue4ss/', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Runtime entry is outside the approved nested UE4SS layout: $RelativePath"
    }
    return $normalized
}

function Read-DawnwalkerBridgeSourceMetadata {
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Dawnwalker bridge source is missing: $LiteralPath"
    }
    $source = Get-Content -LiteralPath $LiteralPath -Raw
    $literalValues = [ordered]@{}
    $phaseMatches = [regex]::Matches($source, '(?m)^\s*local\s+BRIDGE_PHASE\s*=\s*"(?<Value>[^"\r\n]*)"\s*$')
    if ($phaseMatches.Count -ne 1) {
        throw 'Bridge source must declare exactly one literal local BRIDGE_PHASE value.'
    }
    $literalValues.BRIDGE_PHASE = $phaseMatches[0].Groups['Value'].Value
    $phase = [string]$literalValues.BRIDGE_PHASE
    if ($phase -ne 'discovery' -and $phase -ne 'production') {
        throw "Unsupported Dawnwalker bridge phase: $phase"
    }

    foreach ($name in @('BRIDGE_VERSION', 'CAPABILITIES')) {
        $pattern = '(?m)^\s*local\s+' + [regex]::Escape($name) + '\s*=\s*"(?<Value>[^"\r\n]*)"\s*$'
        $matches = [regex]::Matches($source, $pattern)
        if ($matches.Count -ne 1) {
            throw "Bridge source must declare exactly one literal local $name value."
        }
        $literalValues[$name] = $matches[0].Groups['Value'].Value
    }

    $version = [string]$literalValues.BRIDGE_VERSION
    if ($version -notmatch '^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$') {
        throw 'Dawnwalker bridge version is empty or contains unsupported characters.'
    }

    $capabilities = @()
    $capabilityCsv = [string]$literalValues.CAPABILITIES
    if (-not [string]::IsNullOrEmpty($capabilityCsv)) {
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($capability in $capabilityCsv.Split(',')) {
            if ($capability -notmatch '^[a-z][a-z0-9-]*:[a-z][a-z0-9-]*$') {
                throw "Bridge capability is not in canonical category:feature form: $capability"
            }
            if (-not $seen.Add($capability)) {
                throw "Bridge capability is duplicated: $capability"
            }
            $capabilities += $capability
        }
    }
    if ($phase -eq 'discovery' -and $capabilities.Count -ne 0) {
        throw 'A discovery bridge must compile with zero gameplay capabilities.'
    }
    if ($phase -eq 'production' -and $capabilities.Count -eq 0) {
        throw 'A production bridge must compile with at least one gameplay capability.'
    }
    if ($phase -eq 'production' -and $version.IndexOf('discovery', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw 'A production bridge version must not be labeled discovery.'
    }

    return [pscustomobject]@{
        phase = $phase
        bridgeVersion = $version
        gameplayCapabilities = @($capabilities)
    }
}

function Get-DawnwalkerIniValue {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key
    )

    $activeSection = ''
    $values = @()
    foreach ($line in Get-Content -LiteralPath $LiteralPath) {
        if ($line -match '^\s*\[(?<Section>[^\]]+)\]\s*$') {
            $activeSection = $Matches.Section
            continue
        }
        if ($activeSection -ieq $Section -and $line -match ('^\s*' + [regex]::Escape($Key) + '\s*=\s*(?<Value>[^;#]*?)\s*$')) {
            $values += $Matches.Value.Trim()
        }
    }
    if ($values.Count -ne 1) {
        throw "Expected exactly one [$Section] $Key value in $LiteralPath"
    }
    return [string]$values[0]
}

function Assert-DawnwalkerProductionHookProof {
    param(
        [Parameter(Mandatory)]$BridgeMetadata,
        [Parameter(Mandatory)]$Contract,
        [Parameter(Mandatory)][string]$SettingsLiteralPath,
        [Parameter(Mandatory)][string]$ProofLiteralPath
    )

    $hookEngineTickValue = Get-DawnwalkerIniValue -LiteralPath $SettingsLiteralPath -Section 'Hooks' -Key 'HookEngineTick'
    $activeSection = ''
    $enabledHooks = @()
    foreach ($line in Get-Content -LiteralPath $SettingsLiteralPath) {
        if ($line -match '^\s*\[(?<Section>[^\]]+)\]\s*$') {
            $activeSection = $Matches.Section
            continue
        }
        if ($activeSection -ieq 'Hooks' -and $line -match '^\s*(?<Key>Hook[A-Za-z0-9_]+)\s*=\s*(?<Value>[^;#]*?)\s*$') {
            $hookValue = $Matches.Value.Trim()
            if ($hookValue -ne '0' -and $hookValue -ne '1') {
                throw "Unsupported UE4SS hook value in the reviewed template: $($Matches.Key)=$hookValue"
            }
            if ($hookValue -eq '1') { $enabledHooks += $Matches.Key }
        }
    }
    if ($BridgeMetadata.phase -eq 'discovery') {
        if ($hookEngineTickValue -ne '0' -or $enabledHooks.Count -ne 0) {
            throw 'Discovery payload preparation requires every UE4SS Hook setting to remain disabled.'
        }
        return $hookEngineTickValue
    }

    if ($hookEngineTickValue -ne '1' -or $enabledHooks.Count -ne 1 -or $enabledHooks[0] -ne 'HookEngineTick') {
        throw 'Production payload preparation is blocked until the reviewed template sets only HookEngineTick=1.'
    }
    if (-not (Test-Path -LiteralPath $ProofLiteralPath -PathType Leaf)) {
        throw "Production payload preparation requires isolated HookEngineTick proof: $ProofLiteralPath"
    }
    $proof = Get-Content -LiteralPath $ProofLiteralPath -Raw | ConvertFrom-Json
    if ($proof.cyberfox1337x -ne 'function(dawnwalker_hook_engine_tick_live_proof)' -or
        $proof.schemaVersion -ne 1 -or $proof.status -ne 'passed' -or
        $proof.hook -ne 'HookEngineTick' -or [string]$proof.hookValue -ne '1' -or
        $proof.isolatedOffline -ne $true -or
        $proof.steamAppId -ne $Contract.steam.appId -or
        $proof.buildId -ne $Contract.steam.buildId -or
        $proof.executableSha256 -ne $Contract.executable.sha256 -or
        $proof.bridgeVersion -ne $BridgeMetadata.bridgeVersion) {
        throw 'Production HookEngineTick proof is invalid or targets a different pinned build/bridge.'
    }
    return $hookEngineTickValue
}

function Set-DawnwalkerPreparedBridgeModValue {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][ValidateSet('0', '1')][string]$Value
    )

    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $LiteralPath) { $lines.Add($line) }
    $matchCount = 0
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*DawnwalkerModBridge\s*:') {
            $lines[$index] = "DawnwalkerModBridge : $Value"
            $matchCount++
        }
    }
    if ($matchCount -ne 1) {
        throw 'The runtime mod-registry template must contain exactly one DawnwalkerModBridge entry.'
    }
    Set-Content -LiteralPath $LiteralPath -Value $lines -Encoding utf8
}

if (-not (Test-Path -LiteralPath $sourceContractPath -PathType Leaf)) {
    throw "Official Dawnwalker build contract is missing: $sourceContractPath"
}
$contract = Get-Content -LiteralPath $sourceContractPath -Raw | ConvertFrom-Json
if ($contract.cyberfox1337x -ne 'function(dawnwalker_official_build_contract)' -or $contract.schemaVersion -ne 1) {
    throw 'Official Dawnwalker build contract identity is invalid.'
}
if ($contract.steam.appId -ne $expectedAppId -or $contract.steam.buildId -ne $expectedBuildId -or
    $contract.executable.sha256 -ne $expectedExecutableSha256 -or $contract.ue4ss.release -ne $expectedRelease -or
    [long]$contract.ue4ss.archiveBytes -ne $expectedArchiveBytes -or $contract.ue4ss.archiveSha256 -ne $expectedArchiveSha256) {
    throw 'Official Dawnwalker build contract no longer matches the reviewed build/runtime identity.'
}

$bridgeMetadata = Read-DawnwalkerBridgeSourceMetadata -LiteralPath $bridgeSourcePath
if ($bridgeMetadata.phase -cne $PayloadPhase) {
    throw "The selected $PayloadPhase payload source declares phase '$($bridgeMetadata.phase)'."
}
$hookEngineTickValue = Assert-DawnwalkerProductionHookProof `
    -BridgeMetadata $bridgeMetadata `
    -Contract $contract `
    -SettingsLiteralPath $settingsTemplatePath `
    -ProofLiteralPath $hookEngineTickProofPath

$sourceArchivePath = Join-Path $analysisRoot ($contract.ue4ss.archiveRelativePath.Replace('/', '\'))
$archiveName = [IO.Path]::GetFileName($sourceArchivePath)
$packagedArchivePath = Join-Path $runtimeVendorRoot $archiveName

New-Item -ItemType Directory -Path $runtimeVendorRoot -Force | Out-Null
if (-not (Test-Path -LiteralPath $sourceArchivePath -PathType Leaf)) {
    Write-Output 'Downloading the pinned official experimental UE4SS zDEV archive...'
    Invoke-WebRequest -Uri $archiveDownloadUrl -OutFile $sourceArchivePath -UseBasicParsing
}
if ((Get-Item -LiteralPath $sourceArchivePath).Length -ne $expectedArchiveBytes -or
    (Get-Sha256 -LiteralPath $sourceArchivePath) -ne $expectedArchiveSha256) {
    throw 'The staged official experimental UE4SS archive failed its exact size/hash check.'
}
Copy-Item -LiteralPath $sourceArchivePath -Destination $packagedArchivePath -Force
if ((Get-Item -LiteralPath $packagedArchivePath).Length -ne $expectedArchiveBytes -or
    (Get-Sha256 -LiteralPath $packagedArchivePath) -ne $expectedArchiveSha256) {
    throw 'The packaged UE4SS archive failed its post-copy size/hash check.'
}

New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
Copy-Item -LiteralPath $sourceContractPath -Destination $runtimeContractPath -Force

$overlays = @(
    [ordered]@{
        source = $settingsTemplatePath
        packagePath = 'overrides/ue4ss/UE4SS-settings.ini'
        targetPath = 'ue4ss/UE4SS-settings.ini'
    },
    [ordered]@{
        source = $modsTemplatePath
        packagePath = 'overrides/ue4ss/Mods/mods.txt'
        targetPath = 'ue4ss/Mods/mods.txt'
    },
    [ordered]@{
        source = $bridgeSourcePath
        packagePath = 'overrides/ue4ss/Mods/DawnwalkerModBridge/Scripts/main.lua'
        targetPath = 'ue4ss/Mods/DawnwalkerModBridge/Scripts/main.lua'
    }
)

$resolvedRuntimeRoot = [IO.Path]::GetFullPath($runtimeRoot).TrimEnd('\')
if (Test-Path -LiteralPath $runtimeOverridesRoot -PathType Container) {
    $resolvedOverrides = [IO.Path]::GetFullPath($runtimeOverridesRoot)
    if (-not $resolvedOverrides.StartsWith($resolvedRuntimeRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clear an unsafe overlay path: $resolvedOverrides"
    }
    Remove-Item -LiteralPath $resolvedOverrides -Recurse -Force
}

foreach ($overlay in $overlays) {
    if (-not (Test-Path -LiteralPath $overlay.source -PathType Leaf)) {
        throw "Required runtime overlay is missing: $($overlay.source)"
    }
    [void](Assert-AllowedRuntimeTarget -RelativePath $overlay.targetPath)
    $packageRelative = Assert-SafeRelativePath -RelativePath $overlay.packagePath
    $packageDestination = [IO.Path]::GetFullPath((Join-Path $runtimeRoot $packageRelative))
    if (-not $packageDestination.StartsWith($resolvedRuntimeRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Overlay package path escapes runtime root: $($overlay.packagePath)"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $packageDestination) -Force | Out-Null
    Copy-Item -LiteralPath $overlay.source -Destination $packageDestination -Force
}

$preparedModsPath = Join-Path $runtimeRoot 'overrides\ue4ss\Mods\mods.txt'
$bridgeModValue = if ($bridgeMetadata.phase -eq 'production') { '1' } else { '0' }
Set-DawnwalkerPreparedBridgeModValue -LiteralPath $preparedModsPath -Value $bridgeModValue

Add-Type -AssemblyName System.IO.Compression.FileSystem
$requiredUEHelpers = Get-ArchiveEntryIdentity -ArchivePath $packagedArchivePath -RelativePath $requiredUEHelpersRelativePath
Assert-UEHelpersIdentity -Identity $requiredUEHelpers
$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$temporaryRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('dawnwalker-runtime-payload-' + [guid]::NewGuid().ToString('N'))))
if (-not $temporaryRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing unsafe staging directory: $temporaryRoot"
}

New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
try {
    $archive = [IO.Compression.ZipFile]::OpenRead($packagedArchivePath)
    try {
        foreach ($entry in $archive.Entries) {
            if ([string]::IsNullOrWhiteSpace($entry.FullName)) { continue }
            [void](Assert-AllowedRuntimeTarget -RelativePath $entry.FullName)
        }
    }
    finally {
        $archive.Dispose()
    }
    [IO.Compression.ZipFile]::ExtractToDirectory($packagedArchivePath, $temporaryRoot)

    foreach ($overlay in $overlays) {
        $source = Join-Path $runtimeRoot (Assert-SafeRelativePath -RelativePath $overlay.packagePath)
        $target = Join-Path $temporaryRoot (Assert-SafeRelativePath -RelativePath $overlay.targetPath)
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }

    $stagedUEHelpersPath = Join-Path $temporaryRoot (Assert-SafeRelativePath -RelativePath $requiredUEHelpersRelativePath)
    $stagedUEHelpers = [pscustomobject]@{
        relativePath = $requiredUEHelpersRelativePath
        bytes = if (Test-Path -LiteralPath $stagedUEHelpersPath -PathType Leaf) { [int64](Get-Item -LiteralPath $stagedUEHelpersPath).Length } else { -1 }
        sha256 = if (Test-Path -LiteralPath $stagedUEHelpersPath -PathType Leaf) { Get-Sha256 -LiteralPath $stagedUEHelpersPath } else { '' }
    }
    Assert-UEHelpersIdentity -Identity $stagedUEHelpers

    $payloadFiles = @(
        Get-ChildItem -LiteralPath $temporaryRoot -File -Recurse |
            Sort-Object FullName |
            ForEach-Object {
                $relativePath = $_.FullName.Substring($temporaryRoot.Length + 1).Replace('\', '/')
                [void](Assert-AllowedRuntimeTarget -RelativePath $relativePath)
                [ordered]@{
                    relativePath = $relativePath
                    bytes = $_.Length
                    sha256 = Get-Sha256 -LiteralPath $_.FullName
                }
            }
    )

    foreach ($requiredEntry in $contract.ue4ss.requiredEntries) {
        if ($payloadFiles.relativePath -notcontains $requiredEntry) {
            throw "Prepared payload is missing required nested runtime entry: $requiredEntry"
        }
    }
    foreach ($overlay in $overlays) {
        if ($payloadFiles.relativePath -notcontains $overlay.targetPath) {
            throw "Prepared payload is missing overlay target: $($overlay.targetPath)"
        }
    }
    $requiredUEHelpersPayloadEntries = @($payloadFiles | Where-Object { [string]$_.relativePath -ceq $requiredUEHelpersRelativePath })
    if ($requiredUEHelpersPayloadEntries.Count -ne 1 -or
        [int64]$requiredUEHelpersPayloadEntries[0].bytes -ne [int64]$requiredUEHelpersBytes -or
        [string]$requiredUEHelpersPayloadEntries[0].sha256 -cne $requiredUEHelpersSha256) {
        throw 'Prepared payload does not contain the exact pinned UEHelpers dependency.'
    }

    $packageManifest = Get-Content -LiteralPath (Join-Path $projectRoot 'package.json') -Raw | ConvertFrom-Json
    $requiredSettings = @(
        [ordered]@{ section = 'Overrides'; key = 'ControllingModsTxt'; value = 'ue4ss/Mods/mods.txt' },
        [ordered]@{ section = 'General'; key = 'EnableHotReloadSystem'; value = '0' },
        [ordered]@{ section = 'General'; key = 'EnableAutoReloadingLuaMods'; value = '0' },
        [ordered]@{ section = 'General'; key = 'UseCache'; value = '0' },
        [ordered]@{ section = 'General'; key = 'bUseUObjectArrayCache'; value = 'false' },
        [ordered]@{ section = 'General'; key = 'bForceGUObjectArrayForIteration'; value = 'true' },
        [ordered]@{ section = 'General'; key = 'DoEarlyScan'; value = '0' },
        [ordered]@{ section = 'EngineVersionOverride'; key = 'MajorVersion'; value = '5' },
        [ordered]@{ section = 'EngineVersionOverride'; key = 'MinorVersion'; value = '5' },
        [ordered]@{ section = 'ObjectDumper'; key = 'LoadAllAssetsBeforeDumpingObjects'; value = '0' },
        [ordered]@{ section = 'CXXHeaderGenerator'; key = 'LoadAllAssetsBeforeGeneratingCXXHeaders'; value = '0' },
        [ordered]@{ section = 'Debug'; key = 'ConsoleEnabled'; value = '1' },
        [ordered]@{ section = 'Debug'; key = 'GuiConsoleEnabled'; value = '0' },
        [ordered]@{ section = 'Debug'; key = 'GuiConsoleVisible'; value = '0' },
        [ordered]@{ section = 'Debug'; key = 'ToggleGuiKey'; value = 'O' },
        [ordered]@{ section = 'Hooks'; key = 'HookProcessInternal'; value = '0' },
        [ordered]@{ section = 'Hooks'; key = 'HookProcessLocalScriptFunction'; value = '0' },
        [ordered]@{ section = 'Hooks'; key = 'HookInitGameState'; value = '0' },
        [ordered]@{ section = 'Hooks'; key = 'HookLoadMap'; value = '0' },
        [ordered]@{ section = 'Hooks'; key = 'HookCallFunctionByNameWithArguments'; value = '0' },
        [ordered]@{ section = 'Hooks'; key = 'HookBeginPlay'; value = '0' },
        [ordered]@{ section = 'Hooks'; key = 'HookEndPlay'; value = '0' },
        [ordered]@{ section = 'Hooks'; key = 'HookLocalPlayerExec'; value = '0' },
        [ordered]@{ section = 'Hooks'; key = 'HookAActorTick'; value = '0' },
        [ordered]@{ section = 'Hooks'; key = 'HookEngineTick'; value = $hookEngineTickValue },
        [ordered]@{ section = 'Hooks'; key = 'HookGameViewportClientTick'; value = '0' },
        [ordered]@{ section = 'Hooks'; key = 'HookUObjectProcessEvent'; value = '0' },
        [ordered]@{ section = 'Hooks'; key = 'HookProcessConsoleExec'; value = '0' },
        [ordered]@{ section = 'Hooks'; key = 'HookUStructLink'; value = '0' },
        [ordered]@{ section = 'CrashDump'; key = 'EnableDumping'; value = '0' },
        [ordered]@{ section = 'CrashDump'; key = 'FullMemoryDump'; value = '0' }
    )
    $requiredModRegistry = @(
        'KismetDebuggerMod', 'EventViewerMod', 'CheatManagerEnablerMod', 'ActorDumperMod',
        'ConsoleCommandsMod', 'ConsoleEnablerMod', 'SplitScreenMod', 'LineTraceMod',
        'BPML_GenericFunctions', 'BPModLoaderMod', 'jsbLuaProfilerMod'
    ) | ForEach-Object { [ordered]@{ name = $_; value = '0' } }
    $requiredModRegistry += [ordered]@{ name = 'DawnwalkerModBridge'; value = $bridgeModValue }
    $requiredModRegistry += [ordered]@{ name = 'Keybinds'; value = '0' }

    $manifest = [ordered]@{
        cyberfox1337x = 'function(dawnwalker_runtime_payload_manifest)'
        schemaVersion = 1
        applicationVersion = [string]$packageManifest.version
        phase = $bridgeMetadata.phase
        bridgeVersion = $bridgeMetadata.bridgeVersion
        gameplayCapabilities = @($bridgeMetadata.gameplayCapabilities)
        steamAppId = $contract.steam.appId
        steamBuildId = $contract.steam.buildId
        shippingExecutableSha256 = $contract.executable.sha256
        officialBuildContract = [ordered]@{
            packagePath = 'official-build.json'
            bytes = (Get-Item -LiteralPath $runtimeContractPath).Length
            sha256 = Get-Sha256 -LiteralPath $runtimeContractPath
        }
        ue4ssRelease = $contract.ue4ss.release
        ue4ssArchive = [ordered]@{
            packagePath = 'vendor/' + $archiveName
            bytes = $expectedArchiveBytes
            sha256 = $expectedArchiveSha256
            source = $contract.ue4ss.source
            channel = $contract.ue4ss.channel
            license = 'MIT'
        }
        requiredRuntimeDependencies = @(
            [ordered]@{
                relativePath = $requiredUEHelpersRelativePath
                bytes = $requiredUEHelpersBytes
                sha256 = $requiredUEHelpersSha256
                source = 'pinned-ue4ss-archive'
            }
        )
        allowedWriteTargetsRelativeToWin64 = @($contract.safety.allowedWriteTargetsRelativeToWin64)
        conflictingProxyNames = @($contract.safety.conflictingProxyNames)
        requiredSettings = $requiredSettings
        requiredModRegistry = @($requiredModRegistry)
        overlays = @(
            $overlays | ForEach-Object {
                $packagedPath = Join-Path $runtimeRoot (Assert-SafeRelativePath -RelativePath $_.packagePath)
                [ordered]@{
                    packagePath = $_.packagePath
                    targetPath = $_.targetPath
                    sha256 = Get-Sha256 -LiteralPath $packagedPath
                }
            }
        )
        payloadFiles = $payloadFiles
    }

    $temporaryManifest = Join-Path $runtimeRoot ('payload-manifest.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporaryManifest -Encoding utf8
    Move-Item -LiteralPath $temporaryManifest -Destination $manifestPath -Force
    Write-Output "Prepared $($payloadFiles.Count) verified nested runtime files at $manifestPath"
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
        $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
        if ($resolvedTemporaryRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
        }
    }
}
