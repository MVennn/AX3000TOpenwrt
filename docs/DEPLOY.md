# 部署映射

> **一句话**：本仓每个脚本「本地路径 → 路由器上的目标路径 → 被谁调用 → 出事怎么退回去」的正本；改脚本前先来这查备份与回退方式。

## 目录职责

| 目录 | 职责 |
|---|---|
| `system/` | 路由器系统面：开机脚本 `rc.local`、已执行的一次性补丁与核心升级脚本（`archive/`）、RAM 型 `/tmp` 的水位监控与自动回收（`router-health/`） |
| `guardian/` | 网络守护进程：检测 + 最小化修复，每 5 分钟一轮；含 OOM 拉起前的内存闸门 `memgate.sh`，以及按站点探测的 `dest-guard.sh`（每 10 分钟，默认 dry-run） |
| `recovery/` | 故障恢复：`recover-now.sh` 主力、Windows 侧触发器（`local-tools/`）、已被取代的旧版（`archive/`） |
| `docs/` | 文档：索引、规则正本、硬件基线、状态速查、排障手册、Release 说明 |
| `baseline/` | `sysupgrade` 保留清单与无线配置模板（示例值） |
| `tools/` | 文档自检、密钥守卫、门面资源生成 |
| `third-party/` | 上游项目索引（本仓不 vendor 源码） |
| `vault/`（[BACKUP-VAULT.md](BACKUP-VAULT.md)） | **私有金库**：私钥备份、升级前整机快照、argon 主题恢复包 —— **在仓里但不入库**（`.gitignore` 排除 + CI 守卫兜底） |

仓库根还有六个文件：`README.md`（门面）、`CHANGELOG.md`（变更台账）、
`LICENSE`（MIT 许可证全文）、`NOTICE`（第三方声明）、`CONTRIBUTING.md`（贡献流程）、
`SECURITY.md`（安全边界与私密报告渠道）。

## 本仓管哪几件事

| 事项 | 载体 | 具体做什么 |
|---|---|---|
| **网络守护** | [`guardian/guardian.sh`](../guardian/guardian.sh) | 代理进程存活、nft 表补载、策略组出口复原、ShellCrash「静默回退」自愈、`/tmp` 内存盘水位、OOM 拉起前内存闸门；每 5 分钟一轮，只做「检测 + 最小化修复」 |
| **开机自启与运行时目录兜底** | [`system/rc.local`](../system/rc.local) | tmpfs 上的 `/tmp/ShellCrash` 重建、`/var` 软链目标目录重建、四张自建 nft 表开机加载、开机后自动验收派发 |
| **站点健康守卫** | [`guardian/dest-guard.sh`](../guardian/dest-guard.sh) | 按「站点 → 策略组」用真实 URL 探测（X / GitHub / B站 / YouTube / 通用）；默认 dry-run 只写日志，启用后在候选白名单内切换（30 分钟冷却），不碰全局选择器 |
| **故障恢复** | [`recovery/recover-now.sh`](../recovery/recover-now.sh) | 「WiFi 连上了但没网」「DNS 解析全失败」「代理离线」的成套恢复；`check` 参数只诊断、不改任何东西 |
| **一次性补丁与核心升级** | [`system/archive/`](../system/archive/) · [`recovery/archive/`](../recovery/archive/) | 已执行完毕、留档可复用，各自带回滚（见下表的「回退方式」列） |
| **Windows 侧触发器** | [`recovery/local-tools/`](../recovery/local-tools/) | 双击就能把恢复脚本推到路由器上跑；口令由 `askpass.sh` 从环境变量取，自身不含口令 |

## 部署映射表

