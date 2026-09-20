[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory = $true)][string]$ModuleName)
    return $ModuleName
}

$null = cyberfox1337x -ModuleName 'analyze_dawnwalker_reflection_dump_tests'

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

$kitRoot = Split-Path -Parent $PSScriptRoot
$analyzer = Join-Path $kitRoot 'Analyze-DawnwalkerReflectionDump.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dawnwalker-reflection-analysis-test-{0}" -f [Guid]::NewGuid().ToString('N'))
$dumpRoot = Join-Path $testRoot 'dump'
$outputPath = Join-Path $testRoot 'result\reflection-index.json'

try {
    $null = New-Item -ItemType Directory -Path $dumpRoot -Force
    @'
Class /Script/DogwoodAbilitySystem.CharacterAttributeSet
Function SetHealthLocked
Property MaxHealth
'@ | Set-Content -LiteralPath (Join-Path $dumpRoot 'ObjectDump.txt') -Encoding utf8
    @'
class ADawnwalkerPlayerCharacter;
struct AFastTravelMarker;
'@ | Set-Content -LiteralPath (Join-Path $dumpRoot 'Dogwood.generated.hpp') -Encoding utf8
    [byte[]](0, 1, 2, 3) | Set-Content -LiteralPath (Join-Path $dumpRoot 'ignored.usmap') -Encoding Byte

    $report = & $analyzer -DumpRoot $dumpRoot -OutputPath $outputPath
    Assert-True ($report.filesScanned -eq 2) 'only supported text reflection files are scanned'
    Assert-True ($report.anchorsFound -ge 4) 'known classes and members are indexed'
    Assert-True (($report.hits.anchor) -contains 'ADawnwalkerPlayerCharacter') 'player class anchor found'
    Assert-True (($report.hits.anchor) -contains 'SetHealthLocked') 'health setter anchor found'
    Assert-True (Test-Path -LiteralPath $outputPath -PathType Leaf) 'JSON index written atomically'
    $saved = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
    Assert-True ($saved.cyberfox1337x -eq 'function(dawnwalker_reflection_dump_report)') 'saved report signature'
    Assert-True (-not $saved.truncated) 'small reflection fixture is not truncated'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

[pscustomobject]@{
    passed = $true
    analyzer = $analyzer
}
