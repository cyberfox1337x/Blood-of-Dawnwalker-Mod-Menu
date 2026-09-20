[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Status', 'VerifyPayload', 'Install', 'Repair', 'Uninstall')]
    [string]$Action,

    [string]$PayloadRoot,

    [string]$ApplicationVersion = '0.1.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory)][string]$ModuleName)
}

cyberfox1337x -ModuleName 'dawnwalker_runtime_installer'

if ([string]::IsNullOrWhiteSpace($PayloadRoot)) {
    $packagedManifest = Join-Path $PSScriptRoot 'payload-manifest.json'
    $workspaceRuntime = Join-Path $PSScriptRoot 'runtime'
    $PayloadRoot = if (Test-Path -LiteralPath $packagedManifest -PathType Leaf) { $PSScriptRoot } else { $workspaceRuntime }
}

$script:ExpectedAppId = '3751260'
$script:ExpectedBuildId = '25107392'
$script:ExpectedInstallDirectory = 'The Blood of Dawnwalker'
$script:ExpectedRelativeExecutable = 'Dawnwalker\Binaries\Win64\Dawnwalker.exe'
$script:ExpectedWin64Suffix = 'Dawnwalker\Binaries\Win64'
$script:ExpectedExecutableBytes = 176998264
$script:ExpectedExecutableSha256 = '45B7C2949F519ED3E45F7FBDB7127A03373FE44B34ABB58E3C987C5054E2409E'
$script:ExpectedSignerSubject = 'Rebel Wolves'
$script:ExpectedUe4ssRelease = 'v3.0.1-1111-g97b7e501'
$script:ExpectedArchiveBytes = 44605660
$script:ExpectedArchiveSha256 = '8C2E28BB1479CBEA7BF5A3C16E027580D9E71D21606971B5BD103A20BA94C617'
$script:RequiredUEHelpersRelativePath = 'ue4ss/Mods/shared/UEHelpers/UEHelpers.lua'
$script:RequiredUEHelpersBytes = 10237
$script:RequiredUEHelpersSha256 = '7476F02EEF0C87BFEAB169F2FFE2E704363FAEAAE4BF9F1BDA574B1E34F4A0E9'
$script:DefaultStateRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'Cyberfox1337x\BloodOfDawnwalkerModMenu\Runtime'))
$script:StateRoot = $script:DefaultStateRoot
$script:StatePath = Join-Path $script:StateRoot 'install-state.json'
$script:BaselineRoot = Join-Path $script:StateRoot 'baseline'

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

function Get-DawnwalkerValidatedCapabilities {
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Values,
        [Parameter(Mandatory)][string]$Context
    )

    $capabilities = @()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($rawValue in $Values) {
        $capability = [string]$rawValue
        if ($capability -notmatch '^[a-z][a-z0-9-]*:[a-z][a-z0-9-]*$') {
            throw "$Context contains a non-canonical gameplay capability: $capability"
        }
        if (-not $seen.Add($capability)) {
            throw "$Context contains a duplicate gameplay capability: $capability"
        }
        $capabilities += $capability
    }
    return $capabilities
}

function Assert-DawnwalkerPhaseCapabilityContract {
    param(
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$BridgeVersion,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][string[]]$Capabilities,
        [Parameter(Mandatory)][string]$Context
    )

    if ($Phase -ne 'discovery' -and $Phase -ne 'production') {
        throw "$Context has an unsupported bridge phase: $Phase"
    }
    if ($BridgeVersion -notmatch '^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$') {
        throw "$Context has an invalid bridge version."
    }
    if ($Phase -eq 'discovery' -and $Capabilities.Count -ne 0) {
        throw "$Context cannot advertise gameplay capabilities in discovery phase."
    }
    if ($Phase -eq 'production' -and $Capabilities.Count -eq 0) {
        throw "$Context must advertise at least one compiled gameplay capability in production phase."
    }
    if ($Phase -eq 'production' -and $BridgeVersion.IndexOf('discovery', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "$Context cannot use a discovery-labeled bridge version in production phase."
    }
}

function Read-DawnwalkerBridgeSourceMetadata {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [switch]$AllowLegacyDiscovery
    )

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Dawnwalker bridge overlay is missing: $LiteralPath"
    }
    $source = Get-Content -LiteralPath $LiteralPath -Raw
    $literalValues = [ordered]@{}
    foreach ($name in @('BRIDGE_VERSION', 'CAPABILITIES')) {
        $pattern = '(?m)^\s*local\s+' + [regex]::Escape($name) + '\s*=\s*"(?<Value>[^"\r\n]*)"\s*$'
        $matches = [regex]::Matches($source, $pattern)
        if ($matches.Count -ne 1) {
            throw "Bridge overlay must declare exactly one literal local $name value."
        }
        $literalValues[$name] = $matches[0].Groups['Value'].Value
    }

    $phaseMatches = [regex]::Matches($source, '(?m)^\s*local\s+BRIDGE_PHASE\s*=\s*"(?<Value>[^"\r\n]*)"\s*$')
    $phase = $null
    $hasExplicitPhase = $phaseMatches.Count -eq 1
    if ($hasExplicitPhase) {
        $phase = $phaseMatches[0].Groups['Value'].Value
    }
    elseif ($phaseMatches.Count -eq 0 -and $AllowLegacyDiscovery -and
        [string]$literalValues.CAPABILITIES -eq '' -and
        ([string]$literalValues.BRIDGE_VERSION).IndexOf('discovery', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $phase = 'discovery'
    }
    else {
        throw 'Bridge overlay must declare exactly one literal local BRIDGE_PHASE value.'
    }

    $capabilityValues = if ([string]::IsNullOrEmpty([string]$literalValues.CAPABILITIES)) {
        @()
    }
    else {
        @(([string]$literalValues.CAPABILITIES).Split(','))
    }
    $capabilities = @(Get-DawnwalkerValidatedCapabilities -Values $capabilityValues -Context 'Bridge overlay')
    $version = [string]$literalValues.BRIDGE_VERSION
    Assert-DawnwalkerPhaseCapabilityContract -Phase $phase -BridgeVersion $version -Capabilities $capabilities -Context 'Bridge overlay'

    return [pscustomobject]@{
        phase = $phase
        bridgeVersion = $version
        gameplayCapabilities = @($capabilities)
        hasExplicitPhase = $hasExplicitPhase
    }
}

function Get-SafeChildPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $normalized = $RelativePath.Replace('/', '\').TrimStart('\').TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($normalized) -or [IO.Path]::IsPathRooted($normalized) -or
        $normalized -match '(^|\\)\.\.(\\|$)' -or $normalized.Contains(':')) {
        throw "Unsafe relative path: $RelativePath"
    }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $childPath = [IO.Path]::GetFullPath((Join-Path $rootPath $normalized))
    if (-not $childPath.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes its allowed root: $RelativePath"
    }
    return $childPath
}

