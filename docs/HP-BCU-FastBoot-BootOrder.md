# HP BCU: Fast Boot + Boot Order Check & Fix

**Utility:** HP BiosConfigUtility64 (BCU)
**Model:** HP ProBook 4 G1 (and compatible)
**Purpose:** automatically check and fix two BIOS settings without manually entering F9:
1. Fast Boot → must be **Disable**
2. Boot Order → USB must be **first** in the list

The script is called **twice** in the overall imaging pipeline:
- once **before** the BIOS flash (so the USB drive is actually picked up),
- once **after** the flash and reboot (a BIOS flash can reset Boot Order, but doesn't always reset Fast Boot — they live in different NVRAM areas).

---

## Why Fast Boot and Boot Order are handled differently

- **Fast Boot** is a simple enum-style setting. In `/getvalue` output it looks like:
  ```
  <VALUE><![CDATA[*No,Yes]]></VALUE>
  ```
  The asterisk `*` marks the **currently selected** value. It's changed via `/setvalue`.

- **Boot Order** is an **ordered list** of devices, not a single value. There's no asterisk — the order itself is the current state. Confirmed on real hardware (2026-09-02): `/getvalue:"UEFI Boot Order"` does work for **reading** it, returning the whole list as one comma-separated `CDATA` value (e.g. `HDD:USB:1,HDD:M.2:1,NETWORK IPV4:EMBEDDED:1,...`) — same shape as any other `/getvalue` call, just without the `*` marker. **Writing** it is a separate question: `/setvalue` for a list like this is unconfirmed, so the fix path still dumps the whole config (`/GetConfig`), edits the relevant block in the text file, and applies it back (`/SetConfig`).

Known behavior (confirmed on an HP support forum thread): after a successful BIOS flash, **Boot Order can revert to factory defaults**, even if the flash command itself reported success. That's why a second check is required **after** the flash, not just once at the start.

---

## Code

```bat
@echo off
setlocal enabledelayedexpansion

set "TMPDIR=%~dp0temp"
if not exist "%TMPDIR%" mkdir "%TMPDIR%"

REM ============================================
REM  MAIN CALLS
REM ============================================
call :CheckAndFixSimpleSetting "Fast Boot" "Disable"
call :CheckAndFixBootOrder

echo Done.
exit /b 0


REM ============================================
REM  Fast Boot (simple enum-style setting)
REM ============================================
:CheckAndFixSimpleSetting
set "sName=%~1"
set "sDesired=%~2"
set "attempt=0"

:retry_simple
set /a attempt+=1

set "line="
for /f "delims=" %%i in ('biosconfigutility64 /getvalue:"%sName%" ^| findstr "VALUE"') do set "line=%%i"

if not defined line (
    echo [ERROR] Could not read "%sName%" from BCU
    exit /b 1
)

set "value=!line:*CDATA[=!"
set "value=!value:]]></VALUE>=!"

set "current="
for %%A in (%value:,= %) do (
    set "tok=%%A"
    if "!tok:~0,1!"=="*" set "current=!tok:~1!"
)

if not defined current (
    echo [ERROR] Could not parse current value for "%sName%"
    exit /b 1
)

if /i "!current!"=="%sDesired%" (
    echo [OK] %sName% = !current!
    goto :eof
)

if !attempt! gtr 3 (
    echo [FAIL] %sName% still "!current!" after 3 attempts
    exit /b 1
)

echo [FIX] %sName% is "!current!" -^> setting to "%sDesired%" ^(attempt !attempt!^)
biosconfigutility64 /setvalue:"%sName%","%sDesired%" >nul 2>&1
goto :retry_simple


REM ============================================
REM  Boot Order (ordered list) - pure CMD
REM ============================================
:CheckAndFixBootOrder
set "BOOTSETTING=UEFI Boot Order"
set "attempt=0"

:retry_bootorder
set /a attempt+=1

REM --- Check: read the whole list in one shot via /getvalue ---
set "line="
for /f "delims=" %%i in ('biosconfigutility64 /getvalue:"%BOOTSETTING%" ^| findstr "VALUE"') do set "line=%%i"

if not defined line (
    echo [ERROR] Could not read "%BOOTSETTING%" from BCU
    exit /b 1
)

set "bovalue=!line:*CDATA[=!"
set "bovalue=!bovalue:]]></VALUE>=!"
for /f "tokens=1 delims=," %%A in ("!bovalue!") do set "first_entry=%%A"

echo !first_entry! | findstr /i "USB" >nul
if !errorlevel! equ 0 (
    echo [OK] USB is first in boot order
    goto :eof
)

if !attempt! gtr 3 (
    echo [FAIL] Boot order still not USB-first after 3 attempts
    exit /b 1
)

echo [FIX] USB not first, rewriting boot order ^(attempt !attempt!^)

biosconfigutility64 /GetConfig:"%TMPDIR%\config.txt" >nul 2>&1

REM --- Reorder: move USB line to the top of the Boot Order block ---
set "newfile=%TMPDIR%\config_new.txt"
if exist "%newfile%" del "%newfile%"

set "in_block=0"
set "usb_line="
for /f "usebackq delims=" %%L in ("%TMPDIR%\config.txt") do (
    set "line=%%L"
    if "!in_block!"=="1" if not "!line!"=="" (
        echo !line! | findstr /i "USB" >nul && set "usb_line=!line!"
    )
    if "!line!"=="%BOOTSETTING%" set "in_block=1"
    if "!in_block!"=="1" if "!line!"=="" set "in_block=0"
)

set "in_block=0"
set "wrote_usb=0"
(
for /f "usebackq delims=" %%L in ("%TMPDIR%\config.txt") do (
    set "line=%%L"
    if "!in_block!"=="1" (
        if "!line!"=="" (
            set "in_block=0"
            echo(
        ) else (
            if "!wrote_usb!"=="0" (
                echo !usb_line!
                set "wrote_usb=1"
            )
            if not "!line!"=="!usb_line!" echo !line!
        )
    ) else (
        echo !line!
    )
    if "!line!"=="%BOOTSETTING%" set "in_block=1"
)
) > "%newfile%"

move /y "%newfile%" "%TMPDIR%\config.txt" >nul

biosconfigutility64 /SetConfig:"%TMPDIR%\config.txt" >nul 2>&1

goto :retry_bootorder
```

---

## Logic walkthrough

### `:CheckAndFixSimpleSetting`
1. Runs `/getvalue:"Fast Boot"`, extracts the `<VALUE>...</VALUE>` line via `findstr`.
2. If no line was found at all — error (BCU couldn't read the setting, e.g. wrong setting name).
3. Strips out the content between `CDATA[` and `]]` — yields a list like `*No,Yes`.
4. Looks for the token starting with `*` — that's the current value.
5. If the current value already matches the desired one — exits with no changes.
6. If not — calls `/setvalue`, then **re-runs the whole check from scratch** (doesn't trust the command's own return code, re-reads the actual state instead).
7. Capped at 3 attempts, after which it prints an explicit `[FAIL]` and returns exit code 1 (so the calling script can stop instead of continuing blindly).

### `:CheckAndFixBootOrder`
1. Reads the whole list in one call — `/getvalue:"UEFI Boot Order"` — and takes the first comma-separated entry.
2. If that entry contains `USB` — everything is fine, exit.
3. If not — dumps the **entire** BIOS config to a file via `/GetConfig` (not a single value — all settings at once), since the fix path still needs the file-based `/SetConfig` mechanism.
4. Walks the file line by line, finds the block boundaries (from the header to the first blank line), pulls out the line containing `USB`, moves it to the top of the block, keeps the rest in their original order.
5. Rewrites `config.txt` and applies it via `/SetConfig`.
6. Re-checks via `/getvalue` again — if it still didn't take (the known BCU bug), retries, up to 3 times.

---

## Important caveats

- **The `config.txt` format depends on the BCU version and model.** The line-parsing logic (block boundary = blank line, no indentation before device names) is based on the official example in HP's User Guide, but **on your actual ProBook 4 you should manually open `config.txt`** once after `/GetConfig` and confirm the format matches.
- The script uses `UEFI Boot Order` — confirmed against a real config.txt dump for an HP ProBook 450 G1 (see the Full Script doc's Sources), which has two separate sections, `Legacy Boot Order` and `UEFI Boot Order` (there's no plain `Boot Order` on this model family). "UEFI" here is just part of the section's label, not a boot-mode choice — the entry we pick inside it is whichever entry contains "USB", i.e. the physical flash drive, regardless of boot mode.
- Device naming differs by model/BCU version — confirmed on the actual deployment WinPE (2026-09-02), `/getvalue:"UEFI Boot Order"` on the real target hardware returned short tokens like `HDD:USB:1,HDD:M.2:1,NETWORK IPV4:EMBEDDED:1,...`, not the longer `USB Hard Drive` / `Generic USB Device` style names seen in the ProBook 450 G1 reference dump. Only one entry contains "USB" on this real machine, so the ambiguity risk that reference dump raised (it had two "USB"-containing entries) doesn't apply here — but whether `/GetConfig`'s file output uses this same short format is unconfirmed, worth checking on-site if the fix path ever needs debugging.
- The script does **not** check the physical fact that the USB drive is plugged in and detected by the USB controller at POST — that's a separate issue (discussed separately: Legacy Support/CSM, which port, USB 2.0 vs 3.0 controller).
- Recommended to log every call (`>> log.txt 2>&1`) when used in a real imaging pipeline across many machines.
