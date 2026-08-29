# HP ProBook: Combined BIOS Flash + Settings Check Script

**Utilities:** HP BiosConfigUtility64 (BCU), HPBIOSUPDREC64.exe (or HpFirmwareUpdRec64.exe)
**Model:** HP ProBook 4 G1 (and compatible)
**Purpose:** glue together three previously separate scripts (A/B/C) into one pipeline, without manually entering F9/BIOS Setup:
- **A** — flashes the BIOS to the target version (this is what this script implements directly),
- **B** — configures several Security Settings options, including "Enable MS UEFI CA key" (an existing script, called by this one — its internals are out of scope here),
- **C** — the final imaging dialog + Ghost (an existing script, launched at the end — its internals are also out of scope).

On top of that, this script owns Fast Boot and Boot Order (USB first) — these are **not** part of script B; they were added here so the pipeline doesn't need a person to manually catch every reboot and re-enter the BIOS boot menu.

The script is run from a bootable USB drive in a WinPE environment.

---

## Overall idea

The script **cannot run start-to-finish in a single pass** when a flash is required — because after flashing, a reboot is needed, and a batch file can't "resume where it left off" after that. So the script is designed to **safely restart itself** any number of times, checking the current state (BIOS version, attempt count) on every run and continuing from the right stage rather than from scratch.

Conceptually the script runs in three phases:
- the main flash phase (**A**), looping through flash + reboot until the target version is confirmed,
- a final pass once the version is confirmed, checking Fast Boot / Boot Order and gating on script **B** (launching it if the "Enable MS UEFI CA key" indicator isn't set yet),
- handing off to script **C** once A and B are both confirmed.

---

## When does the flash actually happen?

`HPBIOSUPDREC64.exe` (silent mode) does **not** write the new firmware to the BIOS chip while it's running in Windows/WinPE — it stages the update and reboots the machine, and the actual flash write happens **during POST on the next boot**. On systems with HP Sure Start, the update may also trigger **more than one reboot** — the final one is where Sure Start stores a backup copy of the BIOS and security settings.

This is why the script doesn't bother re-checking Fast Boot/Boot Order right after the flash command, before `shutdown` — at that point the BIOS is still the **old** one (nothing has changed since Step 1's check yet), so it would just be a no-op. The only check that matters happens in `:after_flash_confirmed`, after the reboot(s), once the version has actually changed.

The attempt-counter loop (up to 3 attempts, tracked per machine serial) already tolerates an extra Sure Start reboot fine — it just re-checks the version on each subsequent run of the script.

---

## ⚠️ Needs finishing on-site

The flash utility switches for `HPBIOSUPDREC64.exe` are documented by HP as:
```
HPBIOSUPDREC [-s] [-p PasswordFile] [-fBinaryFile] [-a] [-h] [-b] [-r] [-?]
```
- `-s` silent, `-f` path to the `.bin` file, `-l` log path — used in the script below
- `-a` always flash, ignore version check (silent mode only)
- `-r` do not reboot
- `-h` create the HP_TOOLS partition if missing
- `-b` suspend BitLocker
- `-p` encrypted BIOS password file (if a BIOS password is set on the machines)

These are confirmed against HP's own documentation (see Sources below), but it's still worth running:
```
HPBIOSUPDREC64.exe -?
```
on the actual USB drive once, to confirm this exact utility version matches — and to decide whether `-p`/`-h`/`-b` are needed for these specific machines.

