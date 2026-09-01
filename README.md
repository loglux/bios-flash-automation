# HP ProBook 4 G1 — BIOS Flash & Configuration Automation

Batch script automating BIOS flashing and configuration of key settings
(Fast Boot, Boot Order, Enable MS UEFI CA key) on the HP ProBook 4 G1 via
HP BiosConfigUtility64 (BCU), run from a bootable USB drive in WinPE.

A proposed improvement to the existing manual imaging procedure: replaces
manually catching each reboot and re-entering the BIOS boot menu (F9) with
a script that checks, fixes, and logs these steps itself.

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

## Notes

- Real names/paths for scripts B (Security Settings) and C (dialog + Ghost) —
  currently placeholders `B.bat` / `C.bat` next to the script. Candidates spotted
  in a real file listing from this environment: `SetBiosProBook4G1ah14.bat`,
  `Post_Ghost.bat`, `STARTXUEFI85.bat` — not yet confirmed which map to B/C.
- Whether these machines have HP Sure Start is not yet confirmed — if so, the BIOS
  update may trigger more than one reboot before the version actually changes (the
  attempt-counter loop already tolerates this, just worth knowing in advance).
- What BIOS password script B sets, and the other ~3 Security Settings it configures
  alongside "Enable MS UEFI CA key", are not yet identified.
- No self-recovery if Boot Order resets during the flash-triggered reboot on a
  machine that already has a working OS on disk — it boots into Windows instead
  of back into WinPE, and the script (living only on the USB drive) can't restart
  itself. The Step 1 check before the flash is the only protection in place.
  Machines with a blank disk are expected to be unaffected. Observed on hardware
  during on-site testing.
- Re-launching the script after a flash-triggered reboot needs to be hooked into
  whatever already launches on boot for this imaging environment (WinPE always runs
  `Startnet.cmd` on every boot — the existing `T1700Setup` process starts itself this
  way already). Not yet implemented: check for the `flash_attempt_<serial>.state`
  file, launch this script if present.

---

## Sources

Directly backing the canonical script (flash flags/timing, `config.txt` format).

- [Updating BIOS Command Lines — HP Support Community](https://h30434.www3.hp.com/t5/Commercial-PC-Software/Updating-BIOS-Command-Lines/td-p/6518162)
- [BIOS Flash Update (HP PDF)](https://h30434.www3.hp.com/psg/attachments/psg/Business-PC-Workstation-POS/34410/1/BIOS%20Flash%20Update.pdf)
- [How to Update HP BIOS on Commercial Platforms — HP Developer Portal](https://developers.hp.com/hp-client-management/blog/how-update-hp-bios-commercial-platforms)
- [bios1.txt — real config.txt dump for an HP ProBook 450 G1](https://h30434.www3.hp.com/psg/attachments/psg/Tablet/1373380/1/bios1.txt)

---

P.S. HP also publishes an official PowerShell module for BIOS management and
flashing — HP Client Management Script Library (HP CMSL), with cmdlets like
`Set-HPBIOSSettingValue` and `Update-HPFirmware`.

- [Client Management Script Library (HP CMSL) — HP Developer Portal](https://developers.hp.com/hp-client-management/doc/client-management-script-library)

P.S. HP's own deployment whitepaper solves the "does the machine come back to
the deployment environment after reboot" problem architecturally: run the
process as an MDT/SCCM Task Sequence, whose engine guarantees resumption after
a Restart Computer step. Doesn't apply to this pipeline — `T1700Setup` is a
standalone set of batch files on a USB drive, with no Task Sequence engine
underneath it — see `experimental/Boot-Order-Reset-Risk.md` for the full
comparison.

- [Building, Deploying, and Updating an Image on HP Commercial PCs (HP whitepaper)](https://ftp.hp.com/pub/caps-softpaq/cmit/whitepapers/Building,%20Deploying,%20and%20Updating%20an%20Image%20on%20HP%20Commercial%20PCs.pdf)
