@echo off
setlocal enabledelayedexpansion

REM Checks and fixes three boot-related BIOS settings: Fast Boot,
REM Boot Order (USB first), and Startup Delay. Prints the current
REM value of all three to the screen at the end.
REM
REM Uses PowerShell instead of findstr throughout - findstr confirmed
REM missing from this project's WinPE on-site (2026-09-02).
REM
REM NOTE: exact setting name for "Startup Delay" is NOT confirmed on
REM real hardware yet. HP support threads use both "Startup Delay
REM (sec.)" and "Startup Menu Delay (sec.)" for what looks like the
REM same option (Advanced > Boot Options in F10 Setup) - verify with
REM "biosconfigutility64 /getvalue:<name>" on-site; the variable below
REM makes it a one-line fix if the name is wrong.

set "TMPDIR=%~dp0temp"
if not exist "%TMPDIR%" mkdir "%TMPDIR%"

set "BOOTSETTING=UEFI Boot Order"
set "STARTUP_DELAY_SETTING=Startup Delay (sec.)"
set "STARTUP_DELAY_DESIRED=5"

echo === Starting state ===
call :ShowValue "Fast Boot"
call :ShowValue "%BOOTSETTING%"
call :ShowValue "%STARTUP_DELAY_SETTING%"
echo.

call :CheckAndFixSimpleSetting "Fast Boot" "Disable"
call :CheckAndFixBootOrder
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
REM  Boot Order (ordered list) - pure CMD
REM ============================================
:CheckAndFixBootOrder
set "attempt3=0"

:retry_bootorder
set /a attempt3+=1

REM Marker-prefixed output, not errorlevel - "set" between the for /f
REM and the check would clobber errorlevel before it could be read.
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

echo FIX: USB not first, rewriting boot order ^(attempt !attempt3!^)

biosconfigutility64 /GetConfig:"%TMPDIR%\config.txt" >nul 2>&1

set "newfile=%TMPDIR%\config_new.txt"
if exist "%newfile%" del "%newfile%"

REM Find the USB line within the Boot Order block - one PowerShell
REM call instead of a findstr-based batch loop.
set "usb_line="
for /f "delims=" %%U in ('powershell -NoProfile -Command "$lines = Get-Content '%TMPDIR%\config.txt'; $inBlock = $false; $usbLine = $null; foreach ($l in $lines) { if ($inBlock -and $l -ne '' -and -not $usbLine -and $l -match 'USB') { $usbLine = $l }; if ($l -eq '%BOOTSETTING%') { $inBlock = $true }; if ($inBlock -and $l -eq '') { $inBlock = $false } }; $usbLine"') do set "usb_line=%%U"

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
REM  Generic check/fix for a plain numeric setting (no asterisk,
REM  no comma list - just a bare value, e.g. a delay in seconds)
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
