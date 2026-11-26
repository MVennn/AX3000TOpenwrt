# 文档规则

> **一句话**：docs/ 下的文档怎么分类、怎么互相引用、改动时连带改哪些 ——
> 本篇只管「怎么写、怎么保持一致」，不承载任何具体技术规则。
>
> **公共正本**：通用条款（七章骨架、分类与命名、单一正本、红线保护、链接纪律、
> 触发矩阵通用行、体量预算、孤儿零容忍）已上提为记忆正本
> **「跨仓共享约定：docs/DOC-RULES 公共段」**。
> 本文件只保留三类内容：本仓成员清单与正本映射表、本仓变更触发行、本仓红线事实；
> 通用条款按该正本执行，本文件不复述全文。

---

## 1. 分类与定位

docs/ 分四类（索引见 [README.md](README.md)）：

| 类别 | 收什么 | 现有成员 |
|---|---|---|
| 架构与基线 | 设备基线、当前状态 | HARDWARE、OPERATIONS |
| 功能专项 | 部署与回退 | [DEPLOY.md](DEPLOY.md)（部署映射与回退方式集中在它一篇里） |
| 流程与规范 | 文档规则、保留策略、排错、凭据、版本晋升、Release 说明格式 | DOC-RULES、MAINTENANCE、BACKUP-VAULT、TROUBLESHOOTING、PITFALLS、SECRETS、VERSIONING、release-notes/README |
| 参考资料 | Release 说明、仓库根文档、上游调研 | release-notes/、[CHANGELOG.md](../CHANGELOG.md)、[NOTICE](../NOTICE)、[LICENSE](../LICENSE)、[UPSTREAM.md](UPSTREAM.md)、[third-party/](../third-party/README.md) |

每篇文档开头必须有一个 **「一句话」引言块**（`> **一句话**：…`）：新文档没有它不算写完；
判据、例外与反例见公共正本 §2（`tools/check-docs.py` 只扫头部 10 行，仓库根 README 与 Release 说明免检）。

### 文件命名：全大写 + 连字符

docs/ 下的文档一律 `ALL-CAPS-WITH-HYPHENS.md`（如 `TROUBLESHOOTING.md`、
`BACKUP-VAULT.md`）—— 不用小写、不用下划线、不用中文文件名。
例外只有两个：`README.md`（各目录的索引）与 `docs/release-notes/`
下的版本说明（文件名 = `versionName`，如 `0.1.0.md`，**不带 `v`** ——
`v` 前缀只属于发版 tag，见 [VERSIONING.md](VERSIONING.md) §3）。
改名一律 `git mv`，并同步全部引用方（见 §4）。

---

## 2. 单一正本原则

**每条规则只在一篇文档里定义；其余位置只允许一句话概述 + 指向正本的链接。**
两处都写全文，迟早各改各的。

权威正本映射表：

| 规则 | 正本 |
|---|---|
| 硬件 / 固件 / 网络拓扑基线 | [HARDWARE.md](HARDWARE.md) |
| 路由器当前配置值、访问入口、自检命令 | [OPERATIONS.md](OPERATIONS.md) |
| 路由器上需要的包（缺了哪个脚本会失败） | [OPERATIONS.md](OPERATIONS.md) §三 |
| 保留策略与清理流程（备份区命名 / 修剪阈值 / 改完即删） | [MAINTENANCE.md](MAINTENANCE.md) |
| 排障步骤 | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| 凭据存放位置与轮换建议 | [SECRETS.md](SECRETS.md) |
| Release 说明格式（动词 / 一行一条 / 覆盖率红线 / 固定尾巴） | [release-notes/README.md](release-notes/README.md) |
| 文件清单（本地路径 → 路由器目标路径 → 被谁调用 → 回退方式） | [DEPLOY.md](DEPLOY.md) |
| 仓库范围与职责划分（管哪几件事 / 不管什么）、启用与停用守护 | [DEPLOY.md](DEPLOY.md) |
| 变更台账（按对象拆行） | 仓库根 [CHANGELOG.md](../CHANGELOG.md) |
| **版本晋升规则**（三段式进位 / 有没有功能更新怎么判） | [VERSIONING.md](VERSIONING.md) §1–§2 |
| **交付 / 发版规则**（版本号在哪维护 / 什么时候不动版本号 / 打 tag） | [VERSIONING.md](VERSIONING.md) §3、§5 + [release-notes/README.md](release-notes/README.md) |
| 许可证 | 仓库根 [LICENSE](../LICENSE)（MIT 全文） |
| 文档本身的写法规则 | [DOC-RULES.md](DOC-RULES.md)（本篇） |

### 禁止重复清单（勿重蹈）

1. **状态速查 ↔ 硬件基线**：型号 / 内核 / 内存这类**设备事实**写在
   [HARDWARE.md](HARDWARE.md)（带来源与时点）；速查只写**当前配置值**，
   并且**一句话 + 链接**指回基线，不复述。
2. **排障步骤 ↔ 已知坑**：现象 → 步骤 → 解法的**完整流程**只写在
   [TROUBLESHOOTING.md](TROUBLESHOOTING.md)；机制与红线只写在
   [PITFALLS.md](PITFALLS.md)，两边互链不复述。
3. **凭据值 ↔ 任何其它文档**：本仓不保存凭据值；[SECRETS.md](SECRETS.md)
   只写**位置与读取方式**，不抄值。