**Sources:**
- [Updating BIOS Command Lines — HP Support Community](https://h30434.www3.hp.com/t5/Commercial-PC-Software/Updating-BIOS-Command-Lines/td-p/6518162)
- [BIOS Flash Update (HP PDF)](https://h30434.www3.hp.com/psg/attachments/psg/Business-PC-Workstation-POS/34410/1/BIOS%20Flash%20Update.pdf)
- [How to Update HP BIOS on Commercial Platforms — HP Developer Portal](https://developers.hp.com/hp-client-management/blog/how-update-hp-bios-commercial-platforms)
- [650 G1: Silent BIOS Update With No Automatic Reboot? — HP Support Community](https://h30434.www3.hp.com/t5/Commercial-PC-Software/650-G1-Silent-BIOS-Update-With-No-Automatic-Reboot/td-p/5071561)
- [bios1.txt — real config.txt dump for an HP ProBook 450 G1 (HP Support Community attachment)](https://h30434.www3.hp.com/psg/attachments/psg/Tablet/1373380/1/bios1.txt) — shows `Legacy Boot Order` and `UEFI Boot Order` as two separate sections (no plain `Boot Order`), confirming the setting name used in the script below

---

## Full code

```bat
@echo off
setlocal enabledelayedexpansion

REM ============================================
REM  SETTINGS
REM ============================================
set "TARGET_VERSION=10.04.08"
set "MAXATTEMPTS=3"
set "STAGELOG=%~dp0stage.log"
set "TMPDIR=%~dp0temp"
if not exist "%TMPDIR%" mkdir "%TMPDIR%"

REM --- BIOS flash ---
REM Flags per HP's documented syntax for HPBIOSUPDREC64.exe (still worth a
REM one-time "HPBIOSUPDREC64.exe -?" check on-site to confirm this exact
REM utility version matches):
REM   -s  silent               -f  path to the .bin file        -l  log path
REM   -a  always flash, ignore version check (silent mode only)
REM   -r  do not reboot        -h  create HP_TOOLS partition if missing
REM   -b  suspend BitLocker    -p  encrypted BIOS password file (if a BIOS
REM                                password is set on the machines)
set "FLASH_TOOL=%~dp0HPBIOSUPDREC64.exe"
set "FLASH_IMAGE=%~dp0firmware\10.04.08.bin"
set "FLASH_LOG=%~dp0flash_result.log"

REM --- Script B (Security Settings, including MS UEFI CA key) ---
REM TODO: fill in the actual name/path of B.bat
set "SECURITY_SCRIPT=%~dp0B.bat"

REM --- Script C (dialog + Ghost, final stage, we don't touch its internal logic) ---
REM TODO: fill in the actual name/path of C.bat
set "FINAL_SCRIPT=%~dp0C.bat"


REM ============================================
REM  START - bind the state file to the machine's serial number
REM ============================================
set "machineid="
for /f "skip=1 tokens=* delims=" %%S in ('wmic bios get serialnumber 2^>nul') do (
    if not defined machineid if not "%%S"=="" set "machineid=%%S"
)
for /f "tokens=* delims= " %%A in ("!machineid!") do set "machineid=%%A"
if not defined machineid set "machineid=UNKNOWN"

set "STATEFILE=%~dp0flash_attempt_!machineid!.state"

set "attempt=0"
if exist "%STATEFILE%" set /p attempt=<"%STATEFILE%"

call :SetStage "=== SCRIPT START (machine: !machineid!, attempt !attempt!) ==="


REM ============================================
REM  STEP 1: check boot settings BEFORE flashing
REM ============================================
call :SetStage "Checking boot settings before flash"
call :CheckAndFixSimpleSetting "Fast Boot" "Disable"
call :CheckAndFixBootOrder


REM ============================================
REM  STEP 2: check BIOS version
REM ============================================
call :GetBiosVersion
call :SetStage "Current BIOS version: !biosver! (target: %TARGET_VERSION%)"

if /i "!biosver!"=="%TARGET_VERSION%" (
    call :SetStage "OK: BIOS already at target version"
    if exist "%STATEFILE%" del "%STATEFILE%"
    goto :after_flash_confirmed
)

if !attempt! geq %MAXATTEMPTS% (
    call :SetStage "FAIL: still on '!biosver!' after %MAXATTEMPTS% attempts, expected %TARGET_VERSION%"
    exit /b 1
)


REM ============================================
REM  STEP 3: flash
REM ============================================
set /a attempt+=1
echo !attempt! > "%STATEFILE%"
call :SetStage "Flashing BIOS (attempt !attempt! of %MAXATTEMPTS%)"

if not exist "%FLASH_TOOL%" (
    call :SetStage "ERROR: flash tool not found at %FLASH_TOOL%"
    exit /b 1
)
if not exist "%FLASH_IMAGE%" (
    call :SetStage "ERROR: firmware image not found at %FLASH_IMAGE%"
    exit /b 1
)

REM --- TODO: verify and finalize the flag set below ---
"%FLASH_TOOL%" -s -f"%FLASH_IMAGE%" -l"%FLASH_LOG%"
call :SetStage "Flash command finished (exit !errorlevel!), see %FLASH_LOG% for details"


REM ============================================
REM  STEP 4: reboot
REM  NOTE: no boot-settings re-check here - the actual firmware write only
REM  happens during POST on this reboot, not while HPBIOSUPDREC64.exe was
REM  running, so nothing has changed since Step 1's check. The authoritative
REM  check is in :after_flash_confirmed, once the reboot has happened.
REM ============================================
call :SetStage "Rebooting in 5 sec to apply flash..."
shutdown /r /t 5
exit /b 0


REM ============================================
REM  VERSION CONFIRMED - continue the pipeline
REM ============================================
:after_flash_confirmed
call :SetStage "=== BIOS FLASH CONFIRMED at %TARGET_VERSION% ==="

call :SetStage "Final check of boot settings"
call :CheckAndFixSimpleSetting "Fast Boot" "Disable"
call :CheckAndFixBootOrder

call :SetStage "Checking MS UEFI CA key"
call :CheckMSUEFICAKey

call :SetStage "OK: stage A (BIOS flash) and stage B (security settings) confirmed"

if not exist "%FINAL_SCRIPT%" (
    call :SetStage "ERROR: final script not found at %FINAL_SCRIPT%"
    exit /b 1
)

call :SetStage "Launching final script (C)"
call "%FINAL_SCRIPT%"
exit /b !errorlevel!


REM ============================================
REM  Read current BIOS version
REM ============================================
:GetBiosVersion
set "biosver="
for /f "skip=1 tokens=* delims=" %%V in ('wmic bios get smbiosbiosversion 2^>nul') do (
    if not defined biosver if not "%%V"=="" set "biosver=%%V"
)
for /f "tokens=* delims= " %%A in ("!biosver!") do set "biosver=%%A"
if not defined biosver (
    call :SetStage "ERROR: could not read BIOS version"
    exit /b 1
)
goto :eof


REM ============================================
REM  Generic check/fix for an enum setting
REM ============================================
:CheckAndFixSimpleSetting
set "sName=%~1"
set "sDesired=%~2"
set "attempt2=0"

:retry_simple
set /a attempt2+=1
set "line="
for /f "delims=" %%i in ('biosconfigutility64 /getvalue:"%sName%" ^| findstr "VALUE"') do set "line=%%i"

if not defined line (
    call :SetStage "ERROR: could not read '%sName%'"
    exit /b 1
)

set "value=!line:*CDATA[=!"
set "value=!value:]]></VALUE>=!"
set "current="
for %%A in (%value:,= %) do (
    set "tok=%%A"
    if "!tok:~0,1!"=="*" set "current=!tok:~1!"
)

if not defined current (
    call :SetStage "ERROR: could not parse value for '%sName%'"
    exit /b 1
)

if /i "!current!"=="%sDesired%" (
    call :SetStage "OK: %sName% = !current!"
    goto :eof
)

if !attempt2! gtr 3 (
    call :SetStage "FAIL: %sName% still '!current!' after 3 attempts"
    exit /b 1
)

call :SetStage "FIX: %sName% is '!current!' -> setting to '%sDesired%' (attempt !attempt2!)"
biosconfigutility64 /setvalue:"%sName%","%sDesired%" >nul 2>&1
goto :retry_simple


REM ============================================
REM  Boot Order (ordered list) - pure CMD
REM ============================================
:CheckAndFixBootOrder
set "BOOTSETTING=UEFI Boot Order"
set "attempt3=0"

:retry_bootorder
set /a attempt3+=1
biosconfigutility64 /GetConfig:"%TMPDIR%\config.txt" >nul 2>&1

set "found_header="
set "first_after="
for /f "usebackq delims=" %%L in ("%TMPDIR%\config.txt") do (
    if defined found_header if not defined first_after set "first_after=%%L"
    if "%%L"=="%BOOTSETTING%" set "found_header=1"
)

if not defined found_header (
    call :SetStage "ERROR: '%BOOTSETTING%' not found in config.txt"
    exit /b 1
)

echo !first_after! | findstr /i "USB" >nul
if !errorlevel! equ 0 (
    call :SetStage "OK: USB is first in boot order"
    goto :eof
)

if !attempt3! gtr 3 (
    call :SetStage "FAIL: boot order still not USB-first after 3 attempts"
    exit /b 1
)

call :SetStage "FIX: USB not first, rewriting boot order (attempt !attempt3!)"

set "newfile=%TMPDIR%\config_new.txt"
if exist "%newfile%" del "%newfile%"

set "in_block=0"
set "usb_line="
for /f "usebackq delims=" %%L in ("%TMPDIR%\config.txt") do (
    set "line=%%L"
    if "!in_block!"=="1" if not "!line!"=="" (
        echo !line! | findstr /i "USB" >nul && set "usb_line=!line!"
    )
    if "!line!"=="%BOOTSETTING%" set "in_block=1"
    if "!in_block!"=="1" if "!line!"=="" set "in_block=0"
)

set "in_block=0"
set "wrote_usb=0"
(
for /f "usebackq delims=" %%L in ("%TMPDIR%\config.txt") do (
    set "line=%%L"
    if "!in_block!"=="1" (
        if "!line!"=="" (
            set "in_block=0"
            echo(
        ) else (
            if "!wrote_usb!"=="0" (
                echo !usb_line!
                set "wrote_usb=1"
            )
            if not "!line!"=="!usb_line!" echo !line!
        )
    ) else (
        echo !line!
    )
    if "!line!"=="%BOOTSETTING%" set "in_block=1"
)
) > "%newfile%"

move /y "%newfile%" "%TMPDIR%\config.txt" >nul
biosconfigutility64 /SetConfig:"%TMPDIR%\config.txt" >nul 2>&1
goto :retry_bootorder


REM ============================================
REM  MS UEFI CA key - GATE for script B (Security Settings)
REM  This option is not important by itself - it is used as an
REM  indicator of whether script B has run. If not, we launch B
REM  (we don't set the option directly ourselves, so we don't
REM  lose its other settings) and re-check.
REM ============================================
:CheckMSUEFICAKey
set "sName=Enable MS UEFI CA key"
set "sDesired=Yes"
set "attempt4=0"

:recheck_msuefi
set /a attempt4+=1
set "line="
for /f "delims=" %%i in ('biosconfigutility64 /getvalue:"%sName%" ^| findstr "VALUE"') do set "line=%%i"

if not defined line (
    call :SetStage "ERROR: could not read '%sName%'"
    exit /b 1
)

set "value=!line:*CDATA[=!"
set "value=!value:]]></VALUE>=!"
set "current="
for %%A in (%value:,= %) do (
    set "tok=%%A"
    if "!tok:~0,1!"=="*" set "current=!tok:~1!"
)

if /i "!current!"=="%sDesired%" (
    call :SetStage "OK: %sName% = !current! (script B has run)"
    goto :eof
)

if !attempt4! gtr 2 (
    call :SetStage "FAIL: %sName% still '!current!' after running script B %attempt4% time(s)"
    exit /b 1
)

call :SetStage "NEEDED: %sName% = '!current!' - script B has not run (or failed), launching it"

if not exist "%SECURITY_SCRIPT%" (
    call :SetStage "ERROR: security script not found at %SECURITY_SCRIPT%"
    exit /b 1
)

call "%SECURITY_SCRIPT%"
set "bresult=!errorlevel!"
call :SetStage "Script B finished (exit !bresult!), re-checking %sName%"
goto :recheck_msuefi


REM ============================================
REM  Stage logging
REM ============================================
:SetStage
echo [%date% %time%] %~1 >> "%STAGELOG%"
echo %~1
goto :eof
```

---

## How the script works — step by step

### Step 1. Identify the machine and read the state
The script gets the current machine's serial number via `wmic` and creates a **separate** state file for it (`flash_attempt_<serial>.state`). This matters because the USB drive is shared across many machines — a single shared state file would mix up flash attempts between machines. It then reads how many flash attempts have already happened (0 if the file doesn't exist — first run on this machine).

### Step 2. Check boot settings BEFORE the flash
Before anything else, the script makes sure Fast Boot is off and USB is first in the boot order. This is a safeguard in case these settings are already wrong — that way the next reboot (needed for the flash) is guaranteed to come from USB again.

### Step 3. Check the current BIOS version
A fork:
- **Version already matches the target** — no flash needed. The state file is deleted, and the script jumps straight to the final block.
- **Version doesn't match** — continue on to the flash.

### Step 4. Check the attempt limit
If there have already been 3 failed attempts and the version still hasn't changed, the script stops with an explicit error in the log. This guards against an infinite reboot → flash → reboot loop.

### Step 5. The flash itself
The attempt counter is incremented and saved to the file **before** the flash runs (in case the flash itself hangs). The flash utility is then run in silent mode, logging to a separate file.

### Step 6. Reboot
A required step — the new firmware only activates after a reboot; the actual flash write happens during POST on this reboot, not before (see "When does the flash actually happen?" above), so there's no boot-settings check between the flash command and this point — nothing would have changed yet. The script ends **this particular run**. Restarting the script after the reboot must be handled by an external mechanism (an MDT/SCCM Task Sequence step, a `RunOnce` registry entry, or logic in `unattendx.xml`).

### Step 7. Re-running after reboot
The whole process repeats from the top (Step 1), but now `attempt` is read from the file as `1` instead of `0`. The BIOS version is checked again — if the flash succeeded, the script goes to the final block, skipping another flash. If the version still doesn't match, the loop repeats until it succeeds or the 3 attempts run out.

### Final block: `:after_flash_confirmed`
The script only reaches this block once the BIOS version is confirmed to match the target (stage **A** done):
1. Checks Fast Boot / Boot Order **once more** — the most reliable checkpoint, since the flash has now definitely been applied.
2. Gates on **MS UEFI CA key** (stage **B**) — this option is not set by this script; it's only read as an indicator of whether script B (Security Settings) has already run. If it's not `Yes`, the script launches `%SECURITY_SCRIPT%` (script B) and re-checks, up to 2 times. It never sets the option itself — doing so would silently defeat the check, showing "OK" even if B never ran and none of its other settings were applied.
3. Once both A and B are confirmed, logs `"OK: stage A (BIOS flash) and stage B (security settings) confirmed"` and launches `%FINAL_SCRIPT%` (script C — the imaging dialog + Ghost), exiting with its return code. This script's job ends there; script C's own logic is untouched.

---

## Subroutines

| Subroutine | Purpose |
|---|---|
| `:GetBiosVersion` | Reads the BIOS version via `wmic`, extracts the clean value |
| `:CheckAndFixSimpleSetting` | Generic for any enum-style setting (currently used for Fast Boot): reads the value, parses the asterisk marker, fixes via `/setvalue` if it doesn't match, up to 3 attempts |
| `:CheckAndFixBootOrder` | Specific to the Boot Order list: dumps the full config, checks the first line of the block, rewrites it (moving USB to the top) if needed, applies it back |
| `:CheckMSUEFICAKey` | Read-only gate for script B: reads "Enable MS UEFI CA key" as an indicator of whether B has run; if not, launches `%SECURITY_SCRIPT%` and re-checks, up to 2 times — never sets the option itself |
| `:SetStage` | Writes a timestamped line to the shared `stage.log`, called from every block — a single continuous log for the whole process on a given machine |

---

## Important caveats

- The flash utility's command-line switches need to be verified on-site (see the section above).
- The `config.txt` format (for Boot Order) depends on the BCU version and model — it's worth manually checking it once after `/GetConfig`.
- The script uses `UEFI Boot Order` as the setting name — confirmed against a real config.txt dump for an HP ProBook 450 G1 (see Sources above), which has `Legacy Boot Order` and `UEFI Boot Order` as separate sections (no plain `Boot Order`). The exact name can still differ on this specific unit/BIOS revision — verify with `/dumpall` or an unfiltered `/GetConfig` on-site once the machine is available.
- For the retry loop to actually work across reboots, an external mechanism to re-launch the script (Task Sequence, RunOnce, etc.) is required — the script does not restart itself.
- `%SECURITY_SCRIPT%` (script B) and `%FINAL_SCRIPT%` (script C) are placeholders (`B.bat` / `C.bat` next to this script) — plug in the real file names/paths.
- Fast Boot and Boot Order are **not** part of script B — they were added directly to this script so the pipeline doesn't need someone to manually catch every reboot and re-enter the BIOS boot menu.
