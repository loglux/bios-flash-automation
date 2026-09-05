@echo off
setlocal enabledelayedexpansion

REM DRAFT - not yet run on real hardware. Single entry point for the
REM USB flash drive: detects the vendor, then hands off to that
REM vendor's own pipeline. See VendorDispatch/README.md.

set "HP_PIPELINE=%~dp0..\HP\HP-ProBook-BiosCheck-v6.bat"
set "DELL_PIPELINE=%~dp0..\Dell\Dell-SetBootSettings.bat"

set "manufacturer="
for /f "skip=1 tokens=* delims=" %%M in ('wmic computersystem get manufacturer 2^>nul') do (
    if not defined manufacturer if not "%%M"=="" set "manufacturer=%%M"
)
for /f "tokens=* delims= " %%A in ("!manufacturer!") do set "manufacturer=%%A"

if not defined manufacturer (
    echo ERROR: could not read system manufacturer
    exit /b 1
)

echo Manufacturer: !manufacturer!

REM PowerShell -match, not findstr - findstr is confirmed missing on
REM at least one real WinPE build (see Dell/README.md).
powershell -NoProfile -Command "if ('!manufacturer!' -match 'HP|Hewlett-Packard') { exit 0 } else { exit 1 }"
if !errorlevel! equ 0 (
    echo Detected HP - launching HP pipeline
    if not exist "%HP_PIPELINE%" (
        echo ERROR: HP pipeline not found at %HP_PIPELINE%
        exit /b 1
    )
    call "%HP_PIPELINE%"
    exit /b !errorlevel!
)

powershell -NoProfile -Command "if ('!manufacturer!' -match 'Dell') { exit 0 } else { exit 1 }"
if !errorlevel! equ 0 (
    echo Detected Dell - launching Dell pipeline
    if not exist "%DELL_PIPELINE%" (
        echo ERROR: Dell pipeline not found at %DELL_PIPELINE%
        exit /b 1
    )
    call "%DELL_PIPELINE%"
    exit /b !errorlevel!
)

echo ERROR: unrecognized manufacturer '!manufacturer!' - no matching pipeline
exit /b 1
