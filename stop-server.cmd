@echo off
rem ================================================================
rem  Stop the Ternary-Bonsai-2-27B API server.
rem  Just double-click this file.
rem ================================================================
chcp 65001 >nul 2>&1
setlocal
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop-server.ps1" %*
set RC=%ERRORLEVEL%

if "%~1"=="" (
    echo.
    pause
)
exit /b %RC%
