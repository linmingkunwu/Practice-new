# 修改 doc：南昌火车站 -> 南昌西站，铁路客运服务行业 -> 高铁客运服务行业

$ErrorActionPreference = 'Stop'
$docPath = 'D:\qqdownloads\《劳动教育与社会调查》综合报告模板.doc'

function Replace-All($doc, $find, $replace) {
    $rng = $doc.Content
    $rng.Find.ClearFormatting()
    $rng.Find.Replacement.ClearFormatting()
    $rng.Find.Execute($find, $false, $false, $false, $false, $false, $true, 1, $false, $replace, 2) | Out-Null
}

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0

try {
    $doc = $word.Documents.Open($docPath, $false, $false)
    Replace-All $doc "铁路客运服务行业" "高铁客运服务行业"
    Replace-All $doc "南昌火车站" "南昌西站"
    Write-Output "站名已替换为南昌西站"
    try {
        if ($doc.TablesOfContents.Count -gt 0) { $doc.TablesOfContents.Item(1).Update() }
        Write-Output "目录已更新"
    } catch { Write-Output "目录更新跳过" }
    $saved = $false
    try { $doc.Save(); $saved = $true; Write-Output "已保存" }
    catch { Write-Output "Save 失败: $($_.Exception.Message)" }
    if (-not $saved) {
        try { $doc.SaveAs2($docPath, 0); Write-Output "已通过 SaveAs2 保存" }
        catch { Write-Output "SaveAs2 失败: $($_.Exception.Message)" }
    }
    $doc.Close($false)
}
finally {
    $word.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
}
