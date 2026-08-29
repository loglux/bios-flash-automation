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

**Update:** the same symptom (lands back on Windows instead of the USB drive) has also been observed after the reboot triggered by script B's own security-settings changes, not just after the BIOS flash (A). So this isn't necessarily specific to the flash tool — the exact trigger is still unconfirmed (possibly a "Boot Order Lock"-style security feature enabled by B's settings; possibly something else). See "Design principle" below for why the script doesn't depend on pinning that down.

## Design principle: resilience to the reset, not elimination of its cause

The exact cause of the reset is unconfirmed and may never be fully diagnosed without extended on-site testing. Rather than chasing it, the script is built to tolerate it regardless of cause:
- All BIOS state changes go through `biosconfigutility64` programmatically — never a manual F9/BIOS Setup keypress race.
- All reboots are triggered via `shutdown /r` from the script — never a manual power-button cycle.
- Every check is followed by a real re-read (`/getvalue`, `/GetConfig`) and a retry loop, never trust that a fix "should have" applied.

The one thing this can't yet guarantee programmatically is the machine actually returning to WinPE after a risky reboot — that's the gap `BootNext` is meant to close (see below), and short of that, the manual "catch F9 at the right moment" step this project exists to eliminate.

## Proposed mitigation: one-time `BootNext` override via `bcdedit`

UEFI exposes two separate boot-related NVRAM variables:
- `BootOrder` — the persistent priority list. This is what resets.
- `BootNext` — a one-time override for the *next* boot only, auto-cleared once consumed. Separate variable from `BootOrder`.

Setting `BootNext` is a fully automated, per-machine lookup — no manual GUID entry anywhere. The script finds the USB entry's GUID at runtime the same way it already finds the USB line in `BootOrder` (by keyword match), then sets `BootNext` to it.

**Confirmed real output format** of `bcdedit /enum firmware` (from Microsoft docs / community examples):
```
Firmware Boot Manager
---------------------
identifier              {fwbootmgr}
displayorder            {bootmgr}
                        {93cee840-f524-11db-af62-aa767141e6b3}
timeout                 2

Windows Boot Manager
---------------------
identifier              {bootmgr}
device                  partition=...
path                    ...
description             Windows Boot Manager

EFI USB Device
---------------------
identifier              {08dec067-564c-11ee-a2b4-644ed7879b0e}
device                  ...
description             EFI USB Device
```
Each entry is its own block; `identifier` appears before `description` within the same block, both flush-left, space-separated. This confirms the parsing approach below — not yet tested against this specific WinPE's actual output, though.

### Code to add

New subroutine, next to `:CheckAndFixBootOrder`:
```bat
:SetBootNextUSB
set "fwdump=%TMPDIR%\firmware.txt"
bcdedit /enum firmware > "%fwdump%" 2>nul

set "found_id="
set "current_id="
for /f "usebackq delims=" %%L in ("%fwdump%") do (
    set "line=%%L"
    echo !line! | findstr /i "^identifier" >nul && (
        for /f "tokens=2" %%I in ("!line!") do set "current_id=%%I"
    )
    echo !line! | findstr /i "^description.*USB" >nul && set "found_id=!current_id!"
)

if not defined found_id (
    call :SetStage "BootNext: USB entry not found in bcdedit list, skipping"
    goto :eof
)

bcdedit /bootsequence !found_id! >nul 2>&1
call :SetStage "BootNext: one-time boot set to !found_id! (USB)"
goto :eof
```

One call site, in `scripts/HP-ProBook-Flash-And-Configure.bat`, Step 4 — right before the reboot, after the flash command:
```bat
call :SetStage "Rebooting in 5 sec to apply flash..."
shutdown /r /t 5
```
becomes:
```bat
call :SetBootNextUSB
call :SetStage "Rebooting in 5 sec to apply flash..."
shutdown /r /t 5
```
That's the only call site — it runs once per flash attempt, right before the risky reboot. No other part of the script changes; the existing `BootOrder` fix (Step 1, final block) stays exactly as-is. This is an addition, not a replacement.

### Still unverified — and one real concern found

1. Whether this WinPE's actual `bcdedit /enum firmware` output matches the format above.
2. Whether `BootNext` actually survives the same reset that wipes `BootOrder` on this specific BIOS update — the core unknown. Only real-hardware testing answers this.
3. **A more fundamental concern, found in the UEFI Specification itself** (2.11, Boot Manager chapter): boot options the firmware synthesizes for removable media via the standard fallback path (`\EFI\BOOT\BOOTx64.EFI` — how a typical bootable WinPE USB drive boots) are explicitly **not persisted and not added to `BootOrder`**: *"These new boot options must not be saved to non volatile storage, and may not be added to BootOrder."* If that's how this USB drive boots, it may never show up as a distinct entry in `bcdedit /enum firmware` at all — not because of a bug in the script's parsing, but because the spec says such entries aren't meant to exist in that list in the first place. This was **not confirmed or ruled out** by testing `bcdedit /enum firmware` on an ordinary Windows PC with a plain (non-bootable) USB drive plugged in — that test didn't show a new entry either, but for a different, expected reason (see the note below) and doesn't settle point 3.

   Practical implication: before trusting this mitigation, the very first thing to check on real hardware is whether `bcdedit /enum firmware`, run from *inside WinPE while booted from the target USB drive*, shows **any** entry corresponding to that drive at all. If it doesn't, `:SetBootNextUSB` will just log "not found" every time — a safe no-op, but not the safety net intended.

**Command syntax note (fixed):** the code originally used `bcdedit /set {fwbootmgr} bootsequence <id>`, which doesn't match Microsoft's documented syntax. The correct command is the top-level `bcdedit /bootsequence <id>` (see [BCDEdit /bootsequence — Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--bootsequence)) — already corrected below.

**Decision:** not yet added to the script — code is ready to paste in above, pending a test run to confirm points 2 and 3.
