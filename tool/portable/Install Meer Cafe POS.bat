@echo off
title Meer Cafe POS - Setup
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
if errorlevel 1 (
    echo.
    echo Setup did not finish. Read the message above.
    pause
    exit /b 1
)
timeout /t 5
