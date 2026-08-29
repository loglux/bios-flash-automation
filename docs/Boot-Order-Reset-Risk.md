# Boot Order reset during BIOS flash — confirmed risk and proposed mitigation

**Status:** confirmed observed, mitigation proposed but **not implemented** — pending decision.

---

## What was observed

Manual reproduction (not via the combined script, but the same underlying tools — BIOS Setup menu + the flash script referred to elsewhere as "A.bat"):

1. Entered BIOS Setup manually, disabled Fast Boot, set Boot Order with USB first.
2. Rebooted — landed on the USB drive successfully (Fast Boot + Boot Order both held through this reboot).
3. Ran the BIOS flash script from WinPE.
4. Machine rebooted again to apply the flash.
5. Result: **Fast Boot stayed disabled** (unchanged), but **Boot Order reset to default** — and since the disk already had a working Windows install, the default order's first entry (`OS Boot Manager`, see the real ProBook 450 G1 example in `HP-ProBook-BIOS-Flash-Full-Script.md`) won, and the machine booted straight into Windows instead of returning to the USB drive.

This isolates the cause cleanly: it is not a Fast Boot / USB-enumeration-timing issue (Fast Boot held). It is specifically **Boot Order resetting as a result of running the flash**, matching the issue reported on HP's own support forums (see Sources in `HP-ProBook-BIOS-Flash-Full-Script.md`) — now confirmed directly rather than just a documented possibility.

## Why this matters for the combined script

The combined script (`scripts/HP-ProBook-Flash-And-Configure.bat`) has two Boot Order checkpoints:
- Step 1 — before the flash
- The final block (`:after_flash_confirmed`) — after the version is confirmed to have changed, i.e. after the script has been **re-launched** from the USB drive

The final-block checkpoint only runs if the machine actually returns to WinPE from the USB drive. In this observed scenario, it doesn't — the machine boots straight into the existing Windows install instead. The script cannot restart itself from within Windows, so its second line of defense never gets a chance to run. This is exactly the risk already flagged in `README.md` under "Known architectural risk" — this document confirms it's real, not hypothetical, at least for machines with an existing bootable OS on disk.

Machines with a blank/unimaged disk are not expected to hit this — with no `OS Boot Manager` entry to boot, the default order should fall through to the next entry (`USB Hard Drive`, second by default on the ProBook 450 G1 example).

Setting Boot Order via `biosconfigutility64 /SetConfig` (what the script does) vs. via the BIOS Setup menu (what was done manually here) makes no difference to this risk — both write to the same underlying NVRAM `BootOrder` variable, and the firmware update process doesn't distinguish how that value was set.

## Proposed mitigation (not yet implemented): one-time `BootNext` override via `bcdedit`

UEFI firmware exposes two distinct boot-related NVRAM variables:
- `BootOrder` — the persistent priority list. This is what resets.
- `BootNext` — a one-time override for the *next* boot only, cleared automatically by the firmware once consumed. Architecturally separate from `BootOrder`.

`bcdedit` (standard Windows tooling, normally included in WinPE) can set `BootNext` via:
```bat
bcdedit /set {fwbootmgr} bootsequence {GUID}
```
The `{GUID}` must be looked up dynamically per machine/drive — via `bcdedit /enum firmware`, searching its output for the entry whose description contains "USB" (the same generic keyword-matching approach already used for `BootOrder` in `:CheckAndFixBootOrder`, not a hardcoded value). This keeps the fix generic across the fleet (any USB drive, any laptop) rather than tying it to one specific machine or drive — the concern raised earlier in the project about avoiding per-machine/per-drive coupling.

Proposed placement: right before `shutdown /r` in Step 4 of the script (after the flash command), as an **additional** safety net alongside the existing `BootOrder` fix — not a replacement for it.

**Open questions before implementing:**
1. Is `bcdedit` actually present in the specific WinPE image used on the deployment USB drive? (Check with `bcdedit /enum firmware` on-site.)
2. Does the firmware's Boot Order reset (during this specific BIOS update) also clear `BootNext`, or does `BootNext` survive it? This is the core uncertainty — no evidence either way yet, since `BootNext` wasn't set during the reproduction above.
3. Exact wording/matching needed in `bcdedit /enum firmware` output to reliably identify the USB entry — not yet drafted or tested.

**Decision:** paused for now — documented here so it's not lost, to revisit once there's bandwidth/opportunity to test on real hardware whether `BootNext` actually survives this specific reset.
