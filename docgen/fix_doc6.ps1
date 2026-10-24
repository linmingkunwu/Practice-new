# 修复：删除 3.3 残留旧段落，替换引言旧第二段

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$contentJson = [System.IO.File]::ReadAllText('E:\Git\docgen\report_content.json', $utf8)
$content = $contentJson | ConvertFrom-Json
$intro = $content.sections.intro

$docPath = 'D:\qqdownloads\《劳动教育与社会调查》综合报告模板.doc'

function Replace-ParaByFind($doc, $matchKey, $newText) {
    $rng = $doc.Content
    $rng.Find.ClearFormatting()
    $rng.Find.Text = $matchKey
    if ($rng.Find.Execute()) {
        $para = $rng.Paragraphs.Item(1)
        $target = $doc.Range($para.Range.Start, $para.Range.End - 1)
        $target.Text = $newText.Replace("`n", "`r")
        return $true
    }
    return $false
}

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0

try {
    $doc = $word.Documents.Open($docPath, $false, $false)

    # 1. 删除 3.3 残留旧段落（34.3% 段及其后到 3.4 标题前）
    $rng = $doc.Content
    $rng.Find.ClearFormatting()
    $rng.Find.Text = "受访旅客中18—30岁占34.3%"
    if ($rng.Find.Execute()) {
        $startPara = $rng.Paragraphs.Item(1)
        $p = $startPara
        $guard = 0
        while ($p -ne $null -and $guard -lt 50) {
            $txt = $p.Range.Text
            if ($txt -like "*3.4 结论与建议*") { break }
            $next = $p.Next()
            $p.Range.Delete()
            $p = $next
            $guard++
        }
        Write-Output "3.3 残留旧段落已删除（$guard 段）"
    } else {
        Write-Output "警告：未找到 3.3 残留段落"
    }

    # 2. 引言旧第二段替换为新第二段
    $parts = $intro -split "`n`n"
    $second = if ($parts.Count -ge 2) { $parts[1] } else { $intro }
    if (Replace-ParaByFind $doc "本报告围绕" $second) {
        Write-Output "引言第二段已更新"
    } else {
        Write-Output "警告：未找到引言第二段"
    }

    try {
        if ($doc.TablesOfContents.Count -gt 0) { $doc.TablesOfContents.Item(1).Update() }
        Write-Output "目录已更新"
    } catch { Write-Output "目录更新跳过" }

    # 保存：先存临时文件，再覆盖原文件（避免原地保存卡死）
    $tmp = 'D:\qqdownloads\_tmp_report.doc'
    $doc.SaveAs2($tmp, 0)
    $doc.Close($false)
    Write-Output "已保存临时文件: $tmp"
}
finally {
    $word.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
    Get-Process WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force
}
