@echo off
REM ============================================================
REM  Smart Image Distribution Tool - one-click launcher
REM  Double-click this file to start the tool.
REM ============================================================
setlocal
title Smart Image Distribution Tool
cd /d "%~dp0"

set "SCRIPT=%~dp0Smart_Image_Distribution.ps1"

if not exist "%SCRIPT%" (
    echo.
    echo  [ERROR] Could not find:
    echo          %SCRIPT%
    echo.
    echo  Keep this .cmd file in the same folder as Smart_Image_Distribution.ps1
    echo.
    pause
    exit /b 1
)

REM -ExecutionPolicy Bypass applies to this window only; system policy is not changed.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"

if errorlevel 1 (
    echo.
    echo  The tool closed with an error. See the message above.
    pause
)
endlocal
