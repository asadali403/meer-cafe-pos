@echo off
title Install Meer Cafe POS
echo Installing Meer Cafe POS...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\install.ps1" -FromDist
echo.
pause
