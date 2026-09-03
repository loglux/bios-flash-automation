@echo off
setlocal enabledelayedexpansion

REM Resets boot-related BIOS settings back to factory defaults:
REM Fast Boot -> Enable, Boot Order -> disk first (not USB), Startup
REM Delay -> 0. Prints starting and final state to the screen.
REM
REM Uses PowerShell instead of findstr throughout - findstr confirmed
REM missing from this project's WinPE on-site (2026-09-02). The
REM PowerShell logic lives in separate .ps1 files (HP-ProBook-
REM GetBiosValue.ps1, HP-ProBook-FindConfigLine.ps1), called via
REM "-File" with inputs passed through environment variables - not
REM embedded as inline "-Command" text. Confirmed on-site (2026-09-03)
REM that embedding PowerShell code with parentheses directly in a
REM "for /f (...)" call breaks cmd.exe's parser ("was unexpected at
REM this time"), even when the parentheses are inside quotes; this is
REM a documented cmd.exe limitation (the FOR /F parser itself scans
REM the command text for parentheses), not something quoting can fix.
REM
REM PWD_FILE: optional current-password file for biosconfigutility64,
REM only needed if a BIOS Setup password is already set on this
REM machine (e.g. running this on a machine that already went through
REM B.bat, which is what actually sets the password - not something
REM this script or A.bat's password file has anything to do with).
REM Empty by default - not used. If /setvalue or /SetConfig calls
REM start failing with a password-related error, set this to the
REM password file name; it gets appended to every write call below.
set "PWD_FILE="

set "TMPDIR=%~dp0temp"
if not exist "%TMPDIR%" mkdir "%TMPDIR%"

set "BOOTSETTING=UEFI Boot Order"
set "STARTUP_DELAY_SETTING=Startup Delay (sec.)"
set "STARTUP_DELAY_DESIRED=0"

set "PWDARG="
if defined PWD_FILE set PWDARG=/cpwdfile:"%PWD_FILE%"

set "PS_GETVALUE=%~dp0HP-ProBook-GetBiosValue.ps1"
set "PS_BOOTFIRST=%~dp0HP-ProBook-CheckBootOrderFirst.ps1"
set "PS_FINDLINE=%~dp0HP-ProBook-FindConfigLine.ps1"

echo === Starting state ===
call :ShowValue "Fast Boot"
call :ShowValue "%BOOTSETTING%"
call :ShowValue "%STARTUP_DELAY_SETTING%"
echo.

call :CheckAndFixSimpleSetting "Fast Boot" "Enable"
call :CheckAndFixBootOrderReset
call :CheckAndFixNumberSetting "%STARTUP_DELAY_SETTING%" "%STARTUP_DELAY_DESIRED%"

echo.
echo === Final state ===
call :ShowValue "Fast Boot"
call :ShowValue "%BOOTSETTING%"
call :ShowValue "%STARTUP_DELAY_SETTING%"

exit /b 0


REM ============================================
REM  Generic check/fix for an enum setting
REM ============================================
:CheckAndFixSimpleSetting
set "sName=%~1"
set "sDesired=%~2"
set "attempt=0"

:retry_simple
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
    goto :eof
)

if !attempt! gtr 3 (
    echo FAIL: !sName! still '!current!' after 3 attempts
    exit /b 1
)

echo FIX: !sName! is '!current!' -^> setting to '!sDesired!' ^(attempt !attempt!^)
biosconfigutility64 /setvalue:"%sName%","%sDesired%" %PWDARG% >nul 2>&1
goto :retry_simple


REM ============================================
REM  Boot Order reset: make sure the internal disk boots first, not
REM  USB - the inverse of the "USB first" check used elsewhere.
REM ============================================
:CheckAndFixBootOrderReset
set "attempt3=0"

:retry_bootorder_reset
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

if "!bostatus!"=="NOMATCH" (
    echo OK: disk is first in boot order ^(!first_entry!^)
    goto :eof
)

if !attempt3! gtr 3 (
    echo FAIL: boot order still USB-first after 3 attempts
    exit /b 1
)

echo FIX: USB still first, moving disk entry to top ^(attempt !attempt3!^)

biosconfigutility64 /GetConfig:"%TMPDIR%\config.txt" >nul 2>&1

set "newfile=%TMPDIR%\config_new.txt"
if exist "%newfile%" del "%newfile%"

REM Find the disk entry: first line in the block that isn't USB,
REM network, PXE, or Wi-Fi - same elimination approach already used
REM for the BootNext firmware-entry lookup (see
REM experimental/BCDEdit-BootSequence-Notes.md).
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


REM ============================================
REM  Generic check/fix for a plain numeric setting
REM ============================================
:CheckAndFixNumberSetting
set "nName=%~1"
set "nDesired=%~2"
set "attempt4=0"

:retry_number
set /a attempt4+=1

set "_pname=%nName%"
set "value="
for /f "delims=" %%C in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_GETVALUE%"') do set "value=%%C"

if not defined value (
    echo ERROR: could not read '!nName!'
    exit /b 1
)

if "!value!"=="!nDesired!" (
    echo OK: !nName! = !value!
    goto :eof
)

if !attempt4! gtr 3 (
    echo FAIL: !nName! still '!value!' after 3 attempts
    exit /b 1
)

echo FIX: !nName! is '!value!' -^> setting to '!nDesired!' ^(attempt !attempt4!^)
biosconfigutility64 /setvalue:"%nName%","%nDesired%" %PWDARG% >nul 2>&1
goto :retry_number


REM ============================================
REM  Print the raw current value of any setting to the screen
REM ============================================
:ShowValue
set "vName=%~1"
set "_pname=%vName%"
set "value="
for /f "delims=" %%C in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_GETVALUE%"') do set "value=%%C"

if not defined value (
    echo !vName!: could not read
    goto :eof
)

echo !vName!: !value!
goto :eof
