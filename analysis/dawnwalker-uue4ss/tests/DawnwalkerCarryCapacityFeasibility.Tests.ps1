[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory = $true)][string]$ModuleName)
    return $ModuleName
}

$null = cyberfox1337x -ModuleName 'dawnwalker_carry_capacity_feasibility_tests'

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

$kitRoot = Split-Path -Parent $PSScriptRoot
$probePath = Join-Path $kitRoot 'probes\DawnwalkerCarryCapacityReadOnlyProbe.lua'
$luaHarnessPath = Join-Path $PSScriptRoot 'DawnwalkerCarryCapacityReadOnlyProbe.Tests.lua'
$objectDumpPath = Join-Path $kitRoot 'captured-dump\2026-09-02-object-dump\UE4SS_ObjectDump.txt'
$inventoryHeaderPath = Join-Path $kitRoot 'captured-dump\2026-09-02-cxx-sdk\CXXHeaderDump\DogwoodInventory.hpp'
$statsHeaderPath = Join-Path $kitRoot 'captured-dump\2026-09-02-cxx-sdk\CXXHeaderDump\DogwoodStats.hpp'
$gameplayHeaderPath = Join-Path $kitRoot 'captured-dump\2026-09-02-cxx-sdk\CXXHeaderDump\GameplayAbilities.hpp'
$combatUhtPath = Join-Path $kitRoot 'captured-dump\2026-09-02-uht-incomplete\UHTHeaderDump\DogwoodCombat\Public\CombatBlueprintFunctionLibrary.h'
$jmapPath = Get-ChildItem -LiteralPath (Join-Path $kitRoot 'captured-dump\2026-09-02-jmap') -Filter '*.jmap' -File | Select-Object -First 1 -ExpandProperty FullName
$matrixPath = Join-Path $kitRoot 'feature-contract-matrix.json'
$changelogPath = Join-Path $kitRoot 'stage-zdev\ue4ss\Changelog.md'
$tarrayDocsPath = Join-Path $kitRoot 'stage-zdev\ue4ss\Docs\lua-api\classes\tarray.md'
$structDocsPath = Join-Path $kitRoot 'stage-zdev\ue4ss\Docs\lua-api\classes\uscriptstruct.md'

foreach ($requiredPath in @(
    $probePath, $luaHarnessPath, $objectDumpPath, $inventoryHeaderPath, $statsHeaderPath,
    $gameplayHeaderPath, $combatUhtPath, $jmapPath, $matrixPath, $changelogPath,
    $tarrayDocsPath, $structDocsPath
)) {
    Assert-True (Test-Path -LiteralPath $requiredPath -PathType Leaf) "required evidence exists: $requiredPath"
}

$objectDump = Get-Content -LiteralPath $objectDumpPath -Raw -Encoding UTF8
Assert-True ($objectDump -match 'Function /Script/DogwoodCombat\.CombatBlueprintFunctionLibrary:SetAttributeValue') 'exact SetAttributeValue function exists'
Assert-True ($objectDump -match 'SetAttributeValue:AttributeOwner \[o: 0\].*\[pc: [0-9A-F]+\]') 'setter owner parameter is reflected at offset zero'
Assert-True ($objectDump -match 'SetAttributeValue:AttributeToSet \[o: 8\].*\[ss: [0-9A-F]+\]') 'setter gameplay-attribute struct is reflected at offset eight'
Assert-True ($objectDump -match 'SetAttributeValue:AttributeValue \[o: 40\]') 'setter float is reflected at offset 0x40'
Assert-True ($objectDump -match 'GE_Trait_Shared_StrongBack_Level_1\.Default__GE_Trait_Shared_StrongBack_Level_1_C') 'Strong Back Level 1 CDO was loaded in the captured object set'
Assert-True ($objectDump -match 'GE_EnableWeightLimitExceed\.Default__GE_EnableWeightLimitExceed_C:TargetTagsGameplayEffectComponent_0') 'old effect is a tag-component effect, not a capacity modifier'
Assert-True ($objectDump -match 'AbilitySystemBlueprintLibrary /Script/GameplayAbilities\.Default__AbilitySystemBlueprintLibrary') 'exact GAS debug-library CDO path is pinned'

$combatUht = Get-Content -LiteralPath $combatUhtPath -Raw -Encoding UTF8
Assert-True ($combatUht -match 'static void SetAttributeValue\(UAbilitySystemComponent\* AttributeOwner, UPARAM\(Ref\) FGameplayAttribute& AttributeToSet, float AttributeValue\);') 'exact Blueprint setter signature and reference semantics'

$inventoryHeader = Get-Content -LiteralPath $inventoryHeaderPath -Raw -Encoding UTF8
Assert-True ($inventoryHeader -match 'float WeightLimit;\s*// 0x0158') 'raw WeightLimit offset is pinned'
Assert-True ($inventoryHeader -match 'OnWeightExceededChanged;\s*// 0x0398') 'weight-change delegate offset is pinned'
Assert-True ($inventoryHeader -match 'bool bWeightExceeded;\s*// 0x0430') 'cached exceeded flag offset is pinned'
Assert-True ($inventoryHeader -match 'float GetWeightLimit\(\);') 'effective limit readback is reflected'
Assert-True ($inventoryHeader -match 'float GetCurrentWeight\(\);') 'current-weight readback is reflected'
Assert-True ($inventoryHeader -match 'bool CanExceedWeightLimit\(\);') 'over-limit permission telemetry is reflected'

