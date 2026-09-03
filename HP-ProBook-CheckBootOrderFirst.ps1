# Reads the Boot Order setting named in the _pname environment
# variable and reports whether the first entry looks like the boot
# USB drive. Prints "MATCH|<entry>" if it contains "USB",
# "NOMATCH|<entry>" if not, "ERROR|" if the setting couldn't be read.
#
# Called via "-File", not "-Command" - see HP-ProBook-GetBiosValue.ps1
# for why (cmd.exe's "for /f" parser breaks on parentheses in the
# command text, confirmed on-site 2026-09-03). Also calls
# biosconfigutility64 via $PSScriptRoot, not by bare name - PowerShell
# doesn't search the current directory for executables the way cmd.exe
# does (confirmed on-site, 2026-09-03).

$name = $env:_pname
$exe = Join-Path $PSScriptRoot 'biosconfigutility64.exe'
$raw = (& $exe /getvalue:$name) -join [char]10

if ($raw -notmatch '(?s)<!\[CDATA\[(.*?)\]\]>') {
    'ERROR|'
    exit
}

$first = ($matches[1] -split ',')[0]

if ($first -match 'USB') {
    'MATCH|' + $first
} else {
    'NOMATCH|' + $first
}
