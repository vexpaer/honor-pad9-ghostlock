@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"

set "PS_EXE="
where pwsh.exe >nul 2>nul && set "PS_EXE=pwsh.exe"
if not defined PS_EXE (
    where powershell.exe >nul 2>nul && set "PS_EXE=powershell.exe"
)

if not defined PS_EXE (
    echo PowerShell was not found.
    echo Install PowerShell 7 or enable Windows PowerShell, then try again.
    pause
    exit /b 1
)

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run-wireless.ps1" %*
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" echo Exit code: %RC%
pause
exit /b %RC%
