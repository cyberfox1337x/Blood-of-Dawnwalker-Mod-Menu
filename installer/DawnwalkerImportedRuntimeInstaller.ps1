[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Status','VerifyPayload','Install','Repair','Uninstall','Preflight')][string]$Action,
    [string]$PayloadRoot,
    [string]$ApplicationVersion = '0.1.0'
)
if ([string]::IsNullOrWhiteSpace($PayloadRoot)) {
    $PayloadRoot = if (Test-Path (Join-Path $PSScriptRoot 'payload-manifest.json')) { $PSScriptRoot } else { Join-Path $PSScriptRoot 'current-runtime' }
}
$requestedAction = $Action
$sharedAction = if ($Action -eq 'Preflight') { 'Status' } else { $Action }
# The shared installer explicitly avoids its entry point when dot-sourced.
. (Join-Path $PSScriptRoot 'DawnwalkerRuntimeInstaller.ps1') -Action $sharedAction -PayloadRoot $PayloadRoot -ApplicationVersion $ApplicationVersion
$Action = $requestedAction
# PowerShell 7 callers may pass a PSModulePath that shadows Windows PowerShell modules.
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Security') -ErrorAction Stop
$null = cyberfox1337x -ModuleName 'dawnwalker_imported_runtime_installer'
$script:ExpectedBuildId = '25232147'
$script:ExpectedExecutableBytes = 176305016
$script:ExpectedExecutableSha256 = 'CB9B7D7BD88A6754C0A9C08318AA64D5013DDFD92D5BADCAE84E1B4EA980DCFC'
$script:DefaultStateRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'Cyberfox1337x\BloodOfDawnwalkerModMenu\ImportedRuntime'))
$script:StateRoot = $script:DefaultStateRoot
$script:StatePath = Join-Path $script:StateRoot 'install-state.json'
$script:BaselineRoot = Join-Path $script:StateRoot 'baseline'

function Assert-ImportedFile {
    param([string]$Root, $Entry, [string]$Path)
    $target = Get-SafeChildPath -Root $Root -RelativePath $Path
    if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or
        (Get-Item -LiteralPath $target).Length -ne [long]$Entry.bytes -or
        (Get-Sha256 -LiteralPath $target) -ne [string]$Entry.sha256) {
        throw "Imported runtime file identity mismatch: $Path"
    }
    return $target
}

