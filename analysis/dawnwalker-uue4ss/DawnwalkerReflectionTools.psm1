Set-StrictMode -Version Latest

function cyberfox1337x {
    param([Parameter(Mandatory = $true)][string]$ModuleName)
    return $ModuleName
}

$null = cyberfox1337x -ModuleName 'dawnwalker_reflection_tools'

$script:DawnwalkerUEHelpersRelativePath = 'ue4ss/Mods/shared/UEHelpers/UEHelpers.lua'
$script:DawnwalkerUEHelpersBytes = 10237
$script:DawnwalkerUEHelpersSha256 = '7476F02EEF0C87BFEAB169F2FFE2E704363FAEAAE4BF9F1BDA574B1E34F4A0E9'

function Get-DawnwalkerSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "File not found: $LiteralPath"
    }

    # Use the framework hasher directly so an outer advanced command's
    # -WhatIf preference cannot suppress this read-only identity check.
    $stream = [System.IO.File]::Open(
        [System.IO.Path]::GetFullPath($LiteralPath),
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )
    try {
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $hasher.ComputeHash($stream)
            return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '')
        }
        finally {
            $hasher.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Test-DawnwalkerUEHelpersFile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Required pinned UEHelpers dependency is missing: $LiteralPath"
    }
    $helperItem = Get-Item -LiteralPath $LiteralPath
    if ([int64]$helperItem.Length -ne [int64]$script:DawnwalkerUEHelpersBytes) {
        throw "Pinned UEHelpers dependency length mismatch: expected $($script:DawnwalkerUEHelpersBytes), found $($helperItem.Length)."
    }
    $helperHash = Get-DawnwalkerSha256 -LiteralPath $LiteralPath
    if ($helperHash -cne $script:DawnwalkerUEHelpersSha256) {
        throw "Pinned UEHelpers dependency SHA-256 mismatch: expected $($script:DawnwalkerUEHelpersSha256), found $helperHash."
    }

    return [pscustomobject]@{
        relativePath = $script:DawnwalkerUEHelpersRelativePath
        path = [System.IO.Path]::GetFullPath($LiteralPath)
        bytes = [int64]$helperItem.Length
        sha256 = $helperHash
    }
}

function ConvertTo-DawnwalkerUtcDateTime {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Value)

    # PowerShell 7's ConvertFrom-Json materializes ISO timestamps as DateTime.
    # Converting that DateTime to string first drops its round-trip UTC marker
    # under some cultures and applies the local offset a second time.
    if ($Value -is [DateTime]) {
        if ($Value.Kind -eq [DateTimeKind]::Unspecified) {
            throw 'A timestamp without an explicit UTC or local kind is not accepted.'
        }
        return $Value.ToUniversalTime()
    }
    if ($Value -is [DateTimeOffset]) {
        return $Value.UtcDateTime
    }

    $parsed = [DateTime]::Parse(
        [string]$Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind
    )
    if ($parsed.Kind -eq [DateTimeKind]::Unspecified) {
        throw 'A timestamp without an explicit UTC or local offset is not accepted.'
    }
    return $parsed.ToUniversalTime()
}

function Resolve-DawnwalkerSafeChildPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [switch]$AllowRoot
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "A relative child path is required: $RelativePath"
    }

    $normalizedRoot = [System.IO.Path]::GetFullPath($RootPath).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $candidate = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($normalizedRoot, $RelativePath))
    $prefix = $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar

    if ($candidate.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($AllowRoot) {
            return $candidate
        }
        throw "The child path resolves to the root: $RelativePath"
    }

    if (-not $candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path traversal outside the approved root was refused: $RelativePath"
    }

    return $candidate
}

function Read-DawnwalkerJsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "JSON file not found: $LiteralPath"
    }

    try {
        return Get-Content -LiteralPath $LiteralPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Invalid JSON in '$LiteralPath': $($_.Exception.Message)"
    }
}

function Write-DawnwalkerJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$LiteralPath
    )

    $parentPath = Split-Path -Parent $LiteralPath
    if ($parentPath) {
        New-Item -ItemType Directory -Force -Path $parentPath | Out-Null
    }

    $temporaryPath = "$LiteralPath.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $json = $InputObject | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $LiteralPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Get-DawnwalkerAcfValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AcfText,
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$Optional
    )

    $escapedName = [Regex]::Escape($Name)
    $match = [Regex]::Match($AcfText, '(?im)^\s*"' + $escapedName + '"\s+"([^"]*)"\s*$')
    if (-not $match.Success) {
        if ($Optional) {
            return $null
        }
        throw "Steam manifest field '$Name' was not found."
    }

    return $match.Groups[1].Value
}

function Get-DawnwalkerSteamLibraryRoots {
    [CmdletBinding()]
    param()

    $roots = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $candidates = @()

    try {
        $candidates += (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath
    }
    catch {
        Write-Verbose "HKCU SteamPath unavailable: $($_.Exception.Message)"
    }

    try {
        $candidates += (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -Name InstallPath -ErrorAction Stop).InstallPath
    }
    catch {
        Write-Verbose "HKLM Steam InstallPath unavailable: $($_.Exception.Message)"
    }

    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Steam')
    }

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath $candidate -PathType Container)) {
            $null = $roots.Add([System.IO.Path]::GetFullPath([string]$candidate))
        }
    }

    foreach ($steamRoot in @($roots)) {
        $libraryFile = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) {
            continue
        }

        $libraryText = Get-Content -LiteralPath $libraryFile -Raw -Encoding UTF8
        foreach ($match in [Regex]::Matches($libraryText, '(?im)^\s*"path"\s+"([^"]+)"\s*$')) {
            $libraryRoot = $match.Groups[1].Value -replace '\\\\', '\'
            if (Test-Path -LiteralPath $libraryRoot -PathType Container) {
                $null = $roots.Add([System.IO.Path]::GetFullPath($libraryRoot))
            }
        }
    }

    return @($roots)
}

function Find-DawnwalkerSteamManifest {
    [CmdletBinding()]
    param([string]$AppId = '3751260')

    foreach ($libraryRoot in Get-DawnwalkerSteamLibraryRoots) {
        $candidate = Join-Path $libraryRoot "steamapps\appmanifest_$AppId.acf"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    throw "Steam app manifest appmanifest_$AppId.acf was not found in registered Steam libraries."
}

function Get-DawnwalkerMarkerHits {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][object[]]$Markers
    )

    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
        return @()
    }

    $hits = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in Get-ChildItem -LiteralPath $RootPath -Force -Recurse -ErrorAction Stop) {
        foreach ($markerValue in $Markers) {
            $marker = [string]$markerValue
            if ($entry.Name.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $hits.Add($entry.FullName)
                break
            }
        }
    }

    return @($hits | Sort-Object -Unique)
}

function Get-DawnwalkerRunningProcesses {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object[]]$ProcessNames)

    $matches = New-Object 'System.Collections.Generic.List[object]'
    foreach ($processNameValue in $ProcessNames) {
        $processName = [string]$processNameValue
        foreach ($process in @(Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
            $matches.Add([pscustomobject]@{
                name = $process.ProcessName
                id = $process.Id
                responding = $process.Responding
            })
        }
    }

    return $matches.ToArray()
}

