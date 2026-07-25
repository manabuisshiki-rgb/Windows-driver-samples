[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$certificateDirectory = Join-Path $projectRoot '.test-signing'
$certificatePath = Join-Path $certificateDirectory 'ExternalTouchTest.cer'

New-Item -ItemType Directory -Path $certificateDirectory -Force | Out-Null
$certificate = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject 'CN=External Touch Development Driver' `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -KeyUsage DigitalSignature `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(2)

Export-Certificate -Cert $certificate -FilePath $certificatePath -Force | Out-Null
Set-Content -Path (Join-Path $certificateDirectory 'thumbprint.txt') -Value $certificate.Thumbprint -NoNewline

Write-Host "Certificate: $certificatePath"
Write-Host "Thumbprint: $($certificate.Thumbprint)"
Write-Host 'Use this thumbprint with Sign-Driver.ps1.'