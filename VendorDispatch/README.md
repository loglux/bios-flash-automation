# VendorDispatch

The single entry point meant to live at the root of the USB flash
drive: detects whether the machine is HP or Dell, then hands off to
that vendor's own pipeline — instead of a technician having to pick
the right script manually per machine.

Status: draft, not yet run on real hardware. This is the idea
originally parked in `Dell/README.md` ("Vendor dispatcher (future —
not built yet)"), now actually written.

---

## How it works

`VendorDispatch.bat`:

1. Reads `Manufacturer` via `wmic computersystem get manufacturer`,
   same call already confirmed working on real hardware inside
   `Dell/Dell-SetBootSettings.bat`.
2. Matches it with PowerShell `-match` (not `findstr` — confirmed
   missing on at least one real WinPE build, see `Dell/README.md`):
   `HP|Hewlett-Packard` for HP, `Dell` for Dell.
3. Calls the matching pipeline and exits with its exit code:
   - HP → `HP/HP-ProBook-BiosCheck-v6.bat`
   - Dell → `Dell/Dell-SetBootSettings.bat`
   - Neither matches → errors out rather than guessing.

## Important asymmetry between the two branches

The HP branch launches a mature, extensively tested pipeline (v6 —
version check → flash → security settings → boot-order reset →
imaging handoff) — though its version-check step now reads
Manufacturer/Model/BiosVersion via `SystemIdentity/`. That module's
`Get-CimInstance` mechanism, and its wiring into v6 specifically, are
now both confirmed on real hardware - run on a Dell laptop, v6
correctly detected the wrong vendor via this wiring and halted instead
of proceeding (see `SystemIdentity/README.md`). The Dell branch
currently launches only
`Dell-SetBootSettings.bat`, which is *just* the vendor/model
detection + boot-settings + backup piece — there's no Dell equivalent
yet of the BIOS-version check, the actual flash step, or the
handoff to an imaging step. Running this dispatcher on a real Dell
machine right now will only exercise that limited scope, not a full
flash-and-image pipeline. Update `DELL_PIPELINE` in
`VendorDispatch.bat` once a fuller Dell pipeline exists.

## Not yet done

- Not run on real hardware at all.
- Doesn't call `PowerState/` (the AC/battery safety gate) — arguably
  belongs right here, before handing off to either pipeline, once
  that gate itself has been tested on hardware.
- Dell branch points at a partial pipeline, as noted above.
