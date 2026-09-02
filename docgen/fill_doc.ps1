# 用 Word COM 将报告内容写入 .doc 模板
# 读取 report_content.json + survey_data.json

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

# 每题对象（3 基本信息 + 12 核心）
$allQuestions = @()
foreach ($b in $q.basic) { $allQuestions += $b }
foreach ($c in $q.core) { $allQuestions += $c }

function Convert-LfToCr($t) {
    return $t.Replace("`n", "`r")
}

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

# 按关键词替换所在段落（保留段落标记）
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
$word.DisplayAlerts = 0   # wdAlertsNone

try {
    $doc = $word.Documents.Open($docPath, $false, $false)

    # ============ 1. 封面题目 ============
    $rngT = $doc.Content
    $rngT.Find.ClearFormatting()
    $rngT.Find.Text = "以XX实践和XX调查为例"
    if ($rngT.Find.Execute()) {
        $rngT.Text = "以南昌西站志愿服务实践和旅客出行服务问卷调查为例"
        Write-Output "封面题目已替换"
    } else {
        Write-Output "警告：未找到封面题目占位"
    }

    # ============ 2. 正文各节替换 ============
    $map = @(
        @{ key = "简述本课程的背景";       text = $s.intro },
        @{ key = "概述实践时间";           text = $s.p2_1 },
        @{ key = "选取实践过程中出现";     text = $s.p2_2 },
        @{ key = "梳理与该行业有关的问题"; text = $s.s3_1 },
        @{ key = "明确调查对象和问卷数量"; text = $s.s3_2 },
        @{ key = "利用 Excel 进行基础数据统计"; text = $s.s3_3 },
        @{ key = "结合问卷数据分析结果";   text = $s.s3_4 },
        @{ key = "总结在劳动实践和社会调查过程中的收获"; text = $s.s4 },
        @{ key = "对本次劳动教育与社会调查全过程进行简略总结"; text = $s.s5 }
    )
    foreach ($m in $map) {
        if (Replace-ParaByFind $doc $m.key $m.text) {
            Write-Output "已替换: $($m.key)"
        } else {
            Write-Output "警告：未找到: $($m.key)"
        }
    }

    # ============ 3. 附录：调查问卷样本 ============
    $anchor = $null
    foreach ($p in $doc.Paragraphs) {
        if ($p.Range.Text -like "*提供10份问卷样本*") { $anchor = $p; break }
    }
    if ($anchor -eq $null) {
        Write-Output "警告：未找到'提供10份问卷样本'锚点"
    } else {
        # 构造问卷正文 + 10 份样本文本
        $lines = New-Object System.Collections.ArrayList
        [void]$lines.Add($q.title)
        [void]$lines.Add("")
        [void]$lines.Add($q.preamble)
        [void]$lines.Add("")
        [void]$lines.Add($q.part1)
        foreach ($b in $q.basic) {
            [void]$lines.Add($b.text)
            [void]$lines.Add(($b.options -join "　"))
        }
        [void]$lines.Add("")
        [void]$lines.Add($q.part2)
        foreach ($c in $q.core) {
            [void]$lines.Add($c.text)
            [void]$lines.Add(($c.options -join "　"))
        }
        [void]$lines.Add("")
        [void]$lines.Add($q.thanks)
        [void]$lines.Add("")
        [void]$lines.Add("以下为线上调查中随机抽取的10名调查对象的原始作答数据（以表格形式打印，选项字母含义见表格下方注释）：")
        [void]$lines.Add("表2　调查对象原始数据（N=10，线上问卷作答记录）")
        [void]$lines.Add("")
        [void]$lines.Add("表1　南昌西站旅客出行信息服务与志愿服务需求调查数据统计表（N=10）")

        $insertText = ($lines -join "`r") + "`r"
        $rngIns = $anchor.Range
        $rngIns.Collapse(0)   # wdCollapseEnd
        $rngIns.InsertAfter($insertText)
        Write-Output "问卷正文已插入"

        # ============ 3b. 附录：表2 调查对象原始数据表格 ============
        $optLetters = @("A", "B", "C", "D", "E")
        $samples = @()
        foreach ($sidx in $content.samples) { $samples += [int]$sidx }
        function Get-AnswerRow($rec) {
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
        $tblRng2 = $doc.Content
        $tblRng2.Find.ClearFormatting()
        $tblRng2.Find.Text = "表2　调查对象原始数据"
        if ($tblRng2.Find.Execute()) {
            $tp2 = $tblRng2.Paragraphs.Item(1)
            $after2 = $doc.Range($tp2.Range.End, $tp2.Range.End)
            $table2 = $doc.Tables.Add($after2, 11, 16)
            $table2.Borders.Enable = $true
            $table2.Range.Font.Name = "宋体"
            $table2.Range.Font.Size = 8
            $table2.Range.ParagraphFormat.Alignment = 1
            $table2.Cell(1, 1).Range.Text = "编号"
            for ($j = 0; $j -lt 15; $j++) { $table2.Cell(1, $j + 2).Range.Text = "第" + ($j + 1).ToString() + "题" }
            $table2.Rows.Item(1).Range.Font.Bold = $true
            for ($i = 0; $i -lt $samples.Count; $i++) {
                $rec = $data[$samples[$i]]
                $row = Get-AnswerRow $rec
                $table2.Cell($i + 2, 1).Range.Text = ($i + 1).ToString()
                for ($j = 0; $j -lt 15; $j++) { $table2.Cell($i + 2, $j + 2).Range.Text = $row[$j] }
            }
            try {
                $table2.Columns.Item(1).Width = 30
                for ($j = 2; $j -le 16; $j++) { $table2.Columns.Item([int]$j).Width = 24 }
            } catch { }
            $lastEnd = $table2.Rows.Item(11).Range.End
            $noteLines = New-Object System.Collections.ArrayList
            [void]$noteLines.Add("注：表2中各题选项字母含义如下——")
            for ($i = 0; $i -lt 15; $i++) {
                $qq = if ($i -lt 3) { $q.basic[$i] } else { $q.core[$i - 3] }
                $multi = if ($i -eq 3) { "（多选）" } else { "" }
                [void]$noteLines.Add("第" + ($i + 1).ToString() + "题" + $multi + "：" + ($qq.options -join "　"))
            }
            $noteRng = $doc.Range($lastEnd, $lastEnd)
            $noteRng.InsertAfter("`r" + ($noteLines -join "`r"))
            Write-Output "表2原始数据表格与注释已插入"
        }

        # ============ 4. 附录：问卷数据统计表 ============
        $tblRng = $doc.Content
        $tblRng.Find.ClearFormatting()
        $tblRng.Find.Text = "数据统计表（N=10）"
        if ($tblRng.Find.Execute()) {
            $tp = $tblRng.Paragraphs.Item(1)
            $after = $doc.Range($tp.Range.End, $tp.Range.End)
            $totalRows = 1   # 表头行
            for ($i = 1; $i -le 15; $i++) { $totalRows += 1 + $allQuestions[$i - 1].options.Count }
            $table = $doc.Tables.Add($after, $totalRows, 3)
            $table.Borders.Enable = $true
            $table.Range.Font.Name = "宋体"
            $table.Range.Font.Size = 9
            $table.Range.ParagraphFormat.Alignment = 1   # 居中
            $table.Cell(1, 1).Range.Text = "题号/题目"
            $table.Cell(1, 2).Range.Text = "人数"
            $table.Cell(1, 3).Range.Text = "占比"
            $table.Rows.Item(1).Range.Font.Bold = $true
            $rr = 2
            for ($qi = 1; $qi -le 15; $qi++) {
                $qq = $allQuestions[$qi - 1]
                $counts = Get-Counts $data $qi
                $table.Cell($rr, 1).Range.Text = "第${qi}题　" + $qq.text
                $table.Cell($rr, 1).Merge($table.Cell($rr, 3))
                $rr++
                for ($oi = 0; $oi -lt $qq.options.Count; $oi++) {
                    $cnt = 0
                    if ($counts.ContainsKey($oi + 1)) { $cnt = $counts[$oi + 1] }
                    $pct = [Math]::Round($cnt / 10.0 * 100, 1)
                    $table.Cell($rr, 1).Range.Text = $qq.options[$oi]
                    $table.Cell($rr, 2).Range.Text = $cnt.ToString()
                    $table.Cell($rr, 3).Range.Text = $pct.ToString("0.0") + "%"
                    $rr++
                }
            }
            try {
                $table.AutoFitBehavior(1)   # wdAutoFitWindow
                $table.Columns.Item(1).Width = 260
                $table.Columns.Item(2).Width = 55
                $table.Columns.Item(3).Width = 55
            } catch {
                Write-Output "列宽设置跳过（表格保持默认宽度）"
            }
            Write-Output "问卷数据统计表已插入（${totalRows}行）"
        } else {
            Write-Output "警告：未找到统计表标题"
        }
    }

    # ============ 5. 更新目录与页码域 ============
    try {
        if ($doc.TablesOfContents.Count -gt 0) {
            $doc.TablesOfContents.Item(1).Update()
            Write-Output "目录已更新"
        }
    } catch {
        Write-Output "目录更新跳过: $($_.Exception.Message)"
    }
    try {
        $doc.Fields.Update()
        Write-Output "页码域已更新"
    } catch {
        Write-Output "页码域更新跳过"
    }

    # ============ 6. 保存 ============
    $saved = $false
    try {
        $doc.Save()
        $saved = $true
        Write-Output "文档已保存: $docPath"
    } catch {
        Write-Output "Save 失败，改用 SaveAs2 重存: $($_.Exception.Message)"
    }
    if (-not $saved) {
        try {
            $doc.SaveAs2($docPath, 0)   # 0 = wdFormatDocument97 (.doc)
            $saved = $true
            Write-Output "文档已通过 SaveAs2 保存: $docPath"
        } catch {
            Write-Output "SaveAs2 也失败: $($_.Exception.Message)"
        }
    }
    if ($saved) {
        $doc.Close($false)
    } else {
        $doc.Close($false)
    }
}
finally {
    $word.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
}
