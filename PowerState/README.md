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
- **HP** shows the same pattern: AC plus a minimum charge, and for our
  actual fleet tool the exact threshold is now confirmed directly, not
  just from web reports — extracting UTF-16 strings (`strings -e l`)
  from the real `HpFirmwareUpdRec64.exe` binary (the exe `A.bat`
  actually runs) turned up the literal embedded message: *"Connecting
  to AC power is required while updating firmware. Connect the AC
  adapter or try the flash again when battery is at least 50%
  charged."* — plus separate status strings `"System is on battery
  power."` and `"System is on battery power, less than 50%."`. This
  also reads as looser than a strict AND: the "connect AC **or** try
  again once charged ≥50%" phrasing, and the two distinct status
  strings (plain "on battery" vs. "on battery, less than 50%"),
  suggest HP's tool may accept a battery-only flash once charge is
  high enough, with AC being the recommended-but-not-strictly-required
  path rather than an unconditional gate like Dell's. That's a reading
  of the string wording, not an observed conditional branch — not
  100% certain without an actual no-AC/high-charge test. (Background,
  before this was confirmed directly: [HP Support
  Community](https://h30434.www3.hp.com/t5/Notebook-Hardware-and-Upgrade-Questions/Battery-won-t-charge-Can-t-update-bios-without-50-charge/td-p/9609175),
  [Ed Tittel](https://www.edtittel.com/blog/minimum-battery-charge-required-blocks-bios-upgrade.html).)
- **[Official HP whitepaper](https://h10032.www1.hp.com/ctg/Manual/c06696094.pdf)**
  ("HP Commercial Systems Automatic BIOS Update Through Windows Update
  Whitepaper" — about the WU/capsule delivery path, a different
  mechanism than `HpFirmwareUpdRec64.exe`, but the same underlying UEFI
  Capsule apply step) has an FAQ entry quoted here verbatim, not
  paraphrased:

  > **What happens if my system is not plugged into AC when WU starts
  > updating the BIOS?**
  > Before the update starts, if AC-power is not plugged in **and** the
  > remaining battery is below 50%, a message (prompting to charge the
  > battery or connect to AC-power) will be displayed for up to 30
  > seconds. If an AC source is still not plugged in, the update will
  > fail.

  The document only poses the question for the no-AC case — it has no
  separate, explicitly-stated answer for "what if AC **is** plugged
  in." The AND condition it does state (fails only when *both*
  no-AC *and* charge <50%) logically implies charge doesn't matter
  once AC is connected, but that's a deduction from this one stated
  condition, not an independently confirmed sentence for the
  AC-connected case. Consistent with the `HpFirmwareUpdRec64.exe`
  string reading above, but still not a direct confirmation — only a
  real test (AC connected, battery critically low/absent) would settle
  it.
- Searched `cctk.exe` and `BiosConfigUtility64.exe` the same way (for
  "must be charged" / "must be plugged" / "flash") — neither contains
  Dell's "battery must be charged above 10%" message or anything like
  it. Consistent with both being settings tools only: that message
  must live in whatever executable actually performs a Dell flash,
  which hasn't been located yet.
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
    Open question given the HP string finding above: HP's own tool may
    permit a battery-only flash above 50%, which this script currently
    doesn't allow — a deliberately stricter policy for unattended fleet
    use, or worth loosening? Not decided yet.
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
- [HP Commercial Systems Automatic BIOS Update Through Windows Update Whitepaper (official HP PDF)](https://h10032.www1.hp.com/ctg/Manual/c06696094.pdf)
- [Win32_Battery (powershell.one)](https://powershell.one/wmi/root/cimv2/win32_battery)
- [BATTERY_WMI_STATUS (Microsoft Learn)](https://learn.microsoft.com/en-us/windows/win32/api/batclass/ns-batclass-battery_wmi_status)
