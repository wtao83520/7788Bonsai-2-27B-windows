<#
.SYNOPSIS
    一键停止 Ternary-Bonsai-2-27B API 服务。

.DESCRIPTION
    读取 logs\server-state.json 中记录的 PID，先尝试正常结束，
    超时后强制结束进程树。同时清理状态文件。

.EXAMPLE
    .\stop-server.ps1              # 停止服务
    .\stop-server.ps1 -Quiet       # 静默停止（供脚本调用）
    .\stop-server.ps1 -Timeout 5   # 等待 5 秒后强制结束
#>
[CmdletBinding()]
param(
    [int]$Timeout = 5,   # 优雅关闭的等待秒数，超时后强制结束进程
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$LogDir    = Join-Path $PSScriptRoot "logs"
$StateFile = Join-Path $LogDir "server-state.json"

function Say($msg, $color) { if (-not $Quiet) { Write-Host $msg -ForegroundColor $color } }

# 可靠的存活检测：Get-Process 会缓存已退出进程的对象，这里直接向系统重新查询
function Test-ProcessAlive([int]$procId) {
    if ($procId -le 0) { return $false }
    try {
        $p = [System.Diagnostics.Process]::GetProcessById($procId)
        return (-not $p.HasExited)
    } catch {
        return $false
    }
}

if (-not (Test-Path $StateFile)) {
    Say "服务未运行（无状态文件）。" Yellow
    exit 0
}

$state = $null
try { $state = Get-Content $StateFile -Raw | ConvertFrom-Json } catch { }

if (-not $state) {
    Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
    Say "状态文件已损坏，已清理。服务未运行。" Yellow
    exit 0
}

if (-not (Test-ProcessAlive $state.Pid)) {
    Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
    Say "服务未运行（PID $($state.Pid) 不存在）。已清理状态文件。" Yellow
    exit 0
}

Say "正在停止服务 (PID $($state.Pid), 端口 $($state.Port))..." Cyan

# --- 先尝试优雅关闭（让其刷写日志 / 释放显存） ---
try {
    $p = [System.Diagnostics.Process]::GetProcessById($state.Pid)
    if ($p.MainWindowHandle -ne 0) { $p.CloseMainWindow() | Out-Null }
} catch { }

$sw = [Diagnostics.Stopwatch]::StartNew()
while ((Test-ProcessAlive $state.Pid) -and $sw.Elapsed.TotalSeconds -lt $Timeout) {
    Start-Sleep -Milliseconds 300
}

# --- 超时则强制结束整棵进程树 ---
if (Test-ProcessAlive $state.Pid) {
    Say "  优雅关闭超时，强制结束进程树..." DarkYellow
    & taskkill.exe /PID $state.Pid /T /F 2>&1 | Out-Null
    # 等待进程真正从系统中消失（最多 10 秒）
    $sw2 = [Diagnostics.Stopwatch]::StartNew()
    while ((Test-ProcessAlive $state.Pid) -and $sw2.Elapsed.TotalSeconds -lt 10) {
        Start-Sleep -Milliseconds 300
    }
}

if (Test-ProcessAlive $state.Pid) {
    Say "警告：进程 $($state.Pid) 仍未退出，请手动检查。" Red
    exit 1
}

Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
Say "服务已停止 ✓  显存已释放。" Green
