# =============================================================
# ProCraft Phase 5 — Finalise script
# =============================================================
# One-shot Windows-native script that does the three pre-deploy
# steps for the Journal launch:
#   1. Adds "Journal" to the nav across all existing .html pages
#   2. Lints every .html for fabricated prices (£, JSON-LD offers, etc.)
#   3. Regenerates sitemap.xml from the filesystem
#
# Run from the site-build directory:
#   cd "C:\Users\Igorb\Documents\Claude\Projects\ProCraft SEO\site-build"
#   .\phase5-finalise.ps1
#
# This script is idempotent — safe to run multiple times.
# After it reports "ALL CLEAR", run .\deploy.ps1 -Token "ghp_..."
# =============================================================

$ErrorActionPreference = "Stop"
$siteRoot = $PSScriptRoot
if (-not $siteRoot) { $siteRoot = (Get-Location).Path }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ProCraft Phase 5 - Finalise " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Site root: $siteRoot"
Write-Host ""

# -----------------------------------------------------------------
# Step 1: Add "Journal" to nav across all .html pages
# -----------------------------------------------------------------
Write-Host "[1/3] Updating site-wide nav to include Journal..." -ForegroundColor Yellow

$navOldCRLF = "    <li><a href=""/portfolio/"">Portfolio</a></li>`r`n    <li><a href=""/process/"">Process</a></li>"
$navNewCRLF = "    <li><a href=""/portfolio/"">Portfolio</a></li>`r`n    <li><a href=""/journal/"">Journal</a></li>`r`n    <li><a href=""/process/"">Process</a></li>"
$navOldLF   = "    <li><a href=""/portfolio/"">Portfolio</a></li>`n    <li><a href=""/process/"">Process</a></li>"
$navNewLF   = "    <li><a href=""/portfolio/"">Portfolio</a></li>`n    <li><a href=""/journal/"">Journal</a></li>`n    <li><a href=""/process/"">Process</a></li>"

$updated = 0
$skipped = 0
$missing = @()

Get-ChildItem -Path $siteRoot -Filter *.html -Recurse | ForEach-Object {
    $raw = [System.IO.File]::ReadAllText($_.FullName)

    # Already has Journal in nav — skip
    if ($raw.Contains('href="/journal/">Journal</a>')) {
        $skipped++
        return
    }

    $changed = $false
    if ($raw.Contains($navOldCRLF)) {
        $raw = $raw.Replace($navOldCRLF, $navNewCRLF)
        $changed = $true
    } elseif ($raw.Contains($navOldLF)) {
        $raw = $raw.Replace($navOldLF, $navNewLF)
        $changed = $true
    }

    if ($changed) {
        [System.IO.File]::WriteAllText($_.FullName, $raw)
        $updated++
    } else {
        $missing += $_.FullName.Substring($siteRoot.Length + 1)
    }
}

Write-Host "  Updated: $updated file(s)" -ForegroundColor Green
Write-Host "  Skipped (already had Journal): $skipped"
if ($missing.Count -gt 0) {
    Write-Host "  No nav match found in $($missing.Count) file(s):" -ForegroundColor DarkYellow
    foreach ($m in $missing) { Write-Host "    - $m" }
}

# -----------------------------------------------------------------
# Step 2: Lint for fabricated prices
# -----------------------------------------------------------------
Write-Host ""
Write-Host "[2/3] Linting for fabricated prices..." -ForegroundColor Yellow

$forbidden = @(
    @{ Pattern = [char]0x00A3;                   Desc = "GBP currency symbol" },
    @{ Pattern = '"priceRange"';                 Desc = "JSON-LD priceRange key" },
    @{ Pattern = '"priceSpecification"';         Desc = "JSON-LD priceSpecification key" },
    @{ Pattern = '"offers"';                     Desc = "JSON-LD offers key (homepage exception applies)" },
    @{ Pattern = "Investment From";              Desc = "Investment From trust strip" },
    @{ Pattern = "Investment Guide";             Desc = "Investment Guide section" },
    @{ Pattern = "low five figures";             Desc = "vague pricing language" },
    @{ Pattern = "well into six figures";        Desc = "vague pricing language" },
    @{ Pattern = "low six figures";              Desc = "vague pricing language" }
)

# Files that legitimately use "offers" in JSON-LD as itemOffered (homepage OfferCatalog)
$offersExempt = @("index.html")

$violations = @()
$filesScanned = 0

Get-ChildItem -Path $siteRoot -Filter *.html -Recurse | ForEach-Object {
    $filesScanned++
    $rel = $_.FullName.Substring($siteRoot.Length + 1)
    $raw = [System.IO.File]::ReadAllText($_.FullName)
    $lines = $raw -split "`r?`n"

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        foreach ($rule in $forbidden) {
            if ($line.Contains($rule.Pattern)) {
                # Allow "offers" in homepage OfferCatalog (itemOffered structure, no actual prices)
                if ($rule.Pattern -eq '"offers"' -and ($offersExempt -contains $rel)) {
                    continue
                }
                $excerpt = $line.Trim()
                if ($excerpt.Length -gt 120) { $excerpt = $excerpt.Substring(0, 117) + "..." }
                $violations += [pscustomobject]@{
                    File = $rel
                    Line = $i + 1
                    Desc = $rule.Desc
                    Excerpt = $excerpt
                }
            }
        }
    }
}

