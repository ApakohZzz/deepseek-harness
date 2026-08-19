@echo off
REM Thin wrapper: all logic lives in update-dsh.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-dsh.ps1" %*
if errorlevel 1 pause
