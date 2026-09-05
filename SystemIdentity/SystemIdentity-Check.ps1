# Diagnostic only, for now - reports the brand/model-agnostic facts
# every pipeline needs before it can pick a procedure: manufacturer,
# model, serial/service tag, and current BIOS version.
#
# Win32_ComputerSystem gives Manufacturer + Model together;
# Win32_BIOS gives SerialNumber + SMBIOSBIOSVersion together - two
# CIM classes, so two calls, but both already needed separately
# elsewhere (HP's own BiosCheck scripts read SMBIOSBIOSVersion this
# same way) and now read once, here, instead of per-caller.

$cs   = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
$bios = Get-CimInstance -ClassName Win32_BIOS            -ErrorAction SilentlyContinue

Write-Output "Manufacturer|$($cs.Manufacturer)"
Write-Output "Model|$($cs.Model)"
Write-Output "SerialNumber|$($bios.SerialNumber)"
Write-Output "BiosVersion|$($bios.SMBIOSBIOSVersion)"
