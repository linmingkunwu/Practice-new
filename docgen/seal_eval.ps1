# 填写实践评价表综合评价 + 补回签名

$ErrorActionPreference = 'Stop'
$docPath = 'D:\qqdownloads\《劳动教育与社会调查》综合报告模板.doc'

$evalText = "雷文斌同学于2026年7月20日至8月3日在我站参加志愿服务实践。实践期间，该同学政治思想表现良好，遵纪守法，严格遵守车站各项规章制度和安全要求，无迟到早退及违纪现象。工作态度积极主动、认真负责，服务热情、耐心细致，主动为旅客提供指路引导，热心协助老年旅客解决购票困难，展现了良好的职业素养和奉献精神。该同学沟通能力强，与车站工作人员配合默契，圆满完成了安排的各项实践任务，得到旅客和同事的一致好评，综合评价为优秀。特此证明。"

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0

try {
    $doc = $word.Documents.Open($docPath, $false, $false)

    $tb = $null
    foreach ($t in $doc.Tables) {
        if ($t.Range.Text -like "*实践单位对本次实践的综合评价*") { $tb = $t; break }
    }
    if ($tb) {
        $cell = $tb.Cell(4, 1)
        # 1. 综合评价文字插入单元格开头（印章图片之前）
        $r = $cell.Range
        $r.Collapse(1)   # wdCollapseStart
        $r.InsertBefore($evalText + "`r")
        # 2. 补回"签名"（单元格末尾，印章图片之后）
        $r2 = $cell.Range
        $r2.End = $r2.End - 1   # 去掉单元格结束标记
        $r2.InsertAfter("签名")
        Write-Output "综合评价已填写，签名已补回"
    } else {
        Write-Output "警告：未找到实践评价表"
    }

    try {
        if ($doc.TablesOfContents.Count -gt 0) { $doc.TablesOfContents.Item(1).Update() }
        Write-Output "目录已更新"
    } catch { Write-Output "目录更新跳过" }

    $tmp = 'D:\qqdownloads\_tmp_report.doc'
    $doc.SaveAs2($tmp, 0)
    $doc.Close($false)
    Write-Output "已保存临时文件"
}
finally {
    $word.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
    Get-Process WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force
}