Write-Host "  Files scanned: $filesScanned"
if ($violations.Count -eq 0) {
    Write-Host "  CLEAN - no price violations." -ForegroundColor Green
} else {
    Write-Host "  FAIL - $($violations.Count) violation(s):" -ForegroundColor Red
    foreach ($v in $violations) {
        Write-Host "    $($v.File):$($v.Line) - $($v.Desc)" -ForegroundColor Red
        Write-Host "      > $($v.Excerpt)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "Fix these before deploying. See references/pricing-rule.md." -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------
# Step 3: Regenerate sitemap.xml
# -----------------------------------------------------------------
Write-Host ""
Write-Host "[3/3] Regenerating sitemap.xml..." -ForegroundColor Yellow

$domain = "https://www.procraftrefurbishment.co.uk"
$today = (Get-Date -Format "yyyy-MM-dd")

$serviceMoney = @(
    "/bespoke-kitchens/", "/luxury-bathrooms/", "/premium-flooring/",
    "/full-house-refurbishment/", "/bespoke-carpentry/", "/painting-decorating/"
)

function Get-UrlPriority($url) {
    if ($url -eq "/")                  { return @(1.0, "weekly") }
    if ($url -eq "/services/")         { return @(0.9, "monthly") }
    if ($serviceMoney -contains $url)  { return @(0.9, "monthly") }
    if ($url -eq "/areas/")            { return @(0.8, "monthly") }
    if ($url -eq "/portfolio/")        { return @(0.8, "monthly") }
    if ($url -eq "/contact/")          { return @(0.8, "monthly") }
    if ($url -eq "/about/")            { return @(0.7, "monthly") }
    if ($url -eq "/process/")          { return @(0.7, "monthly") }
    if ($url -eq "/testimonials/")     { return @(0.7, "monthly") }
    if ($url -eq "/faq/")              { return @(0.6, "monthly") }
    if ($url -eq "/journal/")          { return @(0.7, "weekly") }

    # Area hubs: /areas/{area}/
    if ($url -like "/areas/*/" -and ($url.Split("/").Count - 1) -eq 3) {
        return @(0.85, "monthly")
    }
    # Journal posts: /journal/{slug}/
    if ($url -like "/journal/*/" -and ($url.Split("/").Count - 1) -eq 3) {
        return @(0.7, "weekly")
    }
    # Service+area combo: /{service}/{area}/
    $parts = $url.Trim("/").Split("/")
    if ($parts.Count -eq 2 -and ($serviceMoney -contains "/$($parts[0])/")) {
        return @(0.8, "monthly")
    }
    return @(0.5, "monthly")
}

$urls = @()
Get-ChildItem -Path $siteRoot -Filter "index.html" -Recurse | ForEach-Object {
    $rel = $_.FullName.Substring($siteRoot.Length + 1).Replace("\", "/")
    if ($rel -eq "index.html") {
        $urls += "/"
    } else {
        $urls += "/" + $rel.Substring(0, $rel.Length - "index.html".Length)
    }
}

# Sort by priority desc, then alpha
$urls = $urls | Sort-Object @{ Expression = { -1 * (Get-UrlPriority $_)[0] } }, @{ Expression = { $_ } }

$xmlLines = @()
$xmlLines += '<?xml version="1.0" encoding="UTF-8"?>'
$xmlLines += '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
foreach ($u in $urls) {
    $p = Get-UrlPriority $u
    $prio = $p[0]; $freq = $p[1]
    $xmlLines += "  <url><loc>$domain$u</loc><lastmod>$today</lastmod><changefreq>$freq</changefreq><priority>$prio</priority></url>"
}
$xmlLines += '</urlset>'

$sitemapPath = Join-Path $siteRoot "sitemap.xml"
[System.IO.File]::WriteAllText($sitemapPath, ($xmlLines -join "`n") + "`n", [System.Text.Encoding]::UTF8)

Write-Host "  Wrote $sitemapPath ($($urls.Count) URLs)" -ForegroundColor Green

# -----------------------------------------------------------------
# Done
# -----------------------------------------------------------------
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ALL CLEAR. Ready to deploy." -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " Next step:" -ForegroundColor White
Write-Host '   .\deploy.ps1 -Token "ghp_xxxxxxxxxxxxxxxx"' -ForegroundColor White
Write-Host ""
Write-Host " After deploy completes, resubmit /sitemap.xml in"
Write-Host " Google Search Console (Sitemaps tab -> ENVIAR)."
Write-Host ""
