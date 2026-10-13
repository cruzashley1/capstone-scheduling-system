param(
    [string]$DocumentName = 'Section_4_1_Testing_Evidence_Update'
)
$ErrorActionPreference = 'Stop'
$testingRoot = 'C:\prototype\docs\revisions'
$testingDocx = Join-Path $testingRoot ($DocumentName + '.docx')
$testingPdf = Join-Path $testingRoot ($DocumentName + '.pdf')
$testingApp = $null
$testingDocument = $null
$testingOldLinks = $null
try {
    $testingApp = New-Object -ComObject Word.Application
    $testingApp.Visible = $false
    $testingApp.DisplayAlerts = 0
    $testingApp.AutomationSecurity = 3
    $testingApp.ScreenUpdating = $false
    $testingOldLinks = $testingApp.Options.UpdateLinksAtOpen
    $testingApp.Options.UpdateLinksAtOpen = $false
    $testingDocument = $testingApp.Documents.Open($testingDocx, $false, $true, $false)
    $testingDocument.Repaginate()
    $testingDocument.ExportAsFixedFormat($testingPdf, 17)
    $testingPdfBytes = [System.IO.File]::ReadAllBytes($testingPdf)
    $testingPageCount = [regex]::Matches([System.Text.Encoding]::ASCII.GetString($testingPdfBytes), '/Type\s*/Page\b').Count
    Write-Output ('Exported ' + $testingPdf + ' (' + $testingPageCount + ' pages).')
} finally {
    if ($null -ne $testingApp -and $null -ne $testingOldLinks) {
        try { $testingApp.Options.UpdateLinksAtOpen = $testingOldLinks } catch {}
    }
    if ($null -ne $testingDocument) {
        try { $testingDocument.Close(0) } catch {}
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($testingDocument)
    }
    if ($null -ne $testingApp) {
        try { $testingApp.Quit() } catch {}
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($testingApp)
    }
}
