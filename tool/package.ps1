# Meer Cafe POS - build (optional) and package a zip to copy to another laptop.
#
#   powershell -ExecutionPolicy Bypass -File tool\package.ps1          # build release + zip
#   powershell -ExecutionPolicy Bypass -File tool\package.ps1 -NoBuild # zip an existing build
#
# Produces  MeerCafePOS_Setup_<version>.zip  on the Desktop. On the new laptop: extract it,
# double-click "Install Meer Cafe POS.bat" once, then use the logo on the Desktop.
# The Visual C++ runtime DLLs are bundled so nothing else has to be installed there.
param([switch]$NoBuild)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not $NoBuild) {
    Write-Host '==> Building release (this can take a few minutes)...' -ForegroundColor Yellow
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
}

$release = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $release 'MeerCafePOS.exe'))) { throw "No release build found at $release" }

$version = ((Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*([^+\s]+)').Matches[0].Groups[1].Value)
$stage = Join-Path $env:TEMP "MeerCafePOS_package\Meer Cafe POS"
if (Test-Path (Split-Path $stage)) { Remove-Item (Split-Path $stage) -Recurse -Force }
$app = Join-Path $stage 'app'
New-Item -ItemType Directory -Force $app | Out-Null

Write-Host '==> Collecting files' -ForegroundColor Yellow
Copy-Item (Join-Path $release '*') $app -Recurse -Force
# App-local Visual C++ runtime, so a fresh Windows install does not need the redistributable.
foreach ($dll in 'msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    $p = Join-Path $env:WINDIR "System32\$dll"
    if (Test-Path $p) { Copy-Item $p $app -Force } else { Write-Warning "Missing $p (new laptop may need the VC++ redistributable)" }
}
Copy-Item (Join-Path $PSScriptRoot 'portable\*') $stage -Force

$zip = Join-Path ([Environment]::GetFolderPath('Desktop')) "MeerCafePOS_Setup_$version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Write-Host "==> Zipping to $zip" -ForegroundColor Yellow
Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal
Remove-Item (Split-Path $stage) -Recurse -Force

Write-Host ''
Write-Host "Done: $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)" -ForegroundColor Green
Write-Host 'Copy it to the new laptop, extract it, and double-click "Install Meer Cafe POS.bat".'
