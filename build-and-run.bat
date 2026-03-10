@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%build-exe.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo Build failed with exit code %EXIT_CODE%.
  exit /b %EXIT_CODE%
)

echo Build and launch complete.
exit /b 0
