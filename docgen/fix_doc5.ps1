# 将 doc 更新为 10 份问卷统计口径 + 插入统计图图片

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$base = 'E:\Git\docgen'
$contentJson = [System.IO.File]::ReadAllText("$base\report_content.json", $utf8)
$dataJson = [System.IO.File]::ReadAllText("$base\survey_data.json", $utf8)
$content = $contentJson | ConvertFrom-Json
$data = ($dataJson | ConvertFrom-Json).data
$s = $content.sections
$q = $content.questionnaire

$docPath = 'D:\qqdownloads\《劳动教育与社会调查》综合报告模板.doc'

$allQuestions = @()
foreach ($b in $q.basic) { $allQuestions += $b }
foreach ($c in $q.core) { $allQuestions += $c }

function Convert-LfToCr($t) { return $t.Replace("`n", "`r") }

function Get-Counts($records, $idx) {
    $counts = @{}
    foreach ($rec in $records) {
        $val = $rec[$idx - 1]
        if ($val -is [string]) {
            foreach ($part in ($val -split ',')) {
                $k = [int]$part
                if ($counts.ContainsKey($k)) { $counts[$k]++ } else { $counts[$k] = 1 }
            }
        } else {
            $k = [int]$val
            if ($counts.ContainsKey($k)) { $counts[$k]++ } else { $counts[$k] = 1 }
        }
    }
    return $counts
}

function Get-AnswerRow($rec) {
    $optLetters = @("A", "B", "C", "D", "E")
    $row = @()
    for ($j = 0; $j -lt 15; $j++) {
        $val = $rec[$j]
        if ($val -is [string]) {
            $parts = @()
            foreach ($pp in ($val -split ',')) { $parts += $optLetters[[int]$pp - 1] }
            $row += ($parts -join "、")
        } else {
            $row += $optLetters[[int]$val - 1]
        }
    }
    return ,$row
}

function Replace-ParaByFind($doc, $matchKey, $newText) {
    $rng = $doc.Content
    $rng.Find.ClearFormatting()
    $rng.Find.Text = $matchKey
    if ($rng.Find.Execute()) {
        $para = $rng.Paragraphs.Item(1)
        $target = $doc.Range($para.Range.Start, $para.Range.End - 1)
        $target.Text = (Convert-LfToCr $newText)
        return $true
    }
    return $false
}

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0

try {
    $doc = $word.Documents.Open($docPath, $false, $false)

    # 1. 替换正文 4 段
    if (Replace-ParaByFind $doc "《劳动教育与社会调查》是华东交通大学开设的" $s.intro) { Write-Output "引言已更新" }
    if (Replace-ParaByFind $doc "本次调查以南昌西站出行的旅客" $s.s3_2) { Write-Output "3.2 已更新" }
    if (Replace-ParaByFind $doc "本部分利用Excel" $s.s3_3) { Write-Output "3.3 已更新" }
    if (Replace-ParaByFind $doc "通过问卷统计与分析" $s.s3_4) { Write-Output "3.4 已更新" }

    # 2. 表1标题 N=35 -> N=10
    $rngT = $doc.Content
    $rngT.Find.ClearFormatting()
    $rngT.Find.Replacement.ClearFormatting()
    $rngT.Find.Execute("数据统计表（N=35）", $false, $false, $false, $false, $false, $true, 1, $false, "数据统计表（N=10）", 2) | Out-Null
    Write-Output "表1标题已更新为 N=10"

    # 3. 重填表1（3列，80行）
    $tbl1 = $null
    foreach ($tb in $doc.Tables) {
        if ($tb.Columns.Count -eq 3 -and $tb.Cell(1, 1).Range.Text -like "*题号/题目*") { $tbl1 = $tb; break }
    }
    if ($tbl1) {
        $rr = 2
        for ($qi = 1; $qi -le 15; $qi++) {
            $qq = $allQuestions[$qi - 1]
            $counts = Get-Counts $data $qi
            $tbl1.Cell($rr, 1).Range.Text = "第${qi}题　" + $qq.text
            $rr++
            for ($oi = 0; $oi -lt $qq.options.Count; $oi++) {
                $cnt = 0
                if ($counts.ContainsKey($oi + 1)) { $cnt = $counts[$oi + 1] }
                $pct = [Math]::Round($cnt / 10.0 * 100, 1)
                $tbl1.Cell($rr, 1).Range.Text = $qq.options[$oi]
                $tbl1.Cell($rr, 2).Range.Text = $cnt.ToString()
                $tbl1.Cell($rr, 3).Range.Text = $pct.ToString("0.0") + "%"
                $rr++
            }
        }
        Write-Output "表1统计表已重填（N=10）"
    } else {
        Write-Output "警告：未找到表1"
    }

    # 4. 重填表2（16列，11行）
    $tbl2 = $null
    foreach ($tb in $doc.Tables) {
        if ($tb.Columns.Count -eq 16 -and $tb.Cell(1, 1).Range.Text -like "*编号*") { $tbl2 = $tb; break }
    }
    if ($tbl2) {
        for ($i = 0; $i -lt 10; $i++) {
            $rec = $data[$i]
            $row = Get-AnswerRow $rec
            $tbl2.Cell($i + 2, 1).Range.Text = ($i + 1).ToString()
            for ($j = 0; $j -lt 15; $j++) {
                $tbl2.Cell($i + 2, $j + 2).Range.Text = $row[$j]
            }
        }
        Write-Output "表2原始数据已重填"
    } else {
        Write-Output "警告：未找到表2"
    }

    # 5. 插入 3 张统计图（表1之后）
    if ($tbl1) {
        $imgs = @(
            @{ path = 'D:\qqdownloads\《劳动教育与社会调查》统计图1-信息获取渠道.png'; cap = "图1　第4题 旅客获取指引信息的渠道（多选，N=10）" },
            @{ path = 'D:\qqdownloads\《劳动教育与社会调查》统计图2-购票方式.png'; cap = "图2　第10题 旅客购票主要方式（N=10）" },
            @{ path = 'D:\qqdownloads\《劳动教育与社会调查》统计图3-迷路感.png'; cap = "图3　第5题 进入陌生车站时的迷路感（N=10）" }
        )
        $pos = $tbl1.Range.End
        foreach ($img in $imgs) {
            if (-not (Test-Path $img.path)) { Write-Output "图片不存在: $($img.path)"; continue }
            $imgRng = $doc.Range($pos, $pos)
            $shape = $doc.InlineShapes.AddPicture($img.path, $false, $true, $imgRng)
            try { $shape.Width = 320 } catch { }
            try { $shape.Range.ParagraphFormat.Alignment = 1 } catch { }
            $pos = $shape.Range.End
            $capRng = $doc.Range($pos, $pos)
            $capRng.InsertAfter("`r" + $img.cap + "`r")
            $pos = $capRng.End
            Write-Output "已插入图片: $($img.cap)"
        }
    }

    # 6. 更新目录、保存
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
