@echo off
rem ================================================================
rem  Add a Windows Firewall rule so other devices on the LAN can
rem  reach the Ternary-Bonsai API server.
rem
rem  *** Right-click this file -> "Run as administrator" ***
rem
rem  Options (pass through to the PowerShell script):
rem      -Status     show current rule
rem      -Remove     delete the rule
rem      -Port 9000  use a different port
rem ================================================================
chcp 65001 >nul 2>&1
setlocal
cd /d "%~dp0"

rem --- self-elevate if not already admin ---
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','\"%~f0\" %*' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0allow-firewall.ps1" %*
echo.
pause
