# 恢复实践评价表：保留证书照片 + 重建表格（评价文字 + 盖章/签名留空待盖章）

$ErrorActionPreference = 'Stop'
$docPath = 'D:\qqdownloads\《劳动教育与社会调查》综合报告模板.doc'

$evalText = "雷文斌同学于2026年7月20日至8月3日在南昌西站参加志愿服务实践。实践期间，该同学政治思想表现良好，遵纪守法，严格遵守车站各项规章制度和安全要求，无迟到早退及违纪现象。工作态度积极主动、认真负责，服务热情、耐心细致，主动为旅客提供指路引导，热心协助老年旅客解决购票困难，展现了良好的职业素养和奉献精神。该同学沟通能力强，与车站工作人员配合默契，圆满完成了安排的各项实践任务，得到旅客和同事的一致好评，综合评价为优秀。"

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0

try {
    $doc = $word.Documents.Open($docPath, $false, $false)

    # 1. 删除证书照片后的重复评价段落（避免与表格重复）
    $rng = $doc.Content
    $rng.Find.ClearFormatting()
    $rng.Find.Text = "综合评价：雷文斌同学"
    if ($rng.Find.Execute()) {
        $p = $rng.Paragraphs.Item(1)
        $p.Range.Delete()
        Write-Output "已删除重复的评价文字段"
    } else {
        Write-Output "未找到重复评价段"
    }

    # 2. 定位照片段（实践评价标题的下一段，含图片）
    $titlePara = $null
    foreach ($p in $doc.Paragraphs) {
        $txt = $p.Range.Text.Trim().TrimEnd([char]13, [char]10, [char]7)
        if ($txt -eq "实践评价") { $titlePara = $p; break }
    }
    $imgPara = if ($titlePara) { $titlePara.Next() } else { $null }
    if ($imgPara -eq $null) {
        Write-Output "警告：未找到照片段"
    } else {
        # 3. 照片段后插入表格标题
        $pos = $imgPara.Range.End
        $ins = $doc.Range($pos, $pos)
        $ins.InsertAfter("`r学生校外实践评价表`r")

        # 4. 在标题后创建 4x4 表格
        $tRng = $doc.Content
        $tRng.Find.ClearFormatting()
        $tRng.Find.Text = "学生校外实践评价表"
        if ($tRng.Find.Execute()) {
            $tp = $tRng.Paragraphs.Item(1)
            $after = $doc.Range($tp.Range.End, $tp.Range.End)
            $table = $doc.Tables.Add($after, 4, 4)
            $table.Borders.Enable = $true
            $table.Range.Font.Name = "宋体"
            $table.Range.Font.Size = 10.5

            # 行1 基本信息
            $table.Cell(1, 1).Range.Text = "学生姓名"
            $table.Cell(1, 2).Range.Text = "雷文斌"
            $table.Cell(1, 3).Range.Text = "班级"
            $table.Cell(1, 4).Range.Text = "英语（国际物流）2025-1"
            # 行2
            $table.Cell(2, 1).Range.Text = "学号"
            $table.Cell(2, 2).Range.Text = "2025"
            $table.Cell(2, 3).Range.Text = "实践起止日期"
            $table.Cell(2, 4).Range.Text = "2026年7月20日至2026年8月3日"
            # 行3 综合评价（合并 2-4 列）
            $table.Cell(3, 1).Range.Text = "实践单位对本次实践的综合评价："
            $table.Cell(3, 2).Merge($table.Cell(3, 4))
            $table.Cell(3, 2).Range.Text = $evalText
            # 行4 盖章签名（整行合并，留空待盖章）
            $table.Cell(4, 1).Merge($table.Cell(4, 4))
            $table.Cell(4, 1).Range.Text = "（单位盖章）　　　　　　签名：　　　　　　　　年　　月　　日"
            Write-Output "实践评价表已恢复"
        }
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
