@echo off
setlocal enabledelayedexpansion

REM Checks the current BIOS version against the target. If it already
REM matches, exits with no action. If not, logs a message and launches
REM A.bat (the BIOS flash script).

set "TARGET_VERSION=10.04.08"
set "FLASH_SCRIPT=%~dp0A.bat"

set "biosver="
for /f "skip=1 tokens=* delims=" %%V in ('wmic bios get smbiosbiosversion 2^>nul') do (
    if not defined biosver if not "%%V"=="" set "biosver=%%V"
)
for /f "tokens=* delims= " %%A in ("!biosver!") do set "biosver=%%A"

if not defined biosver (
    echo ERROR: could not read BIOS version
    exit /b 1
)

if /i "!biosver!"=="%TARGET_VERSION%" (
    echo OK: BIOS already at target version %TARGET_VERSION%
    exit /b 0
)

echo BIOS version is !biosver!, expected %TARGET_VERSION% - launching flash script

if not exist "%FLASH_SCRIPT%" (
    echo ERROR: flash script not found at %FLASH_SCRIPT%
    exit /b 1
)

call "%FLASH_SCRIPT%"
exit /b !errorlevel!