function Assert-AllowedRuntimePath {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)]$Contract
    )

    $normalized = $RelativePath.Replace('\', '/').Trim('/')
    if ([string]::IsNullOrWhiteSpace($normalized) -or [IO.Path]::IsPathRooted($RelativePath) -or
        $normalized -match '(^|/)\.\.(/|$)' -or $normalized.Contains(':')) {
        throw "Unsafe runtime target: $RelativePath"
    }
    foreach ($forbidden in @($Contract.safety.forbiddenWriteRootFragments)) {
        if ($normalized.IndexOf(([string]$forbidden).Replace('\', '/'), [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "Runtime target enters a forbidden game-content root: $RelativePath"
        }
    }
    foreach ($allowed in @($Contract.safety.allowedWriteTargetsRelativeToWin64)) {
        $allowedNormalized = ([string]$allowed).Replace('\', '/').Trim('/')
        if ($normalized.Equals($allowedNormalized, [StringComparison]::OrdinalIgnoreCase) -or
            $normalized.StartsWith($allowedNormalized + '/', [StringComparison]::OrdinalIgnoreCase)) {
            return $normalized
        }
    }
    throw "Runtime target is outside the contract allowlist: $RelativePath"
}

function Read-ManifestValue {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Name
    )

    $match = [regex]::Match($Text, '"' + [regex]::Escape($Name) + '"\s+"(?<Value>[^"]*)"')
    if (-not $match.Success) { throw "Steam manifest is missing '$Name'." }
    return $match.Groups['Value'].Value
}

function Assert-ContractIdentity {
    param([Parameter(Mandatory)]$Contract)

    if ($Contract.cyberfox1337x -ne 'function(dawnwalker_official_build_contract)' -or $Contract.schemaVersion -ne 1) {
        throw 'Official Dawnwalker build contract identity is invalid.'
    }
    if ($Contract.steam.appId -ne $script:ExpectedAppId -or
        $Contract.steam.buildId -ne $script:ExpectedBuildId -or
        $Contract.steam.installDirName -ne $script:ExpectedInstallDirectory -or
        $Contract.executable.relativePath.Replace('/', '\') -ne $script:ExpectedRelativeExecutable -or
        [long]$Contract.executable.bytes -ne $script:ExpectedExecutableBytes -or
        $Contract.executable.sha256 -ne $script:ExpectedExecutableSha256 -or
        $Contract.ue4ss.release -ne $script:ExpectedUe4ssRelease -or
        [long]$Contract.ue4ss.archiveBytes -ne $script:ExpectedArchiveBytes -or
        $Contract.ue4ss.archiveSha256 -ne $script:ExpectedArchiveSha256) {
        throw 'Official Dawnwalker build contract does not match the reviewed identity.'
    }
    if (@($Contract.knownCurrentState.limitations).Count -eq 0) {
        throw 'Official Dawnwalker build contract is missing its experimental-runtime limitations.'
    }
}

function Get-PayloadFileEntry {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $normalized = $RelativePath.Replace('\', '/')
    $entry = @($Manifest.payloadFiles | Where-Object { $_.relativePath -eq $normalized })
    if ($entry.Count -ne 1) { throw "Payload manifest entry is missing or duplicated: $normalized" }
    return $entry[0]
}

function Read-PayloadMetadata {
    param(
        [Parameter(Mandatory)][string]$Root,
        [switch]$SkipArchiveHash
    )

    $payloadRootPath = [IO.Path]::GetFullPath($Root)
    $manifestPath = Join-Path $payloadRootPath 'payload-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Runtime payload manifest is missing: $manifestPath"
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.cyberfox1337x -ne 'function(dawnwalker_runtime_payload_manifest)' -or $manifest.schemaVersion -ne 1) {
        throw 'Runtime payload manifest identity is invalid.'
    }
    $manifestCapabilities = @(Get-DawnwalkerValidatedCapabilities -Values @($manifest.gameplayCapabilities) -Context 'Runtime payload manifest')
    Assert-DawnwalkerPhaseCapabilityContract `
        -Phase ([string]$manifest.phase) `
        -BridgeVersion ([string]$manifest.bridgeVersion) `
        -Capabilities $manifestCapabilities `
        -Context 'Runtime payload manifest'

    $contractEntry = $manifest.officialBuildContract
    $contractPath = Get-SafeChildPath -Root $payloadRootPath -RelativePath $contractEntry.packagePath
    if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf) -or
        (Get-Item -LiteralPath $contractPath).Length -ne [long]$contractEntry.bytes -or
        (Get-Sha256 -LiteralPath $contractPath) -ne $contractEntry.sha256) {
        throw 'Packaged official-build contract failed its exact size/hash check.'
    }
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    Assert-ContractIdentity -Contract $contract
    if ($manifest.steamAppId -ne $contract.steam.appId -or
        $manifest.steamBuildId -ne $contract.steam.buildId -or
        $manifest.shippingExecutableSha256 -ne $contract.executable.sha256 -or
        $manifest.ue4ssRelease -ne $contract.ue4ss.release) {
        throw 'Runtime payload manifest targets a different game/runtime contract.'
    }

    $archivePath = Get-SafeChildPath -Root $payloadRootPath -RelativePath $manifest.ue4ssArchive.packagePath
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        throw "Official UE4SS archive is missing: $archivePath"
    }
    if ((Get-Item -LiteralPath $archivePath).Length -ne [long]$manifest.ue4ssArchive.bytes -or
        [long]$manifest.ue4ssArchive.bytes -ne [long]$contract.ue4ss.archiveBytes -or
        $manifest.ue4ssArchive.sha256 -ne $contract.ue4ss.archiveSha256) {
        throw 'Official UE4SS archive metadata does not match the build contract.'
    }
    if (-not $SkipArchiveHash -and (Get-Sha256 -LiteralPath $archivePath) -ne $manifest.ue4ssArchive.sha256) {
        throw 'Official UE4SS archive failed its exact SHA-256 check.'
    }

    $seenPayloadPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @($manifest.payloadFiles)) {
        $normalized = Assert-AllowedRuntimePath -RelativePath $file.relativePath -Contract $contract
        if (-not $seenPayloadPaths.Add($normalized)) { throw "Duplicate runtime payload path: $normalized" }
    }
    if ($manifest.PSObject.Properties.Name -notcontains 'requiredRuntimeDependencies') {
        throw 'Runtime payload manifest is missing its pinned runtime dependency contract.'
    }
    $requiredRuntimeDependencies = @($manifest.requiredRuntimeDependencies)
    if ($requiredRuntimeDependencies.Count -ne 1) {
        throw "Runtime payload must declare exactly one pinned runtime dependency; found $($requiredRuntimeDependencies.Count)."
    }
    $requiredUEHelpers = $requiredRuntimeDependencies[0]
    $normalizedUEHelpersPath = Assert-AllowedRuntimePath -RelativePath ([string]$requiredUEHelpers.relativePath) -Contract $contract
    if ($normalizedUEHelpersPath -cne $script:RequiredUEHelpersRelativePath -or
        [int64]$requiredUEHelpers.bytes -ne [int64]$script:RequiredUEHelpersBytes -or
        [string]$requiredUEHelpers.sha256 -cne $script:RequiredUEHelpersSha256 -or
        [string]$requiredUEHelpers.source -cne 'pinned-ue4ss-archive') {
        throw 'Runtime payload UEHelpers dependency does not match the exact pinned path/size/hash/source contract.'
    }
    $requiredUEHelpersPayload = Get-PayloadFileEntry -Manifest $manifest -RelativePath $script:RequiredUEHelpersRelativePath
    if ([int64]$requiredUEHelpersPayload.bytes -ne [int64]$script:RequiredUEHelpersBytes -or
        [string]$requiredUEHelpersPayload.sha256 -cne $script:RequiredUEHelpersSha256) {
        throw 'Runtime payload UEHelpers file metadata disagrees with its pinned dependency contract.'
    }
    foreach ($overlay in @($manifest.overlays)) {
        [void](Assert-AllowedRuntimePath -RelativePath $overlay.targetPath -Contract $contract)
        $overlayPath = Get-SafeChildPath -Root $payloadRootPath -RelativePath $overlay.packagePath
        if (-not (Test-Path -LiteralPath $overlayPath -PathType Leaf) -or
            (Get-Sha256 -LiteralPath $overlayPath) -ne $overlay.sha256) {
            throw "Runtime overlay failed validation: $($overlay.packagePath)"
        }
    }

    $bridgeTargetPath = 'ue4ss/Mods/DawnwalkerModBridge/Scripts/main.lua'
    $bridgeOverlays = @($manifest.overlays | Where-Object { ([string]$_.targetPath).Replace('\', '/') -eq $bridgeTargetPath })
    if ($bridgeOverlays.Count -ne 1) {
        throw 'Runtime payload must contain exactly one Dawnwalker bridge overlay.'
    }
    $bridgeOverlayPath = Get-SafeChildPath -Root $payloadRootPath -RelativePath $bridgeOverlays[0].packagePath
    $bridgeMetadata = Read-DawnwalkerBridgeSourceMetadata -LiteralPath $bridgeOverlayPath -AllowLegacyDiscovery
    if ($bridgeMetadata.phase -ne [string]$manifest.phase -or
        $bridgeMetadata.bridgeVersion -ne [string]$manifest.bridgeVersion -or
        (@($bridgeMetadata.gameplayCapabilities) -join "`n") -ne ($manifestCapabilities -join "`n")) {
        throw 'Runtime payload manifest metadata does not exactly match its compiled Dawnwalker bridge overlay.'
    }

    $requiredMods = @($manifest.requiredModRegistry)
    $seenModNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $bridgeModEntries = @()
    foreach ($requiredMod in $requiredMods) {
        $modName = [string]$requiredMod.name
        $modValue = [string]$requiredMod.value
        if ($modName -notmatch '^[A-Za-z0-9_]+$' -or ($modValue -ne '0' -and $modValue -ne '1')) {
            throw "Runtime payload has an invalid required mod-registry entry: $modName"
        }
        if (-not $seenModNames.Add($modName)) {
            throw "Runtime payload has a duplicate required mod-registry entry: $modName"
        }
        if ($modName -ieq 'DawnwalkerModBridge') { $bridgeModEntries += $requiredMod }
        elseif ($modValue -eq '1') { throw "Runtime payload attempts to enable an unapproved UE4SS mod: $modName" }
    }
    $expectedBridgeModValue = if ($manifest.phase -eq 'production') { '1' } else { '0' }
    if ($bridgeModEntries.Count -ne 1 -or [string]$bridgeModEntries[0].value -ne $expectedBridgeModValue) {
        throw "DawnwalkerModBridge must be set to $expectedBridgeModValue for the $($manifest.phase) payload phase."
    }

    $modsTargetPath = 'ue4ss/Mods/mods.txt'
    $modsOverlays = @($manifest.overlays | Where-Object { ([string]$_.targetPath).Replace('\', '/') -eq $modsTargetPath })
    if ($modsOverlays.Count -ne 1) {
        throw 'Runtime payload must contain exactly one UE4SS mod-registry overlay.'
    }
    $modsOverlayPath = Get-SafeChildPath -Root $payloadRootPath -RelativePath $modsOverlays[0].packagePath
    $overlayRegistry = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in Get-Content -LiteralPath $modsOverlayPath) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith(';') -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -notmatch '^(?<Name>[A-Za-z0-9_]+)\s*:\s*(?<Value>[01])$') {
            throw "Runtime mod-registry overlay contains an invalid entry: $trimmed"
        }
        if ($overlayRegistry.ContainsKey($Matches.Name)) {
            throw "Runtime mod-registry overlay duplicates an entry: $($Matches.Name)"
        }
        $overlayRegistry.Add($Matches.Name, $Matches.Value)
    }
    foreach ($requiredMod in $requiredMods) {
        if (-not $overlayRegistry.ContainsKey([string]$requiredMod.name) -or
            $overlayRegistry[[string]$requiredMod.name] -ne [string]$requiredMod.value) {
            throw "Runtime mod-registry overlay disagrees with required metadata for $($requiredMod.name)."
        }
    }
    foreach ($entry in $overlayRegistry.GetEnumerator()) {
        if ($entry.Value -eq '1' -and $entry.Key -ine 'DawnwalkerModBridge') {
            throw "Runtime mod-registry overlay enables an unapproved UE4SS mod: $($entry.Key)"
        }
    }

    $requiredSettings = @($manifest.requiredSettings)
    $seenSettings = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $hookEngineTickEntries = @()
    foreach ($setting in $requiredSettings) {
        $section = [string]$setting.section
        $key = [string]$setting.key
        $value = [string]$setting.value
        if ([string]::IsNullOrWhiteSpace($section) -or [string]::IsNullOrWhiteSpace($key) -or
            -not $seenSettings.Add("$section`n$key")) {
            throw "Runtime payload has an invalid or duplicate required setting: [$section] $key"
        }
        if ($section -ieq 'Hooks') {
            if ($value -ne '0' -and $value -ne '1') {
                throw "Runtime payload has an invalid hook value: $key=$value"
            }
            if ($key -ieq 'HookEngineTick') { $hookEngineTickEntries += $setting }
            elseif ($value -eq '1') { throw "Runtime payload enables an unapproved UE4SS hook: $key" }
        }
    }
    $expectedHookEngineTickValue = if ($manifest.phase -eq 'production') { '1' } else { '0' }
    if ($hookEngineTickEntries.Count -ne 1 -or [string]$hookEngineTickEntries[0].value -ne $expectedHookEngineTickValue) {
        throw "HookEngineTick must be set to $expectedHookEngineTickValue for the $($manifest.phase) payload phase."
    }

    $settingsTargetPath = 'ue4ss/UE4SS-settings.ini'
    $settingsOverlays = @($manifest.overlays | Where-Object { ([string]$_.targetPath).Replace('\', '/') -eq $settingsTargetPath })
    if ($settingsOverlays.Count -ne 1) {
        throw 'Runtime payload must contain exactly one UE4SS settings overlay.'
    }
    $settingsOverlayPath = Get-SafeChildPath -Root $payloadRootPath -RelativePath $settingsOverlays[0].packagePath
    $overlayHookEngineTick = Get-IniValueState -LiteralPath $settingsOverlayPath -Section 'Hooks' -Key 'HookEngineTick'
    if (-not $overlayHookEngineTick.present -or [string]$overlayHookEngineTick.value -ne $expectedHookEngineTickValue) {
        throw "Runtime settings overlay must set HookEngineTick=$expectedHookEngineTickValue for the $($manifest.phase) payload phase."
    }

    return [pscustomobject]@{
        root = $payloadRootPath
        manifestPath = $manifestPath
        manifest = $manifest
        contractPath = $contractPath
        contract = $contract
        archivePath = $archivePath
    }
}

function New-ValidatedPayloadStaging {
    param([Parameter(Mandatory)][string]$Root)

    $metadata = Read-PayloadMetadata -Root $Root
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $stagingRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('dawnwalker-runtime-install-' + [guid]::NewGuid().ToString('N'))))
    if (-not $stagingRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing unsafe payload staging path: $stagingRoot"
    }
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

    try {
        $archive = [IO.Compression.ZipFile]::OpenRead($metadata.archivePath)
        try {
            foreach ($entry in $archive.Entries) {
                if ([string]::IsNullOrWhiteSpace($entry.FullName)) { continue }
                [void](Get-SafeChildPath -Root $stagingRoot -RelativePath $entry.FullName)
                [void](Assert-AllowedRuntimePath -RelativePath $entry.FullName -Contract $metadata.contract)
            }
        }
        finally {
            $archive.Dispose()
        }
        [IO.Compression.ZipFile]::ExtractToDirectory($metadata.archivePath, $stagingRoot)

        foreach ($overlay in @($metadata.manifest.overlays)) {
            $sourcePath = Get-SafeChildPath -Root $metadata.root -RelativePath $overlay.packagePath
            $targetPath = Get-SafeChildPath -Root $stagingRoot -RelativePath $overlay.targetPath
            New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
            Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
        }

        $actualFiles = @(
            Get-ChildItem -LiteralPath $stagingRoot -File -Recurse |
                ForEach-Object { $_.FullName.Substring($stagingRoot.Length + 1).Replace('\', '/') } |
                Sort-Object
        )
        $expectedFiles = @($metadata.manifest.payloadFiles.relativePath | Sort-Object)
        if (($actualFiles -join "`n") -ne ($expectedFiles -join "`n")) {
            throw 'Prepared runtime file list does not match the payload manifest.'
        }
        foreach ($file in @($metadata.manifest.payloadFiles)) {
            $filePath = Get-SafeChildPath -Root $stagingRoot -RelativePath $file.relativePath
            if ((Get-Item -LiteralPath $filePath).Length -ne [long]$file.bytes -or
                (Get-Sha256 -LiteralPath $filePath) -ne $file.sha256) {
                throw "Prepared runtime file failed validation: $($file.relativePath)"
            }
        }
        $stagedUEHelpersPath = Get-SafeChildPath -Root $stagingRoot -RelativePath $script:RequiredUEHelpersRelativePath
        if ((Get-Item -LiteralPath $stagedUEHelpersPath).Length -ne [long]$script:RequiredUEHelpersBytes -or
            (Get-Sha256 -LiteralPath $stagedUEHelpersPath) -ne $script:RequiredUEHelpersSha256) {
            throw 'Prepared runtime UEHelpers dependency failed its exact pinned size/hash check.'
        }
        foreach ($requiredEntry in @($metadata.contract.ue4ss.requiredEntries)) {
            [void](Get-PayloadFileEntry -Manifest $metadata.manifest -RelativePath $requiredEntry)
        }
        return [pscustomobject]@{
            root = $stagingRoot
            manifest = $metadata.manifest
            contract = $metadata.contract
            metadata = $metadata
        }
    }
    catch {
        if (Test-Path -LiteralPath $stagingRoot -PathType Container) {
            Remove-Item -LiteralPath $stagingRoot -Recurse -Force
        }
        throw
    }
}

function Get-SteamRoots {
    $roots = [Collections.Generic.List[string]]::new()
    foreach ($entry in @(
        @{ Path = 'HKCU:\Software\Valve\Steam'; Name = 'SteamPath' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'; Name = 'InstallPath' },
        @{ Path = 'HKLM:\SOFTWARE\Valve\Steam'; Name = 'InstallPath' }
    )) {
        try {
            $rawPath = (Get-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -ErrorAction Stop).($entry.Name)
            if ($rawPath) { $roots.Add([IO.Path]::GetFullPath(([string]$rawPath).Replace('/', '\'))) }
        }
        catch [Management.Automation.ItemNotFoundException] { continue }
        catch [Management.Automation.PSArgumentException] { continue }
    }
    return $roots | Sort-Object -Unique
}

function Get-SteamLibraries {
    $libraries = [Collections.Generic.List[string]]::new()
    foreach ($steamRoot in Get-SteamRoots) {
        if (Test-Path -LiteralPath $steamRoot -PathType Container) { $libraries.Add($steamRoot) }
        $libraryFile = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) { continue }
        foreach ($line in Get-Content -LiteralPath $libraryFile) {
            if ($line -match '^\s*"path"\s+"(?<Path>.+)"\s*$') {
                $libraries.Add([IO.Path]::GetFullPath($Matches.Path.Replace('\\', '\')))
            }
        }
    }
    return $libraries | Sort-Object -Unique
}

function Get-OfficialGameInstall {
    param(
        [Parameter(Mandatory)]$Contract,
        [switch]$RequireExactBuild
    )

    $manifestPaths = @(
        Get-SteamLibraries |
            ForEach-Object { Join-Path $_ "steamapps\appmanifest_$($Contract.steam.appId).acf" } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    )
    if ($manifestPaths.Count -ne 1) {
        throw "Expected exactly one official Steam manifest for App ID $($Contract.steam.appId); found $($manifestPaths.Count)."
    }

    $manifestPath = [IO.Path]::GetFullPath($manifestPaths[0])
    $manifestText = Get-Content -LiteralPath $manifestPath -Raw
    $appId = Read-ManifestValue -Text $manifestText -Name 'appid'
    $buildId = Read-ManifestValue -Text $manifestText -Name 'buildid'
    $stateFlags = [int](Read-ManifestValue -Text $manifestText -Name 'StateFlags')
    $installDirectory = Read-ManifestValue -Text $manifestText -Name 'installdir'
    if ($appId -ne $Contract.steam.appId -or ($stateFlags -band 4) -eq 0) {
        throw "Official Steam identity mismatch. App=$appId StateFlags=$stateFlags."
    }
    if ($installDirectory -ne $Contract.steam.installDirName) {
        throw "Unexpected official install directory '$installDirectory'."
    }
    if ($RequireExactBuild -and $buildId -ne $Contract.steam.buildId) {
        throw "Unsupported Steam build $buildId. This installer requires build $($Contract.steam.buildId)."
    }

    $steamAppsRoot = Split-Path -Parent $manifestPath
    $installPath = [IO.Path]::GetFullPath((Join-Path $steamAppsRoot "common\$installDirectory"))
    $executablePath = [IO.Path]::GetFullPath((Join-Path $installPath $Contract.executable.relativePath.Replace('/', '\')))
    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
        throw "Manifest-derived shipping executable is missing: $executablePath"
    }
    $executableBytes = (Get-Item -LiteralPath $executablePath).Length
    $executableSha256 = Get-Sha256 -LiteralPath $executablePath
    if ($RequireExactBuild -and ($executableBytes -ne [long]$Contract.executable.bytes -or
        $executableSha256 -ne $Contract.executable.sha256)) {
        throw "Unsupported shipping executable identity: bytes=$executableBytes sha256=$executableSha256"
    }
    if ($RequireExactBuild) {
        $signature = Get-AuthenticodeSignature -LiteralPath $executablePath
        $subject = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
        if ([string]$signature.Status -ne $Contract.executable.signatureStatus -or
            $subject.IndexOf([string]$Contract.executable.signerSubjectContains, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            throw 'Shipping executable Authenticode identity is not the reviewed Rebel Wolves signature.'
        }
    }

    return [pscustomobject]@{
        manifestPath = $manifestPath
        buildId = $buildId
        installPath = $installPath
        executablePath = $executablePath
        executableBytes = $executableBytes
        executableSha256 = $executableSha256
        win64Path = [IO.Path]::GetFullPath((Join-Path $installPath $script:ExpectedWin64Suffix))
    }
}

function Assert-GameInstallIdentity {
    param(
        [Parameter(Mandatory)]$GameInstall,
        [Parameter(Mandatory)]$Contract
    )

    if ([string]$GameInstall.buildId -ne [string]$Contract.steam.buildId -or
        [string]$GameInstall.executableSha256 -ne [string]$Contract.executable.sha256) {
        throw 'The selected game installation does not match the exact supported build.'
    }
}

function Test-GameRunning {
    param([Parameter(Mandatory)]$Contract)

    foreach ($processName in @($Contract.safety.processNames)) {
        if (@(Get-Process -Name ([string]$processName) -ErrorAction SilentlyContinue).Count -gt 0) { return $true }
    }
    return $false
}

function Assert-GameStopped {
    param([Parameter(Mandatory)]$Contract)

    if (Test-GameRunning -Contract $Contract) {
        throw 'Close The Blood of Dawnwalker before installing, repairing, or uninstalling the runtime.'
    }
}

function Assert-EligibleInstall {
    param(
        [Parameter(Mandatory)]$GameInstall,
        [Parameter(Mandatory)]$Contract
    )

    $repackMarkers = @($Contract.safety.repackMarkers | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $protectionMarkers = @($Contract.safety.protectionMarkers | ForEach-Object { ([string]$_).ToLowerInvariant() })
    foreach ($file in Get-ChildItem -LiteralPath $GameInstall.installPath -File -Recurse -Force -ErrorAction SilentlyContinue) {
        $candidate = $file.FullName.ToLowerInvariant()
        foreach ($marker in $repackMarkers) {
            if ($candidate.Contains($marker)) { throw 'A repack or Steam-emulation marker was found. Installation is refused.' }
        }
        foreach ($marker in $protectionMarkers) {
            if ($candidate.Contains($marker)) { throw 'An unsupported protection component was found. Installation is refused.' }
        }
    }
}

function Set-IniValue {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value
    )

    $sectionStart = -1
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match '^\s*\[(?<Section>[^\]]+)\]\s*$' -and $Matches.Section -ieq $Section) {
            $sectionStart = $index
            break
        }
    }
    if ($sectionStart -lt 0) {
        if ($Lines.Count -gt 0 -and $Lines[$Lines.Count - 1] -ne '') { $Lines.Add('') }
        $Lines.Add("[$Section]")
        $Lines.Add("$Key = $Value")
        return
    }
    $sectionEnd = $Lines.Count
    for ($index = $sectionStart + 1; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match '^\s*\[[^\]]+\]\s*$') { $sectionEnd = $index; break }
    }
    for ($index = $sectionStart + 1; $index -lt $sectionEnd; $index++) {
        if ($Lines[$index] -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
            $Lines[$index] = "$Key = $Value"
            return
        }
    }
    $Lines.Insert($sectionEnd, "$Key = $Value")
}

function Get-IniValueState {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key
    )

    $activeSection = $null
    foreach ($line in Get-Content -LiteralPath $LiteralPath) {
        if ($line -match '^\s*\[(?<Section>[^\]]+)\]\s*$') { $activeSection = $Matches.Section; continue }
        if ($activeSection -ieq $Section -and $line -match ('^\s*' + [regex]::Escape($Key) + '\s*=\s*(?<Value>.*)$')) {
            return [pscustomobject]@{ present = $true; value = $Matches.Value.Trim() }
        }
    }
    return [pscustomobject]@{ present = $false; value = $null }
}

function Remove-IniValue {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key
    )

    $activeSection = $null
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match '^\s*\[(?<Section>[^\]]+)\]\s*$') { $activeSection = $Matches.Section; continue }
        if ($activeSection -ieq $Section -and $Lines[$index] -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
            $Lines.RemoveAt($index)
            return
        }
    }
}

function Get-ModRegistryValueState {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Name
    )

    foreach ($line in Get-Content -LiteralPath $LiteralPath) {
        if ($line -match ('^\s*' + [regex]::Escape($Name) + '\s*:\s*(?<Value>.*)$')) {
            return [pscustomobject]@{ present = $true; value = $Matches.Value.Trim() }
        }
    }
    return [pscustomobject]@{ present = $false; value = $null }
}

function Remove-ModRegistryValue {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory)][string]$Name
    )

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match ('^\s*' + [regex]::Escape($Name) + '\s*:')) {
            $Lines.RemoveAt($index)
            return
        }
    }
}

function New-MergedSettingsFile {
    param(
        [Parameter(Mandatory)][string]$ExistingPath,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $ExistingPath) { $lines.Add($line) }
    foreach ($setting in @($Manifest.requiredSettings)) {
        Set-IniValue -Lines $lines -Section $setting.section -Key $setting.key -Value ([string]$setting.value)
    }
    Set-Content -LiteralPath $OutputPath -Value $lines -Encoding utf8
}

function New-MergedModRegistryFile {
    param(
        [Parameter(Mandatory)][string]$ExistingPath,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $ExistingPath) { $lines.Add($line) }
    foreach ($requiredMod in @($Manifest.requiredModRegistry)) {
        $replaced = $false
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match ('^\s*' + [regex]::Escape($requiredMod.name) + '\s*:')) {
                $lines[$index] = "$($requiredMod.name) : $($requiredMod.value)"
                $replaced = $true
                break
            }
        }
        if (-not $replaced) { $lines.Add("$($requiredMod.name) : $($requiredMod.value)") }
    }
    Set-Content -LiteralPath $OutputPath -Value $lines -Encoding utf8
}

