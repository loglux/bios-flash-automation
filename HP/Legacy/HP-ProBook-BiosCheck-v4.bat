@echo off
setlocal enabledelayedexpansion

REM Step beyond HP-ProBook-BiosCheck-v3.bat (kept as-is, untouched).
REM Checks and fixes Fast Boot, Boot Order (USB first), and Startup
REM Delay first - same logic as HP-ProBook-CheckBootSettings.bat -
REM then runs the same A/B/C pipeline as v3: checks the BIOS version
REM and launches A.bat if it doesn't match, gates on "Enable MS UEFI
REM CA key" and launches B.bat if needed, then launches C.bat once
REM both are confirmed.

set "TARGET_VERSION=01.04.08"
set "FLASH_SCRIPT=%~dp0A.bat"
set "SECURITY_SCRIPT=%~dp0B.bat"
set "FINAL_SCRIPT=%~dp0C.bat"

set "TMPDIR=%~dp0temp"
if not exist "%TMPDIR%" mkdir "%TMPDIR%"

set "BOOTSETTING=UEFI Boot Order"
set "STARTUP_DELAY_SETTING=Startup Delay (sec.)"
set "STARTUP_DELAY_DESIRED=5"

set "PS_GETVALUE=%~dp0HP-ProBook-GetBiosValue.ps1"
set "PS_BOOTFIRST=%~dp0HP-ProBook-CheckBootOrderFirst.ps1"
set "PS_FINDLINE=%~dp0HP-ProBook-FindConfigLine.ps1"


REM ============================================
REM  STEP 1: boot settings, before anything else
REM ============================================
call :CheckAndFixSimpleSetting "Fast Boot" "Disable"
call :CheckAndFixBootOrder
call :CheckAndFixSimpleSetting "%STARTUP_DELAY_SETTING%" "%STARTUP_DELAY_DESIRED%"


REM ============================================
REM  STEP 2: BIOS version -> A.bat if needed
REM ============================================
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
REM  STEP 3: gate on "Enable MS UEFI CA key" -> B.bat if needed
REM  This option is not important by itself - it is used as an
REM  indicator of whether the security script has run. If not, launch
REM  it (never set the option directly ourselves) and re-check.
REM ============================================
set "sName=Enable MS UEFI CA key"
set "sDesired=Yes"
set "attempt=0"

:recheck_msuefi
set /a attempt+=1

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
REM  STEP 4: A and B both confirmed - hand off to C
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


REM ============================================
REM  Fast Boot / Startup Delay (enum-style setting)
REM ============================================
:CheckAndFixSimpleSetting
set "sName2=%~1"
set "sDesired2=%~2"
set "attempt2=0"

:retry_simple
set /a attempt2+=1

set "_pname=%sName2%"
set "current2="
for /f "delims=" %%C in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_GETVALUE%" -Mode Enum') do set "current2=%%C"

if not defined current2 (
    echo ERROR: could not read or parse value for '!sName2!'
    exit /b 1
)

if /i "!current2!"=="!sDesired2!" (
    echo OK: !sName2! = !current2!
    goto :eof
)

if !attempt2! gtr 3 (
    echo FAIL: !sName2! still '!current2!' after 3 attempts
    exit /b 1
)

echo FIX: !sName2! is '!current2!' -^> setting to '!sDesired2!' ^(attempt !attempt2!^)
biosconfigutility64 /setvalue:"%sName2%","%sDesired2%" >nul 2>&1
goto :retry_simple


REM ============================================
REM  Boot Order (ordered list) - pure CMD
REM ============================================
:CheckAndFixBootOrder
set "attempt3=0"

:retry_bootorder
set /a attempt3+=1

set "_pname=%BOOTSETTING%"
set "bostatus="
set "first_entry="
for /f "tokens=1,* delims=|" %%A in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_BOOTFIRST%"') do (
    set "bostatus=%%A"
    set "first_entry=%%B"
)

if "!bostatus!"=="ERROR" (
    echo ERROR: could not read '%BOOTSETTING%'
    exit /b 1
)

if "!bostatus!"=="MATCH" (
    echo OK: USB is first in boot order ^(!first_entry!^)
    goto :eof
)

if !attempt3! gtr 3 (
    echo FAIL: boot order still not USB-first after 3 attempts
    exit /b 1
)

echo FIX: USB not first, rewriting boot order ^(attempt !attempt3!^)

biosconfigutility64 /GetConfig:"%TMPDIR%\config.txt" >nul 2>&1

set "newfile=%TMPDIR%\config_new.txt"
if exist "%newfile%" del "%newfile%"

set "_pcfg=%TMPDIR%\config.txt"
set "_pname=%BOOTSETTING%"
set "_ppattern=USB"
set "usb_line="
for /f "delims=" %%U in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_FINDLINE%"') do set "usb_line=%%U"

if not defined usb_line (
    echo ERROR: could not find a USB entry in '%BOOTSETTING%' block
    exit /b 1
)

set "in_block=0"
set "wrote_usb=0"
(
for /f "usebackq delims=" %%L in ("%TMPDIR%\config.txt") do (
    set "line=%%L"
    if "!in_block!"=="1" (
        if "!line!"=="" (
            set "in_block=0"
            echo(
        ) else (
            if "!wrote_usb!"=="0" (
                echo !usb_line!
                set "wrote_usb=1"
            )
            if not "!line!"=="!usb_line!" echo !line!
        )
    ) else (
        echo !line!
    )
    if "!line!"=="%BOOTSETTING%" set "in_block=1"
)
) > "%newfile%"

move /y "%newfile%" "%TMPDIR%\config.txt" >nul
biosconfigutility64 /SetConfig:"%TMPDIR%\config.txt" >nul 2>&1
goto :retry_bootorder
