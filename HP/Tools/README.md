# Tools

Standalone diagnostic/utility scripts — none of these are called by
`HP-ProBook-BiosCheck-v6.bat`. Run manually, independent of the main
pipeline.

- **`HP-ProBook-CheckBootSettings.bat`** — checks and fixes Fast Boot,
  Boot Order (USB first), and Startup Delay in one pass, prints the
  final value of all three. The general-purpose version of the same
  logic `v6.bat` runs internally before its own flash/settings steps.
- **`HP-ProBook-CheckBootSettings-Hardcoded.bat`** — fallback variant
  of the above, for if the "find USB in the device list" heuristic
  ever fails to identify the boot device correctly. Rewrites Boot
  Order with a hardcoded full device list instead of editing the
  existing one. Simpler, but the device list is specific to the exact
  machine/BIOS revision it was captured on (2026-09-02) — a different
  model or revision may use different device names, and this script
  would silently write the wrong list there. Verify before using on
  anything but that same hardware.
- **`HP-ProBook-ResetBootSettings.bat`** — the reverse of
  `CheckBootSettings`: resets Fast Boot, Boot Order, and Startup Delay
  back to factory defaults (Fast Boot → Enable, Boot Order → disk
  first, Startup Delay → 0). The same reset `v6.bat` does internally
  in STEP 3 before handing off to `C.bat`, as a standalone tool.
- **`HP-ProBook-SetBootNext.bat`** / **`HP-ProBook-SetBootNext-PS.bat`**
  — experiments with a one-time UEFI `BootNext` override via
  `bcdedit /bootsequence`, meant to force the next boot back to WinPE
  regardless of what happens to the persistent Boot Order. Not wired
  into any pipeline. Status is genuinely unresolved: one real-hardware
  attempt failed with `bcdedit` unable to open the boot configuration
  data store at all, but that was on a single personal (possibly
  restricted) machine — not yet confirmed whether that's a WinPE-wide
  limitation or specific to that machine. Needs a test on different
  hardware before drawing a real conclusion either way.

## Dependency note

`CheckBootSettings.bat`, `CheckBootSettings-Hardcoded.bat`, and
`ResetBootSettings.bat` all call three `.ps1` helpers
(`HP-ProBook-GetBiosValue.ps1`, `HP-ProBook-CheckBootOrderFirst.ps1`,
`HP-ProBook-FindConfigLine.ps1`) that live one level up, in `HP/` -
their `%~dp0..\` paths assume that layout. `SetBootNext.bat`/`-PS.bat`
are fully self-contained (just `bcdedit`), no such dependency.
