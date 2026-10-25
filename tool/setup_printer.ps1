# Meer Cafe POS - set up a USB thermal receipt printer that Windows has no driver for.
#
# Many 58/80 mm receipt printers (e.g. ones that show up as "80Series", "POS-80") are
# connected but never appear in the printer list. This adds a printer called
# "Meer Receipt Printer" on the printer's USB port using Windows' built-in
# "Generic / Text Only" driver. Meer Cafe POS then prints to it directly (thermal mode,
# with automatic paper cut). Needs administrator rights once (Windows will ask).
param([string]$Name = 'Meer Receipt Printer')
$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Windows will ask for permission to add the printer. Click "Yes".' -ForegroundColor Yellow
    $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Name', "`"$Name`"")
    exit $p.ExitCode
}

try {
    if (Get-Printer -Name $Name -ErrorAction SilentlyContinue) {
        Write-Host "Printer '$Name' already exists." -ForegroundColor Green
    } else {
        $ports = @(Get-PrinterPort | Where-Object { $_.Name -like 'USB*' })
        $used = @(Get-Printer | ForEach-Object { $_.PortName })
        $free = @($ports | Where-Object { $used -notcontains $_.Name })
        if ($free.Count -eq 0) {
            throw 'No free USB printer port found. Plug in the printer, switch it on, wait 10 seconds and try again.'
        }
        $port = $free[0]
        Write-Host "Using port $($port.Name) ($($port.Description))"
        if (-not (Get-PrinterDriver -Name 'Generic / Text Only' -ErrorAction SilentlyContinue)) {
            Add-PrinterDriver -Name 'Generic / Text Only'
        }
        Add-Printer -Name $Name -DriverName 'Generic / Text Only' -PortName $port.Name
        Write-Host "Added printer '$Name'." -ForegroundColor Green
    }
    Write-Host ''
    Write-Host "Now open Meer Cafe POS as admin -> Settings -> Printer:" -ForegroundColor Yellow
    Write-Host "  Receipt printer = $Name, Paper = 80 mm (or 58 mm), Printer type = Thermal, then 'Save & test print'."
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    Start-Sleep 8
    exit 1
}
Start-Sleep 8
