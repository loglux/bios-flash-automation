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

## The four `.ps1` scripts next to it

`v6.bat` doesn't touch BCU directly for anything except the simplest
`/setvalue` calls — reading a setting's current value, or handling
Boot Order specifically, is delegated to these four scripts. All four
take their input via environment variables set by the calling `.bat`
(`_pname`, etc.), not command-line arguments — keeps the `call`
sites in `v6.bat` simple, and matches the convention `GetBiosValue`
itself was written to (see its own comment).

- **`SystemIdentity-Check.ps1`** — not HP-specific, shared with
  `Dell/`/`VendorDispatch/` (see `SystemIdentity/README.md` for the
  full detail). Reads Manufacturer/Model/BiosVersion via
  `Get-CimInstance`, prints `Key|Value` lines. Used once, in STEP 1,
  to get the current BIOS version and to defensively confirm the
  manufacturer is HP before doing anything else.
- **`HP-ProBook-GetBiosValue.ps1`** — reads **one** BIOS setting via
  `BiosConfigUtility64.exe /getvalue`. Two modes: `Raw` (the setting's
  full `CDATA` content, whatever it is) and `Enum` (for settings that
  are a comma-separated list of choices with the current one marked
  `*`, like `Fast Boot`: extracts just that marked choice). This is
  the read half of `:CheckAndFixSimpleSetting` in `v6.bat` — used for
  Fast Boot, Startup Delay, and the "Enable MS UEFI CA key" gate. The
  write half is a plain `/setvalue` call, no script needed for that.
- **`HP-ProBook-CheckBootOrderFirst.ps1`** — Boot Order is a
  **list**, not a single enum value, so it needs its own check: reads
  the list, prints `MATCH|<entry>` if the first entry looks like the
  boot USB, `NOMATCH|<entry>` otherwise, `ERROR|` if the setting
  couldn't be read at all. This is what `:CheckAndFixBootOrder` uses
  to decide whether Boot Order needs fixing in the first place.
- **`HP-ProBook-FindConfigLine.ps1`** — the actual *fix* for Boot
  Order, once `CheckBootOrderFirst` says it's needed. Unlike the
  simple settings, a list can't be changed with one `/setvalue` — BCU
  has to dump the whole config to a file (`/GetConfig`), the right
  line inside the `UEFI Boot Order` block gets moved to the top, then
  the whole file is re-imported (`/SetConfig`). This script is the
  "which line" part of that: given a block header and a regex, it
  returns the first matching line (used to find the USB entry when
  fixing) or, with `-Exclude`, the first **non**-matching line (used
  in STEP 3 to find a non-USB/non-network entry when resetting back
  to disk-first before handing off to `C.bat`). The line-swapping
  itself happens in `v6.bat`, not in this script.

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
