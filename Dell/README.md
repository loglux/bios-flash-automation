# Dell BIOS Flash & Configuration Automation

Planned automation for detecting a Dell model, applying BIOS setting
fixes (e.g. disabling IPv6), and flashing the model-specific BIOS
firmware — run from the same WinPE bootable USB flash drive as the
`HP/` pipeline.

No exact model list yet. `Dell-SetBootSettings.bat` /
`Dell-RestoreBootSettings.bat` / `Dell-FindUsbBootDevice.ps1` exist as
drafts (see below) — partially confirmed on real hardware, restore
still untested. The one fixed requirement so far: the approach must
make adding a new model easy — a config entry, not new logic.

**Note for whoever copies these onto the test USB drive**: copy the
`.bat` files straight from this repo, not through an intermediate
editor that might save with a UTF-8 BOM — a BOM before `@echo off`
makes cmd.exe fail to parse that line, so `echo` never gets turned
off and every subsequent line gets echoed back noisily. Purely
cosmetic (the rest of the script still runs), but worth avoiding.

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

## The scripts

- **`Dell-SetBootSettings.bat`** — the main script. STEP 0: detects
  Manufacturer/Model/Service Tag (`wmic` + PowerShell `-match`, same
  pattern the HP scripts use), aborts if the manufacturer isn't Dell.
  STEP 1: snapshots **every** current BIOS setting via `cctk -O`
  before changing anything, so the machine can be restored later.
  STEP 2: applies `--Fastboot=Thorough`, `--ExtPostTime=5s`, and sets
  Boot Order to put USB first — using `Dell-FindUsbBootDevice.ps1` to
  find the right device name rather than assuming one.
- **`Dell-FindUsbBootDevice.ps1`** — helper called from STEP 2. The
  USB flash drive's `cctk` Boot Order short-form isn't a fixed
  constant across machines (confirmed `usbhdd`, not the assumed
  `usbdev`, on a real Latitude 5530) — this reads the live Boot Order
  table and picks out whichever entry is actually the USB device,
  reading column positions from the table's own header line rather
  than assuming them (so a device named e.g. "USB Hard Disk" doesn't
  false-match a plain keyword search).
- **`Dell-RestoreBootSettings.bat`** — restores the snapshot
  `Dell-SetBootSettings.bat`'s STEP 1 made (`cctk -i` the backup
  `.ini`). DRAFT, not yet verified on real hardware.

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
- **Tested on real hardware** (a Dell Precision T1700, then a Dell
  Latitude 5530, both from their own WinPE boot):
  - Manufacturer detection worked (`Manufacturer: Dell Inc.`), but the
    original `findstr`-based substring check failed — `findstr` isn't
    present on that WinPE image (a minimal build). Switched to a
    PowerShell `-match` check instead, matching how the HP scripts
    already handle equivalent substring checks.
  - Model and Service Tag detection both worked cleanly on the
    Latitude 5530 (`Model: Latitude 5530`, `Service Tag: XXXXXXX` —
    redacted here; the actual test machine's real tag was originally
    committed by mistake, see privacy note in `SystemIdentity/README.md`).

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
| Fast Boot (`Enable`/`Disable`) | `--Fastboot` — `Thorough`, `Minimal`, `Auto` | Not a plain toggle — controls POST thoroughness, three values not two. HP disables Fast Boot specifically "so the USB drive is actually picked up" (`HP/docs/HP-BCU-FastBoot-BootOrder.md`) — `Thorough` (full hardware/config testing) is the matching Dell state, not `Minimal` (least testing = the analog of Fast Boot **enabled**, the opposite of what we want). This is the same real phenomenon on Dell, not just an HP-analogy guess: Dell's own community support confirms *"If the USB drive is missing from the boot selection screen, you can disable the Fastboot feature to allow hardware recognition"*, and recommends `Fastboot=Thorough` specifically to fix a USB drive not being detected. `Minimal` was the initial (wrong) pick, corrected to `Thorough`; not yet re-tested on hardware since the fix. Brooks Peppin's real-world Dell USB-provisioning script (below) used `Minimal` for this same use case — unclear why that worked for them; possibly Thunderbolt/USB-C-specific detection issues (where this matters most, per the Dell community reports) don't apply to their hardware/USB port. |
| Startup Delay (sec.) | `--ExtPostTime` — `0s`, `5s`, `10s`, `30s`, `60s` | Same purpose (delays the F2/F12 hotkey window during POST), fixed value set instead of an arbitrary number of seconds. **Confirmed working on real hardware** (Latitude 5530: `cctk --ExtPostTime=5s` echoed back `ExtPostTime=5s` with no warning/error) — previously only seen in Dell's own sample dump, never in independent usage. |
| UEFI Boot Order (USB first / disk first) | `cctk BootOrder --BootListType=uefi --Sequence=<usb-shortform>,hdd.1` | Confirmed syntax, but **the USB short form is machine-specific, not a fixed constant** — on the Latitude 5530 the actual boot device showed up as `usbhdd` ("USB Hard Disk", the Kingston flash drive), and the hardcoded `usbdev` guess failed with `WARNING : Unable to set BootOrder for : usbdev`. Fixed by reading the live device table (`cctk BootOrder --BootListType=uefi`, no `--Sequence`) and picking whichever short form is `usbhdd` or `usbdev` — see `Dell-FindUsbBootDevice.ps1`. Real device list on that machine also included `embnicipv4`/`embnicipv6` (onboard NIC PXE boot entries) — likely what "an IPv6 option to disable" from memory actually refers to, since they sit right in this same Boot Order list, not as a separate BIOS setting. |
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

