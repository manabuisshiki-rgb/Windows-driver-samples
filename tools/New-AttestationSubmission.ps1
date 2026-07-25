[CmdletBinding()]
param(
    [string]$DriverPackagePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'video\IndirectDisplay\x64\Release'),

    [Parameter(Mandatory)]
    [string]$CertificateThumbprint,

    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\attestation'),

    [string]$TimestampServer = 'http://timestamp.digicert.com',

    [switch]$AllowSampleIdentity
)

$ErrorActionPreference = 'Stop'

function Find-WdkTool([string]$RelativePath) {
    $tool = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter $RelativePath -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($null -eq $tool) {
        throw "WDK tool '$RelativePath' was not found. Install the Windows Driver Kit."
    }
    return $tool.FullName
}

$packageSource = (Resolve-Path $DriverPackagePath).Path
$inf = Get-ChildItem $packageSource -File -Filter '*.inf' | Select-Object -First 1
$driver = Get-ChildItem $packageSource -File -Filter '*.dll' | Where-Object Name -eq 'IddSampleDriver.dll' | Select-Object -First 1
$symbols = Get-ChildItem $packageSource -File -Filter '*.pdb' | Where-Object Name -eq 'IddSampleDriver.pdb' | Select-Object -First 1

if ($null -eq $inf -or $null -eq $driver -or $null -eq $symbols) {
    throw 'The release package must contain IddSampleDriver.inf, IddSampleDriver.dll, and IddSampleDriver.pdb.'
}

$infText = Get-Content $inf.FullName -Raw -Encoding Unicode
if (-not $AllowSampleIdentity -and ($infText -match '<Your manufacturer name>' -or $infText -match 'TODO:')) {
    throw 'The INF still contains Microsoft sample identity values. Set your legal manufacturer name, product name, unique hardware ID, and DriverVer before creating a submission. Use -AllowSampleIdentity only for a non-production rehearsal.'
}

$inf2cat = Find-WdkTool 'Inf2Cat.exe'
$signtool = Find-WdkTool 'signtool.exe'
$makecab = Get-Command makecab.exe -ErrorAction SilentlyContinue
if ($null -eq $makecab) {
    throw 'makecab.exe was not found.'
}

$submissionRoot = Join-Path $OutputDirectory 'submission'
$driverFolderName = 'ExternalTouchDisplayDriver'
$stagedDriverPath = Join-Path $submissionRoot $driverFolderName
$cabPath = Join-Path $OutputDirectory 'ExternalTouchDisplayDriver-attestation.cab'

Remove-Item $OutputDirectory -Recurse -Force -ErrorAction SilentlyContinue
New-Item $stagedDriverPath -ItemType Directory -Force | Out-Null
Copy-Item $inf.FullName, $driver.FullName, $symbols.FullName -Destination $stagedDriverPath

& $inf2cat "/driver:$stagedDriverPath" '/os:10_X64,10_GE_X64' /verbose
if ($LASTEXITCODE -ne 0) {
    throw "Inf2Cat failed with exit code $LASTEXITCODE."
}

$catalog = Get-ChildItem $stagedDriverPath -File -Filter '*.cat' | Select-Object -First 1
if ($null -eq $catalog) {
    throw 'Inf2Cat did not create a catalog file.'
}

& $signtool sign /fd SHA256 /sha1 $CertificateThumbprint /s My /tr $TimestampServer /td SHA256 $catalog.FullName
if ($LASTEXITCODE -ne 0) {
    throw "Signing the catalog failed with exit code $LASTEXITCODE."
}

$ddfPath = Join-Path $OutputDirectory 'ExternalTouchDisplayDriver-attestation.ddf'
$ddf = @"
.OPTION EXPLICIT
.Set CabinetFileCountThreshold=0
.Set FolderFileCountThreshold=0
.Set FolderSizeThreshold=0
.Set MaxCabinetSize=0
.Set MaxDiskFileCount=0
.Set MaxDiskSize=0
.Set CompressionType=MSZIP
.Set Cabinet=on
.Set Compress=on
.Set CabinetNameTemplate=ExternalTouchDisplayDriver-attestation.cab
.Set DiskDirectoryTemplate=$OutputDirectory
.Set DestinationDir=$driverFolderName
"@

Get-ChildItem $stagedDriverPath -File | ForEach-Object {
    $ddf += "`r`n`"$($_.FullName)`" `"$($_.Name)`""
}
Set-Content $ddfPath -Value $ddf -Encoding ASCII

& $makecab.Source /F $ddfPath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $cabPath)) {
    throw "MakeCab failed with exit code $LASTEXITCODE."
}

& $signtool sign /fd SHA256 /sha1 $CertificateThumbprint /s My /tr $TimestampServer /td SHA256 $cabPath
if ($LASTEXITCODE -ne 0) {
    throw "Signing the submission CAB failed with exit code $LASTEXITCODE."
}

& $signtool verify /pa /ph /v $cabPath
if ($LASTEXITCODE -ne 0) {
    throw "Submission CAB signature verification failed with exit code $LASTEXITCODE."
}

Write-Host "Attestation submission package created: $cabPath"
Write-Host 'Upload this EV-signed CAB through Partner Center Hardware, then download the Microsoft-signed driver package.'