$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent

function Draw-RoundedRect($graphics, $color, $x, $y, $width, $height, $radius) {
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $d = $radius * 2
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc(($x + $width - $d), $y, $d, $d, 270, 90)
    $path.AddArc(($x + $width - $d), ($y + $height - $d), $d, $d, 0, 90)
    $path.AddArc($x, ($y + $height - $d), $d, $d, 90, 90)
    $path.CloseFigure()
    $brush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($color))
    $graphics.FillPath($brush, $path)
    $brush.Dispose()
    $path.Dispose()
}

function Write-Icon([string]$relativePath, [int]$size, [bool]$foreground = $false) {
    $bitmap = [System.Drawing.Bitmap]::new(2048, 2048)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear($(if ($foreground) { [System.Drawing.Color]::Transparent } else { [System.Drawing.ColorTranslator]::FromHtml('#E3ECFB') }))
    $g.ScaleTransform(10.24, 10.24)
    # Preserve the face geometry of assets/character.svg, centered for launcher masks.
    $g.TranslateTransform(100, 100)
    $scale = if ($foreground) { 0.72 } else { 1.05 }
    $g.ScaleTransform($scale, $scale)
    $g.TranslateTransform(-100, -110)
    Draw-RoundedRect $g '#0047BA' 40 56 120 108 34
    Draw-RoundedRect $g '#E3ECFB' 56 76 88 58 22
    $ink = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#0B1B33'))
    $g.FillEllipse($ink, 75, 97, 14, 14)
    $g.FillEllipse($ink, 111, 97, 14, 14)
    $pen = [System.Drawing.Pen]::new($ink.Color, 4)
    $pen.StartCap = 'Round'
    $pen.EndCap = 'Round'
    $g.DrawBezier($pen, 88, 120, 96, 125.333, 104, 125.333, 112, 120)
    $g.Dispose()
    $ink.Dispose()
    $pen.Dispose()
    $format = if ($foreground) { [System.Drawing.Imaging.PixelFormat]::Format32bppArgb } else { [System.Drawing.Imaging.PixelFormat]::Format24bppRgb }
    $result = [System.Drawing.Bitmap]::new($size, $size, $format)
    $resizer = [System.Drawing.Graphics]::FromImage($result)
    $resizer.InterpolationMode = 'HighQualityBicubic'
    $resizer.DrawImage($bitmap, 0, 0, $size, $size)
    $path = Join-Path $root $relativePath
    [System.IO.Directory]::CreateDirectory((Split-Path $path -Parent)) | Out-Null
    $result.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $resizer.Dispose()
    $result.Dispose()
    $bitmap.Dispose()
}

Write-Icon 'assets/app_icon.png' 1024
$densities = @{ mdpi = 48; hdpi = 72; xhdpi = 96; xxhdpi = 144; xxxhdpi = 192 }
foreach ($density in $densities.Keys) {
    Write-Icon "android/app/src/main/res/mipmap-$density/ic_launcher.png" $densities[$density]
    Write-Icon "android/app/src/main/res/mipmap-$density/ic_launcher_foreground.png" ($densities[$density] * 2.25) $true
}
$catalog = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
$contents = Get-Content (Join-Path $root "$catalog/Contents.json") -Raw | ConvertFrom-Json
foreach ($entry in $contents.images) {
    $size = [double]($entry.size.Split('x')[0]) * [double]($entry.scale.TrimEnd('x'))
    Write-Icon "$catalog/$($entry.filename)" ([int]$size)
}
foreach ($size in 192, 512) {
    Write-Icon "web/icons/Icon-$size.png" $size
    Write-Icon "web/icons/Icon-maskable-$size.png" $size
}
Write-Icon 'web/favicon.png' 32
Write-Output 'Generated Builder launcher icons for Android, iOS and web.'