$statsHeader = Get-Content -LiteralPath $statsHeaderPath -Raw -Encoding UTF8
Assert-True ($statsHeader -match 'FGameplayAttributeData CarryWeightCapacityModifier;\s*// 0x00B0') 'carry-capacity GameplayAttributeData offset is pinned'
$gameplayHeader = Get-Content -LiteralPath $gameplayHeaderPath -Raw -Encoding UTF8
Assert-True ($gameplayHeader -match '(?s)struct FGameplayAttribute\s*\{\s*FString AttributeName;.*TFieldPath<FProperty> Attribute;.*class UStruct\* AttributeOwner;' ) 'FGameplayAttribute name, field, and owner layout is pinned'
Assert-True ($gameplayHeader -match '(?s)struct FGameplayAttributeData\s*\{\s*float BaseValue;.*float CurrentValue;' ) 'GameplayAttributeData base/current layout is pinned'

$strongBackClasses = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$strongBackValues = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$carryAttributeCount = 0
$valueWindow = 0
$reader = [System.IO.StreamReader]::new($jmapPath, [System.Text.Encoding]::UTF8, $true, 65536)
try {
    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        if ($line -match 'GE_Trait_Shared_StrongBack_Level_([123])\.GE_Trait_Shared_StrongBack_Level_\1_C') {
            $null = $strongBackClasses.Add($Matches[1])
        }
        if ($line.IndexOf('"AttributeName": "CarryWeightCapacityModifier"', [System.StringComparison]::Ordinal) -ge 0) {
            $carryAttributeCount++
            $valueWindow = 12
            continue
        }
        if ($valueWindow -gt 0) {
            if ($line -match '"Value": (30\.0|60\.0|100\.0)') {
                $null = $strongBackValues.Add($Matches[1])
                $valueWindow = 0
            }
            else { $valueWindow-- }
        }
    }
}
finally {
    $reader.Dispose()
}
Assert-True ((@($strongBackClasses) | Sort-Object) -join ',' -eq '1,2,3') 'all three exact Strong Back classes are present'
Assert-True ((@($strongBackValues) | Sort-Object) -join ',' -eq '100.0,30.0,60.0') 'Strong Back carry-capacity magnitudes are exactly 30, 60, and 100'
Assert-True ($carryAttributeCount -eq 3) 'only the three loaded Strong Back effects declare carry-capacity modifiers'

$changelog = Get-Content -LiteralPath $changelogPath -Raw -Encoding UTF8
$tarrayDocs = Get-Content -LiteralPath $tarrayDocsPath -Raw -Encoding UTF8
$structDocs = Get-Content -LiteralPath $structDocsPath -Raw -Encoding UTF8
Assert-True ($changelog -match 'support for handling structs as userdata') 'pinned UE4SS build documents struct userdata support'
Assert-True ($tarrayDocs -match 'Use `elem:get\(\)`') 'TArray iteration documents retrieving a struct element without mutation'
Assert-True ($structDocs -match 'GetStructAddress\(\)') 'UScriptStruct exposes a stable struct-address readback'

$probeSource = Get-Content -LiteralPath $probePath -Raw -Encoding UTF8
foreach ($forbiddenPattern in @(
    ':SetAttributeValue\s*\(', ':BP_ApplyGameplayEffectToSelf\s*\(', ':RemoveActiveGameplayEffect\s*\(',
    ':TryAddItem\s*\(', ':RemoveItem\s*\(', 'inventory\.WeightLimit\s*=',
    'inventory\.bWeightExceeded\s*=', 'attribute_data\.BaseValue\s*=', 'attribute_data\.CurrentValue\s*='
)) {
    Assert-True (-not ($probeSource -match $forbiddenPattern)) "read-only probe excludes mutation pattern $forbiddenPattern"
}
Assert-True ($probeSource -match 'mutation_authorized = false') 'probe always fails closed for mutation'

$lua = Get-Command lua -ErrorAction Stop
$harnessOutput = @(& $lua.Source $luaHarnessPath $probePath 2>&1)
Assert-True ($LASTEXITCODE -eq 0) "Lua feasibility harness exits successfully: $(($harnessOutput | Out-String).Trim())"
Assert-True ((($harnessOutput | Out-String) -match 'carry-capacity read-only probe harness passed')) 'Lua harness reaches read-only completion'

$matrix = Get-Content -LiteralPath $matrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
$capability = @($matrix.bridgePilot.capabilities | Where-Object { $_.id -eq 'player:unlimited-weight' })
Assert-True ($capability.Count -eq 1) 'one Unlimited Weight capability contract exists'
Assert-True ($capability[0].status -eq 'pending-reflection' -and $capability[0].disposition -eq 'withdrawn-feasibility-probe') 'capability is withdrawn to feasibility only'
Assert-True ($capability[0].visibleInRelease -eq $false) 'capability is hidden from release'
Assert-True ($capability[0].wrongSemanticTarget -match 'only grants Inventory\.CanExceedWeightLimit') 'matrix records the disproved effect semantics'

Write-Output 'Dawnwalker carry-capacity feasibility tests passed.'
