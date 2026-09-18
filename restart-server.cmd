@echo off
rem ================================================================
rem  Restart Ternary-Bonsai-2-27B OpenAI-compatible API server.
rem  Just double-click this file, or pass arguments:
rem      restart-server.cmd -Port 9000
rem      restart-server.cmd -Context 196608
rem      restart-server.cmd -Quiet
rem      restart-server.cmd -NoVerify
rem ================================================================
chcp 65001 >nul 2>&1
setlocal
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restart-server.ps1" %*
set RC=%ERRORLEVEL%

rem Keep the window open on double-click (no arguments) so output is visible
if "%~1"=="" (
    echo.
    pause
)
exit /b %RC%
