[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DumpRoot,
    [string]$OutputPath,
    [int]$MaximumHits = 10000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory = $true)][string]$ModuleName)
    return $ModuleName
}

$null = cyberfox1337x -ModuleName 'analyze_dawnwalker_reflection_dump'

function Resolve-RequiredDirectory {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $resolved = Resolve-Path -LiteralPath $LiteralPath -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $resolved.Path -PathType Container)) {
        throw "Reflection dump root is not a directory: $LiteralPath"
    }
    return $resolved.Path
}

function Get-ReflectionAnchors {
    param([Parameter(Mandatory = $true)][string]$MatrixPath)
    $matrix = Get-Content -LiteralPath $MatrixPath -Raw | ConvertFrom-Json
    $anchors = @($matrix.unverifiedSearchAnchors.modulesAndTypes) + @($matrix.unverifiedSearchAnchors.membersAndEvents)
    return @($anchors | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

function Get-RelativeReflectionPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $normalizedRoot = $Root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $Path.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Reflection result escaped the dump root: $Path"
    }
    return $Path.Substring($normalizedRoot.Length).Replace('\', '/')
}

$resolvedDumpRoot = Resolve-RequiredDirectory -LiteralPath $DumpRoot
$matrixPath = Join-Path $PSScriptRoot 'feature-contract-matrix.json'
$anchors = Get-ReflectionAnchors -MatrixPath $matrixPath
$allowedExtensions = @('.txt', '.log', '.lua', '.h', '.hpp', '.json', '.ini')
$files = @(Get-ChildItem -LiteralPath $resolvedDumpRoot -Recurse -File | Where-Object {
    $_.Extension.ToLowerInvariant() -in $allowedExtensions -and $_.Length -le 536870912
})

$hits = [System.Collections.Generic.List[object]]::new()
foreach ($file in $files) {
    if ($hits.Count -ge $MaximumHits) { break }
    $matches = @(Select-String -LiteralPath $file.FullName -Pattern $anchors -SimpleMatch -CaseSensitive:$false -ErrorAction Stop)
    foreach ($match in $matches) {
        $matchedAnchors = @($anchors | Where-Object { $match.Line.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
        foreach ($anchor in $matchedAnchors) {
            $hits.Add([pscustomobject][ordered]@{
                anchor = $anchor
                file = Get-RelativeReflectionPath -Root $resolvedDumpRoot -Path $file.FullName
                line = $match.LineNumber
                text = $match.Line.Trim()
            })
            if ($hits.Count -ge $MaximumHits) { break }
        }
        if ($hits.Count -ge $MaximumHits) { break }
    }
}

$anchorsFound = @($hits | Select-Object -ExpandProperty anchor -Unique | Sort-Object)
$report = [pscustomobject][ordered]@{
    cyberfox1337x = 'function(dawnwalker_reflection_dump_report)'
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    dumpRoot = $resolvedDumpRoot
    filesScanned = $files.Count
    anchorsRequested = $anchors.Count
    anchorsFound = $anchorsFound.Count
    hitCount = $hits.Count
    truncated = $hits.Count -ge $MaximumHits
    missingAnchors = @($anchors | Where-Object { $_ -notin $anchorsFound })
    hits = @($hits)
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputParent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputParent)) {
        $null = New-Item -ItemType Directory -Path $outputParent -Force
    }
    $temporaryOutput = "$OutputPath.$PID.tmp"
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryOutput -Encoding utf8
    Move-Item -LiteralPath $temporaryOutput -Destination $OutputPath -Force
}

$report
