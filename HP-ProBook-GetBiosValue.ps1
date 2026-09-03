param([string]$Mode = 'Raw')

# Reads the BIOS setting named in the _pname environment variable (set
# by the calling .bat file) and prints its value.
# Mode Raw  - the full CDATA content as-is (plain string or comma list)
# Mode Enum - the asterisk-marked current selection from an enum list
#
# Called via "-File", not "-Command", and takes the setting name via
# an environment variable rather than a command-line argument: cmd.exe's
# "for /f ('...')" parser can break on parentheses anywhere in the
# command text it captures, including ones coming from setting names
# like "Startup Delay (sec.)" - confirmed on-site, 2026-09-03.

$name = $env:_pname
$raw = (biosconfigutility64 /getvalue:$name) -join [char]10

if ($raw -notmatch '(?s)<!\[CDATA\[(.*?)\]\]>') {
    exit 1
}

$content = $matches[1]

if ($Mode -eq 'Enum') {
    foreach ($tok in ($content -split ',')) {
        if ($tok -match '^\*') {
            $tok -replace '^\*', ''
            exit 0
        }
    }
    exit 1
}

$content
