@echo off
rem ================================================================
rem  Start Ternary-Bonsai-2-27B OpenAI-compatible API server.
rem  Just double-click this file, or pass arguments:
rem      start-server.cmd -Port 9000 -Context 65536
rem      start-server.cmd -Status
rem      start-server.cmd -Force
rem ================================================================
chcp 65001 >nul 2>&1
setlocal
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-server.ps1" %*
set RC=%ERRORLEVEL%

rem Keep the window open on double-click (no arguments) so output is visible
if "%~1"=="" (
    echo.
    pause
)
exit /b %RC%
