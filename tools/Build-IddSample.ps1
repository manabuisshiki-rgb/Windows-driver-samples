[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [ValidateSet('x64', 'ARM64')]
    [string]$Platform = 'x64'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$solution = Join-Path $projectRoot 'video\IndirectDisplay\IddSampleDriver.sln'
$iddcxHeader = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\Include\*\um\iddcx\*\IddCx.h' -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1

if ($null -eq $iddcxHeader) {
    throw 'Windows Driver Kit is not installed. Install Microsoft.WindowsWDK.10.0.26100 first.'
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) {
    throw 'Visual Studio Build Tools with Desktop C++ and WDK integration are required.'
}

$msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($msbuild)) {
    throw 'MSBuild was not found.'
}

& $msbuild $solution /m "/p:Configuration=$Configuration" "/p:Platform=$Platform"
if ($LASTEXITCODE -ne 0) {
    throw "Driver build failed with exit code $LASTEXITCODE."
}

Write-Host 'IddCx sample build completed. Locate the generated .inf package before signing it.'