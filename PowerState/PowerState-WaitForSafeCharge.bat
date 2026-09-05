@echo off
setlocal enabledelayedexpansion

REM DRAFT - not yet run on real hardware. Gates the actual BIOS flash
REM step on AC + minimum battery charge, since both HP's and Dell's own
REM flash tools already refuse under the same conditions (see
REM PowerState/README.md) - this catches it early, with a clear
REM message, instead of the flash step failing partway through.
REM
REM Usage: call PowerState-WaitForSafeCharge.bat <ThresholdPercent> [MaxAttempts] [DelaySeconds]
REM   ThresholdPercent - minimum battery %% required while on AC
REM                      (HP: ~25-50 depending on model, Dell: 10 - not
REM                      hardcoded here, the caller decides)
REM   MaxAttempts      - how many times to recheck before giving up
REM                      (default 12)
REM   DelaySeconds     - delay between rechecks (default 300 = 5 min)
REM
REM No AC at all -> stops immediately, waiting would be pointless.
REM No battery at all (desktop) -> always safe, skips the check.
REM AC present but charge too low -> waits and rechecks, up to
REM MaxAttempts, since a battery that never charges (a real, reported
REM failure mode - see README) would otherwise wait forever.

set "THRESHOLD=%~1"
if not defined THRESHOLD set "THRESHOLD=50"

set "MAXATTEMPTS=%~2"
if not defined MAXATTEMPTS set "MAXATTEMPTS=12"

set "DELAYSECONDS=%~3"
if not defined DELAYSECONDS set "DELAYSECONDS=300"

set "PS_CHECKPOWER=%~dp0PowerState-Check.ps1"
set "attempt=0"

:retry_power
set /a attempt+=1

set "NoBattery="
set "ACOnline="
set "Charging="
set "Discharging="
set "ChargePercent="
set "BatteryStatusCode="
for /f "tokens=1,* delims=|" %%A in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_CHECKPOWER%"') do (
    set "%%A=%%B"
)

if defined NoBattery (
    echo OK: no battery present - AC-only system, safe to proceed
    exit /b 0
)

if not defined ACOnline (
    echo ERROR: could not read power state
    exit /b 1
)

if /i not "!ACOnline!"=="True" (
    echo FAIL: AC adapter not connected - plug it in before flashing
    exit /b 1
)

if not defined ChargePercent (
    echo ERROR: could not read battery charge percentage
    exit /b 1
)

if !ChargePercent! geq !THRESHOLD! (
    echo OK: on AC, charge !ChargePercent!%% ^(threshold !THRESHOLD!%%^)
    exit /b 0
)

if !attempt! gtr !MAXATTEMPTS! (
    echo FAIL: charge still !ChargePercent!%% ^(need !THRESHOLD!%%^) after !MAXATTEMPTS! attempts - battery may not be charging, check hardware
    exit /b 1
)

echo WAIT: on AC, charge !ChargePercent!%%, need !THRESHOLD!%% - rechecking in !DELAYSECONDS!s ^(attempt !attempt!^)
timeout /t !DELAYSECONDS! /nobreak >nul
goto :retry_power
