# 删除 3.4 重复的"基于以上结论"段（保留第一个）

$ErrorActionPreference = 'Stop'
$docPath = 'D:\qqdownloads\《劳动教育与社会调查》综合报告模板.doc'

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0

try {
    $doc = $word.Documents.Open($docPath, $false, $false)

    $rng = $doc.Content
    $rng.Find.ClearFormatting()
    $rng.Find.Text = "基于以上结论"
    $rng.Find.Execute() | Out-Null   # 第一次匹配
    $rng.Find.Execute() | Out-Null   # 第二次匹配
    if ($rng.Find.Found) {
        $para = $rng.Paragraphs.Item(1)
        $para.Range.Delete()
        Write-Output "已删除第二个基于以上结论段"
    } else {
        Write-Output "未找到第二个基于以上结论段"
    }

    $t = $doc.Content.Text
    Write-Output ("基于以上结论剩余: " + ([regex]::Matches($t, "基于以上结论").Count))

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
