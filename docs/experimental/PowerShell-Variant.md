# PowerShell script variant — status, pros/cons, and how to check/add it

**Status:** `powershell` is **confirmed present** in this project's actual WinPE (verified on-site, 2026-09-01) — the availability concern below is resolved. `scripts/experimental/HP-ProBook-Flash-And-Configure.ps1` is still **not adopted**, though — it's a parallel PowerShell port of the batch script, written to compare approaches, and hasn't received anywhere near the real-world scrutiny the batch script has (multiple bugs found and fixed through this project's testing — the `-r` flag, the Boot Order setting name, etc.). The batch script remains the primary, relied-upon version. A switch is now a legitimate option rather than blocked by an unknown, but it would need its own round of validation first.

---

## Why this wasn't a given: PowerShell in WinPE is optional

Unlike `cmd.exe`, `biosconfigutility64.exe`, and `bcdedit` (all confirmed present in this project's WinPE), PowerShell is **not included in a base WinPE image by default**. It has to be deliberately added when the image is built, as a set of optional components layered on top of the base WinPE. If whoever built this specific WinPE hadn't added them, `powershell.exe` simply wouldn't exist — same failure mode as the `wmic` removal discussed elsewhere in this project's history (see CONTEXT.md). This project's WinPE does have it, confirmed by testing.

## How to check if it's there

Already confirmed present on this project's WinPE, but kept here for reference (e.g. re-checking after a WinPE image rebuild, or on a different fleet). From the WinPE command prompt:
```
powershell
```
- **Present:** drops into an interactive PowerShell session (prompt changes to something like `PS X:\T1700Setup>`). Type `exit` to return to cmd.
- **Absent:** immediate error, same shape as the `wmic` failure:
  ```
  'powershell' is not recognized as an internal or external command,
  operable program or batch file.
  ```

To check non-interactively from inside a batch script:
```bat
powershell -command "Write-Output OK" >nul 2>&1
if !errorlevel! neq 0 (
    echo PowerShell not available
) else (
    echo PowerShell available
)
```

## How to add it to an existing WinPE image (not needed here — kept for reference)

Done via **DISM**, on a separate Windows machine with the **Windows ADK + WinPE Add-on** installed (the same tooling used to originally build this image) — not from within WinPE itself.

1. Mount the boot image from the USB drive:
   ```
   Dism /Mount-Image /ImageFile:D:\Sources\boot.wim /Index:1 /MountDir:C:\mount
   ```
2. Add the required optional components, **in this dependency order** — HP's own "Notes on WinPE usage" guide (developers.hp.com) documents this exact list, more complete than earlier guesses in this doc's history (paths are typically under `...\Windows Preinstallation Environment\amd64\WinPE_OCs\` in the ADK install; each `.cab` has a matching `en-us\..._en-us.cab` language pack to add right after it):
   ```
   Dism /Image:C:\mount /Add-Package /PackagePath:"...\WinPE-WMI.cab"
   Dism /Image:C:\mount /Add-Package /PackagePath:"...\WinPE-NetFX.cab"
   Dism /Image:C:\mount /Add-Package /PackagePath:"...\WinPE-Scripting.cab"
   Dism /Image:C:\mount /Add-Package /PackagePath:"...\WinPE-PowerShell.cab"
   Dism /Image:C:\mount /Add-Package /PackagePath:"...\WinPE-StorageWMI.cab"
   Dism /Image:C:\mount /Add-Package /PackagePath:"...\WinPE-DismCmdlets.cab"
   Dism /Image:C:\mount /Add-Package /PackagePath:"...\WinPE-SecureBootCmdlets.cab"
   ```
3. Commit and unmount:
   ```
   Dism /Unmount-Image /MountDir:C:\mount /Commit
   ```
4. Copy the updated `boot.wim` back to the deployment USB drive, replacing the original.

**Caveats:** the CAB architecture (x86/amd64/arm64) must match the existing image exactly; the dependency order above must be respected or `Add-Package` fails; this changes the boot image for the *entire* fleet's USB drives, not just one — treat it as an infrastructure change, not a quick script edit.

## A bigger opportunity: HP's own official PowerShell module (HP CMSL)

Found in HP's own "Notes on WinPE usage" documentation (developers.hp.com), which explicitly covers using it from WinPE: **HP Client Management Script Library (HP CMSL)** is an official HP PowerShell module with purpose-built cmdlets for exactly what this script does by hand today:
- `Set-HPBIOSSettingValue` / `Set-HPBIOSSettingValuesFromFile` — direct replacements for the script's `biosconfigutility64 /setvalue` and `/SetConfig` calls (and their manual CDATA/text parsing).
- `Update-HPFirmware` — HP's official cmdlet for flashing the BIOS, a PowerShell-native alternative to calling `HPBIOSUPDREC64.exe` directly. HP's own docs flag one gotcha for WinPE specifically: *"When flashing the BIOS from WinPE, specify the `-BitLocker ignore` flag, since WinPE does not have the BitLocker-related checks, and our library will fail when trying to check if BitLocker is enabled."*
- `Set-HPBIOSSetupPassword`, `Write-HPFirmwarePasswordFile` — directly relevant to this project's still-unresolved question of automating the BIOS Setup password that script B sets (see CONTEXT.md).
- `Get-HPFirmwareAuditLog` — could help understand exactly what a BIOS update or settings change actually did.

**This is a bigger lift than "PowerShell is present," though.** HP CMSL is a separate module that has to be installed into the WinPE image on top of PowerShell (typically `Install-Module HPCMSL` from PowerShell Gallery, or a manual offline package for an environment without internet access like WinPE) — confirming PowerShell exists doesn't mean this module exists too; that's unconfirmed and unrelated. If pursued, it would replace both `biosconfigutility64` calls and the `HPBIOSUPDREC64.exe` call with HP-native, better-supported equivalents — a more thorough rewrite than the plain-PowerShell port in this doc, but backed by an officially documented, purpose-built tool rather than reverse-engineered text parsing. Not investigated further than this — worth a dedicated look if a PowerShell rewrite is ever pursued for real.

## Does PowerShell replace `bcdedit` too?

No. `bcdedit.exe` is a separate, standard Windows Recovery Environment tool — **not an optional component**, unlike PowerShell — so its presence doesn't depend on PowerShell being installed at all, and PowerShell doesn't remove the need to call it. Even a PowerShell version of `:SetBootNextUSB` would still shell out to `bcdedit.exe` (`& bcdedit.exe /enum firmware`, `& bcdedit.exe /bootsequence <id>`) exactly like the batch version does. PowerShell can technically talk to the underlying BCD store directly via the `root\WMI` `BcdStore`/`BcdObject`/`BcdElement` WMI classes (what `bcdedit.exe` itself is built on), but that API is low-level and poorly documented — not worth it here. The only real benefit PowerShell brings to this piece is parsing `bcdedit`'s text output with `-match`/regex instead of `findstr` + `for /f` loops — same tool, cleaner parsing.

## Pros — what actually gets better if PowerShell is available

These are code-quality/robustness improvements, not fixes to the architectural risks documented elsewhere in this project (Boot Order reset, `BootNext` survival, etc. — those are firmware-level facts, unaffected by scripting language):

- **BCU output parsing** — the batch version manually slices the `<VALUE><![CDATA[*No,Yes]]></VALUE>` string with `findstr` and substring tricks. PowerShell parses it as real XML (`[xml]$xml = $raw`), which is more robust to formatting variations.
- **Boot Order rewriting** — the batch version rebuilds `config.txt` line-by-line inside a `for /f` loop to move one entry to the top of a block. PowerShell does this with array slicing (`Get-Content` → reorder → `Set-Content`) in a handful of clear lines.
- **Control flow** — batch's `exit /b` inside a same-file `call`ed subroutine terminates the *entire* script, not just the subroutine (a real gotcha this project already hit once — see CONTEXT.md). PowerShell functions with `return`/`exit` and `try/catch` don't have this trap.
- Generally easier to read, extend, and debug for future maintenance.

## Cons — what doesn't change or gets worse

- **Adds a dependency that isn't guaranteed to exist**, unlike everything the batch script currently relies on. Switching without confirming presence first would trade a working script for a maybe-working one.
- **Doesn't fix any of the actual hardware/firmware risks** this project has spent most of its effort on — Boot Order resetting during flash, whether `BootNext` survives it, whether the boot USB registers a firmware entry at all. Same uncertainty either way.
- **A full rewrite is a real undertaking** — re-testing every code path from scratch, not a drop-in swap.
- If PowerShell does turn out to be present, a full switch isn't necessarily the best use of that fact — selectively rewriting only the fragile parts (BCU XML parsing, Boot Order rewriting) inside the existing batch script, e.g. by shelling out to `powershell -command "..."` for just those pieces, is a lower-risk way to get most of the benefit without discarding the tested batch flow.

---

## Sources

- [WMIC removal from Windows — Microsoft Support](https://support.microsoft.com/en-us/topic/windows-management-instrumentation-command-line-wmic-removal-from-windows-e9e83c7f-4992-477f-ba1d-96f694b8665d)
- [Notes on WinPE usage — HP Developer Portal](https://developers.hp.com/hp-client-management/doc/notes-winpe-usage)
- [Client Management Script Library (HP CMSL) — HP Developer Portal](https://developers.hp.com/hp-client-management/doc/client-management-script-library)
- [Update-HPFirmware — HP Developer Portal](https://developers.hp.com/hp-client-management/doc/update-hpfirmware)
