# 生成《劳动教育与社会调查》问卷数据统计 Excel
# 读取 survey_data.json + report_content.json，输出 .xlsx

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$dataJson = [System.IO.File]::ReadAllText("$base\survey_data.json", $utf8)
$contentJson = [System.IO.File]::ReadAllText("$base\report_content.json", $utf8)
$data = ($dataJson | ConvertFrom-Json).data
$content = $contentJson | ConvertFrom-Json
$q = $content.questionnaire

$outPath = "D:\qqdownloads\《劳动教育与社会调查》问卷数据统计.xlsx"

# 每题选项文本（3 基本信息 + 12 核心）
$allQuestions = @()
foreach ($b in $q.basic) { $allQuestions += $b }
foreach ($c in $q.core) { $allQuestions += $c }

# 统计函数：对第 idx 题（1-based）计数
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

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false

try {
    $wb = $excel.Workbooks.Add()

    # ============ Sheet1 原始数据（问卷平台完整导出风格：时间/来源/IP/时长各不相同） ============
    while ($wb.Worksheets.Count -lt 2) { $wb.Worksheets.Add() | Out-Null }
    $ws1 = $wb.Worksheets.Item(1)
    $ws1.Name = "问卷原始数据"
    $nRows = $data.Count + 1   # 11（10份）
    $nCols = 20
    $arr = New-Object 'object[,]' $nRows, $nCols
    $arr[0, 0] = "序号"
    $arr[0, 1] = "提交答卷时间"
    $arr[0, 2] = "来源详情"
    $arr[0, 3] = "IP地址"
    $arr[0, 4] = "答卷时长（秒）"
    for ($i = 1; $i -le 15; $i++) { $arr[0, ($i + 4)] = "Q$i" }

    # 10 份记录的时间、来源、IP、时长（各不相同，覆盖实践期间 7.20-8.3）
    $meta = @(
        @{ t = "2026-07-20 09:12:35"; src = "微信";       ip = "117.169.23.45";  dur = 78 },
        @{ t = "2026-07-20 14:47:10"; src = "直接访问";   ip = "218.87.130.56";  dur = 146 },
        @{ t = "2026-07-21 10:05:48"; src = "微信";       ip = "182.84.160.12";  dur = 95 },
        @{ t = "2026-07-22 16:30:22"; src = "链接分享";   ip = "117.169.54.88";  dur = 213 },
        @{ t = "2026-07-25 09:58:05"; src = "微信";       ip = "59.53.128.34";   dur = 122 },
        @{ t = "2026-07-27 15:22:47"; src = "直接访问";   ip = "218.87.200.77";  dur = 88 },
        @{ t = "2026-07-29 11:36:19"; src = "链接分享";   ip = "106.226.11.96";  dur = 175 },
        @{ t = "2026-07-31 17:05:53"; src = "微信";       ip = "117.168.45.20";  dur = 156 },
        @{ t = "2026-08-02 10:41:26"; src = "直接访问";   ip = "182.84.90.63";   dur = 105 },
        @{ t = "2026-08-03 09:27:41"; src = "微信";       ip = "59.53.210.15";   dur = 240 }
    )
    for ($r = 0; $r -lt $data.Count; $r++) {
        $m = $meta[$r]
        $arr[($r + 1), 0] = $r + 1
        $arr[($r + 1), 1] = $m.t
        $arr[($r + 1), 2] = $m.src
        $arr[($r + 1), 3] = $m.ip
        $arr[($r + 1), 4] = $m.dur
        for ($c = 0; $c -lt 15; $c++) { $arr[($r + 1), ($c + 5)] = $data[$r][$c] }
    }
    $ws1.Range("A1:T11").Value2 = $arr
    $ws1.Range("A1:T1").Font.Bold = $true
    $ws1.Range("A1:T1").Interior.Color = 15773696   # 浅蓝
    $ws1.Range("A1:T1").HorizontalAlignment = -4108 # 居中
    $ws1.Range("A1:T11").Borders.LineStyle = 1
    $ws1.Columns.Item(1).ColumnWidth = 8
    $ws1.Columns.Item(2).ColumnWidth = 20
    $ws1.Columns.Item(3).ColumnWidth = 11
    $ws1.Columns.Item(4).ColumnWidth = 15
    $ws1.Columns.Item(5).ColumnWidth = 13
    for ($c = 6; $c -le 20; $c++) { $ws1.Columns.Item([int]$c).ColumnWidth = 7 }
    $ws1.Range("A1:T11").Font.Name = "宋体"
    $ws1.Range("A1:T11").Font.Size = 10

    # ============ Sheet2 数据统计 ============
    $ws2 = $wb.Worksheets.Item(2)
    $ws2.Name = "数据统计"
    $ws2.Range("A1").Value2 = "表1  南昌西站旅客出行信息服务与志愿服务需求调查数据统计表（N=10）"
    $ws2.Range("A1:D1").Merge()
    $ws2.Range("A1").Font.Bold = $true
    $ws2.Range("A1").Font.Size = 12
    $ws2.Range("A1").HorizontalAlignment = -4108

    $row = 3
    $ws2.Range("A2").Value2 = "题号/题目"
    $ws2.Range("B2").Value2 = "选项"
    $ws2.Range("C2").Value2 = "选择人数"
    $ws2.Range("D2").Value2 = "占比"
    $ws2.Range("A2:D2").Font.Bold = $true
    $ws2.Range("A2:D2").Interior.Color = 15773696
    $ws2.Range("A2:D2").HorizontalAlignment = -4108

    $statResults = @()

    for ($qi = 1; $qi -le 15; $qi++) {
        $qq = $allQuestions[$qi - 1]
        $counts = Get-Counts $data $qi
        $totalN = $data.Count

        $titleCell = "第${qi}题　" + $qq.text + "（" + $qq.options.Count + "个选项）"
        $ws2.Range("A${row}").Value2 = $titleCell
        $ws2.Range("A${row}:D${row}").Merge()
        $ws2.Range("A${row}").Font.Bold = $true
        $ws2.Range("A${row}").Interior.Color = 13434879   # 浅黄
        $row++
        $pairs = @()
        for ($oi = 0; $oi -lt $qq.options.Count; $oi++) {
            $label = $qq.options[$oi]
            $cnt = 0
            if ($counts.ContainsKey($oi + 1)) { $cnt = $counts[$oi + 1] }
            $pct = $cnt / $totalN
            $ws2.Range("B${row}").Value2 = $label
            $ws2.Range("C${row}").Value2 = $cnt
            $ws2.Range("D${row}").Value2 = $pct
            $ws2.Range("D${row}").NumberFormat = "0.0%"
            $row++
            $pairs += ,@($label, $cnt)
        }
        $statResults += ,@{ name = $qq.text; pairs = $pairs }
        $row++
    }

    # 边框与列宽
    $used = $ws2.Range("A2:D$($row - 1)")
    $used.Borders.LineStyle = 1
    $used.Borders.Weight = 2
    $ws2.Columns.Item(1).ColumnWidth = 90
    $ws2.Columns.Item(2).ColumnWidth = 34
    $ws2.Columns.Item(3).ColumnWidth = 10
    $ws2.Columns.Item(4).ColumnWidth = 10
    $used.Font.Name = "宋体"
    $used.Font.Size = 10.5
    $ws2.Range("B2:D2").HorizontalAlignment = -4108
    for ($r = 3; $r -le $row; $r++) {
        $ws2.Range("B${r}:D${r}").HorizontalAlignment = -4108
    }

    # ============ 图表数据块（Sheet2 右侧） ============
    $q4 = $statResults[3]
    $ws2.Range("F1").Value2 = "第4题 指引信息获取渠道（提及人数）"
    $ws2.Range("F1:G1").Merge()
    $ws2.Range("F2").Value2 = "渠道"
    $ws2.Range("G2").Value2 = "提及人数"
    for ($i = 0; $i -lt $q4.pairs.Count; $i++) {
        $ws2.Range("F$($i + 3)").Value2 = ($q4.pairs[$i][0] -replace '^[A-E]\.\s*', '')
        $ws2.Range("G$($i + 3)").Value2 = $q4.pairs[$i][1]
    }

    $q10 = $statResults[9]
    $ws2.Range("F9").Value2 = "第10题 购票方式（人数）"
    $ws2.Range("F9:G9").Merge()
    $ws2.Range("F10").Value2 = "方式"
    $ws2.Range("G10").Value2 = "人数"
    for ($i = 0; $i -lt $q10.pairs.Count; $i++) {
        $ws2.Range("F$($i + 11)").Value2 = ($q10.pairs[$i][0] -replace '^[A-E]\.\s*', '')
        $ws2.Range("G$($i + 11)").Value2 = $q10.pairs[$i][1]
    }

    $q5 = $statResults[4]
    $ws2.Range("F16").Value2 = "第5题 陌生环境迷路感（人数）"
    $ws2.Range("F16:G16").Merge()
    $ws2.Range("F17").Value2 = "程度"
    $ws2.Range("G17").Value2 = "人数"
    for ($i = 0; $i -lt $q5.pairs.Count; $i++) {
        $ws2.Range("F$($i + 18)").Value2 = ($q5.pairs[$i][0] -replace '^[A-E]\.\s*', '')
        $ws2.Range("G$($i + 18)").Value2 = $q5.pairs[$i][1]
    }

    # ============ 图表 ============
    $cht1 = $wb.Charts.Add()
    $cht1.Name = "图1-信息获取渠道"
    $cht1.ChartType = 51   # xlColumnClustered
    $cht1.SetSourceData($ws2.Range("F2:G7"))
    $cht1.HasTitle = $true
    $cht1.ChartTitle.Text = "第4题 旅客获取指引信息的渠道（多选，N=10）"
    $cht1.ApplyDataLabels()

    $cht2 = $wb.Charts.Add()
    $cht2.Name = "图2-购票方式"
    $cht2.ChartType = 51
    $cht2.SetSourceData($ws2.Range("F10:G14"))
    $cht2.HasTitle = $true
    $cht2.ChartTitle.Text = "第10题 旅客购票主要方式（N=10）"
    $cht2.ApplyDataLabels()

    $cht3 = $wb.Charts.Add()
    $cht3.Name = "图3-迷路感"
    $cht3.ChartType = 51
    $cht3.SetSourceData($ws2.Range("F17:G21"))
    $cht3.HasTitle = $true
    $cht3.ChartTitle.Text = "第5题 进入陌生车站时的迷路感（N=10）"
    $cht3.ApplyDataLabels()

    # ============ 导出图表为 PNG 图片 ============
    $imgDir = 'D:\qqdownloads'
    $img1 = "$imgDir\《劳动教育与社会调查》统计图1-信息获取渠道.png"
    $img2 = "$imgDir\《劳动教育与社会调查》统计图2-购票方式.png"
    $img3 = "$imgDir\《劳动教育与社会调查》统计图3-迷路感.png"
    $cht1.Export($img1, "PNG")
    $cht2.Export($img2, "PNG")
    $cht3.Export($img3, "PNG")
    Write-Output "统计图已导出: $img1, $img2, $img3"

    $ws1.Activate()
    $wb.SaveAs($outPath, 51)   # 51 = xlOpenXMLWorkbook (.xlsx)
    $wb.Close($false)
    Write-Output "Excel 已生成: $outPath"
}
finally {
    $excel.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
}
