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
`recovery/local-tools/fix-router.sh`、`recover-run.ps1` 与 `recover-gitbash.cmd`
都已改成**按脚本自身位置推导**
（`$(dirname "$0")` / `Split-Path $PSScriptRoot -Parent` / `%~dp0..\..`），仓搬到哪里都能跑。
但 `recover-gitbash.cmd` 仍假定 Git 装在 `C:\Program Files\Git\`；
它还依赖**仓外**的 `%TEMP%\owrt\rsh.sh`（SSH 辅助脚本，不在本仓）。
另外 `fix-router.sh` 里的 SSID 默认值是占位符 `YOUR_ROUTER_SSID`，速查表用的是 `<YOUR-SSID>` ——
两者都是占位符，运行时必须用环境变量指定真实值。

**⑥ 守护的耗时判据：`awk` 取 max 后又除 2，阈值被静默减半。**
3.5 / 3.6 的意图是「两次探测取较慢那次」，写法却是
`awk '{t+=($1>$2?$1:$2)} END{printf "%.1f", t/2}'` —— `$1` / `$2` 是**同一行的两个字段**，
取到 max 之后又除了 2。实测 3.2 / 2.8 得 1.6，而意图是 3.2：`EXIT_MAX_SEC=3` 实际要真实
6 秒才触发，节点劣化守卫长期失灵。另外用 `case "$MS" in 3.*|4.*…)` 判数值时，
`10.0` / `12.5` 这类带小数点的两位数**不会命中**任何分支。
**判据用数值比较**（`awk -v a=… 'BEGIN{exit !(a+0 >= b+0)}'`），不要用 case glob。
**下次怎么避**：任何「阈值 × 探测」的改动，先用两组样本手算一遍再上机。

**⑦ 守护没有实例锁：`*/5` 的 cron 与最坏 300 秒的一轮必然叠轮。**
3.6 每个候选 `sleep 3` + 两次 15 秒超时，4 个候选就 132 秒；叠轮时两轮同时 `put`
策略组、同时写 `.clean_node` / `.clean_verdict`，日志记录与实际生效节点对不上。
锁用 `mkdir` 原子建 + `pid` / `ts` + 600 秒过期回收 + `trap` 清理（`bulk-guard.sh` 同款）。
**下次怎么避**：凡是 cron 周期可能小于最坏耗时的脚本，第一版就要有实例锁。

**⑧ `check` 模式必须在动手之前分流。**
`recover-now.sh check` 声称「只诊断、不改任何东西」，但第 1 节在 `MODE` 判断之前
就备份并重写了 `fake_ip_filter`。**下次怎么避**：只读模式的分支要放在所有写操作之前，
不能靠「后面再 exit」。

**⑨ 两个仓的同名脚本落点相同，部署前先确认设备跑的是哪一版。**
`AX3000TOpenwrt/guardian/guardian.sh` 与 `OpenwrtOpsToolkit/openwrt/guardian.sh`
都部署到 `/etc/ShellCrash/guardian.sh`，但**不是同一份实现**（配置读取、变量名不同）。
2026-10-24 维护时先推了 Ops 版、又推 AX 版，中间几分钟设备上跑的是错误的变体。
**下次怎么避**：部署前先 `md5sum` 对比设备文件与两个仓的候选，确认血缘；部署后再核对。
