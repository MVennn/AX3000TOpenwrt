# 路由调优研究与高星项目对照

> **一句话**：外部研究给出的常规调优，本机绝大多数已做过或明确否决 —— 真正还值得动的只有「内存兜底 / 闪存腾挪 / 5G 功率复测」三项，其余照旧；本文把每条建议与本机实测逐一对齐，附 GitHub 高星项目与一手来源。

研究轮为**只读**。随后 2026-11-16 的落实轮已上机核对：列出的待落地项（zram、GOMEMLIMIT、cnip.mrs）**三项其实早已在设备上生效**（详见 §5 落地核对），无需重复改动；真正还没做的只剩 5G txpower A/B 复测。

查证时间：**2026-11-16 17:58–18:04 Asia/Shanghai**。star / license / 更新时间经 `gh api repos/{owner}/{repo}` 逐仓核实（39 仓），非引擎摘要。

---

## 1. 本机基线现状（对照高程）

固件基线以 [HARDWARE.md](HARDWARE.md) §2 为准（**OpenWrt 25.12.6 / 内核 6.12.112 / mediatek-filogic**），非 10-19 快照里的 25.12.2。

| 项 | 本机实测值 | 状态 |
|---|---|---|
| SoC / RAM / 闪存 | MT7981 双核 A53 / 239 MB / overlay 57.5 MB（占用 65%） | 已测 |
| 拥塞控制 / 调度 | cubic + fq_codel，**无 BBR** | 已定（BBR 已否） |
| flow offload | 软 + 硬均开；PPE 只覆盖境内直连，代理流 0 例被 offload | 已开且验证 |
| conntrack_max | 15360（实际用量 869–1353） | 够用 |
| SQM | 包已装、`enabled=0`，interface 已修正为 wan | Intentional off |
| sysctl 加固 | netdev_backlog 1000→2048；slow_start_after_idle 1→0 | 已调 |
| MTU | 1480（真实路径 1484，改 1500 会让 UDP 黑洞） | 已调 |
| WiFi | 2.4G ch13/HE20/20dBm；5G ch36/HE80/23dBm | 已定（160M/40M 已否） |
| 代理栈 | ShellCrash + mihomo v1.19.33，Redir 模式，fake-ip 劫持 53 | 已定 |
| swap / zram | 无 | 兜底缺口 |
| CPU 调频 | 无 cpufreq（load 0.03–0.14 无瓶颈） | 已否 |

---

## 2. 通用软件层调优研究（外部证据）

### 2.1 SQM / 队列：cake vs fq_codel
- **研究结论**：官方 SQM 文档明确「Use cake, not fq_codel」——cake 在抗 bufferbloat 上全面更优；速率按标称 85% 或实测 95% 填，留余量给链路层开销，避免瓶颈推到 modem 侧。CPU 受限时 fq_codel 吞吐约高 15%。
- **本机裁决**：**不改**。本机 SQM 关闭且代理流不走 flow offload，瓶颈不在队列；fq_codel 已被第八轮审计确认够用。开启 SQM 会与 flow offload 冲突（HFO 不兼容 SQM），得不偿失。

### 2.2 sysctl / 拥塞控制
- **研究结论**：BBR 需 `kmod-tcp-bbr`，适合高带宽高延迟（高 BDP）链路；brutal 是第三方内核模块（HyNetworks/tcp-brutal，非 OpenWrt 官方）；`tcp_tw_reuse` 默认 2（仅 loopback），路由转发别照搬服务器土法设 1；rmem/wmem 内核自动调优，常规路由无需手调；conntrack_max 默认 = buckets，按需调大代价是内存。
- **本机裁决**：**全不改**。BBR 已因「无高 BDP 场景」否决；brutal 非官方不碰；conntrack 实际用量（≤1353）远低于 15360，无需调大。

### 2.3 IRQ / 软中断
- **研究结论**：多队列网卡用 smp_affinity / RPS 分散软中断；irqbalance 在多核有余量时受益，但**双核可能反降**，对大小核不友好。
- **本机裁决**：**不改**。本机双核 A53 且已开 `packet_steering=1`（等价软件分流），上 irqbalance 反而可能降速。

### 2.4 DNS / 缓存
- **研究结论**：dnsmasq cachesize 默认 1000，可按需加大；加密 DNS 用 https-dns-proxy（25.12+ 走 `apk add`）；第三方有 smartdns（测速选最快 IP）。
- **本机裁决**：**不改**。本机 53 端口已被 nft 劫持到 mihomo :1053（fake-ip），dnsmasq 只服务路由器自身——「dnsmasq 客户端侧调优」第八轮已否，重复。

### 2.5 flow offload 取舍
- **研究结论**：SFO 带宽 2–3×；HFO 主要靠 MediaTek Filogic、典型 64 队列、不兼容 SQM；**只作用于转发流，不含本机自发起连接**；开 HFO 自动开 SFO。AX3000T 上有 L2TP+HFO 内核崩溃报告（issue #20869），AN8855 交换机版本 HFO probe 失败案例。
- **本机裁决**：**保持现状**。本机是 Redir 模式（非 L2TP），PPE 实测真实生效且只覆盖境内直连——与官方「代理流不走 offload」机制一致。本机因 SQM 关闭，不存在 HFO/SQM 冲突。

