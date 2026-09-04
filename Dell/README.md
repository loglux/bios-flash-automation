# Dell BIOS Flash & Configuration Automation

Planned automation for detecting a Dell model, applying BIOS setting
fixes (e.g. disabling IPv6), and flashing the model-specific BIOS
firmware — run from the same WinPE bootable USB flash drive as the
`HP/` pipeline.

No exact model list yet. `Dell-SetBootSettings.bat` /
`Dell-RestoreBootSettings.bat` exist as untested drafts (see below) —
not yet run against real Dell hardware. The one fixed requirement so
far: the approach must make adding a new model easy — a config entry,
not new logic.

---

## Design goal

Unlike the HP project (a single model, `HP ProBook 4 G1ah14`), Dell
automation has to support several models from the start, with the
list expected to grow over time and not fully known yet. So the
dispatch logic itself must stay model-agnostic — per-model specifics
(firmware file, target version, settings profile) live in a lookup
table keyed by model/Service Tag, not hardcoded into the script flow.
Adding a model later means adding a row to that table, not writing a
new script.

---

## Planned approach

### 1. Vendor + model detection

- `wmic computersystem get manufacturer` — `Dell Inc.` for Dell, vs.
  `Hewlett-Packard` (older) or `HP` (newer) for HP. Match by substring,
  not exact equality, same reasoning as the HP project's BIOS-version
  check — used as a safety guard so a Dell-only script refuses to run
  on the wrong vendor's hardware.
- `wmic csproduct get name` (or `Get-CimInstance Win32_ComputerSystem`
  for `Model`) — human-readable model name.
- `wmic bios get serialnumber` — the Dell Service Tag. More reliable
  than the model name alone, since it unambiguously identifies the
  exact line/revision.
- Implemented as a draft in `Dell-SetBootSettings.bat` (STEP 0) — logs
  manufacturer/model/Service Tag and aborts if the manufacturer isn't
  Dell. Not yet wired into a model → config lookup table.
- **Tested on real hardware** (a Dell Precision T1700, from its own
  WinPE boot): manufacturer detection worked correctly (`Manufacturer:
  Dell Inc.`), but the original `findstr`-based substring check failed
  — `findstr` isn't present on that WinPE image (a minimal build).
  Switched to a PowerShell `-match` check instead, matching how the HP
  scripts already handle equivalent substring checks. Everything past
  STEP 0 (backup + the three settings) is still untested.

### 2. BIOS settings

- **Dell Command | Configure** (`cctk.exe`) — Dell's standalone
  equivalent of HP's BiosConfigUtility64. No installation needed; runs
  directly from the USB flash drive under WinPE.
- Current version (5.2.2) officially supports WinPE (64-bit and
  ARM64), confirming this fits the same USB/WinPE workflow as the HP
  pipeline. See Documentation below.

Checked the actual option names against the v5.x CLI Reference Guide
(the earlier `--Ipv6=Disabled` example was a guess and doesn't exist —
corrected below):

| HP setting (BiosConfigUtility64) | Dell Command \| Configure equivalent | Notes |
|---|---|---|
| Fast Boot (`Enable`/`Disable`) | `--Fastboot` — `Thorough`, `Minimal`, `Auto` | Not a plain toggle — controls POST thoroughness, three values not two. `Minimal` is the closest match to "fast", and is confirmed in two independent real-world deployment scripts, not just the doc (see Documentation below) — though an older (2014, CCTK-era) blog used the value `automatic` instead of today's `Auto`, so value spelling has changed across versions. |
| Startup Delay (sec.) | `--ExtPostTime` — `0s`, `5s`, `10s`, `30s`, `60s` | Same purpose (delays the F2/F12 hotkey window during POST), fixed value set instead of an arbitrary number of seconds. Not found in use in any real-world script so far — confirmed only via Dell's own sample settings dump in the CLI Reference Guide appendix (`ExtPostTime=0s`), not via independent third-party usage. |
| UEFI Boot Order (USB first / disk first) | `cctk BootOrder --BootListType=uefi --Sequence=... --EnableDevice=... --DisableDevice=...` | Confirmed exact syntax, both from the official guide's own examples and from two independent real-world scripts using `usbdev` as the USB short form. UEFI device short forms include `hdd`, `usbhdd`, `usbdev`, `cdrom`, `embnic`, `embnicipv4`, `embnicipv6`, etc. |
| IPv6 | No plain "disable IPv6" option exists. Closest matches: `--IPv6PXEBoot` (`Enabled`/`Disabled`, IPv6 **PXE boot only**), `--IPvXBootOrder` (`IPv4`/`IPv6`, preference order when both PXE options are on), `--UefiNwStack` (`Enabled`/`Disabled`/`SelectiveEnable`/`AutoEnable`, master switch for the whole preboot UEFI network stack, v4+v6 together) | All three are preboot/PXE-networking knobs, not an OS-level IPv6 stack toggle. Need to pin down which one actually matches the original intent before picking one. |

