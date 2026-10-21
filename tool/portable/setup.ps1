# Meer Cafe POS - one-time setup on a new laptop (run by "Install Meer Cafe POS.bat").
#
# Copies the app next to this script into %LOCALAPPDATA%\Programs\Meer Cafe POS (no admin
# rights needed), puts the Meer Cafe logo on the Desktop and in the Start Menu, and starts
# the app. Data lives separately in %APPDATA%\MeerCafePOS and is never touched.
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'app'
if (-not (Test-Path (Join-Path $src 'MeerCafePOS.exe'))) {
    throw "The 'app' folder is missing. Unzip the WHOLE zip file first, then run the installer again."
}

if (Get-Process MeerCafePOS -ErrorAction SilentlyContinue) {
    throw 'Meer Cafe POS is open. Close it first, then run the installer again.'
}

$dest = Join-Path $env:LOCALAPPDATA 'Programs\Meer Cafe POS'
Write-Host "==> Installing to $dest" -ForegroundColor Yellow
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $src '*') $dest -Recurse -Force
# Files from a downloaded/emailed zip are marked "from the internet"; clear that so Windows
# does not warn every time the app starts.
Get-ChildItem $dest -Recurse -File | Unblock-File

$exe = Join-Path $dest 'MeerCafePOS.exe'
$shell = New-Object -ComObject WScript.Shell
function New-Shortcut($path) {
    $s = $shell.CreateShortcut($path)
    $s.TargetPath = $exe
    $s.WorkingDirectory = $dest
    $s.IconLocation = "$exe,0"
    $s.Description = 'Meer Cafe POS - billing and sales'
    $s.Save()
    Write-Host "    shortcut: $path"
}
New-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Meer Cafe POS.lnk')
New-Shortcut (Join-Path ([Environment]::GetFolderPath('Programs')) 'Meer Cafe POS.lnk')

Write-Host ''
Write-Host 'Done. From now on, just double-click the "Meer Cafe POS" logo on your Desktop.' -ForegroundColor Green
Write-Host "Your data: $env:APPDATA\MeerCafePOS"
Start-Process $exe -WorkingDirectory $dest
