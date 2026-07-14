$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$a = [System.Drawing.Bitmap]::FromFile((Resolve-Path 'assets/icons/app_icon_build124.png'))
$w = $a.Width
$h = $a.Height
$found = 0
for ($y = 60; $y -lt ($h - 60) -and $found -lt 20; $y++) {
  for ($x = 60; $x -lt ($w - 60) -and $found -lt 20; $x++) {
    $c = $a.GetPixel($x, $y)
    if ($c.A -eq 255 -and $c.R -le 90 -and $c.G -le 90 -and $c.B -le 90 -and ($c.R -gt 0 -or $c.G -gt 0 -or $c.B -gt 0)) {
      Write-Output ("nearBlack@({0},{1})={2},{3},{4}" -f $x,$y,$c.R,$c.G,$c.B)
      $found++
    }
  }
}
$a.Dispose()
