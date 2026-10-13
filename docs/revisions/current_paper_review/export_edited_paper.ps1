$ErrorActionPreference = 'Stop'
$revisionRoot = 'C:\prototype\docs\revisions'
$revisionDocx = Join-Path $revisionRoot 'RevisedPaper_ISO25059_Edited.docx'
$revisionPdf = Join-Path $revisionRoot 'RevisedPaper_ISO25059_Edited.pdf'
$revisionManifest = Get-Content -LiteralPath (Join-Path $revisionRoot 'current_paper_review\edit_manifest.json') -Raw | ConvertFrom-Json
$revisionApp = $null
$revisionDocument = $null
$revisionOldLinkOption = $null
try {
    $revisionApp = New-Object -ComObject Word.Application
    $revisionApp.Visible = $false
    $revisionApp.DisplayAlerts = 0
    $revisionApp.AutomationSecurity = 3
    $revisionApp.ScreenUpdating = $false
    $revisionOldLinkOption = $revisionApp.Options.UpdateLinksAtOpen
    $revisionApp.Options.UpdateLinksAtOpen = $false
    $revisionDocument = $revisionApp.Documents.Open($revisionDocx, $false, $true, $false)
    $revisionDocument.ActiveWindow.View.Type = 3
    $revisionDocument.Repaginate()
    $revisionTotalPages = $revisionDocument.ComputeStatistics(2)
    $revisionDocument.Repaginate()
    $revisionDocument.ExportAsFixedFormat($revisionPdf, 17)
    $revisionPdfBytes = [System.IO.File]::ReadAllBytes($revisionPdf)
    $revisionTotalPages = [regex]::Matches([System.Text.Encoding]::ASCII.GetString($revisionPdfBytes), '/Type\s*/Page\b').Count
    $revisionBodyRange = $revisionDocument.Bookmarks.Item('PaperNumberingStart').Range
    $revisionBodyRange.Collapse(1)
    $revisionBodyOffset = $revisionBodyRange.Information(3) - 1
    $revisionAllPages = @{}
    foreach ($revisionBookmark in $revisionDocument.Bookmarks) {
        if ($revisionBookmark.Name -match '^(ISO_|PaperAt_|PaperBodyStart|PaperNumberingStart)') {
            $revisionRange = $revisionBookmark.Range
            $revisionRange.Collapse(1)
            $revisionPhysicalPage = $revisionRange.Information(3)
            $revisionPrintedPage = $revisionPhysicalPage
            if ($revisionPhysicalPage -gt $revisionBodyOffset) { $revisionPrintedPage -= $revisionBodyOffset }
            $revisionAllPages[$revisionBookmark.Name] = @{ printed_page = $revisionPrintedPage; physical_page = $revisionPhysicalPage }
        }
    }
    $revisionAllPages | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $revisionRoot 'current_paper_review\all_page_locations.json') -Encoding UTF8
    $revisionPages = @()
    foreach ($revisionName in $revisionManifest.navigation_bookmarks) {
        $revisionPages += [pscustomobject]@{
            bookmark = $revisionName
            printed_page = $revisionAllPages[$revisionName].printed_page
            physical_page = $revisionAllPages[$revisionName].physical_page
        }
    }
    [pscustomobject]@{
        page_count = $revisionTotalPages
        locations = $revisionPages
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $revisionRoot 'current_paper_review\page_locations.json') -Encoding UTF8
    Write-Output ('Exported edited paper: ' + $revisionTotalPages + ' pages.')
    $revisionPages | Format-Table -AutoSize
} finally {
    if ($null -ne $revisionApp -and $null -ne $revisionOldLinkOption) {
        try { $revisionApp.Options.UpdateLinksAtOpen = $revisionOldLinkOption } catch {}
    }
    if ($null -ne $revisionDocument) {
        try { $revisionDocument.Close(0) } catch {}
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($revisionDocument)
    }
    if ($null -ne $revisionApp) {
        try { $revisionApp.Quit() } catch {}
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($revisionApp)
    }
}
