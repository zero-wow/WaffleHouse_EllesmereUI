param()

$ErrorActionPreference = 'Stop'
$art = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\Media\RandomTransmog')).Path
$utf8 = [System.Text.UTF8Encoding]::new($false)
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
if (-not (Test-Path -LiteralPath $chrome -PathType Leaf)) {
    $chrome = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
}
if (-not (Test-Path -LiteralPath $chrome -PathType Leaf)) {
    throw 'Chromium renderer not found.'
}

function Render-Svg($source, $target, $size) {
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $profile = Join-Path $tempRoot ('wh-transmog-render-' + [Guid]::NewGuid().ToString('N'))
    $resolved = [System.IO.Path]::GetFullPath($profile)
    if (-not $resolved.StartsWith($tempRoot + [System.IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) { throw 'Renderer profile escaped temp directory.' }
    New-Item -ItemType Directory -Path $profile -Force | Out-Null
    try {
        $uri = ([System.Uri]::new($source)).AbsoluteUri
        & $chrome '--headless=new' '--disable-gpu' '--no-first-run' "--user-data-dir=$profile" '--hide-scrollbars' '--default-background-color=00000000' "--window-size=$size,$size" "--screenshot=$target" $uri | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw "Could not render $source"
        }
    } finally {
        Remove-Item -LiteralPath $profile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

foreach ($layer in @('back', 'front', 'gem')) {
    $source = Join-Path $art "button-$layer.svg"
    $target = Join-Path $art "button-$layer.png"
    Render-Svg $source $target 512
}

$atlas = [System.Text.StringBuilder]::new()
[void]$atlas.Append('<svg xmlns="http://www.w3.org/2000/svg" width="2048" height="2048" viewBox="0 0 2048 2048">')
$circumference = 2 * [Math]::PI * 92
for ($frame = 0; $frame -lt 64; $frame++) {
    $x = ($frame % 8) * 256
    $y = [Math]::Floor($frame / 8) * 256
    $length = $circumference * $frame / 63
    [void]$atlas.AppendFormat([System.Globalization.CultureInfo]::InvariantCulture,
        '<g transform="translate({0} {1})"><circle cx="128" cy="128" r="92" fill="none" stroke="#0275e8" stroke-opacity=".55" stroke-width="19" stroke-dasharray="{2:F4} {3:F4}" transform="rotate(-90 128 128)"/><circle cx="128" cy="128" r="92" fill="none" stroke="#54e9ff" stroke-width="12" stroke-dasharray="{2:F4} {3:F4}" transform="rotate(-90 128 128)"/><circle cx="128" cy="128" r="92" fill="none" stroke="#d7ffff" stroke-opacity=".7" stroke-width="3" stroke-dasharray="{2:F4} {3:F4}" transform="rotate(-90 128 128)"/></g>',
        $x, $y, $length, $circumference)
}
[void]$atlas.Append('</svg>')
$atlasSource = Join-Path $art 'button-fill-atlas.svg'
[System.IO.File]::WriteAllText($atlasSource, $atlas.ToString(), $utf8)
$atlasTarget = Join-Path $art 'button-fill-atlas.png'
Render-Svg $atlasSource $atlasTarget 2048

& ffmpeg -y -v error -i (Join-Path $art 'button-back.png') -i $atlasTarget -i (Join-Path $art 'button-front.png') -filter_complex '[1:v]crop=256:256:1792:768,scale=512:512:flags=lanczos[fill];[0:v][fill]overlay=0:0:format=auto[base];[base][2:v]overlay=0:0:format=auto' -frames:v 1 -pix_fmt rgba (Join-Path $art 'button-preview.png')
if ($LASTEXITCODE -ne 0) { throw 'Could not render preview.' }

Write-Output 'Rendered layered random-transmog art and 64-frame channel atlas.'
