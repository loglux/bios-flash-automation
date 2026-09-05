# PowerState

Vendor-agnostic logic shared between `HP/` and `Dell/`: a pre-flash
power/battery safety check, so a bad power state gets caught early
with a clear message instead of the flash step failing partway
through.

Status: drafts, none run on real hardware yet.

---

## Why this matters

Both HP's and Dell's own BIOS flash tools already refuse to run under
certain power conditions — confirmed against the tools' own on-screen
error text quoted in vendor community threads, not assumed:

- **Dell** shows two distinct messages, confirming AC-presence and
  battery-charge are checked separately, not as one combined
  condition: *"The AC adapter and battery must be plugged in before
  the system bios can be flashed"* when AC is missing ([Dell
  Community](https://www.dell.com/community/Laptops-General-Read-Only/quot-The-AC-adapter-and-battery-must-be-plugged-in-before-the/td-p/4080604)),
  and separately *"The battery must be charged above 10% before the
  system bios can be flashed"* — reported specifically *while AC is
  already connected* ([Dell
  Community](https://www.dell.com/community/Laptops-General-Read-Only/the-battery-must-be-charged-above-10-before-the-system-bios-can/td-p/4514501),
  corroborated on
  [MajorGeeks](https://forums.majorgeeks.com/threads/battery-must-be-charged-above-10-to-flash-bios.230260/)).
- **HP** shows the same pattern: AC required plus a minimum charge,
  commonly cited as 50%, though some HP systems/BIOS versions accept
  25% even on AC ([HP Support
  Community](https://h30434.www3.hp.com/t5/Notebook-Hardware-and-Upgrade-Questions/Battery-won-t-charge-Can-t-update-bios-without-50-charge/td-p/9609175),
  [background](https://www.edtittel.com/blog/minimum-battery-charge-required-blocks-bios-upgrade.html)).
  Exact threshold for our ProBook 4 G1ah14 fleet isn't confirmed —
  25%/50% is the general range found in HP's own community content,
  not something tested on our hardware.
- **Stated reason, both vendors**: the battery is a short-term backup
  in case the AC connection gets bumped or loosened mid-flash — losing
  power during the flash can brick the board.
- **What none of these sources document**: whether the tool
  auto-retries/waits once the condition is met, or just aborts and
  needs a manual re-run. No report describes it waiting on its own —
  the working assumption here, and the reason for doing this check
  ourselves *before* invoking the vendor's flash tool rather than
  relying on it to sort things out.
- A real failure mode worth knowing about: a battery that physically
  won't hold charge can block a flash indefinitely (HP Support
  Community thread title: "Battery won't charge. Can't update bios
  without 50% charge") — a wait-loop needs a cap, not an assumption
  that charge will always eventually rise.

## How the check reads power state

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

## The scripts

- **`PowerState-Check.ps1` / `.bat`** — read-only diagnostic. Queries
  both WMI sources above and prints a `Key|Value` report (`ACOnline`,
  `Charging`, `Discharging`, `ChargePercent`, `BatteryStatusCode`, or
  just `NoBattery` on a desktop) — same `tokens=1,* delims=|`
  convention already used elsewhere in this project (e.g. the HP boot
  order helpers).
- **`PowerState-WaitForSafeCharge.bat`** — the actual gate, built on
  top of the diagnostic above:
  - AC connected, charge below threshold → waits and rechecks on a
    delay (default every 5 minutes), capped at a max number of
    attempts (default 12, i.e. ~1 hour) rather than looping forever.
  - AC not connected at all → stops immediately with a clear "plug in
    the AC adapter" message — no point waiting, charge only goes down.
  - No battery (desktop) → skips the check entirely, reports OK.
  - Threshold/max attempts/delay are caller-supplied arguments, not
    hardcoded, since HP and Dell need different thresholds and neither
    is confirmed for this fleet yet:
    `call PowerState-WaitForSafeCharge.bat <ThresholdPercent> [MaxAttempts] [DelaySeconds]`

Not yet run on real hardware (laptop or desktop), and not yet wired
into either pipeline ahead of the actual flash step (`A.bat` on HP,
the equivalent step once it exists on Dell).

## Sources

- [Battery won't charge. Can't update bios without 50% charge (HP Support Community)](https://h30434.www3.hp.com/t5/Notebook-Hardware-and-Upgrade-Questions/Battery-won-t-charge-Can-t-update-bios-without-50-charge/td-p/9609175)
- [Minimum Battery Charge Required Blocks BIOS Upgrade (Ed Tittel)](https://www.edtittel.com/blog/minimum-battery-charge-required-blocks-bios-upgrade.html)
- ["The battery must be charged above 10% before the system bios can be flashed" (Dell Community)](https://www.dell.com/community/Laptops-General-Read-Only/the-battery-must-be-charged-above-10-before-the-system-bios-can/td-p/4514501)
- [Battery must be charged above 10% to flash BIOS (MajorGeeks forums, corroborating)](https://forums.majorgeeks.com/threads/battery-must-be-charged-above-10-to-flash-bios.230260/)
- ["The AC adapter and battery must be plugged in before the system bios can be flashed" (Dell Community)](https://www.dell.com/community/Laptops-General-Read-Only/quot-The-AC-adapter-and-battery-must-be-plugged-in-before-the/td-p/4080604)
- [How to Force Update Your Laptop BIOS Without AC Power (Dell)](https://www.dell.com/support/kbdoc/en-us/000134938/forcing-a-bios-update-without-the-ac-adapter-attached-on-a-dell-laptop)
- [Win32_Battery (powershell.one)](https://powershell.one/wmi/root/cimv2/win32_battery)
- [BATTERY_WMI_STATUS (Microsoft Learn)](https://learn.microsoft.com/en-us/windows/win32/api/batclass/ns-batclass-battery_wmi_status)
