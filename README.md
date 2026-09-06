# BIOS Flash & Configuration Automation

BIOS flashing and configuration automation for a fleet of thousands of
HP and Dell laptops/desktops, run from a bootable WinPE USB drive
during imaging. Started as an HP ProBook 4 G1-only project; expanded
to cover multiple vendors and models.

---

## Layout

- **`VendorDispatch/`** — the single entry point meant to live at the
  root of the USB drive: detects the vendor (HP or Dell), then hands
  off to that vendor's own pipeline below. Draft, not yet run on real
  hardware.
- **`HP/`** — the mature, hardware-tested pipeline (`HP-ProBook-BiosCheck-v6.bat`
  is current; `v1.bat` through `v5.bat` kept in `HP/Legacy/`, each
  version untouched once shipped). Covers one real model (HP ProBook
  4 G1ah14): version check → flash → security settings → boot-order
  reset → imaging handoff.
- **`Dell/`** — vendor/model detection + BIOS settings via Dell Command |
  Configure (`cctk.exe`). No flash step exists yet — confirmed no Dell
  BIOS flashing happens anywhere in the real fleet's own tooling
  either, only settings.
- **`SystemIdentity/`** — vendor-agnostic Manufacturer/Model/SerialNumber/
  BiosVersion check, shared instead of re-implemented per script.
  Confirmed working on real hardware; currently wired into
  `HP/HP-ProBook-BiosCheck-v6.bat` for logging only (doesn't affect its
  behavior), not yet into `VendorDispatch/` or `Dell/` despite being
  built to replace their own inline detection.
- **`PowerState/`** — vendor-agnostic pre-flash AC/battery safety check,
  with a possible wait-and-recheck delay for battery charge. Both HP's
  and Dell's own flash tools refuse to run on bad power state; this
  catches it earlier with a clearer message. The open question behind
  it: whether battery charge still matters even when AC is already
  connected - HP's own docs only state the no-AC case directly, so
  this is a logical inference, not a confirmed fact, and still needs a
  real test to settle. Draft, not tested on real hardware, script
  itself still likely to change once that's confirmed.

Each folder's own README has the full detail, sourcing, and open gaps
for that piece.

---

## Concept: universal model/procedure selection

Splits model handling into three separate concerns, instead of
blending them the way `v6.bat` currently does (it has its own HP-only
check baked directly into the procedure itself):

1. **A models list** - a CSV catalog of every known machine: Product
   ID, Model name, Vendor. Doesn't exist yet as its own file; model
   names currently only appear scattered across comments and docs.
2. **A selection step** - looks up the detected machine in that CSV
   and decides: launch the matching procedure, or exit with a clear
   "unsupported machine" error. Never falls back to a default/generic
   procedure on no match. `VendorDispatch/` is an early, partial version
   of this today, but only at the vendor level (HP vs Dell), not
   per-model.
3. **The procedure itself** - whatever set of scripts a given model
   actually needs (state checks, specific steps in sequence), named
   cleanly by model (e.g. `hp_<model>`, `dell_<model>`) rather than by
   version number - stays focused on doing the work, not on deciding
   whether it should run at all.

The detection step (1+2) runs fresh on **every single launch** - this
is deliberate, not a missed optimization. WinPE has no memory across
reboots (RAM-loaded OS), and the same USB drive serves many different
physical machines across the fleet - caching a previous result would
go stale the moment the drive moves to another machine. The cost of
re-checking (a WMI/CIM query) is negligible next to the minutes-long
flash/imaging steps that follow it.
