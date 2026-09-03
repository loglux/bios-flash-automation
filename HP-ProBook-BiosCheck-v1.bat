@echo off
setlocal enabledelayedexpansion

REM Checks the current BIOS version against the target. If it already
REM matches, exits with no action. If not, logs a message and launches
REM A.bat (the BIOS flash script).

set "TARGET_VERSION=01.04.08"
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

REM Substring match, not exact equality - some platforms report the
REM version with a product-code prefix (e.g. "X78 Ver. 01.04.08"), not
REM the bare number, which would never equal TARGET_VERSION exactly.
REM [regex]::Escape matters: without it, dots are read as "any char".
powershell -NoProfile -Command "if ('!biosver!' -match [regex]::Escape('%TARGET_VERSION%')) { exit 0 } else { exit 1 }"
if !errorlevel! equ 0 (
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
