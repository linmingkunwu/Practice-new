# 修改 doc：字体改黑、删除模板提示、车站改为南昌火车站

$ErrorActionPreference = 'Stop'
$docPath = 'D:\qqdownloads\《劳动教育与社会调查》综合报告模板.doc'

function Replace-All($doc, $find, $replace) {
    $rng = $doc.Content
    $rng.Find.ClearFormatting()
    $rng.Find.Replacement.ClearFormatting()
    $rng.Find.Execute($find, $false, $false, $false, $false, $false, $true, 1, $false, $replace, 2) | Out-Null
}

function Remove-Text($doc, $key) {
    $rng = $doc.Content
    $rng.Find.ClearFormatting()
    $rng.Find.Text = $key
    if ($rng.Find.Execute()) { $rng.Text = ""; return $true }
    return $false
}

function Remove-Para($doc, $key) {
    $rng = $doc.Content
    $rng.Find.ClearFormatting()
    $rng.Find.Text = $key
    if ($rng.Find.Execute()) {
        $para = $rng.Paragraphs.Item(1)
        $para.Range.Delete()
        return $true
    }
    return $false
}

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0

try {
    $doc = $word.Documents.Open($docPath, $false, $false)

    # 1. 全文档字体颜色设为自动（黑色）
    $doc.Content.Font.Color = -16777216   # wdColorAutomatic
    Write-Output "字体颜色已全部改为黑色"

    # 2. 站名替换（先长后短）
    Replace-All $doc "高铁客运服务行业" "铁路客运服务行业"
    Replace-All $doc "高铁站" "南昌火车站"
    Write-Output "站名已替换为南昌火车站"

    # 3. 删除模板提示
    if (Remove-Para $doc "提供3-5张学生本人现场实践的照片") { Write-Output "已删: 提供3-5张提示" }
    if (Remove-Para $doc "本表调整为一页之内") { Write-Output "已删: 本表调整提示" }
    if (Remove-Text $doc "（注明签字人身份）") { Write-Output "已删: 注明签字人身份" }
    if (Remove-Text $doc "（学生政治思想表现、实践态度、纪律、工作情况、实践任务完成情况）") { Write-Output "已删: 政治思想表现提示" }

    # 删除"附：调查问卷基本要素"块（到"结尾：致谢语。"为止）
    $r1 = $doc.Content
    $r1.Find.ClearFormatting()
    $r1.Find.Text = "附：调查问卷基本要素"
    if ($r1.Find.Execute()) {
        $sp = $r1.Paragraphs.Item(1)
        $r2 = $doc.Content
        $r2.Find.ClearFormatting()
        $r2.Find.Text = "结尾：致谢语"
        if ($r2.Find.Execute()) {
            $ep = $r2.Paragraphs.Item(1)
            $del = $doc.Range($sp.Range.Start, $ep.Range.End)
            $del.Delete()
            Write-Output "已删: 调查问卷基本要素说明块"
        } else {
            Write-Output "警告：未找到'结尾：致谢语'"
        }
    } else {
        Write-Output "警告：未找到'附：调查问卷基本要素'"
    }

    # 4. 更新目录
    try {
        if ($doc.TablesOfContents.Count -gt 0) { $doc.TablesOfContents.Item(1).Update() }
        Write-Output "目录已更新"
    } catch { Write-Output "目录更新跳过" }

    # 5. 保存
    $saved = $false
    try {
        $doc.Save(); $saved = $true; Write-Output "已保存"
    } catch {
        Write-Output "Save 失败，改用 SaveAs2: $($_.Exception.Message)"
    }
    if (-not $saved) {
        try { $doc.SaveAs2($docPath, 0); $saved = $true; Write-Output "已通过 SaveAs2 保存" }
        catch { Write-Output "SaveAs2 失败: $($_.Exception.Message)" }
    }
    $doc.Close($false)
}
finally {
    $word.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
}