function Test-DawnwalkerOfficialBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ContractPath,
        [string]$ManifestPath,
        [string]$GameInstallRoot,
        [switch]$RequireStopped
    )

    $contract = Read-DawnwalkerJsonFile -LiteralPath $ContractPath
    if ($contract.cyberfox1337x -ne 'function(dawnwalker_official_build_contract)') {
        throw 'The official-build contract signature is missing or invalid.'
    }

    if (-not $ManifestPath) {
        $ManifestPath = Find-DawnwalkerSteamManifest -AppId ([string]$contract.steam.appId)
    }
    $ManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Steam manifest not found: $ManifestPath"
    }

    $acfText = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    $manifestValues = [ordered]@{
        appId = Get-DawnwalkerAcfValue -AcfText $acfText -Name 'appid'
        name = Get-DawnwalkerAcfValue -AcfText $acfText -Name 'name'
        stateFlags = Get-DawnwalkerAcfValue -AcfText $acfText -Name 'StateFlags'
        installDir = Get-DawnwalkerAcfValue -AcfText $acfText -Name 'installdir'
        buildId = Get-DawnwalkerAcfValue -AcfText $acfText -Name 'buildid'
        targetBuildId = Get-DawnwalkerAcfValue -AcfText $acfText -Name 'TargetBuildID' -Optional
        sizeOnDisk = Get-DawnwalkerAcfValue -AcfText $acfText -Name 'SizeOnDisk'
        bytesToDownload = Get-DawnwalkerAcfValue -AcfText $acfText -Name 'BytesToDownload'
        bytesDownloaded = Get-DawnwalkerAcfValue -AcfText $acfText -Name 'BytesDownloaded'
        bytesToStage = Get-DawnwalkerAcfValue -AcfText $acfText -Name 'BytesToStage'
        bytesStaged = Get-DawnwalkerAcfValue -AcfText $acfText -Name 'BytesStaged'
    }

    if (-not $GameInstallRoot) {
        $steamAppsRoot = Split-Path -Parent $ManifestPath
        $GameInstallRoot = Join-Path (Join-Path $steamAppsRoot 'common') $manifestValues.installDir
    }
    $GameInstallRoot = [System.IO.Path]::GetFullPath($GameInstallRoot)
    $executablePath = Resolve-DawnwalkerSafeChildPath -RootPath $GameInstallRoot -RelativePath ([string]$contract.executable.relativePath)
    $win64Root = Split-Path -Parent $executablePath

    $identityErrors = New-Object 'System.Collections.Generic.List[string]'
    $warnings = New-Object 'System.Collections.Generic.List[string]'
    $expectedManifestValues = [ordered]@{
        appId = [string]$contract.steam.appId
        name = [string]$contract.steam.name
        stateFlags = [string]$contract.steam.stateFlags
        installDir = [string]$contract.steam.installDirName
        buildId = [string]$contract.steam.buildId
        sizeOnDisk = [string]$contract.steam.sizeOnDisk
        bytesToDownload = [string]$contract.steam.bytesToDownload
        bytesDownloaded = [string]$contract.steam.bytesDownloaded
        bytesToStage = [string]$contract.steam.bytesToStage
        bytesStaged = [string]$contract.steam.bytesStaged
    }

    foreach ($key in $expectedManifestValues.Keys) {
        if ([string]$manifestValues[$key] -cne [string]$expectedManifestValues[$key]) {
            $identityErrors.Add("Steam manifest $key mismatch: expected '$($expectedManifestValues[$key])', found '$($manifestValues[$key])'.")
        }
    }
    if ($manifestValues.targetBuildId -and ([string]$manifestValues.targetBuildId -cne [string]$contract.steam.buildId)) {
        $identityErrors.Add("Steam manifest TargetBuildID mismatch: expected '$($contract.steam.buildId)', found '$($manifestValues.targetBuildId)'.")
    }

    $executableEvidence = $null
    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
        $identityErrors.Add("Executable not found: $executablePath")
    }
    else {
        $executableItem = Get-Item -LiteralPath $executablePath
        $versionInfo = $executableItem.VersionInfo
        $signature = Get-AuthenticodeSignature -LiteralPath $executablePath
        $signerSubject = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { '' }
        $rawFileVersion = if ($versionInfo.FileVersionRaw) { $versionInfo.FileVersionRaw.ToString() } else { '' }
        $rawProductVersion = if ($versionInfo.ProductVersionRaw) { $versionInfo.ProductVersionRaw.ToString() } else { '' }
        $executableEvidence = [ordered]@{
            bytes = [int64]$executableItem.Length
            sha256 = Get-DawnwalkerSha256 -LiteralPath $executablePath
            rawFileVersion = $rawFileVersion
            rawProductVersion = $rawProductVersion
            productVersion = [string]$versionInfo.ProductVersion
            originalFilename = [string]$versionInfo.OriginalFilename
            signatureStatus = [string]$signature.Status
            signerSubject = $signerSubject
        }

        foreach ($key in @('bytes', 'sha256', 'rawFileVersion', 'rawProductVersion', 'productVersion', 'originalFilename', 'signatureStatus')) {
            if ([string]$executableEvidence[$key] -cne [string]$contract.executable.$key) {
                $identityErrors.Add("Executable $key mismatch: expected '$($contract.executable.$key)', found '$($executableEvidence[$key])'.")
            }
        }
        $signerFragment = [string]$contract.executable.signerSubjectContains
        if ($signerFragment -and $signerSubject.IndexOf($signerFragment, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            $identityErrors.Add("Executable signer does not contain the required publisher fragment '$signerFragment'.")
        }
    }

    foreach ($container in $contract.containers) {
        $containerPath = Resolve-DawnwalkerSafeChildPath -RootPath $GameInstallRoot -RelativePath ([string]$container.relativePath)
        if (-not (Test-Path -LiteralPath $containerPath -PathType Leaf)) {
            $identityErrors.Add("Locked container not found: $containerPath")
            continue
        }
        $actualLength = (Get-Item -LiteralPath $containerPath).Length
        if ([int64]$actualLength -ne [int64]$container.bytes) {
            $identityErrors.Add("Locked container size mismatch for '$($container.relativePath)': expected $($container.bytes), found $actualLength.")
        }
    }

    $repackHits = @(Get-DawnwalkerMarkerHits -RootPath $GameInstallRoot -Markers @($contract.safety.repackMarkers))
    $protectionHits = @(Get-DawnwalkerMarkerHits -RootPath $GameInstallRoot -Markers @($contract.safety.protectionMarkers))
    $conflictingProxyHits = New-Object 'System.Collections.Generic.List[string]'
    foreach ($proxyNameValue in $contract.safety.conflictingProxyNames) {
        $proxyPath = Join-Path $win64Root ([string]$proxyNameValue)
        if (Test-Path -LiteralPath $proxyPath) {
            $conflictingProxyHits.Add($proxyPath)
        }
    }
    $runningProcesses = @(Get-DawnwalkerRunningProcesses -ProcessNames @($contract.safety.processNames))

    if ($repackHits.Count -gt 0) {
        $identityErrors.Add('Repack or Steam-emulation filename markers were found; this workflow is refused.')
    }
    if ($protectionHits.Count -gt 0) {
        $identityErrors.Add('Anti-cheat or protection filename markers were found; this workflow is refused.')
    }
    if ($conflictingProxyHits.Count -gt 0) {
        $identityErrors.Add('Conflicting proxy loader filenames were found in the Win64 directory.')
    }
    if ($runningProcesses.Count -gt 0) {
        $warnings.Add('Dawnwalker is running. No loader installation, rollback, or dump preparation may run until it exits.')
    }
    if ($protectionHits.Count -eq 0) {
        $warnings.Add('No configured anti-cheat filename marker was found. This absence is not proof that no protection exists.')
    }

    $identityValid = $identityErrors.Count -eq 0
    $installationEligible = $identityValid -and $runningProcesses.Count -eq 0
    if ($RequireStopped -and $runningProcesses.Count -gt 0) {
        $identityErrors.Add('The -RequireStopped gate failed because Dawnwalker is running.')
        $installationEligible = $false
    }

    return [pscustomobject]@{
        cyberfox1337x = 'function(dawnwalker_official_build_verification)'
        checkedAtUtc = [DateTime]::UtcNow.ToString('o')
        identityValid = $identityValid
        installationEligible = $installationEligible
        gameRunning = $runningProcesses.Count -gt 0
        paths = [pscustomobject]@{
            manifest = $ManifestPath
            gameInstall = $GameInstallRoot
            executable = $executablePath
            win64 = $win64Root
        }
        manifest = [pscustomobject]$manifestValues
        executable = if ($executableEvidence) { [pscustomobject]$executableEvidence } else { $null }
        runningProcesses = $runningProcesses
        repackMarkerHits = @($repackHits)
        protectionMarkerHits = @($protectionHits)
        conflictingProxyHits = $conflictingProxyHits.ToArray()
        existingTargets = [pscustomobject]@{
            dwmapi = Test-Path -LiteralPath (Join-Path $win64Root 'dwmapi.dll')
            ue4ss = Test-Path -LiteralPath (Join-Path $win64Root 'ue4ss')
        }
        errors = $identityErrors.ToArray()
        warnings = $warnings.ToArray()
    }
}

function Test-DawnwalkerUe4ssArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ContractPath,
        [Parameter(Mandatory = $true)][string]$ArchivePath
    )

    $contract = Read-DawnwalkerJsonFile -LiteralPath $ContractPath
    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "UE4SS archive not found: $ArchivePath"
    }

    $archiveItem = Get-Item -LiteralPath $ArchivePath
    if ([int64]$archiveItem.Length -ne [int64]$contract.ue4ss.archiveBytes) {
        throw "UE4SS archive length mismatch: expected $($contract.ue4ss.archiveBytes), found $($archiveItem.Length)."
    }
    $archiveHash = Get-DawnwalkerSha256 -LiteralPath $ArchivePath
    if ($archiveHash -cne [string]$contract.ue4ss.archiveSha256) {
        throw "UE4SS archive SHA-256 mismatch: expected $($contract.ue4ss.archiveSha256), found $archiveHash."
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead([System.IO.Path]::GetFullPath($ArchivePath))
    try {
        $entryNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $ueHelpersEntries = @()
        foreach ($entry in $archive.Entries) {
            $normalizedName = $entry.FullName.Replace('\', '/')
            if ([string]::IsNullOrWhiteSpace($normalizedName)) {
                continue
            }
            if ($normalizedName.StartsWith('/') -or $normalizedName.Contains(':')) {
                throw "Unsafe rooted ZIP entry was refused: $normalizedName"
            }
            foreach ($segment in $normalizedName.Split('/')) {
                if ($segment -eq '..') {
                    throw "Unsafe parent traversal ZIP entry was refused: $normalizedName"
                }
            }
            $null = $entryNames.Add($normalizedName.TrimEnd('/'))
            if ($normalizedName.TrimEnd('/').Equals($script:DawnwalkerUEHelpersRelativePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $ueHelpersEntries += $entry
            }
        }

        foreach ($requiredEntryValue in $contract.ue4ss.requiredEntries) {
            $requiredEntry = ([string]$requiredEntryValue).Replace('\', '/').TrimEnd('/')
            if (-not $entryNames.Contains($requiredEntry)) {
                throw "Required UE4SS ZIP entry missing: $requiredEntry"
            }
        }

        if ($ueHelpersEntries.Count -ne 1) {
            throw "Pinned UE4SS archive must contain exactly one $($script:DawnwalkerUEHelpersRelativePath) entry; found $($ueHelpersEntries.Count)."
        }
        $ueHelpersEntry = $ueHelpersEntries[0]
        if ([int64]$ueHelpersEntry.Length -ne [int64]$script:DawnwalkerUEHelpersBytes) {
            throw "Pinned UEHelpers archive entry length mismatch: expected $($script:DawnwalkerUEHelpersBytes), found $($ueHelpersEntry.Length)."
        }
        $ueHelpersStream = $ueHelpersEntry.Open()
        try {
            $ueHelpersHasher = [System.Security.Cryptography.SHA256]::Create()
            try {
                $ueHelpersHash = ([System.BitConverter]::ToString($ueHelpersHasher.ComputeHash($ueHelpersStream))).Replace('-', '')
            }
            finally {
                $ueHelpersHasher.Dispose()
            }
        }
        finally {
            $ueHelpersStream.Dispose()
        }
        if ($ueHelpersHash -cne $script:DawnwalkerUEHelpersSha256) {
            throw "Pinned UEHelpers archive entry SHA-256 mismatch: expected $($script:DawnwalkerUEHelpersSha256), found $ueHelpersHash."
        }

        return [pscustomobject]@{
            cyberfox1337x = 'function(dawnwalker_ue4ss_payload_verification)'
            valid = $true
            path = [System.IO.Path]::GetFullPath($ArchivePath)
            bytes = [int64]$archiveItem.Length
            sha256 = $archiveHash
            entries = $archive.Entries.Count
            ueHelpers = [pscustomobject]@{
                relativePath = $script:DawnwalkerUEHelpersRelativePath
                bytes = [int64]$ueHelpersEntry.Length
                sha256 = $ueHelpersHash
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Get-DawnwalkerFileInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RootPath)

    if (-not (Test-Path -LiteralPath $RootPath)) {
        return @()
    }

    $rootItem = Get-Item -LiteralPath $RootPath
    if (-not $rootItem.PSIsContainer) {
        return @([pscustomobject]@{
            relativePath = $rootItem.Name
            bytes = [int64]$rootItem.Length
            sha256 = Get-DawnwalkerSha256 -LiteralPath $rootItem.FullName
        })
    }

    $normalizedRoot = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/')
    $inventory = foreach ($file in Get-ChildItem -LiteralPath $normalizedRoot -File -Force -Recurse | Sort-Object FullName) {
        [pscustomobject]@{
            relativePath = $file.FullName.Substring($normalizedRoot.Length).TrimStart('\', '/').Replace('\', '/')
            bytes = [int64]$file.Length
            sha256 = Get-DawnwalkerSha256 -LiteralPath $file.FullName
        }
    }
    return @($inventory)
}

function New-DawnwalkerPathSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$BackupPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        return [pscustomobject]@{
            targetPath = [System.IO.Path]::GetFullPath($TargetPath)
            kind = 'absent'
            backupPath = $null
            inventory = @()
        }
    }

    if (Test-Path -LiteralPath $BackupPath) {
        throw "Backup target already exists: $BackupPath"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $BackupPath) | Out-Null
    $targetItem = Get-Item -LiteralPath $TargetPath
    Copy-Item -LiteralPath $TargetPath -Destination $BackupPath -Recurse:$targetItem.PSIsContainer -Force

    return [pscustomobject]@{
        targetPath = [System.IO.Path]::GetFullPath($TargetPath)
        kind = if ($targetItem.PSIsContainer) { 'directory' } else { 'file' }
        backupPath = [System.IO.Path]::GetFullPath($BackupPath)
        inventory = @(Get-DawnwalkerFileInventory -RootPath $TargetPath)
    }
}

function Restore-DawnwalkerPathSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Snapshot)

    $targetPath = [System.IO.Path]::GetFullPath([string]$Snapshot.targetPath)
    if (Test-Path -LiteralPath $targetPath) {
        Remove-Item -LiteralPath $targetPath -Recurse -Force
    }

    if ([string]$Snapshot.kind -eq 'absent') {
        return
    }
    if (-not (Test-Path -LiteralPath ([string]$Snapshot.backupPath))) {
        throw "Snapshot backup is missing: $($Snapshot.backupPath)"
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetPath) | Out-Null
    $isDirectory = [string]$Snapshot.kind -eq 'directory'
    Copy-Item -LiteralPath ([string]$Snapshot.backupPath) -Destination $targetPath -Recurse:$isDirectory -Force
}

function Assert-DawnwalkerInventoryEqual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Expected,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Actual,
        [string]$Label = 'inventory'
    )

    $expectedJson = @($Expected | Sort-Object relativePath) | ConvertTo-Json -Depth 5 -Compress
    $actualJson = @($Actual | Sort-Object relativePath) | ConvertTo-Json -Depth 5 -Compress
    if ($expectedJson -cne $actualJson) {
        throw "$Label does not match the recorded SHA-256 inventory."
    }
}

function Get-DawnwalkerDefaultArchivePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Contract,
        [Parameter(Mandatory = $true)][string]$ContractPath
    )

    $contractRoot = Split-Path -Parent ([System.IO.Path]::GetFullPath($ContractPath))
    return Resolve-DawnwalkerSafeChildPath -RootPath $contractRoot -RelativePath ([string]$Contract.ue4ss.archiveRelativePath)
}

function New-DawnwalkerSafeStaging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ContractPath,
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$TemplatesRoot,
        [Parameter(Mandatory = $true)][string]$StagingRoot
    )

    $payload = Test-DawnwalkerUe4ssArchive -ContractPath $ContractPath -ArchivePath $ArchivePath
    if (Test-Path -LiteralPath $StagingRoot) {
        throw "Staging root must not already exist: $StagingRoot"
    }
    New-Item -ItemType Directory -Path $StagingRoot | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory([System.IO.Path]::GetFullPath($ArchivePath), [System.IO.Path]::GetFullPath($StagingRoot))

    $modsRoot = Resolve-DawnwalkerSafeChildPath -RootPath $StagingRoot -RelativePath 'ue4ss\Mods'
    foreach ($modDirectory in Get-ChildItem -LiteralPath $modsRoot -Directory -Force) {
        if ($modDirectory.Name -cne 'Keybinds' -and $modDirectory.Name -cne 'shared') {
            Remove-Item -LiteralPath $modDirectory.FullName -Recurse -Force
        }
    }
    $sharedRoot = Resolve-DawnwalkerSafeChildPath -RootPath $modsRoot -RelativePath 'shared'
    foreach ($sharedChild in Get-ChildItem -LiteralPath $sharedRoot -Force) {
        if (-not $sharedChild.PSIsContainer -or $sharedChild.Name -cne 'UEHelpers') {
            Remove-Item -LiteralPath $sharedChild.FullName -Recurse -Force
        }
    }
    $ueHelpersRoot = Resolve-DawnwalkerSafeChildPath -RootPath $sharedRoot -RelativePath 'UEHelpers'
    foreach ($ueHelpersChild in Get-ChildItem -LiteralPath $ueHelpersRoot -Force) {
        if ($ueHelpersChild.PSIsContainer -or $ueHelpersChild.Name -cne 'UEHelpers.lua') {
            Remove-Item -LiteralPath $ueHelpersChild.FullName -Recurse -Force
        }
    }
    $stagedUEHelpers = Test-DawnwalkerUEHelpersFile -LiteralPath (Join-Path $ueHelpersRoot 'UEHelpers.lua')
    if ($stagedUEHelpers.bytes -ne $payload.ueHelpers.bytes -or $stagedUEHelpers.sha256 -cne $payload.ueHelpers.sha256) {
        throw 'Sanitized staging did not preserve the exact pinned UEHelpers dependency.'
    }
    $modsJson = Resolve-DawnwalkerSafeChildPath -RootPath $modsRoot -RelativePath 'mods.json'
    if (Test-Path -LiteralPath $modsJson) {
        Remove-Item -LiteralPath $modsJson -Force
    }

    $settingsTemplate = Resolve-DawnwalkerSafeChildPath -RootPath $TemplatesRoot -RelativePath 'UE4SS-settings.ini'
    $modsTemplate = Resolve-DawnwalkerSafeChildPath -RootPath $TemplatesRoot -RelativePath 'Mods\mods.txt'
    foreach ($templatePath in @($settingsTemplate, $modsTemplate)) {
        if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
            throw "Required safe template missing: $templatePath"
        }
    }

    Copy-Item -LiteralPath $settingsTemplate -Destination (Join-Path $StagingRoot 'ue4ss\UE4SS-settings.ini') -Force
    Copy-Item -LiteralPath $modsTemplate -Destination (Join-Path $modsRoot 'mods.txt') -Force

    $settingsText = Get-Content -LiteralPath (Join-Path $StagingRoot 'ue4ss\UE4SS-settings.ini') -Raw
    $modsText = Get-Content -LiteralPath (Join-Path $modsRoot 'mods.txt') -Raw
    foreach ($requiredSetting in @(
        'UseCache = 0',
        'bUseUObjectArrayCache = false',
        'MajorVersion = 5',
        'MinorVersion = 5',
        'LoadAllAssetsBeforeDumpingObjects = 0',
        'LoadAllAssetsBeforeGeneratingCXXHeaders = 0',
        'EnableDumping = 0'
    )) {
        if ($settingsText.IndexOf($requiredSetting, [System.StringComparison]::Ordinal) -lt 0) {
            throw "Safe settings template is missing required value: $requiredSetting"
        }
    }
    if ($modsText -match '(?im)^\s*[^;\r\n]+\s*:\s*1\s*$') {
        throw 'A UE4SS mod is enabled in the inert smoke registry.'
    }
    foreach ($hookLine in [Regex]::Matches($settingsText, '(?im)^\s*Hook[^=\r\n]+\s*=\s*([^;\r\n]+)')) {
        if ($hookLine.Groups[1].Value.Trim() -ne '0') {
            throw "A UE4SS hook is enabled in the inert smoke profile: $($hookLine.Value.Trim())"
        }
    }

    return [pscustomobject]@{
        dwmapiPath = Join-Path $StagingRoot 'dwmapi.dll'
        ue4ssPath = Join-Path $StagingRoot 'ue4ss'
        inventory = @(Get-DawnwalkerFileInventory -RootPath $StagingRoot)
    }
}

