# AX3000T 参考部署状态速查

> **一句话**：一页看完参考设备上的配置、入口与自检命令 ——
> 文中的值是示例快照，换设备 / 换固件 / 换订阅后必须按自己的环境重新核对。

---

## 一、凭据

**本仓库不保存任何凭据。** 文档里出现的是 `<REDACTED-...>` / `<YOUR-...>` 占位符；
脚本从环境变量或设备侧真源读取。位置、读取方式与轮换顺序见 [SECRETS.md](SECRETS.md)。

```sh
# 用密钥登录（推荐）
ssh -i ~/.ssh/owrt_ax3000t root@"$ROUTER_IP"
```

---

## 二、访问入口

把 `10.0.0.1` 换成你自己的路由器 LAN 地址：

| 服务 | 地址 | 说明 |
|---|---|---|
| LuCI 管理后台 | `https://10.0.0.1` | 自签证书，浏览器会告警 |
| mihomo 面板 | `https://10.0.0.1:9999/ui` | 需填控制 API 的 secret |
| ttyd Web 终端 | `https://10.0.0.1:7681` | 如已安装才存在；凭据自行配置 |
| 透明代理入口 | `10.0.0.1:7890` | mixed 口；建议用防火墙限制来源 |

---

## 三、关键配置示例

```
固件            OpenWrt 25.12.x / 内核 6.12.x（以你的设备为准）
LAN             10.0.0.1/24   br-lan = lan2+lan3+lan4
WAN             192.168.1.2/24（DHCP）  MTU 1480   ← 双层 NAT 时的示例
IPv6            <YOUR-IPV6-PD>（运营商 PD 委派，无 NAT66）
2.4G            信道 13 / HE20 / 20dBm   SSID "<YOUR-SSID>"
5G              信道 36 / HE80 / 23dBm   SSID "<YOUR-SSID>"
加密            psk2 + PMF optional
DHCP 池         10.0.0.25 – .224 / 12h
防火墙          wan input=REJECT / forward=REJECT；sw+hw offload 按需
代理            ShellCrash + mihomo，Redir 模式，透明代理 7890/7892
                 控制 API 127.0.0.1:9999（带 secret）
DNS             LAN 客户端 53 端口被 nft 劫持到 mihomo :1053（fake-ip）
                 dnsmasq 只服务路由器自身
```

### 策略组

策略组名与节点名来自参考订阅，**换订阅后要改成你自己的名字**：

```
🚀 节点选择  = ♻️ 自动选择
🤖 AI接口    = 按真实 API 延迟 url-test
🤖 AI网页    = select，固定到经实测可用的出口
🤖 人工智能  = 🤖 AI网页
🛑 广告拦截  = REJECT
```

### 路由器上需要的包

本仓脚本依赖下面这些。缺了对应脚本会失败 —— 装法是 `apk add <包名>`（25.12 用 apk，不是 opkg）；
表里多数是 busybox 自带的 applet，ShellCrash 与 mihomo 核心要单独装。

| 包 | 谁在用 | 缺了会怎样 |
|---|---|---|
| **ShellCrash** | 提供 `/etc/ShellCrash/` 运行时与 `start.sh` / `task/task.sh` / `starts/start_legacy_wd.sh` | 守护与恢复脚本全部无从下手 |
| **mihomo 核心** | 落地为 `/etc/ShellCrash/CrashCore.raw` | 代理起不来，透明代理与 DNS 劫持都没有 |
| `curl` | 守护探测控制 API、恢复脚本测出口 | 探测与连通性校验静默失效 |
| `nft` | fw4 自带；本仓直接调用它加载自建表 | 自建表加载不了（DNS 劫持与 7890 收口都失效） |
| `awk` / `sed` / `grep` | 读配置、改 crontab、解析输出 | 脚本中途失败 |
| `pidof` / `netstat` | 判断核心是否存活、端口是否监听 | 守护误判「代理离线」 |
| `df` | 看 `/tmp` 与 overlay 水位 | 内存盘写满的预警失效（见 [PITFALLS.md](PITFALLS.md)） |
| `nslookup` | 诊断 DNS | 排障时缺一手信息 |
| `crontab` / `logger` | 挂守护与其它定时任务、落日志 | 守护不会自动跑 |
| `uclient-fetch` / `jsonfilter`（**可选**） | 仅 ShellCrash 侧的规则生成器用 | 本仓脚本不直接依赖；缺了只是自动更新失败 |

> 装完对一遍：`nft list tables` 应能看到 `inet quicguard` / `googlecn` / `googleroute` / `mixedport` 四张自建表。

---

## 四、自检命令

```sh
# 1) 路由器侧健康快照（每次一行，落 /etc/router-health/）
sh /etc/router-health/health-snapshot.sh

# 2) AI 链路自检（ShellCrash 侧脚本；应全部 OK，退出码 0）
sh /etc/ShellCrash/ai-api-check.sh

# 3) 代理链路与出口
curl -s --max-time 15 -x http://127.0.0.1:7890 https://chatgpt.com/cdn-cgi/trace | grep -E "^(ip|loc|colo)="
curl -s -o /dev/null -w "%{http_code}\n" --max-time 15 -x http://127.0.0.1:7890 https://opencode.ai/zen/go/v1/models

# 4) 分流是否正确（若已部署 routing-test.sh）
sh /etc/ShellCrash/routing-test.sh

# 5) 定时任务与守护日志
cat /etc/crontabs/root
tail -20 /tmp/ShellCrash/guardian.log
tail -20 /tmp/ShellCrash/dest-guard.log
tail -20 /etc/ShellCrash/logs/auto-update.log
```

