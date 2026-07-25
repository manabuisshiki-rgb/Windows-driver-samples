[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell session.'
}

bcdedit /set testsigning on
if ($LASTEXITCODE -ne 0) {
    throw "BCDEdit failed with exit code $LASTEXITCODE."
}

Write-Host 'Test signing is enabled. Restart Windows before installing the test driver.'