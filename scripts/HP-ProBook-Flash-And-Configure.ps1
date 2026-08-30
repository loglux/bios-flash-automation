<#
    EXPERIMENTAL - PowerShell port of scripts/HP-ProBook-Flash-And-Configure.bat.
    Not adopted, not tested on real hardware. Written purely to compare the two
    approaches - see the chat/CONTEXT.md discussion for why PowerShell presence
    in the target WinPE image is NOT guaranteed (it's an optional component,
    unlike cmd/wmic/bcdedit which are already confirmed present). The batch
    script remains the primary, relied-upon version.

    Requires PowerShell to be present in the WinPE image (WinPE-PowerShell +
    WinPE-WMI + WinPE-NetFx optional components) - not confirmed either way.
#>

# ============================================
#  SETTINGS
# ============================================
$TargetVersion = "10.04.08"
$MaxAttempts   = 3
$ScriptRoot    = Split-Path -Parent $MyInvocation.MyCommand.Path
$StageLog      = Join-Path $ScriptRoot "stage.log"
$TmpDir        = Join-Path $ScriptRoot "temp"
if (-not (Test-Path $TmpDir)) { New-Item -ItemType Directory -Path $TmpDir | Out-Null }

# --- BIOS flash ---
# Flags per HP's documented syntax for HPBIOSUPDREC64.exe (still worth a
# one-time "HPBIOSUPDREC64.exe -?" check on-site to confirm this exact
# utility version matches):
#   -s  silent               -f  path to the .bin file        -l  log path
#   -a  always flash, ignore version check (silent mode only)
#   -r  do not reboot        -h  create HP_TOOLS partition if missing
#   -b  suspend BitLocker    -p  encrypted BIOS password file (if a BIOS
#                                password is set on the machines)
$FlashTool  = Join-Path $ScriptRoot "HPBIOSUPDREC64.exe"
$FlashImage = Join-Path $ScriptRoot "firmware\10.04.08.bin"
$FlashLog   = Join-Path $ScriptRoot "flash_result.log"

# --- Script B (Security Settings, including MS UEFI CA key) ---
# TODO: fill in the actual name/path of B.bat
$SecurityScript = Join-Path $ScriptRoot "B.bat"

# --- Script C (dialog + Ghost, final stage, we don't touch its internal logic) ---
# TODO: fill in the actual name/path of C.bat
$FinalScript = Join-Path $ScriptRoot "C.bat"


# ============================================
#  Stage logging
# ============================================
function Set-Stage {
    param([Parameter(Mandatory)][string]$Message)
    "[{0}] {1}" -f (Get-Date), $Message | Add-Content -Path $StageLog
    Write-Host $Message
}


# ============================================
#  Read current BIOS version
# ============================================
function Get-BiosVersion {
    $version = (Get-CimInstance -ClassName Win32_BIOS).SMBIOSBIOSVersion
    if (-not $version) {
        Set-Stage "ERROR: could not read BIOS version"
        exit 1
    }
    return $version.Trim()
}


# ============================================
#  Generic check/fix for an enum setting
#  Reads BCU's XML output via [xml] - no manual CDATA string-slicing needed,
#  unlike the .bat version.
# ============================================
function Test-AndFixSimpleSetting {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Desired
    )
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $raw = & biosconfigutility64.exe "/getvalue:$Name" | Out-String
        if (-not $raw.Trim()) {
            Set-Stage "ERROR: could not read '$Name'"
            exit 1
        }
        try { [xml]$xml = $raw }
        catch { Set-Stage "ERROR: could not parse BCU output for '$Name'"; exit 1 }

        $value = $xml.BIOSCONFIG.SETTING.VALUE
        $current = ($value -split ",") | Where-Object { $_.StartsWith("*") } | ForEach-Object { $_.Substring(1) }
        if (-not $current) {
            Set-Stage "ERROR: could not parse value for '$Name'"
            exit 1
        }

        if ($current -ieq $Desired) {
            Set-Stage "OK: $Name = $current"
            return
        }
        if ($attempt -ge 3) {
            Set-Stage "FAIL: $Name still '$current' after 3 attempts"
            exit 1
        }
        Set-Stage "FIX: $Name is '$current' -> setting to '$Desired' (attempt $attempt)"
        & biosconfigutility64.exe "/setvalue:$Name,$Desired" | Out-Null
    }
}


# ============================================
#  Boot Order (ordered list)
#  Array slicing instead of the .bat version's line-by-line file rebuild.
# ============================================
function Test-AndFixBootOrder {
    $bootSetting = "UEFI Boot Order"
    $configPath  = Join-Path $TmpDir "config.txt"

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        & biosconfigutility64.exe "/GetConfig:$configPath" | Out-Null
        $lines = @(Get-Content -Path $configPath)

        $headerIndex = [array]::IndexOf($lines, $bootSetting)
        if ($headerIndex -lt 0) {
            Set-Stage "ERROR: '$bootSetting' not found in config.txt"
            exit 1
        }

        $blockEnd = $headerIndex + 1
        while ($blockEnd -lt $lines.Count -and $lines[$blockEnd].Trim() -ne "") { $blockEnd++ }
        $blockLines = @($lines[($headerIndex + 1)..($blockEnd - 1)])

        if ($blockLines.Count -gt 0 -and $blockLines[0] -imatch "USB") {
            Set-Stage "OK: USB is first in boot order"
            return
        }

        if ($attempt -ge 3) {
            Set-Stage "FAIL: boot order still not USB-first after 3 attempts"
            exit 1
        }

        Set-Stage "FIX: USB not first, rewriting boot order (attempt $attempt)"
        $usbLine = $blockLines | Where-Object { $_ -imatch "USB" } | Select-Object -First 1
        $rest    = $blockLines | Where-Object { $_ -ne $usbLine }
        $newBlock = @($usbLine) + @($rest)

        # Guard against PowerShell's descending-range gotcha (e.g. 5..4 reverses)
        # if the block runs to the very end of the file with no trailing blank line.
        $tail = if ($blockEnd -lt $lines.Count) { @($lines[$blockEnd..($lines.Count - 1)]) } else { @() }

        $newLines = @($lines[0..$headerIndex]) + $newBlock + $tail
        Set-Content -Path $configPath -Value $newLines
        & biosconfigutility64.exe "/SetConfig:$configPath" | Out-Null
    }
}