### 一键重启 + 自动验收（醒来后想验证重启时用这个）

```sh
# 备份 -> 注册开机后自检 -> 重启（约 1-2 分钟恢复）
sh /etc/router-health/reboot-verify.sh start

# 起来之后看验收报告
sh /etc/router-health/reboot-verify.sh status
# 或直接看 /etc/router-health/reboot-report.txt
```

### 守护进程在做什么（每 5 分钟）

| 动作 | 触发条件 | 行为 |
|---|---|---|
| 出口组复原 | 节点选择 / 人工智能组的真实出口落在不可用地区 | 复位到健康组；不会覆盖你手动选的合法出口 |
| 干净出口守卫 | Google 判定当前 AI 出口为 CN | 切到预先实测可用的节点（先校验该节点确实在组内） |
| AI 出口失效自愈 | 连续 3 次（=15 分钟）探测失败 | 在候选里找「能连通 + Google 判非 CN」的换过去；找不到就保持原样 |
| nft 表补载 | quicguard / googlecn / googleroute 任一缺失 | 从 `/etc/*.nft` 重新加载 |

另有 **1 分钟看门狗**（进程不在就拉起，且不会误杀已健康运行的代理）、
**10 分钟站点健康守卫（dry-run）**、**10 分钟面板选择保存**、
**30 分钟健康快照**、**每周订阅与规则自动更新**。

### 站点健康守卫在做什么（每 10 分钟，默认 dry-run）

`dest-guard.sh` 按「站点 → 策略组」用真实 URL 探测，只处理站点族自己的出口：

| 站点 | 组 | 探测 URL | 动作 |
|---|---|---|---|
| X / Twitter | `𝕏 媒体` | `pbs.twimg.com/robots.txt` | 只记录（url-test 自愈） |
| GitHub | `🔗 GitHub 出口` | `github.com/robots.txt` | 只记录（url-test 自愈） |
| B站 | `🎬 B站解锁` | `api.bilibili.com/x/web-interface/zone` | 当前出口失败时在候选白名单内切换，30 分钟冷却 |
| YouTube | `🤖 干净出口` | `www.youtube.com/` | 只记录（guardian 管理） |
| 通用 | `🚀 节点选择` | `www.cloudflare.com/cdn-cgi/trace` | 只记录（guardian 管理） |

**默认 dry-run**：只写 `/tmp/ShellCrash/dest-guard.log`，不切任何组；每项探两次取较小值，
避免单次抖动误判。观察一周确认判断与体感一致后，在 cron 行前加
`DEST_GUARD_DRY_RUN=0` 再启用切换。

---

## 五、已知残留风险

| # | 风险 | 为什么不改 | 想改时怎么做 |
|---|---|---|---|
| 1 | root 口令与 WiFi 密码相同 | 改密码必须设备主人知情 | 先用 SSH 密钥登录验证 → `uci set dropbear.main.PasswordAuth='off'` |
| 2 | `7890` 混合口对 LAN 无鉴权 | mihomo 的 `authentication` 会同时作用于 redir 入站，可能搞坏透明代理 | 用防火墙单独限制该端口的来源（需实测） |
| 3 | 订阅 token 经第三方聚合器 | 改订阅方式要重测分流 | 改 `configs/ShellCrash.cfg` 的订阅 URL + 模板来源 |
| 4 | 流量走 CPU，无硬件 NAT（或 offload 只覆盖直连） | 取决于内核与驱动 | 换厂商内核或接受现状 |
| 5 | SoC 温度接近触发点 | 改 cooling map 要重编内核 | 改善散热；观察健康快照里的 `temp_c` |
| 6 | `experimental: {interface-name: en0}` 死配置 | 官方脚本生成，升级会重置 | 后处理脚本里删该行 |

---

## 六、备份

| 内容 | 建议位置 |
|---|---|
| 改前全量配置 | 路由器 `/root/backup/`（按日期命名） |
| 改后全量备份 | 本机离线归档或密码管理器附件 |
| 设备状态快照 | `/etc/router-health/` |
| 不可再生材料（私钥、整机快照） | `vault/`，**不入库**；见 [BACKUP-VAULT.md](BACKUP-VAULT.md) |

保留策略与修剪阈值见 [MAINTENANCE.md](MAINTENANCE.md)。

---

## 七、相关文档

| 要查什么 | 去哪 |
|---|---|
| 硬件 / 固件 / 拓扑基线 | [HARDWARE.md](HARDWARE.md) |
| 部署映射与回退 | [DEPLOY.md](DEPLOY.md) |
| 排障步骤 | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| 凭据位置与轮换 | [SECRETS.md](SECRETS.md) |
| 变更台账 | 仓库根 [CHANGELOG.md](../CHANGELOG.md) |
