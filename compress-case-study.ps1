# Compress 15 case-study photos from C:\Users\Igorb\Desktop\Banheiro verde
# to /site-build/images/case-studies/bathroom-london/ as .jpg at max 1600px wide, 85% quality.
#
# Usage (from site-build folder):
#   .\compress-case-study.ps1

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$src = "C:\Users\Igorb\Desktop\Banheiro verde"
$dst = Join-Path $PSScriptRoot "images\case-studies\bathroom-london"

if (-not (Test-Path $dst)) {
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
}

$maxWidth = 1600
$quality  = 85L

$encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
    Where-Object { $_.MimeType -eq "image/jpeg" }
$params = New-Object System.Drawing.Imaging.EncoderParameters(1)
$params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
    [System.Drawing.Imaging.Encoder]::Quality, $quality
)

Get-ChildItem -Path $src -Filter "*.jpeg" | ForEach-Object {
    $inFile  = $_.FullName
    $outName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name) + ".jpg"
    $outFile = Join-Path $dst $outName

    $img = [System.Drawing.Image]::FromFile($inFile)
    try {
        $w = $img.Width
        $h = $img.Height
        if ($w -gt $maxWidth) {
            $newW = $maxWidth
            $newH = [int]([double]$h * $maxWidth / $w)
        } else {
            $newW = $w
            $newH = $h
        }

        $bmp = New-Object System.Drawing.Bitmap($newW, $newH)
        $g   = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.DrawImage($img, 0, 0, $newW, $newH)
        $g.Dispose()

        $bmp.Save($outFile, $encoder, $params)
        $bmp.Dispose()

        $sizeKB = [int]((Get-Item $outFile).Length / 1024)
        Write-Host "OK  $($_.Name) -> $outName  (${newW}x${newH}, ${sizeKB} KB)"
    } finally {
        $img.Dispose()
    }
}

Write-Host ""
Write-Host "Done. Output: $dst"
