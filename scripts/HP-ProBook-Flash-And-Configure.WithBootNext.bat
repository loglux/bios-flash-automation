@echo off
setlocal enabledelayedexpansion

REM ============================================
REM  SETTINGS
REM ============================================
set "TARGET_VERSION=10.04.08"
set "MAXATTEMPTS=3"
set "STAGELOG=%~dp0stage.log"
set "TMPDIR=%~dp0temp"
if not exist "%TMPDIR%" mkdir "%TMPDIR%"

REM --- BIOS flash ---
REM Flags per HP's documented syntax for HPBIOSUPDREC64.exe (still worth a
REM one-time "HPBIOSUPDREC64.exe -?" check on-site to confirm this exact
REM utility version matches):
REM   -s  silent               -f  path to the .bin file        -l  log path
REM   -a  always flash, ignore version check (silent mode only)
REM   -r  do not reboot        -h  create HP_TOOLS partition if missing
REM   -b  suspend BitLocker    -p  encrypted BIOS password file (if a BIOS
REM                                password is set on the machines)
set "FLASH_TOOL=%~dp0HPBIOSUPDREC64.exe"
set "FLASH_IMAGE=%~dp0firmware\10.04.08.bin"
set "FLASH_LOG=%~dp0flash_result.log"

REM --- Script B (Security Settings, including MS UEFI CA key) ---
REM TODO: fill in the actual name/path of B.bat
set "SECURITY_SCRIPT=%~dp0B.bat"

