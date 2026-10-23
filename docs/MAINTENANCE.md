# 保留策略与清理流程

> **一句话**：备份区该留什么、留几个、什么时候修剪 —— 以及为什么
> **光清理没用，必须「改完即删」**。

> **通用版在哪**：本篇提到的 `guardian.sh` / `recover-now.sh` 是**参考实现**；
> 通用版在公开仓 `OpenwrtOpsToolkit/openwrt/` —— 两边的分工见 [UPSTREAM.md](UPSTREAM.md) §7。
> 本篇的保留策略只管**设备上的备份区**，通用版不涉及设备上的备份区。

---

## 1. 两个备份区，先分清

| 位置 | 是什么 | 处置 |
|---|---|---|
| 路由器 `/root/backup/` | 改路由器之前在**设备上**留的回滚点 | 按本文的保留策略修剪；**不能**长期堆着 |
| PC 侧离线归档 | 设备状态的**本机镜像** + 少量锚点包 | 含 `etc/shadow` / SSH 主机私钥 / HTTPS 私钥的包**移出版本库**；只留小而稳的锚点 |

**原则**：`backup/` 是**小而稳定的锚点目录**，不是垃圾堆放区。
大体积的升级对比包与含密钥的包天然属于版本库之外。

---

## 2. 命名约定

统一 `<对象>-<动作>-<YYYYMMDD>`（需要精确到分时补 `-HHMMSS`）：

| 类型 | 约定 | 例 |
|---|---|---|
| 改前快照（目录） | `pre-<purpose>-<YYYYMMDD>/` | `pre-rule-reorg-20261020/` |
| 单文件回滚 | `<name>.bak-<YYYYMMDD-HHMMSS>` | `guardian.sh.bak-20261020-015300` |
| 配置基线 | `config-<fwver>-<YYYYMMDD>.tar.gz` | `config-25.12.6-20261020.tar.gz` |
| 升级前后 | `sysupgrade-{pre,post}-<fwver>-<YYYYMMDD>.tar.gz` | `sysupgrade-pre-25.12.6-20261020.tar.gz` |
| 状态转储 | `state-<kind>-<YYYYMMDD>.txt` | `state-nft-20261020.txt` |
| 主题包 | `<theme>-files.tar.gz` | `luci-theme-argon-files.tar.gz` |

**现状问题**：旧目录里 `bk-` / `pre-` / `current-` / `router-pre-` 四套前缀混用，
还有「目录套同名目录」（`backup/backup/`）这种毫无语义的形态 —— **新写的备份一律按上表**，
旧的不强制改名（改名要同步改引用方，代价大于收益）。

---

## 3. 修剪阈值

| 规则 | 阈值 | 理由 |
|---|---|---|
| **同 basename 只留最新 1 个** | 保留 mtime 最新的，其余删 | 「改脚本前 cp 一份」会产出同一个名字的一堆副本，只有一份有回滚价值 |
| **`pre-*` 只留最近 3 个** | 按 mtime 排序，删掉第 4 个及以后 | 最近的三个覆盖了「今天改了什么」，更早的回滚点已经过期 |
| **`*.apk-new` 一律不留** | 全删 | 内容全是上游 OpenWrt 的默认模板（`luci.apk-new` 只有 `option lang auto` 等），**不含任何本机定制**，不需要「合并」 |
| **总量上限触发修剪** | 路由器 `/root/backup` **≤ 1 MiB** | 已实测有效：从 **4,128 KB 降到 532 KB**（U05 批次） |
| **单文件回滚副本** | 只留最新 1 个 | 同上 |

**必保留清单**（不论体积都不删，U05 已核对过 20 项）：

- `/etc/crontabs/root`（当前定时任务）
- `/etc/config/` 下的当前 UCI 配置
- `/etc/ShellCrash/yamls/`（订阅与规则源）
- `/etc/ShellCrash/CrashCore.raw`（正在运行的内核）
- `sysupgrade.conf`（保留清单本身）
- `authorized_keys`（SSH 公钥）、`/etc/router-health/`、`FLASH-SOP.md`
- `luci-theme-argon-files.tar.gz`（argon 主题在 overlay 上**没有别的来源**，是唯一恢复包）

---

## 4. 清理流程

