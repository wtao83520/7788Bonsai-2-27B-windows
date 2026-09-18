<#
.SYNOPSIS
    为 Ternary-Bonsai API 服务添加/删除 Windows 防火墙入站规则（需管理员权限）。

.DESCRIPTION
    局域网内其他设备要访问本机的 API 服务，必须放行对应端口的入站连接。
    本脚本会自动读取 server-config.psd1 中的端口，并限定只放行本地子网，
    比"允许任何来源"更安全。

.EXAMPLE
    .\allow-firewall.ps1              # 添加规则
    .\allow-firewall.ps1 -Remove      # 删除规则
    .\allow-firewall.ps1 -Status      # 查看规则状态
    .\allow-firewall.ps1 -Port 9000   # 指定端口
#>
[CmdletBinding()]
param(
    [int]$Port,
    [switch]$Remove,
    [switch]$Status
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# ---------------------------------------------------------------- 共享工具
. (Join-Path $PSScriptRoot "common.ps1")

# ---------------------------------------------------------------- 读端口
if (-not $Port) {
    $cfgPath = Join-Path $PSScriptRoot "server-config.psd1"
    if (Test-Path $cfgPath) {
        try { $Port = [int](Import-PowerShellDataFile -Path $cfgPath).Server.Port } catch { }
    }
    if (-not $Port) { $Port = 8080 }
}

$ruleName = "Ternary-Bonsai API (TCP $Port)"

# ---------------------------------------------------------------- 状态查询（无需管理员）
if ($Status) {
    $rules = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($rules) {
        $rules | ForEach-Object {
            Write-Host "规则名称 : $($_.DisplayName)"
            Write-Host "状态     : $(if ($_.Enabled -eq 'True') {'已启用'} else {'已禁用'})"
            Write-Host "方向     : $($_.Direction) / 动作: $($_.Action)"
            $pf = $_ | Get-NetFirewallPortFilter
            Write-Host "协议/端口: $($pf.Protocol) $($pf.LocalPort)"
            $af = $_ | Get-NetFirewallAddressFilter
            Write-Host "远程地址 : $($af.RemoteAddress -join ', ')"
            Write-Host ""
        }
    } else {
        Write-Host "未找到防火墙规则：$ruleName" -ForegroundColor Yellow
        Write-Host "局域网其他设备可能无法访问，请以管理员身份运行 .\allow-firewall.cmd" -ForegroundColor DarkYellow
    }
    exit 0
}

# ---------------------------------------------------------------- 管理员检查
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "需要管理员权限才能修改防火墙规则。" -ForegroundColor Red
    Write-Host ""
    Write-Host "请用以下任一方式运行：" -ForegroundColor Yellow
    Write-Host "  1) 右键点击开始菜单 → 终端(管理员) / PowerShell(管理员)，然后执行："
    Write-Host "       cd `"$PSScriptRoot`""
    Write-Host "       .\allow-firewall.ps1"
    Write-Host ""
    Write-Host "  2) 或者右键点击 allow-firewall.cmd → 以管理员身份运行"
    Write-Host ""
    Write-Host "（仅查看规则状态可用：.\allow-firewall.ps1 -Status）"
    Write-Host ""
    exit 1
}

# ---------------------------------------------------------------- 删除
if ($Remove) {
    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        $existing | Remove-NetFirewallRule
        Write-Host "已删除防火墙规则：$ruleName" -ForegroundColor Green
    } else {
        Write-Host "规则不存在，无需删除：$ruleName" -ForegroundColor Yellow
    }
    exit 0
}

# ---------------------------------------------------------------- 添加
# 计算本地子网，只放行同一局域网，避免暴露到所有网络
$remoteAddr = @("LocalSubnet")
$subnets = @(Get-LanSubnets)
if ($subnets.Count -gt 0) { $remoteAddr = $subnets }

$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "规则已存在，正在更新..." -ForegroundColor Yellow
    $existing | Remove-NetFirewallRule
}

New-NetFirewallRule `
    -DisplayName $ruleName `
    -Description "Allow LAN access to the local Ternary-Bonsai-2-27B OpenAI-compatible API server" `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort $Port `
    -RemoteAddress $remoteAddr `
    -Profile Private,Domain `
    -Enabled True | Out-Null

Write-Host "防火墙规则已添加 ✓" -ForegroundColor Green
Write-Host "  规则名称 : $ruleName"
Write-Host "  端口     : TCP $Port"
Write-Host "  允许来源 : $($remoteAddr -join ', ')  (仅私有/域网络)"
Write-Host ""
Write-Host "局域网内其他设备现在可以访问：" -ForegroundColor Cyan
$ips = @(Get-LanIPv4)
if ($ips.Count -eq 0) { Write-Host "  (未检测到已连接网卡，请检查网络)" -ForegroundColor DarkYellow }
foreach ($ip in $ips) { Write-Host "  http://$ip`:$Port/v1" }
Write-Host ""
