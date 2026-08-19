# ============================================================
# update-dsh.ps1 - 一键更新：同步官方 -> 合并 my-dsh -> 构建 -> 重启
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File update-dsh.ps1 [-NoBuild] [-NoRestart] [-NoBrowser] [-NoPush]
# 官方无更新时秒退，不做任何动作
# ============================================================
[CmdletBinding()]
param(
  [switch]$NoBuild,    # 跳过 pnpm install + build
  [switch]$NoRestart,  # 跳过重启 dsh
  [switch]$NoBrowser,  # 重启后不开浏览器
  [switch]$NoPush      # 只本地同步，不推送 fork
)

$ErrorActionPreference = 'Stop'

# ---- 路径 -------------------------------------------------------
$BinDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $BinDir
$RepoDir = if (Test-Path (Join-Path $RootDir 'apps\cli\package.json')) { $RootDir }
           elseif (Test-Path (Join-Path $RootDir 'deepseek-harness\apps\cli\package.json')) { Join-Path $RootDir 'deepseek-harness' }
           elseif (Test-Path (Join-Path $RootDir 'deepseek-harness-master\apps\cli\package.json')) { Join-Path $RootDir 'deepseek-harness-master' }
           else { Join-Path $RootDir 'deepseek-harness' }

function Write-Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Info($msg) { Write-Host "     $msg"  -ForegroundColor Gray }
function Write-Err2($msg) { Write-Host "[XX] $msg" -ForegroundColor Red }

function Get-Ver {
  try { return ([IO.File]::ReadAllText((Join-Path $RepoDir 'apps\cli\package.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json).version } catch { '?' }
}

function Invoke-Git([string[]]$GitArgs) {
  # git 身份未配置时兜底（仅本次命令，不写入配置）
  $pre = @()
  if (-not (git config user.name)) { $pre = @('-c','user.name=ApakohZzz','-c','user.email=ApakohZzz@users.noreply.github.com') }
  & git @pre @GitArgs
  return $LASTEXITCODE
}

# ---- 开始 -------------------------------------------------------
Set-Location $RepoDir
$OldVer = Get-Ver
Write-Host '===== dsh 一键更新 =====' -ForegroundColor Cyan
Write-Info "当前版本: v$OldVer"

# 0. 工作区必须干净
if ((git status --porcelain).Count -gt 0) {
  Write-Err2 '工作区有未提交的改动，请先提交或暂存 (git stash) 后再更新'
  exit 1
}

# 1. 拉取官方与 fork
Write-Host '正在检查官方更新 ...' -NoNewline
git fetch upstream 2>&1 | Out-Null
git fetch origin    2>&1 | Out-Null
$behind = [int](git rev-list --count master..upstream/master)
if ($behind -eq 0) {
  Write-Host ''
  Write-Ok "已是最新 (v$OldVer)，无需更新"
  exit 0
}
Write-Host " 落后 $behind 个提交"

# 2. master 快进到官方最新（master 保持零私有提交，永远可快进）
[void](Invoke-Git @('switch','master'))
if ((Invoke-Git @('merge','--ff-only','upstream/master')) -ne 0) {
  Write-Err2 'master 快进失败（不应发生，可能有本地提交），请手动检查'
  exit 1
}
Write-Ok 'master 已同步官方'
if (-not $NoPush) { git push origin master 2>&1 | Out-Null; Write-Ok 'fork 的 master 已推送' }

# 3. 官方进展并入 my-dsh
[void](Invoke-Git @('switch','my-dsh'))
Write-Host '正在合并进 my-dsh ...'
if ((Invoke-Git @('merge','master','--no-edit')) -ne 0) {
  git merge --abort 2>$null
  Write-Err2 '合并出现冲突，已自动回滚。请手动执行: git switch my-dsh; git merge master 后解决冲突'
  exit 1
}
Write-Ok 'my-dsh 已合并官方进展'
if (-not $NoPush) { git push origin my-dsh 2>&1 | Out-Null; Write-Ok 'fork 的 my-dsh 已推送' }

# 4. 重建
if (-not $NoBuild) {
  Write-Host '正在安装依赖与构建（可能需要几分钟）...'
  pnpm.cmd install 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Err2 'pnpm install 失败'; exit 1 }
  pnpm.cmd run build 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Err2 'pnpm run build 失败'; exit 1 }
  Write-Ok '构建完成'
} else {
  Write-Info '已跳过构建 (-NoBuild)'
}

# 5. 重启生效
$NewVer = Get-Ver
if (-not $NoRestart) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BinDir 'dsh-control.ps1') -Action restart $(if ($NoBrowser) { '-NoBrowser' })
} else {
  Write-Info '已跳过重启 (-NoRestart)'
}
Write-Host ''
Write-Host "===== 更新完成: v$OldVer -> v$NewVer =====" -ForegroundColor Cyan
