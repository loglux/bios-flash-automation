@echo off
setlocal enabledelayedexpansion

REM DRAFT / diagnostic only - not wired into any pipeline yet. Prints
REM manufacturer/model/serial/BIOS version so we can see real output
REM on real hardware first. See SystemIdentity/README.md.

set "PS_CHECKIDENTITY=%~dp0SystemIdentity-Check.ps1"

for /f "tokens=1,* delims=|" %%A in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_CHECKIDENTITY%"') do (
    set "%%A=%%B"
)

echo Manufacturer: !Manufacturer!
echo Model: !Model!
echo Product ID: !ProductID!
echo Serial Number: !SerialNumber!
echo BIOS Version: !BiosVersion!
