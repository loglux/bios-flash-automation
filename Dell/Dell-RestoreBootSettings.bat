@echo off
setlocal enabledelayedexpansion

REM DRAFT - not yet verified on real Dell hardware.
REM Restores the BIOS settings snapshot written by
REM Dell-SetBootSettings.bat before it made any changes.

set "CCTK=%~dp0cctk.exe"
set "BACKUP_INI=%~dp0dell-bios-backup.ini"

if not exist "%BACKUP_INI%" (
    echo ERROR: no backup file found at %BACKUP_INI%
    exit /b 1
)

"%CCTK%" -i "%BACKUP_INI%"
exit /b !errorlevel!
