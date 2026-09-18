<#
.SYNOPSIS
    一键重启 Ternary-Bonsai-2-27B API 服务（含健康与能力自检）。

.DESCRIPTION
    按「停止 → 等待显存释放 → 启动 → 自检」四步执行，全程无需手动干预。
    停止与启动均复用 stop-server.ps1 / start-server.ps1，保证配置与行为一致。

    自检内容：
      · GET /health                  服务是否就绪
      · GET /props                   上下文长度、modalities（图片/视频是否可用）
      · GET /v1/models               模型名与 capabilities 是否含 multimodal

.EXAMPLE
    .\restart-server.ps1                      # 一键重启（按 server-config.psd1）
    .\restart-server.ps1 -Quiet                # 静默模式，只输出关键结果
    .\restart-server.ps1 -Port 9000            # 换端口重启
    .\restart-server.ps1 -Context 196608       # 换上下文重启
    .\restart-server.ps1 -SamplingPreset instruct
    .\restart-server.ps1 -NoVerify             # 跳过自检（更快）
    .\restart-server.ps1 -Force                # 强杀旧进程，不做优雅等待
    .\restart-server.ps1 -ConfigFile .\my.psd1
#>
[CmdletBinding()]
param(
    [string]$ConfigFile,
    [int]$Port,
    [int]$Context,
    [ValidateSet("thinking", "instruct", "custom")]
    [string]$SamplingPreset,
    [int]$StopTimeout  = 5,     # 优雅停止的等待秒数
    [int]$VramTimeout  = 30,    # 等待显存释放的上限秒数
    [switch]$Quiet,             # 静默模式
    [switch]$NoVerify,          # 跳过启动后自检
    [switch]$Force,             # 强制结束旧进程（不做优雅等待）
    [switch]$NoPause            # 供 .cmd 使用：结束后不暂停
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# ------------------------------------------------------------------ 共享工具
. (Join-Path $PSScriptRoot "common.ps1")

$LogDir    = Join-Path $PSScriptRoot "logs"
$StateFile = Join-Path $LogDir "server-state.json"
$OutLog    = Join-Path $LogDir "server.log"
$ErrLog    = Join-Path $LogDir "server.err.log"

$Total = [Diagnostics.Stopwatch]::StartNew()

function Say([string]$msg, $color = $null) {
    if ($Quiet) { return }
    if ($color) { Write-Host $msg -ForegroundColor $color } else { Write-Host $msg }
}

# 无论是否静默，都要输出的关键信息
function SayKey([string]$msg, $color = $null) {
    if ($color) { Write-Host $msg -ForegroundColor $color } else { Write-Host $msg }
}

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

# 查询 GPU 显存（MiB），无 NVIDIA 显卡或未安装 nvidia-smi 时返回 $null
function Get-GpuMemory {
    $exe = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $exe) { return $null }
    try {
        $out = & $exe.Source --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>$null |
               Select-Object -First 1
        if (-not $out) { return $null }
        $parts = $out -split ","
        if ($parts.Count -lt 2) { return $null }
        return [pscustomobject]@{
            Used  = [int]$parts[0].Trim()
            Total = [int]$parts[1].Trim()
        }
    } catch {
        return $null
    }
}

function Show-Gpu([string]$label, $color = "DarkGray") {
    $g = Get-GpuMemory
    if (-not $g) { return }
    Say "  $label 显存: $($g.Used) / $($g.Total) MiB" $color
}

# ------------------------------------------------------------------ 解析配置
$cfgPath = if ($ConfigFile) { $ConfigFile } else { Join-Path $PSScriptRoot "server-config.psd1" }
if (-not (Test-Path $cfgPath)) { throw "找不到配置文件: $cfgPath" }
$cfg = Import-PowerShellDataFile -Path $cfgPath

$portNum = if ($Port) { $Port } else { [int]$cfg.Server.Port }
$hostAddr = $cfg.Server.Host

Say ""
Say ("=" * 74) Cyan
SayKey "  一键重启 Ternary-Bonsai-2-27B API 服务" Cyan
Say ("=" * 74) Cyan
Say ""

# ================================================================== ① 停止
Say "【1/4】停止现有服务" White

$stopped = $false
$oldPid  = 0
$st = $null
if (Test-Path $StateFile) {
    try { $st = Get-Content $StateFile -Raw | ConvertFrom-Json } catch { $st = $null }
}

# 停止前先取显存基线，这样才能在下一步看出「确实释放了多少」
$preGpu = Get-GpuMemory

