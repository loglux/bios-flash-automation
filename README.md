# HP ProBook 4 G1 — BIOS Flash & Configuration Automation

Batch script automating BIOS flashing and configuration of key settings
(Fast Boot, Boot Order, Enable MS UEFI CA key) on the HP ProBook 4 G1 via
HP BiosConfigUtility64 (BCU), run from a bootable USB drive in WinPE.

---

## Structure

```
scripts/
  HP-ProBook-Flash-And-Configure.bat   — main script

docs/
  HP-BCU-FastBoot-BootOrder.md
  HP-BCU-MSUEFICAKey-Gate.md            — early gate draft, superseded — see Full Script
  HP-ProBook-BIOS-Flash-Full-Script.md  — full combined script, kept in sync with scripts/
```

---

## Status

⚠️ **Work in progress.**

Open items requiring on-site verification:

- [x] `HPBIOSUPDREC64.exe` flags — confirmed against HP's own documentation
      (`-s`, `-f`, `-l`, `-a`, `-r`, `-h`, `-b`, `-p`, see Sources below and
      `docs/HP-ProBook-BIOS-Flash-Full-Script.md`); still worth a one-time
      `HPBIOSUPDREC64.exe -?` check on-site to confirm this exact utility version
- [ ] `config.txt` format for Boot Order on this specific model — the line-based
      parsing (block boundary = blank line, no indentation, no `*` marker on
      list entries) matches HP's own documented example, and the setting name
      is set to `UEFI Boot Order`, confirmed against a real config.txt dump for
      an HP ProBook 450 G1 which has separate `Legacy Boot Order` / `UEFI Boot
      Order` sections (see Sources); still needs a one-time `/GetConfig` on the
      actual machine to confirm the exact section name and entry format on this
      specific unit/BIOS revision — the flash drive will be physically inserted
      when the script runs, so its boot entry should carry the drive's own name
      (containing "USB"), not a generic placeholder
- [ ] Mechanism to re-launch the script after reboot (Task Sequence / RunOnce)
- [ ] Real names/paths for scripts B (Security Settings) and C (dialog + Ghost) —
      currently placeholders `B.bat` / `C.bat` next to the script
- [ ] Confirm whether these machines have HP Sure Start — if so, the BIOS update
      may trigger more than one reboot before the version actually changes (the
      attempt-counter loop already tolerates this, just worth knowing in advance)

---

## ⚠️ Confirmed risk: no self-recovery if Boot Order breaks during the flash

**This has been directly observed, not just reported on forums** — see `docs/Boot-Order-Reset-Risk.md` for the full write-up. Manual reproduction: Fast Boot and Boot Order both set correctly and confirmed holding through a normal reboot; after running the flash and rebooting again, Fast Boot stayed disabled but Boot Order reset to default, and since the disk already had a working Windows install, the machine booted straight into Windows instead of back into WinPE.

The actual firmware write happens during POST on the reboot right after the flash command (see `docs/HP-ProBook-BIOS-Flash-Full-Script.md` → "When does the flash actually happen?"), and that's where Boot Order resets. Since the script only lives on the USB drive, it cannot restart itself to fix this if the machine boots the internal disk instead — its final-block re-check never gets a chance to run. The Step 1 check (Fast Boot/Boot Order verified *before* the flash) is the only real protection going into that risky reboot.

Machines with a blank/unimaged disk are expected to be unaffected (no competing OS to boot into — see the doc for why). For machines with an existing OS on disk, this is a real, confirmed gap. A mitigation is proposed (a one-time `BootNext` override via `bcdedit`, found dynamically per machine — not hardcoded) but **not yet implemented**, pending on-site testing of whether it actually survives the same reset. See `docs/Boot-Order-Reset-Risk.md` for details.

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

- [Updating BIOS Command Lines — HP Support Community](https://h30434.www3.hp.com/t5/Commercial-PC-Software/Updating-BIOS-Command-Lines/td-p/6518162)
- [BIOS Flash Update (HP PDF)](https://h30434.www3.hp.com/psg/attachments/psg/Business-PC-Workstation-POS/34410/1/BIOS%20Flash%20Update.pdf)
- [How to Update HP BIOS on Commercial Platforms — HP Developer Portal](https://developers.hp.com/hp-client-management/blog/how-update-hp-bios-commercial-platforms)
- [650 G1: Silent BIOS Update With No Automatic Reboot? — HP Support Community](https://h30434.www3.hp.com/t5/Commercial-PC-Software/650-G1-Silent-BIOS-Update-With-No-Automatic-Reboot/td-p/5071561)
- [bios1.txt — real config.txt dump for an HP ProBook 450 G1](https://h30434.www3.hp.com/psg/attachments/psg/Tablet/1373380/1/bios1.txt)
