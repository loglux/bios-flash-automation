@echo off
setlocal enabledelayedexpansion

REM DRAFT - not yet verified on real Dell hardware. See Dell/README.md
REM for which parts are confirmed (official docs / real-world usage)
REM and which are constructed by analogy.

set "CCTK=%~dp0cctk.exe"
set "BACKUP_INI=%~dp0dell-bios-backup.ini"
set "PS_FINDUSB=%~dp0Dell-FindUsbBootDevice.ps1"


REM ============================================
REM  STEP 0: vendor + model detection
REM ============================================
set "manufacturer="
for /f "skip=1 tokens=* delims=" %%M in ('wmic computersystem get manufacturer 2^>nul') do (
    if not defined manufacturer if not "%%M"=="" set "manufacturer=%%M"
)
for /f "tokens=* delims= " %%A in ("!manufacturer!") do set "manufacturer=%%A"

if not defined manufacturer (
    echo ERROR: could not read system manufacturer
    exit /b 1
)

echo Manufacturer: !manufacturer!

REM findstr isn't present on every WinPE image (confirmed missing on
REM one real build) - use PowerShell -match instead, same as the HP
REM scripts already do for similar substring checks.
powershell -NoProfile -Command "if ('!manufacturer!' -match 'Dell') { exit 0 } else { exit 1 }"
if !errorlevel! neq 0 (
    echo ERROR: this is not a Dell system ^(Manufacturer='!manufacturer!'^) - aborting
    exit /b 1
)

set "model="
for /f "skip=1 tokens=* delims=" %%N in ('wmic csproduct get name 2^>nul') do (
    if not defined model if not "%%N"=="" set "model=%%N"
)
for /f "tokens=* delims= " %%A in ("!model!") do set "model=%%A"

set "svctag="
for /f "skip=1 tokens=* delims=" %%S in ('wmic bios get serialnumber 2^>nul') do (
    if not defined svctag if not "%%S"=="" set "svctag=%%S"
)
for /f "tokens=* delims= " %%A in ("!svctag!") do set "svctag=%%A"

if not defined model (
    echo ERROR: could not read system model
    exit /b 1
)
if not defined svctag (
    echo ERROR: could not read Service Tag
    exit /b 1
)

echo Model: !model!
echo Service Tag: !svctag!

REM Model/Service Tag will drive the per-model config lookup table once
REM more than one model needs different settings/firmware. For now this
REM just confirms detection works and logs what was found.


REM ============================================
REM  STEP 1: snapshot every current BIOS setting, so it can be restored
REM  later with: "%CCTK%" -i "%BACKUP_INI%"
REM ============================================
if exist "%BACKUP_INI%" del "%BACKUP_INI%"
"%CCTK%" -O "%BACKUP_INI%"


REM ============================================
REM  STEP 2: apply boot settings
REM ============================================
REM Thorough, not Minimal - Minimal is the "fastest POST" state, i.e.
REM the analog of Fast Boot ENABLED. HP disables Fast Boot here so the
REM USB drive is reliably detected (see HP/docs/HP-BCU-FastBoot-BootOrder.md) -
REM Thorough (full hardware/config testing) is the matching Dell state.
"%CCTK%" --Fastboot=Thorough
"%CCTK%" --ExtPostTime=5s

REM The USB flash drive's Shortform varies by machine/BIOS (confirmed
REM usbhdd, not usbdev, on a real Latitude 5530) - read the actual boot
REM order table and find it rather than hardcoding one guess.
set "usb_short="
for /f "delims=" %%U in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_FINDUSB%" -CctkPath "%CCTK%"') do set "usb_short=%%U"

if not defined usb_short (
    echo ERROR: could not find a USB boot device in BootOrder
    exit /b 1
)

echo Found USB boot device: !usb_short!
"%CCTK%" BootOrder --BootListType=uefi --Sequence=!usb_short!,hdd.1