if ($st -and (Test-ProcessAlive $st.Pid)) {
    $oldPid = $st.Pid
    Say "  旧进程 PID $($st.Pid)（端口 $($st.Port)），正在停止..."
    $stopArgs = @{ Timeout = $(if ($Force) { 0 } else { $StopTimeout }); Quiet = $true }
    & (Join-Path $PSScriptRoot "stop-server.ps1") @stopArgs
    $stopped = $true
} else {
    Say "  未检测到运行中的服务，跳过停止步骤。" DarkGray
    if ($st) { Remove-Item $StateFile -Force -ErrorAction SilentlyContinue }
}

# 兜底：状态文件丢失、或上面没停干净（例如手动启动过 / 换端口启动过）
# 注意：taskkill 失败时会往 stderr 写信息，必须吞掉，否则会触发
#       $ErrorActionPreference="Stop" 导致脚本中断
$leftovers = @(Get-Process -Name "llama-server" -ErrorAction SilentlyContinue |
               Where-Object { $_.Id -ne $PID -and $_.Id -ne $oldPid })
foreach ($lp in $leftovers) {
    Say "  发现游离的 llama-server 进程 (PID $($lp.Id))，正在结束..." DarkYellow
    cmd /c "taskkill /PID $($lp.Id) /T /F >nul 2>&1" | Out-Null
    $stopped = $true
}

# 确认旧进程真的退出了（stop-server.ps1 已等待，这里只做最后核对）
if ($oldPid -gt 0 -and (Test-ProcessAlive $oldPid)) {
    Say "  旧进程仍在，强制结束..." DarkYellow
    cmd /c "taskkill /PID $oldPid /T /F >nul 2>&1" | Out-Null
    $swWait = [Diagnostics.Stopwatch]::StartNew()
    while ((Test-ProcessAlive $oldPid) -and $swWait.Elapsed.TotalSeconds -lt 10) {
        Start-Sleep -Milliseconds 300
    }
    if (Test-ProcessAlive $oldPid) {
        SayKey "✗ 无法结束进程 $oldPid，请手动处理（可能需要管理员权限）。" Red
        exit 1
    }
}

if ($stopped) { Say "  ✓ 已停止" Green } else { Say "  ✓ 无需停止" DarkGray }

# ================================================================== ② 等待显存释放
Say ""
Say "【2/4】等待显存释放" White

$sw = [Diagnostics.Stopwatch]::StartNew()
$baseline = if ($preGpu) { $preGpu.Used } else { $null }

if ($null -eq $baseline) {
    Say "  未检测到 nvidia-smi，跳过显存检查。" DarkGray
} elseif ($baseline -lt 1000) {
    # 停止前显存本来就很低 → 说明确实没有模型驻留
    Say "  停止前显存仅 $baseline MiB，无模型驻留，直接继续。" DarkGray
} else {
    Say "  停止前显存: $baseline MiB，等待释放..."
    # 等显存回落到「基线以下」——即旧模型的权重确实被释放
    $released = $false
    while ($sw.Elapsed.TotalSeconds -lt $VramTimeout) {
        $cur = Get-GpuMemory
        if (-not $cur) { break }
        if ($cur.Used -lt ($baseline - 1000)) {   # 至少释放 1 GB 才算真的卸载
            $released = $true
            Say "  ✓ 显存已释放: $baseline → $($cur.Used) MiB（耗时 $([math]::Round($sw.Elapsed.TotalSeconds,1))s）" Green
            break
        }
        Start-Sleep -Milliseconds 400
    }
    if (-not $released) {
        $now = (Get-GpuMemory).Used
        Say "  ⚠ 显存未明显下降（$baseline → $now MiB），继续启动（可能仍会成功）" DarkYellow
    }
}

# ================================================================== ③ 启动
Say ""
Say "【3/4】启动服务" White

$startArgs = @{}
if ($ConfigFile)     { $startArgs["ConfigFile"]     = $ConfigFile }
if ($Port)           { $startArgs["Port"]           = $Port }
if ($Context)        { $startArgs["Context"]        = $Context }
if ($SamplingPreset) { $startArgs["SamplingPreset"] = $SamplingPreset }

$startScript = Join-Path $PSScriptRoot "start-server.ps1"
$startOut    = Join-Path $LogDir "restart-output.log"

if ($Quiet) {
    # 静默模式：把 start-server.ps1 的输出收进日志，失败时才回显
    & $startScript @startArgs *> $startOut
    $startRc = $LASTEXITCODE
    if ($startRc -eq 0) {
        Say "  ✓ 已启动（详细输出见 $startOut）" DarkGray
    } else {
        SayKey "  启动脚本输出尾部：" DarkRed
        if (Test-Path $startOut) {
            Get-Content $startOut -Tail 25 | ForEach-Object { SayKey "    $_" DarkRed }
        }
    }
} else {
    & $startScript @startArgs
    $startRc = $LASTEXITCODE
}

