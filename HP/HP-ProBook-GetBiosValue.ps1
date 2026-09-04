param([string]$Mode = 'Raw')

# Reads the BIOS setting named in the _pname environment variable (set
# by the calling .bat file) and prints its value.
# Mode Raw  - the full CDATA content as-is (plain string or comma list)
# Mode Enum - the asterisk-marked current selection from an enum list

$name = $env:_pname
$exe = Join-Path $PSScriptRoot 'biosconfigutility64.exe'
$raw = (& $exe /getvalue:$name) -join [char]10

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
