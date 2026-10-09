param([switch]$MobileOnly)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root 'assets\branding\whatsgram_logo.png'
if (!(Test-Path $source)) { throw 'Place your original PNG in assets/branding/whatsgram_logo.png first.' }
$original = [System.Drawing.Image]::FromFile($source)
function Get-IconPng([int]$Size, [double]$Padding = 0.10) {
    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $available = $Size * (1 - 2 * $Padding)
    $ratio = [Math]::Min($available / $original.Width, $available / $original.Height)
    $width = [int]($original.Width * $ratio)
    $height = [int]($original.Height * $ratio)
    $graphics.DrawImage($original, [int](($Size-$width)/2), [int](($Size-$height)/2), $width, $height)
    $stream = [System.IO.MemoryStream]::new()
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $stream.ToArray()
    $graphics.Dispose(); $bitmap.Dispose(); $stream.Dispose()
    return ,$bytes
}
try {
    $mobileSource = Join-Path $root 'assets\branding\android_launcher.png'
    if (Test-Path $mobileSource) {
        $original.Dispose()
        $original = [System.Drawing.Image]::FromFile($mobileSource)
    }
    $densities = @{mdpi=48;hdpi=72;xhdpi=96;xxhdpi=144;xxxhdpi=192}
    foreach ($entry in $densities.GetEnumerator()) {
        $directory = Join-Path $root "android\app\src\main\res\mipmap-$($entry.Key)"
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $directory 'ic_launcher.png'), (Get-IconPng $entry.Value))
    }
    $foreground = Join-Path $root 'android\app\src\main\res\drawable-nodpi'
    New-Item -ItemType Directory -Path $foreground -Force | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $foreground 'launcher_foreground.png'), (Get-IconPng 432 0.20))
    if ($MobileOnly) { Write-Output 'Updated Android launcher icons only.'; return }
    $original.Dispose()
    $original = [System.Drawing.Image]::FromFile($source)
    $sizes = @(16,24,32,48,64,128,256)
    $pngs = @($sizes | ForEach-Object { ,(Get-IconPng $_ 0.04) })
    $icon = Join-Path $root 'windows\runner\resources\app_icon.ico'
    $stream = [System.IO.File]::Create($icon)
    $writer = [System.IO.BinaryWriter]::new($stream)
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($i=0; $i -lt $sizes.Count; $i++) {
        $dimension = if ($sizes[$i] -eq 256) { 0 } else { $sizes[$i] }
        $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
        $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([uint16]1); $writer.Write([uint16]32)
        $writer.Write([uint32]$pngs[$i].Length); $writer.Write([uint32]$offset)
        $offset += $pngs[$i].Length
    }
    foreach ($png in $pngs) { $writer.Write([byte[]]$png) }
    $writer.Dispose(); $stream.Dispose()
    Write-Output 'Generated padded Android icons and seven-size Windows ICO. Original PNG unchanged.'
} finally { $original.Dispose() }