```sh
# ---- 在路由器上（/root/backup）----
cd /root/backup

# 1) 先看现状：谁占了多少
du -sk * 2>/dev/null | sort -rn | head -20
du -sk . | tail -1

# 2) 同 basename 只留最新 1 个（先看要删什么，确认后再删）
ls -lt *.bak-* 2>/dev/null | awk 'NR>1{print $NF}'

# 3) pre-* 只留最近 3 个
ls -dt pre-* 2>/dev/null | tail -n +4

# 4) apk 残留全删（不需要合并）
rm -f *.apk-new

# 5) 总量复核
du -sk .
```

**PC 侧离线归档**的处置顺序按「先凭据、再体积、最后归档」：

1. **先处理凭据** —— 含 `etc/shadow` / SSH 主机私钥 / HTTPS 私钥 / WireGuard 明文私钥的包
   **移出版本库**（离线加密归档），不是「删了了事」；
2. **再删可删项** —— 过期镜像目录、一次性调试残留、`.apk-new`；
3. **再归档** —— 主题包、配置基线、状态转储各归各位。

---

## 5. 改完即删（这才是止血点）

> **结论**：**光清理不改变斜率。**

- **堆积机制**：「每次人工 / Agent 改动脚本前，先 `cp` 一份到 `/root/backup`」——
  **副本只进不出**。清一次只是把当下的堆积清掉，下一次改动又堆回去。
- **真正的止血点有三样，缺一不可**：
  1. **改完即删** —— 改动**验证通过**之后，立刻把这次改动的临时副本删掉；
  2. **cron 修剪** —— 定期跑 §4 的阈值检查，而不是等它堆到爆；
  3. **副本移出 overlay** —— 需要长期留的包挪到 PC 侧或离线归档，别放在设备上。
- **判定「验证通过」的标准**：守护日志无 `ERROR`，且关键自检（健康快照 / 代理链路）
  通过。**没验收过就不算通过**，但也**不许把副本一直留着** —— 不通过就回滚，回滚完删副本。

---

## 6. RAM 型 `/tmp` 的自动回收

> 与 §1–§5 的备份区不是一回事：这里管的是**内存盘**，占的是 RAM，不是 flash。

`/tmp` 是 tmpfs，由 `/etc/init.d/tmpfs-cap` 封顶 **48 MiB**，且本机**无 swap** ——
tmpfs 页不可回收，写满即 `ENOSPC`，ShellCrash 生成配置失败、退回基础配置
（机制见 [PITFALLS.md](PITFALLS.md) ⑩）。它**没有自动过期机制**：OpenWrt 上没有
tmpwatch / systemd-tmpfiles，只有删文件或重启才会降。

### 6.1 回收器与阈值

`/etc/router-health/tmp-watch.sh` 每 5 分钟一轮（cron），做两件事：**看水位** +
**回收白名单内的陈旧文件**。阈值与开关在 `tmp-watch.conf`：

| 键 | 默认 | 含义 |
|---|---|---|
| `TMP_WARN_KB` | 24576（24 MB，上限的 50%） | 超了写 WARN 日志 + syslog |
| `TMP_CRIT_KB` | 40960（40 MB） | 超了写 CRIT，离 `ENOSPC` 只剩 8 MB |
| `TMP_NOTICE_KB` / `TMP_GROWTH_KB` | 20480 / 4096 | 20 MB 以上且单轮增长 ≥4 MB → GROW 告警（早期发现泄漏） |
| `TMP_PURGE` | 1 | `0` = 只观察不删 |
| `TMP_PURGE_AGE_MIN` | 360 | 只删 6 小时未修改的文件 |

### 6.2 回收边界（改脚本前必须守住）

1. **只动 `/tmp` 根目录**（`find /tmp -maxdepth 1`），**永不递归进子目录** ——
   `/tmp/ShellCrash/config.yaml` 是正在运行的配置，删了就是「掉配置」；
2. **正向白名单**：`*.html` / `*.json` / `*.txt` / `*.log` / `*.out` / `*.sh` /
   `test*.yaml` / `*.nft.new.*` / `cdnbody*`；没匹配上的一律不碰；
3. **保护名单**：`TZ` / `resolv.conf` / `dhcp.leases` / `cron_tmp` / `.ujailnoafile` /
   `luci-indexcache.*.json`；
4. **三重保险**：6 小时未修改 + 没被任何进程打开（比对 `/proc/*/fd`）+
   每轮最多 64 个 / 8 MB；