if ($startRc -ne 0) {
    Say ""
    SayKey "✗ 启动失败（退出码 $startRc）。" Red
    if (Test-Path $ErrLog) {
        SayKey "  错误日志尾部：" Red
        Get-Content $ErrLog -Tail 20 | ForEach-Object { SayKey "    $_" DarkRed }
    }
    SayKey "  完整日志: $OutLog" DarkYellow
    exit 1
}

# ================================================================== ④ 自检
Say ""
Say "【4/4】启动后自检" White

if ($NoVerify) {
    Say "  已跳过（-NoVerify）。" DarkGray
} else {
    $baseUrl = "http://127.0.0.1:$portNum"
    $headers = @{}
    if ($cfg.Server.ApiKey) { $headers["Authorization"] = "Bearer $($cfg.Server.ApiKey)" }

    # --- /health ---
    $healthOk = $false
    try {
        $r = Invoke-WebRequest -Uri "$baseUrl/health" -Headers $headers -UseBasicParsing -TimeoutSec 10
        $healthOk = ($r.StatusCode -eq 200)
    } catch { }
    Say "  $(if ($healthOk) { '[✓]' } else { '[✗]' }) GET /health  $(if ($healthOk) { '200 OK' } else { '失败' })" `
        $(if ($healthOk) { 'Green' } else { 'Red' })

    # --- /props ---
    $propsOk = $false
    $ctxShown = "-"
    $modShown = "-"
    try {
        $p = Invoke-RestMethod -Uri "$baseUrl/props" -Headers $headers -TimeoutSec 20
        $propsOk = $true
        # 上下文长度在 default_generation_settings.n_ctx
        if ($p.default_generation_settings -and $p.default_generation_settings.n_ctx) {
            $ctxShown = [string]$p.default_generation_settings.n_ctx
        }
        if ($p.modalities) {
            $modShown = "vision=$($p.modalities.vision) video=$($p.modalities.video) audio=$($p.modalities.audio)"
        }
    } catch { }
    Say "  $(if ($propsOk) { '[✓]' } else { '[✗]' }) GET /props   上下文=$ctxShown" `
        $(if ($propsOk) { 'Green' } else { 'Red' })
    if ($propsOk) { Say "       modalities: $modShown" DarkGray }

    # --- /v1/models ---
    $modelsOk = $false
    $modelName = "-"
    $caps = "-"
    try {
        $m = Invoke-RestMethod -Uri "$baseUrl/v1/models" -Headers $headers -TimeoutSec 20
        $first = @($m.models)[0]
        if ($first) {
            $modelsOk = $true
            $modelName = $first.name
            $caps = (@($first.capabilities) -join ", ")
        }
    } catch { }
    Say "  $(if ($modelsOk) { '[✓]' } else { '[✗]' }) GET /v1/models  模型=$modelName" `
        $(if ($modelsOk) { 'Green' } else { 'Red' })
    if ($modelsOk) { Say "       capabilities: $caps" DarkGray }

    $allOk = $healthOk -and $propsOk -and $modelsOk
    Say ""
    if ($allOk) {
        SayKey "  ✓ 自检全部通过" Green
    } else {
        SayKey "  ⚠ 自检存在失败项，请检查日志: $OutLog" Yellow
    }
}

# ================================================================== 汇总
$st2 = $null
if (Test-Path $StateFile) {
    try { $st2 = Get-Content $StateFile -Raw | ConvertFrom-Json } catch { $st2 = $null }
}
$pidShown = if ($st2 -and (Test-ProcessAlive $st2.Pid)) { $st2.Pid } else { "?" }

Say ""
Say ("=" * 74) Cyan
SayKey "  重启完成 ✓   PID $pidShown   总耗时 $([math]::Round($Total.Elapsed.TotalSeconds,1))s" Green
Say ""
SayKey "  本机访问 : http://127.0.0.1:$portNum/v1"
if ($hostAddr -eq "0.0.0.0") {
    foreach ($ip in (Get-LanIPv4)) {
        SayKey "  局域网   : http://$ip`:$portNum/v1"
    }
}
SayKey "  媒体请求 : 务必带 ""cache_prompt"": false，否则不同视频会复用同一 KV 缓存"
Say ("=" * 74) Cyan
Say ""
