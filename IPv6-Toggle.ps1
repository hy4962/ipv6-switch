#Requires -Version 5.1
<#
.SYNOPSIS
    Windows IPv6 一键开关（交互式）

.DESCRIPTION
    交互式模式（默认）：先显示当前 IPv6 状态，然后等你输入
        y  -> 打开 IPv6
        n  -> 关闭 IPv6
        回车 / 其它 -> 不改任何东西，直接退出
    命令行模式：
        .\IPv6-Toggle.ps1 -Action Status
        .\IPv6-Toggle.ps1 -Action Off [-Restart]
        .\IPv6-Toggle.ps1 -Action On  [-Restart]

    原理：写 HKLM\...\Tcpip6\Parameters\DisabledComponents
        255 (0xFF) 关闭    0 (0x00) 打开
    这是协议栈级总开关，优先于网卡属性里的勾选，虚拟网卡重建也不会失效。
#>
[CmdletBinding()]
param(
    [ValidateSet('Off', 'On', 'Status', 'Interactive')]
    [string]$Action = 'Interactive',

    [switch]$Restart
)

$RegPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
$RegName = 'DisabledComponents'
$ValOff  = 255   # 0xFF
$ValOn   = 0     # 0x00

# ---------- 关闭控制台 QuickEdit，防止误点一下就把输出冻住（标题栏出现“选择”）----------
try {
    if (-not ('ConsoleTools.WinApi' -as [type])) {
        Add-Type -Namespace ConsoleTools -Name WinApi -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int handle);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr handle, out uint mode);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr handle, uint mode);
'@
    }
    $h = [ConsoleTools.WinApi]::GetStdHandle(-10)   # STD_INPUT_HANDLE
    $mode = [uint32]0
    [void][ConsoleTools.WinApi]::GetConsoleMode($h, [ref]$mode)
    $mode = [uint32](($mode -band (-bnot 0x0040)) -bor 0x0080)   # 关 ENABLE_QUICK_EDIT_MODE，需同时带 ENABLE_EXTENDED_FLAGS
    [void][ConsoleTools.WinApi]::SetConsoleMode($h, $mode)
} catch {
    # 关不掉也不影响功能，只是误点窗口仍可能暂停输出
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-IPv6Value {
    $v = (Get-ItemProperty -Path $RegPath -Name $RegName -ErrorAction SilentlyContinue).$RegName
    if ($null -eq $v) { return 0 }
    return [int]$v
}

function Get-StateText {
    param([int]$Value)
    if ($Value -eq $ValOff) { return 'IPv6 已关闭' }
    if ($Value -eq $ValOn)  { return 'IPv6 已开启' }
    return 'IPv6 处于自定义中间状态（按开启处理）'
}

function Show-Status {
    param([int]$Value)
    $hex = '0x{0:X}' -f $Value
    Write-Host ''
    Write-Host '================ 当前状态 ================' -ForegroundColor Cyan
    Write-Host ('  IPv6 状态 : ' + (Get-StateText $Value)) -ForegroundColor White
    Write-Host ('  注册表值  : DisabledComponents = ' + $hex + '  (' + $Value + ')') -ForegroundColor White
    try {
        $all   = @(Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction Stop)
        $bound = @($all | Where-Object { $_.Enabled -eq $true })
        Write-Host ('  网卡绑定  : ' + $bound.Count + ' / ' + $all.Count + ' 块网卡勾着 IPv6') -ForegroundColor White
    } catch {
        Write-Host '  网卡绑定  : 读取失败（不影响开关）' -ForegroundColor DarkGray
    }
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ''
}

function Set-IPv6 {
    param([int]$Target)
    New-ItemProperty -Path $RegPath -Name $RegName -Value $Target -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $RegPath -Name $RegName -Value $Target

    if ($Target -eq $ValOn) {
        Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue |
            Where-Object { $_.Enabled -eq $false } |
            ForEach-Object { Enable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue | Out-Null }
    }

    $after = Get-IPv6Value
    if ($after -ne $Target) {
        Write-Host '失败：注册表没有改动，请用管理员权限运行。' -ForegroundColor Red
        return $false
    }
    return $true
}

# ---------- 权限检查（查询状态不需要管理员）----------
if (-not (Test-IsAdmin) -and $Action -ne 'Status') {
    $psExe   = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Action ' + $Action
    if ($Restart) { $argLine += ' -Restart' }

    Write-Host '正在申请管理员权限（请在 UAC 窗口点“是”）...' -ForegroundColor Yellow
    try {
        Start-Process -FilePath $psExe -Verb RunAs -Wait -ArgumentList $argLine
    } catch {
        Write-Host ('提权失败或被取消：' + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
    exit 0
}

# ---------- 仅查询 ----------
if ($Action -eq 'Status') {
    Show-Status (Get-IPv6Value)
    exit 0
}

# ---------- 交互式选择 ----------
if ($Action -eq 'Interactive') {
    $cur = Get-IPv6Value
    Show-Status $cur

    Write-Host '  y = 打开 IPv6    n = 关闭 IPv6    回车或其它 = 不改，直接退出' -ForegroundColor Yellow
    $ans = (Read-Host '  请输入 (y/n)').Trim().ToLower()

    if ($ans -eq 'y') {
        $Action = 'On'
    } elseif ($ans -eq 'n') {
        $Action = 'Off'
    } else {
        Write-Host '未做任何修改，退出。' -ForegroundColor DarkGray
        exit 0
    }
}

# ---------- 执行 ----------
if ($Action -eq 'Off') { $target = $ValOff } else { $target = $ValOn }

Write-Host ''
if ($target -eq $ValOff) {
    Write-Host '正在关闭 IPv6 ...' -ForegroundColor Yellow
} else {
    Write-Host '正在打开 IPv6 ...' -ForegroundColor Yellow
}

if (-not (Set-IPv6 $target)) { exit 1 }

if ($target -eq $ValOff) {
    Write-Host '已关闭 IPv6（DisabledComponents = 0xFF）。' -ForegroundColor Green
} else {
    Write-Host '已打开 IPv6（DisabledComponents = 0x0），已恢复所有网卡的 IPv6 绑定。' -ForegroundColor Green
}

Write-Host ''
if ($Restart) {
    Write-Host '15 秒后重启（取消：shutdown /a）' -ForegroundColor Yellow
    shutdown /r /t 15 /c 'IPv6 设置已更改，需要重启'
    exit 0
}

Show-Status (Get-IPv6Value)
Write-Host '注意：必须重启电脑（或注销重登）后才会真正生效。' -ForegroundColor Cyan

Write-Host '  y = 立即重启（15 秒倒计时）    回车或其它 = 稍后自己重启' -ForegroundColor Yellow
$rb = (Read-Host '  请输入 (y)').Trim().ToLower()
if ($rb -eq 'y') {
    Write-Host '15 秒后重启（取消：shutdown /a）' -ForegroundColor Yellow
    shutdown /r /t 15 /c 'IPv6 设置已更改，需要重启'
} else {
    Write-Host '好的，记得手动重启生效。' -ForegroundColor DarkGray
}

exit 0
