[CmdletBinding(DefaultParameterSetName = 'Installer')]
param(
    [Parameter(ParameterSetName = 'Installer')]
    [string]$InstallerPath,

    [Parameter(ParameterSetName = 'Installer')]
    [string]$ReleaseDirectory,

    [Parameter(Mandatory, ParameterSetName = 'Extracted')]
    [string]$ExtractedApplicationRoot,

    [Parameter(Mandatory)]
    [ValidateSet('discovery', 'production')]
    [string]$ExpectedPhase
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory)][string]$ModuleName)
    return $ModuleName
}

$null = cyberfox1337x -ModuleName 'assert_dawnwalker_packaged_installer'

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

function Get-FileInventory {
    param([Parameter(Mandatory)][string]$Root)

    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
        throw "Inventory root is missing: $resolvedRoot"
    }
    $reparsePoints = @(Get-ChildItem -LiteralPath $resolvedRoot -Force -Recurse | Where-Object {
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    })
    if ($reparsePoints.Count -gt 0) {
        throw "Runtime inventory contains a reparse point: $($reparsePoints[0].FullName)"
    }

    return @(
        Get-ChildItem -LiteralPath $resolvedRoot -Force -File -Recurse |
            ForEach-Object {
                [ordered]@{
                    relativePath = $_.FullName.Substring($resolvedRoot.Length + 1).Replace('\', '/')
                    bytes = [long]$_.Length
                    sha256 = Get-Sha256 -LiteralPath $_.FullName
                }
            } |
            Sort-Object relativePath
    )
}

function Assert-InventoryEqual {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Expected,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Actual
    )

    $expectedByPath = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $actualByPath = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($entry in $Expected) {
        $relativePath = [string]($entry.relativePath)
        if ($expectedByPath.ContainsKey($relativePath)) { throw "Expected runtime inventory contains a duplicate path: $relativePath" }
        $expectedByPath.Add($relativePath, $entry)
    }
    foreach ($entry in $Actual) {
        $relativePath = [string]($entry.relativePath)
        if ($actualByPath.ContainsKey($relativePath)) { throw "Packaged runtime inventory contains a duplicate path: $relativePath" }
        $actualByPath.Add($relativePath, $entry)
    }
    $missing = @($expectedByPath.Keys | Where-Object { -not $actualByPath.ContainsKey($_) })
    $unexpected = @($actualByPath.Keys | Where-Object { -not $expectedByPath.ContainsKey($_) })
    $changed = @(
        foreach ($relativePath in $expectedByPath.Keys) {
            if (-not $actualByPath.ContainsKey($relativePath)) { continue }
            $expectedEntry = $expectedByPath[$relativePath]
            $actualEntry = $actualByPath[$relativePath]
            if ([long]($actualEntry.bytes) -ne [long]($expectedEntry.bytes) -or
                [string]($actualEntry.sha256) -cne [string]($expectedEntry.sha256)) {
                $relativePath
            }
        }
    )
    if ($missing.Count -gt 0 -or $unexpected.Count -gt 0 -or $changed.Count -gt 0 -or
        $Expected.Count -ne $Actual.Count) {
        throw "Packaged runtime inventory differs from the exact prepared payload (expected $($Expected.Count), actual $($Actual.Count)). Missing: $($missing -join ', '). Unexpected: $($unexpected -join ', '). Changed: $($changed -join ', ')."
    }
}

