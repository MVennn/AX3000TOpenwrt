# 踩坑总汇

> **一句话**：这类设备的机制级坑与红线 —— 现象 → 步骤 → 解法的**排查流程**在 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)，本篇只写「为什么会这样」与「动手前的红线」。

**① `/tmp` 是 tmpfs，写满就是 OOM。**
`/tmp` 无 `size=` → 上限 ≈ RAM/2 = **119 MB**，且直接吃内存。
2026-10-20 12:45 实测：升级 mihomo 核心时 `gunzip` 把 **57 MB** 裸二进制灌进 `/tmp`，
占用冲到 99% → 核心被杀 → 触发 mtk-wdt 硬件看门狗整机复位。
守护每 5 分钟看水位，≥ 80% 就清掉已知的大临时文件。
**清理 `/tmp` 前先 `ls -ld /var`。**

**② `/var` 是指向 `/tmp` 的相对软链。**
`/var -> tmp` ⇒ `/var/etc` 就是 `/tmp/etc`，而那里正是 **dnsmasq 生成配置文件**的目录
（dnsmasq 以 `-C /var/etc/dnsmasq.conf.<cfg>` 启动）。
`rm -rf /tmp/etc` 之后 dnsmasq 靠内存里的旧配置继续跑，**看起来一切正常**，
但任何一次 dnsmasq 重启都会失败 → 全屋 DNS 断。
**只删具体文件名，绝不用通配符删目录**；`rc.local` 里已有 `VAR_RUNTIME_DIRS` 兜底重建。

**③ YAML 重复键 / 非法 `mixed-port` → mihomo 拒载 → ShellCrash 静默回退基础配置。**
ShellCrash 校验失败时**只打一行日志**（「自定义配置文件校验失败！将使用基础配置文件启动！」），
自定义策略组（🤖 AI网页 / 🤖 干净出口）与 E 段规则**全丢**，面板却看着正常。
`mixed-port` 被写成 `127.0.0.1:7890`（mihomo v1.19 只接受纯数字）是最典型的一种。
**检测**：`ls /tmp/ShellCrash/error.yaml`（存在 = 回退过）；
`grep -q "name: 🤖 AI网页" /tmp/ShellCrash/config.yaml`（缺失 = 自定义组没了）。
守护里有 30 分钟限频的自愈分支会自动重跑 `hotupdate`。

**④ overlay 余量比看上去紧。**
分区 **57.5 MB**。2026-10-20 早间实测 `23.1M / 57.5M`（40%），
同日 15:00 内存审计实测 **36,392 KB / 58,832 KB（65%）**，余 19 MB。
`du` 是逻辑值、**高估约 2.16×**（UBIFS 压缩），判断余量以 `df` 为准。
备份区是最大的消耗项 —— 策略见 [MAINTENANCE.md](MAINTENANCE.md)。

**⑤ Windows 侧工具的路径依赖。**
`recovery/local-tools/fix-router.sh` 与 `recover-run.ps1` 已改成**按脚本自身位置推导**
（`$(dirname "$0")` / `Split-Path $PSScriptRoot -Parent`），仓搬到哪里都能跑。
但 `recovery/local-tools/` 一族里 **`recover-gitbash.cmd` 仍硬编码绝对路径**
`<仓库根>/recovery` —— **仓一搬家就断**；
它还依赖**仓外**的 `%TEMP%\owrt\rsh.sh`（SSH 辅助脚本，不在本仓）。
另外 `fix-router.sh` 里的 SSID 默认值是占位符 `YOUR_ROUTER_SSID`，速查表用的是 `<YOUR-SSID>` ——
两者都是占位符，运行时必须用环境变量指定真实值。
