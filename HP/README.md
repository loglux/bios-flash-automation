# HP ProBook 4 G1 — BIOS Flash & Configuration Automation

Batch script automating BIOS flashing and configuration of key settings
(Fast Boot, Boot Order, Enable MS UEFI CA key) on the HP ProBook 4 G1 via
HP BiosConfigUtility64 (BCU), run from a bootable USB drive in WinPE.

A proposed improvement to the existing manual imaging procedure: replaces
manually catching each reboot and re-entering the BIOS boot menu (F9) with
a script that checks, fixes, and logs these steps itself.

---

## What the script does

`HP-ProBook-BiosCheck-v6.bat` orchestrates three external scripts —
**A** (flash), **B** (security settings), **C** (imaging dialog +
Ghost) — without implementing any of their internals itself. `A.bat`/
`B.bat`/`C.bat` are expected to already be present alongside it (they
come from the real deployment environment, not this repo).

1. **STEP 1** — reads Manufacturer/Model/BiosVersion via
   `SystemIdentity-Check.ps1`, defensively errors out if the
   manufacturer isn't HP. Compares BIOS version against
   `TARGET_VERSION` (substring match, since some platforms report a
   product-code prefix). If it doesn't match: checks/fixes Fast Boot
   and Boot Order (USB first), then calls `A.bat` and exits with its
   code — relies on the next WinPE boot to re-run this script and
   re-check, there's no in-script retry loop or attempt counter.
2. **STEP 2** — once the version matches, gates on "Enable MS UEFI CA
   key" as an indicator of whether `B.bat` has run (never sets the
   value directly itself): if not `Yes`, checks/fixes Fast Boot/Boot
   Order again, calls `B.bat`, re-checks (up to 3 attempts).
3. **STEP 3** — once both are confirmed, resets Fast Boot/Boot
   Order/Startup Delay back to factory defaults before handing off.
4. **STEP 4** — calls `C.bat`.

Everything is logged with plain `echo` to the console only — nothing
persists to a file, so this output is lost once the console closes.

The four `.ps1` helpers next to it (`HP-ProBook-GetBiosValue.ps1`,
`HP-ProBook-CheckBootOrderFirst.ps1`, `HP-ProBook-FindConfigLine.ps1`,
`SystemIdentity-Check.ps1`) are its real, confirmed dependencies —
`GetBiosValue` reads simple enum-style settings (Fast Boot, Startup
Delay, the CA key), `CheckBootOrderFirst`/`FindConfigLine` exist
specifically because Boot Order is a *list* setting that can't be
fixed with a single `/setvalue` the way the others can.

---

## Other folders here

- **`Legacy/`** — `v1.bat` through `v5.bat`, superseded by `v6.bat`,
  kept untouched as historical reference (this project's own
  versioning convention).
- **`Tools/`** — standalone diagnostic/utility scripts `v6.bat`
  doesn't call: boot-settings checkers, a reset script, the
  not-yet-wired-in BootNext experiments.
- **`DesktopShortcuts/`** — a separate feature, own README.
- **`docs/`, `experimental/`** — deeper notes on specific mechanisms
  (Fast Boot/Boot Order handling, the CA key gate).

---

## Notes

- What BIOS password `B.bat` sets, and the other Security Settings it
  configures alongside "Enable MS UEFI CA key", are not identified
  here (out of scope for this repo).
- No self-recovery if Boot Order resets during the flash-triggered
  reboot on a machine that already has a working OS on disk — it
  boots into Windows instead of back into WinPE, and the script
  (living only on the USB drive) can't restart itself. STEP 1's check
  before the flash is the only protection in place. Observed on
  hardware during on-site testing.

---

## Desktop shortcuts for remote configuration

Not part of the BIOS pipeline above — a separate proposal for the
imaging process around it, now in its own `DesktopShortcuts/`
subfolder with its own README.

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