---

## 3. AX3000T / Filogic 平台专项

- **芯片确认**：MT7981B（Filogic 820），双核 A53 1.3GHz，配对 MT7976C 无线；256MB RAM + 128MB NAND 硬上限；交换机 MT7531AE 与 Airoha AN8855 混用。
- **版本坑**：RD03v2 是高通硬件、官方不支持；NAND/交换机型号决定最低版本，推荐 25.12.x（当前 25.12.6 覆盖三种 NAND + 两种交换机）——本机版本正确。
- **WiFi**：硬件上限 2.4G 40MHz / 5G 160MHz；但 160MHz + 多 SSID 有已知挂掉问题（issue #16537），信道 100/149 的 160MHz 需 patch；5G txpower 实测约 26dBm，厂商标称 30dBm 依赖闭源驱动达不到。
- **本机裁决**：160MHz / 40MHz 第八轮已否（无 802.11v、收益不抵代价），保持 HE80 / HE20。**唯一可评估项**：5G txpower 23→26dBm（见 §5）。

### 透明代理场景专条
- 本机出口本就走路由器透明代理，**PC 上再拨测节点 = 双重代理，结果失真**（全局环境事实，非故障证据）。
- 路由器侧：本机自发起连接不走 flow offload；LAN 客户端若走 TPROXY 分流则需慎开 SFO / 关 HFO。本机 Redir 模式下 PPE 行为已实测确认，无需改。

---

## 4. GitHub 高星项目（star 查证 2026-11-16）