5. 唯一进入子目录的例外：`/tmp/ShellCrash/config.yaml.rules-*.{del,ana}` ——
   `rules-cnip.sh` / `rules-porn.sh` 带 PID 的中间产物（`trap` 未执行时残留，
   文件名含 PID 永不复用）；`config.yaml` / `.bak-*` / `-test.yaml` 不在其中。

### 6.3 首次清理记录（2026-10-23 22:00 实测）

| 指标 | 清理前 | 清理后 |
|---|---|---|
| `/tmp` 已用 | 29,412 KB（60%） | 4.2 MB（9%） |
| `MemAvailable` | 30,396 KB | 52,416 KB |
| `Shmem` | 42,976 KB | 17,836 KB |

共清掉 87 个根目录调试文件（网页抓取 `*.html`、`play*.json`、`bili-*.log` 等）
与 9 个 ShellCrash 中间产物；`config.yaml` 的 md5 全程未变。

**手工跑一次**（不影响 cron）：

```sh
sh /etc/router-health/tmp-watch.sh                    # 有候选才删，无候选静默
TMPWATCH_PURGE=0 sh /etc/router-health/tmp-watch.sh   # 只观察，不删
tail -5 /etc/router-health/tmp-usage.log              # 告警与回收台账（上限 64 KB）
```

**不在白名单内、需要人工判断的**：`/tmp/cache/apk`（apk 索引，每周 `apk update` 重建）、
`/tmp/ShellCrash/config.yaml.bak-*` 与 `config.cnip-test.yaml`。回收器不碰它们 ——
要清就按 §4 的思路先看再删具体文件名，**不要为了省事往白名单里加通配符**。

---

## 7. 不做什么（红线）

以下都是**已经评估过并否决**的，别再提、别再动：

| 不要动 | 理由 |
|---|---|
| `vm.min_free_kbytes` | OOM 时空闲内存已经低于它，调低只会更早爆 |
| `vm.swappiness` | 无 swap 时无效 |
| `vfs_cache_pressure` | 方向是反的 |
| `nf_conntrack_max` | 调小只省 88 KB |
| **开 zram** | 池子从同一块 239 MB 里挖，CrashCore 的匿名页是热页，收益 ≈ 0 |
| `start_old=OFF` | 会启用 procd respawn，OOM 时把「只杀核心」放大成「反复重启」 |
| 手动删 `CrashCore.raw` / 把它加进 `sysupgrade.conf` | 那是正在运行的内核；加了保留清单会让每次升级都往 overlay 里塞 24 MiB |
| `apk del wpad-mbedtls` | 断 WiFi |
| `apk del` ROM 里的包 | 闪存收益为 0（ROM 本来就不占 overlay） |
| `/var -> /tmp` 软链 | 系统设计如此，见 [PITFALLS.md](PITFALLS.md) ② |
| 删防火墙链、重启路由器 | 守护的硬约束：只做「检测 + 最小化修复」 |
| **把 `/tmp` 回收范围扩到子目录、或改成通配符删目录** | `/tmp/ShellCrash` 里是正在运行的配置；`/var` 还是指向 `/tmp` 的相对软链，删目录会连带 dnsmasq 配置（见 [PITFALLS.md](PITFALLS.md) ②）。回收器只走 §6.2 的白名单 |
| 改 root 口令、WiFi SSID / PSK、订阅链路 | **必须用户知情并同意**，脚本与守护都不碰 |

**一个例外要记着**：`/www/modern`（用户自建项目）**不在 `sysupgrade.conf` 里**，
刷机会丢 —— **应该新增进保留清单**，但这属于用户的资产，动手前先问。

---

## 8. 相关文档

| 要查什么 | 去哪 |
|---|---|
| 改脚本前该备份到哪、怎么退回去 | [DEPLOY.md](DEPLOY.md) 的部署映射表 |
| 排障步骤 | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| 当前 flash / 内存占用 | [HARDWARE.md](HARDWARE.md) §5 |
| 凭据位置（清理时要一并处理） | [SECRETS.md](SECRETS.md) |
| 逐条变更台账 | 仓库根 [CHANGELOG.md](../CHANGELOG.md) |
| 发版时版本号动哪一位（版本晋升规则正本） | [VERSIONING.md](VERSIONING.md) §1–§2 |
| 许可证 | 仓库根 [LICENSE](../LICENSE)（MIT 全文） |
