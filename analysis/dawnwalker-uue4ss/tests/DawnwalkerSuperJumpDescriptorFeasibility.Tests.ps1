[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function cyberfox1337x {
    param([Parameter(Mandatory)][string]$ModuleName)
    $null = $ModuleName
}
cyberfox1337x 'dawnwalker_super_jump_descriptor_feasibility_tests'

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Label
    )
    if (-not $Condition) { throw "Assertion failed: $Label" }
}

$kitRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = Split-Path -Parent (Split-Path -Parent $kitRoot)
$probePath = Join-Path $kitRoot 'probes\DawnwalkerSuperJumpDescriptorReadOnlyProbe.lua'
$luaHarnessPath = Join-Path $PSScriptRoot 'DawnwalkerSuperJumpDescriptorReadOnlyProbe.Tests.lua'
$notePath = Join-Path $kitRoot 'SUPER-JUMP-DESCRIPTOR-PROBE.md'
$buildPath = Join-Path $kitRoot 'official-build.json'
$uhtRoot = Join-Path $kitRoot 'captured-dump\2026-09-02-uht-incomplete\UHTHeaderDump'
$objectDumpPath = Join-Path $kitRoot 'captured-dump\2026-09-02-object-dump\UE4SS_ObjectDump.txt'

foreach ($requiredPath in @($probePath, $luaHarnessPath, $notePath, $buildPath, $objectDumpPath)) {
    Assert-True (Test-Path -LiteralPath $requiredPath -PathType Leaf) "required artifact exists: $requiredPath"
}

$build = Get-Content -LiteralPath $buildPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($build.steam.buildId -ceq '25014996') 'probe research remains pinned to Steam build 25014996'
Assert-True ($build.steam.depotManifest -ceq '116071877880222957') 'probe research remains pinned to the exact depot manifest'
Assert-True ($build.executable.bytes -eq 176484216) 'probe research remains pinned to the exact executable length'
Assert-True ($build.executable.sha256 -ceq '31D6271093358CA859C5D98CD5BF226113285FED41532F3B76881DDA7BE8278A') 'probe research remains pinned to the exact executable hash'

$playerHeader = Get-Content -LiteralPath (Join-Path $uhtRoot 'Dawnwalker\Public\DawnwalkerPlayerCharacter.h') -Raw -Encoding UTF8
$controllerHeader = Get-Content -LiteralPath (Join-Path $uhtRoot 'Dawnwalker\Public\DawnwalkerPlayerControllerBase.h') -Raw -Encoding UTF8
$engineControllerHeader = Get-Content -LiteralPath (Join-Path $uhtRoot 'Engine\Public\Controller.h') -Raw -Encoding UTF8
$pawnHeader = Get-Content -LiteralPath (Join-Path $uhtRoot 'Engine\Public\Pawn.h') -Raw -Encoding UTF8
$attributeHeader = Get-Content -LiteralPath (Join-Path $uhtRoot 'DogwoodStats\Public\PlayerMovementAttributeSet.h') -Raw -Encoding UTF8
$ascHeader = Get-Content -LiteralPath (Join-Path $uhtRoot 'GameplayAbilities\Public\AbilitySystemComponent.h') -Raw -Encoding UTF8
$effectHeader = Get-Content -LiteralPath (Join-Path $uhtRoot 'GameplayAbilities\Public\GameplayEffect.h') -Raw -Encoding UTF8
$modifierInfoHeader = Get-Content -LiteralPath (Join-Path $uhtRoot 'GameplayAbilities\Public\GameplayModifierInfo.h') -Raw -Encoding UTF8

Assert-True ($playerHeader.Contains('UPlayerMovementAttributeSet* MovementAttributeSet;')) 'player exposes the exact direct MovementAttributeSet'
Assert-True ($controllerHeader.Contains('ADawnwalkerPlayerCharacter* PossessedCharacter;')) 'controller exposes the game-specific possession crosscheck'
Assert-True ($engineControllerHeader.Contains('APawn* K2_GetPawn() const;')) 'controller exposes the reflected pawn getter'
Assert-True ($engineControllerHeader.Contains('bool IsLocalPlayerController() const;')) 'controller exposes the reflected local-player identity check'
Assert-True ($pawnHeader.Contains('AController* GetController() const;')) 'pawn exposes the reflected controller getter'
Assert-True ($attributeHeader.Contains('FGameplayAttributeData JumpVelocity;')) 'PlayerMovementAttributeSet exposes JumpVelocity readback'
Assert-True ($ascHeader.Contains('UAttributeSet* GetAttributeSet(TSubclassOf<UAttributeSet> AttributeSetClass) const;')) 'ASC exposes the exact attribute-set crosscheck'
Assert-True ($ascHeader.Contains('float GetGameplayAttributeValue(FGameplayAttribute Attribute, bool& bFound) const;')) 'ASC exposes the read-only descriptor-value call'
Assert-True ($ascHeader.Contains('int32 GetGameplayEffectCount(TSubclassOf<UGameplayEffect> SourceGameplayEffect, UAbilitySystemComponent* OptionalInstigatorFilterComponent, bool bEnforceOnGoingCheck) const;')) 'ASC exposes the read-only source-effect count'
Assert-True ($effectHeader.Contains('TArray<FGameplayModifierInfo> Modifiers;')) 'GameplayEffect exposes the bounded Modifiers array'
Assert-True ($modifierInfoHeader.Contains('FGameplayAttribute Attribute;')) 'GameplayModifierInfo exposes its attribute descriptor'

