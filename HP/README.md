# HP ProBook 4 G1 — BIOS Flash & Configuration Automation

Batch script automating BIOS flashing and configuration of key settings
(Fast Boot, Boot Order, Enable MS UEFI CA key) on the HP ProBook 4 G1 via
HP BiosConfigUtility64 (BCU), run from a bootable USB drive in WinPE.

A proposed improvement to the existing manual imaging procedure: replaces
manually catching each reboot and re-entering the BIOS boot menu (F9) with
a script that checks, fixes, and logs these steps itself.

---

## What the script does

The pipeline glues together three scripts:
- **A** — flashes the BIOS to the target version (implemented directly in this script)
- **B** — configures several Security Settings options, including "Enable MS UEFI CA key"
  (an existing script, called by this one — its internals are out of scope here)
- **C** — the final imaging dialog + Ghost (an existing script, launched at the end)

Plus Fast Boot and Boot Order (USB first), which are not part of script B — they were
added directly to this script so the pipeline doesn't need someone to manually catch
every reboot and re-enter the BIOS boot menu.

1. Checks and fixes Fast Boot and Boot Order (USB first) before flashing
2. Checks the current BIOS version against the target
3. If it doesn't match — flashes, with retry logic (up to 3 attempts) across reboots,
   with the attempt counter tied to the machine's serial number
4. Once the version is confirmed — final check of Fast Boot / Boot Order, then a gate on
   "Enable MS UEFI CA key": if not `Yes`, launches script B (Security Settings) and
   re-checks — never sets the value itself
5. Once the gate passes — launches script C (imaging dialog + Ghost), without touching
   its internal logic
6. Logs every step to `stage.log`

For a detailed logic walkthrough, see
`docs/HP-ProBook-BIOS-Flash-Full-Script.md`.

---

## Notes

- Real names/paths for scripts B (Security Settings) and C (dialog + Ghost) —
  currently placeholders `B.bat` / `C.bat` next to the script. Candidates spotted
  in a real file listing from this environment: `SetBiosProBook4G1ah14.bat`,
  `Post_Ghost.bat`, `STARTXUEFI85.bat` — not yet confirmed which map to B/C.
- Whether these machines have HP Sure Start is not yet confirmed — if so, the BIOS
  update may trigger more than one reboot before the version actually changes (the
  attempt-counter loop already tolerates this, just worth knowing in advance).
- What BIOS password script B sets, and the other ~3 Security Settings it configures
  alongside "Enable MS UEFI CA key", are not yet identified.
- No self-recovery if Boot Order resets during the flash-triggered reboot on a
  machine that already has a working OS on disk — it boots into Windows instead
  of back into WinPE, and the script (living only on the USB drive) can't restart
  itself. The Step 1 check before the flash is the only protection in place.
  Machines with a blank disk are expected to be unaffected. Observed on hardware
  during on-site testing.
- Re-launching the script after a flash-triggered reboot needs to be hooked into
  whatever already launches on boot for this imaging environment (WinPE always runs
  `Startnet.cmd` on every boot — the existing `T1700Setup` process starts itself this
  way already). Not yet implemented: check for the `flash_attempt_<serial>.state`
  file, launch this script if present.

---

## Idea: desktop shortcuts for remote configuration

Not part of the BIOS pipeline above — a separate proposal for the imaging process around it.

Some machines need tool shortcuts (compliance, restart, Altiris, etc.) on the desktop so an engineer can finish configuring them over a remote connection after imaging. Placing them can be automated the same way as the rest of this project: `HP-ProBook-PlaceShortcuts.bat` copies every `.lnk` file from a `Shortcuts/` folder next to it onto the target system's Public Desktop (`Users\Public\Desktop`) while still in WinPE — visible to whichever account is used to connect remotely, without depending on a specific username or on a new profile being created first. Managing the shortcut list is just adding or removing files in that folder, not editing the script.

Cleanup (removing those shortcuts once remote configuration is done) is deliberately **not** automated the same way — an automatic trigger at first login would delete them before they're ever used. It only makes sense as a step the engineer takes once configuration is actually finished, ideally centrally across whichever machines are done rather than one at a time (e.g. via Altiris/Notification Server pushing the existing cleanup script, or `Invoke-Command`/PsExec against a list of hosts) rather than manually double-clicking a desktop icon on each machine.

