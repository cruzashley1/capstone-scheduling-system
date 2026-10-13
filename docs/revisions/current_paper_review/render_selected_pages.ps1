param([string]$PdfPath, [string]$PageNumbers, [string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[void][Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
[void][Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType = WindowsRuntime]
[void][Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
[void][Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType = WindowsRuntime]
$renderAsTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
$renderAsAction = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and -not $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1
function Wait-RenderOperation($Operation, [Type]$ResultType) {
    $renderTask = $renderAsTask.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    $renderTask.Wait()
    return $renderTask.Result
}
$renderFile = Wait-RenderOperation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($PdfPath)) ([Windows.Storage.StorageFile])
$renderDocument = Wait-RenderOperation ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($renderFile)) ([Windows.Data.Pdf.PdfDocument])
[void][System.IO.Directory]::CreateDirectory($OutputDirectory)
foreach ($renderNumber in ($PageNumbers -split ',' | ForEach-Object { [int]$_ } | Sort-Object -Unique)) {
    if ($renderNumber -lt 1 -or $renderNumber -gt $renderDocument.PageCount) { throw 'Page outside PDF bounds' }
    $renderPage = $renderDocument.GetPage($renderNumber - 1)
    $renderStream = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
    $renderOptions = New-Object Windows.Data.Pdf.PdfPageRenderOptions
    $renderOptions.DestinationWidth = 1100
    $renderTask = $renderAsAction.Invoke($null, @($renderPage.RenderToStreamAsync($renderStream, $renderOptions)))
    $renderTask.Wait()
    $renderReader = New-Object Windows.Storage.Streams.DataReader($renderStream.GetInputStreamAt(0))
    [void](Wait-RenderOperation ($renderReader.LoadAsync([uint32]$renderStream.Size)) ([uint32]))
    $renderBytes = New-Object byte[] ([int]$renderStream.Size)
    $renderReader.ReadBytes($renderBytes)
    [System.IO.File]::WriteAllBytes((Join-Path $OutputDirectory ('page-' + $renderNumber + '.png')), $renderBytes)
    $renderReader.Dispose()
    $renderStream.Dispose()
    $renderPage.Dispose()
}
Write-Output ('PDF contains ' + $renderDocument.PageCount + ' pages. Selected pages rendered to ' + $OutputDirectory)
