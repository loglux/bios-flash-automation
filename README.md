# HP ProBook 4 G1 — BIOS Flash & Configuration Automation

Batch script automating BIOS flashing and configuration of key settings
(Fast Boot, Boot Order, Enable MS UEFI CA key) on the HP ProBook 4 G1 via
HP BiosConfigUtility64 (BCU), run from a bootable USB drive in WinPE.

---

## Structure

```
scripts/
  HP-ProBook-Flash-And-Configure.bat    — the script

docs/
  HP-BCU-FastBoot-BootOrder.md
  HP-BCU-MSUEFICAKey-Gate.md            — early gate draft, superseded — see Full Script
  HP-ProBook-BIOS-Flash-Full-Script.md  — full combined script, kept in sync with scripts/
```

---

## Status

Several previously open items are now confirmed on real hardware (2026-08-29 to 2026-09-01 on-site testing).

Verified:
- [x] `HPBIOSUPDREC64.exe` flags confirmed against HP's own documentation:
      `-s`, `-f`, `-l`, `-a`, `-r`, `-h`, `-b`, `-p`
- [x] `config.txt` format and setting name for Boot Order — `UEFI Boot Order` confirmed
      correct on the actual ProBook; the line-based parsing (block boundary = blank
      line, no indentation, no `*` marker on list entries) works as designed
- [x] `wmic` works in the actual deployment WinPE

Still open:
- [ ] **Mechanism to re-launch the script after reboot.** Re-scoped after on-site
      investigation: WinPE always runs its `Startnet.cmd` entry point on every boot
      (that's how the existing `T1700Setup` process already starts itself) — so the
      real gap isn't "invent a re-launch mechanism," it's "hook this script into
      whatever already launches on boot" (check for the `flash_attempt_<serial>.state`
      file, launch this script if present). Not yet implemented.
- [ ] Real names/paths for scripts B (Security Settings) and C (dialog + Ghost) —
      currently placeholders `B.bat` / `C.bat` next to the script. Candidates spotted
      in a real file listing from this environment: `SetBiosProBook4G1ah14.bat`,
      `Post_Ghost.bat`, `STARTXUEFI85.bat` — not yet confirmed which map to B/C.
- [ ] Confirm whether these machines have HP Sure Start — if so, the BIOS update
      may trigger more than one reboot before the version actually changes (the
      attempt-counter loop already tolerates this, just worth knowing in advance)
- [ ] What BIOS password script B sets, and the other ~3 Security Settings it
      configures alongside "Enable MS UEFI CA key" — not yet identified
- [ ] No self-recovery if Boot Order resets during the flash-triggered reboot on a
      machine that already has a working OS on disk — it boots into Windows instead
      of back into WinPE, and the script (living only on the USB drive) can't restart
      itself. The Step 1 check before the flash is the only protection in place.
      Machines with a blank disk are expected to be unaffected. Observed on hardware
      during on-site testing.

---

## What the script does

The pipeline glues together three scripts:
- **A** — flashes the BIOS to the target version (implemented directly in this script)
- **B** — configures several Security Settings options, including "Enable MS UEFI CA key"
  (an existing script, called by this one — its internals are out of scope here)
- **C** — the final imaging dialog + Ghost (an existing script, launched at the end)

Plus Fast Boot and Boot Order (USB first), which are not part of script B — they were
added directly to this script so the pipeline doesn't need someone to manually catch
every reboot and re-enter the BIOS boot menu.

1. Checks and fixes Fast Boot and Boot Order (USB first) before flashing
2. Checks the current BIOS version against the target
3. If it doesn't match — flashes, with retry logic (up to 3 attempts) across reboots,
   with the attempt counter tied to the machine's serial number
4. Once the version is confirmed — final check of Fast Boot / Boot Order, then a gate on
   "Enable MS UEFI CA key": if not `Yes`, launches script B (Security Settings) and
   re-checks — never sets the value itself
5. Once the gate passes — launches script C (imaging dialog + Ghost), without touching
   its internal logic
6. Logs every step to `stage.log`

For a detailed logic walkthrough, see
`docs/HP-ProBook-BIOS-Flash-Full-Script.md`.

---

## Sources

Directly backing the canonical script (flash flags/timing, `config.txt` format).

- [Updating BIOS Command Lines — HP Support Community](https://h30434.www3.hp.com/t5/Commercial-PC-Software/Updating-BIOS-Command-Lines/td-p/6518162)
- [BIOS Flash Update (HP PDF)](https://h30434.www3.hp.com/psg/attachments/psg/Business-PC-Workstation-POS/34410/1/BIOS%20Flash%20Update.pdf)
- [How to Update HP BIOS on Commercial Platforms — HP Developer Portal](https://developers.hp.com/hp-client-management/blog/how-update-hp-bios-commercial-platforms)
- [bios1.txt — real config.txt dump for an HP ProBook 450 G1](https://h30434.www3.hp.com/psg/attachments/psg/Tablet/1373380/1/bios1.txt)
