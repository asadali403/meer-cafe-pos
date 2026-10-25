@echo off
title Set up receipt printer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\setup_printer.ps1"
