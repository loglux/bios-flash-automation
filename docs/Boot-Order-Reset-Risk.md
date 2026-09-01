# Boot Order reset during BIOS flash — confirmed risk and proposed mitigation

**Status:** the Boot Order reset itself is confirmed observed. The `BootNext` mitigation is implemented in the `WithBootNext` variant but real-hardware testing on the actual ProBook shows its current matching logic finds nothing — see "Where this leaves the mitigation" below. Decision on how to proceed is open.

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

Setting `BootNext` is a fully automated, per-machine lookup — no manual GUID entry anywhere.

### Real-hardware test (2026-08-29, ordinary Windows PC, not a ProBook)

Ran `bcdedit /enum firmware` (admin Command Prompt) at three points:
1. **No USB drive attached:** only `Firmware Boot Manager` and `Windows Boot Manager` entries — as expected.
2. **A plain, non-bootable USB drive plugged in:** no change. Expected — the firmware only lists devices with a valid EFI bootloader on them, not just any attached media.
3. **A genuinely UEFI-bootable USB drive (built with AOMEI Partition Assistant) plugged in — without rebooting:** two new entries appeared immediately:
   ```
   Firmware Application (101fffff)
   -------------------------------
   identifier              {d5041891-a3e9-11f1-b549-806e6f6e6963}
   device                  partition=F:
   description             UEFI: SanDisk Extreme Pro 0, Partition 1
   isolatedcontext         Yes

   Firmware Application (101fffff)
   -------------------------------
   identifier              {d5041892-a3e9-11f1-b549-806e6f6e6963}
   device                  partition=G:
   description             UEFI: SanDisk Extreme Pro 0, Partition 2
   isolatedcontext         Yes
   ```

**Two findings, one good, one requiring a fix (already applied below):**

- **Good news:** no reboot was needed — Windows discovers bootable EFI applications on currently-attached media live, at least on this PC's firmware. This weakens (doesn't fully settle — see "Still open" below) the UEFI-spec concern that removable-media boot options might never appear in this list at all.
- **Bug found:** the `description` field does **not** reliably contain the word "USB" — it showed the drive's brand/model instead (`"UEFI: SanDisk Extreme Pro 0, Partition N"`). The original design (`findstr "^description.*USB"`) would have found nothing on this real example and silently skipped every time. Matching on brand/model name was considered and rejected — it would tie the script to whatever USB drive model happens to be in use today, breaking silently if the fleet ever switches drive models (the same per-drive coupling concern raised earlier in this project for other mechanisms).

**Fix applied:** match by the script's **own drive letter** instead — `identifier` still appears before `device` within each block (confirmed again by this real output), and `device partition=X:` gives an exact, assumption-free match: whatever drive the script is currently running from, found via `%~d0` (batch syntax for "the drive letter of the currently executing script").

### Code (already in `scripts/HP-ProBook-Flash-And-Configure.WithBootNext.bat`)

```bat
:SetBootNextUSB
set "mydrive=%~d0"
set "fwdump=%TMPDIR%\firmware.txt"
bcdedit /enum firmware > "%fwdump%" 2>nul

set "found_id="
set "current_id="
for /f "usebackq delims=" %%L in ("%fwdump%") do (
    set "line=%%L"
    echo !line! | findstr /i "^identifier" >nul && (
        for /f "tokens=2" %%I in ("!line!") do set "current_id=%%I"
    )
    echo !line! | findstr /i /c:"partition=%mydrive%" >nul && set "found_id=!current_id!"
)

if not defined found_id (
    call :SetStage "BootNext: no firmware entry found for drive %mydrive%, skipping"
    goto :eof
)

bcdedit /bootsequence !found_id! >nul 2>&1
call :SetStage "BootNext: one-time boot set to !found_id! (drive %mydrive%)"
goto :eof
```

Call site — Step 4, right before the reboot, after the flash command:
```bat
call :SetBootNextUSB
call :SetStage "Rebooting in 5 sec to apply flash..."
shutdown /r /t 5
```
That's the only call site — it runs once per flash attempt, right before the risky reboot. No other part of the script changes; the existing `BootOrder` fix (Step 1, final block) stays exactly as-is. This is an addition, not a replacement. Only the `WithBootNext` script variant has this; the base script doesn't.

