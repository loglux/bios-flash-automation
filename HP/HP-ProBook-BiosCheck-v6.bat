@echo off
setlocal enabledelayedexpansion

REM Step beyond HP-ProBook-BiosCheck-v5.bat (kept as-is, untouched).
REM Same pipeline as v5, but the boot-settings enable checks no longer
REM run unconditionally up front - they run right before each of A.bat
REM and B.bat, only when that script is actually about to launch. If
REM the BIOS version and CA key are already correct (A/B don't need to
REM run), the boot settings are never touched at all, avoiding a
REM pointless enable-then-reset cycle before C.bat.

set "TARGET_VERSION=01.04.08"
set "FLASH_SCRIPT=%~dp0A.bat"
set "SECURITY_SCRIPT=%~dp0B.bat"
set "FINAL_SCRIPT=%~dp0C.bat"

REM Current-password file for biosconfigutility64 - the real password
REM B.bat sets via /npwdfile. Needed for the reset step below, since
REM B.bat has already run by then.
set "PWD_FILE=hpbiospw.bin"
set "PWDARG="
if defined PWD_FILE set PWDARG=/cpwdfile:"%PWD_FILE%"

set "TMPDIR=%~dp0temp"
if not exist "%TMPDIR%" mkdir "%TMPDIR%"

set "BOOTSETTING=UEFI Boot Order"
set "STARTUP_DELAY_SETTING=Startup Delay (sec.)"
set "STARTUP_DELAY_DESIRED=5"
set "STARTUP_DELAY_RESET=0"

set "PS_GETVALUE=%~dp0HP-ProBook-GetBiosValue.ps1"
set "PS_BOOTFIRST=%~dp0HP-ProBook-CheckBootOrderFirst.ps1"
set "PS_FINDLINE=%~dp0HP-ProBook-FindConfigLine.ps1"


REM ============================================
REM  STEP 1: BIOS version -> A.bat if needed. Boot settings are
REM  checked/enabled right before the call, not unconditionally.
REM
REM  Manufacturer/Model read here too, via the shared SystemIdentity/
REM  module - not used for branching yet (only one real HP model in
REM  the fleet so far), just logged and defensively checked, as
REM  groundwork for a future vendor+model dispatch shared across HP
REM  and Dell. See SystemIdentity/README.md.
REM ============================================
set "PS_SYSID=%~dp0SystemIdentity-Check.ps1"

set "Manufacturer="
set "Model="
set "SerialNumber="
set "BiosVersion="
for /f "tokens=1,* delims=|" %%A in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SYSID%"') do (
    set "%%A=%%B"
)
set "biosver=%BiosVersion%"

if not defined biosver (
    echo ERROR: could not read BIOS version
    exit /b 1
)

echo Manufacturer: %Manufacturer%   Model: %Model%   BIOS Version: !biosver!

REM Defense in depth - VendorDispatch.bat already checks this before
REM calling this script, but this script can also be run directly.
REM PowerShell -match, not findstr - findstr is confirmed missing on
REM at least one real WinPE build (see Dell/README.md).
if defined Manufacturer (
    powershell -NoProfile -Command "if ('%Manufacturer%' -match 'HP|Hewlett-Packard') { exit 0 } else { exit 1 }"
    if !errorlevel! neq 0 (
        echo ERROR: this script is HP-only, detected manufacturer: %Manufacturer%
        exit /b 1
    )
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

    call :CheckAndFixSimpleSetting "Fast Boot" "Disable"
    call :CheckAndFixBootOrder
    call :CheckAndFixSimpleSetting "%STARTUP_DELAY_SETTING%" "%STARTUP_DELAY_DESIRED%"

    call "%FLASH_SCRIPT%"
    exit /b !errorlevel!
)

echo OK: BIOS already at target version %TARGET_VERSION%


REM ============================================
REM  STEP 2: gate on "Enable MS UEFI CA key" -> B.bat if needed
REM  This option is not important by itself - it is used as an
REM  indicator of whether the security script has run. If not, launch
REM  it (never set the option directly ourselves) and re-check. Boot
REM  settings are checked/enabled right before the call.
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
    goto :reset_boot_settings
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

call :CheckAndFixSimpleSetting "Fast Boot" "Disable"
call :CheckAndFixBootOrder
call :CheckAndFixSimpleSetting "%STARTUP_DELAY_SETTING%" "%STARTUP_DELAY_DESIRED%"

