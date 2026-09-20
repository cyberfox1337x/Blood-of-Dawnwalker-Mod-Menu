[CmdletBinding()]
param(
    [string]$BridgeSourcePath,
    [string]$PreparedBridgePath,
    [string]$PayloadManifestPath,
    [switch]$SourceOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function cyberfox1337x {
    param([Parameter(Mandatory)][string]$ModuleName)
    return $ModuleName
}

$null = cyberfox1337x -ModuleName 'test_dawnwalker_lua'

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

function Read-BridgeMetadata {
    param([Parameter(Mandatory)][string]$LiteralPath)

    $source = Get-Content -LiteralPath $LiteralPath -Raw -Encoding UTF8
    if ($source.IndexOf([char]0) -ge 0) { throw "Lua source contains a NUL byte: $LiteralPath" }
    if ($source.IndexOf('cyberfox1337x.function_signature("dawnwalker_mod_bridge")', [StringComparison]::Ordinal) -lt 0) {
        throw "Lua source is missing its cyberfox1337x bridge signature: $LiteralPath"
    }
    $values = [ordered]@{}
    $phaseMatches = [Regex]::Matches($source, '(?m)^\s*local\s+BRIDGE_PHASE\s*=\s*"(?<Value>[^"\r\n]*)"\s*$')
    if ($phaseMatches.Count -ne 1) {
        throw "Lua source must contain exactly one literal local BRIDGE_PHASE assignment: $LiteralPath"
    }
    $values.BRIDGE_PHASE = $phaseMatches[0].Groups['Value'].Value
    if ($values.BRIDGE_PHASE -ne 'discovery' -and $values.BRIDGE_PHASE -ne 'production') {
        throw "Lua bridge phase is not packageable: $($values.BRIDGE_PHASE)"
    }
    foreach ($name in @('BRIDGE_VERSION', 'CAPABILITIES')) {
        $matches = [Regex]::Matches(
            $source,
            '(?m)^\s*local\s+' + [Regex]::Escape($name) + '\s*=\s*"(?<Value>[^"\r\n]*)"\s*$'
        )
        if ($matches.Count -ne 1) {
            throw "Lua source must contain exactly one literal local $name assignment: $LiteralPath"
        }
        $values[$name] = $matches[0].Groups['Value'].Value
    }
    $capabilities = @()
    if (-not [string]::IsNullOrEmpty([string]$values.CAPABILITIES)) {
        $capabilities = @(([string]$values.CAPABILITIES).Split(','))
    }
    if ($values.BRIDGE_PHASE -eq 'discovery' -and $capabilities.Count -ne 0) {
        throw 'Discovery Lua source cannot advertise gameplay capabilities.'
    }
    if ($values.BRIDGE_PHASE -eq 'production' -and $capabilities.Count -eq 0) {
        throw 'Production Lua source must advertise at least one gameplay capability.'
    }
    return [pscustomobject]@{
        version = [string]$values.BRIDGE_VERSION
        phase = [string]$values.BRIDGE_PHASE
        capabilities = $capabilities
    }
}

function Test-LuaSyntax {
    param(
        [Parameter(Mandatory)][string]$CompilerPath,
        [Parameter(Mandatory)][string]$LiteralPath
    )

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Lua source is missing: $LiteralPath"
    }
    $sourceItem = Get-Item -LiteralPath $LiteralPath
    if ($sourceItem.Length -lt 64 -or $sourceItem.Length -gt 1048576) {
        throw "Lua source size is outside the approved 64-byte to 1-MiB range: $LiteralPath"
    }
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $compilerOutput = @(& $CompilerPath -p -- $LiteralPath 2>&1)
        $compilerExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    if ($compilerExitCode -ne 0) {
        throw "luac rejected '$LiteralPath' (exit $compilerExitCode): $(($compilerOutput | Out-String).Trim())"
    }
}