### 5. Vendor dispatcher

Now built as a draft — see `VendorDispatch/`. A single top-level entry
point that checks `Manufacturer` (see Vendor + model detection above)
and launches the matching pipeline — `HP/HP-ProBook-BiosCheck-v6.bat`
for HP, `Dell-SetBootSettings.bat` for Dell. Not yet run on real
hardware, and the Dell branch currently only reaches this file's
detection/settings/backup logic, not a full flash-and-image pipeline
(there's no Dell equivalent yet of HP's version-check/flash/handoff
steps) — see `VendorDispatch/README.md` for that asymmetry.

---

## Documentation

- [Dell Command | Configure — overview / KB article](https://www.dell.com/support/kbdoc/en-us/000178000/dell-command-configure)
- [Dell Command | Configure v5.x — Command-line Interface Reference Guide](https://www.dell.com/support/manuals/en-us/command-configure/dcc_5.x_ref_guide/introduction-to-dell-command-configure) ([PDF](https://dl.dell.com/content/manual22642211-dell-command-configure-version-5-x-command-line-interface-reference-guide.pdf))
- [Dell Command | Configure v5.x — User's Guide](https://www.dell.com/support/manuals/en-us/command-configure/dcc_ug_5.x/Dell-Command--Configure-Version-5x-Users-Guide)
- [Dell Command | Configure — download page](https://www.dell.com/support/home/en-us/drivers/DriversDetails?driverId=F2V9N)
- CLI Reference Guide Appendix, "Sample Dell Command | Configure utility.ini file format" (same PDF above) — a real settings dump confirming `ExtPostTime`, `Fastboot`, and `BootOrder` all exist and are captured by `-O`/`-i`.
- [How to Build a Dell USB Imaging Tool (Brooks Peppin)](https://brookspeppin.com/2022/01/29/build-a-fast-diy-usb-zero-touch-provisioning-process-for-dell/) — real-world deployment script, confirms `--Fastboot=Minimal` and `bootorder --sequence=...,usbdev,...` in practice.
- [Mick's IT Blog — Installing Dell CCTK and Configuring BIOS Settings](https://mickitblog.blogspot.com/2014/05/powershell-installing-dell-cctk-and.html) — older (CCTK-era) example, same `bootorder --sequence=...,usbdev,...` pattern, but uses the now-outdated value `automatic` instead of `Auto` for Fastboot.
