# 附录改造：10份文本样本 -> 表2 调查对象原始数据表格（Excel形式打印）

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$base = 'E:\Git\docgen'
$contentJson = [System.IO.File]::ReadAllText("$base\report_content.json", $utf8)
$dataJson = [System.IO.File]::ReadAllText("$base\survey_data.json", $utf8)
$content = $contentJson | ConvertFrom-Json
$data = ($dataJson | ConvertFrom-Json).data
$q = $content.questionnaire

$docPath = 'D:\qqdownloads\《劳动教育与社会调查》综合报告模板.doc'

$optLetters = @("A", "B", "C", "D", "E")

# 10个对象的样本索引
$samples = @()
foreach ($sidx in $content.samples) { $samples += [int]$sidx }

# 每行对象答案 -> 15个单元格文本
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

# 构造选项注释文本
$noteLines = New-Object System.Collections.ArrayList
[void]$noteLines.Add("注：表2中各题选项字母含义如下——")
for ($i = 0; $i -lt 15; $i++) {
    $qq = if ($i -lt 3) { $q.basic[$i] } else { $q.core[$i - 3] }
    $multi = if ($i -eq 3) { "（多选）" } else { "" }
    $head = "第" + ($i + 1).ToString() + "题" + $multi + "：" + ($qq.options -join "　")
    [void]$noteLines.Add($head)
}
$noteText = ($noteLines -join "`r")

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0

try {
    $doc = $word.Documents.Open($docPath, $false, $false)

    # 1. 删除旧的文本样本区（到"表1"标题前）
    $rng = $doc.Content
    $rng.Find.ClearFormatting()
    $rng.Find.Text = "以下为随机抽取的10份填写完成的问卷样本"
    if (-not $rng.Find.Execute()) { throw "未找到样本区起始段" }
    $startPara = $rng.Paragraphs.Item(1)
    $pos = $startPara.Range.Start
    $p = $startPara
    $guard = 0
    while ($p -ne $null -and $guard -lt 100) {
        $txt = $p.Range.Text
        if ($txt -like "*表1*") { break }
        $next = $p.Next()
        $p.Range.Delete()
        $p = $next
        $guard++
    }
    Write-Output "旧文本样本区已删除（$guard 段）"

    # 2. 插入表2标题
    $ins = $doc.Range($pos, $pos)
    $ins.InsertAfter("以下为线上调查中随机抽取的10名调查对象的原始作答数据（以表格形式打印，选项字母含义见表格下方注释）：`r表2　调查对象原始数据（N=10，线上问卷作答记录）`r")

    # 3. 建表 11 行 x 16 列
    $tblRng = $doc.Content
    $tblRng.Find.ClearFormatting()
    $tblRng.Find.Text = "表2　调查对象原始数据"
    if (-not $tblRng.Find.Execute()) { throw "未找到表2标题" }
    $tp = $tblRng.Paragraphs.Item(1)
    $after = $doc.Range($tp.Range.End, $tp.Range.End)
    $table = $doc.Tables.Add($after, 11, 16)
    $table.Borders.Enable = $true
    $table.Range.Font.Name = "宋体"
    $table.Range.Font.Size = 8
    $table.Range.ParagraphFormat.Alignment = 1

    # 表头
    $table.Cell(1, 1).Range.Text = "编号"
    for ($j = 0; $j -lt 15; $j++) {
        $table.Cell(1, $j + 2).Range.Text = "第" + ($j + 1).ToString() + "题"
    }
    $table.Rows.Item(1).Range.Font.Bold = $true

    # 数据行
    for ($i = 0; $i -lt $samples.Count; $i++) {
        $rec = $data[$samples[$i]]
        $row = Get-AnswerRow $rec
        $table.Cell($i + 2, 1).Range.Text = ($i + 1).ToString()
        for ($j = 0; $j -lt 15; $j++) {
            $table.Cell($i + 2, $j + 2).Range.Text = $row[$j]
        }
    }

    # 列宽（编号 30pt，每题 24pt；总 30+360=390pt≈13.8cm，A4 纵向可容纳）
    try {
        $table.Columns.Item(1).Width = 30
        for ($j = 2; $j -le 16; $j++) { $table.Columns.Item([int]$j).Width = 24 }
    } catch { Write-Output "列宽设置跳过" }

    # 4. 表格后插入选项注释
    $lastRowEnd = $table.Rows.Item(11).Range.End
    $noteRng = $doc.Range($lastRowEnd, $lastRowEnd)
    $noteRng.InsertAfter("`r" + $noteText)
    Write-Output "表2与选项注释已插入"

    # 5. 更新目录、保存
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
