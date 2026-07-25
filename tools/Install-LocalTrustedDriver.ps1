[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$DriverPackagePath,

    [Parameter(Mandatory)]
    [string]$CertificatePath,

    [Parameter(Mandatory)]
    [string]$DeviceAppPath,

    [switch]$DisableTestSigning
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell session.'
}

$package = (Resolve-Path $DriverPackagePath).Path
$certificate = (Resolve-Path $CertificatePath).Path
$deviceApp = (Resolve-Path $DeviceAppPath).Path
$inf = Get-ChildItem $package -File -Filter '*.inf' | Select-Object -First 1
$catalog = Get-ChildItem $package -File -Filter '*.cat' | Select-Object -First 1

if ($null -eq $inf -or $null -eq $catalog) {
    throw 'The package must contain an INF and a signed catalog.'
}

if (Get-ChildItem $package -File -Filter '*.sys') {
    throw 'This local-trust flow is restricted to the UMDF-only package and refuses kernel-mode SYS files.'
}

$infText = Get-Content $inf.FullName -Raw -Encoding Unicode
if ($infText -notmatch 'UmdfService=' -or $infText -notmatch 'Include=WUDFRD\.inf') {
    throw 'The INF is not recognized as the expected UMDF driver package.'
}

$publicCertificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($certificate)
$enhancedKeyUsage = $publicCertificate.Extensions |
    Where-Object { $_ -is [Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension] } |
    Select-Object -First 1
$hasCodeSigningUsage = $null -ne $enhancedKeyUsage -and
    @($enhancedKeyUsage.EnhancedKeyUsages | ForEach-Object { $_.Value }) -contains '1.3.6.1.5.5.7.3.3'
if (-not $hasCodeSigningUsage) {
    throw 'The certificate does not include the Code Signing enhanced key usage.'
}

Import-Certificate -FilePath $certificate -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
Import-Certificate -FilePath $certificate -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null

$signature = Get-AuthenticodeSignature $catalog.FullName
if ($signature.Status -ne 'Valid') {
    throw "Catalog signature validation failed: $($signature.StatusMessage)"
}
if ($signature.SignerCertificate.Thumbprint -ne $publicCertificate.Thumbprint) {
    throw 'The catalog signer does not match the supplied certificate.'
}

& pnputil.exe /add-driver $inf.FullName /install
if ($LASTEXITCODE -ne 0) {
    throw "PnPUtil failed with exit code $LASTEXITCODE."
}

if ($DisableTestSigning) {
    & bcdedit.exe /set testsigning off
    if ($LASTEXITCODE -ne 0) {
        throw "BCDEdit failed with exit code $LASTEXITCODE."
    }
    Write-Host 'Test-signing is disabled. Restart Windows before starting the virtual display.'
    return
}

Start-Process -FilePath $deviceApp
Write-Host 'The locally trusted UMDF display driver is installed and the device app was started.'
Write-Warning 'This certificate trust is valid only on this PC and is not a Microsoft production signature.'