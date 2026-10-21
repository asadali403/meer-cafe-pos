# Meer Cafe POS - install for the current Windows user.
#
#   Install.bat (double-click)                                          # install the ready-built app in dist\
#   powershell -ExecutionPolicy Bypass -File tool\install.ps1 -FromDist # same as Install.bat
#   powershell -ExecutionPolicy Bypass -File tool\install.ps1           # build from source + install (needs Flutter)
#   powershell -ExecutionPolicy Bypass -File tool\install.ps1 -NoBuild  # install an existing local build
#
# Installs to  %LOCALAPPDATA%\Programs\Meer Cafe POS  (no admin rights needed) and creates
# Desktop + Start Menu shortcuts. Data lives separately in %APPDATA%\MeerCafePOS and is
# never touched by (re)installing.
param([switch]$NoBuild, [switch]$FromDist)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if ($FromDist) {
    $release = Join-Path $root 'dist\MeerCafePOS'
} else {
    if (-not $NoBuild) {
        Write-Host '==> Building release (this can take a few minutes)...' -ForegroundColor Yellow
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
    }
    $release = Join-Path $root 'build\windows\x64\runner\Release'
}
if (-not (Test-Path (Join-Path $release 'MeerCafePOS.exe'))) { throw "App files not found at $release" }

$running = Get-Process MeerCafePOS -ErrorAction SilentlyContinue
if ($running) { throw 'Meer Cafe POS is running. Close it first, then run the installer again.' }

$dest = Join-Path $env:LOCALAPPDATA 'Programs\Meer Cafe POS'
Write-Host "==> Installing to $dest" -ForegroundColor Yellow
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $release '*') $dest -Recurse -Force
# Files from a downloaded ZIP carry the "downloaded from internet" mark; clear it so
# Windows does not block the app's DLLs.
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
Write-Host 'Done. Double-click "Meer Cafe POS" on your Desktop to start.' -ForegroundColor Green
Write-Host "Your data: $env:APPDATA\MeerCafePOS"
