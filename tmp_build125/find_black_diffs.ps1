$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$a = [System.Drawing.Bitmap]::FromFile((Resolve-Path 'assets/icons/app_icon_build124.png'))
$b = [System.Drawing.Bitmap]::FromFile((Resolve-Path 'assets/icons/app_icon_build125.png'))
$w = $a.Width
$h = $a.Height
$found = 0

for ($y = 60; $y -lt ($h - 60) -and $found -lt 12; $y++) {
  for ($x = 60; $x -lt ($w - 60) -and $found -lt 12; $x++) {
    $ca = $a.GetPixel($x, $y)
    $cb = $b.GetPixel($x, $y)
    if ($cb.A -eq 255 -and $cb.R -le 2 -and $cb.G -le 2 -and $cb.B -le 2 -and ($ca.R -gt $cb.R -or $ca.G -gt $cb.G -or $ca.B -gt $cb.B)) {
      Write-Output ("blackDiff@({0},{1}) B124={2},{3},{4} B125={5},{6},{7}" -f $x, $y, $ca.R, $ca.G, $ca.B, $cb.R, $cb.G, $cb.B)
      $found++
    }
  }
}

$a.Dispose()
$b.Dispose()
