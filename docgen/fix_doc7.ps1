# 最终修复：删除引言35份残留段、3.4重复段

$ErrorActionPreference = 'Stop'
$docPath = 'D:\qqdownloads\《劳动教育与社会调查》综合报告模板.doc'

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0

try {
    $doc = $word.Documents.Open($docPath, $false, $false)

    # 1. 删除引言旧第二段（含"借助Excel对35份"）
    $rng = $doc.Content
    $rng.Find.ClearFormatting()
    $rng.Find.Text = "借助Excel对35份"
    if ($rng.Find.Execute()) {
        $para = $rng.Paragraphs.Item(1)
        $para.Range.Delete()
        Write-Output "已删除引言35份残留段"
    } else {
        Write-Output "未找到35份段"
    }

    # 2. 删除 3.4 重复的"基于以上结论"段（第二个）
    $rng2 = $doc.Content
    $rng2.Find.ClearFormatting()
    $rng2.Find.Text = "基于以上结论"
    if ($rng2.Find.Execute()) {
        $first = $rng2.Paragraphs.Item(1)
        $second = $first.Next()
        if ($second -ne $null -and $second.Range.Text -like "*基于以上结论*") {
            $second.Range.Delete()
            Write-Output "已删除重复的基于以上结论段"
        } else {
            Write-Output "未找到第二个基于以上结论段"
        }
    } else {
        Write-Output "未找到基于以上结论段"
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
