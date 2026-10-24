# 生成 TNO:2WRW+LFB 简体中文补丁（本地 mod）
# 数据来源：
#   1) 合并版 mod 的英文本地化      ...\394360\3788892521\localisation          （LFB 合并版，v0.3.5）
#   2) 单体版 LFB 的现成简体中文    ...\394360\3350747146\localisation\simp_chinese
#   3) 2WRW Continued 的英文本地化  ...\394360\3649456037\localisation\english    （v1.5.5）
#   4) 2WRW-TNO 的简体中文          ...\394360\3449417512\localisation\simp_chinese（v1.6.99，作为 2WRW 译文来源）
#   5) TNO 汉化包（CN.Ver）         ...\394360\2243912940\localisation          （已覆盖的键不重复定义）
# 输出：Documents\Paradox Interactive\Hearts of Iron IV\mod\LFB_2WRW_zh_patch\
param(
  [string]$WorkshopRoot = 'E:\SteamLibrary\steamapps\workshop\content\394360',
  [string]$OutRoot = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Paradox Interactive\Hearts of Iron IV\mod')
)
$ErrorActionPreference = 'Stop'

$lfbMod = Join-Path $WorkshopRoot '3788892521'          # 合并版（LFB + 2WRW Continued 适配）
$lfbZhSrc = Join-Path $WorkshopRoot '3350747146'        # 单体版 LFB（含简中）
$wrwMod = Join-Path $WorkshopRoot '3649456037'          # 2WRW Continued（纯英文）
$wrwZhSrc = Join-Path $WorkshopRoot '3449417512'        # 2WRW-TNO（自带简中，作为译文来源）
$cnPack = Join-Path $WorkshopRoot '2243912940'          # TNO 汉化包

function Parse-LocFiles([string[]]$paths) {
  $map = @{}
  foreach ($p in $paths) {
    foreach ($line in [System.IO.File]::ReadAllLines($p)) {
      $t = $line.Trim()
      if ($t -eq '' -or $t.StartsWith('#')) { continue }
      if ($t -match '^l_(english|simp_chinese)\s*:$') { continue }
      if ($t -match '^([A-Za-z0-9_.\-]+)\s*:\s*\d*\s*"(.*)"\s*(?:#.*)?$') {
        $map[$matches[1]] = $matches[2]
      }
    }
  }
  return $map
}
function LocMap([string]$dir) {
  Parse-LocFiles (Get-ChildItem -LiteralPath $dir -Recurse -Filter *.yml -ErrorAction SilentlyContinue | ForEach-Object FullName)
}
function Has-CJK([string]$s) { return ($s -match '[\u4e00-\u9fff]') }
function Escape-Value([string]$v) { return [regex]::Replace($v, '(?<!\\)"', '\"') }

$lfb_en = LocMap (Join-Path $lfbMod 'localisation')
$lfb_zh = LocMap (Join-Path $lfbZhSrc 'localisation\simp_chinese')
$wrw_en = LocMap (Join-Path $wrwMod 'localisation\english')
$wrw_zh = LocMap (Join-Path $wrwZhSrc 'localisation\simp_chinese')
$wrw_zh_en = LocMap (Join-Path $wrwZhSrc 'localisation\english')
$cn_zh  = LocMap (Join-Path $cnPack 'localisation')

# ---------- A. LFB 合并版 ----------
$aKeys = @($lfb_en.Keys | Where-Object { -not $cn_zh.ContainsKey($_) } | Sort-Object)
$aZhFromLfb = 0; $aZhFrom2wrw = 0; $aEn = 0; $aRows = New-Object System.Collections.Generic.List[object]
foreach ($k in $aKeys) {
  if ($lfb_zh.ContainsKey($k)) { $v = $lfb_zh[$k]; $aZhFromLfb++ }
  elseif ($wrw_zh.ContainsKey($k) -and (Has-CJK $wrw_zh[$k])) { $v = $wrw_zh[$k]; $aZhFrom2wrw++ }
  else { $v = $lfb_en[$k]; $aEn++ }
  $aRows.Add([pscustomobject]@{ Key = $k; Val = $v })
}

# ---------- B. 2WRW Continued ----------
# 已由汉化包覆盖的键跳过；与 LFB 合并版重名的键归入 A 段（合并版后加载，优先）
$bKeys = @($wrw_en.Keys | Where-Object { -not $cn_zh.ContainsKey($_) -and -not $lfb_en.ContainsKey($_) } | Sort-Object)
$bZh = 0; $bEn = 0; $bRows = New-Object System.Collections.Generic.List[object]
foreach ($k in $bKeys) {
  $safe = $wrw_zh.ContainsKey($k) -and (Has-CJK $wrw_zh[$k]) -and
          $wrw_zh_en.ContainsKey($k) -and $wrw_zh_en[$k] -eq $wrw_en[$k]
  if ($safe) { $v = $wrw_zh[$k]; $bZh++ } else { $v = $wrw_en[$k]; $bEn++ }
  $bRows.Add([pscustomobject]@{ Key = $k; Val = $v })
}

# ---------- 写出 ----------
$utf8bom = New-Object System.Text.UTF8Encoding($true)
$outDir = Join-Path $OutRoot 'LFB_2WRW_zh_patch'
$locDir = Join-Path $outDir 'localisation\simp_chinese'
New-Item -ItemType Directory -Force -Path $locDir | Out-Null

function Write-LocFile([string]$path, $rows) {
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('l_simp_chinese:')
  foreach ($r in $rows) { $lines.Add(' ' + $r.Key + ': "' + (Escape-Value $r.Val) + '"') }
  [System.IO.File]::WriteAllLines($path, $lines, $utf8bom)
}
Write-LocFile (Join-Path $locDir 'LFB_zh_l_simp_chinese.yml') $aRows
Write-LocFile (Join-Path $locDir '2WRW_Continued_zh_l_simp_chinese.yml') $bRows
# 旧版本单文件，若存在则删除，避免重复定义
$old = Join-Path $locDir 'LFB_2WRW_zh_l_simp_chinese.yml'
if (Test-Path $old) { Remove-Item -LiteralPath $old -Force }

$modFile = @'
version="1.1"
tags={
	"Translation"
}
name="TNO 2WRW+LFB 简体中文补丁"
supported_version="1.19.*"
'@
[System.IO.File]::WriteAllText((Join-Path $OutRoot 'LFB_2WRW_zh_patch.mod'), $modFile, $utf8bom)
[System.IO.File]::WriteAllText((Join-Path $outDir 'descriptor.mod'), $modFile, $utf8bom)

"=== A. LFB 合并版（3788892521） ==="
"  keys: $($aKeys.Count)  | 中文: $($aZhFromLfb + $aZhFrom2wrw) (LFB源 $aZhFromLfb + 2WRW源 $aZhFrom2wrw) | 英文兜底: $aEn"
"=== B. 2WRW Continued（3649456037） ==="
"  keys: $($bKeys.Count)  | 中文: $bZh | 英文兜底: $bEn"
"=== 输出文件 ==="
Get-ChildItem -LiteralPath $locDir | ForEach-Object { "  {0}  {1:N0} KB" -f $_.Name, ($_.Length / 1KB) }
