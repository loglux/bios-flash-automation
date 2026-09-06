# Diagnostic only, for now - reports the brand/model-agnostic facts
# every pipeline needs before it can pick a procedure: manufacturer,
# model, baseboard product code, serial/service tag, and current BIOS
# version.
#
# Win32_ComputerSystem gives Manufacturer + Model together;
# Win32_BIOS gives SerialNumber + SMBIOSBIOSVersion together - two
# CIM classes, so two calls, but both already needed separately
# elsewhere (HP's own BiosCheck scripts read SMBIOSBIOSVersion this
# same way) and now read once, here, instead of per-caller.
#
# Win32_BaseBoard.Product is a third class/call, added separately - a
# short product code, previously confirmed on real Dell hardware to
# match the code a real driver-pack dispatch system keys on for that
# exact model (unlike Win32_ComputerSystem.SystemSKUNumber, tried
# first and confirmed wrong - see SystemIdentity/README.md).

$cs        = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
$bios      = Get-CimInstance -ClassName Win32_BIOS            -ErrorAction SilentlyContinue
$baseboard = Get-CimInstance -ClassName Win32_BaseBoard       -ErrorAction SilentlyContinue

Write-Output "Manufacturer|$($cs.Manufacturer)"
Write-Output "Model|$($cs.Model)"
Write-Output "ProductID|$($baseboard.Product)"
Write-Output "SerialNumber|$($bios.SerialNumber)"
Write-Output "BiosVersion|$($bios.SMBIOSBIOSVersion)"