function Assert-NoConflictingProxies {
    param(
        [Parameter(Mandatory)][string]$Win64Path,
        [Parameter(Mandatory)]$Manifest
    )

    foreach ($proxyName in @($Manifest.conflictingProxyNames)) {
        if (Test-Path -LiteralPath (Join-Path $Win64Path ([string]$proxyName)) -PathType Leaf) {
            throw "Conflicting proxy loader '$proxyName' is present. Restore a clean official build before continuing."
        }
    }
}

function Get-LoaderMode {
    param(
        [Parameter(Mandatory)][string]$Win64Path,
        [Parameter(Mandatory)]$Manifest
    )

    Assert-NoConflictingProxies -Win64Path $Win64Path -Manifest $Manifest
    $proxyPath = Join-Path $Win64Path 'dwmapi.dll'
    $corePath = Join-Path $Win64Path 'ue4ss\UE4SS.dll'
    $runtimeFolder = Join-Path $Win64Path 'ue4ss'
    $proxyExists = Test-Path -LiteralPath $proxyPath -PathType Leaf
    $coreExists = Test-Path -LiteralPath $corePath -PathType Leaf
    $runtimeFolderExists = Test-Path -LiteralPath $runtimeFolder -PathType Container

    if (-not $proxyExists -and -not $coreExists) {
        $remainingRuntimeFiles = @(
            if ($runtimeFolderExists) {
                Get-ChildItem -LiteralPath $runtimeFolder -File -Recurse -Force -ErrorAction SilentlyContinue
            }
        )
        $nonConfigFiles = @(
            foreach ($remainingFile in $remainingRuntimeFiles) {
                $relative = $remainingFile.FullName.Substring([IO.Path]::GetFullPath($Win64Path).TrimEnd('\').Length + 1).Replace('\', '/')
                if ($relative -notin @('ue4ss/UE4SS-settings.ini', 'ue4ss/Mods/mods.txt')) { $remainingFile }
            }
        )
        if ($nonConfigFiles.Count -eq 0) { return 'Fresh' }
    }
    if (-not $proxyExists -or -not $coreExists) {
        throw 'A partial nested UE4SS installation was found. Use Repair only for a runtime previously installed by this menu.'
    }

    $expectedProxy = Get-PayloadFileEntry -Manifest $Manifest -RelativePath 'dwmapi.dll'
    $expectedCore = Get-PayloadFileEntry -Manifest $Manifest -RelativePath 'ue4ss/UE4SS.dll'
    if ((Get-Sha256 -LiteralPath $proxyPath) -ne $expectedProxy.sha256 -or
        (Get-Sha256 -LiteralPath $corePath) -ne $expectedCore.sha256) {
        throw 'An unknown or conflicting UE4SS loader version is installed. No files were changed.'
    }
    return 'ExistingExact'
}

function Get-InstallPlan {
    param(
        [Parameter(Mandatory)][string]$Win64Path,
        [Parameter(Mandatory)]$Payload,
        [Parameter(Mandatory)][ValidateSet('Fresh', 'ExistingExact')][string]$LoaderMode
    )

    $plan = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($LoaderMode -eq 'Fresh') {
        foreach ($file in @($Payload.manifest.payloadFiles)) {
            $plan[$file.relativePath] = [pscustomobject]@{
                relativePath = $file.relativePath
                sourcePath = Get-SafeChildPath -Root $Payload.root -RelativePath $file.relativePath
                sha256 = $file.sha256
            }
        }
    }
    else {
        foreach ($overlay in @($Payload.manifest.overlays)) {
            $payloadEntry = Get-PayloadFileEntry -Manifest $Payload.manifest -RelativePath $overlay.targetPath
            $plan[$payloadEntry.relativePath] = [pscustomobject]@{
                relativePath = $payloadEntry.relativePath
                sourcePath = Get-SafeChildPath -Root $Payload.root -RelativePath $payloadEntry.relativePath
                sha256 = $payloadEntry.sha256
            }
        }
        foreach ($dependency in @($Payload.manifest.requiredRuntimeDependencies)) {
            $payloadEntry = Get-PayloadFileEntry -Manifest $Payload.manifest -RelativePath $dependency.relativePath
            $plan[$payloadEntry.relativePath] = [pscustomobject]@{
                relativePath = $payloadEntry.relativePath
                sourcePath = Get-SafeChildPath -Root $Payload.root -RelativePath $payloadEntry.relativePath
                sha256 = $payloadEntry.sha256
            }
        }
    }

    $generatedRoot = Join-Path $Payload.root '_dawnwalker-generated'
    New-Item -ItemType Directory -Path $generatedRoot -Force | Out-Null
    foreach ($config in @(
        @{ relativePath = 'ue4ss/UE4SS-settings.ini'; kind = 'settings' },
        @{ relativePath = 'ue4ss/Mods/mods.txt'; kind = 'mods' }
    )) {
        if (-not $plan.ContainsKey($config.relativePath)) { continue }
        $destinationPath = Get-SafeChildPath -Root $Win64Path -RelativePath $config.relativePath
        $existingPath = if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
            $destinationPath
        }
        else {
            Get-SafeChildPath -Root $Payload.root -RelativePath $config.relativePath
        }
        $generatedPath = Get-SafeChildPath -Root $generatedRoot -RelativePath $config.relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $generatedPath) -Force | Out-Null
        if ($config.kind -eq 'settings') {
            New-MergedSettingsFile -ExistingPath $existingPath -Manifest $Payload.manifest -OutputPath $generatedPath
        }
        else {
            New-MergedModRegistryFile -ExistingPath $existingPath -Manifest $Payload.manifest -OutputPath $generatedPath
        }
        $plan[$config.relativePath] = [pscustomobject]@{
            relativePath = $config.relativePath
            sourcePath = $generatedPath
            sha256 = Get-Sha256 -LiteralPath $generatedPath
        }
    }
    return @($plan.Values)
}

