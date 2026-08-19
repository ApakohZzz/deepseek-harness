@echo off
REM Thin wrapper: all logic lives in dsh-control.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dsh-control.ps1" -Action status
pause
