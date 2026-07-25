[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$DriverPackagePath,
    [Parameter(Mandatory)]
    [string]$CertificatePath,
    [Parameter(Mandatory)]
    [string]$DeviceAppPath
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell session.'
}

$package = Resolve-Path $DriverPackagePath
$certificate = Resolve-Path $CertificatePath
$deviceApp = Resolve-Path $DeviceAppPath
$inf = Get-ChildItem $package -Filter '*.inf' | Select-Object -First 1
if ($null -eq $inf) {
    throw 'No INF file was found in the driver package directory.'
}

Import-Certificate -FilePath $certificate -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
Import-Certificate -FilePath $certificate -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null
pnputil /add-driver $inf.FullName /install
if ($LASTEXITCODE -ne 0) {
    throw "PnPUtil failed with exit code $LASTEXITCODE."
}

Start-Process -FilePath $deviceApp
Write-Host 'The software display device has been created. Open Windows display settings and extend onto it.'