```bat
@echo off
setlocal enabledelayedexpansion

REM Copies every .lnk file from the Shortcuts folder (next to this
REM script) onto the target system's Public Desktop, so they're
REM visible to whichever account is used to connect remotely and
REM finish configuring the machine. Doesn't need to know the exact
REM list of shortcuts - just copies whatever is currently in the
REM Shortcuts folder. Manage the shortcut list by adding/removing
REM files there, not by editing this script.
REM
REM TARGET_DRIVE: the offline target system's internal disk drive
REM letter, as seen from WinPE - NOT the boot USB drive (which is D:
REM in this project's real environment; X: is WinPE's own RAM disk).
REM The internal disk is typically C: from within WinPE, but verify
REM on-site before relying on this.

set "SHORTCUTS_SRC=%~dp0Shortcuts"
set "TARGET_DRIVE=C:"
set "PUBLIC_DESKTOP=%TARGET_DRIVE%\Users\Public\Desktop"

if not exist "%SHORTCUTS_SRC%" (
    echo ERROR: shortcuts source folder not found at %SHORTCUTS_SRC%
    exit /b 1
)

if not exist "%PUBLIC_DESKTOP%" (
    echo ERROR: target Public Desktop not found at %PUBLIC_DESKTOP%
    exit /b 1
)

set "found=0"
for %%F in ("%SHORTCUTS_SRC%\*.lnk") do set "found=1"

if "!found!"=="0" (
    echo No .lnk files found in %SHORTCUTS_SRC% - nothing to copy.
    exit /b 0
)

copy "%SHORTCUTS_SRC%\*.lnk" "%PUBLIC_DESKTOP%\" /y

if !errorlevel! neq 0 (
    echo ERROR: copy failed, exit code !errorlevel!
    exit /b 1
)

echo OK: shortcuts copied to %PUBLIC_DESKTOP%
exit /b 0
```

The cleanup counterpart, `HP-ProBook-RemoveShortcuts.bat`, runs later on the live target system (not from WinPE), triggered centrally once configuration is actually done:

```bat
@echo off
setlocal enabledelayedexpansion

REM Removes every .lnk shortcut from the target system's Public
REM Desktop. Runs on the LIVE target system (not from WinPE) - after
REM remote configuration is finished, meant to be triggered centrally
REM (e.g. pushed via Altiris/Notification Server, or Invoke-Command/
REM PsExec against a list of hosts) rather than double-clicked one
REM machine at a time.

del "%PUBLIC%\Desktop\*.lnk" /q

echo OK: shortcuts removed from %PUBLIC%\Desktop
exit /b 0
```

---

## Sources

Directly backing the canonical script (flash flags/timing, `config.txt` format).

- [Updating BIOS Command Lines — HP Support Community](https://h30434.www3.hp.com/t5/Commercial-PC-Software/Updating-BIOS-Command-Lines/td-p/6518162)
- [BIOS Flash Update (HP PDF)](https://h30434.www3.hp.com/psg/attachments/psg/Business-PC-Workstation-POS/34410/1/BIOS%20Flash%20Update.pdf)
- [How to Update HP BIOS on Commercial Platforms — HP Developer Portal](https://developers.hp.com/hp-client-management/blog/how-update-hp-bios-commercial-platforms)
- [bios1.txt — real config.txt dump for an HP ProBook 450 G1](https://h30434.www3.hp.com/psg/attachments/psg/Tablet/1373380/1/bios1.txt)
- [HP BIOS Configuration Utility (BCU) User Guide (PDF)](https://ftp.hp.com/pub/caps-softpaq/cmit/whitepapers/BIOS_Configuration_Utility_User_Guide.pdf) — official command reference (`/getvalue`, `/setvalue`, `/GetConfig`, `/SetConfig`, `/cpwdfile`) and a sample config.txt
- [How to change BIOS settings on a HP PC — HP Wolf Pro Security Support](https://support.hpwolf.com/s/article/How-to-change-BIOS-settings-on-a-HP-PC) — covers the four BCU/WMI setting types, including a real `UEFI Boot Order` example matching this project's own device-naming format, and the `/cpwdfile` password-file mechanism
- [BIOS Settings Protection Assessment — HP Wolf Pro Security Support](https://support.hpwolf.com/s/article/BIOS-Settings-Protection-Assessment)

---

P.S. HP also publishes an official PowerShell module for BIOS management and
flashing — HP Client Management Script Library (HP CMSL), with cmdlets like
`Set-HPBIOSSettingValue` and `Update-HPFirmware`.

- [Client Management Script Library (HP CMSL) — HP Developer Portal](https://developers.hp.com/hp-client-management/doc/client-management-script-library)
