# ============================================================
# dsh-control.ps1 - DeepSeek Harness 启停控制脚本
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File dsh-control.ps1 <start|stop|restart|status|log>
# ============================================================
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet('start', 'stop', 'restart', 'status', 'log')]
  [string]$Action = 'start',

  [int]$Port = 3080,
  [switch]$NoBrowser,
  [switch]$NoNotify,
  [int]$Tail = 40,
  [switch]$Follow
)

$ErrorActionPreference = 'Stop'

# ---- 路径与常量 -------------------------------------------------
$BinDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $BinDir
# 仓库根探测：脚本在仓库内 (scripts/win-launcher) 时 RootDir 即仓库根；
# 在外层壳 bin 时，仓库根为 RootDir 下的 deepseek-harness（或旧名 deepseek-harness-master）
$RepoDir   = if (Test-Path (Join-Path $RootDir 'apps\cli\package.json')) { $RootDir }
             elseif (Test-Path (Join-Path $RootDir 'deepseek-harness\apps\cli\package.json')) { Join-Path $RootDir 'deepseek-harness' }
             elseif (Test-Path (Join-Path $RootDir 'deepseek-harness-master\apps\cli\package.json')) { Join-Path $RootDir 'deepseek-harness-master' }
             else { Join-Path $RootDir 'deepseek-harness' }
$CliJs     = Join-Path $RepoDir 'apps\cli\lib\bin.js'
$CliPkg    = Join-Path $RepoDir 'apps\cli\package.json'
$LogFile   = Join-Path $BinDir 'dsh.log'
$ErrLog    = "$LogFile.err"
$PidFile   = Join-Path $BinDir 'dsh.pid'
$IconFile  = Join-Path $BinDir 'deepseek.ico'
$Url       = "http://127.0.0.1:$Port"
$MaxLogMB  = 2
$StartTimeoutSec = 30
$StopTimeoutSec  = 8

# ---- 输出辅助 ---------------------------------------------------
function Write-Ok($msg)   { Write-Host "[OK] $msg"   -ForegroundColor Green }
function Write-Info($msg) { Write-Host "     $msg"    -ForegroundColor Gray }
function Write-Warn2($msg){ Write-Host "[!!] $msg"    -ForegroundColor Yellow }
function Write-Err2($msg) { Write-Host "[XX] $msg"    -ForegroundColor Red }

# ---- 气泡通知 ---------------------------------------------------
function Show-Balloon([string]$Title, [string]$Message, [string]$Type = 'Info') {
  if ($NoNotify) { return }
  try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $icon = if (Test-Path $IconFile) { New-Object System.Drawing.Icon($IconFile) }
            else { [System.Drawing.SystemIcons]::Information }
    $ni = New-Object System.Windows.Forms.NotifyIcon
    $ni.Icon = $icon
    $ni.Visible = $true
    $ni.BalloonTipTitle = $Title
    $ni.BalloonTipText = $Message
    $ni.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::$Type
    $ni.ShowBalloonTip(5000)
    Start-Sleep -Milliseconds 2500
    $ni.Dispose()
  } catch { }
}

# ---- 端口 / 进程 ------------------------------------------------
function Get-DshPid {
  # 返回监听本端口的进程 PID（去重，排除系统 PID 0/4）
  try {
    Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop |
      Select-Object -ExpandProperty OwningProcess -Unique |
      Where-Object { $_ -and $_ -gt 4 }
  } catch { @() }
}

function Get-DshVersion([string]$PkgPath) {
  try {
    if (Test-Path $PkgPath) {
      return ([IO.File]::ReadAllText($PkgPath, [Text.Encoding]::UTF8) |
        ConvertFrom-Json).version
    }
  } catch { }
  return $null
}

