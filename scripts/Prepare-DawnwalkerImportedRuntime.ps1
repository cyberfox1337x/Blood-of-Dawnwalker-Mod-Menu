[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$installerRoot = Join-Path $projectRoot 'installer'
$outputRoot = Join-Path $installerRoot 'current-runtime'
. (Join-Path $installerRoot 'DawnwalkerImportedRuntimeInstaller.ps1') -Action VerifyPayload -PayloadRoot $outputRoot
$null = cyberfox1337x -ModuleName 'prepare_dawnwalker_imported_runtime'
$sourceRoot = Join-Path $projectRoot 'integration/imported-menu'
$sourceManifest = Get-Content (Join-Path $sourceRoot 'manifest.json') -Raw | ConvertFrom-Json
$currentContract = Get-Content (Join-Path $sourceRoot 'official-build.json') -Raw | ConvertFrom-Json
if ($currentContract.steam.buildId -ne $script:ExpectedBuildId -or $sourceManifest.buildId -ne $script:ExpectedBuildId -or
    $currentContract.executable.sha256 -ne $script:ExpectedExecutableSha256 -or @($sourceManifest.files).Count -ne 76) { throw 'Current source does not match the reviewed installer build.' }
$legacyRoot = Join-Path $installerRoot 'runtime'
$legacyManifest = Get-Content (Join-Path $legacyRoot 'payload-manifest.json') -Raw | ConvertFrom-Json
$archiveSource = Get-SafeChildPath -Root $legacyRoot -RelativePath $legacyManifest.ue4ssArchive.packagePath
if ((Get-Sha256 $archiveSource) -ne $script:ExpectedArchiveSha256 -or (Get-Item $archiveSource).Length -ne $script:ExpectedArchiveBytes) { throw 'Pinned archive is unavailable or corrupt.' }
$contract = Get-Content (Join-Path $legacyRoot 'official-build.json') -Raw | ConvertFrom-Json
$contract.PSObject.Properties.Remove('capturedAtUtc')
$contract.purpose = 'Current imported-menu installer exact-build contract. Acceptance and release readiness are separate hash-bound evidence.'
$contract.steam.buildId = $currentContract.steam.buildId
$contract.executable.sha256 = $currentContract.executable.sha256
$contract.executable.bytes = $currentContract.executable.bytes
$contract.executable.productVersion = 'dw1-pc-258504-shipping-patch2-all-CL-258504'
$contract.knownCurrentState = [pscustomobject]@{ limitations=@('Pinned UE4SS is experimental. See current release acceptance evidence for startup stability and supported effects.') }
# Omit obsolete point-in-time depot/container fields; never present old sizes as current.
$contract.PSObject.Properties.Remove('containers')
foreach ($field in @('sizeOnDisk','bytesToDownload','bytesDownloaded','bytesToStage','bytesStaged','depotId','depotManifest')) { $contract.steam.PSObject.Properties.Remove($field) }
Assert-ContractIdentity $contract
$null = New-Item -ItemType Directory -Path $outputRoot -Force
$archiveTarget = Get-SafeChildPath -Root $outputRoot -RelativePath $legacyManifest.ue4ssArchive.packagePath
$null = New-Item -ItemType Directory -Path (Split-Path $archiveTarget) -Force
Copy-Item -LiteralPath $archiveSource -Destination $archiveTarget -Force
$contractPath = Join-Path $outputRoot 'official-build.json'
$contract | ConvertTo-Json -Depth 20 | Set-Content $contractPath -Encoding utf8
$importedManifestPath = Join-Path $outputRoot 'imported-menu-manifest.json'
Copy-Item (Join-Path $sourceRoot 'manifest.json') $importedManifestPath -Force
$stagingParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$stagingRoot = [IO.Path]::GetFullPath((Join-Path $stagingParent ('dawnwalker-imported-prep-' + [guid]::NewGuid().ToString('N'))))
if (-not $stagingRoot.StartsWith($stagingParent, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe staging path.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$overlays = @()
try {
    # Archive has an exact pinned SHA-256; validate every destination before extraction.
    $archive = [IO.Compression.ZipFile]::OpenRead($archiveSource)
    try { foreach ($entry in $archive.Entries) {
        if ($entry.FullName) {
            [void](Get-SafeChildPath -Root $stagingRoot -RelativePath $entry.FullName)
            [void](Assert-AllowedRuntimePath -RelativePath $entry.FullName -Contract $contract)
        }
    } } finally { $archive.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($archiveSource, $stagingRoot)
    foreach ($file in $sourceManifest.files) {
        $source = Assert-ImportedFile -Root (Join-Path $sourceRoot 'Mods/DawnwalkerImportedMenu') -Entry $file -Path $file.path
        $relative = 'ue4ss/Mods/DawnwalkerImportedMenu/' + $file.path.Replace('\','/')
        $target = Get-SafeChildPath -Root $stagingRoot -RelativePath $relative
        $null = New-Item -ItemType Directory -Path (Split-Path $target) -Force
        Copy-Item -LiteralPath $source -Destination $target -Force
        $overlays += $relative
    }
    $settingsPath = Join-Path $stagingRoot 'ue4ss/UE4SS-settings.ini'
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content (Join-Path $installerRoot 'templates/ue4ss/UE4SS-settings.ini')) { $lines.Add($line) }
    $lines[0] = '; cyberfox1337x.function("dawnwalker_imported_runtime_settings")'
    $lines[1] = '; Current imported runtime; required EngineTick and EndPlay hooks.'
    $lines[2] = '; Live acceptance is separate from installer payload integrity.'
    Set-IniValue -Lines $lines -Section Hooks -Key HookEngineTick -Value '1'
    Set-IniValue -Lines $lines -Section Hooks -Key HookEndPlay -Value '1'
    Set-Content -LiteralPath $settingsPath -Value $lines -Encoding utf8
    $requiredSettings = @()
    $section = ''
    foreach ($line in $lines) {
        if ($line -match '^\[([^\]]+)\]') { $section = $Matches[1] }
        elseif ($line -match '^([^;#=]+?)\s*=\s*(.*)$') {
            $requiredSettings += [pscustomobject]@{section=$section;key=$Matches[1].Trim();value=$Matches[2].Trim()}
        }
    }
    $modsPath = Join-Path $stagingRoot 'ue4ss/Mods/mods.txt'
    @('; cyberfox1337x.function("dawnwalker_imported_mod_registry")','DawnwalkerImportedMenu : 1','DawnwalkerModBridge : 0','Keybinds : 0') | Set-Content $modsPath -Encoding utf8
    $overlays += @('ue4ss/UE4SS-settings.ini','ue4ss/Mods/mods.txt')
    $overlayEntries = @()
    foreach ($relative in $overlays) {
        $source = Get-SafeChildPath -Root $stagingRoot -RelativePath $relative
        $packagePath = 'overrides/' + $relative
        $destination = Get-SafeChildPath -Root $outputRoot -RelativePath $packagePath
        $null = New-Item -ItemType Directory -Path (Split-Path $destination) -Force
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $overlayEntries += [pscustomobject]@{targetPath=$relative;packagePath=$packagePath;sha256=(Get-Sha256 $source)}
    }
    $files = @(Get-ChildItem $stagingRoot -File -Recurse | Sort-Object FullName | ForEach-Object {
        [pscustomobject]@{relativePath=$_.FullName.Substring($stagingRoot.Length+1).Replace('\','/');bytes=$_.Length;sha256=(Get-Sha256 $_.FullName)}
    })
    $manifest = [ordered]@{
        cyberfox1337x='function(dawnwalker_imported_installer_manifest)';schemaVersion=1
        applicationVersion=(Get-Content (Join-Path $projectRoot 'package.json') -Raw | ConvertFrom-Json).version
        phase='production';bridgeVersion='imported-25232147';gameplayCapabilities=@('imported:menu')
        steamAppId='3751260';steamBuildId=$script:ExpectedBuildId;shippingExecutableSha256=$script:ExpectedExecutableSha256
        officialBuildContract=@{packagePath='official-build.json';bytes=(Get-Item $contractPath).Length;sha256=(Get-Sha256 $contractPath)}
        importedMenuManifest=@{packagePath='imported-menu-manifest.json';bytes=(Get-Item $importedManifestPath).Length;sha256=(Get-Sha256 $importedManifestPath)}
        ue4ssRelease=$script:ExpectedUe4ssRelease;ue4ssArchive=$legacyManifest.ue4ssArchive
        requiredRuntimeDependencies=$legacyManifest.requiredRuntimeDependencies
        conflictingProxyNames=$contract.safety.conflictingProxyNames
        allowedWriteTargetsRelativeToWin64=$contract.safety.allowedWriteTargetsRelativeToWin64
        requiredSettings=$requiredSettings
        requiredModRegistry=@(@{name='DawnwalkerImportedMenu';value='1'},@{name='DawnwalkerModBridge';value='0'},@{name='Keybinds';value='0'})
        overlays=$overlayEntries;payloadFiles=$files
    }
    $manifest | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $outputRoot 'payload-manifest.json') -Encoding utf8
    $null = Read-PayloadMetadata -Root $outputRoot
    "Prepared $($files.Count) current runtime files; live release evidence remains separately required."
} finally {
    if (Test-Path -LiteralPath $stagingRoot -PathType Container) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
}