call "%SECURITY_SCRIPT%"
echo Security script finished ^(exit !errorlevel!^), re-checking !sName!
goto :recheck_msuefi


REM ============================================
REM  STEP 3: A and B confirmed - reset boot settings to factory
REM  defaults before handing off to C.
REM ============================================
:reset_boot_settings
call :ResetSimpleSetting "Fast Boot" "Enable"
call :CheckAndFixBootOrderReset
call :ResetSimpleSetting "%STARTUP_DELAY_SETTING%" "%STARTUP_DELAY_RESET%"


REM ============================================
REM  STEP 4: hand off to C
REM ============================================
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
REM  Same as :CheckAndFixSimpleSetting, but for the post-B.bat reset
REM  pass, where a BIOS password is set - adds /cpwdfile.
REM ============================================
:ResetSimpleSetting
set "sName3=%~1"
set "sDesired3=%~2"
set "attempt5=0"

:retry_reset_simple
set /a attempt5+=1

set "_pname=%sName3%"
set "current3="
for /f "delims=" %%C in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_GETVALUE%" -Mode Enum') do set "current3=%%C"

if not defined current3 (
    echo ERROR: could not read or parse value for '!sName3!'
    exit /b 1
)

if /i "!current3!"=="!sDesired3!" (
    echo OK: !sName3! = !current3!
    goto :eof
)

if !attempt5! gtr 3 (
    echo FAIL: !sName3! still '!current3!' after 3 attempts
    exit /b 1
)

echo FIX: !sName3! is '!current3!' -^> setting to '!sDesired3!' ^(attempt !attempt5!^)
biosconfigutility64 /setvalue:"%sName3%","%sDesired3%" %PWDARG% >nul 2>&1
goto :retry_reset_simple


REM ============================================
REM  Boot Order (ordered list) - USB first, before A.bat / B.bat
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


REM ============================================
REM  Boot Order reset: disk first, not USB - the inverse of
REM  :CheckAndFixBootOrder above, used right before C.bat.
REM ============================================
:CheckAndFixBootOrderReset
set "attempt4=0"

:retry_bootorder_reset
set /a attempt4+=1

set "_pname=%BOOTSETTING%"
set "bostatus2="
set "first_entry2="
for /f "tokens=1,* delims=|" %%A in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_BOOTFIRST%"') do (
    set "bostatus2=%%A"
    set "first_entry2=%%B"
)

if "!bostatus2!"=="ERROR" (
    echo ERROR: could not read '%BOOTSETTING%'
    exit /b 1
)

if "!bostatus2!"=="NOMATCH" (
    echo OK: disk is first in boot order ^(!first_entry2!^)
    goto :eof
)

if !attempt4! gtr 3 (
    echo FAIL: boot order still USB-first after 3 attempts
    exit /b 1
)

echo FIX: USB still first, moving disk entry to top ^(attempt !attempt4!^)

biosconfigutility64 /GetConfig:"%TMPDIR%\config.txt" >nul 2>&1

set "newfile=%TMPDIR%\config_new.txt"
if exist "%newfile%" del "%newfile%"

set "_pcfg=%TMPDIR%\config.txt"
set "_pname=%BOOTSETTING%"
set "_ppattern=(?i)USB|Network|Ethernet|IPV4|IPV6|PXE|WI-FI|WIFI"
set "disk_line="
for /f "delims=" %%D in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_FINDLINE%" -Exclude') do set "disk_line=%%D"

if not defined disk_line (
    echo ERROR: could not find a non-USB, non-network entry to move to the top
    exit /b 1
)

set "in_block=0"
set "wrote_disk=0"
(
for /f "usebackq delims=" %%L in ("%TMPDIR%\config.txt") do (
    set "line=%%L"
    if "!in_block!"=="1" (
        if "!line!"=="" (
            set "in_block=0"
            echo(
        ) else (
            if "!wrote_disk!"=="0" (
                echo !disk_line!
                set "wrote_disk=1"
            )
            if not "!line!"=="!disk_line!" echo !line!
        )
    ) else (
        echo !line!
    )
    if "!line!"=="%BOOTSETTING%" set "in_block=1"
)
) > "%newfile%"

move /y "%newfile%" "%TMPDIR%\config.txt" >nul
biosconfigutility64 /SetConfig:"%TMPDIR%\config.txt" %PWDARG% >nul 2>&1
goto :retry_bootorder_reset
