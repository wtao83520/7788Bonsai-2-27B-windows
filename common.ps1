# ============================================================================
#  共享工具函数（被 start-server.ps1 / allow-firewall.ps1 点源加载）
#  注意：本文件需保存为 UTF-8 with BOM，否则 Windows PowerShell 5.1 解析中文会出错
# ============================================================================

<#
.SYNOPSIS
    获取本机当前可用的局域网 IPv4 地址。

.DESCRIPTION
    只返回「网卡已连接 + 地址状态为 Preferred」的地址。
    这样可以排除掉已拔线的网卡上残留的失效 IP（例如网线拔掉后仍显示 192.168.x.x），
    避免脚本向用户提示一个根本无法访问的地址。
#>
function Get-LanIPv4 {
    [CmdletBinding()]
    param()

    $result = @()
    try {
        $candidates = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -notlike "127.*"      -and
                $_.IPAddress -notlike "169.254.*" -and   # 排除 APIPA 自动私有地址
                $_.PrefixOrigin -ne "WellKnown"
            }

        foreach ($c in $candidates) {
            # 地址状态：Preferred 为正常可用；Tentative/Deprecated/Duplicate 均不可用
            if ($c.AddressState -and $c.AddressState -ne "Preferred") { continue }

            # 所在网卡必须是已连接状态
            $adapter = Get-NetAdapter -InterfaceIndex $c.InterfaceIndex -ErrorAction SilentlyContinue
            if (-not $adapter -or $adapter.Status -ne "Up") { continue }

            $result += $c.IPAddress
        }
    } catch {
        # Get-NetIPAddress 不可用时退回到 .NET 方式
        try {
            $result = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
                Where-Object { $_.AddressFamily -eq "InterNetwork" -and $_.ToString() -notlike "127.*" } |
                ForEach-Object { $_.ToString() }
        } catch { }
    }

    # 用 @() 包住，保证调用方拿到的永远是数组而不是标量字符串
    return @($result | Select-Object -Unique)
}

<#
.SYNOPSIS
    计算本机所有局域网地址所在子网（CIDR 形式），用于防火墙规则的远程地址范围。
#>
function Get-LanSubnets {
    [CmdletBinding()]
    param()

    $subnets = @()
    try {
        $candidates = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -notlike "127.*"      -and
                $_.IPAddress -notlike "169.254.*" -and
                $_.PrefixOrigin -ne "WellKnown"
            }

        foreach ($c in $candidates) {
            if ($c.AddressState -and $c.AddressState -ne "Preferred") { continue }
            $adapter = Get-NetAdapter -InterfaceIndex $c.InterfaceIndex -ErrorAction SilentlyContinue
            if (-not $adapter -or $adapter.Status -ne "Up") { continue }

            $octets = [System.Net.IPAddress]::Parse($c.IPAddress).GetAddressBytes()
            [array]::Reverse($octets)                                    # 转为小端以便做位运算
            $ipUint = [BitConverter]::ToUInt32($octets, 0)
            $maskUint = if ($c.PrefixLength -eq 0) { [uint32]0 } else { [uint32]([uint32]::MaxValue -shl (32 - $c.PrefixLength)) }
            $netUint = $ipUint -band $maskUint

            $netBytes = [BitConverter]::GetBytes($netUint)
            [array]::Reverse($netBytes)
            $subnets += "$($netBytes -join '.')/$($c.PrefixLength)"
        }
    } catch { }

    return @($subnets | Select-Object -Unique)
}