4. **CHANGELOG ↔ Release 说明**：CHANGELOG 是**开发者记录**（症状 / 根因 / 改法）；
   Release 说明是**给使用者看的清单**。两者受众不同，不能一份两用。
5. **VERSIONING ↔ CHANGELOG 头部**：版本**号本身**（当前是哪个版本）只在
   [CHANGELOG.md](../CHANGELOG.md) 的版本标题里；**进位规则**只在
   [VERSIONING.md](VERSIONING.md) §1–§2。两处都写规则，迟早各改各的。

---

## 3. 红线内容保护

以下内容在文档合并、压缩、改写时**必须逐字保留，一个不删**：

1. **路径与接口名** —— 路由器上的目标路径（`/etc/ShellCrash/guardian.sh`、
   `/etc/rc.local`、nft 表名 `inet quicguard` / `inet mixedport`…）、
   端口（`7890` / `7892` / `9999` / `1053`）、cron 行、配置键名。
   这些是**事实**，不是描述；写错一个字符，脚本就找不到东西。
2. **实测数字与它们的时点** —— 内存 / 闪存占用、节点延迟、规则条数。
   **数字后面必须带时点**（「2026-10-20 15:00 审计时」），
   因为同一项在不同时点是不同的值。
3. **脚本的 shebang 与调用方式** —— `guardian/guardian.sh` **首行即 `#!/bin/sh`**
   （历史文档曾误记为「第 9 行 / 前 8 行空行」，2026-11-04 用 git 与设备双端实物核对后订正）。
   `scp` 落地可能丢执行位，cron 与文档统一用 `sh` / `/bin/ash` 显式调用。
4. **占位符的写法** —— `<YOUR-SSID>`、`<YOUR-IPV6-PD>`、`<REDACTED-...>`
   是脱敏标记，不是待填值；不要为了「让示例能跑」把真实值填回文档。

---

## 4. 链接纪律

通用条文（相对链接 + 锚点、锚点必须真实存在、改动后双向点验出链与入链、
待补文档不留死链）见公共正本 §4。本仓补充：改完跑 `python tools/check-docs.py`，
一次查全链接目标、锚点、引言块与孤儿（见 §7），比人工 grep 可靠。

---

## 5. 变更触发矩阵

改了什么，就必须连带改什么：

| 变更 | 必须同步 |
|---|---|
| **修一个缺陷**（行为变化 / 判据修正 / 安全加固） | 对应正本补一条 **现象 → 根因 → 怎么避**：[PITFALLS.md](PITFALLS.md)；CHANGELOG 只是变更记录，**不算补文档** |
| 改脚本（`system/` `guardian/` `recovery/`） | [DEPLOY.md](DEPLOY.md)（目标路径 / 被谁调用 / 回退方式）、[OPERATIONS.md](OPERATIONS.md) 的相关值、[TROUBLESHOOTING.md](TROUBLESHOOTING.md) 的对应节 |
| 路由器当前配置变了 | [OPERATIONS.md](OPERATIONS.md)（**只改正文里的当前值**）；[HARDWARE.md](HARDWARE.md)（设备事实变了才动） |
| 设备事实变了（换固件 / 换硬件） | [HARDWARE.md](HARDWARE.md)（带新时点）；[OPERATIONS.md](OPERATIONS.md) 同步 |
| 新增 / 删除 / 改名文件 | [DEPLOY.md](DEPLOY.md) 的目录职责与部署映射表 |
| 新增 / 删除 / 改名文档 | [README.md](README.md) 索引（见 §7） |
| 改了保留策略 / 清理规则 | [MAINTENANCE.md](MAINTENANCE.md) |
| 改了凭据的存放位置或新增了凭据 | [SECRETS.md](SECRETS.md)（位置清单）；`.gitignore` 的排除项 |
| 改了版本晋升 / 发版规则 | [VERSIONING.md](VERSIONING.md)；仓库根 [CHANGELOG.md](../CHANGELOG.md)（版本号本身） |
| 改了许可证 | 仓库根 [LICENSE](../LICENSE)、[NOTICE](../NOTICE)、[README.md](../README.md) 的许可证段 |
| 发版 | 仓库根 [CHANGELOG.md](../CHANGELOG.md)、[docs/release-notes/](release-notes/) 下对应版本说明（格式正本：[release-notes/README.md](release-notes/README.md)；版本号进位规则：[VERSIONING.md](VERSIONING.md)） |
| 内部重构 / 底层修复 / 死代码 | CHANGELOG 与 Release 说明里**必须按对象单列一行**（算「修复」，不许打包成「代码整理」） |

---

## 6. 体量预算与样例时效

通用判定（单篇 ≤ 800 行拆分法、样例可过时 / 当前值必须同步、阶段性报告追加勘误）见公共正本 §6。
本仓补充：本仓当前没有 `docs/archive/` 目录，一次性报告暂时直接进 docs/，结论过时在文末追加勘误节。

---

## 7. 索引维护与孤儿零容忍

通用条文（唯一索引、孤儿零容忍、仓库根 README 与 docs/README 两层分工）见公共正本 §7。
本仓补充：[README.md](README.md) 是 docs/ 的唯一索引；改完用 `python tools/check-docs.py` 复核孤儿与断链。
