# Dell BIOS Flash & Configuration Automation

Planned automation for detecting a Dell model, applying BIOS setting
fixes (e.g. disabling IPv6), and flashing the model-specific BIOS
firmware — run from the same WinPE bootable USB flash drive as the
`HP/` pipeline.

**Status: design stage.** No exact model list yet, no scripts written.
The one fixed requirement so far: the approach must make adding a new
model easy — a config entry, not new logic.

---

## Design goal

Unlike the HP project (a single model, `HP ProBook 4 G1ah14`), Dell
automation has to support several models from the start, with the
list expected to grow over time and not fully known yet. So the
dispatch logic itself must stay model-agnostic — per-model specifics
(firmware file, target version, settings profile) live in a lookup
table keyed by model/Service Tag, not hardcoded into the script flow.
Adding a model later means adding a row to that table, not writing a
new script.

---

## Planned approach

### 1. Model detection

- `wmic csproduct get name` (or `Get-CimInstance Win32_ComputerSystem`
  for `Model`) — human-readable model name.
- `wmic bios get serialnumber` — the Dell Service Tag. More reliable
  than the model name alone, since it unambiguously identifies the
  exact line/revision.

### 2. BIOS settings

- **Dell Command | Configure** (`cctk.exe`) — Dell's standalone
  equivalent of HP's BiosConfigUtility64. No installation needed; runs
  directly from the USB flash drive under WinPE.
- Example: `cctk.exe --Ipv6=Disabled`

### 3. Firmware flashing

The main open question, needs per-model verification before anything
is built:

- Dell BIOS updates typically ship as a self-extracting `.exe` with a
  silent `/s` flag.
- Not all of them are WinPE-compatible — some require a full Windows
  environment to run. Each package's release notes usually say whether
  offline/WinPE flashing is supported.
- Fallback to check per model: UEFI Flash-from-capsule via **F12 →
  BIOS Flash Update**, which reads the firmware file straight off USB
  without needing any runner executable at all.

### 4. Multi-model dispatch

A `Model` / `Service Tag prefix` → `{flash file, target version,
settings profile}` lookup table drives the pipeline. This isn't
speculative complexity — it's required because, unlike the HP project,
there is more than one real model to support from day one; the table
just isn't populated yet since the exact model list isn't confirmed.

---

## Status

Planning only. No scripts, no config table, no confirmed model list.