$effectClassEvidence = Select-String -LiteralPath $objectDumpPath -SimpleMatch `
    '/Game/_Dawnwalker/Combat/Focus/Vampire/WolfBoost/GE_WolfBoost_JumpIncrease.GE_WolfBoost_JumpIncrease_C' `
    -List
$effectCdoEvidence = Select-String -LiteralPath $objectDumpPath -SimpleMatch `
    '/Game/_Dawnwalker/Combat/Focus/Vampire/WolfBoost/GE_WolfBoost_JumpIncrease.Default__GE_WolfBoost_JumpIncrease_C' `
    -List
$abilityLibraryCdoEvidence = Select-String -LiteralPath $objectDumpPath -SimpleMatch `
    '/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary' `
    -List
$jumpFieldEvidence = Select-String -LiteralPath $objectDumpPath -SimpleMatch `
    '/Script/DogwoodStats.PlayerMovementAttributeSet:JumpVelocity [o: A0]' `
    -List
Assert-True ($null -ne $effectClassEvidence) 'captured ObjectDump contains the exact Wolf Boost jump-effect class'
Assert-True ($null -ne $effectCdoEvidence) 'captured ObjectDump contains the exact Wolf Boost jump-effect CDO'
Assert-True ($null -ne $abilityLibraryCdoEvidence) 'captured ObjectDump contains the exact AbilitySystemBlueprintLibrary CDO'
Assert-True ($null -ne $jumpFieldEvidence) 'captured ObjectDump contains JumpVelocity at offset 0xA0'

$probeText = Get-Content -LiteralPath $probePath -Raw -Encoding UTF8
foreach ($requiredMarker in @(
    'player:super-jump-descriptor',
    'development-read-only',
    '/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary',
    'mutation_authorized = false',
    'release_visible = false',
    'controller:K2_GetPawn()',
    'controller.PossessedCharacter',
    'player:GetController()',
    'ability_system:GetAttributeSet(attribute_set_class)',
    'GetDebugStringFromGameplayAttribute',
    'GetGameplayAttributeValue',
    'GetGameplayEffectCount',
    'GE_WolfBoost_JumpIncrease.Default__GE_WolfBoost_JumpIncrease_C',
    'if #values ~= 1 then',
    'identities_remain_stable'
)) {
    Assert-True ($probeText.Contains($requiredMarker)) "probe contains required fail-closed marker: $requiredMarker"
}

foreach ($forbiddenPattern in @(
    'Default__AbilitySystemBlueprintFunctionLibrary',
    ':SetAttributeValue\s*\(',
    ':BP_ApplyGameplayEffectToSelf\s*\(',
    ':RemoveActiveGameplayEffect\s*\(',
    '\.BaseValue\s*=',
    '\.CurrentValue\s*=',
    '\.JumpZVelocity\s*=',
    'StaticLoadObject\s*\(',
    'LoadAsset\s*\(',
    'StaticConstructObject\s*\(',
    'ExecuteInGameThread\s*\(',
    'LoopAsync\s*\(',
    'RegisterHook\s*\(',
    'NotifyOnNewObject\s*\(',
    'os\.execute\s*\(',
    'io\.popen\s*\(',
    'io\.open\s*\('
)) {
    Assert-True (-not [Regex]::IsMatch($probeText, $forbiddenPattern)) "probe excludes mutation, activation, scheduling, and file/process pattern: $forbiddenPattern"
}

$sharedCapabilitySurfaces = @(
    (Join-Path $projectRoot 'integration\uue4ss\Mods\DawnwalkerModBridge\Scripts\main.lua'),
    (Join-Path $projectRoot 'electron\runtimeCapabilities.ts'),
    (Join-Path $projectRoot 'src\runtimeContract.ts'),
    (Join-Path $projectRoot 'installer\templates\ue4ss\Mods\DawnwalkerModBridge\Scripts\main.lua'),
    (Join-Path $projectRoot 'installer\runtime\overrides\ue4ss\Mods\DawnwalkerModBridge\Scripts\main.lua')
)
foreach ($surfacePath in $sharedCapabilitySurfaces) {
    if (-not (Test-Path -LiteralPath $surfacePath -PathType Leaf)) { continue }
    $surfaceText = Get-Content -LiteralPath $surfacePath -Raw -Encoding UTF8
    Assert-True (-not $surfaceText.Contains('player:super-jump-descriptor')) "standalone probe is absent from shared capability surface: $surfacePath"
    Assert-True (-not $surfaceText.Contains('DawnwalkerSuperJumpDescriptorReadOnlyProbe')) "standalone module is absent from shared runtime surface: $surfacePath"
}

$package = Get-Content -LiteralPath (Join-Path $projectRoot 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$packagedFiles = @($package.build.files)
Assert-True (-not ($packagedFiles | Where-Object { $_ -match 'analysis|probe' })) 'analysis-only probe is excluded from packaged Electron files'

$lua = Get-Command lua -ErrorAction Stop
$harnessOutput = @(& $lua.Source $luaHarnessPath $probePath 2>&1)
Assert-True ($LASTEXITCODE -eq 0) "Lua probe harness exits successfully: $(($harnessOutput | Out-String).Trim())"
Assert-True ((($harnessOutput | Out-String) -match 'Super Jump descriptor read-only probe harness passed')) 'Lua probe harness reports its success marker'

Write-Output 'Dawnwalker Super Jump descriptor feasibility tests passed.'
