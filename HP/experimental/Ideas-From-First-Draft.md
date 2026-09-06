# Ideas from the first-draft script (not verified, may be rejected)

`HP-ProBook-Flash-And-Configure.bat` was this project's very first attempt
(the initial commit) - written speculatively, never verified on real
hardware, and superseded entirely by the `HP-ProBook-BiosCheck-v1..v6`
series, which was verified step by step on real machines. The original
file is being deleted since it doesn't work as written: wrong flash tool
filename (`HPBIOSUPDREC64.exe` instead of the real `HpFirmwareUpdRec64.exe`),
a `-l` log-path flag that doesn't exist on the real tool, and a `shutdown
/r` call that doesn't work in WinPE (needs `wpeutil reboot` instead) - so
its own persistent-logging and controlled-reboot behavior never actually
worked either.

That said, a few of the *goals* it was reaching for are still real gaps in
the current v6 pipeline - captured here as candidate ideas for a possible
future version, not a decided plan. Any of these could just as easily be
rejected once actually tried on hardware, same as the rest of this file.

## Idea 1: persistent per-step logging

v6 only `echo`s to console - nothing survives past the current WinPE
session. The first draft tried `>> stage.log` next to itself, but that
almost certainly landed on the ephemeral `X:` copy (everything under
`T1700Setup` gets copied there by `startnet.cmd` and run from there,
unless a script explicitly switches back to a real drive like `A.bat`
does with `d:`). A version that actually persists would need to
explicitly target the real, persistent USB drive letter (confirmed `D:`
in this environment), not just `%~dp0`.

## Idea 2: capped retry attempts tied to machine serial number

`flash_attempt_<serial>.state`, `MAXATTEMPTS=3` - a safety cap so a
machine stuck in a bad loop doesn't retry forever. v6 has no equivalent
limit at all currently. Same persistence caveat as Idea 1 applies to the
state file itself.

## Idea 3: explicit reboot control instead of relying on the tool's own behavior

The idea of passing `-r` (do not reboot) and then explicitly triggering
the reboot ourselves, instead of trusting `HpFirmwareUpdRec64.exe`'s own
reboot behavior (which this project spent a long session establishing is
inconsistent/hard to predict - see the WinPE `RestartSystem`/`MiniNt`
detection and toast-notification findings), is a reasonable instinct. The
first draft's mistake was using `shutdown /r`, which doesn't work in
WinPE - a real attempt at this would need `wpeutil reboot`.
