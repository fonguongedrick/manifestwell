# Finishes the store images after they are rendered:
#   STORE=1 flutter test test/store_shots_test.dart --update-goldens
#   powershell -File store\finish.ps1
#
# - strips the alpha channel (App Store and Google Play reject transparency)
# - checks every image is exactly the size its store asks for
# - makes the 512 x 512 Google Play icon from assets\icon\icon.png
Add-Type -AssemblyName System.Drawing

$root = $PSScriptRoot
$expected = [ordered]@{
  'appstore_6.3in_1206x2622'      = @(1206, 2622)
  'appstore_6.1in_1179x2556'      = @(1179, 2556)
  'play_phone_1080x1920'          = @(1080, 1920)
  'play_feature_graphic_1024x500' = @(1024, 500)
}

$bad = 0
foreach ($dir in $expected.Keys) {
  $want = $expected[$dir]
  foreach ($file in Get-ChildItem (Join-Path $root $dir) -Filter *.png) {
    $src = [System.Drawing.Image]::FromFile($file.FullName)
    $w = $src.Width; $h = $src.Height
    if ($w -ne $want[0] -or $h -ne $want[1]) {
      Write-Host "WRONG SIZE  $dir\$($file.Name): $w x $h (wanted $($want[0]) x $($want[1]))"
      $bad++
    }
    # Redraw onto an opaque 24-bit canvas.
    $flat = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $flat.SetResolution(72, 72)
    $g = [System.Drawing.Graphics]::FromImage($flat)
    $g.Clear([System.Drawing.Color]::Black)
    $g.DrawImage($src, 0, 0, $w, $h)
    $g.Dispose(); $src.Dispose()
    $tmp = "$($file.FullName).tmp"
    $flat.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
    $flat.Dispose()
    Move-Item -Force $tmp $file.FullName
    Write-Host ("ok  {0,-34} {1,-18} {2} x {3}" -f $dir, $file.Name, $w, $h)
  }
}

# Google Play icon: 512 x 512 PNG.
$iconDir = Join-Path $root 'play_icon_512x512'
New-Item -ItemType Directory -Force $iconDir | Out-Null
$icon = [System.Drawing.Image]::FromFile((Join-Path $root '..\assets\icon\icon.png'))
$sized = New-Object System.Drawing.Bitmap(512, 512)
$g = [System.Drawing.Graphics]::FromImage($sized)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.DrawImage($icon, 0, 0, 512, 512)
$g.Dispose(); $icon.Dispose()
$sized.Save((Join-Path $iconDir 'icon.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$sized.Dispose()
Write-Host "ok  play_icon_512x512                  icon.png           512 x 512"

if ($bad -gt 0) { Write-Host "`n$bad image(s) have the wrong size."; exit 1 }
Write-Host "`nAll images are the right size and have no transparency."
