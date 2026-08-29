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

- [ ] Exact `HPBIOSUPDREC64.exe` flags (`-s`, `-l` confirmed; `-r`, `-a`, `-h`, `-b`, `-p`
      need verification) — check via `HPBIOSUPDREC64.exe -?`
- [ ] `config.txt` format for Boot Order on this specific model
- [ ] Mechanism to re-launch the script after reboot (Task Sequence / RunOnce)
- [ ] Real names/paths for scripts B (Security Settings) and C (dialog + Ghost) —
      currently placeholders `B.bat` / `C.bat` next to the script

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