function Read-PayloadMetadata {
    param([Parameter(Mandatory)][string]$Root, [switch]$SkipArchiveHash)
    $rootPath = [IO.Path]::GetFullPath($Root)
    $manifestPath = Join-Path $rootPath 'payload-manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.cyberfox1337x -ne 'function(dawnwalker_imported_installer_manifest)' -or
        $manifest.schemaVersion -ne 1 -or $manifest.phase -ne 'production' -or
        $manifest.bridgeVersion -ne 'imported-25232147' -or
        (@($manifest.gameplayCapabilities) -join ',') -ne 'imported:menu') { throw 'Invalid imported installer manifest identity.' }
    $contractPath = Assert-ImportedFile -Root $rootPath -Entry $manifest.officialBuildContract -Path $manifest.officialBuildContract.packagePath
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    Assert-ContractIdentity -Contract $contract
    if ($manifest.steamAppId -ne $contract.steam.appId -or $manifest.steamBuildId -ne $contract.steam.buildId -or
        $manifest.shippingExecutableSha256 -ne $contract.executable.sha256 -or $manifest.ue4ssRelease -ne $script:ExpectedUe4ssRelease) { throw 'Imported installer build identity mismatch.' }
    # Do not trust a payload-supplied lower archive hash, including in status checks.
    if ($manifest.ue4ssArchive.sha256 -ne $script:ExpectedArchiveSha256 -or
        [long]$manifest.ue4ssArchive.bytes -ne $script:ExpectedArchiveBytes) { throw 'Unreviewed UE4SS archive.' }
    $archivePath = Assert-ImportedFile -Root $rootPath -Entry $manifest.ue4ssArchive -Path $manifest.ue4ssArchive.packagePath
    $importedPath = Assert-ImportedFile -Root $rootPath -Entry $manifest.importedMenuManifest -Path $manifest.importedMenuManifest.packagePath
    $imported = Get-Content -LiteralPath $importedPath -Raw | ConvertFrom-Json
    if ($imported.schema -ne 1 -or $imported.buildId -ne $script:ExpectedBuildId -or @($imported.files).Count -ne 76) { throw 'Invalid imported menu source manifest.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @($manifest.payloadFiles)) {
        $path = Assert-AllowedRuntimePath -RelativePath $file.relativePath -Contract $contract
        if (-not $seen.Add($path) -or $file.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [long]$file.bytes -lt 0) { throw 'Invalid or duplicate payload file.' }
    }
    $overlayTargets = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($overlay in @($manifest.overlays)) {
        $path = Assert-AllowedRuntimePath -RelativePath $overlay.targetPath -Contract $contract
        if (-not $overlayTargets.Add($path)) { throw 'Duplicate imported overlay.' }
        $entry = Get-PayloadFileEntry -Manifest $manifest -RelativePath $path
        if ($overlay.sha256 -ne $entry.sha256) { throw 'Imported overlay metadata mismatch.' }
        [void](Assert-ImportedFile -Root $rootPath -Entry $entry -Path $overlay.packagePath)
    }
    $expectedTargets = @('ue4ss/UE4SS-settings.ini','ue4ss/Mods/mods.txt')
    foreach ($file in @($imported.files)) {
        # Resolve within the mod root before prefixing, rejecting traversal/absolute paths.
        [void](Get-SafeChildPath -Root (Join-Path $rootPath 'imported-check') -RelativePath $file.path)
        $path = 'ue4ss/Mods/DawnwalkerImportedMenu/' + $file.path.Replace('\','/')
        $entry = Get-PayloadFileEntry -Manifest $manifest -RelativePath $path
        if ($entry.sha256 -ne $file.sha256 -or [long]$entry.bytes -ne [long]$file.bytes) { throw 'Imported source manifest disagrees with installer files.' }
        $expectedTargets += $path
    }
    if (($expectedTargets | Sort-Object) -join "`n" -cne (($overlayTargets | Sort-Object) -join "`n")) { throw 'Imported overlay file set differs from the reviewed source.' }
    $dependencies = @($manifest.requiredRuntimeDependencies)
    if ($dependencies.Count -ne 1 -or $dependencies[0].relativePath -ne $script:RequiredUEHelpersRelativePath -or
        $dependencies[0].sha256 -ne $script:RequiredUEHelpersSha256 -or [long]$dependencies[0].bytes -ne $script:RequiredUEHelpersBytes) { throw 'Imported UEHelpers dependency mismatch.' }
    $requiredMods = @($manifest.requiredModRegistry | ForEach-Object { "$($_.name):$($_.value)" } | Sort-Object)
    if (($requiredMods -join ',') -cne 'DawnwalkerImportedMenu:1,DawnwalkerModBridge:0,Keybinds:0') { throw 'Imported mod enablement contract mismatch.' }
    $settings = @($manifest.requiredSettings)
    $settingKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($setting in $settings) {
        if (-not $settingKeys.Add("$($setting.section)/$($setting.key)")) { throw 'Duplicate imported setting.' }
        if ($setting.section -eq 'Hooks' -and $setting.value -eq '1' -and $setting.key -notin @('HookEngineTick','HookEndPlay')) { throw 'Unreviewed imported hook.' }
    }
    foreach ($hook in @('HookEngineTick','HookEndPlay')) {
        $entry = @($settings | Where-Object { $_.section -eq 'Hooks' -and $_.key -eq $hook })
        if ($entry.Count -ne 1 -or $entry[0].value -ne '1') { throw "Required imported hook missing: $hook" }
    }
    $settingsOverlay = @($manifest.overlays | Where-Object targetPath -EQ 'ue4ss/UE4SS-settings.ini')[0]
    $settingsPath = Get-SafeChildPath -Root $rootPath -RelativePath $settingsOverlay.packagePath
    foreach ($setting in $settings) {
        $actual = Get-IniValueState -LiteralPath $settingsPath -Section $setting.section -Key $setting.key
        if (-not $actual.present -or $actual.value -ne $setting.value) { throw 'Imported settings overlay disagrees with required settings.' }
    }
    $modsOverlay = @($manifest.overlays | Where-Object targetPath -EQ 'ue4ss/Mods/mods.txt')[0]
    $modsPath = Get-SafeChildPath -Root $rootPath -RelativePath $modsOverlay.packagePath
    foreach ($mod in @($manifest.requiredModRegistry)) {
        $actual = Get-ModRegistryValueState -LiteralPath $modsPath -Name $mod.name
        if (-not $actual.present -or $actual.value -ne $mod.value) { throw 'Imported mod registry disagrees with required entries.' }
    }
    return [pscustomobject]@{root=$rootPath;manifestPath=$manifestPath;manifest=$manifest;contractPath=$contractPath;contract=$contract;archivePath=$archivePath}
}
if ($MyInvocation.InvocationName -ne '.') {
    if ($Action -in @('Install','Repair','Preflight')) {
        $legacyState = Join-Path $env:ProgramData 'Cyberfox1337x/BloodOfDawnwalkerModMenu/Runtime/install-state.json'
        if (Test-Path -LiteralPath $legacyState) { throw 'A legacy managed runtime is installed. Uninstall that legacy runtime before installing the current product; its backup ownership must not overlap.' }
    }
    if ($Action -eq 'Preflight') {
        $contract = Get-Content (Join-Path $PayloadRoot 'official-build.json') -Raw | ConvertFrom-Json
        Assert-ContractIdentity -Contract $contract
        Assert-GameStopped -Contract $contract
        $game = Get-OfficialGameInstall -Contract $contract -RequireExactBuild
        Assert-EligibleInstall -GameInstall $game -Contract $contract
        'Current game build and closed-process preflight passed.'
    } else { Invoke-DawnwalkerRuntimeInstaller }
}