Source: Dell Command | Configure Version 5.x Command-line Interface
Reference Guide (linked below).

### Backing up and restoring settings

`cctk.exe` has a built-in snapshot mechanism, useful for testing safely
on real hardware:

- `cctk.exe -O backup.ini` — dumps **every** current BIOS setting
  (including `Fastboot`, `ExtPostTime`, `BootOrder`, everything) to an
  INI file.
- `cctk.exe -i backup.ini` — re-applies a previously dumped INI file,
  restoring that exact state.

Confirmed against the CLI Reference Guide's own appendix ("Sample Dell
Command | Configure utility.ini file format"), which shows a real dump
from an actual machine including `ExtPostTime=0s`, `Fastboot=Thorough`,
and `BootOrder=uefitype,+hdd.1,+hdd.2` — proof these three settings are
genuinely readable/writable this way, not just documented in theory.
The exact quoting/`=`-vs-space format for `-O`/`-i` still needs
confirming on real hardware — the guide's own example formatting for
these two is inconsistent (PDF extraction artifact, or a real quirk).

### 3. Firmware flashing

The main open question, needs per-model verification before anything
is built:

- Dell BIOS updates typically ship as a self-extracting `.exe` with a
  silent `/s` flag.
- Not all of them are WinPE-compatible — some require a full Windows
  environment to run. Each package's release notes usually say whether
  offline/WinPE flashing is supported.
- Fallback to check per model: UEFI Flash-from-capsule via **F12 →
  BIOS Flash Update**, which reads the firmware file straight off USB
  without needing any runner executable at all.

### 4. Multi-model dispatch

A `Model` / `Service Tag prefix` → `{flash file, target version,
settings profile}` lookup table drives the pipeline. This isn't
speculative complexity — it's required because, unlike the HP project,
there is more than one real model to support from day one; the table
just isn't populated yet since the exact model list isn't confirmed.

### 5. Vendor dispatcher (future — not built yet)

Idea to keep, not implemented: a single top-level entry point on the
USB flash drive that runs first, checks `Manufacturer` (see Vendor +
model detection above), and launches the matching pipeline —
`HP/HP-ProBook-BiosCheck-v6.bat` for HP, the Dell entry script for
Dell. Both pipelines already exist side by side (`HP/`, `Dell/`), so
this would just be the missing "which one do I run" step at the very
top, instead of someone picking manually per machine.

Deliberately parked for now — `Dell-SetBootSettings.bat`'s own
vendor check (STEP 0) is enough while the Dell side is still
untested; build the real dispatcher once the Dell pipeline itself is
proven on hardware.

---

## Documentation

- [Dell Command | Configure — overview / KB article](https://www.dell.com/support/kbdoc/en-us/000178000/dell-command-configure)
- [Dell Command | Configure v5.x — Command-line Interface Reference Guide](https://www.dell.com/support/manuals/en-us/command-configure/dcc_5.x_ref_guide/introduction-to-dell-command-configure) ([PDF](https://dl.dell.com/content/manual22642211-dell-command-configure-version-5-x-command-line-interface-reference-guide.pdf))
- [Dell Command | Configure v5.x — User's Guide](https://www.dell.com/support/manuals/en-us/command-configure/dcc_ug_5.x/Dell-Command--Configure-Version-5x-Users-Guide)
- [Dell Command | Configure — download page](https://www.dell.com/support/home/en-us/drivers/DriversDetails?driverId=F2V9N)
- CLI Reference Guide Appendix, "Sample Dell Command | Configure utility.ini file format" (same PDF above) — a real settings dump confirming `ExtPostTime`, `Fastboot`, and `BootOrder` all exist and are captured by `-O`/`-i`.
- [How to Build a Dell USB Imaging Tool (Brooks Peppin)](https://brookspeppin.com/2022/01/29/build-a-fast-diy-usb-zero-touch-provisioning-process-for-dell/) — real-world deployment script, confirms `--Fastboot=Minimal` and `bootorder --sequence=...,usbdev,...` in practice.
- [Mick's IT Blog — Installing Dell CCTK and Configuring BIOS Settings](https://mickitblog.blogspot.com/2014/05/powershell-installing-dell-cctk-and.html) — older (CCTK-era) example, same `bootorder --sequence=...,usbdev,...` pattern, but uses the now-outdated value `automatic` instead of `Auto` for Fastboot.
