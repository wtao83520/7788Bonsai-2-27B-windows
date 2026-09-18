<#
.SYNOPSIS
    一键启动 Ternary-Bonsai-2-27B 的 OpenAI 兼容 API 服务。

.DESCRIPTION
    读取 server-config.psd1 配置，在后台启动 bin\llama-server.exe，
    等待模型加载完成后打印可用的 OpenAI 兼容端点与调用示例。

.EXAMPLE
    .\start-server.ps1                 # 按配置启动
    .\start-server.ps1 -Status         # 查看运行状态
    .\start-server.ps1 -Force          # 已在运行则重启
    .\start-server.ps1 -Port 9000 -Context 65536
    .\start-server.ps1 -SamplingPreset instruct
    .\start-server.ps1 -Foreground     # 前台运行，Ctrl+C 退出
#>
[CmdletBinding()]
param(
    [string]$ConfigFile,
    [switch]$Foreground,
    [switch]$Force,
    [switch]$Status,
    [int]$Port,
    [int]$Context,
    [ValidateSet("thinking", "instruct", "custom")]
    [string]$SamplingPreset
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# ------------------------------------------------------------------ 共享工具
. (Join-Path $PSScriptRoot "common.ps1")

# ------------------------------------------------------------------ 工具函数
$LogDir   = Join-Path $PSScriptRoot "logs"
$StateFile = Join-Path $LogDir "server-state.json"
$OutLog   = Join-Path $LogDir "server.log"
$ErrLog   = Join-Path $LogDir "server.err.log"

function Resolve-CfgPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $p }
    if ([System.IO.Path]::IsPathRooted($p)) { return $p }
    return (Join-Path $PSScriptRoot $p)
}

