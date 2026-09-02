# 生成"南昌西站"电子印章 PNG（圆形红章样式）

Add-Type -AssemblyName System.Drawing

$size = 600
$bmp = New-Object System.Drawing.Bitmap($size, $size)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)

$red = [System.Drawing.Color]::FromArgb(255, 200, 16, 46)
$brush = New-Object System.Drawing.SolidBrush($red)

$cx = 300; $cy = 300

# 外粗圆环
$penOuter = New-Object System.Drawing.Pen($red, 14)
$g.DrawEllipse($penOuter, 30, 30, 540, 540)

# 内细圆环
$penInner = New-Object System.Drawing.Pen($red, 3)
$g.DrawEllipse($penInner, 68, 68, 464, 464)

# 上方环绕单位名称
$text = "南昌西站"
$font = New-Object System.Drawing.Font("黑体", 60, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$R2 = 238
$n = $text.Length
$startDeg = -158; $endDeg = -22
for ($i = 0; $i -lt $n; $i++) {
    $deg = $startDeg + ($endDeg - $startDeg) * $i / ($n - 1)
    $rad = $deg * [Math]::PI / 180
    $x = $cx + $R2 * [Math]::Cos($rad)
    $y = $cy + $R2 * [Math]::Sin($rad)
    $g.TranslateTransform($x, $y)
    $g.RotateTransform($deg + 90)
    $g.DrawString($text[$i].ToString(), $font, $brush, -14, -19)
    $g.ResetTransform()
}

# 中心五角星
$starR = 82
$pts = New-Object 'System.Drawing.PointF[]' 10
for ($k = 0; $k -lt 10; $k++) {
    $rr = if ($k % 2 -eq 0) { $starR } else { $starR * 0.42 }
    $ang = -90 + $k * 36
    $rad = $ang * [Math]::PI / 180
    $pts[$k] = New-Object System.Drawing.PointF(($cx + $rr * [Math]::Cos($rad)), ($cy + $rr * [Math]::Sin($rad)))
}
$g.FillPolygon($brush, $pts)

$g.Dispose()
$out = 'D:\qqdownloads\南昌西站电子印章.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "印章已生成: $out"
