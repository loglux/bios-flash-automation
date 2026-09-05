# PowerState

**Confirmed directly against sources, not inferred**: Dell's own BIOS
flash tool shows the literal on-screen message *"The battery must be
charged above 10% before the system bios can be flashed"* even with
the AC adapter connected — confirmed via a [Dell Community
thread quoting that exact
text](https://www.dell.com/community/Laptops-General-Read-Only/the-battery-must-be-charged-above-10-before-the-system-bios-can/td-p/4514501),
independently corroborated on [MajorGeeks
forums](https://forums.majorgeeks.com/threads/battery-must-be-charged-above-10-to-flash-bios.230260/).
A related, separate message — *"The AC adapter and battery must be
plugged in before the system bios can be flashed"* — is confirmed via
[another Dell Community
thread](https://www.dell.com/community/Laptops-General-Read-Only/quot-The-AC-adapter-and-battery-must-be-plugged-in-before-the/td-p/4080604)
quoting that exact text too. HP shows the analogous behavior — an [HP
Support Community thread titled "Battery won't charge. Can't update
bios without 50%
charge"](https://h30434.www3.hp.com/t5/Notebook-Hardware-and-Upgrade-Questions/Battery-won-t-charge-Can-t-update-bios-without-50-charge/td-p/9609175)
— though the exact percentage clearly varies by model/BIOS generation
(other reports cite >10% on some HP systems). This is specifically
reported as happening *while the AC adapter is connected* — Dell users
describe hitting the 10% message "when trying to update the BIOS while
the AC adapter is connected but the battery isn't charging," i.e. a
genuine AC-present-but-still-blocked case, not just a no-AC scenario;
the two distinct Dell messages (missing-AC vs. low-charge) further
confirm these are two separate checks, not one. **What none of these
sources document**: whether the tool auto-retries/waits once the
condition is met, or just aborts and needs a manual re-run — no report
found describes it waiting on its own, which is the working assumption
here, and part of why doing this check ourselves *before* invoking the
vendor's flash tool is worth the effort rather than relying on the
tool to sort it out.

Vendor-agnostic logic shared between the `HP/` and `Dell/` pipelines,
starting with a pre-flash power/battery safety check — the actual
BIOS flashing tools on both vendors already enforce something like
this internally, so this is a way to catch it early and clearly,
rather than let the flash step fail partway through with a less
obvious error.

Status: drafts, none run on real hardware yet.
`PowerState-Check.ps1` / `.bat` just report the current AC/battery
state. `PowerState-WaitForSafeCharge.bat` is the actual gate — waits
and rechecks while on AC below threshold, fails immediately with no
AC, skips the check entirely with no battery (a desktop).

---

## Why this check matters (researched, not assumed)

Both HP and Dell's own BIOS update tools already refuse to flash under
certain power conditions — this isn't just caution on our part:

- **HP**: requires the AC adapter connected, *and* a minimum battery
  charge — commonly cited as 50%, though some HP systems/BIOS versions
  accept 25% even while on AC. There's a real HP Support Community
  thread titled "Battery won't charge. Can't update bios without 50%
  charge" — a battery that physically won't hold charge can block a
  flash entirely, worth knowing about before assuming a wait-loop will
  always eventually succeed.
- **Dell**: requires the AC adapter connected, *and* at least 10%
  battery charge.
- **Stated reason (both vendors)**: the battery is a short-term backup
  in case the AC connection is bumped/loosened mid-flash — losing
  power during the flash can brick the board entirely.

Exact HP ProBook 4 G1ah14 thresholds aren't confirmed for this
specific model/BIOS — the 25%/50% figures are the general range found
across HP's own community/support content, not something tested on
our fleet's hardware yet.

## How to read the power state

Two different WMI sources, queried together since neither alone gives
the full picture:

- `Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus` —
  gives `PowerOnline`, `Charging`, `Discharging` as plain booleans, no
  interpretation needed. This is the most direct answer to "is the AC
  adapter actually delivering power right now."
- `Get-CimInstance -ClassName Win32_Battery` (root\cimv2) — gives
  `EstimatedChargeRemaining` (percentage) and a `BatteryStatus` code
  (`1`=Other, `3`=Fully Charged, `4`=Low, `5`=Critical, `6`-`9`=various
  Charging states, `10`=Undefined, `11`=Partially Charged) — useful for
  the percentage, but its status code alone doesn't unambiguously say
  "AC connected," which is why `BatteryStatus.PowerOnline` is used for
  that instead.
- **No battery at all** (a desktop — the fleet already includes at
  least one, a Dell Precision T1700) — both queries come back empty.
  Must be treated as "always safe, AC-only system," not as an error.

`PowerState-Check.ps1` queries both and prints a simple
`Key|Value` report; `PowerState-Check.bat` parses that into
environment variables and echoes them, same `tokens=1,* delims=|`
convention already used elsewhere in this project (e.g. the HP boot
order helpers).

## Fail immediately, or wait for the battery to charge?

Implemented as: **wait and recheck, but only while AC is connected**
(`PowerState-WaitForSafeCharge.bat`):

- **AC connected, charge below threshold** → waits and rechecks on a
  delay (default every 5 minutes), since the technician has
  presumably already plugged it in and the battery should be
  charging. Capped at a max number of attempts (default 12, i.e. ~1
  hour) — see the HP "battery won't charge" case above; a dead battery
  would otherwise wait forever. After the cap, stops and reports FAIL
  rather than looping indefinitely.
- **AC not connected at all** → stops immediately with a clear "plug
  in the AC adapter" message, no wait loop — charge only goes down
  without AC.
- **No battery (desktop)** → skips the check entirely, reports OK.

Threshold, max attempts, and delay are all caller-supplied arguments
(`call PowerState-WaitForSafeCharge.bat <ThresholdPercent> [MaxAttempts] [DelaySeconds]`)
rather than hardcoded, since HP (~25-50%) and Dell (10%) need
different thresholds and neither is confirmed for our specific
fleet hardware yet.

Not yet run on real hardware, laptop or desktop — `PowerState-Check.ps1`/`.bat`
are still just the read-only diagnostic underneath it; this is the
next thing to test before wiring the wait script into the pipelines
ahead of the actual flash step (`A.bat` on HP, the equivalent step
once it exists on Dell).

## Sources

- [Battery won't charge. Can't update bios without 50% charge (HP Support Community)](https://h30434.www3.hp.com/t5/Notebook-Hardware-and-Upgrade-Questions/Battery-won-t-charge-Can-t-update-bios-without-50-charge/td-p/9609175)
- [Minimum Battery Charge Required Blocks BIOS Upgrade (Ed Tittel)](https://www.edtittel.com/blog/minimum-battery-charge-required-blocks-bios-upgrade.html)
- ["The battery must be charged above 10% before the system bios can be flashed" (Dell Community)](https://www.dell.com/community/Laptops-General-Read-Only/the-battery-must-be-charged-above-10-before-the-system-bios-can/td-p/4514501)
- [Battery must be charged above 10% to flash BIOS (MajorGeeks forums, corroborating)](https://forums.majorgeeks.com/threads/battery-must-be-charged-above-10-to-flash-bios.230260/)
- ["The AC adapter and battery must be plugged in before the system bios can be flashed" (Dell Community)](https://www.dell.com/community/Laptops-General-Read-Only/quot-The-AC-adapter-and-battery-must-be-plugged-in-before-the/td-p/4080604)
- [How to Force Update Your Laptop BIOS Without AC Power (Dell)](https://www.dell.com/support/kbdoc/en-us/000134938/forcing-a-bios-update-without-the-ac-adapter-attached-on-a-dell-laptop)
- [Win32_Battery (powershell.one)](https://powershell.one/wmi/root/cimv2/win32_battery)
- [BATTERY_WMI_STATUS (Microsoft Learn)](https://learn.microsoft.com/en-us/windows/win32/api/batclass/ns-batclass-battery_wmi_status)
