[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$DriverPackagePath,
    [Parameter(Mandatory)]
    [string]$CertificateThumbprint
)

$ErrorActionPreference = 'Stop'
$package = Resolve-Path $DriverPackagePath
$inf2cat = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\*\inf2cat.exe' -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1
$signtool = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe' -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1

if ($null -eq $inf2cat -or $null -eq $signtool) {
    throw 'WDK packaging and signing tools were not found.'
}

& $inf2cat.FullName "/driver:$package" /os:10_X64
if ($LASTEXITCODE -ne 0) {
    throw "Inf2Cat failed with exit code $LASTEXITCODE."
}

$catalog = Get-ChildItem $package -Filter '*.cat' | Select-Object -First 1
if ($null -eq $catalog) {
    throw 'No catalog file was created.'
}

& $signtool.FullName sign /fd SHA256 /sha1 $CertificateThumbprint /s My $catalog.FullName
if ($LASTEXITCODE -ne 0) {
    throw "SignTool failed with exit code $LASTEXITCODE."
}

Write-Host "Signed catalog: $($catalog.FullName)"