# Reads the Boot Order setting named in the _pname environment
# variable and reports whether the first entry looks like the boot
# USB drive. Prints "MATCH|<entry>" if it contains "USB",
# "NOMATCH|<entry>" if not, "ERROR|" if the setting couldn't be read.

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
