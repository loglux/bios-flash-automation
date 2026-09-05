# Diagnostic only, for now - reports AC/battery power state so we can
# see real output on real hardware before wiring any pass/fail logic
# into the flash pipeline. Handles desktops (no battery) explicitly.
#
# root\wmi BatteryStatus gives PowerOnline/Charging/Discharging
# directly (booleans, no interpretation needed); Win32_Battery
# (root\cimv2) gives the charge percentage and a status code, but
# doesn't unambiguously say "is AC connected right now".

$batteryStatus = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue
$battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue

if (-not $battery -and -not $batteryStatus) {
    Write-Output "NoBattery|no battery detected (desktop or battery-less system)"
    exit 0
}

Write-Output "ACOnline|$($batteryStatus.PowerOnline)"
Write-Output "Charging|$($batteryStatus.Charging)"
Write-Output "Discharging|$($batteryStatus.Discharging)"
Write-Output "ChargePercent|$($battery.EstimatedChargeRemaining)"
Write-Output "BatteryStatusCode|$($battery.BatteryStatus)"
