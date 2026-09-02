@echo off
setlocal enabledelayedexpansion

REM Step beyond HP-ProBook-BiosCheck-v1.bat (kept as-is, untouched).
REM Checks the current BIOS version against the target. If it doesn't
REM match, logs a message and launches A.bat (the BIOS flash script).
REM If it does match, goes one step further and gates on "Enable MS
REM UEFI CA key": if not Yes, launches B.bat (Security Settings) and
REM re-checks, up to 2 times - never sets the value itself.

set "TARGET_VERSION=01.04.08"
set "FLASH_SCRIPT=%~dp0A.bat"
set "SECURITY_SCRIPT=%~dp0B.bat"

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
echo !biosver! | findstr /i /c:"%TARGET_VERSION%" >nul
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
set "line="
for /f "delims=" %%i in ('biosconfigutility64 /getvalue:"%sName%" ^| findstr "VALUE"') do set "line=%%i"

if not defined line (
    echo ERROR: could not read '%sName%'
    exit /b 1
)

set "value=!line:*CDATA[=!"
set "value=!value:]]></VALUE>=!"
set "current="
for %%A in (%value:,= %) do (
    set "tok=%%A"
    if "!tok:~0,1!"=="*" set "current=!tok:~1!"
)

if not defined current (
    echo ERROR: could not parse value for '%sName%'
    exit /b 1
)

if /i "!current!"=="%sDesired%" (
    echo OK: %sName% = !current!
    exit /b 0
)

if !attempt! gtr 2 (
    echo FAIL: %sName% still '!current!' after running security script %attempt% time^(s^)
    exit /b 1
)

echo NEEDED: %sName% = '!current!' - security script has not run ^(or failed^), launching it

if not exist "%SECURITY_SCRIPT%" (
    echo ERROR: security script not found at %SECURITY_SCRIPT%
    exit /b 1
)

call "%SECURITY_SCRIPT%"
echo Security script finished ^(exit !errorlevel!^), re-checking %sName%
goto :recheck_msuefi
