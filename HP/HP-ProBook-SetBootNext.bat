@echo off
setlocal enabledelayedexpansion

REM Standalone test tool - not part of the pipeline. Not about the BIOS
REM flash at all - just checks whether "bcdedit /bootsequence" itself
REM actually works on this hardware, with a plain reboot, no flashing
REM involved.
REM Finds the boot USB's firmware entry (by excluding entries that look
REM like a network controller) and sets a one-time BootNext override on
REM it via bcdedit, so it can be run and checked on its own.
REM
REM How to use: run this, then reboot - "shutdown /r" if testing from
REM full Windows, "wpeutil reboot" if testing from WinPE (confirmed
REM "shutdown" doesn't work there). If bootsequence works, the machine
REM should land back on this same USB drive one more time.
REM See experimental/BCDEdit-BootSequence-Notes.md for background.
REM
REM bcdedit /bootsequence reference (Microsoft Learn):
REM https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--bootsequence

set "TMPDIR=%~dp0temp"
if not exist "%TMPDIR%" mkdir "%TMPDIR%"
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
    echo No non-network firmware entry found - nothing to set.
    echo Raw dump saved at %fwdump% for inspection.
    exit /b 1
)

echo Found candidate boot-USB firmware entry: %found_id%
bcdedit /bootsequence %found_id%
if !errorlevel! neq 0 (
    echo bcdedit /bootsequence FAILED, exit code !errorlevel!
    exit /b 1
)

echo OK: one-time BootNext set to %found_id%.
echo Now reboot manually to test it:
echo     shutdown /r /t 5     (full Windows)
echo     wpeutil reboot       (WinPE - "shutdown" doesn't work there)
echo Then check where the machine lands - back on this USB drive means
echo bootsequence worked.
