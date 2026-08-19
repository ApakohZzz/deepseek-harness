# Windows Launcher (dsh 启停脚本)

Windows 下 `dsh web` 的一键启停外壳：后台启动、端口探测、气泡通知、日志轮转、快捷方式。

## 文件

| 文件 | 作用 |
|---|---|
| `dsh-control.ps1` | 核心控制脚本（start / stop / restart / status / log） |
| `start-dsh.bat` / `stop-dsh.bat` / `status-dsh.bat` | 供快捷方式调用的薄包装 |
| `make-shortcuts.ps1` | 生成/刷新桌面快捷方式 |
| `deploy.ps1` | 把本目录脚本部署到外层壳的 `bin/` 并重建快捷方式 |
| `deepseek.ico` | 快捷方式图标 |

## 两种运行形态

脚本自动探测自身位置，无需配置：

- **仓库内**：在本目录直接运行，仓库根即脚本上上级目录；
- **外层壳**：部署到 `<shell>/bin/` 后运行，仓库根为 `<shell>/deepseek-harness`（兼容旧目录名 `deepseek-harness-master`）。

日志 / PID 等运行时产物始终写在脚本所在目录（已被 `.gitignore` 忽略）。

## 部署到外层壳

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/win-launcher/deploy.ps1
# 或指定目标: -TargetBin D:\anywhere\bin
```

## 常用操作

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-control.ps1 start    # 启动 (默认端口 3080, 自动开浏览器)
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-control.ps1 stop
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-control.ps1 status
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-control.ps1 log -Follow -Tail 100
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-control.ps1 start -Port 3081 -NoBrowser
```

## Fork 工作流（本目录维护者适用）

本目录只存在于个人分支 `my-dsh`，不进官方 `master`：

```powershell
# 1. 同步官方进展到 master（保持干净基线，只快进）
git switch master
git fetch upstream
git merge --ff-only upstream/master
git push origin master        # 顺便更新 fork 上的 master

# 2. 把官方进展并入个人分支
git switch my-dsh
git merge master              # 或 rebase：git rebase master

# 3. 日常开发 / 修改启停脚本：直接在 my-dsh 上提交，push 到 fork
git push origin my-dsh

# 4. 向官方发 PR：从干净的 master 切特性分支（勿基于 my-dsh）
git switch master
git switch -c feature/xxx
#   ...开发、提交...
git push origin feature/xxx
#   然后在 GitHub 上向 deepseek-ai/deepseek-harness 发 Pull Request
```

remote 布局：`origin` = 个人 fork（push 目标）；`upstream` = 官方仓库（已禁 push，仅同步）。
