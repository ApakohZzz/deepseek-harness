$w = New-Object -ComObject WScript.Shell
$bin = Split-Path -Parent $MyInvocation.MyCommand.Path   # ...\bin 或 ...\scripts\win-launcher
$root = Split-Path -Parent $bin                           # shell root or repo root
$icon = Join-Path $bin 'deepseek.ico'

# 快捷方式落点：默认外层部署壳根（仓库根的父目录）；在壳内运行时即 $root 本身
$linkRoot = if (Test-Path (Join-Path $root 'apps\cli\package.json')) { Split-Path -Parent $root } else { $root }

function Mk($name, $target) {
  $s = $w.CreateShortcut($name)
  $s.TargetPath = $target
  $s.WorkingDirectory = $bin
  $s.IconLocation = $icon
  $s.WindowStyle = 1   # normal window: shows progress briefly, auto-closes on success
  $s.Save()
  Write-Output "Created $name"
}

# Refresh the user-visible shortcuts (keep existing names)
Mk "$linkRoot\Start DeepSeek Harness.lnk"  (Join-Path $bin 'start-dsh.bat')
Mk "$linkRoot\Stop DeepSeek Harness.lnk"   (Join-Path $bin 'stop-dsh.bat')
Mk "$linkRoot\Status DeepSeek Harness.lnk" (Join-Path $bin 'status-dsh.bat')
Mk "$linkRoot\Update DeepSeek Harness.lnk" (Join-Path $bin 'update-dsh.bat')

# Remove legacy shortcut names from the old version of this script
Remove-Item "$linkRoot\Start dsh.lnk", "$linkRoot\Stop dsh.lnk" -ErrorAction SilentlyContinue
