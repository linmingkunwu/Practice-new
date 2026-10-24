# 将电子印章图片插入实践评价表盖章处

$ErrorActionPreference = 'Stop'
$docPath = 'D:\qqdownloads\《劳动教育与社会调查》综合报告模板.doc'
$sealPath = 'D:\qqdownloads\南昌西站电子印章.png'

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0

try {
    $doc = $word.Documents.Open($docPath, $false, $false)

    $rng = $doc.Content
    $rng.Find.ClearFormatting()
    $rng.Find.Text = "（单位盖章）"
    if ($rng.Find.Execute()) {
        $cell = $rng.Cells.Item(1)
        $cell.Range.Text = ""   # 清空原提示文字
        $cellRng = $cell.Range
        # 在单元格内插入印章图片
        $shape = $doc.InlineShapes.AddPicture($sealPath, $false, $true, $cellRng)
        try { $shape.Width = 130; $shape.Height = 130 } catch { }
        try { $cellRng.ParagraphFormat.Alignment = 1 } catch { }
        Write-Output "印章已插入实践评价表盖章处"
    } else {
        Write-Output "警告：未找到（单位盖章）"
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