function Add-ExistingManagedPlanItems {
    param(
        [Parameter(Mandatory)][object[]]$Plan,
        [Parameter(Mandatory)]$ExistingState,
        [Parameter(Mandatory)]$Payload
    )

    $byPath = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $Plan) { $byPath[$item.relativePath] = $item }
    foreach ($record in @($ExistingState.files)) {
        if ($byPath.ContainsKey([string]$record.relativePath)) { continue }
        $entries = @($Payload.manifest.payloadFiles | Where-Object { $_.relativePath -eq $record.relativePath })
        if ($entries.Count -ne 1) { continue }
        $entry = $entries[0]
        $byPath[$entry.relativePath] = [pscustomobject]@{
            relativePath = $entry.relativePath
            sourcePath = Get-SafeChildPath -Root $Payload.root -RelativePath $entry.relativePath
            sha256 = $entry.sha256
        }
    }
    return @($byPath.Values)
}

function Copy-FileAtomically {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$ExpectedSha256
    )

    $destinationDirectory = Split-Path -Parent $DestinationPath
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    $temporaryPath = Join-Path $destinationDirectory ('.dawnwalker-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $replacementBackupPath = Join-Path $destinationDirectory ('.dawnwalker-' + [guid]::NewGuid().ToString('N') + '.bak')
    try {
        Copy-Item -LiteralPath $SourcePath -Destination $temporaryPath -Force
        if ((Get-Sha256 -LiteralPath $temporaryPath) -ne $ExpectedSha256) {
            throw "Staged copy failed its hash check: $DestinationPath"
        }
        if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
            [IO.File]::Replace($temporaryPath, $DestinationPath, $replacementBackupPath, $true)
            Remove-Item -LiteralPath $replacementBackupPath -Force
        }
        else {
            [IO.File]::Move($temporaryPath, $DestinationPath)
        }
        if ((Get-Sha256 -LiteralPath $DestinationPath) -ne $ExpectedSha256) {
            throw "Installed file failed its hash check: $DestinationPath"
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
        if (Test-Path -LiteralPath $replacementBackupPath -PathType Leaf) {
            Remove-Item -LiteralPath $replacementBackupPath -Force
        }
    }
}