# 解析启动命令：优先项目内已构建的 CLI（随仓库更新），回退全局 dsh
function Resolve-DshCommand {
  $node = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($node -and (Test-Path $CliJs)) {
    $ver = Get-DshVersion $CliPkg
    return @{
      Exe   = $node.Source
      Args  = @("`"$CliJs`"", 'web')
      Label = "项目内 CLI v$ver"
    }
  }
  $dsh = Get-Command dsh.cmd, dsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($dsh) {
    $globalPkg = Join-Path $env:APPDATA "npm\node_modules\@deepseek-ai\dsh\package.json"
    $ver = Get-DshVersion $globalPkg
    return @{
      Exe   = $dsh.Source
      Args  = @('web')
      Label = "全局 dsh v$ver"
    }
  }
  return $null
}

function Wait-Port([bool]$WaitForUp, [int]$TimeoutSec) {
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    $up = [bool](Get-DshPid)
    if ($up -eq $WaitForUp) { return $true }
    Write-Host '.' -NoNewline -ForegroundColor DarkGray
    Start-Sleep -Milliseconds 500
  }
  return ($WaitForUp -eq [bool](Get-DshPid))
}

function Rotate-Log {
  foreach ($f in @($LogFile, $ErrLog)) {
    if ((Test-Path $f) -and ((Get-Item $f).Length -gt $MaxLogMB * 1MB)) {
      $old = "$f.old"
      Remove-Item $old -ErrorAction SilentlyContinue
      Move-Item $f $old
      Write-Info "日志 $(Split-Path -Leaf $f) 超过 ${MaxLogMB}MB，已轮转为 $(Split-Path -Leaf $old)"
    }
  }
}

# ---- 动作：start ------------------------------------------------
function Do-Start {
  $pids = @(Get-DshPid)
  if ($pids.Count -gt 0) {
    $proc = Get-Process -Id $pids[0] -ErrorAction SilentlyContinue
    $name = if ($proc) { $proc.ProcessName } else { '未知' }
    if ($proc -and $proc.ProcessName -match '^(node|dsh)') {
      Write-Ok "dsh 已在运行 (PID $($pids -join ', '))"
      Write-Info "Web UI : $Url"
      if (-not $NoBrowser) { Start-Process $Url }
      return 0
    }
    Write-Err2 "端口 $Port 已被其他程序占用: $name (PID $($pids -join ', '))"
    Write-Info "请关闭该程序，或用 -Port 指定其他端口后重试"
    return 1
  }

  $cmd = Resolve-DshCommand
  if (-not $cmd) {
    Write-Err2 "未找到可用的 dsh：项目内 CLI 未构建 ($CliJs)，且全局 PATH 中无 dsh"
    Write-Info "请先在仓库目录执行: pnpm install && pnpm run build"
    return 1
  }

  Rotate-Log
  Write-Host "正在启动 dsh web ($($cmd.Label)) " -NoNewline

  # 直接启动可执行文件，参数以数组传递（引号由 Start-Process 处理），
  # stdout / stderr 分别重定向，完全脱离当前会话
  Start-Process $cmd.Exe -ArgumentList $cmd.Args -WindowStyle Hidden `
    -RedirectStandardOutput $LogFile -RedirectStandardError $ErrLog | Out-Null

  if (-not (Wait-Port $true $StartTimeoutSec)) {
    Write-Host ''
    Write-Err2 "启动失败：端口 $Port 在 ${StartTimeoutSec}s 内未就绪"
    foreach ($f in @($ErrLog, $LogFile)) {
      if ((Test-Path $f) -and ((Get-Item $f).Length -gt 0)) {
        Write-Warn2 "$(Split-Path -Leaf $f) 最后 15 行:"
        Get-Content $f -Tail 15 -Encoding UTF8 | ForEach-Object { Write-Host "  | $_" -ForegroundColor DarkGray }
      }
    }
    return 1
  }

  $pids = @(Get-DshPid)
  [IO.File]::WriteAllText($PidFile, "$($pids -join ',')")
  Write-Host ''
  Write-Ok "dsh 已启动 (PID $($pids -join ', '))"
  Write-Info "Web UI : $Url"
  Write-Info "日志   : $LogFile"
  Show-Balloon 'DeepSeek Harness' "已启动 PID $($pids -join ', ')$([char]10)$Url"
  if (-not $NoBrowser) { Start-Process $Url }
  return 0
}

# ---- 动作：stop -------------------------------------------------
function Do-Stop {
  $pids = @(Get-DshPid)
  if ($pids.Count -eq 0) {
    # 端口无监听，但 PID 文件里的进程可能仍在（未监听状态），做兜底清理
    $stale = @()
    if (Test-Path $PidFile) {
      foreach ($p in (([IO.File]::ReadAllText($PidFile)) -split ',') | ForEach-Object { $_.Trim() }) {
        if ($p -match '^\d+$' -and (Get-Process -Id $p -ErrorAction SilentlyContinue)) { $stale += $p }
      }
      Remove-Item $PidFile -ErrorAction SilentlyContinue
    }
    if ($stale.Count -eq 0) {
      Write-Warn2 "dsh 未在运行 (端口 $Port 无监听)"
      Show-Balloon 'DeepSeek Harness' '未在运行' 'Warning'
      return 0
    }
    $pids = $stale
  }

  Write-Host "正在停止 dsh (PID $($pids -join ', ')) " -NoNewline
  foreach ($p in $pids) {
    taskkill /PID $p /T /F 2>&1 | Out-Null
  }
  Wait-Port $false $StopTimeoutSec | Out-Null
  Remove-Item $PidFile -ErrorAction SilentlyContinue
  Write-Host ''
  Write-Ok "dsh 已停止"
  Show-Balloon 'DeepSeek Harness' '已停止'
  return 0
}

# ---- 动作：status -----------------------------------------------
function Do-Status {
  $pids = @(Get-DshPid)
  Write-Host ''
  Write-Host '===== DeepSeek Harness 状态 =====' -ForegroundColor Cyan
  if ($pids.Count -gt 0) {
    $proc = Get-Process -Id $pids[0] -ErrorAction SilentlyContinue
    $name = if ($proc) { $proc.ProcessName } else { '?' }
    $mem  = if ($proc) { '{0:N0} MB' -f ($proc.WorkingSet64 / 1MB) } else { '-' }
    $start = if ($proc) { $proc.StartTime.ToString('yyyy-MM-dd HH:mm:ss') } else { '-' }
    Write-Host '  状态   : ' -NoNewline; Write-Host "运行中" -ForegroundColor Green
    Write-Host "  PID    : $($pids -join ', ')  ($name, $mem, 启动于 $start)"
    Write-Host "  Web UI : $Url"
  } else {
    Write-Host '  状态   : ' -NoNewline; Write-Host '已停止' -ForegroundColor Yellow
    Write-Host "  Web UI : $Url (未监听)"
  }
  $cmd = Resolve-DshCommand
  if ($cmd) { Write-Host "  CLI    : $($cmd.Label)" }
  if (Test-Path $LogFile) {
    $f = Get-Item $LogFile
    Write-Host ("  日志   : {0}  ({1:N0} KB, 更新于 {2:HH:mm:ss})" -f $LogFile, ($f.Length / 1KB), $f.LastWriteTime)
  } else {
    Write-Host '  日志   : (尚无)'
  }
  Write-Host '=================================' -ForegroundColor Cyan
  return 0
}

# ---- 动作：log --------------------------------------------------
function Do-Log {
  if (-not (Test-Path $LogFile)) {
    Write-Warn2 "日志不存在: $LogFile"
    return 1
  }
  Get-Content $LogFile -Tail $Tail -Encoding UTF8
  if ($Follow) {
    Write-Info '跟随日志中 (Ctrl+C 退出) ...'
    Get-Content $LogFile -Tail 0 -Wait -Encoding UTF8
  }
  if ((Test-Path $ErrLog) -and ((Get-Item $ErrLog).Length -gt 0)) {
    Write-Info "stderr 日志存在内容: $ErrLog"
  }
  return 0
}

# ---- 分发 -------------------------------------------------------
try {
  switch ($Action) {
    'start'   { exit (Do-Start) }
    'stop'    { exit (Do-Stop) }
    'restart' { [void](Do-Stop); exit (Do-Start) }
    'status'  { exit (Do-Status) }
    'log'     { exit (Do-Log) }
  }
} catch {
  Write-Err2 $_.Exception.Message
  exit 1
}
