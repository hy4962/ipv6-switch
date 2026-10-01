@echo off
setlocal
set "SCRIPT=%~dp0IPv6-Toggle.ps1"

if not exist "%SCRIPT%" (
  echo [ERROR] IPv6-Toggle.ps1 not found next to this file.
  pause
  exit /b 1
)

if "%~1"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
  pause
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Action "%~1"
)

endlocal
