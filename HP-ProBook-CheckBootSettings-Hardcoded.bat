@echo off
setlocal enabledelayedexpansion

REM Fallback variant of HP-ProBook-CheckBootSettings.bat, for the case
REM where the "findstr USB" heuristic ever fails to identify the boot
REM device correctly. Same three settings (Fast Boot, Boot Order,
REM Startup Delay), but the Boot Order fix writes a hardcoded full list
REM via /setvalue instead of /GetConfig + file edit + /SetConfig.
REM
REM Uses PowerShell instead of findstr throughout - findstr confirmed
REM missing from this project's WinPE on-site (2026-09-02).
REM
REM Simpler code, but two real tradeoffs:
REM - The device list below is specific to the exact machine this was
REM   captured on (2026-09-02, real ProBook, /getvalue:"UEFI Boot
REM   Order") - a different model or BIOS revision may use different
REM   device names entirely, and this script would silently write the
REM   wrong list on such a machine.
REM - Whether /setvalue actually accepts a full ordered-list value like
REM   this is UNCONFIRMED on real hardware - it's a reasonable
REM   inference from HP's own hp-bioscfg Linux kernel driver source and
REM   HP's own official PowerShell/WMI example (see
REM   experimental/PowerShell-Variant.md), not something tested here.
REM
REM HP-ProBook-CheckBootSettings.bat (the non-hardcoded version) stays
REM the one actually relied on until this is verified.

set "TMPDIR=%~dp0temp"
if not exist "%TMPDIR%" mkdir "%TMPDIR%"

set "BOOTSETTING=UEFI Boot Order"
set "STARTUP_DELAY_SETTING=Startup Delay (sec.)"
set "STARTUP_DELAY_DESIRED=5"

REM Captured via "biosconfigutility64 /getvalue:%BOOTSETTING%" on the
REM real target hardware, 2026-09-02 - USB already first at capture
REM time, kept in that order here.
set "USB_FIRST_ORDER=HDD:USB:1,HDD:M.2:1,NETWORK IPV4:EMBEDDED:1,NETWORK IPV6:EMBEDDED:1,WI-FI NETWORK IPV4:EMBEDDED:1,WI-FI NETWORK IPV6:EMBEDDED:1"

echo === Starting state ===
call :ShowValue "Fast Boot"
call :ShowValue "%BOOTSETTING%"
call :ShowValue "%STARTUP_DELAY_SETTING%"
echo.

call :CheckAndFixSimpleSetting "Fast Boot" "Disable"
call :CheckAndFixBootOrderHardcoded
call :CheckAndFixNumberSetting "%STARTUP_DELAY_SETTING%" "%STARTUP_DELAY_DESIRED%"

echo.
echo === Final state ===
call :ShowValue "Fast Boot"
call :ShowValue "%BOOTSETTING%"
call :ShowValue "%STARTUP_DELAY_SETTING%"

exit /b 0


REM ============================================
REM  Fast Boot (simple enum-style setting)
REM ============================================
:CheckAndFixSimpleSetting
set "sName=%~1"
set "sDesired=%~2"
set "attempt=0"

:retry_simple
set /a attempt+=1

set "current="
for /f "delims=" %%C in ('powershell -NoProfile -Command "$raw = (biosconfigutility64 /getvalue:'%sName%') -join [char]10; if ($raw -match '(?s)<!\[CDATA\[(.*?)\]\]>') { foreach ($tok in ($matches[1] -split ',')) { if ($tok -match '^\*') { $tok -replace '^\*',''; break } } }"') do set "current=%%C"

if not defined current (
    echo ERROR: could not read or parse value for '%sName%'
    exit /b 1
)

if /i "!current!"=="%sDesired%" (
    echo OK: %sName% = !current!
    goto :eof
)

if !attempt! gtr 3 (
    echo FAIL: %sName% still '!current!' after 3 attempts
    exit /b 1
)

echo FIX: %sName% is '!current!' -^> setting to '%sDesired%' ^(attempt !attempt!^)
biosconfigutility64 /setvalue:"%sName%","%sDesired%" >nul 2>&1
goto :retry_simple


REM ============================================
REM  Boot Order - hardcoded full list via /setvalue, no /GetConfig
REM ============================================
:CheckAndFixBootOrderHardcoded
set "attempt3=0"

:retry_bootorder_hc
set /a attempt3+=1

set "bostatus="
set "first_entry="
for /f "tokens=1,* delims=|" %%A in ('powershell -NoProfile -Command "$raw = (biosconfigutility64 /getvalue:'%BOOTSETTING%') -join [char]10; if ($raw -match '(?s)<!\[CDATA\[(.*?)\]\]>') { $first = ($matches[1] -split ',')[0]; if ($first -match 'USB') { 'MATCH|' + $first } else { 'NOMATCH|' + $first } } else { 'ERROR|' }"') do (
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

echo FIX: USB not first, writing hardcoded order ^(attempt !attempt3!^)
biosconfigutility64 /setvalue:"%BOOTSETTING%","%USB_FIRST_ORDER%" >nul 2>&1
goto :retry_bootorder_hc


REM ============================================
REM  Generic check/fix for a plain numeric setting
REM ============================================
:CheckAndFixNumberSetting
set "nName=%~1"
set "nDesired=%~2"
set "attempt4=0"

:retry_number
set /a attempt4+=1

set "value="
for /f "delims=" %%C in ('powershell -NoProfile -Command "$raw = (biosconfigutility64 /getvalue:'%nName%') -join [char]10; if ($raw -match '(?s)<!\[CDATA\[(.*?)\]\]>') { $matches[1] }"') do set "value=%%C"

if not defined value (
    echo ERROR: could not read '%nName%'
    exit /b 1
)

if "!value!"=="%nDesired%" (
    echo OK: %nName% = !value!
    goto :eof
)

if !attempt4! gtr 3 (
    echo FAIL: %nName% still '!value!' after 3 attempts
    exit /b 1
)

echo FIX: %nName% is '!value!' -^> setting to '%nDesired%' ^(attempt !attempt4!^)
biosconfigutility64 /setvalue:"%nName%","%nDesired%" >nul 2>&1
goto :retry_number


REM ============================================
REM  Print the raw current value of any setting to the screen
REM ============================================
:ShowValue
set "vName=%~1"
set "value="
for /f "delims=" %%C in ('powershell -NoProfile -Command "$raw = (biosconfigutility64 /getvalue:'%vName%') -join [char]10; if ($raw -match '(?s)<!\[CDATA\[(.*?)\]\]>') { $matches[1] }"') do set "value=%%C"

if not defined value (
    echo %vName%: could not read
    goto :eof
)

echo %vName%: !value!
goto :eof