### Real-hardware test on the actual ProBook (2026-09-01, WinPE, `X:\T1700Setup>`)

Ran `bcdedit /enum firmware` from inside the real deployment WinPE, booted from the actual USB drive (a Kingston DataTraveler — confirmed mounted as `D:`; `X:` is WinPE's own RAM disk, a separate thing). Relevant part of the real output:
```
Firmware Boot Manager
----------------------
identifier              {fwbootmgr}
displayorder            {bootmgr}
                        {bba13431-292a-11f1-9c38-9875ebeb91fd}
                        {bba1342e-292a-11f1-9c38-9875ebeb91fd}
timeout                 0

Windows Boot Manager
---------------------
identifier              {bootmgr}
...

Firmware Application (101fffff)
--------------------------------
identifier              {bba1342e-292a-11f1-9c38-9875ebeb91fd}
description             IPV4 Network - Realtek PCIe GBE Family Controller

Firmware Application (101fffff)
--------------------------------
identifier              {bba13431-292a-11f1-9c38-9875ebeb91fd}
description             Kingston DataTraveler 3.0 2CFDA15C4C131A51C90E009F
```

**This settles "still open" point 1 from the earlier test, definitively and positively: yes, on this exact ProBook firmware, the boot USB gets its own `Firmware Application` entry in `bcdedit /enum firmware`.** That's the good news.

**But it breaks both matching strategies tried so far, confirmed by directly checking with the user that nothing was cropped from the output:**
- No `device` field at all in this entry — just `identifier` and `description`, nothing else. Unlike the earlier SanDisk test on an ordinary PC (which had `device partition=F:`), there's nothing here for the `%~d0`/drive-letter match to compare against.
- No "USB" in `description` either — same finding as the SanDisk test, now confirmed a second time on different, actually-target hardware. It shows the drive's own brand/model/serial instead (`"Kingston DataTraveler 3.0 2CFDA15C4C131A51C90E009F"`), which is different for every physical flash drive in the fleet and can't be hardcoded.

So as currently written, `:SetBootNextUSB` finds nothing on the real target hardware and always takes the "not found, skipping" branch — a safe no-op, but not the safety net intended.

**A candidate third approach, not yet implemented or tested:** match by *elimination* instead of by a positive USB signal. On this machine, the only other `Firmware Application` entry is the network controller, whose description reliably contains generic, vendor-agnostic words (`Network`, `IPV4`/`IPV6`, `Ethernet`, `PXE`) — far more standardized across NIC vendors than USB drive branding is across USB vendors. The idea: enumerate all `Firmware Application` entries, exclude ones matching a network/PXE keyword pattern, and treat whatever's left as the boot drive. Risk: this is still a heuristic, not a guaranteed identifier — a machine with some other non-network, non-USB firmware application entry (e.g. a card reader, Thunderbolt, TPM) would misidentify or find multiple candidates. Not drafted or tested.

### Where this leaves the mitigation

Two real-hardware tests (an ordinary PC, and now the actual ProBook) have each broken the matching approach in a different way. The underlying mechanism (`BootNext` via `bcdedit`) is confirmed to exist and be reachable on the real target hardware, but reliably identifying *which* firmware entry is the boot USB — without any device path or USB keyword to go on — has turned out to be genuinely hard, not just an unverified detail.

**Worth deciding explicitly:** keep pushing on the elimination-based heuristic (real but imperfect), or treat this real result as the point where `BootNext` gets shelved and the project relies solely on the already-working `BootOrder`-via-BCU mechanism (Step 1 + final block), accepting the residual architectural risk as documented in `README.md` rather than adding an increasingly fragile workaround on top of it.

**Decision:** implemented in the `WithBootNext` script variant with the drive-letter matching approach, which the real-hardware test above shows does not find anything on the actual ProBook. Not yet adopted as the default, and the path forward (elimination heuristic vs. shelving the idea) is an open decision, not yet made.