$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if (-not $BridgeSourcePath) {
    $BridgeSourcePath = Join-Path $projectRoot 'integration\uue4ss\Mods\DawnwalkerModBridge\Scripts\main.lua'
}
if (-not $PreparedBridgePath) {
    $PreparedBridgePath = Join-Path $projectRoot 'installer\runtime\overrides\ue4ss\Mods\DawnwalkerModBridge\Scripts\main.lua'
}
if (-not $PayloadManifestPath) {
    $PayloadManifestPath = Join-Path $projectRoot 'installer\runtime\payload-manifest.json'
}

$compiler = Get-Command luac -ErrorAction SilentlyContinue
if (-not $compiler -or -not $compiler.Source) {
    throw 'Lua 5.4 luac is required for package validation and was not found on PATH.'
}
$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $compilerVersion = (& $compiler.Source -v 2>&1 | Out-String).Trim()
    $compilerVersionExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $savedErrorActionPreference
}
if ($compilerVersionExitCode -ne 0) {
    throw "Unable to identify the packaging Lua compiler: $compilerVersion"
}
if ($compilerVersion -notmatch '^Lua 5\.4(?:\.|\s)') {
    throw "The packaging Lua compiler must be Lua 5.4.x; found: $compilerVersion"
}

$resolvedSourcePath = [IO.Path]::GetFullPath($BridgeSourcePath)
Test-LuaSyntax -CompilerPath $compiler.Source -LiteralPath $resolvedSourcePath
$sourceMetadata = Read-BridgeMetadata -LiteralPath $resolvedSourcePath
$validatedPaths = @($resolvedSourcePath)

if (-not $SourceOnly) {
    $resolvedPreparedPath = [IO.Path]::GetFullPath($PreparedBridgePath)
    $resolvedManifestPath = [IO.Path]::GetFullPath($PayloadManifestPath)
    Test-LuaSyntax -CompilerPath $compiler.Source -LiteralPath $resolvedPreparedPath
    $preparedMetadata = Read-BridgeMetadata -LiteralPath $resolvedPreparedPath
    if ((Get-Sha256 -LiteralPath $resolvedSourcePath) -cne (Get-Sha256 -LiteralPath $resolvedPreparedPath)) {
        throw 'Prepared runtime bridge is not an exact byte-for-byte copy of the validated integration bridge.'
    }
    if ($preparedMetadata.phase -cne $sourceMetadata.phase -or
        $preparedMetadata.version -cne $sourceMetadata.version -or
        (@($preparedMetadata.capabilities) -join ',') -cne (@($sourceMetadata.capabilities) -join ',')) {
        throw 'Prepared and integration bridge metadata differ.'
    }

    if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
        throw "Prepared runtime manifest is missing: $resolvedManifestPath"
    }
    $manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.cyberfox1337x -ne 'function(dawnwalker_runtime_payload_manifest)' -or
        [string]$manifest.phase -cne $sourceMetadata.phase -or
        [string]$manifest.bridgeVersion -cne $sourceMetadata.version -or
        (@($manifest.gameplayCapabilities) -join ',') -cne (@($sourceMetadata.capabilities) -join ',')) {
        throw 'Prepared runtime manifest does not describe the validated Lua bridge exactly.'
    }
    $bridgeOverlays = @($manifest.overlays | Where-Object {
        ([string]$_.targetPath).Replace('\', '/') -ceq 'ue4ss/Mods/DawnwalkerModBridge/Scripts/main.lua'
    })
    if ($bridgeOverlays.Count -ne 1 -or
        [string]$bridgeOverlays[0].sha256 -cne (Get-Sha256 -LiteralPath $resolvedPreparedPath)) {
        throw 'Prepared runtime manifest does not pin the exact Lua bridge overlay hash.'
    }
    $validatedPaths += $resolvedPreparedPath
}

[pscustomobject]@{
    cyberfox1337x = 'function(dawnwalker_lua_validation_result)'
    valid = $true
    compiler = $compilerVersion
    phase = $sourceMetadata.phase
    bridgeVersion = $sourceMetadata.version
    capabilities = @($sourceMetadata.capabilities)
    validatedPaths = $validatedPaths
    bridgeSha256 = Get-Sha256 -LiteralPath $resolvedSourcePath
} | ConvertTo-Json -Depth 5
