# Reads the current UEFI BootOrder table from cctk.exe and prints the
# Shortform of whatever device is actually the USB boot device on this
# machine - confirmed on real hardware to vary (usbhdd, not usbdev, on
# a Latitude 5530 with a Kingston USB stick). Column positions are
# read from the header line rather than assumed, since DeviceType text
# ("USB Hard Disk") would otherwise false-match a keyword search.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CctkPath
)

$lines = & $CctkPath BootOrder --BootListType=uefi

$headerIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'Shortform') { $headerIdx = $i; break }
}
if ($headerIdx -lt 0) { exit 1 }

$header = $lines[$headerIdx]
$shortformCol = $header.IndexOf('Shortform')
$descCol = $header.IndexOf('DeviceDescription')
if ($shortformCol -lt 0) { exit 1 }

for ($i = $headerIdx + 1; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -notmatch '\S') { continue }
    if ($line -match '^-+$') { continue }
    if ($line.Length -le $shortformCol) { continue }
    $end = if ($descCol -gt $shortformCol) { [Math]::Min($descCol, $line.Length) } else { $line.Length }
    $shortform = $line.Substring($shortformCol, $end - $shortformCol).Trim()
    # Only usbhdd/usbdev - the actual flash drive as mass storage.
    # Not usbfloppy/usbcdrom/usbzip/usbdevzip - legacy removable-media
    # emulation modes, not the drive we actually want to boot from.
    if ($shortform -match '^(?i)(usbhdd|usbdev)$') {
        Write-Output $shortform
        exit 0
    }
}
exit 1
