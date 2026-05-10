# Compress 9 photos from C:\Users\Igorb\Desktop\Banheiro quadrado
# - All 9 -> /site-build/images/case-studies/geometric-bathroom-london/  (1600px wide, q85)
# - Photo 6.jpeg -> /site-build/images/bathroom-4.jpg                    (1600px wide, q85, hero)
#
# Usage (from site-build folder, Windows PowerShell 5.1):
#   powershell.exe -File ".\compress-geometric-bathroom.ps1"

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$src = "C:\Users\Igorb\Desktop\Banheiro quadrado"
$dst = Join-Path $PSScriptRoot "images\case-studies\geometric-bathroom-london"
$hero = Join-Path $PSScriptRoot "images\bathroom-4.jpg"

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

function Resize-And-Save {
    param([string]$inFile, [string]$outFile)

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
        Write-Host ("OK  {0,-20} -> {1,-60} ({2}x{3}, {4} KB)" -f (Split-Path $inFile -Leaf), (Split-Path $outFile -Leaf), $newW, $newH, $sizeKB)
    } finally {
        $img.Dispose()
    }
}

# 1. Compress all 9 photos into the case-study folder
Get-ChildItem -Path $src -Filter "*.jpeg" | ForEach-Object {
    $outName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name) + ".jpg"
    $outFile = Join-Path $dst $outName
    Resize-And-Save -inFile $_.FullName -outFile $outFile
}

# 2. Compress 6.jpeg also as bathroom-4.jpg (portfolio hero)
$heroSrc = Join-Path $src "6.jpeg"
if (Test-Path $heroSrc) {
    Resize-And-Save -inFile $heroSrc -outFile $hero
} else {
    Write-Host "WARNING: $heroSrc not found - hero image not generated"
}

Write-Host ""
Write-Host "Done."
Write-Host "Case study photos: $dst"
Write-Host "Portfolio hero:    $hero"