function Read-InstallState {
    if (-not (Test-Path -LiteralPath $script:StatePath -PathType Leaf)) { return $null }
    $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
    if ($state.cyberfox1337x -ne 'function(dawnwalker_runtime_install_state)' -or
        $state.schemaVersion -ne 1 -or $state.steamAppId -ne $script:ExpectedAppId) {
        throw 'The existing Dawnwalker runtime install state is invalid. No files were changed.'
    }
    if (-not $state.PSObject.Properties['phase'] -or
        -not $state.PSObject.Properties['bridgeVersion'] -or
        -not $state.PSObject.Properties['gameplayCapabilities']) {
        throw 'The existing Dawnwalker runtime install state is missing bridge metadata. No files were changed.'
    }
    $stateCapabilities = @(Get-DawnwalkerValidatedCapabilities -Values @($state.gameplayCapabilities) -Context 'Runtime install state')
    Assert-DawnwalkerPhaseCapabilityContract `
        -Phase ([string]$state.phase) `
        -BridgeVersion ([string]$state.bridgeVersion) `
        -Capabilities $stateCapabilities `
        -Context 'Runtime install state'
    return $state
}

function Get-ManagedGameInstallFromState {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Contract
    )

    if ([string]$State.steamBuildId -ne [string]$Contract.steam.buildId) {
        throw 'Runtime install state was not recorded from the pinned Steam build.'
    }
    $stateWin64 = [string]$State.win64Path
    $stateInstallPath = [string]$State.installPath
    $stateManifestPath = [string]$State.manifestPath
    if (-not [IO.Path]::IsPathRooted($stateWin64) -or
        -not [IO.Path]::IsPathRooted($stateInstallPath) -or
        -not [IO.Path]::IsPathRooted($stateManifestPath)) {
        throw 'Runtime install state contains a non-rooted game path.'
    }
    $resolvedWin64 = [IO.Path]::GetFullPath($stateWin64).TrimEnd('\')
    $resolvedInstallPath = [IO.Path]::GetFullPath($stateInstallPath).TrimEnd('\')
    $resolvedManifestPath = [IO.Path]::GetFullPath($stateManifestPath)
    if ([IO.Path]::GetFileName($resolvedManifestPath) -ine "appmanifest_$($Contract.steam.appId).acf" -or
        (Split-Path -Leaf (Split-Path -Parent $resolvedManifestPath)) -ine 'steamapps') {
        throw 'Runtime install state does not reference the exact Dawnwalker Steam manifest layout.'
    }
    $expectedInstallPath = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $resolvedManifestPath) "common\$($Contract.steam.installDirName)")).TrimEnd('\')
    if (-not $resolvedInstallPath.Equals($expectedInstallPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Runtime install state does not reference the manifest-derived Dawnwalker install directory.'
    }
    if (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf) {
        $manifestText = Get-Content -LiteralPath $resolvedManifestPath -Raw
        if ((Read-ManifestValue -Text $manifestText -Name 'appid') -ne $Contract.steam.appId -or
            (Read-ManifestValue -Text $manifestText -Name 'installdir') -ne $Contract.steam.installDirName) {
            throw 'Runtime install state Steam manifest identity no longer matches Dawnwalker.'
        }
    }
    elseif (Test-Path -LiteralPath $resolvedInstallPath) {
        throw 'The recorded Steam manifest is missing while its game directory still exists.'
    }
    $expectedSuffix = '\' + $script:ExpectedWin64Suffix
    if (-not $resolvedWin64.EndsWith($expectedSuffix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Runtime install state does not target the exact Dawnwalker Win64 suffix.'
    }
    $derivedInstallPath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $resolvedWin64))
    if (-not $resolvedInstallPath.Equals([IO.Path]::GetFullPath($derivedInstallPath).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Runtime install state game and Win64 paths are inconsistent.'
    }

    $seenPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($record in @($State.files)) {
        $normalized = Assert-AllowedRuntimePath -RelativePath ([string]$record.relativePath) -Contract $Contract
        if (-not $seenPaths.Add($normalized)) {
            throw "Runtime install state duplicates a managed path: $normalized"
        }
        [void](Get-SafeChildPath -Root $resolvedWin64 -RelativePath $normalized)
    }
    if ($seenPaths.Count -eq 0) {
        throw 'Runtime install state has no managed files.'
    }

    return [pscustomobject]@{
        manifestPath = $resolvedManifestPath
        buildId = [string]$State.steamBuildId
        installPath = $resolvedInstallPath
        executablePath = Join-Path $resolvedWin64 'Dawnwalker.exe'
        executableSha256 = $null
        win64Path = $resolvedWin64
    }
}

function Write-InstallState {
    param([Parameter(Mandatory)]$State)

    New-Item -ItemType Directory -Path $script:StateRoot -Force | Out-Null
    $temporaryPath = Join-Path $script:StateRoot ('install-state.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $State | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporaryPath -Encoding utf8
    Move-Item -LiteralPath $temporaryPath -Destination $script:StatePath -Force
}

function Get-ManagedFileHealth {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Win64Path
    )

    $issues = @()
    foreach ($record in @($State.files)) {
        $destinationPath = Get-SafeChildPath -Root $Win64Path -RelativePath $record.relativePath
        if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
            $issues += [pscustomobject]@{ relativePath = $record.relativePath; reason = 'missing' }
            continue
        }
        $ownership = if ($record.PSObject.Properties['ownership']) { [string]$record.ownership } else { 'whole-file' }
        if ($ownership -eq 'semantic-ini') {
            foreach ($entry in @($record.semanticEntries)) {
                $current = Get-IniValueState -LiteralPath $destinationPath -Section $entry.section -Key $entry.key
                if (-not $current.present -or $current.value -ne [string]$entry.installedValue) {
                    $issues += [pscustomobject]@{ relativePath = $record.relativePath; reason = "owned-setting-drift:$($entry.section)/$($entry.key)" }
                }
            }
            continue
        }
        if ($ownership -eq 'semantic-mod-registry') {
            foreach ($entry in @($record.semanticEntries)) {
                $current = Get-ModRegistryValueState -LiteralPath $destinationPath -Name $entry.name
                if (-not $current.present -or $current.value -ne [string]$entry.installedValue) {
                    $issues += [pscustomobject]@{ relativePath = $record.relativePath; reason = "owned-mod-drift:$($entry.name)" }
                }
            }
            continue
        }
        if ((Get-Sha256 -LiteralPath $destinationPath) -ne [string]$record.installedSha256) {
            $issues += [pscustomobject]@{ relativePath = $record.relativePath; reason = 'hash-mismatch' }
        }
    }
    return @($issues)
}

