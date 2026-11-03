<#
    Build portfolio PDF  (ASCII-only source file - ON PURPOSE)

    Why this file contains no Chinese:
        Windows PowerShell 5.1 reads a .ps1 file with the system ANSI code page
        (GBK on a Chinese Windows) unless the file starts with a UTF-8 BOM.
        The `edit` tool strips the BOM, which silently breaks every Chinese
        string literal into garbage and produces a parse error.
        So: keep this script pure ASCII, and load all Chinese text from
        separate UTF-8 files (portfolio-template.html / captions.json).

    Usage:
        cd C:\AndroidProjects\SD-Repo
        powershell -NoProfile -ExecutionPolicy Bypass -File .\build-portfolio-pdf.ps1
        (or double-click the wrapper .bat next to this file)

    Inputs:
        portfolio-template.html   UTF-8, contains {{NAME}} {{CONTACT}} {{SHOT_COUNT}} {{SHOT_PAGES}}
        captions.json             UTF-8, filename-without-ext -> caption
        <shots dir>\*.png         (dir name comes from captions.json "_shotsDir")
    Output:
        <pdf name from captions.json "_pdfName">
#>

param(
    [string]$Name = "(your name)",
    [string]$Contact = "(phone / email)"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------- 1. load Chinese text from UTF-8 files ----------
#  Every Chinese string (folder name, output file name, headings, captions)
#  lives in captions.json / portfolio-template.html -- never in this file.
$templatePath = Join-Path $root "portfolio-template.html"
$captionsPath = Join-Path $root "captions.json"
$htmlPath     = Join-Path $root "_portfolio.html"

foreach ($f in @($templatePath, $captionsPath)) {
    if (-not (Test-Path $f)) {
        Write-Host "[FAIL] missing file: $f" -ForegroundColor Red
        exit 1
    }
}

$template = [System.IO.File]::ReadAllText($templatePath, [System.Text.Encoding]::UTF8)
$captions = [System.IO.File]::ReadAllText($captionsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

$shotsDir = Join-Path $root $captions._shotsDir
$pdfPath  = Join-Path $root $captions._pdfName

# ---------- 2. collect screenshots ----------
if (-not (Test-Path $shotsDir)) {
    Write-Host "[FAIL] screenshot folder not found: $shotsDir" -ForegroundColor Red
    exit 1
}
$shots = Get-ChildItem $shotsDir -Filter *.png | Sort-Object Name
if ($shots.Count -eq 0) {
    Write-Host "[FAIL] no png in screenshot folder" -ForegroundColor Red
    exit 1
}

# ---------- 3. build screenshot pages (6 per page) ----------
$perPage = 6
$pageTotal = [int][Math]::Ceiling($shots.Count / $perPage)
$sb = New-Object System.Text.StringBuilder

for ($p = 0; $p -lt $pageTotal; $p++) {

    [void]$sb.AppendLine('<div class="page">')

    if ($p -eq 0) {
        [void]$sb.AppendLine(('<h2>' + $captions._shotHeading + '</h2>'))
    } else {
        [void]$sb.AppendLine('<h2>' + ($captions._shotPageHeading -f ($p + 1), $pageTotal) + '</h2>')
    }

    [void]$sb.AppendLine('<div class="grid">')

    $chunk = $shots | Select-Object -Skip ($p * $perPage) -First $perPage
    foreach ($img in $chunk) {
        $key = [System.IO.Path]::GetFileNameWithoutExtension($img.Name)
        $cap = $captions.$key
        if (-not $cap) { $cap = $key }

        $rel = $captions._shotsDir + "/" + $img.Name
        [void]$sb.AppendLine(("<div class='shot'><img src='{0}'><div class='cap'>{1}</div></div>" -f $rel, $cap))
    }

    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('</div>')
}

# ---------- 4. fill template ----------
$html = $template
$html = $html.Replace('{{NAME}}', $Name)
$html = $html.Replace('{{CONTACT}}', $Contact)
$html = $html.Replace('{{SHOT_COUNT}}', [string]$shots.Count)
$html = $html.Replace('{{SHOT_PAGES}}', $sb.ToString())

# UTF-8 WITHOUT BOM: the html declares <meta charset="utf-8">, so Edge is fine,
# and a BOM would otherwise show up as a stray character in some viewers.
[System.IO.File]::WriteAllText($htmlPath, $html, (New-Object System.Text.UTF8Encoding($false)))

# ---------- 5. print to PDF with Edge ----------
$edge = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edge)) { $edge = "C:\Program Files\Microsoft\Edge\Application\msedge.exe" }
if (-not (Test-Path $edge)) {
    Write-Host "[FAIL] Edge not found" -ForegroundColor Red
    exit 1
}

if (Test-Path $pdfPath) { Remove-Item $pdfPath -Force }

$profileDir = Join-Path $env:TEMP ("edge-pdf-" + [guid]::NewGuid().ToString("N").Substring(0,8))
$errFile    = Join-Path $env:TEMP ("edge-err-" + [guid]::NewGuid().ToString("N").Substring(0,8) + ".txt")
$outFile    = Join-Path $env:TEMP ("edge-out-" + [guid]::NewGuid().ToString("N").Substring(0,8) + ".txt")
$htmlUri    = "file:///" + $htmlPath.Replace("\", "/")

Write-Host "Rendering PDF ($($shots.Count) screenshots) ..."

#  --headless=new is REQUIRED. The old --headless prints nothing on Edge 15x
#  (silent failure, no error). And we must use Start-Process to isolate Edge's
#  noisy stderr, otherwise 'Stop' treats those warnings as fatal errors.
$edgeArgs = @(
    "--headless=new",
    "--disable-gpu",
    "--no-pdf-header-footer",
    "--user-data-dir=$profileDir",
    "--print-to-pdf=$pdfPath",
    $htmlUri
)
$proc = Start-Process -FilePath $edge -ArgumentList $edgeArgs -NoNewWindow -Wait -PassThru `
        -RedirectStandardError $errFile -RedirectStandardOutput $outFile
$edgeExit = $proc.ExitCode

Start-Sleep -Seconds 2
Remove-Item $profileDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $errFile, $outFile -Force -ErrorAction SilentlyContinue

# ---------- 6. report ----------
if (Test-Path $pdfPath) {
    $size = (Get-Item $pdfPath).Length
    $raw = [System.IO.File]::ReadAllText($pdfPath, [System.Text.Encoding]::GetEncoding("ISO-8859-1"))
    $pageCount = ([regex]::Matches($raw, "/Type\s*/Page[^s]")).Count

    Write-Host ""
    Write-Host "[OK] done" -ForegroundColor Green
    Write-Host ("     file : " + $pdfPath)
    Write-Host ("     size : {0:N1} MB" -f ($size / 1MB))
    Write-Host ("     shots: {0}" -f $shots.Count)
    Write-Host ("     pages: about {0}" -f $pageCount)
} else {
    Write-Host ("[FAIL] no pdf produced (edge exit code " + $edgeExit + ")") -ForegroundColor Red
    exit 1
}