function Invoke-DawnwalkerReflectionInstall {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)][string]$ContractPath,
        [string]$ArchivePath,
        [string]$TemplatesRoot,
        [string]$StateRoot,
        [string]$ManifestPath,
        [string]$GameInstallRoot,
        [string]$SavedRoot,
        [switch]$ReplaceExisting
    )

    $contract = Read-DawnwalkerJsonFile -LiteralPath $ContractPath
    $contractRoot = Split-Path -Parent ([System.IO.Path]::GetFullPath($ContractPath))
    if (-not $ArchivePath) { $ArchivePath = Get-DawnwalkerDefaultArchivePath -Contract $contract -ContractPath $ContractPath }
    if (-not $TemplatesRoot) { $TemplatesRoot = Join-Path $contractRoot 'templates' }
    if (-not $StateRoot) { $StateRoot = Join-Path $contractRoot 'state' }
    if (-not $SavedRoot) { $SavedRoot = Join-Path $env:LOCALAPPDATA 'Dawnwalker\Saved' }

    $verification = Test-DawnwalkerOfficialBuild -ContractPath $ContractPath -ManifestPath $ManifestPath -GameInstallRoot $GameInstallRoot -RequireStopped
    if (-not $verification.installationEligible) {
        throw "Dawnwalker is not eligible for reflection-tool installation: $($verification.errors -join ' ')"
    }
    $payload = Test-DawnwalkerUe4ssArchive -ContractPath $ContractPath -ArchivePath $ArchivePath

    $currentStatePath = Join-Path $StateRoot 'install-state.json'
    if (Test-Path -LiteralPath $currentStatePath) {
        throw "An active install state already exists. Roll it back first: $currentStatePath"
    }

    $targetDwmapi = Resolve-DawnwalkerSafeChildPath -RootPath $verification.paths.win64 -RelativePath 'dwmapi.dll'
    $targetUe4ss = Resolve-DawnwalkerSafeChildPath -RootPath $verification.paths.win64 -RelativePath 'ue4ss'
    if (((Test-Path -LiteralPath $targetDwmapi) -or (Test-Path -LiteralPath $targetUe4ss)) -and -not $ReplaceExisting) {
        throw 'A preexisting dwmapi.dll or ue4ss target exists. Re-run with -ReplaceExisting only after reviewing the backup plan.'
    }

    if (-not $PSCmdlet.ShouldProcess($verification.paths.win64, 'Back up saves and existing loader targets, then install the pinned sanitized zDEV reflection loader')) {
        return [pscustomobject]@{ installed = $false; whatIf = $true; verification = $verification; payload = $payload }
    }

    $transactionId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $transactionRoot = Join-Path (Join-Path $StateRoot 'backups') $transactionId
    $baselineRoot = Join-Path $transactionRoot 'baseline'
    $stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dawnwalker-reflection-$transactionId")
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
    if (-not ([System.IO.Path]::GetFullPath($stagingRoot)).StartsWith($tempRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refused an unsafe temporary staging path.'
    }

    New-Item -ItemType Directory -Force -Path $baselineRoot | Out-Null
    $saveSnapshot = New-DawnwalkerPathSnapshot -TargetPath $SavedRoot -BackupPath (Join-Path $baselineRoot 'Saved')
    $dwmapiSnapshot = New-DawnwalkerPathSnapshot -TargetPath $targetDwmapi -BackupPath (Join-Path $baselineRoot 'dwmapi.dll')
    $ue4ssSnapshot = New-DawnwalkerPathSnapshot -TargetPath $targetUe4ss -BackupPath (Join-Path $baselineRoot 'ue4ss')

    $state = [ordered]@{
        cyberfox1337x = 'function(dawnwalker_reflection_install_state)'
        schemaVersion = 1
        transactionId = $transactionId
        status = 'prepared'
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
        contractPath = [System.IO.Path]::GetFullPath($ContractPath)
        manifestPath = $verification.paths.manifest
        gameInstallRoot = $verification.paths.gameInstall
        win64Root = $verification.paths.win64
        executableSha256 = $verification.executable.sha256
        buildId = $verification.manifest.buildId
        archive = $payload
        saveBackup = $saveSnapshot
        targetBackups = @($dwmapiSnapshot, $ue4ssSnapshot)
        installedInventory = @()
    }
    Write-DawnwalkerJsonFile -InputObject $state -LiteralPath (Join-Path $transactionRoot 'transaction-state.json')

    $modifiedTargets = $false
    try {
        $staged = New-DawnwalkerSafeStaging -ContractPath $ContractPath -ArchivePath $ArchivePath -TemplatesRoot $TemplatesRoot -StagingRoot $stagingRoot
        $modifiedTargets = $true
        if (Test-Path -LiteralPath $targetDwmapi) { Remove-Item -LiteralPath $targetDwmapi -Recurse -Force }
        if (Test-Path -LiteralPath $targetUe4ss) { Remove-Item -LiteralPath $targetUe4ss -Recurse -Force }
        Copy-Item -LiteralPath $staged.dwmapiPath -Destination $targetDwmapi -Force
        Copy-Item -LiteralPath $staged.ue4ssPath -Destination $targetUe4ss -Recurse -Force

        $installedInventory = @(
            Get-DawnwalkerFileInventory -RootPath $targetDwmapi
            Get-DawnwalkerFileInventory -RootPath $targetUe4ss
        )
        $state.status = 'installed'
        $state.installedAtUtc = [DateTime]::UtcNow.ToString('o')
        $state.installedInventory = $installedInventory
        Write-DawnwalkerJsonFile -InputObject $state -LiteralPath (Join-Path $transactionRoot 'transaction-state.json')
        Write-DawnwalkerJsonFile -InputObject $state -LiteralPath $currentStatePath

        return [pscustomobject]@{
            cyberfox1337x = 'function(dawnwalker_reflection_install_result)'
            installed = $true
            transactionId = $transactionId
            statePath = $currentStatePath
            backupRoot = $transactionRoot
            saveBackupPath = $saveSnapshot.backupPath
            targets = @($targetDwmapi, $targetUe4ss)
        }
    }
    catch {
        if ($modifiedTargets) {
            Restore-DawnwalkerPathSnapshot -Snapshot $dwmapiSnapshot
            Restore-DawnwalkerPathSnapshot -Snapshot $ue4ssSnapshot
        }
        $state.status = 'failed-restored'
        $state.failure = $_.Exception.Message
        Write-DawnwalkerJsonFile -InputObject $state -LiteralPath (Join-Path $transactionRoot 'transaction-state.json')
        throw
    }
    finally {
        if (Test-Path -LiteralPath $stagingRoot) {
            Remove-Item -LiteralPath $stagingRoot -Recurse -Force
        }
    }
}