function Assert-ManagedFilesUnchanged {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Win64Path
    )

    $issues = @(Get-ManagedFileHealth -State $State -Win64Path $Win64Path)
    if ($issues.Count -gt 0) {
        throw "Managed Dawnwalker runtime drift was found at '$($issues[0].relativePath)' ($($issues[0].reason)). Run Repair before updating or rolling back."
    }
}

function Assert-SafeStateRoot {
    $resolved = [IO.Path]::GetFullPath($script:StateRoot).TrimEnd('\')
    if ($resolved.Equals($script:DefaultStateRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { return }
    $temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) { return }
    throw "Refusing destructive state cleanup outside the approved roots: $resolved"
}

function New-TransactionSnapshot {
    param(
        [Parameter(Mandatory)][string]$Win64Path,
        [Parameter(Mandatory)][string[]]$RelativePaths
    )

    $transactionRoot = Join-Path $script:StateRoot ('transactions\' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $transactionRoot -Force | Out-Null
    $records = @()
    foreach ($relativePath in $RelativePaths | Sort-Object -Unique) {
        $destinationPath = Get-SafeChildPath -Root $Win64Path -RelativePath $relativePath
        $exists = Test-Path -LiteralPath $destinationPath -PathType Leaf
        $snapshotRelativePath = $null
        if ($exists) {
            $snapshotPath = Get-SafeChildPath -Root $transactionRoot -RelativePath $relativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $snapshotPath) -Force | Out-Null
            Copy-Item -LiteralPath $destinationPath -Destination $snapshotPath -Force
            $snapshotRelativePath = $relativePath
        }
        $records += [pscustomobject]@{
            relativePath = $relativePath
            existed = $exists
            snapshotRelativePath = $snapshotRelativePath
        }
    }
    return [pscustomobject]@{ root = $transactionRoot; records = $records }
}

function Restore-TransactionSnapshot {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][string]$Win64Path
    )

    foreach ($record in @($Snapshot.records)) {
        $destinationPath = Get-SafeChildPath -Root $Win64Path -RelativePath $record.relativePath
        if ($record.existed) {
            $sourcePath = Get-SafeChildPath -Root $Snapshot.root -RelativePath $record.snapshotRelativePath
            Copy-FileAtomically -SourcePath $sourcePath -DestinationPath $destinationPath -ExpectedSha256 (Get-Sha256 -LiteralPath $sourcePath)
        }
        elseif (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
            Remove-Item -LiteralPath $destinationPath -Force
        }
    }
}

function Remove-SafeTransaction {
    param([Parameter(Mandatory)][string]$TransactionRoot)

    $transactionsParent = [IO.Path]::GetFullPath((Join-Path $script:StateRoot 'transactions')).TrimEnd('\') + '\'
    $resolved = [IO.Path]::GetFullPath($TransactionRoot)
    if (-not $resolved.StartsWith($transactionsParent, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove unsafe transaction path: $resolved"
    }
    if (Test-Path -LiteralPath $resolved -PathType Container) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

function Get-SemanticBaseline {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)]$Manifest
    )

    if ($RelativePath -ieq 'ue4ss/UE4SS-settings.ini') {
        return [pscustomobject]@{
            ownership = 'semantic-ini'
            entries = @(
                foreach ($setting in @($Manifest.requiredSettings)) {
                    $current = Get-IniValueState -LiteralPath $LiteralPath -Section $setting.section -Key $setting.key
                    [pscustomobject]@{
                        section = $setting.section
                        key = $setting.key
                        originalPresent = $current.present
                        originalValue = $current.value
                        installedValue = [string]$setting.value
                    }
                }
            )
        }
    }
    if ($RelativePath -ieq 'ue4ss/Mods/mods.txt') {
        return [pscustomobject]@{
            ownership = 'semantic-mod-registry'
            entries = @(
                foreach ($requiredMod in @($Manifest.requiredModRegistry)) {
                    $current = Get-ModRegistryValueState -LiteralPath $LiteralPath -Name $requiredMod.name
                    [pscustomobject]@{
                        name = $requiredMod.name
                        originalPresent = $current.present
                        originalValue = $current.value
                        installedValue = [string]$requiredMod.value
                    }
                }
            )
        }
    }
    return [pscustomobject]@{ ownership = 'whole-file'; entries = @() }
}

function Restore-BaselineRecord {
    param(
        [Parameter(Mandatory)]$Record,
        [Parameter(Mandatory)][string]$Win64Path
    )

    $destinationPath = Get-SafeChildPath -Root $Win64Path -RelativePath $Record.relativePath
    $ownership = if ($Record.PSObject.Properties['ownership']) { [string]$Record.ownership } else { 'whole-file' }
    if ($ownership -eq 'semantic-ini' -or $ownership -eq 'semantic-mod-registry') {
        if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
            throw "Semantically managed configuration is missing: $($Record.relativePath)"
        }
        # With no later edits, preserve the complete baseline (including BOM and newlines).
        # Otherwise retain the per-key merge below so unrelated user changes survive.
        if ($Record.originalKind -eq 'file' -and $Record.PSObject.Properties['exactRestoreAllowed'] -and
            $Record.exactRestoreAllowed -eq $true -and $Record.PSObject.Properties['installedSha256'] -and
            (Get-Sha256 -LiteralPath $destinationPath) -eq [string]$Record.installedSha256) {
            $backupPath = Get-SafeChildPath -Root $script:StateRoot -RelativePath $Record.backupRelativePath
            if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or
                (Get-Sha256 -LiteralPath $backupPath) -ne [string]$Record.originalSha256) {
                throw "Baseline backup is missing or corrupt: $($Record.relativePath)"
            }
            Copy-FileAtomically -SourcePath $backupPath -DestinationPath $destinationPath -ExpectedSha256 ([string]$Record.originalSha256)
            return
        }
        $lines = [Collections.Generic.List[string]]::new()
        foreach ($line in Get-Content -LiteralPath $destinationPath) { $lines.Add($line) }
        foreach ($entry in @($Record.semanticEntries)) {
            if ($ownership -eq 'semantic-ini') {
                if ($entry.originalPresent) {
                    Set-IniValue -Lines $lines -Section $entry.section -Key $entry.key -Value ([string]$entry.originalValue)
                }
                else {
                    Remove-IniValue -Lines $lines -Section $entry.section -Key $entry.key
                }
            }
            elseif ($entry.originalPresent) {
                $replaced = $false
                for ($index = 0; $index -lt $lines.Count; $index++) {
                    if ($lines[$index] -match ('^\s*' + [regex]::Escape($entry.name) + '\s*:')) {
                        $lines[$index] = "$($entry.name) : $($entry.originalValue)"
                        $replaced = $true
                        break
                    }
                }
                if (-not $replaced) { $lines.Add("$($entry.name) : $($entry.originalValue)") }
            }
            else {
                Remove-ModRegistryValue -Lines $lines -Name $entry.name
            }
        }
        $temporaryPath = Join-Path $script:StateRoot ('semantic-restore-' + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            Set-Content -LiteralPath $temporaryPath -Value $lines -Encoding utf8
            Copy-FileAtomically -SourcePath $temporaryPath -DestinationPath $destinationPath -ExpectedSha256 (Get-Sha256 -LiteralPath $temporaryPath)
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
        }
        return
    }
    if ($Record.originalKind -eq 'absent') {
        if (Test-Path -LiteralPath $destinationPath -PathType Leaf) { Remove-Item -LiteralPath $destinationPath -Force }
        return
    }
    if ($Record.originalKind -ne 'file') { throw "Unknown baseline record kind: $($Record.originalKind)" }
    $backupPath = Get-SafeChildPath -Root $script:StateRoot -RelativePath $Record.backupRelativePath
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or
        (Get-Sha256 -LiteralPath $backupPath) -ne [string]$Record.originalSha256) {
        throw "Baseline backup is missing or corrupt: $($Record.relativePath)"
    }
    Copy-FileAtomically -SourcePath $backupPath -DestinationPath $destinationPath -ExpectedSha256 ([string]$Record.originalSha256)
}

