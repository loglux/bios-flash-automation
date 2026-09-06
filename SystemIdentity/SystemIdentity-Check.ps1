# Diagnostic only, for now - reports the brand/model-agnostic facts
# every pipeline needs before it can pick a procedure: manufacturer,
# model, SKU/product ID, serial/service tag, and current BIOS version.
#
# Win32_ComputerSystem gives Manufacturer + Model + SystemSKUNumber
# together; Win32_BIOS gives SerialNumber + SMBIOSBIOSVersion together
# - two CIM classes, so two calls, but both already needed separately
# elsewhere (HP's own BiosCheck scripts read SMBIOSBIOSVersion this
# same way) and now read once, here, instead of per-caller.
#
# SystemSKUNumber is a candidate for the short Product ID code the
# real fleet's own dispatch table (STARTXUEFI85.bat) keys on (e.g.
# HP's own platform string shows "8DF7" for this exact model) - not
# yet confirmed on real hardware that this field is the same code, so
# treat it as unverified until checked.

$cs   = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
$bios = Get-CimInstance -ClassName Win32_BIOS            -ErrorAction SilentlyContinue

Write-Output "Manufacturer|$($cs.Manufacturer)"
Write-Output "Model|$($cs.Model)"
Write-Output "ProductID|$($cs.SystemSKUNumber)"
Write-Output "SerialNumber|$($bios.SerialNumber)"
Write-Output "BiosVersion|$($bios.SMBIOSBIOSVersion)"
