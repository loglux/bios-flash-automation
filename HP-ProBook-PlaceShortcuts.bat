@echo off
setlocal enabledelayedexpansion

REM Copies every .lnk file from the Shortcuts folder (next to this
REM script) onto the target system's Public Desktop, so they're
REM visible to whichever account is used to connect remotely and
REM finish configuring the machine. Doesn't need to know the exact
REM list of shortcuts - just copies whatever is currently in the
REM Shortcuts folder. Manage the shortcut list by adding/removing
REM files there, not by editing this script.
REM
REM TARGET_DRIVE: the offline target system's internal disk drive
REM letter, as seen from WinPE - NOT the boot USB drive (which is D:
REM in this project's real environment; X: is WinPE's own RAM disk).
REM The internal disk is typically C: from within WinPE, but verify
REM on-site before relying on this.

set "SHORTCUTS_SRC=%~dp0Shortcuts"
set "TARGET_DRIVE=C:"
set "PUBLIC_DESKTOP=%TARGET_DRIVE%\Users\Public\Desktop"

if not exist "%SHORTCUTS_SRC%" (
    echo ERROR: shortcuts source folder not found at %SHORTCUTS_SRC%
    exit /b 1
)

if not exist "%PUBLIC_DESKTOP%" (
    echo ERROR: target Public Desktop not found at %PUBLIC_DESKTOP%
    exit /b 1
)

set "found=0"
for %%F in ("%SHORTCUTS_SRC%\*.lnk") do set "found=1"

if "!found!"=="0" (
    echo No .lnk files found in %SHORTCUTS_SRC% - nothing to copy.
    exit /b 0
)

copy "%SHORTCUTS_SRC%\*.lnk" "%PUBLIC_DESKTOP%\" /y

if !errorlevel! neq 0 (
    echo ERROR: copy failed, exit code !errorlevel!
    exit /b 1
)

echo OK: shortcuts copied to %PUBLIC_DESKTOP%
exit /b 0