function Remove-FailedInitialState {
    param([Parameter(Mandatory)][bool]$StateRootExistedBefore)

    if ($StateRootExistedBefore -or -not (Test-Path -LiteralPath $script:StateRoot -PathType Container)) { return }
    Assert-SafeStateRoot
    Remove-Item -LiteralPath $script:StateRoot -Recurse -Force
}

function Invoke-RuntimeDeployment {
    param(
        [Parameter(Mandatory)][ValidateSet('Install', 'Repair')][string]$Mode,
        [Parameter(Mandatory)]$GameInstall,
        [Parameter(Mandatory)]$Payload,
        [Parameter(Mandatory)][string]$ApplicationVersion
    )

    Assert-GameInstallIdentity -GameInstall $GameInstall -Contract $Payload.contract
    $stateRootExistedBefore = Test-Path -LiteralPath $script:StateRoot -PathType Container
    $existingState = Read-InstallState
    $initialInstall = $null -eq $existingState
    if ($Mode -eq 'Repair' -and $initialInstall) { throw 'No managed Dawnwalker runtime is installed. Use Install first.' }
    if ($existingState) {
        if (-not ([IO.Path]::GetFullPath($existingState.win64Path)).Equals([IO.Path]::GetFullPath($GameInstall.win64Path), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Existing runtime state targets a different Steam installation.'
        }
        if ($Mode -eq 'Install') {
            Assert-ManagedFilesUnchanged -State $existingState -Win64Path $GameInstall.win64Path
        }
    }
    elseif ($stateRootExistedBefore -and @(Get-ChildItem -LiteralPath $script:StateRoot -Force).Count -gt 0) {
        throw 'Runtime backup directory exists without a valid install state. No files were changed.'
    }

    if ($Mode -eq 'Repair' -and $existingState.loaderMode -eq 'Fresh') {
        Assert-NoConflictingProxies -Win64Path $GameInstall.win64Path -Manifest $Payload.manifest
        $loaderMode = 'Fresh'
    }
    else {
        $loaderMode = Get-LoaderMode -Win64Path $GameInstall.win64Path -Manifest $Payload.manifest
    }
    $plan = @(Get-InstallPlan -Win64Path $GameInstall.win64Path -Payload $Payload -LoaderMode $loaderMode)
    if ($existingState) {
        $plan = @(Add-ExistingManagedPlanItems -Plan $plan -ExistingState $existingState -Payload $Payload)
    }

    $snapshot = $null
    try {
        New-Item -ItemType Directory -Path $script:BaselineRoot -Force | Out-Null
        $baselineByPath = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($existingState) {
            foreach ($record in @($existingState.files)) {
                # A repair adopts merged bytes as installedSha256; remember prior user edits.
                $destination = Get-SafeChildPath -Root $GameInstall.win64Path -RelativePath $record.relativePath
                $exactRestoreAllowed = $record.PSObject.Properties['exactRestoreAllowed'] -and
                    $record.exactRestoreAllowed -eq $true -and
                    (Test-Path -LiteralPath $destination -PathType Leaf) -and
                    (Get-Sha256 -LiteralPath $destination) -eq [string]$record.installedSha256
                $record | Add-Member -NotePropertyName exactRestoreAllowed -NotePropertyValue ([bool]$exactRestoreAllowed) -Force
                $baselineByPath[$record.relativePath] = $record
            }
        }
        foreach ($item in $plan) {
            if ($baselineByPath.ContainsKey($item.relativePath)) { continue }
            $destinationPath = Get-SafeChildPath -Root $GameInstall.win64Path -RelativePath $item.relativePath
            if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
                $semanticBaseline = Get-SemanticBaseline -RelativePath $item.relativePath -LiteralPath $destinationPath -Manifest $Payload.manifest
                $backupRelativePath = 'baseline/' + $item.relativePath.Replace('\', '/')
                $backupPath = Get-SafeChildPath -Root $script:StateRoot -RelativePath $backupRelativePath
                New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
                Copy-Item -LiteralPath $destinationPath -Destination $backupPath -Force
                $baselineByPath[$item.relativePath] = [pscustomobject]@{
                    relativePath = $item.relativePath
                    originalKind = 'file'
                    originalSha256 = Get-Sha256 -LiteralPath $backupPath
                    exactRestoreAllowed = $true
                    backupRelativePath = $backupRelativePath
                    ownership = $semanticBaseline.ownership
                    semanticEntries = @($semanticBaseline.entries)
                }
            }
            else {
                $baselineByPath[$item.relativePath] = [pscustomobject]@{
                    relativePath = $item.relativePath
                    originalKind = 'absent'
                    exactRestoreAllowed = $false
                    originalSha256 = $null
                    backupRelativePath = $null
                    ownership = 'whole-file'
                    semanticEntries = @()
                }
            }
        }

        $oldPaths = @($baselineByPath.Keys)
        $newPaths = @($plan.relativePath)
        $snapshot = New-TransactionSnapshot -Win64Path $GameInstall.win64Path -RelativePaths @($oldPaths + $newPaths)
        foreach ($oldPath in $oldPaths) {
            if ($newPaths -notcontains $oldPath) {
                Restore-BaselineRecord -Record $baselineByPath[$oldPath] -Win64Path $GameInstall.win64Path
                [void]$baselineByPath.Remove($oldPath)
            }
        }
        foreach ($item in $plan) {
            $destinationPath = Get-SafeChildPath -Root $GameInstall.win64Path -RelativePath $item.relativePath
            Copy-FileAtomically -SourcePath $item.sourcePath -DestinationPath $destinationPath -ExpectedSha256 $item.sha256
        }

        $stateRecords = @(
            foreach ($item in $plan) {
                $baseline = $baselineByPath[$item.relativePath]
                [ordered]@{
                    relativePath = $item.relativePath.Replace('\', '/')
                    installedSha256 = $item.sha256
                    exactRestoreAllowed = [bool]$baseline.exactRestoreAllowed
                    originalKind = $baseline.originalKind
                    originalSha256 = $baseline.originalSha256
                    backupRelativePath = $baseline.backupRelativePath
                    ownership = $baseline.ownership
                    semanticEntries = @($baseline.semanticEntries)
                }
            }
        )
        $state = [ordered]@{
            cyberfox1337x = 'function(dawnwalker_runtime_install_state)'
            schemaVersion = 1
            applicationVersion = $ApplicationVersion
            phase = $Payload.manifest.phase
            bridgeVersion = $Payload.manifest.bridgeVersion
            gameplayCapabilities = @($Payload.manifest.gameplayCapabilities)
            installedAtUtc = [DateTime]::UtcNow.ToString('o')
            steamAppId = $script:ExpectedAppId
            steamBuildId = $GameInstall.buildId
            manifestPath = $GameInstall.manifestPath
            installPath = $GameInstall.installPath
            win64Path = $GameInstall.win64Path
            loaderMode = if ($existingState) { $existingState.loaderMode } else { $loaderMode }
            payloadManifestSha256 = Get-Sha256 -LiteralPath $Payload.metadata.manifestPath
            files = $stateRecords
        }
        Write-InstallState -State $state
    }
    catch {
        if ($snapshot) { Restore-TransactionSnapshot -Snapshot $snapshot -Win64Path $GameInstall.win64Path }
        if ($initialInstall) { Remove-FailedInitialState -StateRootExistedBefore $stateRootExistedBefore }
        throw
    }
    finally {
        if ($snapshot -and (Test-Path -LiteralPath $snapshot.root -PathType Container)) {
            Remove-SafeTransaction -TransactionRoot $snapshot.root
        }
    }
    Write-Output "Dawnwalker $($Payload.manifest.phase) runtime $Mode completed for exact Steam build $($GameInstall.buildId) with $(@($Payload.manifest.gameplayCapabilities).Count) compiled gameplay capabilities."
}

function Install-Runtime {
    param(
        [Parameter(Mandatory)]$GameInstall,
        [Parameter(Mandatory)]$Payload,
        [string]$ApplicationVersion = '0.1.0'
    )

    Invoke-RuntimeDeployment -Mode Install -GameInstall $GameInstall -Payload $Payload -ApplicationVersion $ApplicationVersion
}

function Repair-Runtime {
    param(
        [Parameter(Mandatory)]$GameInstall,
        [Parameter(Mandatory)]$Payload,
        [string]$ApplicationVersion = '0.1.0'
    )

    Invoke-RuntimeDeployment -Mode Repair -GameInstall $GameInstall -Payload $Payload -ApplicationVersion $ApplicationVersion
}

function Uninstall-Runtime {
    param([Parameter(Mandatory)]$GameInstall)

    $state = Read-InstallState
    if (-not $state) {
        Write-Output 'No managed Dawnwalker runtime install state was found; nothing to restore.'
        return
    }
    if (-not ([IO.Path]::GetFullPath($state.win64Path)).Equals([IO.Path]::GetFullPath($GameInstall.win64Path), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Runtime state no longer matches the validated managed Steam installation.'
    }
    if (-not (Test-Path -LiteralPath $GameInstall.win64Path -PathType Container)) {
        if (Test-Path -LiteralPath $GameInstall.installPath) {
            throw 'The recorded game directory still exists but its Win64 directory is missing. Runtime state was retained for manual recovery.'
        }
        $volumeRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($GameInstall.installPath))
        if ([string]::IsNullOrWhiteSpace($volumeRoot) -or -not (Test-Path -LiteralPath $volumeRoot -PathType Container)) {
            throw 'The recorded game volume is unavailable. Runtime state was retained so rollback data is not lost.'
        }
        foreach ($record in @($state.files | Where-Object { $_.originalKind -eq 'file' })) {
            $backupPath = Get-SafeChildPath -Root $script:StateRoot -RelativePath ([string]$record.backupRelativePath)
            if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or
                (Get-Sha256 -LiteralPath $backupPath) -ne [string]$record.originalSha256) {
                throw "Recorded baseline backup is missing or corrupt: $($record.relativePath)"
            }
        }
        Assert-SafeStateRoot
        Remove-Item -LiteralPath $script:StateRoot -Recurse -Force
        Write-Output 'The recorded Dawnwalker installation has been removed; validated orphaned runtime state was cleared without recreating game files.'
        return
    }
    Assert-ManagedFilesUnchanged -State $state -Win64Path $GameInstall.win64Path
    $relativePaths = @($state.files.relativePath)
    $snapshot = New-TransactionSnapshot -Win64Path $GameInstall.win64Path -RelativePaths $relativePaths
    try {
        foreach ($record in @($state.files)) {
            Restore-BaselineRecord -Record $record -Win64Path $GameInstall.win64Path
        }
    }
    catch {
        Restore-TransactionSnapshot -Snapshot $snapshot -Win64Path $GameInstall.win64Path
        throw
    }
    finally {
        Remove-SafeTransaction -TransactionRoot $snapshot.root
    }
    Assert-SafeStateRoot
    Remove-Item -LiteralPath $script:StateRoot -Recurse -Force
    Write-Output 'Dawnwalker runtime files were restored to their recorded pre-install baseline.'
}

function Get-RuntimeStatus {
    param(
        [Parameter(Mandatory)]$GameInstall,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)]$Contract,
        [bool]$PayloadValid = $true
    )

    $state = Read-InstallState
    $issues = @(
        if ($state) { Get-ManagedFileHealth -State $state -Win64Path $GameInstall.win64Path }
    )
    $loaderMode = $null
    $loaderError = $null
    try { $loaderMode = Get-LoaderMode -Win64Path $GameInstall.win64Path -Manifest $Manifest }
    catch { $loaderError = $_.Exception.Message }
    $exactBuild = [string]$GameInstall.buildId -eq [string]$Contract.steam.buildId -and
        [string]$GameInstall.executableSha256 -eq [string]$Contract.executable.sha256
    $status = if (-not $state) { 'not-installed' } elseif ($issues.Count -gt 0) { 'installed-drifted' } else { 'installed-healthy' }
    $installedCapabilities = @()
    if ($state) { $installedCapabilities = @($state.gameplayCapabilities) }
    return [ordered]@{
        cyberfox1337x = 'function(dawnwalker_runtime_status)'
        schemaVersion = 1
        phase = $Manifest.phase
        bridgeVersion = $Manifest.bridgeVersion
        gameplayCapabilities = @($Manifest.gameplayCapabilities)
        status = $status
        payloadValid = $PayloadValid
        gameRunning = Test-GameRunning -Contract $Contract
        exactOfficialBuild = $exactBuild
        steamAppId = $Contract.steam.appId
        expectedBuildId = $Contract.steam.buildId
        actualBuildId = $GameInstall.buildId
        expectedExecutableSha256 = $Contract.executable.sha256
        actualExecutableSha256 = $GameInstall.executableSha256
        win64Path = $GameInstall.win64Path
        loaderMode = $loaderMode
        loaderError = $loaderError
        installStatePresent = $null -ne $state
        installedApplicationVersion = if ($state) { $state.applicationVersion } else { $null }
        installedPhase = if ($state) { $state.phase } else { $null }
        installedBridgeVersion = if ($state) { $state.bridgeVersion } else { $null }
        installedGameplayCapabilities = $installedCapabilities
        managedFileIssues = @($issues)
    }
}

