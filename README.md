<div align="center">

<img src="assets/logo.png" width="128" alt="AX3000TOpenwrt">

# AX3000TOpenwrt

**小米 AX3000T 路由器的 OpenWrt 本体运维参考实现**

Make the Router Boring Again.

![CI](https://github.com/MVennn/AX3000TOpenwrt/actions/workflows/ci.yml/badge.svg) ![源码仓库](https://img.shields.io/badge/源码仓库-GitHub-181717?logo=github&logoColor=white) ![问题反馈](https://img.shields.io/badge/问题反馈-Issues-181717?logo=github&logoColor=white) ![OpenWrt](https://img.shields.io/badge/OpenWrt-25.12-00B5E2?logo=openwrt&logoColor=white) ![ShellCrash](https://img.shields.io/badge/ShellCrash-mihomo-9B59B6) ![License](https://img.shields.io/badge/License-MIT-blue)

</div>

---

## 这是什么

一台小米 AX3000T 刷上 OpenWrt 之后，硬路由之外还叠了一层 ShellCrash + mihomo 透明代理。这个仓库只管**路由器本体这一层**：网络守护、开机自启、故障恢复，以及这些脚本改过的系统状态。

**这是一份脱敏后的参考实现**：脚本保留真实逻辑，设备相关的值（SSID、IPv6 PD 前缀、节点名、出口 IP、本机路径）已替换为占位符或环境变量。原始设备证据、内部进度台账与审计报告**不随公开仓发布**。通用版在兄弟仓 [OpenwrtOpsToolkit](https://github.com/MVennn/OpenwrtOpsToolkit) —— 同一套逻辑，设备相关的值抽成配置项；两边的分工见 [docs/UPSTREAM.md](docs/UPSTREAM.md) §7。

**这个仓库不管**：ShellCrash 与 mihomo 本体、订阅内容、分流规则与 geosite 规则集、LuCI 控制台、AI 模型接入。它们各有归属，这里只引用，不复制。

## 环境要求

| 项 | 要求 |
|---|---|
| 设备 | 小米 AX3000T（MT7981），OpenWrt 25.12 |
| 路由器上 | ShellCrash + mihomo 核心、nft、curl，以及 awk / sed / grep / pidof / netstat / df / nslookup 等常用工具 |
| 本机 | SSH（建议用密钥）、Git Bash 或 PowerShell |

固件、内存、网络拓扑等基线见 [docs/HARDWARE.md](docs/HARDWARE.md)；路由器上需要的包清单见 [docs/OPERATIONS.md](docs/OPERATIONS.md) §三。

## 使用

1. 用 SSH 连上你的路由器（地址换成你自己的 LAN 地址）：

   ```sh
   export ROUTER_IP=192.168.1.1
   ssh -i ~/.ssh/owrt_ax3000t root@"$ROUTER_IP"
   ```

2. 先看状态 —— [docs/OPERATIONS.md](docs/OPERATIONS.md) 是一页速查：当前配置、访问入口、自检命令。
3. 出问题了跑恢复脚本 —— 在路由器上直接跑，或在 PC 上双击 `recovery/local-tools/recover-run.cmd` 推过去跑；带 `check` 参数时只诊断，不改任何东西：

   ```sh
   ash /tmp/recover-now.sh check     # 只诊断
   ash /tmp/recover-now.sh           # 完整修复
   ```

4. 把守护脚本装上并挂进 crontab，每 5 分钟一轮：

   ```sh
   R=root@"$ROUTER_IP"
   scp guardian/guardian.sh "$R":/etc/ShellCrash/guardian.sh
   ssh "$R" 'chmod +x /etc/ShellCrash/guardian.sh'
   ssh "$R" 'echo "*/5 * * * * /bin/ash /etc/ShellCrash/guardian.sh #网络守护" >> /etc/crontabs/root && /etc/init.d/cron restart'
   ```

5. 维护或升级前先停守护，否则守护会把代理复活、妨碍升级（命令见 [docs/DEPLOY.md](docs/DEPLOY.md)）。

> ⚠️ `guardian.sh` 的 shebang 在**第 9 行**（前面 8 行是空行），直接 `./guardian.sh` 不会执行 —— 必须用 `sh` 或 `/bin/ash` 显式调用，crontab 里已经这么写了。

脚本装到路由器的哪个路径、被谁调用、出事怎么退回去，见 [docs/DEPLOY.md](docs/DEPLOY.md)。

## 目录

```
guardian/       网络守护（检测 + 最小化修复）
recovery/       故障恢复脚本与 Windows 侧触发器
system/         开机脚本（rc.local）与已归档的一次性脚本
baseline/       sysupgrade 保留清单与无线配置模板
docs/           文档（唯一索引：docs/README.md）
tools/          文档自检、密钥守卫、门面资源生成
third-party/    上游项目索引（本仓不 vendor 源码）
assets/         logo 与社交预览
```

## 安全与隐私

- 本仓库**不保存凭据**：文档里出现的是占位符，脚本从环境变量或设备侧真源读取（见 [docs/SECRETS.md](docs/SECRETS.md)）。
- 占位符不是真实值，拿它去登录一定失败。
- 脚本会**直接改路由器上的系统状态**（重启服务、重载防火墙、改 crontab、改 mihomo 策略组）。执行前先备份，先看 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)。
- 原始设备证据与内部台账仅保留在维护者的本地工作区，不进入公开仓库。

## 反馈

遇到问题、想要新功能，或者换了固件/订阅之后某个脚本失灵，都可以到 [Issues](https://github.com/MVennn/AX3000TOpenwrt/issues) 反馈。常见现象先查 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) —— 八个高频现象，每节都是能直接粘的命令；机制与红线见 [docs/PITFALLS.md](docs/PITFALLS.md)。

反馈时带上这些信息：

- 设备型号与固件版本
- 出问题的现象与复现步骤
- 相关日志：`/tmp/ShellCrash/guardian.log`、`/root/recover-last.log`
- 涉及的脚本路径

## 免责声明

本项目仅供学习与个人使用。

- 脚本会直接改路由器上的系统状态（重启服务、重载防火墙、改 crontab、改 mihomo 策略组）。执行前先备份。
- 这里的结论都是**在特定固件、特定订阅、特定时间点**下实测的，换固件、换订阅之后必须重新验证。
- 使用本仓库造成的任何后果由使用者自行承担。
- 本项目不提供任何翻墙、绕过地域限制或规避服务条款的能力说明。

「小米」「AX3000T」「MT7981」商标与标识的权利均归其权利人所有，本仓库与小米公司不存在任何隶属、合作、授权、认可或支持关系。OpenWrt、ShellCrash、mihomo 等第三方项目的权利归各自作者所有，见 [NOTICE](NOTICE)。

## 开源鸣谢

本仓库的脚本与规则建立在这些开源项目之上：

| 项目 | 用途 |
|---|---|
| [**OpenWrt**](https://openwrt.org/) | 固件本体；`/etc/rc.local`、`fw4`/`nft`、`uci`、busybox 工具链 |
| [**LuCI**](https://github.com/openwrt/luci) | 设备上的 Web 管理界面 —— 本仓把它当**应急入口** |
| [**ShellCrash**](https://github.com/nekoii/shellcrash) | 代理配置生成与运行时（`/etc/ShellCrash/`、`start.sh`、`task/task.sh`） |
| [**mihomo**](https://github.com/MetaCubeX/mihomo) | 代理内核（`CrashCore.raw`）、控制 API `:9999`、Redir 透明代理 `:7892` |
| [**MetaCubeX geosite / geoip**](https://github.com/MetaCubeX/meta-rules-dat) | 分流规则集来源 |
| [**art-design-pro**](https://github.com/Daymychen/art-design-pro) | 设计令牌来源（MIT）；本仓只用其中色值做对比度基准，非代码依赖 |
| [**nftables**](https://nftables.org/) | 防火墙规则（`quicguard` / `googlecn` / `googleroute` / `mixedport` 四张自建表） |

本仓不 vendor 任何上游源码 —— 逐个候选的判定与理由见 [third-party/README.md](third-party/README.md)。

## 许可证

本仓库以 [MIT License](LICENSE) 发布。第三方组件的版权与许可证声明见 [NOTICE](NOTICE)；凭据的存放位置与轮换建议见 [docs/SECRETS.md](docs/SECRETS.md)。
