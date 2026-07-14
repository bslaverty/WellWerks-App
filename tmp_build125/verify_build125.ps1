$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Hex([System.Drawing.Color] $c) {
  return ('#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B)
}

function Probe([string] $name, [System.Drawing.Bitmap] $bmp, [int] $x, [int] $y) {
  $c = $bmp.GetPixel($x, $y)
  Write-Output ("{0}@({1},{2}) RGB=({3},{4},{5}) HEX={6} A={7}" -f $name, $x, $y, $c.R, $c.G, $c.B, (Hex $c), $c.A)
}

function EdgeAlpha([System.Drawing.Bitmap] $bmp) {
  $w = $bmp.Width
  $h = $bmp.Height
  $total = (2 * $w) + (2 * $h) - 4
  $opaque = 0
  for ($x = 0; $x -lt $w; $x++) {
    if ($bmp.GetPixel($x, 0).A -eq 255) { $opaque++ }
    if ($bmp.GetPixel($x, $h - 1).A -eq 255) { $opaque++ }
  }
  for ($y = 1; $y -lt $h - 1; $y++) {
    if ($bmp.GetPixel(0, $y).A -eq 255) { $opaque++ }
    if ($bmp.GetPixel($w - 1, $y).A -eq 255) { $opaque++ }
  }
  return "${opaque}/${total}"
}

function EdgeDiffCount([System.Drawing.Bitmap] $a, [System.Drawing.Bitmap] $b) {
  $w = $a.Width
  $h = $a.Height
  $diff = 0
  for ($x = 0; $x -lt $w; $x++) {
    $ca = $a.GetPixel($x, 0)
    $cb = $b.GetPixel($x, 0)
    if ($ca.R -ne $cb.R -or $ca.G -ne $cb.G -or $ca.B -ne $cb.B -or $ca.A -ne $cb.A) { $diff++ }
    $ca = $a.GetPixel($x, $h - 1)
    $cb = $b.GetPixel($x, $h - 1)
    if ($ca.R -ne $cb.R -or $ca.G -ne $cb.G -or $ca.B -ne $cb.B -or $ca.A -ne $cb.A) { $diff++ }
  }
  for ($y = 1; $y -lt $h - 1; $y++) {
    $ca = $a.GetPixel(0, $y)
    $cb = $b.GetPixel(0, $y)
    if ($ca.R -ne $cb.R -or $ca.G -ne $cb.G -or $ca.B -ne $cb.B -or $ca.A -ne $cb.A) { $diff++ }
    $ca = $a.GetPixel($w - 1, $y)
    $cb = $b.GetPixel($w - 1, $y)
    if ($ca.R -ne $cb.R -or $ca.G -ne $cb.G -or $ca.B -ne $cb.B -or $ca.A -ne $cb.A) { $diff++ }
  }
  return $diff
}

$b124 = [System.Drawing.Bitmap]::FromFile((Resolve-Path 'assets/icons/app_icon_build124.png'))
$b125 = [System.Drawing.Bitmap]::FromFile((Resolve-Path 'assets/icons/app_icon_build125.png'))
$ios180Path = Resolve-Path 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png'
$ios1024Path = Resolve-Path 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png'
$i180 = [System.Drawing.Bitmap]::FromFile($ios180Path)
$i1024 = [System.Drawing.Bitmap]::FromFile($ios1024Path)

Write-Output ("master124Path={0}" -f (Resolve-Path 'assets/icons/app_icon_build124.png'))
Write-Output ("master125Path={0}" -f (Resolve-Path 'assets/icons/app_icon_build125.png'))
Write-Output ("master125Size={0}x{1}" -f $b125.Width, $b125.Height)
Write-Output ("ios180Path={0}" -f $ios180Path)
Write-Output ("ios180Size={0}x{1}" -f $i180.Width, $i180.Height)
Write-Output ("ios1024Path={0}" -f $ios1024Path)
Write-Output ("ios1024Size={0}x{1}" -f $i1024.Width, $i1024.Height)

Probe 'build124_black_master' $b124 1109 145
Probe 'build125_black_master' $b125 1109 145
Probe 'build124_gold_master' $b124 747 200
Probe 'build125_gold_master' $b125 747 200
Probe 'build125_edge_master' $b125 0 0
Probe 'build125_black_ios180' $i180 159 21
Probe 'build125_gold_ios180' $i180 107 29
Probe 'build125_edge_ios180' $i180 0 0

Write-Output ("edgeAlpha124={0}" -f (EdgeAlpha $b124))
Write-Output ("edgeAlpha125={0}" -f (EdgeAlpha $b125))
Write-Output ("edgeAlpha180={0}" -f (EdgeAlpha $i180))
Write-Output ("edgeDiff124to125={0}" -f (EdgeDiffCount $b124 $b125))

$b124.Dispose()
$b125.Dispose()
$i180.Dispose()
$i1024.Dispose()
