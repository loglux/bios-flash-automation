param([switch]$Exclude)

# Finds one line inside a named block of a BCU config.txt dump.
# Reads its inputs from environment variables (set by the calling
# .bat file), not command-line arguments - see
# HP-ProBook-GetBiosValue.ps1 for why.
#
#   _pcfg      path to config.txt
#   _pname     the block header line to look inside (e.g. "UEFI Boot Order")
#   _ppattern  a regex; by default finds the first matching line in
#              the block, or with -Exclude, the first line that does
#              NOT match (the "elimination" approach used for the
#              disk entry when USB can't be matched positively)

$path = $env:_pcfg
$header = $env:_pname
$pattern = $env:_ppattern

$lines = Get-Content $path
$inBlock = $false
$found = $null

foreach ($l in $lines) {
    if ($inBlock -and $l -ne '' -and -not $found) {
        $isMatch = $l -match $pattern
        if ($Exclude) { $isMatch = -not $isMatch }
        if ($isMatch) { $found = $l }
    }
    if ($l -eq $header) { $inBlock = $true }
    if ($inBlock -and $l -eq '') { $inBlock = $false }
}

$found
