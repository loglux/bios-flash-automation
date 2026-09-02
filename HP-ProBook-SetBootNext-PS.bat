@echo off
setlocal enabledelayedexpansion

REM PowerShell-based variant of HP-ProBook-SetBootNext.bat, for the
REM case where findstr turns out to be unavailable. Same purpose: find
REM the boot USB's firmware entry by excluding entries that look like
REM a network controller, then set a one-time BootNext override on it
REM via bcdedit - but the parsing is done in a single PowerShell call
REM (regex) instead of findstr + for /f loops.
REM
REM UNTESTED - written to have ready if findstr is ever confirmed
REM missing, not verified against real "bcdedit /enum firmware" output
REM the way the findstr version was.
REM
REM How to use: same as HP-ProBook-SetBootNext.bat - run this, then do
REM an ordinary reboot (e.g. "shutdown /r") - no BIOS flash needed. See
REM experimental/BCDEdit-BootSequence-Notes.md for background.

set "found_id="
for /f "delims=" %%I in ('powershell -NoProfile -Command "$fw = (bcdedit /enum firmware) -join [char]10; $blocks = $fw -split '(?=Firmware Application)'; foreach ($b in $blocks) { if ($b -match 'Firmware Application' -and $b -notmatch '(?i)Network|Ethernet|IPV4|IPV6|PXE') { if ($b -match 'identifier\s+(\{[0-9a-fA-F-]+\})') { $matches[1]; break } } }"') do set "found_id=%%I"

if not defined found_id (
    echo No non-network firmware entry found - nothing to set.
    exit /b 1
)

echo Found candidate boot-USB firmware entry: %found_id%
bcdedit /bootsequence %found_id%
if !errorlevel! neq 0 (
    echo bcdedit /bootsequence FAILED, exit code !errorlevel!
    exit /b 1
)

echo OK: one-time BootNext set to %found_id%.
echo Now reboot manually to test it, for example:
echo     shutdown /r /t 5
echo Then check where the machine lands - back on this USB drive means
echo bootsequence worked.
