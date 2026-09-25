param()

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$installed = 'D:\Games\World of Warcraft\_retail_\Interface\AddOns\WaffleHouse_EllesmereUI'
$publicMarker = '## X-WaffleHouse-FlightIndicatorDefault: 0'
$ownerMarker = '## X-WaffleHouse-FlightIndicatorDefault: 1'
$publicTransmogMarker = '## X-WaffleHouse-RandomTransmogDefault: 0'
$ownerTransmogMarker = '## X-WaffleHouse-RandomTransmogDefault: 1'
$publicTransmogButtonMarker = '## X-WaffleHouse-RandomTransmogButtonDefault: 0'
$ownerTransmogButtonMarker = '## X-WaffleHouse-RandomTransmogButtonDefault: 1'

if (-not (Test-Path -LiteralPath $installed -PathType Container)) {
    throw "Installed addon folder not found: $installed"
}

$tocName = 'WaffleHouse_EllesmereUI.toc'
$toc = Get-Content -LiteralPath (Join-Path $source $tocName) -Raw
if ($toc.IndexOf($publicMarker, [StringComparison]::Ordinal) -lt 0) {
    throw 'Public flight-indicator default marker is missing from the source TOC.'
}
if ($toc.IndexOf($publicTransmogMarker, [StringComparison]::Ordinal) -lt 0) {
    throw 'Public random-transmog default marker is missing from the source TOC.'
}
if ($toc.IndexOf($publicTransmogButtonMarker, [StringComparison]::Ordinal) -lt 0) {
    throw 'Public random-transmog button default marker is missing from the source TOC.'
}
$localToc = $toc.Replace($publicMarker, $ownerMarker).Replace($publicTransmogMarker, $ownerTransmogMarker).Replace($publicTransmogButtonMarker, $ownerTransmogButtonMarker)

# Only deploy completed source changes; preserve unrelated installed files.
# Source TOC defaults remain off for public users.
foreach ($name in @('WaffleHouse_EllesmereUI.lua', 'WaffleHouse_Adventure.lua', 'WaffleHouse_FlightIndicator.lua', 'WaffleHouse_RandomTransmog.lua', 'WaffleHouse_BagSlotFreeze.lua', 'WaffleHouse_Slash.lua')) {
    Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $installed $name) -Force
}

foreach ($name in @('button-back.png', 'button-front.png', 'button-gem.png', 'button-fill-atlas.png')) {
    $sourceTransmogArt = Join-Path $source "Media\RandomTransmog\$name"
    $installedTransmogArt = Join-Path $installed "Media\RandomTransmog\$name"
    New-Item -ItemType Directory -Path (Split-Path -Parent $installedTransmogArt) -Force | Out-Null
    Copy-Item -LiteralPath $sourceTransmogArt -Destination $installedTransmogArt -Force
    if ((Get-FileHash -LiteralPath $sourceTransmogArt -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $installedTransmogArt -Algorithm SHA256).Hash) {
        throw "Random-transmog art deployment mismatch: $name"
    }
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
for ($index = 1; $index -le 20; $index++) {
    $name = 'creature-{0:d2}.png' -f $index
    Copy-Item -LiteralPath (Join-Path $sourceArt $name) -Destination (Join-Path $installedArt $name) -Force
    if ((Get-FileHash -LiteralPath (Join-Path $sourceArt $name) -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $installedArt $name) -Algorithm SHA256).Hash) {
        throw "Art deployment mismatch: $name"
    }
}
for ($index = 1; $index -le 4; $index++) {
    $name = 'turn-{0:d2}.png' -f $index
    Copy-Item -LiteralPath (Join-Path $sourceArt $name) -Destination (Join-Path $installedArt $name) -Force
    if ((Get-FileHash -LiteralPath (Join-Path $sourceArt $name) -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $installedArt $name) -Algorithm SHA256).Hash) {
        throw "Art deployment mismatch: $name"
    }
}
for ($gap = 1; $gap -le 19; $gap++) {
    $suffixes = if ($gap -ge 6 -and $gap -le 10) {
        if ($gap -eq 9) { @('50', '67') } else { @('33', '67') }
    } else { @('50') }
    foreach ($suffix in $suffixes) {
        $name = 'morph-g{0:d2}-{1}.png' -f $gap, $suffix
        Copy-Item -LiteralPath (Join-Path $sourceArt $name) -Destination (Join-Path $installedArt $name) -Force
        if ((Get-FileHash -LiteralPath (Join-Path $sourceArt $name) -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath (Join-Path $installedArt $name) -Algorithm SHA256).Hash) {
            throw "Art deployment mismatch: $name"
        }
    }
}
foreach ($name in @('empty-skyriding.png', 'empty-steady.png', 'compact-housing.png', 'compact-steady.png', 'compact-skyride.png', 'compact-alternate-steady.png', 'compact-alternate-skyride.png')) {
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
if (-not (Select-String -LiteralPath (Join-Path $installed $tocName) -SimpleMatch $ownerTransmogMarker)) {
    throw 'The local random-transmog owner-default marker was not deployed.'
}
if (-not (Select-String -LiteralPath (Join-Path $installed $tocName) -SimpleMatch $ownerTransmogButtonMarker)) {
    throw 'The local random-transmog button owner-default marker was not deployed.'
}

Write-Output 'Waffle House completed changes deployed with owner flight and transmog defaults on; source/public defaults remain off.'
