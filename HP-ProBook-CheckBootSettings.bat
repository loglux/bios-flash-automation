@echo off
setlocal enabledelayedexpansion

REM Checks and fixes three boot-related BIOS settings: Fast Boot,
REM Boot Order (USB first), and Startup Delay. Prints the current
REM value of all three to the screen at the end.
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

set "line="
for /f "delims=" %%i in ('biosconfigutility64 /getvalue:"%BOOTSETTING%" ^| findstr "VALUE"') do set "line=%%i"

if not defined line (
    echo ERROR: could not read '%BOOTSETTING%'
    exit /b 1
)

set "bovalue=!line:*CDATA[=!"
set "bovalue=!bovalue:]]></VALUE>=!"
for /f "tokens=1 delims=," %%A in ("!bovalue!") do set "first_entry=%%A"

echo !first_entry! | findstr /i "USB" >nul
if !errorlevel! equ 0 (
    echo OK: USB is first in boot order
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

set "in_block=0"
set "usb_line="
for /f "usebackq delims=" %%L in ("%TMPDIR%\config.txt") do (
    set "line=%%L"
    if "!in_block!"=="1" if not "!line!"=="" (
        echo !line! | findstr /i "USB" >nul && set "usb_line=!line!"
    )
    if "!line!"=="%BOOTSETTING%" set "in_block=1"
    if "!in_block!"=="1" if "!line!"=="" set "in_block=0"
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

set "line="
for /f "delims=" %%i in ('biosconfigutility64 /getvalue:"%nName%" ^| findstr "VALUE"') do set "line=%%i"

if not defined line (
    echo ERROR: could not read '%nName%'
    exit /b 1
)

set "value=!line:*CDATA[=!"
set "value=!value:]]></VALUE>=!"

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
set "line="
for /f "delims=" %%i in ('biosconfigutility64 /getvalue:"%vName%" ^| findstr "VALUE"') do set "line=%%i"

if not defined line (
    echo %vName%: could not read
    goto :eof
)

set "value=!line:*CDATA[=!"
set "value=!value:]]></VALUE>=!"
echo %vName%: !value!
goto :eof
