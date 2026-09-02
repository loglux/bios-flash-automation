@echo off
setlocal enabledelayedexpansion

REM Resets boot-related BIOS settings back to factory defaults:
REM Fast Boot -> Enable, Boot Order -> disk first (not USB), Startup
REM Delay -> 0. Prints starting and final state to the screen.
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
if !errorlevel! neq 0 (
    echo OK: disk is first in boot order
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
set "in_block=0"
set "disk_line="
for /f "usebackq delims=" %%L in ("%TMPDIR%\config.txt") do (
    set "line=%%L"
    if "!in_block!"=="1" if not "!line!"=="" if not defined disk_line (
        echo !line! | findstr /i "USB Network Ethernet IPV4 IPV6 PXE WI-FI WIFI" >nul
        if !errorlevel! neq 0 set "disk_line=!line!"
    )
    if "!line!"=="%BOOTSETTING%" set "in_block=1"
    if "!in_block!"=="1" if "!line!"=="" set "in_block=0"
)

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
biosconfigutility64 /setvalue:"%nName%","%nDesired%" %PWDARG% >nul 2>&1
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