### 4.1 调优直接可用
| 项目 | star | 作用 | 本机相关性 |
|---|---:|---|---|
| [openwrt/openwrt](https://github.com/openwrt/openwrt) | 29,220 | 主源码官方镜像 | 基线源码 |
| [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) | 11,930 | 国内向分支 | 备选底座 |
| [openwrt/luci](https://github.com/openwrt/luci) | 7,983 | Web 配置界面 | SQM/防火墙 UI |
| [openwrt/packages](https://github.com/openwrt/packages) | 4,675 | 社区软件包源 | sqm-scripts 正统来源 |
| [Irqbalance/irqbalance](https://github.com/Irqbalance/irqbalance) | 673 | 多核 IRQ 均衡 | 双核机不建议上 |
| [tohojo/sqm-scripts](https://github.com/tohojo/sqm-scripts) | 290 | SQM/cake 前端 | 官方指定实现 |

### 4.2 代理网关 / DNS（本机核心场景）
| 项目 | star | 作用 | 本机相关性 |
|---|---:|---|---|
| [MetaCubeX/ClashMetaForAndroid](https://github.com/MetaCubeX/ClashMetaForAndroid) | 49,592 | Android mihomo 客户端 | mihomo 核心佐证 |
| [XTLS/Xray-core](https://github.com/XTLS/Xray-core) | 42,938 | Xray 代理核心 | passwall 上游 |
| [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) | 35,810 | 原代理核心仓（见口径说明） | 本机 v1.19.33 来源 |
| [vernesong/OpenClash](https://github.com/vernesong/OpenClash) | 28,228 | OpenWrt Clash/mihomo + LuCI | 路由侧代理首选 |
| [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat) | 21,046 | geoip/geosite 分流规则 | 分流数据 |
| [juewuy/ShellCrash](https://github.com/juewuy/ShellCrash) | 13,682 | shell 运行 sing-box/mihomo | **本机在用** |
| [pymumu/smartdns](https://github.com/pymumu/smartdns) | 11,420 | 本地 DNS，测速选最快 IP | DNS 优化备选 |
| [Openwrt-Passwall/openwrt-passwall](https://github.com/Openwrt-Passwall/openwrt-passwall) | 10,006 | OpenWrt Passwall 插件 | 路由侧代理备选 |
| [zfl9/chinadns-ng](https://github.com/zfl9/chinadns-ng) | 1,389 | DNS 分流 + nftset | DNS 分流备选 |

### 4.3 运维监控
| 项目 | star | 作用 |
|---|---:|---|
| [tsl0922/ttyd](https://github.com/tsl0922/ttyd) | 12,639 | 浏览器共享终端 |
| [cogwheel0/luci-mobile](https://github.com/cogwheel0/luci-mobile) | 734 | 手机端远程管理 OpenWrt |

> **口径说明**：`MetaCubeX/mihomo` 当前 description/README 疑似改为非代理内容（star 35,810 确切），代理核心身份以 [ClashMetaForAndroid](https://github.com/MetaCubeX/ClashMetaForAndroid) 与 wiki.metacubex.one 为准。License `NOASSERTION`=多许可证/非标准，`NULL`=无 license 文件，均未臆造协议。低 star / 停更项（fancontrol、myautocore、firewall4、luci-app-clash）已剔除出主表。

---

## 5. 落地核对：研究建议 vs 设备真实现状

> 2026-11-16 18:15 SSH 上机只读核对结果。文档快照（2026-10-20）与设备现状已有偏差，**以现场为准**。

| 建议 | 上报时的判断 | 设备实测（2026-11-16） | 处置 |
|---|---|---|---|
| GOMEMLIMIT=64MiB | 待落地 | `/etc/ShellCrash/configs/command.env` 已 `export GOMEMLIMIT=64MiB`（mtime 2026-10-20 16:13）；运行中 CrashCore PID 7184 的 `/proc/<pid>/environ` 确实含该值 | **早已生效，无需改** |
| zram / zswap 兜底 | 中优先级待评估 | `/dev/zram0` 已作为 swap 在跑：118,780 KB，已用 37,360 KB；`system.@system[0].zram_size_mb=116`、`zram_comp_algo=lzo-rle` | **早已落地**（旧红线已过时）；本轮不动 |
| 内联 IP-CIDR → cnip.mrs | 待落地 | 迁移链路**已完整生效**：`clash_modify.sh:303` 每次订阅更新自动调 `rules-cnip.sh`；当前 config.yaml 中「全球直连」目标的内联 IP-CIDR = **0 条**，`RULE-SET,cnip` 与 `cnip` provider 均已在位。653 条 IP-CIDR 全是其它策略组（大流量/广告/节点选择等）的条目，脚本按设计不碰 | **早已落地**，无需改 |
| 5G txpower 23→26dBm | 低优先级复测 | 实测否决：当前 SoC **59.8°C**（逼近 60°C 热墙），5G 已 Tx 23dBm / Signal -42dBm / Link 68-70 / 1050Mbps（近乎满格）。此温度下提功率是负收益高风险，证据不支持改 | **保持 23dBm**，复测项关闭 |
| overlay 闪存腾挪（原研究里的隐含前提） | overlay 65% 需腾挪 | 实测 overlay 仅 **47%**（26,440/58,832 KB，余 29 MB），比旧快照的 65% 低很多；`/etc/ShellCrash/ruleset/cnip.mrs` 已存在且每日更新，备份区合计 <2 MB | **前提不成立**，无需腾挪 |

**本轮未对设备写入任何配置**：四项待落地建议经上机核对，三项早已生效、一项（5G 功率）有据否决、闪存腾挪前提已消失。全部结论都来自现场只读实测，没有一条需要盲改。

### 原始建议表（研究时的假设，保留作对照）

> 以下三项是从「本机待办 + 研究可达」交集里筛出的，其余常规调优均已做或已否。

| 优先级 | 建议 | 依据 | 落地动作 |
|---|---|---|---|
| 高 | **内联 IP-CIDR → cnip.mrs** | [HARDWARE.md](HARDWARE.md) §5 待办：9,631 条内联占闪存，overlay 已 65% | 按 MAINTENANCE.md 保留策略迁移；先备份、后验证规则数不丢 |
| 高 | **GOMEMLIMIT=64MiB** | 同上待办；mihomo 13,106 条规则 + 239MB RAM，限制 GC 上限防内存冲高 | 在 ShellCrash 环境变量注入，改前留存回滚副本 |
| 中 | **zram / zswap 兜底评估** | 本机无 swap/zram，内存吃紧时无缓冲；256MB RAM 设备常见增益手段 | 先量内存峰值与 swap 需求，证明确有压力再上；否则属多余 |
| 低 | **5G txpower 23→26dBm 复测** | 论坛实测 MT7981 5G 可到 26dBm（398mW），本机保守设 23 | 单频段 A/B 测信号与温度（本机常驻 58–59°C，注意热墙），确认 regulatory 允许再定。**→ 2026-11-16 实测否决：59.8°C 逼近热墙 + 信号已近乎满格，保持 23dBm** |

**不建议动**（重复劳动或高风险）：BBR / brutal / 2.4G 40MHz / 5G 160MHz / SQM 开启 / irqbalance / dnsmasq 客户端调优 / conntrack 调大 / MTU 改回 1500 / HFO 叠加 VPN。

---

## 6. 引用

| # | 来源 | 确切值 | 用在哪 |
|---|---|---|---|
| 1 | [OpenWrt SQM 官方](https://openwrt.org/docs/guide-user/network/traffic-shaping/sqm-details) | Use cake not fq_codel；85% 标称 / 95% 实测 | §2.1 |
| 2 | [Flow Offloading 官方](https://openwrt.org/docs/guide-user/perf_and_log/flow_offloading) | SFO 2–3×；HFO 靠 Filogic、不兼容 SQM、只管转发流 | §2.5 / §3 |
| 3 | [OpenWrt AX3000T 设备页](https://openwrt.org/toh/xiaomi/ax3000t) | MT7981B/Filogic 820；2.4G 40M + 5G 160M 上限；推荐 25.12 | §3 |
| 4 | [内核 ip-sysctl](https://docs.kernel.org/networking/ip-sysctl.html) | tcp_tw_reuse 默认 2(loopback)；rmem/wmem 自动调优 | §2.2 |
| 5 | gh api repos/{owner}/{repo} | 全表 star/license/时间，逐仓核实 2026-11-16 18:02 +08 | §4 |
