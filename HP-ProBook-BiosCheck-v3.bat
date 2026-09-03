@echo off
setlocal enabledelayedexpansion

REM Step beyond HP-ProBook-BiosCheck-v2.bat (kept as-is, untouched).
REM Checks the current BIOS version against the target. If it doesn't
REM match, logs a message and launches A.bat (the BIOS flash script).
REM If it does match, gates on "Enable MS UEFI CA key": if not Yes,
REM launches B.bat (Security Settings) and re-checks, up to 2 times -
REM never sets the value itself. Once both A and B are confirmed,
REM launches C.bat (the final imaging dialog + Ghost) and exits with
REM its return code.

set "TARGET_VERSION=01.04.08"
set "FLASH_SCRIPT=%~dp0A.bat"
set "SECURITY_SCRIPT=%~dp0B.bat"
set "FINAL_SCRIPT=%~dp0C.bat"
set "PS_GETVALUE=%~dp0HP-ProBook-GetBiosValue.ps1"

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
if !errorlevel! neq 0 (
    echo BIOS version is !biosver!, expected %TARGET_VERSION% - launching flash script

    if not exist "%FLASH_SCRIPT%" (
        echo ERROR: flash script not found at %FLASH_SCRIPT%
        exit /b 1
    )

    call "%FLASH_SCRIPT%"
    exit /b !errorlevel!
)

echo OK: BIOS already at target version %TARGET_VERSION%


REM ============================================
REM  Gate on "Enable MS UEFI CA key"
REM  This option is not important by itself - it is used as an
REM  indicator of whether the security script has run. If not, launch
REM  it (never set the option directly ourselves) and re-check.
REM ============================================
set "sName=Enable MS UEFI CA key"
set "sDesired=Yes"
set "attempt=0"

:recheck_msuefi
set /a attempt+=1

REM Uses the shared HP-ProBook-GetBiosValue.ps1 helper (Enum mode).
set "_pname=%sName%"
set "current="
for /f "delims=" %%C in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_GETVALUE%" -Mode Enum') do set "current=%%C"

if not defined current (
    echo ERROR: could not read or parse value for '!sName!'
    exit /b 1
)

if /i "!current!"=="!sDesired!" (
    echo OK: !sName! = !current!
    goto :launch_final
)

if !attempt! gtr 2 (
    echo FAIL: !sName! still '!current!' after running security script !attempt! time^(s^)
    exit /b 1
)

echo NEEDED: !sName! = '!current!' - security script has not run ^(or failed^), launching it

if not exist "%SECURITY_SCRIPT%" (
    echo ERROR: security script not found at %SECURITY_SCRIPT%
    exit /b 1
)

call "%SECURITY_SCRIPT%"
echo Security script finished ^(exit !errorlevel!^), re-checking !sName!
goto :recheck_msuefi


REM ============================================
REM  A and B both confirmed - hand off to C
REM ============================================
:launch_final
echo OK: stage A (BIOS flash) and stage B (security settings) confirmed

if not exist "%FINAL_SCRIPT%" (
    echo ERROR: final script not found at %FINAL_SCRIPT%
    exit /b 1
)

echo Launching final script (C)
call "%FINAL_SCRIPT%"
exit /b !errorlevel!