function Invoke-DawnwalkerReflectionRollback {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)][string]$ContractPath,
        [string]$StateRoot,
        [string]$ManifestPath,
        [string]$GameInstallRoot
    )

    $contractRoot = Split-Path -Parent ([System.IO.Path]::GetFullPath($ContractPath))
    if (-not $StateRoot) { $StateRoot = Join-Path $contractRoot 'state' }
    $currentStatePath = Join-Path $StateRoot 'install-state.json'
    $state = Read-DawnwalkerJsonFile -LiteralPath $currentStatePath
    if ($state.cyberfox1337x -ne 'function(dawnwalker_reflection_install_state)') {
        throw 'Install state signature is missing or invalid.'
    }

    $contract = Read-DawnwalkerJsonFile -LiteralPath $ContractPath
    $running = @(Get-DawnwalkerRunningProcesses -ProcessNames @($contract.safety.processNames))
    if ($running.Count -gt 0) {
        throw "Rollback refused while Dawnwalker is running (PID(s): $(($running.id) -join ', '))."
    }

    if (-not $ManifestPath) { $ManifestPath = Find-DawnwalkerSteamManifest -AppId ([string]$contract.steam.appId) }
    $acfText = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    $appId = Get-DawnwalkerAcfValue -AcfText $acfText -Name 'appid'
    $installDir = Get-DawnwalkerAcfValue -AcfText $acfText -Name 'installdir'
    if ($appId -cne [string]$contract.steam.appId -or $installDir -cne [string]$contract.steam.installDirName) {
        throw 'Rollback refused because the Steam app identity or install directory no longer matches the recorded product.'
    }
    if (-not $GameInstallRoot) {
        $GameInstallRoot = Join-Path (Join-Path (Split-Path -Parent $ManifestPath) 'common') $installDir
    }
    $expectedWin64 = Split-Path -Parent (Resolve-DawnwalkerSafeChildPath -RootPath $GameInstallRoot -RelativePath ([string]$contract.executable.relativePath))
    if (-not ([System.IO.Path]::GetFullPath($expectedWin64)).Equals([System.IO.Path]::GetFullPath([string]$state.win64Root), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Rollback refused because the recorded Win64 root differs from the current Steam install root.'
    }

    $targetDwmapi = Resolve-DawnwalkerSafeChildPath -RootPath $expectedWin64 -RelativePath 'dwmapi.dll'
    $targetUe4ss = Resolve-DawnwalkerSafeChildPath -RootPath $expectedWin64 -RelativePath 'ue4ss'
    $transactionId = [string]$state.transactionId
    if ($transactionId -notmatch '^\d{8}T\d{6}Z-[0-9a-f]{8}$') {
        throw "Rollback refused because the transaction identifier is invalid: $transactionId"
    }
    $backupsRoot = Join-Path $StateRoot 'backups'
    $transactionRoot = Resolve-DawnwalkerSafeChildPath -RootPath $backupsRoot -RelativePath $transactionId
    if (-not (Test-Path -LiteralPath $transactionRoot -PathType Container)) {
        throw "Rollback transaction directory not found: $transactionRoot"
    }
    $captureRoot = Join-Path $transactionRoot ('captured-before-rollback-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
    $transactionStatePath = Join-Path $transactionRoot 'transaction-state.json'
    $transactionStatePreviouslyExisted = Test-Path -LiteralPath $transactionStatePath -PathType Leaf
    $originalTransactionStateText = if ($transactionStatePreviouslyExisted) {
        Get-Content -LiteralPath $transactionStatePath -Raw -Encoding UTF8
    }
    else {
        $null
    }
    $historyRoot = Join-Path $StateRoot 'history'
    $historyPath = Join-Path $historyRoot ("$transactionId-rolled-back.json")
    if (Test-Path -LiteralPath $historyPath) {
        throw "Rollback history already exists for this active transaction: $historyPath"
    }

    if (-not $PSCmdlet.ShouldProcess($expectedWin64, 'Capture the current loader tree, remove it, and restore the exact preinstall target snapshots')) {
        return [pscustomobject]@{ rolledBack = $false; whatIf = $true; statePath = $currentStatePath }
    }

    $currentDwmapi = New-DawnwalkerPathSnapshot -TargetPath $targetDwmapi -BackupPath (Join-Path $captureRoot 'dwmapi.dll')
    $currentUe4ss = New-DawnwalkerPathSnapshot -TargetPath $targetUe4ss -BackupPath (Join-Path $captureRoot 'ue4ss')
    try {
        Restore-DawnwalkerPathSnapshot -Snapshot $state.targetBackups[0]
        Restore-DawnwalkerPathSnapshot -Snapshot $state.targetBackups[1]
        Assert-DawnwalkerInventoryEqual -Expected @($state.targetBackups[0].inventory) -Actual @(Get-DawnwalkerFileInventory -RootPath $targetDwmapi) -Label 'Restored dwmapi.dll'
        Assert-DawnwalkerInventoryEqual -Expected @($state.targetBackups[1].inventory) -Actual @(Get-DawnwalkerFileInventory -RootPath $targetUe4ss) -Label 'Restored ue4ss tree'

        $state.status = 'rolled-back'
        $state | Add-Member -NotePropertyName rolledBackAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
        $state | Add-Member -NotePropertyName captureBeforeRollback -NotePropertyValue @($currentDwmapi, $currentUe4ss) -Force
        New-Item -ItemType Directory -Force -Path $historyRoot | Out-Null
        Write-DawnwalkerJsonFile -InputObject $state -LiteralPath $historyPath
        Write-DawnwalkerJsonFile -InputObject $state -LiteralPath $transactionStatePath
        Remove-Item -LiteralPath $currentStatePath -Force
    }
    catch {
        Restore-DawnwalkerPathSnapshot -Snapshot $currentDwmapi
        Restore-DawnwalkerPathSnapshot -Snapshot $currentUe4ss
        if (Test-Path -LiteralPath $historyPath) {
            Remove-Item -LiteralPath $historyPath -Force
        }
        if ($transactionStatePreviouslyExisted) {
            [System.IO.File]::WriteAllText(
                $transactionStatePath,
                $originalTransactionStateText,
                [System.Text.UTF8Encoding]::new($false)
            )
        }
        elseif (Test-Path -LiteralPath $transactionStatePath) {
            Remove-Item -LiteralPath $transactionStatePath -Force
        }
        throw
    }

    return [pscustomobject]@{
        cyberfox1337x = 'function(dawnwalker_reflection_rollback_result)'
        rolledBack = $true
        transactionId = $state.transactionId
        historyPath = $historyPath
        captureBeforeRollback = $captureRoot
        savesRestored = $false
        saveBackupPath = $state.saveBackup.backupPath
    }
}

function Test-DawnwalkerBridgePilotPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ContractPath,
        [string]$TemplatesRoot,
        [string]$BridgeSourcePath
    )

    $contractRoot = Split-Path -Parent ([System.IO.Path]::GetFullPath($ContractPath))
    if (-not $TemplatesRoot) { $TemplatesRoot = Join-Path $contractRoot 'templates\bridge-pilot' }
    if (-not $BridgeSourcePath) {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $contractRoot)
        $BridgeSourcePath = Join-Path $projectRoot 'integration\uue4ss\Mods\DawnwalkerModBridge\Scripts\main.lua'
    }

    $settingsPath = Resolve-DawnwalkerSafeChildPath -RootPath $TemplatesRoot -RelativePath 'UE4SS-settings.ini'
    $modsPath = Resolve-DawnwalkerSafeChildPath -RootPath $TemplatesRoot -RelativePath 'Mods\mods.txt'
    $BridgeSourcePath = [System.IO.Path]::GetFullPath($BridgeSourcePath)
    foreach ($requiredFile in @($settingsPath, $modsPath, $BridgeSourcePath)) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "Required bridge-pilot file missing: $requiredFile"
        }
    }

    $settingsText = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8
    $requiredSettings = [ordered]@{
        ModsFolderPath = ''
        ControllingModsTxt = ''
        EnableHotReloadSystem = '0'
        EnableAutoReloadingLuaMods = '0'
        UseCache = '0'
        bUseUObjectArrayCache = 'false'
        bForceGUObjectArrayForIteration = 'true'
        DoEarlyScan = '0'
        DefaultExecuteInGameThreadMethod = 'EngineTick'
        MajorVersion = '5'
        MinorVersion = '5'
        LoadAllAssetsBeforeDumpingObjects = '0'
        LoadAllAssetsBeforeGeneratingCXXHeaders = '0'
        GuiConsoleEnabled = '0'
        GuiConsoleVisible = '0'
        EnableDumping = '0'
        FullMemoryDump = '0'
    }
    foreach ($requiredSettingName in $requiredSettings.Keys) {
        $settingPattern = '(?im)^[ \t]*' + [Regex]::Escape([string]$requiredSettingName) + '[ \t]*=[ \t]*([^;\r\n]*)'
        $settingMatches = [Regex]::Matches($settingsText, $settingPattern)
        if ($settingMatches.Count -ne 1) {
            throw "Bridge-pilot settings must contain exactly one '$requiredSettingName' assignment; found $($settingMatches.Count)."
        }
        $actualSettingValue = $settingMatches[0].Groups[1].Value.Trim()
        $expectedSettingValue = [string]$requiredSettings[$requiredSettingName]
        if ($actualSettingValue -cne $expectedSettingValue) {
            throw "Bridge-pilot setting invariant failed: $requiredSettingName must equal '$expectedSettingValue', found '$actualSettingValue'."
        }
    }

    $hookMatches = [Regex]::Matches($settingsText, '(?im)^\s*(Hook[^=\r\n]+)\s*=\s*([^;\r\n]+)')
    if ($hookMatches.Count -eq 0) {
        throw 'Bridge-pilot settings contain no explicit Hook* assignments.'
    }
    $approvedHookNames = @(
        'HookProcessInternal',
        'HookProcessLocalScriptFunction',
        'HookInitGameState',
        'HookLoadMap',
        'HookCallFunctionByNameWithArguments',
        'HookBeginPlay',
        'HookEndPlay',
        'HookLocalPlayerExec',
        'HookAActorTick',
        'HookEngineTick',
        'HookGameViewportClientTick',
        'HookUObjectProcessEvent',
        'HookProcessConsoleExec',
        'HookUStructLink'
    )
    $seenHooks = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($hookMatch in $hookMatches) {
        $hookName = $hookMatch.Groups[1].Value.Trim()
        $hookValue = $hookMatch.Groups[2].Value.Trim()
        if (-not $seenHooks.Add($hookName)) {
            throw "Bridge-pilot settings contain a duplicate hook assignment: $hookName"
        }
        $expectedValue = if ($hookName -ceq 'HookEngineTick') { '1' } else { '0' }
        if ($hookValue -cne $expectedValue) {
            throw "Bridge-pilot hook invariant failed: $hookName must equal $expectedValue, found $hookValue."
        }
    }
    $seenHookNames = @($seenHooks | Sort-Object)
    $expectedHookNames = @($approvedHookNames | Sort-Object)
    if (($seenHookNames -join ',') -cne ($expectedHookNames -join ',')) {
        throw "Bridge-pilot settings must explicitly contain only the approved Hook* assignments. Found: $($seenHookNames -join ', ')."
    }

    $modsText = Get-Content -LiteralPath $modsPath -Raw -Encoding UTF8
    $enabledMods = New-Object 'System.Collections.Generic.List[string]'
    $seenMods = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($registryLine in [Regex]::Split($modsText, '\r?\n')) {
        $trimmedRegistryLine = $registryLine.Trim()
        if (-not $trimmedRegistryLine -or $trimmedRegistryLine.StartsWith(';')) { continue }
        $modMatch = [Regex]::Match($trimmedRegistryLine, '^([^;\s][^:]*)\s*:\s*([01])$')
        if (-not $modMatch.Success) {
            throw "Bridge-pilot registry contains an invalid assignment: $trimmedRegistryLine"
        }
        $modName = $modMatch.Groups[1].Value.Trim()
        if (-not $seenMods.Add($modName)) {
            throw "Bridge-pilot registry contains a duplicate mod assignment: $modName"
        }
        if ($modMatch.Groups[2].Value -eq '1') { $enabledMods.Add($modName) }
    }
    if ($enabledMods.Count -ne 1 -or $enabledMods[0] -cne 'DawnwalkerModBridge') {
        throw "Only DawnwalkerModBridge may be enabled in the bridge pilot; enabled: $($enabledMods -join ', ')."
    }

    $bridgeItem = Get-Item -LiteralPath $BridgeSourcePath
    if ($bridgeItem.Length -lt 256 -or $bridgeItem.Length -gt 524288) {
        throw "Bridge source size is outside the approved 256-byte to 512-KiB range: $($bridgeItem.Length) bytes."
    }
    $bridgeText = Get-Content -LiteralPath $BridgeSourcePath -Raw -Encoding UTF8
    if ($bridgeText.IndexOf([char]0) -ge 0) {
        throw 'Bridge source contains a NUL byte.'
    }
    foreach ($requiredBridgeMarker in @(
        'cyberfox1337x.function_signature("dawnwalker_mod_bridge")',
        'local BRIDGE_PHASE = "pilot"',
        'local CAPABILITIES = table.concat(CAPABILITY_LIST, ",")',
        'EngineTickAvailable == true',
        'ExecuteInGameThread(function()',
        'if teardown_retry_pending or not game_thread_available or not player_ready then return "" end',
        'journal:GetOpenedQuests(opened_out)',
        'local opened_quests = opened_out',
        'opened_quests[index]',
        'player:GetInventoryComponent()',
        'subsystem:GetPlayerInventoryComponent()',
        'inventory:GetCurrencyQuantity(COIN_CURRENCY_TYPE)',
        'inventory:AddCurrency(COIN_CURRENCY_TYPE, requested)',
        'rollback_inventory:AddCurrency(COIN_CURRENCY_TYPE, -observed_delta)',
        'combat:rpg-difficulty',
        'combat:action-difficulty',
        'settings:GetSettingAsDifficulty(setting, output)',
        'record.subsystem:SetRPGDifficulty(record.baseline_rpg)',
        'record.subsystem:SetActionDifficulty(record.baseline_action)',
        'local teardown_retry_pending = false',
        'teardown_session_state("pending restore retry")',
        'retain_only_pending_active_state()',
        'unresolved restore state was retained instead of discarded'
    )) {
        if ($bridgeText.IndexOf($requiredBridgeMarker, [System.StringComparison]::Ordinal) -lt 0) {
            throw "Bridge source is missing the audited pilot marker: $requiredBridgeMarker"
        }
    }
    if ($bridgeText -notmatch '(?m)^local BRIDGE_VERSION = "[^"]*pilot[^"]*"\s*$') {
        throw 'Bridge source version is not explicitly pilot-scoped.'
    }
    foreach ($singleAssignment in @('BRIDGE_VERSION', 'BRIDGE_PHASE', 'CAPABILITIES')) {
        $assignmentCount = [Regex]::Matches($bridgeText, '(?m)^\s*local\s+' + $singleAssignment + '\s*=').Count
        if ($assignmentCount -ne 1) {
            throw "Bridge source must contain exactly one local $singleAssignment assignment; found $assignmentCount."
        }
    }
    $bridgeVersionMatch = [Regex]::Match($bridgeText, '(?m)^local BRIDGE_VERSION = "(?<version>[^"]+)"\s*$')
    $bridgeVersion = $bridgeVersionMatch.Groups['version'].Value
    if ($bridgeVersion -cne '0.3.21-pilot') {
        throw "Bridge source must identify the nil-return TMap-compatible two-axis difficulty, F9-enabled, teardown-safe, deferred-unblock-verified pilot version 0.3.21-pilot; found: $bridgeVersion"
    }
    foreach ($forbiddenBridgeMarker in @(
        'ProcessEventAvailable',
        'RegisterHook(',
        'NotifyOnNewObject(',
        'StaticConstructObject(',
        'StaticLoadObject(',
        'LoadAsset(',
        'player:unlimited-weight',
        'GE_EnableWeightLimitExceed',
        'RemoveActiveGameplayEffectBySourceEffect',
        'opened_out.OutQuests',
        'journal.OpenedQuests',
        'opened_quests:ForEach',
        'objectives:ForEach',
        'os.execute(',
        'io.popen(',
        'package.loadlib(',
        'dofile(',
        'loadfile('
    )) {
        if ($bridgeText.IndexOf($forbiddenBridgeMarker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "Bridge source contains a forbidden pilot marker: $forbiddenBridgeMarker"
        }
    }

    $capabilityBlock = [Regex]::Match($bridgeText, '(?s)local CAPABILITY_LIST\s*=\s*\{(?<body>.*?)\}')
    if (-not $capabilityBlock.Success) {
        throw 'Bridge source does not contain a literal CAPABILITY_LIST.'
    }
    $capabilities = @([Regex]::Matches($capabilityBlock.Groups['body'].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    foreach ($capability in $capabilities) {
        if ($capability -cnotmatch '^[a-z][a-z0-9-]*:[a-z][a-z0-9-]*$') {
            throw "Bridge source contains an invalid pilot capability token: $capability"
        }
    }
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
    if ($capabilities.Count -ne $approvedCapabilities.Count -or
        (@($capabilities | Sort-Object -Unique) -join ',') -cne (@($approvedCapabilities | Sort-Object) -join ',')) {
        throw "Bridge pilot capabilities differ from the nineteen audited controls: $($capabilities -join ',')."
    }

    return [pscustomobject]@{
        cyberfox1337x = 'function(dawnwalker_bridge_pilot_payload_result)'
        valid = $true
        settingsPath = [System.IO.Path]::GetFullPath($settingsPath)
        settingsSha256 = Get-DawnwalkerSha256 -LiteralPath $settingsPath
        modsPath = [System.IO.Path]::GetFullPath($modsPath)
        modsSha256 = Get-DawnwalkerSha256 -LiteralPath $modsPath
        bridgeSourcePath = $BridgeSourcePath
        bridgeSourceBytes = [int64]$bridgeItem.Length
        bridgeSourceSha256 = Get-DawnwalkerSha256 -LiteralPath $BridgeSourcePath
        bridgeVersion = $bridgeVersion
        capabilities = $capabilities
        enabledHooks = @('HookEngineTick')
        enabledMods = @('DawnwalkerModBridge')
    }
}

function Enable-DawnwalkerBridgePilot {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)][string]$ContractPath,
        [string]$StateRoot,
        [string]$PilotTemplatesRoot,
        [string]$SmokeLogPath,
        [string]$ManifestPath,
        [string]$GameInstallRoot,
        [switch]$ApproveCleanSmokeLog,
        [switch]$ApproveHookEngineTickPilot
    )

    if (-not $ApproveCleanSmokeLog) {
        throw 'Bridge-pilot promotion requires -ApproveCleanSmokeLog after a human reviews the fresh inert-smoke UE4SS.log.'
    }
    if (-not $ApproveHookEngineTickPilot) {
        throw 'Bridge-pilot promotion requires -ApproveHookEngineTickPilot to explicitly authorize the single HookEngineTick change.'
    }

    $contractRoot = Split-Path -Parent ([System.IO.Path]::GetFullPath($ContractPath))
    if (-not $StateRoot) { $StateRoot = Join-Path $contractRoot 'state' }
    if (-not $PilotTemplatesRoot) { $PilotTemplatesRoot = Join-Path $contractRoot 'templates\bridge-pilot' }
    $payload = Test-DawnwalkerBridgePilotPayload -ContractPath $ContractPath -TemplatesRoot $PilotTemplatesRoot
    $contract = Read-DawnwalkerJsonFile -LiteralPath $ContractPath
    $pinnedArchivePath = Get-DawnwalkerDefaultArchivePath -Contract $contract -ContractPath $ContractPath
    $pinnedArchive = Test-DawnwalkerUe4ssArchive -ContractPath $ContractPath -ArchivePath $pinnedArchivePath

    $currentStatePath = Join-Path $StateRoot 'install-state.json'
    $state = Read-DawnwalkerJsonFile -LiteralPath $currentStatePath
    if ($state.cyberfox1337x -ne 'function(dawnwalker_reflection_install_state)' -or $state.status -ne 'installed') {
        throw 'A valid active inert-smoke install state is required before bridge-pilot promotion.'
    }
    foreach ($promotionProperty in @('promotion', 'bridgePilot')) {
        if ($state.PSObject.Properties.Name -contains $promotionProperty) {
            throw "Bridge-pilot promotion requires an unpromoted inert-smoke transaction; state already contains '$promotionProperty'."
        }
    }
    $transactionId = [string]$state.transactionId
    if ($transactionId -notmatch '^\d{8}T\d{6}Z-[0-9a-f]{8}$') {
        throw "Bridge-pilot promotion refused because the transaction identifier is invalid: $transactionId"
    }

    $verification = Test-DawnwalkerOfficialBuild -ContractPath $ContractPath -ManifestPath $ManifestPath -GameInstallRoot $GameInstallRoot -RequireStopped
    if (-not $verification.installationEligible) {
        throw "Bridge-pilot promotion requires the exact stopped official build: $($verification.errors -join ' ')"
    }
    $expectedContractPath = [System.IO.Path]::GetFullPath($ContractPath)
    if (-not $expectedContractPath.Equals([System.IO.Path]::GetFullPath([string]$state.contractPath), [System.StringComparison]::OrdinalIgnoreCase) -or
        -not ([System.IO.Path]::GetFullPath([string]$verification.paths.win64)).Equals([System.IO.Path]::GetFullPath([string]$state.win64Root), [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]$verification.executable.sha256 -cne [string]$state.executableSha256 -or
        [string]$verification.manifest.buildId -cne [string]$state.buildId) {
        throw 'Bridge-pilot promotion refused because the active transaction no longer matches the verified build, contract, or Win64 root.'
    }

    $backupsRoot = Join-Path $StateRoot 'backups'
    $transactionRoot = Resolve-DawnwalkerSafeChildPath -RootPath $backupsRoot -RelativePath $transactionId
    $transactionStatePath = Join-Path $transactionRoot 'transaction-state.json'
    $transactionState = Read-DawnwalkerJsonFile -LiteralPath $transactionStatePath
    if ($transactionState.cyberfox1337x -ne 'function(dawnwalker_reflection_install_state)' -or
        [string]$transactionState.transactionId -cne $transactionId -or
        [string]$transactionState.status -cne 'installed') {
        throw 'The transaction-local state is not the matching installed inert-smoke transaction.'
    }
    foreach ($promotionProperty in @('promotion', 'bridgePilot')) {
        if ($transactionState.PSObject.Properties.Name -contains $promotionProperty) {
            throw "The transaction-local state is already promoted through '$promotionProperty'."
        }
    }
    if ((Get-DawnwalkerSha256 -LiteralPath $currentStatePath) -cne (Get-DawnwalkerSha256 -LiteralPath $transactionStatePath)) {
        throw 'The active and transaction-local inert-smoke state files are not byte-for-byte identical.'
    }

    $win64Root = [System.IO.Path]::GetFullPath([string]$state.win64Root)
    $targetDwmapi = Resolve-DawnwalkerSafeChildPath -RootPath $win64Root -RelativePath 'dwmapi.dll'
    $ue4ssRoot = Resolve-DawnwalkerSafeChildPath -RootPath $win64Root -RelativePath 'ue4ss'
    $targetSettings = Resolve-DawnwalkerSafeChildPath -RootPath $ue4ssRoot -RelativePath 'UE4SS-settings.ini'
    $targetMods = Resolve-DawnwalkerSafeChildPath -RootPath $ue4ssRoot -RelativePath 'Mods\mods.txt'
    $targetBridge = Resolve-DawnwalkerSafeChildPath -RootPath $ue4ssRoot -RelativePath 'Mods\DawnwalkerModBridge'
    $targetUEHelpers = Resolve-DawnwalkerSafeChildPath -RootPath $win64Root -RelativePath $script:DawnwalkerUEHelpersRelativePath
    $installedUEHelpers = Test-DawnwalkerUEHelpersFile -LiteralPath $targetUEHelpers
    if ($installedUEHelpers.bytes -ne $pinnedArchive.ueHelpers.bytes -or $installedUEHelpers.sha256 -cne $pinnedArchive.ueHelpers.sha256) {
        throw 'Installed UEHelpers dependency does not match the exact pinned archive entry.'
    }
    if (Test-Path -LiteralPath $targetBridge) {
        throw 'An exact inert-smoke transaction cannot already contain DawnwalkerModBridge.'
    }

    $smokeSettingsTemplate = Resolve-DawnwalkerSafeChildPath -RootPath (Join-Path $contractRoot 'templates') -RelativePath 'UE4SS-settings.ini'
    $smokeModsTemplate = Resolve-DawnwalkerSafeChildPath -RootPath (Join-Path $contractRoot 'templates') -RelativePath 'Mods\mods.txt'
    if ((Get-DawnwalkerSha256 -LiteralPath $targetSettings) -cne (Get-DawnwalkerSha256 -LiteralPath $smokeSettingsTemplate) -or
        (Get-DawnwalkerSha256 -LiteralPath $targetMods) -cne (Get-DawnwalkerSha256 -LiteralPath $smokeModsTemplate)) {
        throw 'The installed settings or mod registry no longer matches the exact inert-smoke templates.'
    }

    $expectedInventory = @($state.installedInventory | Where-Object { [string]$_.relativePath -cne 'UE4SS.log' })
    $currentInventory = @(
        Get-DawnwalkerFileInventory -RootPath $targetDwmapi
        Get-DawnwalkerFileInventory -RootPath $ue4ssRoot | Where-Object { [string]$_.relativePath -cne 'UE4SS.log' }
    )
    Assert-DawnwalkerInventoryEqual -Expected $expectedInventory -Actual $currentInventory -Label 'Current inert-smoke loader (excluding its runtime log)'

    $expectedLogPath = [System.IO.Path]::GetFullPath((Join-Path $ue4ssRoot 'UE4SS.log'))
    if (-not $SmokeLogPath) { $SmokeLogPath = $expectedLogPath }
    $SmokeLogPath = [System.IO.Path]::GetFullPath($SmokeLogPath)
    if (-not $SmokeLogPath.Equals($expectedLogPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Only the installed inert-smoke loader's UE4SS.log may satisfy the bridge-pilot gate: $expectedLogPath"
    }
    if (-not (Test-Path -LiteralPath $SmokeLogPath -PathType Leaf)) {
        throw "Fresh inert-smoke log not found: $SmokeLogPath"
    }
    $logItem = Get-Item -LiteralPath $SmokeLogPath
    $installedAt = ConvertTo-DawnwalkerUtcDateTime -Value $state.installedAtUtc
    $nowUtc = [DateTime]::UtcNow
    if ($logItem.LastWriteTimeUtc -le $installedAt) {
        throw 'The UE4SS.log is not newer than this inert-smoke install transaction.'
    }
    if ($logItem.LastWriteTimeUtc -lt $nowUtc.AddHours(-24) -or $logItem.LastWriteTimeUtc -gt $nowUtc.AddMinutes(5)) {
        throw 'The UE4SS.log is outside the approved fresh-log window (last 24 hours, with five minutes of clock skew).'
    }
    if ($logItem.Length -lt 32 -or $logItem.Length -gt 16777216) {
        throw "The UE4SS.log size is outside the approved 32-byte to 16-MiB range: $($logItem.Length) bytes."
    }
    $logText = Get-Content -LiteralPath $SmokeLogPath -Raw -Encoding UTF8
    if ($logText.IndexOf('UE4SS', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw 'The inert-smoke log does not identify UE4SS.'
    }
    if ($logText -match '(?im)(\[(?:error|fatal)\]|fatal error|unhandled exception|access violation|failed to initialize|stack overflow)') {
        throw 'The inert-smoke log contains an error, fatal, or startup-failure marker; bridge-pilot promotion is refused.'
    }
    $smokeLogSha256 = Get-DawnwalkerSha256 -LiteralPath $SmokeLogPath

    $running = @(Get-DawnwalkerRunningProcesses -ProcessNames @((Read-DawnwalkerJsonFile -LiteralPath $ContractPath).safety.processNames))
    if ($running.Count -gt 0) {
        throw "Bridge-pilot promotion refused because Dawnwalker started after verification (PID(s): $(($running.id) -join ', '))."
    }

    if (-not $PSCmdlet.ShouldProcess($ue4ssRoot, 'Snapshot every changed path, enable only HookEngineTick and DawnwalkerModBridge, and copy the current audited integration bridge')) {
        return [pscustomobject]@{
            cyberfox1337x = 'function(dawnwalker_bridge_pilot_preview_result)'
            promoted = $false
            whatIf = $true
            profile = 'hook-engine-tick-bridge-pilot'
            bridgeSourceSha256 = $payload.bridgeSourceSha256
            smokeLogSha256 = $smokeLogSha256
        }
    }

    foreach ($sourceInvariant in @(
        @{ path = $payload.settingsPath; sha256 = $payload.settingsSha256 },
        @{ path = $payload.modsPath; sha256 = $payload.modsSha256 },
        @{ path = $payload.bridgeSourcePath; sha256 = $payload.bridgeSourceSha256 }
    )) {
        if ((Get-DawnwalkerSha256 -LiteralPath $sourceInvariant.path) -cne [string]$sourceInvariant.sha256) {
            throw "A bridge-pilot source changed after validation: $($sourceInvariant.path)"
        }
    }

    if (Test-Path -LiteralPath $targetBridge) {
        throw 'DawnwalkerModBridge appeared after validation; bridge-pilot promotion is refused.'
    }
    foreach ($unchangedInvariant in @(
        @{ path = $targetSettings; sha256 = (Get-DawnwalkerSha256 -LiteralPath $smokeSettingsTemplate) },
        @{ path = $targetMods; sha256 = (Get-DawnwalkerSha256 -LiteralPath $smokeModsTemplate) },
        @{ path = $currentStatePath; sha256 = (Get-DawnwalkerSha256 -LiteralPath $transactionStatePath) },
        @{ path = $SmokeLogPath; sha256 = $smokeLogSha256 },
        @{ path = $targetUEHelpers; sha256 = $installedUEHelpers.sha256 }
    )) {
        if ((Get-DawnwalkerSha256 -LiteralPath $unchangedInvariant.path) -cne [string]$unchangedInvariant.sha256) {
            throw "A validated inert-smoke input changed before promotion: $($unchangedInvariant.path)"
        }
    }
    $finalInventory = @(
        Get-DawnwalkerFileInventory -RootPath $targetDwmapi
        Get-DawnwalkerFileInventory -RootPath $ue4ssRoot | Where-Object { [string]$_.relativePath -cne 'UE4SS.log' }
    )
    Assert-DawnwalkerInventoryEqual -Expected $expectedInventory -Actual $finalInventory -Label 'Final inert-smoke loader check (excluding its runtime log)'
    $running = @(Get-DawnwalkerRunningProcesses -ProcessNames @((Read-DawnwalkerJsonFile -LiteralPath $ContractPath).safety.processNames))
    if ($running.Count -gt 0) {
        throw "Bridge-pilot promotion refused because Dawnwalker started during confirmation (PID(s): $(($running.id) -join ', '))."
    }

    $promotionId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $promotionRoot = Join-Path (Join-Path $transactionRoot 'bridge-pilot-promotions') $promotionId
    $snapshots = @(
        New-DawnwalkerPathSnapshot -TargetPath $targetSettings -BackupPath (Join-Path $promotionRoot 'baseline\ue4ss\UE4SS-settings.ini')
        New-DawnwalkerPathSnapshot -TargetPath $targetMods -BackupPath (Join-Path $promotionRoot 'baseline\ue4ss\Mods\mods.txt')
        New-DawnwalkerPathSnapshot -TargetPath $targetBridge -BackupPath (Join-Path $promotionRoot 'baseline\ue4ss\Mods\DawnwalkerModBridge')
        New-DawnwalkerPathSnapshot -TargetPath $currentStatePath -BackupPath (Join-Path $promotionRoot 'baseline\state\install-state.json')
        New-DawnwalkerPathSnapshot -TargetPath $transactionStatePath -BackupPath (Join-Path $promotionRoot 'baseline\state\transaction-state.json')
    )

    try {
        Copy-Item -LiteralPath $payload.settingsPath -Destination $targetSettings -Force
        Copy-Item -LiteralPath $payload.modsPath -Destination $targetMods -Force
        $targetBridgeScript = Join-Path $targetBridge 'Scripts\main.lua'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetBridgeScript) | Out-Null
        Copy-Item -LiteralPath $payload.bridgeSourcePath -Destination $targetBridgeScript -Force

        $promotedPayload = Test-DawnwalkerBridgePilotPayload -ContractPath $ContractPath -TemplatesRoot $ue4ssRoot -BridgeSourcePath $targetBridgeScript
        if ($promotedPayload.settingsSha256 -cne $payload.settingsSha256 -or
            $promotedPayload.modsSha256 -cne $payload.modsSha256 -or
            $promotedPayload.bridgeSourceSha256 -cne $payload.bridgeSourceSha256) {
            throw 'Installed bridge-pilot bytes differ from their validated sources.'
        }

        $promotion = [pscustomobject]@{
            cyberfox1337x = 'function(dawnwalker_bridge_pilot_promotion)'
            promotionId = $promotionId
            profile = 'hook-engine-tick-bridge-pilot'
            promotedAtUtc = [DateTime]::UtcNow.ToString('o')
            smokeLogPath = $SmokeLogPath
            smokeLogBytes = [int64]$logItem.Length
            smokeLogSha256 = $smokeLogSha256
            bridgeSourcePath = $payload.bridgeSourcePath
            bridgeSourceSha256 = $payload.bridgeSourceSha256
            ueHelpersDependency = $installedUEHelpers
            capabilities = @($payload.capabilities)
            enabledHooks = @('HookEngineTick')
            enabledMods = @('DawnwalkerModBridge')
            backupRoot = $promotionRoot
            snapshots = $snapshots
            promotedInventory = @(
                Get-DawnwalkerFileInventory -RootPath $targetSettings
                Get-DawnwalkerFileInventory -RootPath $targetMods
                Get-DawnwalkerFileInventory -RootPath $targetBridge
            )
        }
        $state.status = 'bridge-pilot'
        $state | Add-Member -NotePropertyName bridgePilot -NotePropertyValue $promotion -Force
        Write-DawnwalkerJsonFile -InputObject $state -LiteralPath $currentStatePath
        Write-DawnwalkerJsonFile -InputObject $state -LiteralPath $transactionStatePath
    }
    catch {
        for ($snapshotIndex = $snapshots.Count - 1; $snapshotIndex -ge 0; $snapshotIndex--) {
            Restore-DawnwalkerPathSnapshot -Snapshot $snapshots[$snapshotIndex]
        }
        $failure = [pscustomobject]@{
            cyberfox1337x = 'function(dawnwalker_bridge_pilot_failure)'
            failedAtUtc = [DateTime]::UtcNow.ToString('o')
            error = $_.Exception.Message
            restored = $true
        }
        Write-DawnwalkerJsonFile -InputObject $failure -LiteralPath (Join-Path $promotionRoot 'failure.json')
        throw
    }

    return [pscustomobject]@{
        cyberfox1337x = 'function(dawnwalker_bridge_pilot_result)'
        promoted = $true
        profile = 'hook-engine-tick-bridge-pilot'
        promotionId = $promotionId
        promotionBackup = $promotionRoot
        bridgeSourceSha256 = $payload.bridgeSourceSha256
        ueHelpersSha256 = $installedUEHelpers.sha256
        smokeLogSha256 = $smokeLogSha256
        capabilities = @($payload.capabilities)
    }
}

function Enable-DawnwalkerDumpProfile {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)][string]$ContractPath,
        [string]$StateRoot,
        [string]$DumpTemplatesRoot,
        [string]$SmokeLogPath,
        [Parameter(Mandatory = $true)][switch]$ApproveCleanSmokeLog
    )

    if (-not $ApproveCleanSmokeLog) {
        throw 'Promotion requires -ApproveCleanSmokeLog after a human reviews the fresh inert-smoke UE4SS.log.'
    }

    $contractRoot = Split-Path -Parent ([System.IO.Path]::GetFullPath($ContractPath))
    if (-not $StateRoot) { $StateRoot = Join-Path $contractRoot 'state' }
    if (-not $DumpTemplatesRoot) { $DumpTemplatesRoot = Join-Path $contractRoot 'templates\dump' }
    $currentStatePath = Join-Path $StateRoot 'install-state.json'
    $state = Read-DawnwalkerJsonFile -LiteralPath $currentStatePath
    if ($state.cyberfox1337x -ne 'function(dawnwalker_reflection_install_state)' -or $state.status -ne 'installed') {
        throw 'A valid active inert-smoke install state is required before dump-profile promotion.'
    }

    $contract = Read-DawnwalkerJsonFile -LiteralPath $ContractPath
    $running = @(Get-DawnwalkerRunningProcesses -ProcessNames @($contract.safety.processNames))
    if ($running.Count -gt 0) {
        throw "Dump-profile promotion refused while Dawnwalker is running (PID(s): $(($running.id) -join ', '))."
    }

    $win64Root = [System.IO.Path]::GetFullPath([string]$state.win64Root)
    $ue4ssRoot = Resolve-DawnwalkerSafeChildPath -RootPath $win64Root -RelativePath 'ue4ss'
    if (-not $SmokeLogPath) { $SmokeLogPath = Join-Path $ue4ssRoot 'UE4SS.log' }
    $SmokeLogPath = [System.IO.Path]::GetFullPath($SmokeLogPath)
    $expectedLogPath = [System.IO.Path]::GetFullPath((Join-Path $ue4ssRoot 'UE4SS.log'))
    if (-not $SmokeLogPath.Equals($expectedLogPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Only the installed loader's UE4SS.log may satisfy the smoke gate: $expectedLogPath"
    }
    if (-not (Test-Path -LiteralPath $SmokeLogPath -PathType Leaf)) {
        throw "Smoke log not found: $SmokeLogPath"
    }

    $logItem = Get-Item -LiteralPath $SmokeLogPath
    $installedAt = ConvertTo-DawnwalkerUtcDateTime -Value $state.installedAtUtc
    if ($logItem.LastWriteTimeUtc -le $installedAt) {
        throw 'The UE4SS.log is not newer than this install transaction.'
    }
    $logText = Get-Content -LiteralPath $SmokeLogPath -Raw -Encoding UTF8
    if ($logText.Length -lt 32 -or $logText.IndexOf('UE4SS', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw 'The smoke log is empty or does not identify UE4SS.'
    }
    if ($logText -match '(?im)(fatal error|unhandled exception|access violation|failed to initialize)') {
        throw 'The smoke log contains a fatal/startup-failure marker; dump-profile promotion is refused.'
    }

    $settingsTemplate = Resolve-DawnwalkerSafeChildPath -RootPath $DumpTemplatesRoot -RelativePath 'UE4SS-settings.ini'
    $modsTemplate = Resolve-DawnwalkerSafeChildPath -RootPath $DumpTemplatesRoot -RelativePath 'Mods\mods.txt'
    $keybindTemplate = Resolve-DawnwalkerSafeChildPath -RootPath $DumpTemplatesRoot -RelativePath 'Mods\Keybinds\Scripts\main.lua'
    foreach ($template in @($settingsTemplate, $modsTemplate, $keybindTemplate)) {
        if (-not (Test-Path -LiteralPath $template -PathType Leaf)) {
            throw "Required promoted dump template missing: $template"
        }
    }

    $settingsText = Get-Content -LiteralPath $settingsTemplate -Raw
    $modsText = Get-Content -LiteralPath $modsTemplate -Raw
    foreach ($requiredSetting in @(
        'UseCache = 0',
        'bUseUObjectArrayCache = false',
        'bForceGUObjectArrayForIteration = true',
        'MajorVersion = 5',
        'MinorVersion = 5',
        'LoadAllAssetsBeforeDumpingObjects = 0',
        'LoadAllAssetsBeforeGeneratingCXXHeaders = 0',
        'UseModuleOffsets = 1',
        'GuiConsoleEnabled = 0',
        'GuiConsoleVisible = 0',
        'GraphicsAPI = opengl'
    )) {
        if ($settingsText.IndexOf($requiredSetting, [System.StringComparison]::Ordinal) -lt 0) {
            throw "Dump settings template is missing required value: $requiredSetting"
        }
    }
    if ($modsText -match '(?im)^\s*(?!Keybinds\s*:)[^;\r\n]+\s*:\s*1\s*$') {
        throw 'An action or optional mod is enabled in the promoted dump registry.'
    }
    foreach ($hookLine in [Regex]::Matches($settingsText, '(?im)^\s*Hook[^=\r\n]+\s*=\s*([^;\r\n]+)')) {
        if ($hookLine.Groups[1].Value.Trim() -ne '0') {
            throw "A UE4SS hook is enabled in the restricted metadata-dump profile: $($hookLine.Value.Trim())"
        }
    }
    if ($modsText -notmatch '(?im)^\s*Keybinds\s*:\s*1\s*$') {
        throw 'The restricted metadata-dump keybind dispatcher is not enabled in the promoted profile.'
    }

    $transactionRoot = Split-Path -Parent (Split-Path -Parent ([string]$state.saveBackup.backupPath))
    $promotionId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $promotionRoot = Join-Path (Join-Path $transactionRoot 'promotions') $promotionId
    $targetSettings = Resolve-DawnwalkerSafeChildPath -RootPath $ue4ssRoot -RelativePath 'UE4SS-settings.ini'
    $targetMods = Resolve-DawnwalkerSafeChildPath -RootPath $ue4ssRoot -RelativePath 'Mods\mods.txt'
    $targetKeybinds = Resolve-DawnwalkerSafeChildPath -RootPath $ue4ssRoot -RelativePath 'Mods\Keybinds'

    if (-not $PSCmdlet.ShouldProcess($ue4ssRoot, 'Back up the inert-smoke configuration and promote the restricted reflection-dump profile')) {
        return [pscustomobject]@{ promoted = $false; whatIf = $true; smokeLog = $SmokeLogPath }
    }

    $settingsSnapshot = New-DawnwalkerPathSnapshot -TargetPath $targetSettings -BackupPath (Join-Path $promotionRoot 'baseline\UE4SS-settings.ini')
    $modsSnapshot = New-DawnwalkerPathSnapshot -TargetPath $targetMods -BackupPath (Join-Path $promotionRoot 'baseline\Mods\mods.txt')
    $keybindSnapshot = New-DawnwalkerPathSnapshot -TargetPath $targetKeybinds -BackupPath (Join-Path $promotionRoot 'baseline\Mods\Keybinds')
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Join-Path $targetKeybinds 'Scripts\main.lua')) | Out-Null
        Copy-Item -LiteralPath $settingsTemplate -Destination $targetSettings -Force
        Copy-Item -LiteralPath $modsTemplate -Destination $targetMods -Force
        Copy-Item -LiteralPath $keybindTemplate -Destination (Join-Path $targetKeybinds 'Scripts\main.lua') -Force
    }
    catch {
        Restore-DawnwalkerPathSnapshot -Snapshot $settingsSnapshot
        Restore-DawnwalkerPathSnapshot -Snapshot $modsSnapshot
        Restore-DawnwalkerPathSnapshot -Snapshot $keybindSnapshot
        throw
    }

    $promotion = [pscustomobject]@{
        cyberfox1337x = 'function(dawnwalker_dump_profile_promotion)'
        promotedAtUtc = [DateTime]::UtcNow.ToString('o')
        smokeLogPath = $SmokeLogPath
        smokeLogBytes = [int64]$logItem.Length
        smokeLogSha256 = Get-DawnwalkerSha256 -LiteralPath $SmokeLogPath
        backupRoot = $promotionRoot
        snapshots = @($settingsSnapshot, $modsSnapshot, $keybindSnapshot)
        promotedInventory = @(
            Get-DawnwalkerFileInventory -RootPath $targetSettings
            Get-DawnwalkerFileInventory -RootPath $targetMods
            Get-DawnwalkerFileInventory -RootPath $targetKeybinds
        )
    }
    $state | Add-Member -NotePropertyName promotion -NotePropertyValue $promotion -Force
    Write-DawnwalkerJsonFile -InputObject $state -LiteralPath $currentStatePath
    Write-DawnwalkerJsonFile -InputObject $state -LiteralPath (Join-Path $transactionRoot 'transaction-state.json')

    return [pscustomobject]@{
        cyberfox1337x = 'function(dawnwalker_dump_profile_result)'
        promoted = $true
        profile = 'restricted-metadata-dump'
        promotionBackup = $promotionRoot
        smokeLogSha256 = $promotion.smokeLogSha256
    }
}

Export-ModuleMember -Function @(
    'Get-DawnwalkerSha256',
    'ConvertTo-DawnwalkerUtcDateTime',
    'Resolve-DawnwalkerSafeChildPath',
    'Read-DawnwalkerJsonFile',
    'Get-DawnwalkerAcfValue',
    'Find-DawnwalkerSteamManifest',
    'Test-DawnwalkerOfficialBuild',
    'Test-DawnwalkerUe4ssArchive',
    'Get-DawnwalkerFileInventory',
    'New-DawnwalkerPathSnapshot',
    'Restore-DawnwalkerPathSnapshot',
    'Assert-DawnwalkerInventoryEqual',
    'New-DawnwalkerSafeStaging',
    'Invoke-DawnwalkerReflectionInstall',
    'Invoke-DawnwalkerReflectionRollback',
    'Test-DawnwalkerBridgePilotPayload',
    'Enable-DawnwalkerBridgePilot',
    'Enable-DawnwalkerDumpProfile'
)
