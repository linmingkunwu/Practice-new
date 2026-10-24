# 填写附录"实践照片"部分的时间、地点、内容

$ErrorActionPreference = 'Stop'
$docPath = 'D:\qqdownloads\《劳动教育与社会调查》综合报告模板.doc'

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0

try {
    $doc = $word.Documents.Open($docPath, $false, $false)

    # 找到单独占一行的"时间：""地点：""内容："段落并补充内容
    $fillMap = @{
        "时间：" = "2027年寒假，为期两周，每日9:00—17:00"
        "地点：" = "南昌西站"
        "内容：" = "高铁志愿服务岗：旅客指路引导，协助老年旅客购买地铁票等"
    }
    foreach ($p in $doc.Paragraphs) {
        $txt = $p.Range.Text.Trim().TrimEnd([char]13, [char]10, [char]7)
        if ($fillMap.ContainsKey($txt)) {
            $rng = $doc.Range($p.Range.Start, $p.Range.End - 1)
            $rng.InsertAfter($fillMap[$txt])
            Write-Output "已填写: $txt$($fillMap[$txt])"
        }
    }

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
    Get-Process WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force
}