function Get-SevenZipPath {
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $candidates = @(
        (Join-Path $ProjectRoot 'node_modules\7zip-bin\win\x64\7za.exe'),
        (Join-Path $ProjectRoot 'node_modules\electron-winstaller\vendor\7z.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    foreach ($commandName in @('7z.exe', '7z')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command -and $command.Source) { return [IO.Path]::GetFullPath($command.Source) }
    }
    throw '7-Zip is required to inspect the completed NSIS installer, but no approved executable was found.'
}

function Expand-SevenZipArchive {
    param(
        [Parameter(Mandatory)][string]$SevenZipPath,
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$OutputDirectory
    )

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $SevenZipPath x '-y' ("-o$OutputDirectory") $ArchivePath 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    if ($exitCode -ne 0) {
        $details = ($output | Out-String).Trim()
        if ($details.Length -gt 2000) { $details = $details.Substring($details.Length - 2000) }
        throw "7-Zip could not extract '$ArchivePath' (exit $exitCode): $details"
    }
}

function Assert-PackageConfiguration {
    param([Parameter(Mandatory)]$PackageManifest)

    if ($PackageManifest.cyberfox1337x -ne 'function(package_manifest)') {
        throw 'Package manifest signature is missing or invalid.'
    }
    $targets = @($PackageManifest.build.win.target)
    if ($targets.Count -ne 1 -or [string]$targets[0].target -cne 'nsis' -or
        @($targets[0].arch).Count -ne 1 -or [string]$targets[0].arch[0] -cne 'x64') {
        throw 'Windows packaging must expose exactly one NSIS x64 target.'
    }
    if ($PackageManifest.build.PSObject.Properties.Name -contains 'portable') {
        throw 'Portable packaging is forbidden because its runtime-install behavior has not been proven.'
    }
    if ([string]$PackageManifest.build.nsis.artifactName -cne '${productName}-Setup-${version}-${arch}.${ext}') {
        throw 'The NSIS artifact name no longer matches the locked Setup naming contract.'
    }
}

function Assert-RuntimeManifest {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$ApplicationVersion,
        [Parameter(Mandatory)][string]$Phase
    )

    if ($Manifest.cyberfox1337x -ne 'function(dawnwalker_runtime_payload_manifest)' -or $Manifest.schemaVersion -ne 1) {
        throw 'Packaged runtime manifest signature or schema is invalid.'
    }
    if ([string]$Manifest.applicationVersion -cne $ApplicationVersion) {
        throw "Packaged runtime application version does not match package.json: $($Manifest.applicationVersion)"
    }
    if ([string]$Manifest.phase -cne $Phase) {
        throw "Packaged runtime phase '$($Manifest.phase)' does not match required phase '$Phase'."
    }
    if ([string]$Manifest.phase -eq 'pilot') {
        throw 'A bridge pilot must never be packaged as a release payload.'
    }

    $capabilities = @($Manifest.gameplayCapabilities)
    $seenCapabilities = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($capabilityValue in $capabilities) {
        $capability = [string]$capabilityValue
        if ($capability -notmatch '^[a-z][a-z0-9-]*:[a-z][a-z0-9-]*$' -or -not $seenCapabilities.Add($capability)) {
            throw "Packaged runtime contains an invalid or duplicate capability: $capability"
        }
    }
    if ($Phase -eq 'production' -and $capabilities.Count -eq 0) {
        throw 'A production installer cannot contain an empty capability manifest.'
    }
    if ($Phase -eq 'discovery' -and $capabilities.Count -ne 0) {
        throw 'A discovery installer cannot contain gameplay capabilities.'
    }
}

function Test-ExtractedApplication {
    param(
        [Parameter(Mandatory)][string]$ApplicationRoot,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)]$PackageManifest,
        [Parameter(Mandatory)][string]$Phase
    )

    $resolvedApplicationRoot = [IO.Path]::GetFullPath($ApplicationRoot)
    if (-not (Test-Path -LiteralPath $resolvedApplicationRoot -PathType Container)) {
        throw "Extracted application root is missing: $resolvedApplicationRoot"
    }
    $sourceRuntimeRoot = Join-Path $ProjectRoot 'installer\runtime'
    $sourceHelperPath = Join-Path $ProjectRoot 'installer\DawnwalkerRuntimeInstaller.ps1'
    $packagedRuntimeRoot = Join-Path $resolvedApplicationRoot 'resources\dawnwalker-runtime'
    $packagedHelperPath = Join-Path $packagedRuntimeRoot 'DawnwalkerRuntimeInstaller.ps1'
    $packagedManifestPath = Join-Path $packagedRuntimeRoot 'payload-manifest.json'
    foreach ($requiredFile in @($sourceHelperPath, $packagedHelperPath, $packagedManifestPath)) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "Required runtime package file is missing: $requiredFile"
        }
    }

    $expectedInventory = [Collections.Generic.List[object]]::new()
    foreach ($entry in Get-FileInventory -Root $sourceRuntimeRoot) { $expectedInventory.Add($entry) }
    $expectedInventory.Add([ordered]@{
        relativePath = 'DawnwalkerRuntimeInstaller.ps1'
        bytes = [long](Get-Item -LiteralPath $sourceHelperPath).Length
        sha256 = Get-Sha256 -LiteralPath $sourceHelperPath
    })
    $actualInventory = @(Get-FileInventory -Root $packagedRuntimeRoot)
    Assert-InventoryEqual -Expected @($expectedInventory) -Actual $actualInventory

    $manifest = Get-Content -LiteralPath $packagedManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-RuntimeManifest -Manifest $manifest -ApplicationVersion ([string]$PackageManifest.version) -Phase $Phase

    $windowsPowerShell = Get-Command powershell.exe -ErrorAction Stop
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $verificationOutput = @(& $windowsPowerShell.Source -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
            -File $packagedHelperPath -Action VerifyPayload -PayloadRoot $packagedRuntimeRoot `
            -ApplicationVersion ([string]$PackageManifest.version) 2>&1)
        $verificationExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    if ($verificationExitCode -ne 0) {
        throw "The packaged runtime helper rejected its own payload (exit $verificationExitCode): $(($verificationOutput | Out-String).Trim())"
    }
    $verificationText = ($verificationOutput | Out-String).Trim()
    if ($verificationText -notmatch ('Verified\s+\d+\s+' + [Regex]::Escape($Phase) + '-phase runtime payload files')) {
        throw "The packaged runtime helper did not emit its verified-payload result: $verificationText"
    }

    return [pscustomobject]@{
        cyberfox1337x = 'function(dawnwalker_packaged_runtime_validation)'
        valid = $true
        phase = $Phase
        applicationVersion = [string]$PackageManifest.version
        runtimeFiles = $actualInventory.Count
        manifestSha256 = Get-Sha256 -LiteralPath $packagedManifestPath
        helperSha256 = Get-Sha256 -LiteralPath $packagedHelperPath
        verification = $verificationText
    }
}

$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$packageManifestPath = Join-Path $projectRoot 'package.json'
$packageManifest = Get-Content -LiteralPath $packageManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-PackageConfiguration -PackageManifest $packageManifest

if ($PSCmdlet.ParameterSetName -eq 'Extracted') {
    Test-ExtractedApplication -ApplicationRoot $ExtractedApplicationRoot -ProjectRoot $projectRoot `
        -PackageManifest $packageManifest -Phase $ExpectedPhase | ConvertTo-Json -Depth 5
    return
}

