# DesktopShortcuts

Separate from the BIOS pipeline in `HP/` — a proposal for the imaging
process around it, not the flash/settings work itself.

Some machines need tool shortcuts (compliance, restart, Altiris, etc.)
on the desktop so an engineer can finish configuring them over a
remote connection after imaging.

## The two scripts

- **`HP-ProBook-PlaceShortcuts.bat`** — runs from WinPE, copies every
  `.lnk` file from a `Shortcuts/` folder next to it onto the target
  system's Public Desktop (`Users\Public\Desktop`), visible to
  whichever account is used to connect remotely, without depending on
  a specific username or a new profile being created first. Managing
  the shortcut list is just adding/removing files in that `Shortcuts/`
  folder, not editing the script.
- **`HP-ProBook-RemoveShortcuts.bat`** — the cleanup counterpart, runs
  later on the *live* target system (not from WinPE), once remote
  configuration is actually finished. Deliberately **not** automated
  the same way as placing them — an automatic trigger at first login
  would delete them before they're ever used. Meant to be triggered
  centrally across whichever machines are done (e.g. via
  Altiris/Notification Server, or `Invoke-Command`/PsExec against a
  list of hosts), not double-clicked one machine at a time.

## Gotcha to check on-site

`PlaceShortcuts.bat`'s `TARGET_DRIVE` assumes the offline target
system's internal disk is `C:` as seen from WinPE — typically true,
but not guaranteed on every machine/WinPE build (see the drive-letter
discussion in the root project's `SystemIdentity/README.md` for why
letter assignment isn't always fixed). Verify before relying on it.
