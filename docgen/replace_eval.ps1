# 用真实照片替代附录"实践评价"的模拟表格，评价文字保留为段落

$ErrorActionPreference = 'Stop'
$docPath = 'D:\qqdownloads\《劳动教育与社会调查》综合报告模板.doc'
$imgPath = 'D:\qqdownloads\MVIMG_20260902_210013.jpg'

$evalPara = "综合评价：雷文斌同学于2026年7月20日至8月3日在南昌西站参加志愿服务实践。实践期间，该同学政治思想表现良好，遵纪守法，严格遵守车站各项规章制度和安全要求，无迟到早退及违纪现象。工作态度积极主动、认真负责，服务热情、耐心细致，主动为旅客提供指路引导，热心协助老年旅客解决购票困难，展现了良好的职业素养和奉献精神。该同学沟通能力强，与车站工作人员配合默契，圆满完成了安排的各项实践任务，得到旅客和同事的一致好评，综合评价为优秀。"

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0

try {
    $doc = $word.Documents.Open($docPath, $false, $false)

    # 1. 定位附录正文"实践评价"标题段（完全等于"实践评价"的段落）
    $titlePara = $null
    foreach ($p in $doc.Paragraphs) {
        $txt = $p.Range.Text.Trim().TrimEnd([char]13, [char]10, [char]7)
        if ($txt -eq "实践评价") { $titlePara = $p; break }
    }
    if ($titlePara -eq $null) { throw "未找到'实践评价'标题段" }

    # 2. 删除模拟的实践评价表
    $tb = $null
    foreach ($t in $doc.Tables) {
        if ($t.Range.Text -like "*实践单位对本次实践的综合评价*") { $tb = $t; break }
    }
    if ($tb) {
        $tb.Delete()
        Write-Output "模拟实践评价表已删除"
    } else {
        Write-Output "警告：未找到实践评价表"
    }

    # 3. 标题后插入真实照片
    $pos = $titlePara.Range.End
    $imgRng = $doc.Range($pos, $pos)
    $shape = $doc.InlineShapes.AddPicture($imgPath, $false, $true, $imgRng)
    try { $shape.Width = 400 } catch { }
    try { $shape.Range.ParagraphFormat.Alignment = 1 } catch { }
    Write-Output "真实照片已插入"

    # 4. 照片下方写入评价文字
    $r2 = $doc.Range($shape.Range.End, $shape.Range.End)
    $r2.InsertAfter("`r" + $evalPara)
    Write-Output "评价文字已写入"

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
