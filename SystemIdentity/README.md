# SystemIdentity

Vendor-agnostic logic shared between `VendorDispatch/`, `HP/`, and
`Dell/`: reads the brand/model-agnostic facts every pipeline needs
before it can pick a procedure — manufacturer, model, serial/service
tag, and current BIOS version — in one place, instead of each caller
re-implementing its own WMI/CIM calls.

Status: draft, not run on real hardware yet, not wired into any
pipeline.

---

## Why this matters

Right now this detection is scattered and duplicated:

- `VendorDispatch/VendorDispatch.bat` reads `Manufacturer` on its own
  (`wmic computersystem get manufacturer`).
- `Dell/Dell-SetBootSettings.bat` STEP 0 reads `Manufacturer`, `Model`,
  and `SerialNumber` separately, each its own `wmic ... get <field>`
  call.
- Every HP `HP-ProBook-BiosCheck-v*.bat` (v1 through v6) reads
  `SMBIOSBIOSVersion` on its own, the same way.

None of this is wrong — each script works standalone, confirmed on
real hardware in `Dell-SetBootSettings.bat`'s case. But WinPE has no
memory across reboots (it's a RAM-loaded OS), so this detection isn't
a one-time cost — it reruns from scratch every fresh WinPE boot in
the pipeline. That makes it worth consolidating rather than treating
each `wmic.exe` call as free:

- `wmic` can pull multiple fields from the *same* WMI class in one
  call, but not across classes. `Manufacturer` + `Model` are both on
  `Win32_ComputerSystem`; `SerialNumber` + `SMBIOSBIOSVersion` are
  both on `Win32_BIOS`. So the real floor is **two** `wmic` calls, not
  four separate one-field calls:
  ```
  wmic computersystem get manufacturer,model /format:list
  wmic bios get serialnumber,smbiosbiosversion /format:list
  ```
  The BIOS version comes along for free with the serial number call,
  since they're the same class.
- The bigger win is on the PowerShell side: `wmic.exe` and
  `powershell.exe` both pay a real, non-trivial process/COM startup
  cost each time they're invoked — that's the dominant cost here, not
  the query itself. One `powershell.exe` process running two
  `Get-CimInstance` calls back to back (see `SystemIdentity-Check.ps1`)
  replaces two-to-four separate process starts with one.
- None of this is a big number in absolute terms (low single-digit
  seconds either way), but it's not zero either, and it's the same
  kind of cheap, deterministic, stateless check every time — safe to
  rerun on every WinPE boot rather than trying to cache the result
  (caching would be riskier: the same USB drive serves many different
  physical machines across the fleet, so any cached identity would go
  stale the moment the drive moves to a different machine).

## The scripts

- **`SystemIdentity-Check.ps1`** — reads both classes, prints a
  `Key|Value` report (`Manufacturer`, `Model`, `SerialNumber`,
  `BiosVersion`) — same `tokens=1,* delims=|` convention already used
  by `PowerState-Check.ps1`.
- **`SystemIdentity-Check.bat`** — wraps the `.ps1` the same way
  `PowerState-Check.bat` wraps its own: one `for /f` loop, sets each
  key as a batch variable.

## Example output

The two consolidated `wmic` calls, `/format:list` output (real
Manufacturer/Model/BiosVersion from a Dell Latitude 5530 tested
earlier in this project; `SerialNumber` replaced with a placeholder —
a Service Tag identifies one specific physical machine, and the real
value was committed here by mistake, see note below):

```
C:\> wmic computersystem get manufacturer,model /format:list

Manufacturer=Dell Inc.
Model=Latitude 5530


C:\> wmic bios get serialnumber,smbiosbiosversion /format:list

SerialNumber=XXXXXXX
SMBIOSBIOSVersion=1.14.0

```

`SystemIdentity-Check.ps1` run directly (one process, both classes):

```
C:\> powershell -NoProfile -ExecutionPolicy Bypass -File SystemIdentity-Check.ps1
Manufacturer|Dell Inc.
Model|Latitude 5530
SerialNumber|XXXXXXX
BiosVersion|1.14.0
```

`SystemIdentity-Check.bat` run — same data, parsed into readable
labels by the `for /f "tokens=1,* delims=|"` loop:

```
C:\> SystemIdentity-Check.bat
Manufacturer: Dell Inc.
Model: Latitude 5530
Serial Number: XXXXXXX
BIOS Version: 1.14.0
```

## Privacy note

`SerialNumber` above is a placeholder, not a real value. The actual
Dell Service Tag of the test machine (`Latitude 5530`) was committed
here by mistake, then again earlier in `Dell/README.md` — both fixed
in the working tree, but the real value is still recoverable from
older commits in this repo's history until that history is rewritten
and force-pushed (a separate, deliberate step, not done automatically
as part of this fix).

## Not yet done

- Not run on real hardware.
- Not wired into `VendorDispatch/VendorDispatch.bat` or
  `Dell/Dell-SetBootSettings.bat` yet — both still have their own
  inline, single-field detection; this is a candidate replacement, not
  a completed migration.
- HP's `BiosCheck-v6.bat` still reads `SMBIOSBIOSVersion` itself, the
  same way it always has — unclear yet whether it's worth switching
  that mature, already-tested pipeline over to this instead of leaving
  it alone.
