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
- **`HP/`** — the mature, hardware-tested pipeline (`HP-ProBook-BiosCheck-v1.bat`
  through `v6.bat`, each version kept as-is once shipped). Covers one
  real model (HP ProBook 4 G1ah14): version check → flash → security
  settings → boot-order reset → imaging handoff.
- **`Dell/`** — vendor/model detection + BIOS settings via Dell Command |
  Configure (`cctk.exe`). No flash step exists yet — confirmed no Dell
  BIOS flashing happens anywhere in the real fleet's own tooling
  either, only settings.
- **`SystemIdentity/`** — vendor-agnostic Manufacturer/Model/SerialNumber/
  BiosVersion check, shared instead of re-implemented per script. Draft,
  not tested on real hardware; currently wired into `HP/HP-ProBook-BiosCheck-v6.bat`
  for logging only (doesn't affect its behavior), not yet into
  `VendorDispatch/` or `Dell/` despite being built to replace their own
  inline detection.
- **`PowerState/`** — vendor-agnostic pre-flash AC/battery safety check,
  with a possible wait-and-recheck delay for battery charge. Both HP's
  and Dell's own flash tools refuse to run on bad power state; this
  catches it earlier with a clearer message. The open question behind
  it: whether battery charge still matters even when AC is already
  connected - HP's own docs only state the no-AC case directly, so
  this is a logical inference, not a confirmed fact, and still needs a
  real test to settle. Draft, not tested on real hardware, script
  itself still likely to change once that's confirmed.

## Status at a glance

Only `HP/` (`v6.bat`) has been verified end-to-end on real hardware.
Everything else - `VendorDispatch/`, `SystemIdentity/`, `PowerState/`,
and the Dell side - is a draft that hasn't run on real hardware yet.

Each folder's own README has the full detail, sourcing, and open gaps
for that piece.