| 本地路径 | 路由器上的目标路径 | 被谁调用 | 回退方式 |
|---|---|---|---|
| `system/rc.local` | `/etc/rc.local` | 开机（procd 执行） | 改前 cp 一份到 `/root/backup/<对象>-<动作>-<YYYYMMDD>/rc.local`；或用 `system/archive/bootfix.sh` 留下的 `/root/backup/pre-bootfix-<时间戳>/rc.local` 还原 |
| `system/mixedport.nft` | `/etc/mixedport.nft` | 开机（`rc.local` 执行 `nft -f`） | 从 `/etc/mixedport.nft.bak-*` 还原；缺失时 LAN 可直连 7890（见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)） |
| `system/router-health/tmp-watch.sh` | `/etc/router-health/tmp-watch.sh` | cron `*/5 * * * *`（`/bin/ash` 调用）；看 `/tmp` 水位，并在白名单内回收根目录的陈旧文件 | 从 `/etc/router-health/tmp-watch.sh.bak-<YYYYMMDD-HHMMSS>` 还原；**停用回收**：改 conf 的 `TMP_PURGE=0`，或临时 `TMPWATCH_PURGE=0 sh …` 只观察 |
| `system/router-health/tmp-watch.conf` | `/etc/router-health/tmp-watch.conf` | `tmp-watch.sh` 读取阈值与回收开关 | 删文件 → 用脚本内置默认（WARN 24 MB / CRIT 40 MB / `PURGE=1` / 6 小时） |
| `guardian/guardian.sh` | `/etc/ShellCrash/guardian.sh` | cron `*/5 * * * *`（`/bin/ash` 调用） | 从 `/root/backup/` 下同名备份还原；**停用**：见[「启用与停用守护」](#启用与停用守护) |
| `guardian/memgate.sh` | `/etc/ShellCrash/memgate.sh` | `guardian.sh`（OOM 拉起前）与 `starts/start_legacy_wd.sh`（每分钟看门狗）调用 | 从 `/root/backup/` 下同名备份还原；缺失时两个调用方都 fail-open（照旧拉起，只告警一次） |
| `guardian/memgate.conf` | `/etc/ShellCrash/configs/memgate.conf` | `memgate.sh` 读取阈值 | 删文件 → 用脚本内置默认 `MEM_GATE_KB=32768` / `MEMGATE_FORCE_AFTER=5` |
| `guardian/dest-guard.sh` | `/etc/ShellCrash/dest-guard.sh` | cron `*/10 * * * *`（`/bin/ash` 调用）；**默认 dry-run**，只写 `/tmp/ShellCrash/dest-guard.log` | 删 cron 行 + 删文件；已切换过的组在面板里手动选回 |
| `bulk-guard.sh`（**不在本仓**，来自 `OpenwrtOpsToolkit/openwrt/`） | `/etc/ShellCrash/bulk-guard.sh` | cron `*/10 * * * *`（`/bin/ash` 调用）；组名从 `/etc/openwrt-ops/device.conf` 读 | 删 cron 行 + 删文件；已切过的组在面板里手动选回 |
| `/etc/openwrt-ops/device.conf`（设备侧新建，不入库） | 同左 | `bulk-guard.sh` 读取 `BULK_GROUP` / `BULK_PUBLIC` / `BULK_AIRPORT` | 删文件 → 脚本报「未配置」并跳过（不改任何组） |
| `recovery/recover-now.sh` | `/tmp/recover-now.sh`（临时，用完即弃） | 人工，或 `recovery/local-tools/recover-run.cmd` | 脚本自带回滚：改前把 `fake_ip_filter` 备份到 `/root/fake_ip_filter.bak.<时间戳>`，crontab 备份到 `/tmp/cron.recover.bak` |
| `recovery/local-tools/recover-run.cmd` | 不上设备 | 人双击 | 无需回退 |
| `recovery/local-tools/recover-run.ps1` | 不上设备 | `recover-run.cmd` | 无需回退 |
| `recovery/local-tools/recover-gitbash.cmd` | 不上设备 | 人双击（依赖 `%TEMP%\owrt\rsh.sh`） | 无需回退 |
| `recovery/local-tools/fix-router.sh` | 不上设备 | 人手跑（切 WiFi → 推脚本 → 切回热点） | 无需回退 |
| `recovery/local-tools/askpass.sh` | 不上设备 | ssh askpass（喂 root 口令） | 无需回退；**读 `ROUTER_PASSWORD` / `.router-password`，自身不含口令** |
| `system/archive/bootfix.sh` | `/tmp/bootfix.sh`（一次性） | 人工 | 自带备份：`/root/backup/pre-bootfix-<时间戳>/`（rc.local / guardian.sh / crontab 三件） |
| `system/archive/core-upgrade.sh` | `/tmp/core-upgrade.sh`（一次性） | 人工 | 自带 `rollback()`：mihomo 退回 v1.19.28，cron 也一并还原 |
| `recovery/archive/recover-tmpfull.sh` | `/tmp/recover-tmpfull.sh` | 人工 | 已被 `recover-now.sh` v2 覆盖（nft、配置重生成、crontab 恢复都更全） |
| `recovery/archive/verify-fix.sh` | `/tmp/verify-fix.sh` | 人工 | 已被 ShellCrash 侧 `ai-api-check.sh` 覆盖；且依赖本仓没有的 `/etc/router-health/` |

## 启用与停用守护

守护由 crontab 里的这一行拉起（**必须用 `/bin/ash` 调用**，不能用 `./guardian.sh` ——
它的 shebang 在**第 9 行**，前面 8 行是空行）：

```sh
*/5 * * * * /bin/ash /etc/ShellCrash/guardian.sh #网络守护
```

**维护 / 升级前先停守护** —— 否则守护会把代理复活、妨碍升级：

```sh
sed -i '/guardian/d' /etc/crontabs/root && /etc/init.d/cron restart
```

维护结束后再把上面那行加回去：

```sh
echo "*/5 * * * * /bin/ash /etc/ShellCrash/guardian.sh #网络守护" >> /etc/crontabs/root && /etc/init.d/cron restart
```

停守护后若代理仍被拉起，看 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)「crontab 被覆盖」一节 ——
守护只在 `/tmp/ShellCrash/shellcrash.pid` 存在时拉起进程。

**大流量守卫（`bulk-guard.sh`）要一起停**：它会在空闲时切策略组，维护期间
（改配置 / 重启 ShellCrash）切组没有意义，还可能把面板里的选择改掉：

```sh
sed -i '/bulk-guard/d' /etc/crontabs/root && /etc/init.d/cron restart
```

**站点健康守卫（`dest-guard.sh`）默认是 dry-run**：只写日志、不切组，可以和 guardian
一起常驻。先看 `/tmp/ShellCrash/dest-guard.log` 跑一周，确认它的判断与体感一致，再把
cron 行改成带 `DEST_GUARD_DRY_RUN=0` 的形式启用切换：

```sh
*/10 * * * * DEST_GUARD_DRY_RUN=0 /bin/ash /etc/ShellCrash/dest-guard.sh #站点健康守卫
```

## 一个悬空引用（`rc.local` 引用、但文件不在本仓，在路由器上）

| 被引用 | 被谁引用 | 本仓状态 |
|---|---|---|
| `/etc/router-health/reboot-verify.sh` | `rc.local` | **待补**：开机后自动验收分发器，文件在设备上、未入版本库 |

## 通用版在哪

部署映射表里的 `system/rc.local`、`guardian/guardian.sh`、`recovery/recover-now.sh` 三份
**通用版**在公开仓 `OpenwrtOpsToolkit/openwrt/`（同名文件 + 一份 `conf/device.conf.example`）。
本仓这三份是**参考实现** —— 同一套逻辑，但设备相关的值是示例值或占位符。
差异点清单见 [UPSTREAM.md](UPSTREAM.md) §7。
