# IPv6 Switch for Windows

一键开关 Windows 全局 IPv6 的小脚本，专治「网卡属性里取消勾选 IPv6，过一会儿又自己勾回去」。

## 怎么用

双击 `ipv6-toggle.bat`，会先显示当前状态，然后等你输入：

```
================ 当前状态 ================
  IPv6 状态 : IPv6 已开启
  注册表值  : DisabledComponents = 0x0  (0)
  网卡绑定  : 5 / 5 块网卡勾着 IPv6
==========================================

y = 打开 IPv6   |   n = 关闭 IPv6   |   回车或其它 = 不改，直接退出   请输入:
```

- 输入 **y** → 打开 IPv6
- 输入 **n** → 关闭 IPv6
- 直接回车 → 什么都不改，退出

改完会再显示一次状态，并问你要不要立即重启（**必须重启才生效**，输入 y 走 15 秒倒计时，回车则稍后自己重启）。

首次运行会弹 UAC 框，点「是」。

## 命令行用法

双击是交互模式，命令行可以带参数直接执行：

```bat
ipv6-toggle.bat status   :: 只看状态，不改任何东西（不需要管理员）
ipv6-toggle.bat on       :: 打开 IPv6
ipv6-toggle.bat off      :: 关闭 IPv6
ipv6-toggle.bat          :: 不带参数 = 交互式（显示状态 + 等你输 y/n）
```

直接调 PowerShell 也行：

```powershell
.\IPv6-Toggle.ps1                       # 交互式
.\IPv6-Toggle.ps1 -Action Status        # 只看状态
.\IPv6-Toggle.ps1 -Action Off           # 关闭
.\IPv6-Toggle.ps1 -Action On            # 打开
.\IPv6-Toggle.ps1 -Action Off -Restart  # 关闭并立即重启（15 秒倒计时）
```

`-Action` 可选值：`Off` / `On` / `Status` / `Interactive`（默认）。

## 为什么网卡属性里取消勾选不管用

在适配器属性里取消勾选只是**解绑**（unbind），不是关闭协议。以下情况都会让它恢复：

- Clash Verge / Mihomo / Meta Tunnel 之类用 **wintun** 建虚拟网卡的软件，每次开关 TUN 模式都会重建网卡，绑定回到默认状态；
- 系统网络重置、驱动重装、VPN/代理软件安装卸载；
- 某些优化工具扫一遍又给勾上。

真正可靠的做法是改注册表总开关：

```
HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters
  DisabledComponents  (REG_DWORD)
    255 (0xFF)  ->  全系统关闭 IPv6
    0   (0x00)  ->  启用 IPv6
```

这个值作用于 **TCP/IP 协议栈本身**，优先级高于任何单块网卡的勾选状态，新建的虚拟网卡同样被压住。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `IPv6-Toggle.ps1` | 核心脚本，UTF-8 BOM 编码（Win10/11 自带 PowerShell 5.1 才能正确显示中文），非管理员时自动弹 UAC 提权 |
| `ipv6-toggle.bat` | 双击入口，用 `-ExecutionPolicy Bypass` 单次绕过执行策略，不用改系统策略 |

两个文件必须放在**同一目录**下。

## 状态说明

| 显示 | 含义 |
| --- | --- |
| `IPv6 已关闭` | 值 = 0xFF，IPv6 全关 |
| `IPv6 已开启` | 值 = 0x00，IPv6 全开 |
| `IPv6 处于自定义中间状态` | 值是其它值（如 0x08、0x20），多半是代理/优化软件留下的半成品，脚本按「开启」处理，跑一次 y 或 n 就清干净了 |

「网卡绑定」那一行只是告诉你有几块网卡**勾着** IPv6 绑定——关闭状态下这不影响，协议栈层面已经不工作了。

## 注意事项

1. **必须重启**（或注销重登）才生效。脚本只改注册表，不即时生效，网络图标不会当场变化，这是正常的。
2. 重启有 15 秒倒计时，后悔了执行 `shutdown /a` 取消。
3. **企业/校园网、某些 VPN、WSL2 桥接、Windows 热点、DirectAccess** 依赖 IPv6。关掉后网络异常，再跑一次输入 `y` 打开即可，无副作用。
4. 打开 IPv6 时脚本会顺带把所有网卡上被手动取消的 `ms_tcpip6` 绑定重新勾上，避免「注册表开了、网卡还解绑着」的半吊子状态。
5. 若报「无法加载文件，因为在此系统上禁止运行脚本」，说明你直接用 powershell 跑 ps1 了，改用 bat 入口。
6. 编辑 ps1 后请保持 **UTF-8 with BOM**，否则 PowerShell 5.1 会把中文读成乱码。

## 手动验证

管理员 PowerShell：

```powershell
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name DisabledComponents
```

重启后 `ipconfig` 里应该看不到任何 IPv6 地址（`::1` 回环保留，系统内部必需，不影响断网效果）。

## 完全还原

```powershell
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name DisabledComponents
```

删除注册表值后重启，回到出厂状态。

## 上传到 GitHub

```bash
cd "D:\Users\XOS\Documents\GitHub\ipv6-switch"
git init
git add .
git commit -m "feat: interactive IPv6 on/off switch for Windows"
git remote add origin git@github.com:<用户名>/<仓库名>.git
git branch -M main
git push -u origin main
```

> 本机 hosts 被 Steam++ 劫持，直连 GitHub 常报 `CRYPT_E_NO_REVOCATION_CHECK (0x80092012)`。
> 推之前先 `unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY`，再 `GIT_SSL_NO_VERIFY=true git push`。

## 许可

随意使用、随意改。
