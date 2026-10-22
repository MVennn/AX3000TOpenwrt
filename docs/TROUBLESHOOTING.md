# 排障手册

> **一句话**：八个高频现象，每个按「现象 → 排查步骤 → 原因 / 解法」三段写，
> 排查步骤全是**能在路由器上直接粘的命令**。

**节标题就是检索词** —— 遇到什么就搜什么，不用通读。

> **通用版在哪**：本篇步骤里的 `recover-now.sh` / `guardian.sh` 是**参考实现**
> （表名与路径是示例值，按自己的设备改）；通用版在公开仓 `OpenwrtOpsToolkit/openwrt/`（全部可配）——
> 两边的分工见 [UPSTREAM.md](UPSTREAM.md) §7。

---

## 先跑这三个

任何「连不上 / 打不开」的问题，先在路由器上跑这三条，输出一起贴回来：

```sh
# 1) 核心在不在 + 端口开没开
pidof CrashCore; netstat -lntp 2>/dev/null | grep -E ':(7890|7892|9999|1053)'

# 2) nft 表齐不齐
nft list tables

# 3) 内存与闪存余量（/tmp 是内存盘，爆了就是 OOM）
grep MemAvailable /proc/meminfo; df -h /tmp /overlay
```

再跑一次健康快照，把输出一起贴回来：

```sh
sh /etc/router-health/health-snapshot.sh          # 每次一行，落 /etc/router-health/
```

---

## WiFi 连上没网

### 现象

手机 / 电脑连上了 SSID，IP 也拿到了（`10.0.0.x`），但**所有网页都打不开**。
部分情况下「刚重启完一会儿全站打不开」，过一会儿自己好了。

### 排查步骤

```sh
# 1) 是不是 DNS 的问题（先分清：DNS 挂了 vs 全链路挂了）
nslookup www.baidu.com 127.0.0.1

# 2) 绕过 DNS 直接打 IP —— 通 = DNS 问题；不通 = 路由 / 防火墙问题
ping -c 3 223.5.5.5

# 3) 默认路由还在不在
ip route show default; ip -brief addr show | grep -E 'wan|br-lan'

# 4) nft 表齐不齐（DNS 劫持在自建表 googleroute 里，缺表 = 劫持落空）
nft list tables

# 5) 防火墙是不是被 start.sh 留在半加载状态
/etc/init.d/firewall restart && sleep 3 && nft list ruleset | head -40
```

### 原因 / 解法