function Remove-ValidatedPayloadStaging {
    param([Parameter(Mandatory)]$Payload)

    if (-not $Payload -or -not $Payload.root -or -not (Test-Path -LiteralPath $Payload.root -PathType Container)) { return }
    $temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolvedRoot = [IO.Path]::GetFullPath($Payload.root)
    if (-not $resolvedRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove unsafe payload staging path: $resolvedRoot"
    }
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
}

function Invoke-DawnwalkerRuntimeInstaller {
    $payload = $null
    try {
        if ($Action -eq 'VerifyPayload') {
            $payload = New-ValidatedPayloadStaging -Root $PayloadRoot
            Write-Output "Verified $($payload.manifest.payloadFiles.Count) $($payload.manifest.phase)-phase runtime payload files with $(@($payload.manifest.gameplayCapabilities).Count) compiled gameplay capabilities."
            return
        }

        $metadata = Read-PayloadMetadata -Root $PayloadRoot
        if ($Action -eq 'Status') {
            try {
                $gameInstall = Get-OfficialGameInstall -Contract $metadata.contract
                Get-RuntimeStatus -GameInstall $gameInstall -Manifest $metadata.manifest -Contract $metadata.contract |
                    ConvertTo-Json -Depth 8
            }
            catch {
                $gameDiscoveryError = $_.Exception.Message
                $unavailableState = $null
                $stateReadError = $null
                try { $unavailableState = Read-InstallState }
                catch { $stateReadError = $_.Exception.Message }
                $unavailableInstalledCapabilities = @()
                if ($unavailableState) { $unavailableInstalledCapabilities = @($unavailableState.gameplayCapabilities) }
                [ordered]@{
                    cyberfox1337x = 'function(dawnwalker_runtime_status)'
                    schemaVersion = 1
                    phase = $metadata.manifest.phase
                    bridgeVersion = $metadata.manifest.bridgeVersion
                    gameplayCapabilities = @($metadata.manifest.gameplayCapabilities)
                    status = 'unavailable'
                    payloadValid = $true
                    gameRunning = Test-GameRunning -Contract $metadata.contract
                    exactOfficialBuild = $false
                    installStatePresent = $null -ne $unavailableState
                    installedApplicationVersion = if ($unavailableState) { $unavailableState.applicationVersion } else { $null }
                    installedPhase = if ($unavailableState) { $unavailableState.phase } else { $null }
                    installedBridgeVersion = if ($unavailableState) { $unavailableState.bridgeVersion } else { $null }
                    installedGameplayCapabilities = $unavailableInstalledCapabilities
                    error = if ($stateReadError) { "$gameDiscoveryError Install state error: $stateReadError" } else { $gameDiscoveryError }
                } | ConvertTo-Json -Depth 8
            }
            return
        }

        if ($Action -eq 'Uninstall') {
            Assert-GameStopped -Contract $metadata.contract
            $installedState = Read-InstallState
            if (-not $installedState) {
                Write-Output 'No managed Dawnwalker runtime install state was found; nothing to restore.'
                return
            }
            $managedGameInstall = Get-ManagedGameInstallFromState -State $installedState -Contract $metadata.contract
            Uninstall-Runtime -GameInstall $managedGameInstall
            return
        }

        Assert-GameStopped -Contract $metadata.contract
        $gameInstall = Get-OfficialGameInstall -Contract $metadata.contract -RequireExactBuild
        Assert-EligibleInstall -GameInstall $gameInstall -Contract $metadata.contract
        $payload = New-ValidatedPayloadStaging -Root $PayloadRoot
        if ($Action -eq 'Repair') {
            Repair-Runtime -GameInstall $gameInstall -Payload $payload -ApplicationVersion $ApplicationVersion
        }
        else {
            Install-Runtime -GameInstall $gameInstall -Payload $payload -ApplicationVersion $ApplicationVersion
        }
    }
    finally {
        if ($payload) { Remove-ValidatedPayloadStaging -Payload $payload }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-DawnwalkerRuntimeInstaller
}
