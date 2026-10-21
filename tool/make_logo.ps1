# Generates the placeholder Meer Cafe logo (PNG) and Windows app icon (ICO).
# Replace assets\images\logo.png with the real logo and re-run this script to rebuild the icon.
#   powershell -ExecutionPolicy Bypass -File tool\make_logo.ps1
param([string]$Root = (Split-Path -Parent $PSScriptRoot))
Add-Type -AssemblyName System.Drawing

$gold  = [System.Drawing.Color]::FromArgb(255, 212, 175, 55)
$gold2 = [System.Drawing.Color]::FromArgb(255, 245, 215, 110)
$black = [System.Drawing.Color]::FromArgb(255, 14, 14, 14)

function New-Logo([int]$size, [bool]$withText) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear([System.Drawing.Color]::Transparent)
    $m = [math]::Max(1, [int]($size * 0.03))
    $g.FillEllipse((New-Object System.Drawing.SolidBrush $black), $m, $m, $size - 2*$m, $size - 2*$m)
    $pen = New-Object System.Drawing.Pen $gold, ([math]::Max(1.5, $size * 0.045))
    $r = [int]($size * 0.08)
    $g.DrawEllipse($pen, $r, $r, $size - 2*$r, $size - 2*$r)
    # Coffee cup
    $cupBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Point 0, 0), (New-Object System.Drawing.Point $size, $size), $gold2, $gold
    if ($withText) { $cw = $size * 0.28; $ch = $size * 0.15; $cy = $size * 0.245 }
    else { $cw = $size * 0.36; $ch = $size * 0.22; $cy = $size * 0.36 }
    $cx = ($size - $cw) / 2 - $size * 0.03
    $g.FillPie($cupBrush, [single]$cx, [single]($cy - $ch), [single]$cw, [single]($ch * 2), 0, 180)
    $hp = New-Object System.Drawing.Pen $gold, ([math]::Max(1.2, $size * 0.03))
    $g.DrawArc($hp, [single]($cx + $cw * 0.82), [single]($cy + $ch * 0.05), [single]($cw * 0.32), [single]($ch * 0.6), -90, 180)
    # steam
    $sp = New-Object System.Drawing.Pen $gold2, ([math]::Max(1, $size * 0.02))
    for ($i = 0; $i -lt 3; $i++) {
        $sx = $cx + $cw * (0.25 + 0.25 * $i)
        $g.DrawBezier($sp, [single]$sx, [single]($cy - $size*0.02), [single]($sx - $size*0.03), [single]($cy - $size*0.06), [single]($sx + $size*0.03), [single]($cy - $size*0.09), [single]$sx, [single]($cy - $size*0.13))
    }
    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    if ($withText) {
        $f1 = New-Object System.Drawing.Font 'Georgia', ([single]($size * 0.17)), ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
        $g.DrawString('MEER', $f1, (New-Object System.Drawing.SolidBrush $gold), (New-Object System.Drawing.RectangleF 0, ([single]($size*0.40)), $size, ([single]($size*0.2))), $sf)
        $f2 = New-Object System.Drawing.Font 'Segoe UI', ([single]($size * 0.085)), ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
        $g.DrawString('C A F E', $f2, (New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)), (New-Object System.Drawing.RectangleF 0, ([single]($size*0.58)), $size, ([single]($size*0.12))), $sf)
        $f3 = New-Object System.Drawing.Font 'Segoe UI', ([single]($size * 0.042)), ([System.Drawing.FontStyle]::Italic), ([System.Drawing.GraphicsUnit]::Pixel)
        $g.DrawString('Our Circle. Your Place.', $f3, (New-Object System.Drawing.SolidBrush $gold2), (New-Object System.Drawing.RectangleF 0, ([single]($size*0.70)), $size, ([single]($size*0.08))), $sf)
    } else {
        $f1 = New-Object System.Drawing.Font 'Georgia', ([single]($size * 0.30)), ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
        $g.DrawString('M', $f1, (New-Object System.Drawing.SolidBrush $gold), (New-Object System.Drawing.RectangleF 0, ([single]($size*0.42)), $size, ([single]($size*0.36))), $sf)
    }
    $g.Dispose()
    return $bmp
}

$img = Join-Path $Root 'assets\images'
New-Item -ItemType Directory -Force $img | Out-Null
$logoPath = Join-Path $img 'logo.png'
if (-not (Test-Path $logoPath)) {
    $logo = New-Logo 1024 $true
    $logo.Save($logoPath, [System.Drawing.Imaging.ImageFormat]::Png); $logo.Dispose()
}
$src = [System.Drawing.Image]::FromFile($logoPath)

# Build a multi-size ICO (PNG-compressed entries).
$sizes = 16, 24, 32, 48, 64, 128, 256
$pngs = @()
foreach ($s in $sizes) {
    if ($s -le 48) { $b = New-Logo $s $false } else {
        $b = New-Object System.Drawing.Bitmap $s, $s
        $g = [System.Drawing.Graphics]::FromImage($b); $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'AntiAlias'
        $g.DrawImage($src, 0, 0, $s, $s); $g.Dispose()
    }
    $ms = New-Object System.IO.MemoryStream; $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose()
    $pngs += ,($ms.ToArray())
}
$src.Dispose()
$icoPath = Join-Path $Root 'windows\runner\resources\app_icon.ico'
$fs = [System.IO.File]::Create($icoPath); $w = New-Object System.IO.BinaryWriter $fs
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $d = if ($s -ge 256) { 0 } else { $s }
    $w.Write([byte]$d); $w.Write([byte]$d); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $w.Write($p) }
$w.Close(); $fs.Close()
Write-Host "Logo: $logoPath"; Write-Host "Icon: $icoPath"