if (-not $ReleaseDirectory) { $ReleaseDirectory = Join-Path $projectRoot 'release' }
$resolvedReleaseDirectory = [IO.Path]::GetFullPath($ReleaseDirectory)
if (-not (Test-Path -LiteralPath $resolvedReleaseDirectory -PathType Container)) {
    throw "Release directory is missing: $resolvedReleaseDirectory"
}
$expectedArtifactName = "$($packageManifest.build.productName)-Setup-$($packageManifest.version)-x64.exe"
$expectedInstallerPath = Join-Path $resolvedReleaseDirectory $expectedArtifactName
if (-not $InstallerPath) { $InstallerPath = $expectedInstallerPath }
$resolvedInstallerPath = [IO.Path]::GetFullPath($InstallerPath)
if (-not $resolvedInstallerPath.Equals([IO.Path]::GetFullPath($expectedInstallerPath), [StringComparison]::OrdinalIgnoreCase)) {
    throw "Only the locked NSIS Setup artifact may be validated: $expectedInstallerPath"
}
$topLevelExecutables = @(Get-ChildItem -LiteralPath $resolvedReleaseDirectory -File -Filter '*.exe')
if ($topLevelExecutables.Count -ne 1 -or
    -not $topLevelExecutables[0].FullName.Equals($resolvedInstallerPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Release output must contain exactly one top-level executable, the locked NSIS Setup artifact. Found: $($topLevelExecutables.Name -join ', ')."
}
$installerItem = Get-Item -LiteralPath $resolvedInstallerPath
if ($installerItem.Length -lt 1048576 -or ($installerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'The NSIS installer is unexpectedly small or is a reparse point.'
}
$header = [byte[]]::new(2)
$installerStream = [IO.File]::OpenRead($resolvedInstallerPath)
try {
    $headerBytesRead = $installerStream.Read($header, 0, $header.Length)
}
finally {
    $installerStream.Dispose()
}
if ($headerBytesRead -ne 2 -or $header[0] -ne 0x4D -or $header[1] -ne 0x5A) {
    throw 'The NSIS installer does not have a Windows PE header.'
}

$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$temporaryRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('dawnwalker-package-validation-' + [Guid]::NewGuid().ToString('N'))))
if (-not $temporaryRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing unsafe package-validation staging path: $temporaryRoot"
}
$outerRoot = Join-Path $temporaryRoot 'outer'
$applicationRoot = Join-Path $temporaryRoot 'application'
$sevenZipPath = Get-SevenZipPath -ProjectRoot $projectRoot

try {
    Expand-SevenZipArchive -SevenZipPath $sevenZipPath -ArchivePath $resolvedInstallerPath -OutputDirectory $outerRoot
    $applicationArchives = @(Get-ChildItem -LiteralPath $outerRoot -File -Recurse -Filter 'app-*.7z')
    if ($applicationArchives.Count -ne 1 -or $applicationArchives[0].Name -cne 'app-64.7z') {
        throw "NSIS installer must contain exactly one x64 application archive named app-64.7z. Found: $($applicationArchives.Name -join ', ')."
    }
    Expand-SevenZipArchive -SevenZipPath $sevenZipPath -ArchivePath $applicationArchives[0].FullName -OutputDirectory $applicationRoot
    $result = Test-ExtractedApplication -ApplicationRoot $applicationRoot -ProjectRoot $projectRoot `
        -PackageManifest $packageManifest -Phase $ExpectedPhase
    $result | Add-Member -NotePropertyName installerPath -NotePropertyValue $resolvedInstallerPath
    $result | Add-Member -NotePropertyName installerBytes -NotePropertyValue ([long]$installerItem.Length)
    $result | Add-Member -NotePropertyName installerSha256 -NotePropertyValue (Get-Sha256 -LiteralPath $resolvedInstallerPath)
    $result | ConvertTo-Json -Depth 5
}
finally {
    $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
    if (Test-Path -LiteralPath $resolvedTemporaryRoot) {
        if (-not $resolvedTemporaryRoot.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unsafe package-validation staging path: $resolvedTemporaryRoot"
        }
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
    }
}
