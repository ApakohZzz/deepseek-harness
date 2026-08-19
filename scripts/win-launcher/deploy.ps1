# ============================================================
# deploy.ps1 - 将 win-launcher 脚本部署到外层壳的 bin 目录
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File deploy.ps1 [-TargetBin <dir>]
# 默认目标: 仓库根的父目录下的 bin（即外层部署壳）
# ============================================================
param(
  [string]$TargetBin = ''
)

$ErrorActionPreference = 'Stop'
$src       = $PSScriptRoot
$repoRoot  = Split-Path -Parent (Split-Path -Parent $src)   # win-launcher -> scripts -> repo
$shellRoot = Split-Path -Parent $repoRoot                     # 外层部署壳
if (-not $TargetBin) { $TargetBin = Join-Path $shellRoot 'bin' }

if (-not (Test-Path $TargetBin)) {
  Write-Error "目标目录不存在: $TargetBin（可用 -TargetBin 指定）"
}

$files = 'dsh-control.ps1', 'start-dsh.bat', 'stop-dsh.bat', 'status-dsh.bat', 'make-shortcuts.ps1', 'deepseek.ico'
foreach ($f in $files) {
  Copy-Item (Join-Path $src $f) $TargetBin -Force
  Write-Host "[OK] $f -> $TargetBin" -ForegroundColor Green
}

# 重建快捷方式（指向部署后的 bin）
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $TargetBin 'make-shortcuts.ps1')
Write-Host "`n部署完成。运行时产物 (dsh.log / dsh.pid 等) 继续留在 $TargetBin" -ForegroundColor Cyan
