# third-party —— 上游开源项目索引（本仓不 vendor）

> **一句话**：本目录是「本仓引用了哪些上游开源项目」的索引 —— 本仓**一个上游都没有 vendor**，
> 这里写清每个候选**为什么没 vendor**，以及替代方案是什么。

本目录的用途是：将来若有上游需要 vendor，就原样放进这里，保证「参照物不会漂走」。

**本仓的结论是：没有东西够格进这个目录。** 本仓的全部内容都是**参考设备的运维配置与脚本**
（UCI 配置片段、nft 规则、守护脚本、验收脚本与文档），
不包含任何从上游复制的源码。逐个候选的判断依据见下表。

## 候选与判定

| 候选 | 上游 URL | stars | GitHub size (KB) | license | 默认分支 | 最新 commit SHA | 判定 | 理由 |
|---|---|---|---|---|---|---|---|---|
| OpenWrt | https://github.com/openwrt/openwrt | 28835 | **316,997** | **NOASSERTION** | `main` | `0d245fdaeae5c890c8aa997fadcf9287a707558f` | **不 vendor** | 体积超门槛约 60 倍；且 GitHub 侧 license 字段是 `NOASSERTION`（"Other"）—— 许可证在仓库里以 `LICENSES/` 目录逐包声明，不是单一文件，**不适合整仓再分发**。本仓只**调用**它的接口 |
| LuCI | https://github.com/openwrt/luci | 7919 | **596,030** | Apache-2.0 | `master` | `0a601b651af34ae4a83dd89f417dccdc474ec348` | **不 vendor** | license 允许再分发，但体积超门槛约 116 倍。本仓只把 LuCI 当**设备上的应急入口**，不碰它的源码 |

> 上表数据取自 GitHub REST API（2026-10-20 查询）。`size` 字段是 GitHub 统计的**整个 git 仓库**
> 体积（含历史），用作门槛判定的保守口径。

## 判定标准（三条都满足才 vendor）

1. **与本仓有代码级关系** —— 本仓派生自它 / 按它的规范写 / 直接用它的协议定义。
2. **体积 < 5 MB**。
3. **license 允许再分发** —— GPL-3.0 / MIT / Apache-2.0 可以；**NOASSERTION 或不明确的不要 vendor**。

OpenWrt 与 LuCI **两条都不满足**（一条体积超，一条 license 不明或体积超）。

## 替代方案：写清楚去哪核对

不 vendor 并不等于「查不到」。本仓把「脚本依赖哪些上游行为、上游源码在哪」逐条写进了
**[docs/UPSTREAM.md](../docs/UPSTREAM.md)** —— 每条都给出上游源码路径与可直接取原文的 URL：

| 上游行为 | 正本位置 |
|---|---|
| `rc.local` 的执行时机（由 S95 的 `done` 调用，早于 S99） | `package/base-files/files/etc/init.d/done` |
| `/etc/init.d/` 的约定（`rc.common` / `START=` / `/etc/rc.d/S??` / procd） | `package/base-files/files/etc/rc.common`、`package/system/procd/files/procd.sh` |
| LuCI 的 CGI 约定（`/www/cgi-bin/luci`、环境变量 + stdin、CSRF token） | `modules/luci-base/htdocs/cgi-bin/luci`、`modules/luci-base/ucode/dispatcher.uc` |
| ubus 会话机制（`session` ubus 对象、`ubus_rpc_session` 参数） | rpcd `session.c`、ubus `ubusd_acl.c` |

固件版本基线（OpenWrt 25.12.6 / LuCI `openwrt-25.12` 分支 / rpcd / ubus / firewall4 各自钉住的 commit）
见 [docs/UPSTREAM.md](../docs/UPSTREAM.md) §0 与 [docs/HARDWARE.md](../docs/HARDWARE.md) §2。

## 约定（留给将来）

若将来某个上游同时满足上面三条，按这个格式 vendor：

```
third-party/
├─ README.md                      ← 总索引：名称 / 上游 URL / 用途 / license / vendored 的 commit SHA / 为什么 vendor
└─ <project-name>/
   ├─ UPSTREAM.md                 ← 单项目来源凭证：上游 URL、clone 时间、commit SHA、license、怎么更新、本仓怎么用它
   └─ <vendored 内容>
```

流程：`git clone --depth 1` → 记 commit SHA → 删掉 `.git` → 复制入仓；
保留上游 LICENSE / NOTICE / 版权头；**不改上游代码一个字节**；
落库前逐文件 sha256 与 clone 比对。
