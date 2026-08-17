param(
  [string]$SourceDirectory = 'C:\Users\subai\Pictures\Screenshots',
  [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\steam\assets\screenshots')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$targetWidth = 1920
$targetHeight = 1080
$targetRatio = $targetWidth / $targetHeight
$canvasColor = [System.Drawing.Color]::FromArgb(255, 13, 25, 35)

$screenshots = @(
  @{
    Source = 'Screenshot 2026-08-12 225815.png'
    Destination = '01-library-grid.png'
    Mode = 'Cover'
    TrimTop = 0
    AnchorY = 0.5
  },
  @{
    Source = 'Screenshot 2026-08-12 225855.png'
    Destination = '02-library-details.png'
    Mode = 'Contain'
    TrimTop = 22
    AnchorY = 0.5
  },
  @{
    Source = 'Screenshot 2026-08-12 225914.png'
    Destination = '03-compression-inventory.png'
    Mode = 'Contain'
    TrimTop = 0
    AnchorY = 0.5
  },
  @{
    Source = 'Screenshot 2026-08-12 225827.png'
    Destination = '04-game-details.png'
    Mode = 'Cover'
    TrimTop = 0
    AnchorY = 0.5
  },
  @{
    Source = 'Screenshot 2026-08-12 230658.png'
    Destination = '05-settings-and-automation.png'
    Mode = 'Cover'
    TrimTop = 0
    AnchorY = 0.4
  }
)

function Export-SteamScreenshot {
  param(
    [Parameter(Mandatory)] [string]$SourcePath,
    [Parameter(Mandatory)] [string]$DestinationPath,
    [Parameter(Mandatory)] [ValidateSet('Cover', 'Contain')] [string]$Mode,
    [Parameter(Mandatory)] [int]$TrimTop,
    [Parameter(Mandatory)] [double]$AnchorY
  )

  if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Screenshot not found: $SourcePath"
  }

  $source = [System.Drawing.Bitmap]::FromFile($SourcePath)
  try {
    if ($TrimTop -lt 0 -or $TrimTop -ge $source.Height) {
      throw "Invalid top trim $TrimTop for $SourcePath"
    }

    $availableWidth = $source.Width
    $availableHeight = $source.Height - $TrimTop
    $sourceX = 0
    $sourceY = $TrimTop
    $sourceWidth = $availableWidth
    $sourceHeight = $availableHeight

    if ($Mode -eq 'Cover') {
      $sourceRatio = $availableWidth / $availableHeight
      if ($sourceRatio -gt $targetRatio) {
        $sourceWidth = [int][math]::Floor($availableHeight * $targetRatio)
        $sourceX = [int][math]::Round(($availableWidth - $sourceWidth) / 2)
      } elseif ($sourceRatio -lt $targetRatio) {
        $sourceHeight = [int][math]::Floor($availableWidth / $targetRatio)
        $remainingHeight = $availableHeight - $sourceHeight
        $sourceY = $TrimTop + [int][math]::Round($remainingHeight * $AnchorY)
      }
      $destinationX = 0
      $destinationY = 0
      $destinationWidth = $targetWidth
      $destinationHeight = $targetHeight
    } else {
      $scale = [math]::Min($targetWidth / $availableWidth, $targetHeight / $availableHeight)
      $destinationWidth = [int][math]::Round($availableWidth * $scale)
      $destinationHeight = [int][math]::Round($availableHeight * $scale)
      $destinationX = [int][math]::Round(($targetWidth - $destinationWidth) / 2)
      $destinationY = [int][math]::Round(($targetHeight - $destinationHeight) / 2)
    }

    $output = New-Object System.Drawing.Bitmap($targetWidth, $targetHeight, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    try {
      $graphics = [System.Drawing.Graphics]::FromImage($output)
      try {
        $graphics.Clear($canvasColor)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $destinationRectangle = New-Object System.Drawing.Rectangle($destinationX, $destinationY, $destinationWidth, $destinationHeight)
        $graphics.DrawImage(
          $source,
          $destinationRectangle,
          $sourceX,
          $sourceY,
          $sourceWidth,
          $sourceHeight,
          [System.Drawing.GraphicsUnit]::Pixel
        )
      } finally {
        $graphics.Dispose()
      }

      $output.Save($DestinationPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
      $output.Dispose()
    }
  } finally {
    $source.Dispose()
  }
}

$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
[System.IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null

foreach ($screenshot in $screenshots) {
  $sourcePath = Join-Path $SourceDirectory $screenshot.Source
  $destinationPath = Join-Path $resolvedOutputDirectory $screenshot.Destination
  Export-SteamScreenshot `
    -SourcePath $sourcePath `
    -DestinationPath $destinationPath `
    -Mode $screenshot.Mode `
    -TrimTop $screenshot.TrimTop `
    -AnchorY $screenshot.AnchorY
  Write-Host "Prepared $destinationPath"
}