| 观察到的现象 | 原因 | 解法 |
|---|---|---|
| `ping 223.5.5.5` 通、`nslookup` 失败 | DNS 劫持表缺失或 mihomo 的 DNS 端口没起 | `sh /etc/ShellCrash/start.sh stop && sh /etc/ShellCrash/start.sh start`，再 `nft -f /etc/googleroute.nft` |
| `nft list tables` 里**没有** `inet googleroute` | DNS 劫持表没加载 → LAN 的 53 端口漏到 dnsmasq → 返回被污染的解析 | `nft -f /etc/googleroute.nft`；常驻由 `rc.local` 开机加载、`guardian.sh` 每 5 分钟补载 |
| 默认路由为空 / `wan` 没地址 | WAN 掉了 | `ifup wan`；检查 `network.wan` 的 DHCP 配置 |
| 刚重启完一会儿不通、之后自好 | ShellCrash 重建 `inet shellcrash` 整表的那几秒，53 端口漏到 dnsmasq | **已修**：DNS 劫持移进自建表 `inet googleroute`（dstnat-4，早于 shellcrash 的 dstnat-100）。仍出现就走 [「代理离线」](#代理离线) |

**兜底**：整套恢复 —— `ash /tmp/recover-now.sh`（摘 DNS 劫持 → 停核心重生成 → 加载 nft 表 → 重载 fw4 → 恢复 crontab → 连通性校验）。

---

## DNS 解析全失败

### 现象

所有域名都解析不出来，表现为「WiFi 连上了但没网」。
路由器自己 `nslookup` 也失败。

### 排查步骤

```sh
# 1) mihomo 的 DNS 端口（1053）在不在
netstat -lntp 2>/dev/null | grep ':1053'

# 2) 直接问 mihomo
nslookup www.baidu.com 127.0.0.1

# 3) fake-ip 过滤文件里有没有空行 / 注释 —— 这是本仓恢复脚本的第一个修复目标
grep -c '^[[:space:]]*$' /etc/ShellCrash/configs/fake_ip_filter
cat -A /etc/ShellCrash/configs/fake_ip_filter | head -20

# 4) 运行配置是不是回退成了基础配置（自定义组没了 = 回退过）
grep -c "name: 🤖 AI网页" /tmp/ShellCrash/config.yaml
ls -la /tmp/ShellCrash/error.yaml        # 存在 = 校验失败过，已回退

# 5) dnsmasq 自己的配置目录在不在
ls -ld /var /var/etc; ls /var/etc/dnsmasq.conf.* 2>/dev/null
```

### 原因 / 解法

| 观察到的现象 | 原因 | 解法 |
|---|---|---|
| `fake_ip_filter` 里有空行 | ShellCrash 把它原样塞进 `fake-ip-filter` → mihomo DNS 异常不自愈 | `ash /tmp/recover-now.sh`（会先去空行/注释/去重，改前备份到 `/root/fake_ip_filter.bak.<时间戳>`） |
| `/var/etc/dnsmasq.conf.*` 不存在 | **`/var` 是指向 `/tmp` 的相对软链** —— 之前清理 `/tmp` 时把 dnsmasq 的配置目录一起删了。dnsmasq 靠内存里的旧配置继续跑，**看着正常**，但任何一次重启都会失败 | `mkdir -p /var/etc /var/lib` 后 `/etc/init.d/dnsmasq restart`；`rc.local` 里已有 `VAR_RUNTIME_DIRS` 兜底重建 |
| `error.yaml` 存在、运行配置缺 `🤖 AI网页` | **ShellCrash 静默回退基础配置** —— 校验失败只打一行日志，自定义组与规则全丢 | 看 `head -1 /tmp/ShellCrash/error.yaml`，用 `/etc/ShellCrash/CrashCore.raw -t -f /tmp/ShellCrash/error.yaml` 复现；修好后 `task/task.sh hotupdate` 重新生成。守护里已有 30 分钟限频的自愈分支 |
| 1053 端口没起 | 核心没跑起来 | 见 [「代理离线」](#代理离线) |

---

## 代理离线

### 现象

国内站点正常，**国外站点打不开**；面板 `:9999/ui` 打不开；
`curl -x http://127.0.0.1:7890` 超时。

### 排查步骤

```sh
# 1) 核心进程与端口
pidof CrashCore; netstat -lntp 2>/dev/null | grep -E ':(7890|7892|9999)'

# 2) 控制 API（**必须带密钥**，不带会静默 Unauthorized）
SECRET=$(sed -n "s/^secret=//p" /etc/ShellCrash/configs/ShellCrash.cfg | head -1)
curl -s -m 5 -H "Authorization: Bearer $SECRET" http://127.0.0.1:9999/version

# 3) 走代理打一发，看出口国家
curl -s --max-time 15 -x http://127.0.0.1:7890 https://chatgpt.com/cdn-cgi/trace | grep -E "^(ip|loc|colo)="

# 4) 策略组当前指向（每个组的真实出口）
for g in "🚀 节点选择" "🤖 人工智能" "🤖 AI网页" "🤖 干净出口"; do
  printf '%s = ' "$g"
  curl -s -m 5 -H "Authorization: Bearer $SECRET" \
    "http://127.0.0.1:9999/proxies/$(echo "$g" | sed 's/ /%20/g')" | grep -oE '"now":"[^"]*"' | head -1
done

# 5) 守护日志（每 5 分钟一轮，FIX / ALERT 都记在这）
tail -30 /tmp/ShellCrash/guardian.log

# 6) 全套 AI 链路自检（16 段，应全绿、退出码 0）
sh /etc/ShellCrash/ai-api-check.sh
```

### 原因 / 解法

| 观察到的现象 | 原因 | 解法 |
|---|---|---|
| `CrashCore` 进程不存在，但 `/tmp/ShellCrash/shellcrash.pid` 在 | 进程被 OOM 杀了 | `sh /etc/ShellCrash/start.sh start`；再按 [「OOM 杀进程」](#oom-杀进程) 查根因 |
| 进程不在、pid 文件也不在、30 分钟内无存活记录 | **人为停止**（维护时 `start.sh stop` 会清 pid 文件）—— 守护**故意不拉起**，不妨碍维护 | 维护结束后 `sh /etc/ShellCrash/start.sh start` |
| 控制 API 返回 `{"message":"Unauthorized"}` | 没带 `Authorization: Bearer <secret>`。ShellCrash 在 04:30 的每周更新里给控制器加了 `secret=` | 补上认证头；真源是 `/etc/ShellCrash/configs/ShellCrash.cfg` 的 `secret=` 行 |
| 出口 `loc=CN` 或 `cc` 不是 `IN` | 干净出口漂到了被判为 CN 的节点 | 守护会自动复位；手动：`PUT /proxies/<组>` 选 `🇮🇳 印度-优化`。**注意**：印度是三入口共用同一出口 IP，切入口不换 IP |
| 控制 API 正常，但代理请求超时 | nft 表缺失 / 路由异常 / 核心热加载中 | `nft list tables` 看三张自建表在不在；看 `guardian.log` 的 FIX 记录 |
| `start.sh start` 报配置校验失败 | 运行配置被截断或 YAML 有重复键 | 看 `/tmp/ShellCrash/error.yaml` 第 1 行 |

---

## OOM 杀进程

### 现象

`CrashCore` 莫名其妙消失，`dmesg` 里有 OOM 记录；
或者整机突然重启，日志里只有开机序列、**没有** shutdown/reboot 记录。

### 排查步骤

```sh
# 1) 内核有没有 OOM 记录
dmesg | grep -i -E 'oom|killed process'
logread | grep -i -E 'oom|killed'

# 2) 现在内存还剩多少
grep -E 'MemAvailable|MemFree|Slab|Cached' /proc/meminfo

# 3) 谁在吃内存（按 RSS 排序，前 10）
top -b -n 1 | head -15

# 4) mihomo 自己的内存与上限（Go 的 PROT_NONE 保留区是假象）
grep -E 'VmRSS|VmSize' /proc/$(pidof CrashCore)/status

# 5) /tmp 水位（tmpfs，写满 = 直接吃 RAM）
df -h /tmp

# 6) 有没有 swap / zram（没有的话，shmem 不可回收）
cat /proc/swaps; ls /dev/zram* 2>/dev/null
```

### 原因 / 解法

| 观察到的现象 | 原因 | 解法 |
|---|---|---|
| `dmesg` 有 `Out of memory: Killed process ... CrashCore` | 内存峰值超限，**只杀核心，不重启整机**（`vm.panic_on_oom=0`，PID1 被内核豁免） | 查 `/tmp` 是不是被写满（见下）；`command.env` 加 `export GOMEMLIMIT=64MiB`（**已验证可传导**，待执行） |
| `/tmp` 用量冲到 90%+ | `/tmp` 是 tmpfs（无 `size=` → 上限 ≈ RAM/2 = 119 MB），**直接吃 RAM**。最典型的场景：更新 mihomo 核心时 `gunzip` 把 **57 MB** 裸二进制灌进 `/tmp`（加上下载的 .gz 21 MB，峰值 ≈ 78 MB） | `sh /etc/ShellCrash/start.sh stop`；删掉 `/tmp` 下的大文件（**只删具体文件名**）；守护每 5 分钟看水位，≥80% 会自动清 |
| `VmSize` 1.39 GB 但 `VmRSS` 只有 68 MB | Go 的 `PROT_NONE` 保留区，**物理占用为 0**，不是泄漏 | 不用管；判断泄漏看 `VmRSS` 的**趋势**（10 分钟净变化） |
| `Slab` 很大、`Cached` 很大 | 大部分是**可回收**的 | 不用管 |

**不要动**（第八轮已否，附理由）：`vm.min_free_kbytes`、`vm.swappiness`、
`vfs_cache_pressure`、`nf_conntrack_max`、**开 zram**（池子从同一块 239 MB 挖，收益 ≈ 0）、
`start_old=OFF`（会启用 procd respawn，OOM 时变成重启放大器）。

---

## 看门狗复位

### 现象

路由器**突然重启**：无正常关机日志，`uptime` 归零，内核日志只有开机序列。

### 排查步骤

```sh
# 1) 上一次重启的原因：看是不是 OOM（OOM 有记录，看门狗复位没有）
dmesg | grep -i -E 'oom|killed|watchdog|wdt'

# 2) 看门狗设备与超时
ls /dev/mtk_wdt /dev/watchdog 2>/dev/null
cat /sys/class/watchdog/*/timeout 2>/dev/null

# 3) 重启前后的负载：看是不是被压出来的
cat /proc/loadavg

# 4) 谁在喂狗、谁该喂狗
cat /etc/crontabs/root
ls /etc/init.d/ | grep -i -E 'watchdog|wdt'
```

### 原因 / 解法

| 观察到的现象 | 原因 | 解法 |
|---|---|---|
| 无 OOM 记录、无 shutdown 记录、`uptime` 归零 | **mtk-wdt 硬件看门狗复位**（31 秒超时，只有 PID1 喂狗） | 见下 |
| 复位前负载冲到 2.6 | **并发探测压顶** —— 10 个复盘子代理同时逐节点切换 + 多路 HTTPS 抓取，一次顶到看门狗 | **对路由器做批量探测必须限速**：串行化或加大间隔。复盘类任务的「负载控制」是与「只读」同等的硬约束 |
| 重启后 `/tmp/ShellCrash` 不存在，mihomo 起不来 | `/tmp` 在 tmpfs 上，重启即清空 → 看门狗 `mkdir` 锁目录永远失败 → 每分钟 exit 1 | 看门狗已加 `mkdir -p /tmp/ShellCrash`（已实测：10 秒内自动拉起）；`rc.local` 里也有兜底 |

**判据**：`uptime` 归零 + 内核日志只有开机序列 + **没有** shutdown/reboot 记录 + 无 OOM 记录
⇒ 判为看门狗复位，而不是内存问题。

---

## /tmp 写满导致配置生成 ENOSPC

### 现象

ShellCrash 生成配置失败，日志里出现 `ENOSPC` / `No space left on device`；
或 `/tmp` 满了之后**代理与 DNS 一起断**。

### 排查步骤

```sh
# 1) /tmp 水位（tmpfs 无 size=，上限 ≈ RAM/2）
df -h /tmp; df -k /tmp

# 2) 谁把 /tmp 撑大了（按大小排序，前 20）
du -k /tmp/* 2>/dev/null | sort -rn | head -20

# 3) 是不是更新核心留下的 .gz / 裸二进制
ls -la /tmp/*.gz /tmp/mihomo-* /tmp/scmeta.tar.gz 2>/dev/null

# 4) 配置生成有没有报错
ls -la /tmp/ShellCrash/error.yaml
head -3 /tmp/ShellCrash/error.yaml 2>/dev/null
```

### 原因 / 解法

| 观察到的现象 | 原因 | 解法 |
|---|---|---|
| `/tmp` 里躺着几十 MB 的 `.gz` 或裸二进制 | 更新 mihomo 核心时 `gunzip -c > $TMPDIR/core_new` —— **57.4 MB 裸二进制 + 21 MB 的 .gz 一次性进内存盘** | 删掉这些具体文件（守护的水位清理清单里就有它们）；重启后再更新 |
| `df` 说满了但 `du` 加起来没那么大 | tmpfs 用的是**页缓存 + shmem**，无 swap 时不可回收 | 只能靠删文件；不要指望内核回收 |
| `error.yaml` 存在且内容是磁盘错 | 配置写不进去 | 先腾空间，再 `task/task.sh hotupdate` 重新生成 |

**清 `/tmp` 的红线**（机制见 [PITFALLS.md](PITFALLS.md) ②）：
`/var` 是指向 `/tmp` 的**相对软链** ⇒ `/var/etc` 就是 `/tmp/etc`，
而那里是 **dnsmasq 生成配置文件**的目录。
**只删具体文件名，绝不用通配符删目录**；删完确认 `ls -ld /var/etc`。

---

## nft 表未加载

### 现象

某一类流量没被接管：QUIC 没被拦、Google 国内边缘没进代理、
DNS 劫持不生效、或 **7890 mixed 口从 LAN 又能连上了**。

### 排查步骤

```sh
# 1) 现在有几张表
nft list tables

# 2) 本仓关心的四张自建表逐个查
for t in quicguard googlecn googleroute mixedport; do
  printf '%-12s ' "$t"
  nft list table inet $t >/dev/null 2>&1 && echo "已加载" || echo "缺失"
done

# 3) 计数器（有没有真的在拦）
nft list table inet quicguard | grep -c counter
nft list table inet mixedport

# 4) 源文件在不在
ls -la /etc/quicguard.nft /etc/googlecn.nft /etc/googleroute.nft /etc/mixedport.nft

# 5) 开机脚本里的加载顺序
grep -n 'nft -f' /etc/rc.local
```

### 原因 / 解法

| 观察到的现象 | 原因 | 解法 |
|---|---|---|
| 表缺失、`/etc/<name>.nft` 也在 | 文件没入版本库或被删 | `system/mixedport.nft` 已入本仓，按部署映射表投放；`/etc/router-health/reboot-verify.sh` 仍不在本仓（在设备上）—— **待补**。缺失时手工 `nft -f /etc/<name>.nft` |
| 表缺失、源文件在 | 开机加载顺序没走到（`googleroute` 要等 DNS 1053 就绪才加载） | 手工 `nft -f /etc/<name>.nft`；守护每 5 分钟补载三张表（`mixedport` **不在守护的补载清单里**） |
| 表在、计数器不涨 | 规则没命中（如流量走的不是被拦的网段） | 看 `nft list table inet <name>` 里的 counter 与网段 |
| `mixedport` 缺失 → 7890 又能被 LAN 连上 | 这张表是 **7890 收口**的实现，丢了就等于开放代理复活 | `nft -f /etc/mixedport.nft`；源文件已入本仓 `system/mixedport.nft`，`rc.local` 开机会加载 |

**顺序很重要**：`inet googleroute` 用 **dstnat-4**（早于 shellcrash 的 dstnat-100），
`inet mixedport` 用 **input priority -200**（早于 shellcrash 的 -100，
否则 LAN 源地址会被它先 accept 掉）。

---

## crontab 被覆盖

### 现象

定时任务没了：守护不跑、看门狗不跑、订阅不更新；
或者 `start.sh stop` 之后代理被守护复活，妨碍维护。

### 排查步骤

```sh
# 1) 现在有哪些 cron
cat /etc/crontabs/root

# 2) 应该有哪几条（参考配置）
#    * * * * *  start_legacy_wd.sh shellcrash   （每分钟，保守模式看门狗）
#    */5 * * * * guardian.sh                     （每 5 分钟，网络守护）
#    */10 * * * * task.sh 106                    （每 10 分钟保存面板选择）
#    每 30 分钟  health-snapshot.sh              （健康快照）
#    每天 05:05  daily-ai-check.sh               （AI 链路自检）
#    每周日 04:30 auto-update.sh                 （订阅与规则更新）

# 3) crond 本身在跑吗
ps | grep crond; /etc/init.d/cron status

# 4) 守护有没有在补回
tail -20 /tmp/ShellCrash/guardian.log | grep -i 'restored'
```

### 原因 / 解法

| 观察到的现象 | 原因 | 解法 |
|---|---|---|
| 少了 `start_legacy_wd.sh` 那一行 | **`start.sh stop` 会重写 crontab 并删掉 legacy 看门狗行**（2026-10-20 事故） | 守护每 5 分钟会自动补回；手动：`echo '* * * * * /bin/ash /etc/ShellCrash/starts/start_legacy_wd.sh shellcrash' >> /etc/crontabs/root && crontab /etc/crontabs/root` |
| 少了 `guardian.sh` 那一行 | 恢复流程没走完，或守护自己也被覆盖了 | 补回 `*/5 * * * * /bin/ash /etc/ShellCrash/guardian.sh` |
| 整张 crontab 空 | 恢复脚本中途失败 | `ash /tmp/recover-now.sh`（第 5 节会从 `/tmp/cron.recover.bak` 还原整张表，并补回两行关键任务） |
| 代理在 `start.sh stop` 之后又活了 | 守护把进程拉起来了 | **维护前先停守护**：`sed -i '/guardian/d' /etc/crontabs/root && /etc/init.d/cron restart`。另外守护只在 `/tmp/ShellCrash/shellcrash.pid` 存在时拉起 —— `start.sh stop` 会删该 pid 文件，所以停代理时它本来就不该复活；若仍复活，说明 pid 文件还在，先 `rm -f /tmp/ShellCrash/shellcrash.pid` |

**提醒**：`crontab -l` 读的是 `/etc/crontabs/root`。
busybox 的 crond **不支持 `@reboot`** —— 需要开机执行的任务要靠
「标记文件 + `rc.local` 派发」（`/etc/router-health/reboot-verify.sh` 就是这个机制）。
