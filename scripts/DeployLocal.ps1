param()

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$installed = 'D:\Games\World of Warcraft\_retail_\Interface\AddOns\WaffleHouse_EllesmereUI'
$publicMarker = '## X-WaffleHouse-FlightIndicatorDefault: 0'
$ownerMarker = '## X-WaffleHouse-FlightIndicatorDefault: 1'

if (-not (Test-Path -LiteralPath $installed -PathType Container)) {
    throw "Installed addon folder not found: $installed"
}

$tocName = 'WaffleHouse_EllesmereUI.toc'
$toc = Get-Content -LiteralPath (Join-Path $source $tocName) -Raw
if ($toc.IndexOf($publicMarker, [StringComparison]::Ordinal) -lt 0) {
    throw 'Public flight-indicator default marker is missing from the source TOC.'
}
$localToc = $toc.Replace($publicMarker, $ownerMarker)

# Only deploy the completed flight-indicator change set; preserve unrelated
# installed files. The source TOC remains off-by-default for public users.
foreach ($name in @('WaffleHouse_EllesmereUI.lua', 'WaffleHouse_Adventure.lua', 'WaffleHouse_FlightIndicator.lua')) {
    Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $installed $name) -Force
}

$sourceArt = Join-Path $source 'Media\FlightStyle'
$installedArt = Join-Path $installed 'Media\FlightStyle'
New-Item -ItemType Directory -Path $installedArt -Force | Out-Null
for ($index = 1; $index -le 16; $index++) {
    $name = 'flight-{0:d2}.png' -f $index
    Copy-Item -LiteralPath (Join-Path $sourceArt $name) -Destination (Join-Path $installedArt $name) -Force
    if ((Get-FileHash -LiteralPath (Join-Path $sourceArt $name) -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $installedArt $name) -Algorithm SHA256).Hash) {
        throw "Art deployment mismatch: $name"
    }
}
foreach ($name in @('wind.png', 'veil.png')) {
    Copy-Item -LiteralPath (Join-Path $sourceArt $name) -Destination (Join-Path $installedArt $name) -Force
    if ((Get-FileHash -LiteralPath (Join-Path $sourceArt $name) -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $installedArt $name) -Algorithm SHA256).Hash) {
        throw "Art deployment mismatch: $name"
    }
}

$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText((Join-Path $installed $tocName), $localToc, $utf8)
if (-not (Select-String -LiteralPath (Join-Path $installed $tocName) -SimpleMatch $ownerMarker)) {
    throw 'The local owner-default marker was not deployed.'
}

Write-Output 'Waffle House flight indicator deployed with owner default on; source/public default remains off.'