function Read-State {
    if (-not (Test-Path $StateFile)) { return $null }
    try { return (Get-Content $StateFile -Raw | ConvertFrom-Json) } catch { return $null }
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

function Get-RunningState {
    $st = Read-State
    if (-not $st) { return $null }
    if (-not (Test-ProcessAlive $st.Pid)) {
        # 进程已不在，清理陈旧状态文件
        Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
        return $null
    }
    return $st
}

function Show-Status($st) {
    if (-not $st) {
        Write-Host "服务未运行。" -ForegroundColor Yellow
        return $false
    }
    $url = "http://$($st.Host):$($st.Port)"
    $up  = [math]::Round(((Get-Date) - [datetime]$st.StartTime).TotalMinutes, 1)
    Write-Host "服务运行中 ✓" -ForegroundColor Green
    Write-Host "  PID      : $($st.Pid)"
    Write-Host "  监听     : $($st.Host):$($st.Port)"
    Write-Host "  本机访问 : http://127.0.0.1:$($st.Port)"
    if ($st.Host -eq "0.0.0.0") {
        $ips = @(Get-LanIPv4)
        if ($ips.Count -eq 0) { Write-Host "  局域网   : 未检测到可用网卡" -ForegroundColor DarkYellow }
        foreach ($ip in $ips) { Write-Host "  局域网   : http://$ip`:$($st.Port)" -ForegroundColor Yellow }
        $rule = Get-NetFirewallRule -DisplayName "Ternary-Bonsai API (TCP $($st.Port))" -ErrorAction SilentlyContinue
        if ($rule -and $rule.Enabled -eq "True") {
            Write-Host "  防火墙   : 已放行 ✓" -ForegroundColor Green
        } else {
            Write-Host "  防火墙   : 未放行（需管理员运行 .\allow-firewall.cmd）" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host "  访问范围 : 仅本机（改 Host 为 0.0.0.0 可开放局域网）" -ForegroundColor DarkGray
    }
    Write-Host "  模型     : $($st.ModelName)  (上下文 $($st.Context))"
    if ($st.PSObject.Properties["Vision"]) {
        if ($st.Vision -eq "on") { Write-Host "  图片输入 : 已启用 ✓" -ForegroundColor Green }
        else                     { Write-Host "  图片输入 : 未启用" -ForegroundColor DarkGray }
    }
    if ($st.PSObject.Properties["Video"]) {
        if ($st.Video -eq "on")  { Write-Host "  视频输入 : 已启用 ✓" -ForegroundColor Green }
        else                     { Write-Host "  视频输入 : 未启用" -ForegroundColor DarkGray }
    }
    if ($st.PSObject.Properties["Thinking"]) {
        Write-Host "  思考     : $($st.Thinking)（可在请求中用 reasoning_effort 覆盖）"
    }
    Write-Host "  采样     : $($st.Sampling)"
    Write-Host "  鉴权     : $(if ($st.ApiKey) { '已启用 (Bearer ' + $st.ApiKey + ')' } else { '无（开放访问）' })"
    Write-Host "  已运行   : $up 分钟"
    Write-Host "  日志     : $OutLog"
    return $true
}

# ------------------------------------------------------------------ 读配置
if (-not $ConfigFile) { $ConfigFile = Join-Path $PSScriptRoot "server-config.psd1" }
if (-not (Test-Path $ConfigFile)) { throw "找不到配置文件: $ConfigFile" }
$cfg = Import-PowerShellDataFile -Path $ConfigFile

if ($Status) { Show-Status (Get-RunningState) | Out-Null; exit 0 }

$modelPath = Resolve-CfgPath $cfg.Model.Path
$hostAddr  = $cfg.Server.Host
$portNum   = if ($Port)    { $Port }    else { [int]$cfg.Server.Port }
$ctxNum    = if ($Context) { $Context } else { [int]$cfg.Model.ContextSize }
$preset    = if ($SamplingPreset) { $SamplingPreset } else { $cfg.Sampling.Preset }

# ------------------------------------------------------------------ 前置检查
if (-not (Test-Path $modelPath)) {
    throw "找不到模型文件: $modelPath`n请将 Ternary-Bonsai-2-27B-PQ2_0.gguf 放入 models\ 目录。"
}
$srvExe = Join-Path $PSScriptRoot "bin\llama-server.exe"
if (-not (Test-Path $srvExe)) { throw "找不到服务程序: $srvExe" }

# ------------------------------------------------------------------ 重复启动检查
$running = Get-RunningState
if ($running) {
    if ($Force) {
        Write-Host "检测到服务运行中 (PID $($running.Pid))，正在重启..." -ForegroundColor Yellow
        & (Join-Path $PSScriptRoot "stop-server.ps1") -Quiet | Out-Null
        Start-Sleep -Milliseconds 800
    } else {
        Write-Host "服务已在运行，无需重复启动（用 -Force 可重启）。" -ForegroundColor Yellow
        Show-Status $running | Out-Null
        exit 0
    }
}

# ------------------------------------------------------------------ 采样预设
switch ($preset) {
    "thinking" { $temp = 1.0; $topP = 0.95; $topK = 20; $minP = 0.0; $pres = 0.0 }
    "instruct" { $temp = 0.7; $topP = 0.80; $topK = 20; $minP = 0.0; $pres = 1.5 }
    default    {
        $temp = [double]$cfg.Sampling.Temperature
        $topP = [double]$cfg.Sampling.TopP
        $topK = [int]$cfg.Sampling.TopK
        $minP = [double]$cfg.Sampling.MinP
        $pres = [double]$cfg.Sampling.PresencePenalty
    }
}
$repPen = [double]$cfg.Sampling.RepeatPenalty

# ------------------------------------------------------------------ 组装参数
$modelArgs = @(
    "-m", $modelPath,
    "-a", $cfg.Model.Alias,
    "-c", "$ctxNum",
    "-ngl", "$($cfg.Model.GpuLayers)",
    "-fa", "$($cfg.Model.FlashAttention)",
    "-np", "$($cfg.Model.Parallel)",
    "-b", "$($cfg.Model.BatchSize)",
    "-ub", "$($cfg.Model.UbatchSize)",
    "-ctk", "$($cfg.Model.CacheTypeK)",
    "-ctv", "$($cfg.Model.CacheTypeV)"
)
if (-not $cfg.Model.UseMmap)  { $modelArgs += "--no-mmap" }
if (-not $cfg.Model.UseJinja) { $modelArgs += "--no-jinja" }

# ---------------------------- 推测解码（加速）-----------------------------
# 注意: Import-PowerShellDataFile 返回 Hashtable，其 PSObject.Properties 只含 .NET 属性、
#       不含键名，故必须直接访问属性（缺失时返回 $null）。
# 本模型不含 MTP 权重，draft-mtp 会直接启动失败，这里做前置拦截并给出提示
$specType = $cfg.Model.SpecType
if (-not $specType) { $specType = "none" }
if ($specType -ne "none") {
    $validSpec = @("ngram-simple", "ngram-map-k", "ngram-map-k4v", "ngram-mod", "ngram-cache",
                   "draft-mtp", "draft-simple", "draft-eagle3", "draft-dflash", "draft-dspark")
    if ($validSpec -notcontains $specType) {
        throw "Model.SpecType = '$specType' 不是有效的推测解码类型。`n可选: none, $($validSpec -join ', ')"
    }
    if ($specType -eq "draft-mtp") {
        throw @"
Model.SpecType = 'draft-mtp' 不可用 —— 本模型不含 MTP 层。
      运行时错误: context type MTP requested but model doesn't contain MTP layers
      原因: MTP 需要 GGUF 含 qwen35.nextn_predict_layers 键及额外的 nextn 层，
            本模型无此键（64 层均为主干层 blk.0~63）。
      建议: 改用 "ngram-map-k"（无需额外权重，重复性内容实测提速 4.3 倍）
"@
    }
    if ($specType -like "draft-*") {
        throw "Model.SpecType = '$specType' 需要额外的草稿模型权重（当前未部署）。`n建议改用 ngram-map-k（无需额外权重）。"
    }
    $modelArgs += @("--spec-type", $specType)
    # ngram 系列的尺寸参数名随类型不同而不同，按前缀拼接
    if ($specType -like "ngram-*") {
        $n = if ($cfg.Model.SpecNgramSizeN) { $cfg.Model.SpecNgramSizeN } else { 12 }
        $m = if ($cfg.Model.SpecNgramSizeM) { $cfg.Model.SpecNgramSizeM } else { 48 }
        if ($specType -eq "ngram-mod") {
            $modelArgs += @("--spec-ngram-mod-n-match", "$n", "--spec-ngram-mod-n-max", "$m")
        } else {
            $modelArgs += @("--spec-$specType-size-n", "$n", "--spec-$specType-size-m", "$m")
        }
    }
}

# ---------------------------- 视觉（图片/视频输入）----------------------------
$visionOn  = $false
$videoOn   = $false
$mmprojPath = $null
if ($cfg.Vision -and $cfg.Vision.Enabled) {
    $mmprojPath = Resolve-CfgPath $cfg.Vision.MmprojPath
    if (Test-Path $mmprojPath) {
        $visionOn = $true
        $modelArgs += @("-mm", $mmprojPath)
        if (-not $cfg.Vision.Offload) { $modelArgs += "--no-mmproj-offload" }
        if ($cfg.Vision.ImageMinTokens) { $modelArgs += @("--image-min-tokens", "$($cfg.Vision.ImageMinTokens)") }
        if ($cfg.Vision.ImageMaxTokens) { $modelArgs += @("--image-max-tokens", "$($cfg.Vision.ImageMaxTokens)") }
        if ($cfg.Vision.MediaPath) {
            $mediaPath = Resolve-CfgPath $cfg.Vision.MediaPath
            if (-not (Test-Path $mediaPath)) { New-Item -ItemType Directory -Path $mediaPath -Force | Out-Null }
            $modelArgs += @("--media-path", $mediaPath)
        }

        # ------------------------ 视频：抽帧 + 时间戳 ------------------------
        # 视频由 ffprobe 探测、ffmpeg 抽帧后交给同一个 2D 视觉塔，并在文本里插入时间戳。
        # ⚠ 不同 fork 版本的参数集不同：本仓库的 prism-b10685 **没有**
        #   --video-fps / --video-timestamp-interval / --video-ffmpeg-dir，
        #   视频按编译期默认工作（4 fps 抽帧、每 5000 ms 一条时间戳、ffmpeg 从 PATH 查找）。
        #   因此这里先探测二进制支持哪些参数，只传它真正认识的，避免启动失败。
        if ($null -eq $script:SrvHelp) {
            $script:SrvHelp = (& $srvExe --help 2>&1 | Out-String)
        }
        $hasVideoFps   = $script:SrvHelp -match '--video-fps'
        $hasVideoTs    = $script:SrvHelp -match '--video-timestamp-interval'
        $hasFfmpegDir  = $script:SrvHelp -match '--video-ffmpeg-dir'

        if ($hasVideoFps -and $cfg.Vision.VideoFps) {
            $modelArgs += @("--video-fps", "$($cfg.Vision.VideoFps)")
        } elseif (-not $hasVideoFps -and $cfg.Vision.VideoFps -and [double]$cfg.Vision.VideoFps -ne 4.0) {
            Write-Host "  提示: 当前二进制不支持 --video-fps，抽帧帧率按内置默认 4 fps（配置值 $($cfg.Vision.VideoFps) 已忽略）" -ForegroundColor DarkYellow
        }
        if ($hasVideoTs -and $cfg.Vision.VideoTimestampInterval -ne $null) {
            $modelArgs += @("--video-timestamp-interval", "$($cfg.Vision.VideoTimestampInterval)")
        } elseif (-not $hasVideoTs -and $cfg.Vision.VideoTimestampInterval -ne $null -and
                  "$($cfg.Vision.VideoTimestampInterval)" -ne "5000") {
            Write-Host "  提示: 当前二进制不支持 --video-timestamp-interval，时间戳按内置默认 5000 ms（配置值 $($cfg.Vision.VideoTimestampInterval) 已忽略）" -ForegroundColor DarkYellow
        }

        # 定位 ffmpeg / ffprobe（视频抽帧必需，图片不需要）
        $ffmpegDir = $null
        if ($cfg.Vision.VideoFfmpegDir) { $ffmpegDir = Resolve-CfgPath $cfg.Vision.VideoFfmpegDir }
        if ($ffmpegDir) {
            if ((Test-Path (Join-Path $ffmpegDir "ffmpeg.exe")) -and
                (Test-Path (Join-Path $ffmpegDir "ffprobe.exe"))) {
                if ($hasFfmpegDir) { $modelArgs += @("--video-ffmpeg-dir", $ffmpegDir) }
                elseif (-not ($env:PATH -split ';' | Where-Object { $_ -and (Test-Path (Join-Path $_ 'ffmpeg.exe') -ErrorAction SilentlyContinue) })) {
                    Write-Host "⚠ 当前二进制不支持 --video-ffmpeg-dir，请把 $ffmpegDir 加入系统 PATH" -ForegroundColor Yellow
                }
                $videoOn = $true
            } else {
                Write-Host "⚠ VideoFfmpegDir 下未找到 ffmpeg.exe/ffprobe.exe：$ffmpegDir" -ForegroundColor Yellow
            }
        }
        if (-not $videoOn) {
            if ((Get-Command ffmpeg -ErrorAction SilentlyContinue) -and
                (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
                $videoOn = $true
            } else {
                Write-Host "⚠ 未检测到 ffmpeg/ffprobe → 视频输入不可用（图片不受影响）" -ForegroundColor Yellow
                Write-Host "  可安装 ffmpeg 并加入 PATH，再重试" -ForegroundColor DarkYellow
            }
        }
    } else {
        Write-Host "⚠ 未找到视觉投影文件，图片/视频输入已跳过：$mmprojPath" -ForegroundColor Yellow
    }
}

$srvArgs = @(
    "--host", $hostAddr,
    "--port", "$portNum",
    "--timeout", "$($cfg.Server.TimeoutSeconds)",
    "--threads-http", "$($cfg.Server.ThreadsHttp)",
    "--temp", "$temp",
    "--top-p", "$topP",
    "--top-k", "$topK",
    "--min-p", "$minP",
    "--presence-penalty", "$pres",
    "--repeat-penalty", "$repPen",
    "--reasoning-format", "$($cfg.Reasoning.Format)",
    "--reasoning-budget", "$($cfg.Reasoning.Budget)"
)

# 思考力度：本模型模板只接受 low/medium/xhigh，其余值会被模板拒绝并报 500
if ($cfg.Reasoning.Effort -and $cfg.Reasoning.Effort -ne "default") {
    $allowedEffort = @("low", "medium", "xhigh")
    if ($allowedEffort -contains $cfg.Reasoning.Effort) {
        $srvArgs += @("--reasoning-effort", "$($cfg.Reasoning.Effort)")
    } else {
        throw "Reasoning.Effort = '$($cfg.Reasoning.Effort)' 不被本模型支持。`n" +
              "本模型 chat template 仅接受: default, low, medium, xhigh`n" +
              "（high / max / minimal 会导致请求返回 500 错误）"
    }
}
if ($cfg.Reasoning.Preserve)  { $srvArgs += "--reasoning-preserve" }
if ($cfg.Server.ApiKey)       { $srvArgs += @("--api-key", $cfg.Server.ApiKey) }
if (-not $cfg.Server.WebUI)   { $srvArgs += "--no-webui" }
if ($cfg.Server.Metrics)      { $srvArgs += "--metrics" }
if ($cfg.Server.SlotsMonitor) { $srvArgs += "--slots" } else { $srvArgs += "--no-slots" }
if ($cfg.Server.AllowedOrigins) { $srvArgs += @("--cors-origins", $cfg.Server.AllowedOrigins) }

$allArgs = $modelArgs + $srvArgs

# 是否对外（局域网）开放
$isLanMode = ($hostAddr -eq "0.0.0.0" -or $hostAddr -eq "::" -or $hostAddr -eq "*")

# $baseUrl 用于本机访问与健康检查；0.0.0.0 只是绑定地址，不可作为连接目标
$localUrl = "http://127.0.0.1:$portNum"
$baseUrl  = $localUrl

# 探测本机可用于局域网访问的 IPv4 地址（只取已连接网卡上的有效地址）
# 注意：必须写成「先赋值空数组再覆盖」，不能用 $x = if(...){ @(...) }，
#       因为 if 语句的输出会被 PowerShell 解包，单元素数组会退化成标量，
#       随后 $lanIps[0] 会取到字符串的首字符而不是整个地址。
$lanIps = @()
if ($isLanMode) { $lanIps = @(Get-LanIPv4) }

$lanUrl = $null
if ($lanIps.Count -gt 0) { $lanUrl = "http://$($lanIps[0]):$portNum" }

# ------------------------------------------------------------------ 创建日志目录
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (Test-Path $OutLog) { Move-Item $OutLog "$OutLog.prev" -Force -ErrorAction SilentlyContinue }
if (Test-Path $ErrLog) { Move-Item $ErrLog "$ErrLog.prev" -Force -ErrorAction SilentlyContinue }

# ------------------------------------------------------------------ 启动
Write-Host ""
Write-Host "=== 启动 Ternary-Bonsai-2-27B OpenAI 兼容服务 ===" -ForegroundColor Cyan
Write-Host "  模型    : $(Split-Path $modelPath -Leaf)"
Write-Host "  上下文  : $ctxNum    GPU 层: $($cfg.Model.GpuLayers)    并发槽: $($cfg.Model.Parallel)"
Write-Host "  采样    : $preset (temp=$temp top_p=$topP top_k=$topK pres_pen=$pres)"
Write-Host "  思考    : effort=$($cfg.Reasoning.Effort) format=$($cfg.Reasoning.Format) budget=$($cfg.Reasoning.Budget) preserve=$($cfg.Reasoning.Preserve)"
Write-Host "            请求级开关: reasoning_effort=none 关闭 / low|medium|xhigh 调深度" -ForegroundColor DarkGray
if ($visionOn) {
    Write-Host "  图片    : 已启用  (mmproj=$(Split-Path $mmprojPath -Leaf), offload=$($cfg.Vision.Offload))" -ForegroundColor Green
    if ($videoOn) {
        $vInfo = if ($hasVideoFps) { "抽帧 $($cfg.Vision.VideoFps) fps" } else { "抽帧 4 fps(内置默认)" }
        Write-Host "  视频    : 已启用  ($vInfo, 时间戳每 5000 ms)" -ForegroundColor Green
    } else {
        Write-Host "  视频    : 未启用（缺少 ffmpeg/ffprobe）" -ForegroundColor DarkGray
    }
    Write-Host "  ⚠ 媒体请求请带 ""cache_prompt"": false，否则不同视频会复用同一 KV 缓存" -ForegroundColor DarkYellow
} else {
    Write-Host "  图片    : 未启用" -ForegroundColor DarkGray
}
if ($isLanMode) {
    Write-Host "  监听    : 全部网卡 0.0.0.0:$portNum（局域网可访问）" -ForegroundColor Yellow
    foreach ($ip in $lanIps) { Write-Host "  局域网  : http://$ip`:$portNum" -ForegroundColor Yellow }
    if (-not $cfg.Server.ApiKey) {
        Write-Host "  ⚠ 安全  : 未设置 ApiKey，同网段任何人可调用本服务" -ForegroundColor Red
        Write-Host "            建议在 server-config.psd1 中填写 Server.ApiKey" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "  监听    : 仅本机 (127.0.0.1)"
}
Write-Host "  本机    : $localUrl"
Write-Host ""

if ($Foreground) {
    # 前台运行：直接占用当前窗口
    & $srvExe @allArgs
    exit 0
}

$proc = Start-Process -FilePath $srvExe -ArgumentList $allArgs `
    -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog

# ------------------------------------------------------------------ 写状态
$state = [pscustomobject][ordered]@{
    Pid        = $proc.Id
    Host       = $hostAddr
    Port       = $portNum
    ApiKey     = if ($cfg.Server.ApiKey) { $cfg.Server.ApiKey } else { "" }
    ModelPath  = $modelPath
    ModelName  = $cfg.Model.Alias
    Context    = $ctxNum
    Sampling   = "$preset(temp=$temp,top_p=$topP,top_k=$topK)"
    Vision     = if ($visionOn) { "on" } else { "off" }
    Video      = if ($videoOn)  { "on" } else { "off" }
    Thinking   = "effort=$($cfg.Reasoning.Effort),budget=$($cfg.Reasoning.Budget),format=$($cfg.Reasoning.Format)"
    StartTime  = (Get-Date).ToString("o")
    OutLog     = $OutLog
    ErrLog     = $ErrLog
}
$state | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8

# ------------------------------------------------------------------ 等待就绪
Write-Host "正在加载模型（约 7.2 GB 权重上载到 GPU）..." -ForegroundColor Gray
$headers = @{}
if ($cfg.Server.ApiKey) { $headers["Authorization"] = "Bearer $($cfg.Server.ApiKey)" }

$ready   = $false
$failed  = $false
$sw      = [Diagnostics.Stopwatch]::StartNew()
$lastTick = 0
while ($sw.Elapsed.TotalSeconds -lt 600) {
    if (-not (Test-ProcessAlive $proc.Id)) { $failed = $true; break }
    try {
        $resp = Invoke-WebRequest -Uri "$baseUrl/health" -Headers $headers `
                    -UseBasicParsing -TimeoutSec 5
        if ($resp.StatusCode -eq 200) { $ready = $true; break }
    } catch {
        # 503 = 模型仍在加载；连接失败 = 尚未开始监听
    }
    $elapsed = [int]$sw.Elapsed.TotalSeconds
    if ($elapsed -ge ($lastTick + 10)) {
        $lastTick = $elapsed
        Write-Host "  ... 已等待 $elapsed s" -ForegroundColor DarkGray
    }
    Start-Sleep -Milliseconds 700
}

Write-Host ""
if ($failed) {
    Write-Host "启动失败，进程已退出。错误日志尾部：" -ForegroundColor Red
    if (Test-Path $ErrLog) { Get-Content $ErrLog -Tail 25 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkRed } }
    Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
    exit 1
}
if (-not $ready) {
    Write-Host "等待超时（600s）。服务可能仍在加载，请查看 $OutLog" -ForegroundColor Yellow
    exit 1
}

Write-Host "服务已就绪 ✓  (PID $($proc.Id), 耗时 $([math]::Round($sw.Elapsed.TotalSeconds,1))s)" -ForegroundColor Green
Write-Host ""

if ($isLanMode) {
    # 局域网环境检查
    if (-not $lanIps) {
        Write-Host "⚠ 未检测到局域网 IP，请检查网络连接。" -ForegroundColor Yellow
    }
    $fwOk = $false
    try {
        $rule = Get-NetFirewallRule -DisplayName "Ternary-Bonsai API (TCP $portNum)" -ErrorAction SilentlyContinue
        if ($rule -and $rule.Enabled -eq "True" -and $rule.Action -eq "Allow") { $fwOk = $true }
    } catch { }
    if (-not $fwOk) {
        Write-Host "⚠ 防火墙可能拦截外部访问，需以管理员身份运行一次：" -ForegroundColor Yellow
        Write-Host "     .\allow-firewall.cmd" -ForegroundColor White
        Write-Host "" 
    } else {
        Write-Host "✓ 防火墙规则已就绪（Ternary-Bonsai API）" -ForegroundColor Green
        Write-Host ""
    }
}

# 展示端点：优先用局域网地址，便于复制到其他机器
$showUrl = if ($isLanMode -and $lanUrl) { $lanUrl } else { $baseUrl }
Write-Host "OpenAI 兼容端点 (Base URL: $showUrl/v1):" -ForegroundColor Cyan
Write-Host "  POST $showUrl/v1/chat/completions    # 对话补全"
Write-Host "  POST $showUrl/v1/completions         # 文本补全"
Write-Host "  GET  $showUrl/v1/models              # 模型列表"
if ($cfg.Server.WebUI) { Write-Host "  GET  $showUrl/                       # 内置网页界面" }
if ($isLanMode -and $lanUrl) {
    Write-Host ""
    Write-Host "  （本机访问: $localUrl/v1）" -ForegroundColor DarkGray
}
Write-Host ""
$apiKeyShown = if ($cfg.Server.ApiKey) { $cfg.Server.ApiKey } else { "not-needed" }
Write-Host "调用示例:" -ForegroundColor Cyan
if ($cfg.Server.ApiKey) {
    Write-Host "  (需鉴权) Authorization: Bearer $($cfg.Server.ApiKey)"
}
Write-Host @"
  curl $showUrl/v1/chat/completions -H "Content-Type: application/json" -d "{\"model\":\"$($cfg.Model.Alias)\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}"

  Python (openai SDK):
      from openai import OpenAI
      c = OpenAI(base_url="$showUrl/v1", api_key="$apiKeyShown")
      r = c.chat.completions.create(model="$($cfg.Model.Alias)",
              messages=[{"role":"user","content":"你好"}])
      print(r.choices[0].message.content)
"@
Write-Host ""
Write-Host "停止服务:  .\stop-server.ps1" -ForegroundColor DarkGray
Write-Host "查看状态:  .\start-server.ps1 -Status" -ForegroundColor DarkGray
