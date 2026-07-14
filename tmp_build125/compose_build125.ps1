$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$border = [System.Drawing.Bitmap]::FromFile((Resolve-Path 'assets/icons/app_icon_build124.png'))
$internal = [System.Drawing.Bitmap]::FromFile((Resolve-Path 'tmp_build125/app_icon_old.png'))
$out = [System.Drawing.Bitmap]::FromFile((Resolve-Path 'tmp_build125/app_icon_old.png'))

if ($border.Width -ne $internal.Width -or $border.Height -ne $internal.Height) {
  throw "Source size mismatch"
}

$w = $border.Width
$h = $border.Height
$band = 60
$outPath = Join-Path (Get-Location) 'assets/icons/app_icon_build125.png'

for ($y = 0; $y -lt $h; $y++) {
  for ($x = 0; $x -lt $w; $x++) {
    if ($x -lt $band -or $x -ge ($w - $band) -or $y -lt $band -or $y -ge ($h - $band)) {
      $out.SetPixel($x, $y, $border.GetPixel($x, $y))
      continue
    }

    $c = $out.GetPixel($x, $y)
    if ($c.A -ne 255) {
      continue
    }

    if ($c.R -le 70 -and $c.G -le 70 -and $c.B -le 70) {
      $out.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, 0, 0, 0))
      continue
    }

    if ($c.R -ge 120 -and $c.R -le 232 -and $c.G -ge 95 -and $c.G -le 210 -and $c.B -ge 70 -and $c.B -le 170) {
      $r = [Math]::Min(255, $c.R + 6)
      $g = [Math]::Min(255, $c.G + 4)
      $b = [Math]::Max(0, $c.B - 2)
      $out.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $r, $g, $b))
    }
  }
}

$out.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)

function Emit([string] $name, [System.Drawing.Bitmap] $bmp, [int] $x, [int] $y) {
  $c = $bmp.GetPixel($x, $y)
  Write-Output ("{0}@({1},{2})={3},{4},{5}" -f $name, $x, $y, $c.R, $c.G, $c.B)
}

Emit 'build124_black_probe' $border 155 144
Emit 'build125_black_probe' $out 155 144
Emit 'build124_gold_probe' $border 747 200
Emit 'build125_gold_probe' $out 747 200
Emit 'build124_black_probe2' $border 176 176
Emit 'build125_black_probe2' $out 176 176
Emit 'build124_black_probe3' $border 1109 145
Emit 'build125_black_probe3' $out 1109 145
Emit 'build124_edge_probe' $border 0 0
Emit 'build125_edge_probe' $out 0 0

$border.Dispose()
$internal.Dispose()
$out.Dispose()
