@echo off
setlocal enabledelayedexpansion

REM Checks and fixes three boot-related BIOS settings: Fast Boot,
REM Boot Order (USB first), and Startup Delay. Prints the current
REM value of all three to the screen at the end.
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
REM "Startup Delay (sec.)" confirmed on real hardware (2026-09-03) -
REM both the setting name and that it's enum-style, not a plain
REM number: /getvalue returns the full allowed range with the current
REM one asterisk-marked (e.g. "*0,5,10,...,60"), same shape as Fast
REM Boot. Checked/fixed via :CheckAndFixSimpleSetting like Fast Boot,
REM not a separate numeric-setting routine.

set "TMPDIR=%~dp0temp"
if not exist "%TMPDIR%" mkdir "%TMPDIR%"

set "BOOTSETTING=UEFI Boot Order"
set "STARTUP_DELAY_SETTING=Startup Delay (sec.)"
set "STARTUP_DELAY_DESIRED=5"

set "PS_GETVALUE=%~dp0HP-ProBook-GetBiosValue.ps1"
set "PS_BOOTFIRST=%~dp0HP-ProBook-CheckBootOrderFirst.ps1"
set "PS_FINDLINE=%~dp0HP-ProBook-FindConfigLine.ps1"

echo === Starting state ===
call :ShowValue "Fast Boot"
call :ShowValue "%BOOTSETTING%"
call :ShowValue "%STARTUP_DELAY_SETTING%"
echo.

call :CheckAndFixSimpleSetting "Fast Boot" "Disable"
call :CheckAndFixBootOrder
call :CheckAndFixSimpleSetting "%STARTUP_DELAY_SETTING%" "%STARTUP_DELAY_DESIRED%"

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
biosconfigutility64 /setvalue:"%sName%","%sDesired%" >nul 2>&1
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
