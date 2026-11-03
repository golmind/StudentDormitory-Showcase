<#
    Build portfolio DOCX (Word) from portfolio-content.json + captions.json

    WHY THIS FILE IS PURE ASCII:
        Windows PowerShell 5.1 reads .ps1 with the system ANSI code page (GBK).
        Any Chinese literal in this file would be garbled and break parsing.
        All Chinese text lives in the two UTF-8 json files instead.

    Requires: a Word-compatible COM server (MS Word or WPS).
    Output:   <name>  (taken from captions.json "_docName")

    Usage:
        powershell -NoProfile -ExecutionPolicy Bypass -File .\build-portfolio-docx.ps1
#>

param(
    [string]$Name = "",
    [string]$Contact = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$contentPath  = Join-Path $root "portfolio-content.json"
$captionsPath = Join-Path $root "captions.json"
foreach ($f in @($contentPath, $captionsPath)) {
    if (-not (Test-Path $f)) { Write-Host "[FAIL] missing $f" -ForegroundColor Red; exit 1 }
}

$C = [System.IO.File]::ReadAllText($contentPath,  [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$K = [System.IO.File]::ReadAllText($captionsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

$docsDir = Join-Path $root $K._shotsDir
$outPath = Join-Path $root $K._docName

# name / contact override
if ($Name)    { $C.meta[0][1] = $Name }
if ($Contact) { $C.meta[1][1] = $Contact }

# ---------------- helpers ----------------
function Pt([double]$cm) { return $cm * 28.3464567 }

# Word colours are BGR integers, NOT RGB. Easy to get wrong, so compute them.
function WRgb([int]$r, [int]$g, [int]$b) { return ($r + $g * 256 + $b * 65536) }

$C_BLACK   = WRgb 34 34 34          # body text
$C_GRAY    = WRgb 85 85 85
$C_SILVER  = WRgb 128 128 128
$C_BLUE    = WRgb 63 81 181         # heading accent
$C_TBLHEAD = WRgb 238 241 251       # table header background
$C_CODEBGR = WRgb 247 247 247       # code block background
$C_NOTEBGR = WRgb 255 248 225       # note background

$FONT_CN = "Microsoft YaHei"
$FONT_CODE = "Consolas"

$word = $null
$doc = $null

try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    try { $word.DisplayAlerts = 0 } catch { }
    $doc = $word.Documents.Add()
    $sel = $word.Selection

    # ---- page setup: A4 + 2cm margins (explicit, so locale defaults don't matter) ----
    $ps = $doc.PageSetup
    $ps.PageWidth  = (Pt 21.0)
    $ps.PageHeight = (Pt 29.7)
    $ps.TopMargin    = (Pt 2.0)
    $ps.BottomMargin = (Pt 2.0)
    $ps.LeftMargin   = (Pt 2.0)
    $ps.RightMargin  = (Pt 2.0)

    function SetFont([double]$size, [bool]$bold, [int]$rgb, [string]$name) {
        $sel.Font.Name = $name
        try { $sel.Font.NameFarEast = $name } catch { }
        $sel.Font.Size = $size
        $sel.Font.Bold = $(if ($bold) { 1 } else { 0 })
        $sel.Font.Color = $rgb
    }

    function Para([string]$text, [double]$size, [bool]$bold, [int]$rgb, [string]$name, [double]$spaceBefore, [double]$spaceAfter) {
        $sel.ParagraphFormat.SpaceBefore = $spaceBefore
        $sel.ParagraphFormat.SpaceAfter  = $spaceAfter
        SetFont $size $bold $rgb $name
        $sel.TypeText($text)
        $sel.TypeParagraph()
    }

    function TryStyle([string[]]$names) {
        foreach ($n in $names) {
            try { $sel.Style = $n; return $true } catch { }
        }
        return $false
    }

    function ShadedBox([string]$text, [int]$rgb, [string]$font, [double]$size) {
        # one-cell table with background colour: works for both code blocks and notes
        $t = $doc.Tables.Add($sel.Range, 1, 1)
        $t.Borders.Enable = 0
        $t.Rows.Item(1).Shading.BackgroundPatternColor = $rgb
        $c = $t.Cell(1, 1)
        $c.Range.Text = $text
        $c.Range.Font.Name = $font
        try { $c.Range.Font.NameFarEast = $font } catch { }
        $c.Range.Font.Size = $size
        $c.Range.Font.Color = $C_BLACK
        $c.Range.ParagraphFormat.SpaceBefore = (Pt 0.15)
        $c.Range.ParagraphFormat.SpaceAfter  = (Pt 0.15)
        $sel.EndKey(6) | Out-Null          # wdStory
        $sel.TypeParagraph()
    }

    function AddTable($head, $rows) {
        # $head may be empty -> no header row (used by the cover info block)
        $hasHead = ($null -ne $head) -and ($head.Count -gt 0)
        if ($hasHead) { $cols = $head.Count } else { $cols = $rows[0].Count }
        if ($hasHead) { $nRows = $rows.Count + 1 } else { $nRows = $rows.Count }
        $bodyStart = $(if ($hasHead) { 2 } else { 1 })
        $t = $doc.Tables.Add($sel.Range, $nRows, $cols)
        $t.Borders.Enable = 1
        $t.Range.Font.Name = $FONT_CN
        try { $t.Range.Font.NameFarEast = $FONT_CN } catch { }
        $t.Range.Font.Size = 9.5
        $t.Range.ParagraphFormat.SpaceBefore = (Pt 0.1)
        $t.Range.ParagraphFormat.SpaceAfter  = (Pt 0.1)

        if ($hasHead) {
            for ($c = 1; $c -le $cols; $c++) {
                $t.Cell(1, $c).Range.Text = [string]$head[$c - 1]
                $t.Cell(1, $c).Range.Font.Bold = 1
                $t.Cell(1, $c).Shading.BackgroundPatternColor = $C_TBLHEAD
            }
            try { $t.Rows.Item(1).HeadingFormat = -1 } catch { }
        }
        for ($r = 0; $r -lt $rows.Count; $r++) {
            $row = $rows[$r]
            for ($c = 1; $c -le $cols; $c++) {
                $v = ""
                if ($c - 1 -lt $row.Count) { $v = [string]$row[$c - 1] }
                $t.Cell($r + $bodyStart, $c).Range.Text = $v
            }
        }
        try { $t.AutoFitBehavior(2) } catch { }    # wdAutoFitWindow
        $t.Range.ParagraphFormat.SpaceAfter = (Pt 0.2)
        $sel.EndKey(6) | Out-Null
        $sel.TypeParagraph()
    }

    function AddShots() {
        # Two-row table per chunk: row 1 = pictures, row 2 = captions.
        # Why not one cell with two paragraphs: WPS's Word-compatibility layer
        # throws E_FAIL on Range.Paragraphs.Add(), so we never touch paragraphs
        # inside a cell -- one picture / one caption per cell only.
        $shots = Get-ChildItem $docsDir -Filter *.png | Sort-Object Name
        if ($shots.Count -eq 0) { return }

        $perRow = 3
        for ($base = 0; $base -lt $shots.Count; $base += $perRow) {

            $tbl = $doc.Tables.Add($sel.Range, 2, $perRow)
            $tbl.Borders.Enable = 0
            $tbl.Range.ParagraphFormat.SpaceBefore = (Pt 0.1)
            $tbl.Range.ParagraphFormat.SpaceAfter  = (Pt 0.1)

            for ($c = 1; $c -le $perRow; $c++) {

                $idx = $base + $c - 1

                $cellPic = $tbl.Cell(1, $c)
                $cellCap = $tbl.Cell(2, $c)
                $cellPic.Range.ParagraphFormat.Alignment = 1
                $cellCap.Range.ParagraphFormat.Alignment = 1

                if ($idx -ge $shots.Count) { continue }

                $img = $shots[$idx]

                $shape = $cellPic.Range.InlineShapes.AddPicture($img.FullName)
                try { $shape.LockAspectRatio = -1 } catch { }
                try { $shape.Width = (Pt 5.0) } catch { }

                $key = [System.IO.Path]::GetFileNameWithoutExtension($img.Name)
                $cap = $K.$key
                if (-not $cap) { $cap = $key }

                $cellCap.Range.Text = [string]$cap
                $cellCap.Range.Font.Name = $FONT_CN
                try { $cellCap.Range.Font.NameFarEast = $FONT_CN } catch { }
                $cellCap.Range.Font.Size = 8
                $cellCap.Range.Font.Color = $C_GRAY
            }

            try { $tbl.AutoFitBehavior(2) } catch { }
            $sel.EndKey(6) | Out-Null
            $sel.TypeParagraph()
        }
    }
    # ---------------- cover ----------------
    $sel.ParagraphFormat.SpaceBefore = (Pt 6.0)
    Para $C.title 26 $true $C_BLACK $FONT_CN (Pt 6.0) (Pt 0.3)
    Para $C.subtitle 11 $false $C_SILVER $FONT_CN (Pt 0) (Pt 1.0)

    $metaRows = @()
    foreach ($m in $C.meta) {
        $metaRows += ,@([string]$m[0], [string]$m[1])
    }
    AddTable $C.metaHead $metaRows

    $sel.InsertBreak(7) | Out-Null      # page break

    # ---------------- sections ----------------
    $first = $true
    foreach ($sec in $C.sections) {

        if (-not $first) { $sel.InsertBreak(7) | Out-Null }
        $first = $false

        # section heading
        try { $sel.Style = -2 } catch { }   # wdStyleHeading1
        Para $sec.heading 16 $true $C_BLUE $FONT_CN (Pt 0) (Pt 0.4)

        foreach ($b in $sec.blocks) {
            switch ($b.type) {
                "p"        { Para $b.text 10.5 $false $C_BLACK $FONT_CN (Pt 0) (Pt 0.25) }
                "p_bold"   { Para $b.text 10.5 $true  $C_BLACK $FONT_CN (Pt 0.1) (Pt 0.3) }
                "h3"       { try { $sel.Style = -4 } catch { }   # wdStyleHeading3
                             Para $b.text 11.5 $true $C_BLACK $FONT_CN (Pt 0.35) (Pt 0.2) }
                "table"    { AddTable $b.head $b.rows }
                "code"     { ShadedBox $b.text $C_CODEBGR $FONT_CODE 8.5 }
                "note"     { ShadedBox $b.text $C_NOTEBGR $FONT_CN 9.5 }
                "shots"    { AddShots }
            }
        }
    }

    # ---------------- save ----------------
    if (Test-Path $outPath) { Remove-Item $outPath -Force }

    $saved = $false
    foreach ($fmt in @(16, 12, 0)) {          # docx(default) -> docx(2007) -> doc
        try {
            $doc.SaveAs($outPath, $fmt)
            $saved = $true
            Write-Host ("Saved with format code " + $fmt)
            break
        } catch {
            if (Test-Path $outPath) { $saved = $true; break }
        }
    }

    if (-not $saved) { throw "SaveAs failed" }

    Write-Host ""
    Write-Host "[OK] docx generated" -ForegroundColor Green
    Write-Host ("     file: " + $outPath)
}
finally {
    if ($doc)  { try { $doc.Close(0) } catch { } }
    if ($word) { try { $word.Quit() } catch { } }
    try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc)  | Out-Null } catch { }
    try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null } catch { }
    [GC]::Collect()
}

if (Test-Path $outPath) {
    $sz = (Get-Item $outPath).Length
    Write-Host ("     size: {0:N1} KB" -f ($sz / 1KB))
} else {
    Write-Host "[FAIL] output not found" -ForegroundColor Red
    exit 1
}
