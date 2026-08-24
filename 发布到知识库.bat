@echo off
REM ===========================================================================
REM  Publish to notes.231652.xyz
REM
REM  This file is intentionally pure ASCII. Do NOT add Chinese text here.
REM
REM  Reason: cmd.exe parses .bat files using the system ANSI codepage (GBK on
REM  Chinese Windows). A UTF-8 encoded Chinese character is 3 bytes, which
REM  desyncs the parser and silently eats the following characters -- e.g.
REM  "-NoProfile" became "-Profile" and "notes.x" became "otes.x", so the
REM  window flashed and closed. "chcp 65001" only changes the console output
REM  codepage; it does not fix how cmd reads this file.
REM
REM  All Chinese messages are printed by publish.ps1 instead, which handles
REM  UTF-8 correctly.
REM ===========================================================================

REM Switch console to UTF-8 so PowerShell's Chinese output renders correctly
chcp 65001 >nul

cd /d "%~dp0"

REM Tell publish.ps1 not to pause on its own -- this file pauses at the end,
REM otherwise the user would have to press Enter twice.
set PUBLISH_FROM_BAT=1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1"
set EXITCODE=%ERRORLEVEL%

set PUBLISH_FROM_BAT=

echo.
if not "%EXITCODE%"=="0" (
    echo [FAILED] exit code %EXITCODE% - see messages above
)
echo.
pause
exit /b %EXITCODE%
