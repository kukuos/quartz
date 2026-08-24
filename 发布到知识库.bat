@echo off
chcp 65001 >nul
title 发布到知识库 - notes.231652.xyz
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1"
if errorlevel 1 (
    echo.
    echo 发布未成功完成，请查看上方提示。
    pause
)
