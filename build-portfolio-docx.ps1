<#
    Build a finished-looking portfolio DOCX from portfolio-content.json.

    WHY THIS FILE IS PURE ASCII:
        Windows PowerShell 5.1 reads .ps1 with the system ANSI code page (GBK),
        so a Chinese literal here would be garbled and break parsing.
        All Chinese lives in portfolio-content.json / captions.json (UTF-8).

    Requires: Word-compatible COM server (MS Word or WPS).
    Output:   <captions.json "_docName">

    Structure produced:
        cover -> table of contents -> one section per json entry -> footer page numbers
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

# ---------------- helpers ----------------
function Pt([double]$cm) { return $cm * 28.3464567 }

# Word colours are BGR integers, not RGB.
function WRgb([int]$r, [int]$g, [int]$b) { return ($r + $g * 256 + $b * 65536) }

$C_BLACK   = WRgb 34 34 34
$C_GRAY    = WRgb 85 85 85
$C_SILVER  = WRgb 128 128 128
$C_BLUE    = WRgb 63 81 181
$C_TBLHEAD = WRgb 238 241 251
$C_CODEBGR = WRgb 247 247 247
$C_NOTEBGR = WRgb 255 248 225

$FONT_CN   = "Microsoft YaHei"
$FONT_CODE = "Consolas"

# built-in Word style ids (locale independent)
$ST_NORMAL = -1
$ST_H1     = -2
$ST_H3     = -4

$word = $null
$doc  = $null

try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    try { $word.DisplayAlerts = 0 } catch { }
    $doc = $word.Documents.Add()
    $sel = $word.Selection

    # ---- page setup: A4, ~2cm margins ----
    $ps = $doc.PageSetup
    $ps.PageWidth    = (Pt 21.0)
    $ps.PageHeight   = (Pt 29.7)
    $ps.TopMargin    = (Pt 2.2)
    $ps.BottomMargin = (Pt 2.0)
    $ps.LeftMargin   = (Pt 2.2)
    $ps.RightMargin  = (Pt 2.2)

    function SetFont([double]$size, [bool]$bold, [int]$rgb, [string]$name) {
        $sel.Font.Name = $name
        try { $sel.Font.NameFarEast = $name } catch { }
        $sel.Font.Size = $size
        $sel.Font.Bold = $(if ($bold) { 1 } else { 0 })
        $sel.Font.Color = $rgb
    }

    function Para([string]$text, [double]$size, [bool]$bold, [int]$rgb, [string]$name,
                  [double]$spaceBefore, [double]$spaceAfter, [int]$styleNum = -1) {
        try { $sel.Style = $styleNum } catch { }
        $sel.ParagraphFormat.SpaceBefore = $spaceBefore
        $sel.ParagraphFormat.SpaceAfter  = $spaceAfter
        SetFont $size $bold $rgb $name
        $sel.TypeText($text)
        $sel.TypeParagraph()
    }

    function ShadedBox([string]$text, [int]$rgb, [string]$font, [double]$size) {
        try { $sel.Style = $ST_NORMAL } catch { }
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
        $sel.EndKey(6) | Out-Null
        $sel.TypeParagraph()
    }

    function AddTable($head, $rows) {
        try { $sel.Style = $ST_NORMAL } catch { }
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
        try { $t.AutoFitBehavior(2) } catch { }
        $sel.EndKey(6) | Out-Null
        $sel.TypeParagraph()
    }

    function AddShots() {
        # Two-row table per chunk: row 1 pictures, row 2 captions.
        # WPS's compatibility layer throws E_FAIL on Range.Paragraphs.Add(),
        # so never build multi-paragraph cells.
        try { $sel.Style = $ST_NORMAL } catch { }
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
                try { $shape.Width = (Pt 4.9) } catch { }

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

    # ---------------- footer: page numbers ----------------
    try {
        $ftr = $doc.Sections.Item(1).Footers.Item(1)
        $ftr.Range.ParagraphFormat.Alignment = 1
        $ftr.Range.Font.Size = 9
        $ftr.Range.Font.Color = $C_SILVER
        $ftr.Range.Fields.Add($ftr.Range, 33) | Out-Null      # wdFieldPage
    } catch { }

    # ---------------- cover ----------------
    $sel.ParagraphFormat.SpaceBefore = (Pt 7.0)
    Para $C.title 28 $true $C_BLACK $FONT_CN (Pt 7.0) (Pt 0.4)
    Para $C.subtitle 12 $false $C_SILVER $FONT_CN (Pt 0) (Pt 0.8)

    if ($C.abstract) {
        Para $C.abstract 9.5 $false $C_GRAY $FONT_CN (Pt 0.2) (Pt 1.0)
    }

    $metaRows = @()
    foreach ($m in $C.meta) { $metaRows += ,@([string]$m[0], [string]$m[1]) }
    AddTable $C.metaHead $metaRows

    $sel.InsertBreak(7) | Out-Null

    # ---------------- table of contents ----------------
    Para $C.tocHeading 16 $true $C_BLUE $FONT_CN (Pt 0) (Pt 0.6)
    $tocOk = $false
    try {
        $toc = $doc.TablesOfContents.Add($sel.Range, $true, 1, 3)
        try { $toc.Update() } catch { }
        $tocOk = $true
        $sel.EndKey(6) | Out-Null
        $sel.TypeParagraph()
    } catch {
        Para "TOC_UNSUPPORTED" 9 $false $C_GRAY $FONT_CN (Pt 0) (Pt 0.3)
    }
    $sel.InsertBreak(7) | Out-Null

    # ---------------- sections ----------------
    $firstSection = $true
    foreach ($sec in $C.sections) {

        if (-not $firstSection) { $sel.InsertBreak(7) | Out-Null }
        $firstSection = $false

        Para $sec.heading 17 $true $C_BLUE $FONT_CN (Pt 0) (Pt 0.5) $ST_H1

        foreach ($b in $sec.blocks) {
            switch ($b.type) {
                "p"      { Para $b.text 10.5 $false $C_BLACK $FONT_CN (Pt 0) (Pt 0.28) }
                "p_bold" { Para $b.text 10.5 $true  $C_BLACK $FONT_CN (Pt 0.1) (Pt 0.3) }
                "h3"     { Para $b.text 11.5 $true  $C_BLACK $FONT_CN (Pt 0.4) (Pt 0.2) $ST_H3 }
                "table"  { AddTable $b.head $b.rows }
                "code"   { ShadedBox $b.text $C_CODEBGR $FONT_CODE 8.5 }
                "note"   { ShadedBox $b.text $C_NOTEBGR $FONT_CN 9.5 }
                "shots"  { AddShots }
            }
        }
    }

    # ---------------- refresh the TOC ----------------
    # MUST happen after every heading exists, otherwise Word renders
    # "no table of contents entries found".
    try {
        if ($doc.TablesOfContents.Count -gt 0) {
            $doc.TablesOfContents.Item(1).Update()
            $tocOk = $true
        }
    } catch { }

    # ---------------- save ----------------
    if (Test-Path $outPath) { Remove-Item $outPath -Force }

    $saved = $false
    foreach ($fmt in @(16, 12, 0)) {
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

    if ($tocOk) { Write-Host "[OK] docx generated (with TOC)" -ForegroundColor Green }
    else        { Write-Host "[OK] docx generated (TOC unsupported by this Word build)" -ForegroundColor Yellow }
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
    Write-Host ("     size: {0:N1} KB" -f ((Get-Item $outPath).Length / 1KB))
} else {
    Write-Host "[FAIL] output not found" -ForegroundColor Red
    exit 1
}
