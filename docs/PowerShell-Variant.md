# PowerShell script variant — status, pros/cons, and how to check/add it

**Status:** `powershell` is **confirmed present** in this project's actual WinPE (verified on-site, 2026-09-01) — the availability concern below is resolved. `scripts/HP-ProBook-Flash-And-Configure.ps1` is still **not adopted**, though — it's a parallel PowerShell port of the batch script, written to compare approaches, and hasn't received anywhere near the real-world scrutiny the batch script has (multiple bugs found and fixed through this project's testing — the `-r` flag, the Boot Order setting name, etc.). The batch script remains the primary, relied-upon version. A switch is now a legitimate option rather than blocked by an unknown, but it would need its own round of validation first.

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
2. Add the required optional components, **in this dependency order** (paths are typically under `...\Windows Preinstallation Environment\amd64\WinPE_OCs\` in the ADK install):
   ```
   Dism /Image:C:\mount /Add-Package /PackagePath:"...\WinPE-WMI.cab"
   Dism /Image:C:\mount /Add-Package /PackagePath:"...\WinPE-NetFx.cab"
   Dism /Image:C:\mount /Add-Package /PackagePath:"...\WinPE-Scripting.cab"
   Dism /Image:C:\mount /Add-Package /PackagePath:"...\WinPE-PowerShell.cab"
   ```
3. Commit and unmount:
   ```
   Dism /Unmount-Image /MountDir:C:\mount /Commit
   ```
4. Copy the updated `boot.wim` back to the deployment USB drive, replacing the original.

**Caveats:** the CAB architecture (x86/amd64/arm64) must match the existing image exactly; the dependency order above must be respected or `Add-Package` fails; this changes the boot image for the *entire* fleet's USB drives, not just one — treat it as an infrastructure change, not a quick script edit.

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