# ============================================
#  MS UEFI CA key - GATE for script B (Security Settings)
#  This option is not important by itself - it is used as an
#  indicator of whether script B has run. If not, we launch B
#  (we don't set the option directly ourselves, so we don't
#  lose its other settings) and re-check.
# ============================================
function Test-MSUEFICAKey {
    $name    = "Enable MS UEFI CA key"
    $desired = "Yes"

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $raw = & biosconfigutility64.exe "/getvalue:$name" | Out-String
        if (-not $raw.Trim()) {
            Set-Stage "ERROR: could not read '$name'"
            exit 1
        }
        [xml]$xml = $raw
        $value = $xml.BIOSCONFIG.SETTING.VALUE
        $current = ($value -split ",") | Where-Object { $_.StartsWith("*") } | ForEach-Object { $_.Substring(1) }

        if ($current -ieq $desired) {
            Set-Stage "OK: $name = $current (script B has run)"
            return
        }
        if ($attempt -ge 2) {
            Set-Stage "FAIL: $name still '$current' after running script B $attempt time(s)"
            exit 1
        }

        Set-Stage "NEEDED: $name = '$current' - script B has not run (or failed), launching it"
        if (-not (Test-Path $SecurityScript)) {
            Set-Stage "ERROR: security script not found at $SecurityScript"
            exit 1
        }
        & $SecurityScript
        Set-Stage "Script B finished (exit $LASTEXITCODE), re-checking $name"
    }
}


# ============================================
#  START - bind the state file to the machine's serial number
# ============================================
$machineId = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
if (-not $machineId) { $machineId = "UNKNOWN" }
$machineId = $machineId.Trim()

$stateFile = Join-Path $ScriptRoot "flash_attempt_$machineId.state"
$attempt = 0
if (Test-Path $stateFile) { $attempt = [int](Get-Content $stateFile -Raw).Trim() }

Set-Stage "=== SCRIPT START (machine: $machineId, attempt $attempt) ==="


# ============================================
#  STEP 1: check boot settings BEFORE flashing
# ============================================
Set-Stage "Checking boot settings before flash"
Test-AndFixSimpleSetting -Name "Fast Boot" -Desired "Disable"
Test-AndFixBootOrder


# ============================================
#  STEP 2: check BIOS version
# ============================================
$biosVersion = Get-BiosVersion
Set-Stage "Current BIOS version: $biosVersion (target: $TargetVersion)"

if ($biosVersion -ieq $TargetVersion) {
    Set-Stage "OK: BIOS already at target version"
    if (Test-Path $stateFile) { Remove-Item $stateFile }
}
else {
    if ($attempt -ge $MaxAttempts) {
        Set-Stage "FAIL: still on '$biosVersion' after $MaxAttempts attempts, expected $TargetVersion"
        exit 1
    }

    # ============================================
    #  STEP 3: flash
    # ============================================
    $attempt++
    Set-Content -Path $stateFile -Value $attempt
    Set-Stage "Flashing BIOS (attempt $attempt of $MaxAttempts)"

    if (-not (Test-Path $FlashTool))  { Set-Stage "ERROR: flash tool not found at $FlashTool"; exit 1 }
    if (-not (Test-Path $FlashImage)) { Set-Stage "ERROR: firmware image not found at $FlashImage"; exit 1 }

    # TODO: verify and finalize the flag set below
    # -r (do not reboot) is required here: without it, the tool likely reboots
    # the machine itself once it's done, before control returns to this script
    # - which would skip the logging/reboot-control logic below entirely.
    & $FlashTool -s -r -f"$FlashImage" -l"$FlashLog"
    Set-Stage "Flash command finished (exit $LASTEXITCODE), see $FlashLog for details"

    # ============================================
    #  STEP 4: reboot
    #  NOTE: no boot-settings re-check here - the actual firmware write only
    #  happens during POST on this reboot, not while HPBIOSUPDREC64.exe was
    #  running, so nothing has changed since Step 1's check. The authoritative
    #  check is below, once the script has been re-launched and the version
    #  is confirmed.
    # ============================================
    Set-Stage "Rebooting in 5 sec to apply flash..."
    shutdown /r /t 5
    exit 0
}


# ============================================
#  VERSION CONFIRMED - continue the pipeline
# ============================================
Set-Stage "=== BIOS FLASH CONFIRMED at $TargetVersion ==="

Set-Stage "Final check of boot settings"
Test-AndFixSimpleSetting -Name "Fast Boot" -Desired "Disable"
Test-AndFixBootOrder

Set-Stage "Checking MS UEFI CA key"
Test-MSUEFICAKey

Set-Stage "OK: stage A (BIOS flash) and stage B (security settings) confirmed"

if (-not (Test-Path $FinalScript)) {
    Set-Stage "ERROR: final script not found at $FinalScript"
    exit 1
}

Set-Stage "Launching final script (C)"
& $FinalScript
exit $LASTEXITCODE
