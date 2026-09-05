# PowerState

Vendor-agnostic logic shared between the `HP/` and `Dell/` pipelines,
starting with a pre-flash power/battery safety check — the actual
BIOS flashing tools on both vendors already enforce something like
this internally, so this is a way to catch it early and clearly,
rather than let the flash step fail partway through with a less
obvious error.

Status: diagnostic only. `PowerState-Check.ps1` / `.bat` report the
current AC/battery state — no pass/fail gating logic yet, and neither
has been run on real hardware.

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

## Open question: fail immediately, or wait for the battery to charge?

Leaning toward: **wait and recheck, but only while AC is connected.**

- **AC connected, charge below threshold** → this is the case worth
  waiting on: loop with a delay (e.g. re-check every few minutes),
  since the technician has presumably already plugged it in and the
  battery should be charging. Needs a cap on total wait time/attempts
  though — see the HP "battery won't charge" case above; a dead
  battery would otherwise wait forever. After the cap, stop and flag
  it for a human rather than loop indefinitely.
- **AC not connected at all** → waiting is pointless, charge only goes
  down. Stop immediately with a clear "plug in the AC adapter" message
  instead of entering a wait loop.
- **No battery (desktop)** → skip the check entirely.

Not yet implemented — `PowerState-Check.ps1`/`.bat` are diagnostic
only for now, to see real output on real hardware (laptop and desktop
both) before deciding on exact thresholds and wiring this into the
pipelines ahead of the actual flash step (`A.bat` on HP, the
equivalent step once it exists on Dell).

## Sources

- [Battery won't charge. Can't update bios without 50% charge (HP Support Community)](https://h30434.www3.hp.com/t5/Notebook-Hardware-and-Upgrade-Questions/Battery-won-t-charge-Can-t-update-bios-without-50-charge/td-p/9609175)
- [Minimum Battery Charge Required Blocks BIOS Upgrade (Ed Tittel)](https://www.edtittel.com/blog/minimum-battery-charge-required-blocks-bios-upgrade.html)
- ["The AC adapter and battery must be plugged in before the system bios can be flashed" (Dell Community)](https://www.dell.com/community/Laptops-General-Read-Only/quot-The-AC-adapter-and-battery-must-be-plugged-in-before-the/td-p/4080604)
- [How to Force Update Your Laptop BIOS Without AC Power (Dell)](https://www.dell.com/support/kbdoc/en-us/000134938/forcing-a-bios-update-without-the-ac-adapter-attached-on-a-dell-laptop)
- [Win32_Battery (powershell.one)](https://powershell.one/wmi/root/cimv2/win32_battery)
- [BATTERY_WMI_STATUS (Microsoft Learn)](https://learn.microsoft.com/en-us/windows/win32/api/batclass/ns-batclass-battery_wmi_status)