REM --- Script C (dialog + Ghost, final stage, we don't touch its internal logic) ---
REM TODO: fill in the actual name/path of C.bat
set "FINAL_SCRIPT=%~dp0C.bat"


REM ============================================
REM  START - bind the state file to the machine's serial number
REM ============================================
set "machineid="
for /f "skip=1 tokens=* delims=" %%S in ('wmic bios get serialnumber 2^>nul') do (
    if not defined machineid if not "%%S"=="" set "machineid=%%S"
)
for /f "tokens=* delims= " %%A in ("!machineid!") do set "machineid=%%A"
if not defined machineid set "machineid=UNKNOWN"

set "STATEFILE=%~dp0flash_attempt_!machineid!.state"

set "attempt=0"
if exist "%STATEFILE%" set /p attempt=<"%STATEFILE%"

call :SetStage "=== SCRIPT START (machine: !machineid!, attempt !attempt!) ==="


REM ============================================
REM  STEP 1: check boot settings BEFORE flashing
REM ============================================
call :SetStage "Checking boot settings before flash"
call :CheckAndFixSimpleSetting "Fast Boot" "Disable"
call :CheckAndFixBootOrder


REM ============================================
REM  STEP 2: check BIOS version
REM ============================================
call :GetBiosVersion
call :SetStage "Current BIOS version: !biosver! (target: %TARGET_VERSION%)"

if /i "!biosver!"=="%TARGET_VERSION%" (
    call :SetStage "OK: BIOS already at target version"
    if exist "%STATEFILE%" del "%STATEFILE%"
    goto :after_flash_confirmed
)

if !attempt! geq %MAXATTEMPTS% (
    call :SetStage "FAIL: still on '!biosver!' after %MAXATTEMPTS% attempts, expected %TARGET_VERSION%"
    exit /b 1
)


REM ============================================
REM  STEP 3: flash
REM ============================================
set /a attempt+=1
echo !attempt! > "%STATEFILE%"
call :SetStage "Flashing BIOS (attempt !attempt! of %MAXATTEMPTS%)"

if not exist "%FLASH_TOOL%" (
    call :SetStage "ERROR: flash tool not found at %FLASH_TOOL%"
    exit /b 1
)
if not exist "%FLASH_IMAGE%" (
    call :SetStage "ERROR: firmware image not found at %FLASH_IMAGE%"
    exit /b 1
)

REM --- TODO: verify and finalize the flag set below ---
REM -r (do not reboot) is required here: without it, the tool likely reboots
REM the machine itself once it's done, before control returns to this script
REM - which would skip the logging/BootNext/reboot-control logic below.
"%FLASH_TOOL%" -s -r -f"%FLASH_IMAGE%" -l"%FLASH_LOG%"
call :SetStage "Flash command finished (exit !errorlevel!), see %FLASH_LOG% for details"


REM ============================================
REM  STEP 4: reboot
REM  NOTE: no boot-settings re-check here - the actual firmware write only
REM  happens during POST on this reboot, not while HPBIOSUPDREC64.exe was
REM  running, so nothing has changed since Step 1's check. The authoritative
REM  check is in :after_flash_confirmed, once the reboot has happened.
REM
REM  EXPERIMENTAL (this variant only): also set a one-time BootNext override
REM  via bcdedit, as an extra safety net alongside the BootOrder fix above -
REM  see docs/Boot-Order-Reset-Risk.md. Unverified whether BootNext survives
REM  the same reset that can wipe BootOrder during this flash.
REM ============================================
call :SetBootNextUSB
call :SetStage "Rebooting in 5 sec to apply flash..."
shutdown /r /t 5
exit /b 0


REM ============================================
REM  VERSION CONFIRMED - continue the pipeline
REM ============================================
:after_flash_confirmed
call :SetStage "=== BIOS FLASH CONFIRMED at %TARGET_VERSION% ==="

call :SetStage "Final check of boot settings"
call :CheckAndFixSimpleSetting "Fast Boot" "Disable"
call :CheckAndFixBootOrder

call :SetStage "Checking MS UEFI CA key"
call :CheckMSUEFICAKey

call :SetStage "OK: stage A (BIOS flash) and stage B (security settings) confirmed"

if not exist "%FINAL_SCRIPT%" (
    call :SetStage "ERROR: final script not found at %FINAL_SCRIPT%"
    exit /b 1
)

call :SetStage "Launching final script (C)"
call "%FINAL_SCRIPT%"
exit /b !errorlevel!


REM ============================================
REM  Read current BIOS version
REM ============================================
:GetBiosVersion
set "biosver="
for /f "skip=1 tokens=* delims=" %%V in ('wmic bios get smbiosbiosversion 2^>nul') do (
    if not defined biosver if not "%%V"=="" set "biosver=%%V"
)
for /f "tokens=* delims= " %%A in ("!biosver!") do set "biosver=%%A"
if not defined biosver (
    call :SetStage "ERROR: could not read BIOS version"
    exit /b 1
)
goto :eof


REM ============================================
REM  Generic check/fix for an enum setting
REM ============================================
:CheckAndFixSimpleSetting
set "sName=%~1"
set "sDesired=%~2"
set "attempt2=0"

:retry_simple
set /a attempt2+=1
set "line="
for /f "delims=" %%i in ('biosconfigutility64 /getvalue:"%sName%" ^| findstr "VALUE"') do set "line=%%i"

if not defined line (
    call :SetStage "ERROR: could not read '%sName%'"
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
    call :SetStage "ERROR: could not parse value for '%sName%'"
    exit /b 1
)

if /i "!current!"=="%sDesired%" (
    call :SetStage "OK: %sName% = !current!"
    goto :eof
)

if !attempt2! gtr 3 (
    call :SetStage "FAIL: %sName% still '!current!' after 3 attempts"
    exit /b 1
)

call :SetStage "FIX: %sName% is '!current!' -> setting to '%sDesired%' (attempt !attempt2!)"
biosconfigutility64 /setvalue:"%sName%","%sDesired%" >nul 2>&1
goto :retry_simple


REM ============================================
REM  Boot Order (ordered list) - pure CMD
REM ============================================
:CheckAndFixBootOrder
set "BOOTSETTING=UEFI Boot Order"
set "attempt3=0"

:retry_bootorder
set /a attempt3+=1
biosconfigutility64 /GetConfig:"%TMPDIR%\config.txt" >nul 2>&1

set "found_header="
set "first_after="
for /f "usebackq delims=" %%L in ("%TMPDIR%\config.txt") do (
    if defined found_header if not defined first_after set "first_after=%%L"
    if "%%L"=="%BOOTSETTING%" set "found_header=1"
)

if not defined found_header (
    call :SetStage "ERROR: '%BOOTSETTING%' not found in config.txt"
    exit /b 1
)

echo !first_after! | findstr /i "USB" >nul
if !errorlevel! equ 0 (
    call :SetStage "OK: USB is first in boot order"
    goto :eof
)

if !attempt3! gtr 3 (
    call :SetStage "FAIL: boot order still not USB-first after 3 attempts"
    exit /b 1
)

call :SetStage "FIX: USB not first, rewriting boot order (attempt !attempt3!)"

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
REM  MS UEFI CA key - GATE for script B (Security Settings)
REM  This option is not important by itself - it is used as an
REM  indicator of whether script B has run. If not, we launch B
REM  (we don't set the option directly ourselves, so we don't
REM  lose its other settings) and re-check.
REM ============================================
:CheckMSUEFICAKey
set "sName=Enable MS UEFI CA key"
set "sDesired=Yes"
set "attempt4=0"

:recheck_msuefi
set /a attempt4+=1
set "line="
for /f "delims=" %%i in ('biosconfigutility64 /getvalue:"%sName%" ^| findstr "VALUE"') do set "line=%%i"

if not defined line (
    call :SetStage "ERROR: could not read '%sName%'"
    exit /b 1
)

set "value=!line:*CDATA[=!"
set "value=!value:]]></VALUE>=!"
set "current="
for %%A in (%value:,= %) do (
    set "tok=%%A"
    if "!tok:~0,1!"=="*" set "current=!tok:~1!"
)

if /i "!current!"=="%sDesired%" (
    call :SetStage "OK: %sName% = !current! (script B has run)"
    goto :eof
)

if !attempt4! gtr 2 (
    call :SetStage "FAIL: %sName% still '!current!' after running script B %attempt4% time(s)"
    exit /b 1
)

call :SetStage "NEEDED: %sName% = '!current!' - script B has not run (or failed), launching it"

if not exist "%SECURITY_SCRIPT%" (
    call :SetStage "ERROR: security script not found at %SECURITY_SCRIPT%"
    exit /b 1
)

call "%SECURITY_SCRIPT%"
set "bresult=!errorlevel!"
call :SetStage "Script B finished (exit !bresult!), re-checking %sName%"
goto :recheck_msuefi


REM ============================================
REM  One-time BootNext override via bcdedit (EXPERIMENTAL)
REM  Extra safety net alongside :CheckAndFixBootOrder - not a replacement.
REM  See docs/Boot-Order-Reset-Risk.md for the rationale and open questions.
REM
REM  Matches by ELIMINATION, not by a positive USB signal. Real-hardware
REM  testing (both an ordinary PC and the actual ProBook) showed neither a
REM  "USB" keyword nor a device/drive-letter field can be relied on - the
REM  real ProBook entry for the boot USB had only identifier+description,
REM  no device= line, and description was the drive's own brand/model/
REM  serial (e.g. "Kingston DataTraveler 3.0 <serial>"), never "USB".
REM
REM  So instead: scan all "Firmware Application" entries (this excludes
REM  Firmware Boot Manager and Windows Boot Manager), skip any whose
REM  description matches known network/PXE keywords (confirmed present on
REM  the real ProBook: "IPV4 Network - Realtek PCIe GBE Family Controller"),
REM  and use whatever's left. On a fleet of identical hardware (same NIC),
REM  this is a real but imperfect heuristic - it would misidentify a
REM  machine with some other unexpected Firmware Application entry (e.g.
REM  a card reader). Not a hardcoded brand/model - works for any USB drive.
REM ============================================
:SetBootNextUSB
set "fwdump=%TMPDIR%\firmware.txt"
bcdedit /enum firmware > "%fwdump%" 2>nul

set "found_id="
set "current_id="
set "in_fwapp=0"
for /f "usebackq delims=" %%L in ("%fwdump%") do (
    set "line=%%L"
    echo !line! | findstr /i "^Firmware Application" >nul && set "in_fwapp=1"
    echo !line! | findstr /i "^Windows Boot Manager" >nul && set "in_fwapp=0"
    echo !line! | findstr /i "^Firmware Boot Manager" >nul && set "in_fwapp=0"

    if "!in_fwapp!"=="1" (
        echo !line! | findstr /i "^identifier" >nul && (
            for /f "tokens=2" %%I in ("!line!") do set "current_id=%%I"
        )
        echo !line! | findstr /i "^description" >nul && (
            echo !line! | findstr /i "Network Ethernet IPV4 IPV6 PXE" >nul
            if !errorlevel! neq 0 set "found_id=!current_id!"
        )
    )
)

if not defined found_id (
    call :SetStage "BootNext: no non-network firmware entry found, skipping"
    goto :eof
)

bcdedit /bootsequence !found_id! >nul 2>&1
call :SetStage "BootNext: one-time boot set to !found_id! (drive %mydrive%)"
goto :eof


REM ============================================
REM  Stage logging
REM ============================================
:SetStage
echo [%date% %time%] %~1 >> "%STAGELOG%"
echo %~1
goto :eof
