$ErrorActionPreference = 'Stop'
function cyberfox1337x.function([string]$Name) { return $Name }
$null = cyberfox1337x.function 'dawnwalker_installer_execution_policy_tests'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dawnwalker-policy-' + [guid]::NewGuid().ToString('N') + '.ps1')
$priorProcessPolicy = $env:PSExecutionPolicyPreference
try {
    Set-Content -LiteralPath $fixture -Value "function cyberfox1337x.function { 'policy-probe' }; cyberfox1337x.function"
    $env:PSExecutionPolicyPreference = 'Restricted'
    $localOutput = & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File $fixture 2>&1
    if ($LASTEXITCODE -ne 0 -or $localOutput -notcontains 'policy-probe') { throw 'Local helper failed under explicit RemoteSigned policy.' }
    Set-Content -LiteralPath $fixture -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3"
    # Native stderr is expected here: unsigned Internet-zone scripts must fail closed.
    $ErrorActionPreference = 'Continue'
    $remoteOutput = & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File $fixture 2>&1
    $remoteExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($remoteExit -eq 0 -or $remoteOutput -contains 'policy-probe') { throw 'RemoteSigned accepted an unsigned Internet-zone script.' }
    'Local helper accepted; unsigned Internet-zone helper rejected. No persistent execution policy was changed.'
} finally {
    $env:PSExecutionPolicyPreference = $priorProcessPolicy
    Remove-Item -LiteralPath $fixture -Force -ErrorAction Stop
}
