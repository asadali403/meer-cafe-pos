@echo off
title Setup Dependencies - Meer Cafe POS
cd /d "%~dp0"

echo ===================================================
echo     Setting up Meer Cafe POS Dependencies
echo ===================================================
echo.

where flutter >nul 2>nul
if %errorlevel% neq 0 (
    echo [!] Flutter was not found in your PATH.
    echo.
    echo If you just want to run/install the application:
    echo   Double-click "Install.bat" directly (no Flutter required!).
    echo.
    echo If you want to develop or build from source:
    echo   Please install Flutter and add it to your PATH, then re-run this script.
    echo.
    pause
    exit /b 1
)

echo [*] Flutter detected! Fetching pub dependencies...
echo.
call flutter pub get

if %errorlevel% equ 0 (
    echo.
    echo [OK] All dependencies have been downloaded successfully!
) else (
    echo.
    echo [ERROR] Failed to fetch dependencies. Please check your internet connection.
)

echo.
pause
