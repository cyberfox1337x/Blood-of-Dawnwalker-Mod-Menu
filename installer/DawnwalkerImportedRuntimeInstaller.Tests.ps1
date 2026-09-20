[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
function cyberfox1337x.function([string]$Name) { return $Name }
$null = cyberfox1337x.function 'imported_runtime_installer_tests'
$helper = Join-Path $PSScriptRoot 'DawnwalkerImportedRuntimeInstaller.ps1'
. $helper -Action VerifyPayload
if ($script:ExpectedBuildId -ne '25232147') { throw 'Current installer does not pin the accepted build.' }
if ($script:DefaultStateRoot -notmatch 'ImportedRuntime$') { throw 'Current installer shares legacy ownership state.' }
$metadata = Read-PayloadMetadata -Root (Join-Path $PSScriptRoot 'current-runtime')
if (@($metadata.manifest.overlays | Where-Object targetPath -Like 'ue4ss/Mods/DawnwalkerImportedMenu/*').Count -ne 76) { throw 'Imported payload coverage is incomplete.' }
$wrong = $metadata.contract | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$wrong.steam.buildId = '25107392'
$rejected = $false
try { Assert-ContractIdentity -Contract $wrong } catch { $rejected = $true }
if (-not $rejected) { throw 'Wrong build accepted.' }
$staged = New-ValidatedPayloadStaging -Root $metadata.root
try {
    $settings = Join-Path $staged.root 'ue4ss/UE4SS-settings.ini'
    if ((Get-IniValueState -LiteralPath $settings -Section Hooks -Key HookEndPlay).value -ne '1') { throw 'Shutdown hook absent.' }
    if ((Get-IniValueState -LiteralPath $settings -Section Hooks -Key HookEngineTick).value -ne '1') { throw 'Tick hook absent.' }
} finally { Remove-ValidatedPayloadStaging -Payload $staged }
'Current imported runtime identity, coverage, hooks, and staging passed.'

# Exercise only a disposable fake Steam tree. Never invoke live discovery/install.
$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$fixture = [IO.Path]::GetFullPath((Join-Path $temporaryParent ('dawnwalker-imported-tests-' + [guid]::NewGuid().ToString('N'))))
if (-not $fixture.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture path.' }
$originalStateRoot = $script:StateRoot
$originalStatePath = $script:StatePath
$originalBaselineRoot = $script:BaselineRoot
$payload = New-ValidatedPayloadStaging -Root $metadata.root
try {
    $script:StateRoot = Join-Path $fixture 'ownership'
    $script:StatePath = Join-Path $script:StateRoot 'install-state.json'
    $script:BaselineRoot = Join-Path $script:StateRoot 'baseline'
    $steamApps = Join-Path $fixture 'steamapps'
    $gameRoot = Join-Path $steamApps 'common/The Blood of Dawnwalker'
    $win64 = Join-Path $gameRoot 'Dawnwalker/Binaries/Win64'
    $null = New-Item -ItemType Directory -Path (Join-Path $win64 'ue4ss/Mods/DawnwalkerImportedMenu/Scripts') -Force
    Copy-Item (Join-Path $payload.root 'dwmapi.dll') (Join-Path $win64 'dwmapi.dll')
    Copy-Item (Join-Path $payload.root 'ue4ss/UE4SS.dll') (Join-Path $win64 'ue4ss/UE4SS.dll')
    $settings = Join-Path $win64 'ue4ss/UE4SS-settings.ini'
    @('[Hooks]','HookEndPlay = 0','[Unrelated]','Keep = yes') | Set-Content $settings
    $mods = Join-Path $win64 'ue4ss/Mods/mods.txt'
    @('OtherUserMod : 1','DawnwalkerImportedMenu : 0') | Set-Content $mods
    $main = Join-Path $win64 'ue4ss/Mods/DawnwalkerImportedMenu/Scripts/main.lua'
    Set-Content $main 'original user mod baseline'
    $baselineHash = Get-Sha256 $main
    $manifest = Join-Path $steamApps 'appmanifest_3751260.acf'
    '"appid" "3751260" "buildid" "25232147" "StateFlags" "4" "installdir" "The Blood of Dawnwalker"' | Set-Content $manifest
    $fakeGame = [pscustomobject]@{manifestPath=$manifest;buildId='25232147';installPath=$gameRoot;win64Path=$win64;executableSha256=$script:ExpectedExecutableSha256}
    $script:OriginalAtomicCopy = (Get-Item Function:Copy-FileAtomically).ScriptBlock
    $script:FaultCopyCount = 0
    function Copy-FileAtomically {
        param([string]$SourcePath, [string]$DestinationPath, [string]$ExpectedSha256)
        $script:FaultCopyCount++
        if ($script:FaultCopyCount -eq 2) { throw 'Injected second-copy failure' }
        & $script:OriginalAtomicCopy -SourcePath $SourcePath -DestinationPath $DestinationPath -ExpectedSha256 $ExpectedSha256
    }
    $failedAsExpected = $false
    try { Install-Runtime -GameInstall $fakeGame -Payload $payload | Out-Null }
    catch { if ($_.Exception.Message -notmatch 'Injected second-copy failure') { throw }; $failedAsExpected = $true }
    finally { Set-Item Function:Copy-FileAtomically $script:OriginalAtomicCopy }
    if (-not $failedAsExpected -or (Get-Sha256 $main) -ne $baselineHash -or (Test-Path $script:StatePath)) { throw 'Failed deployment did not roll back the original runtime.' }
    Install-Runtime -GameInstall $fakeGame -Payload $payload | Out-Null
    if ((Get-Sha256 $main) -eq $baselineHash) { throw 'Imported install did not replace the baseline.' }
    if ((Get-ModRegistryValueState $mods 'OtherUserMod').value -ne '1') { throw 'Unrelated mod was altered.' }
    if ((Get-IniValueState $settings Hooks HookEndPlay).value -ne '1') { throw 'Install did not enable EndPlay.' }
    Add-Content $settings @('[LaterUserSetting]','Keep = yes')
    Add-Content $mods 'LaterUserMod : 1'
    Set-Content $main 'simulated corruption'
    Repair-Runtime -GameInstall $fakeGame -Payload $payload | Out-Null
    if ((Get-Sha256 $main) -ne (Get-Sha256 (Join-Path $payload.root 'ue4ss/Mods/DawnwalkerImportedMenu/Scripts/main.lua'))) { throw 'Repair did not recover imported payload.' }
    Uninstall-Runtime -GameInstall $fakeGame | Out-Null
    if ((Get-Sha256 $main) -ne $baselineHash) { throw 'Uninstall did not restore original user mod.' }
    if ((Get-IniValueState $settings Hooks HookEndPlay).value -ne '0') { throw 'Uninstall did not restore original hook.' }
    if ((Get-IniValueState $settings LaterUserSetting Keep).value -ne 'yes') { throw 'Uninstall removed later unrelated setting.' }
    if ((Get-ModRegistryValueState $mods 'LaterUserMod').value -ne '1') { throw 'Uninstall removed later unrelated mod.' }
    if (Test-Path $script:StatePath) { throw 'Uninstall left ownership state.' }
    # A metadata mutation is rejected before any game-facing write.
    $malformed = Join-Path $fixture 'malformed-payload'
    Copy-Item -LiteralPath $metadata.root -Destination $malformed -Recurse
    $manifestFile = Join-Path $malformed 'payload-manifest.json'
    $originalManifest = Get-Content $manifestFile -Raw
    foreach ($mutation in @('duplicate-overlay','missing-shutdown-hook','wrong-source-build','unapproved-mod')) {
        $changed = $originalManifest | ConvertFrom-Json
        switch ($mutation) {
            'duplicate-overlay' { $changed.overlays += $changed.overlays[0] }
            'missing-shutdown-hook' { $changed.requiredSettings = @($changed.requiredSettings | Where-Object key -NE 'HookEndPlay') }
            'wrong-source-build' { $changed.steamBuildId = '25107392' }
            'unapproved-mod' { $changed.requiredModRegistry += [pscustomobject]@{name='OtherMod';value='1'} }
        }
        $changed | ConvertTo-Json -Depth 20 | Set-Content $manifestFile -Encoding utf8
        $rejected = $false
        try { $null = Read-PayloadMetadata -Root $malformed } catch { $rejected = $true }
        if (-not $rejected) { throw "Malformed imported metadata accepted: $mutation" }
    }
    'Current install/repair/restore, injected failure rollback, unrelated-edit preservation, and four malformed-payload rejections passed.'
} finally {
    $script:StateRoot = $originalStateRoot
    $script:StatePath = $originalStatePath
    $script:BaselineRoot = $originalBaselineRoot
    Remove-ValidatedPayloadStaging -Payload $payload
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
