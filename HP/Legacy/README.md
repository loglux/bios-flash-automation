# Legacy

`HP-ProBook-BiosCheck-v1.bat` through `v5.bat` — earlier iterations of
the pipeline, superseded by `HP-ProBook-BiosCheck-v6.bat` (in `HP/`).
Kept untouched, per this project's own versioning convention: each
version is a snapshot of that point in the project's history, never
edited after the next one supersedes it.

**These are for reading, not running.** `v2.bat` through `v5.bat`
reference `.ps1` helpers (`HP-ProBook-GetBiosValue.ps1`,
`HP-ProBook-CheckBootOrderFirst.ps1`, `HP-ProBook-FindConfigLine.ps1`)
via `%~dp0<name>.ps1` — a path relative to wherever the script itself
sits. That assumption was correct when these lived in `HP/` alongside
the helpers; now that they're in `HP/Legacy/`, those paths point at
files that aren't here (the helpers stayed in `HP/`). Left as-is
deliberately, since fixing the paths would mean editing a "shipped"
version's content, which defeats the point of keeping it as a
historical snapshot. If one of these ever needs to actually run again,
copy it back next to the current `.ps1` helpers first.
