@echo off
setlocal enabledelayedexpansion

REM DRAFT / diagnostic only - not wired into any pipeline yet. Prints
REM AC/battery state so we can see real output on real hardware first.
REM See PowerState/README.md for the vendor requirements this is meant
REM to eventually check against (HP: AC + ~25-50% charge; Dell: AC + 10%).

set "PS_CHECKPOWER=%~dp0PowerState-Check.ps1"

for /f "tokens=1,* delims=|" %%A in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_CHECKPOWER%"') do (
    set "%%A=%%B"
)

if defined NoBattery (
    echo No battery detected - !NoBattery!
    echo Treating as an AC-only system - safe to proceed.
    exit /b 0
)

echo AC Online: !ACOnline!
echo Charging: !Charging!
echo Discharging: !Discharging!
echo Charge Percent: !ChargePercent!
echo Battery Status Code: !BatteryStatusCode!
