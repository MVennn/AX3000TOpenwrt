# 更新日志

> **一句话**：本仓的版本号、每个版本改了什么、为什么升这一位 —— 按对象拆行，不做流水账。

版本命名遵循三段式进位：**有功能更新进次版本（+0.1.0），没有就进补丁版本（+0.0.1）**。
规则正本见 [docs/VERSIONING.md](docs/VERSIONING.md) §1 与 §2。
本仓是脚本与配置仓库，**没有构建产物、没有 `versionCode`** —— 版本号只在本文档头部维护；
发版 tag 与 Release 说明文件名都用它（格式见 [docs/release-notes/README.md](docs/release-notes/README.md)）。

---

## [0.3.1] — 2026-10-22

补掉干净出口候选里的两个坑：印度节点已判 CN、香港 HY2 不在组内。

### 修复

- 修复 `guardian/guardian.sh` —— `is_bad_node` 把 `*印度*` 计入「判 CN」：印度池整池已 `cc=CN`，手动选中后守护进程要能纠正
- 修复 `guardian/guardian.sh` —— `CL_CANDIDATES` / `CL_ALIVE_CANDIDATES` 去掉印度与香港 HY2：印度会与 2.1「锁到干净节点」互相切换（每 5 分钟一次），香港 HY2 被 exclude-filter 挡住、`put` 必然失败

### 部署验证（2026-10-22）

- 备份：`/etc/ShellCrash/guardian.sh.bak-subsync-20261022`
- 手动跑一轮 guardian：无 FIX/ALERT，干净出口仍停在 `🇸🇬 新加坡SG-HY2`
- `cc='SG'`；`gemini.google.com/app` 200 / 0.29s

---

## [0.3.0] — 2026-10-22

干净出口从 vmess 池（整池被判 `cc=CN`）切到 Hysteria2 池（`cc=SG`），Gemini 恢复。

### 新增

- 新增 `guardian/guardian.sh` —— `is_bad_node` 对 `*-HY2*` 开例外：Hysteria2 池是当前唯一 `cc=SG` 的干净出口，不再当成「Google 判 CN」的坏节点

### 修复

- 修复 `guardian/guardian.sh` —— `CLEAN_NODE` 默认值从 `🇮🇳 印度-优化` 改为 `🇸🇬 新加坡SG-HY2`
- 修复 `guardian/guardian.sh` —— `CL_CANDIDATES` / `CL_ALIVE_CANDIDATES` 改为 HY2 四个优先，台湾-优化3 与印度兜底
- 修复 `guardian/guardian.sh` —— §6 的 cc 探针从「必须等于 IN」改为「只有 CN / HK 才 ALERT」，`cc=SG` 不再误报

### 排查结论（2026-10-22）

- vmess 池 5 个候选（印度×3、新加坡-优化3、台湾-优化3）全部 `var cc='CN'` / `pref=hkredirect`；手机同款「新加坡-优化3」在路由器上同样被判 CN
- HY2 池 4 个节点（`*.mjhy2.com`）全部 `cc='SG'`，新加坡延迟 44ms（vmess 同地区 114ms、印度 224ms）
- 验证：`gemini.google.com/app` 200 / 0.34s；`hotupdate` 后 `hy2=4` 且选择仍是 SG-HY2

### 部署验证（2026-10-22）

- 备份：`/etc/ShellCrash/guardian.sh.bak-hy2-20261022`、`/root/backup/guardian.sh.pre-hy2-20261022`
- 设备版与仓库版字节一致，`sh -n` 通过

---

## [0.2.0] — 2026-10-22

与设备上实际运行的版本对齐。设备侧在 2026-10-21 公开化之后继续演进，
仓库仍停留在当时的快照；本次把设备侧的新逻辑收回仓库，并补上只存在于设备的依赖文件。

### 新增

- 新增 `guardian/guardian.sh` §2.3 `CLEAN_EXIT_ALIVE` —— 干净出口当前入口的 GitHub 拨号失败时，按「印度优先」自动切到第一个存活入口并同步 `🤖 AI网页`；候选全挂时只告警、不乱切

### 修复

- 修复 `guardian/guardian.sh` —— 与设备版对齐：补上 `memgate` 内存闸门（OOM 拉起前先看 `MemAvailable`）、`is_bad_node` 的台湾-优化3 / 台湾-优化2-GPT 例外、`CL_CANDIDATES` 改为台湾优先；同时保留公开版的参数化与占位符
- 新增 `guardian/memgate.sh` —— OOM 闸门源文件（此前只在设备上，仓库缺失）
- 新增 `guardian/memgate.conf` —— 闸门阈值（`MEM_GATE_KB=32768` / `MEMGATE_FORCE_AFTER=5`）

### 文档

- 调整 `docs/DEPLOY.md` —— 补 `memgate.sh` / `memgate.conf` 的部署映射与回退方式

---

## [0.1.0] — 2026-10-21

首次公开版。仓库从私有运维仓整理为可独立阅读、可复用的参考实现。

### 公开化

- 调整 仓库范围 —— 移除设备原始证据、内部进度台账、审计报告、历史归档与拆仓分析；公开树只保留脚本、文档、配置模板与门面资源
- 修复 隐私 —— SSID、IPv6 PD 前缀、节点域名、出口 IP、本机路径全部改为占位符或环境变量
- 修复 凭据 —— 仓库不保存任何凭据；root 口令、mihomo secret、节点 UUID 与订阅 token 均从环境变量或设备侧真源读取
- 新增 密钥守卫 —— `tools/check-secrets.py` 扫描订阅链接、节点 URI、私钥块与 shadow 哈希，CI 强制执行
- 调整 忽略规则 —— `.gitignore` 排除 `vault/`、`.work/`、私钥、订阅原文与本机口令文件

### 脚本

- 调整 `guardian/guardian.sh` —— 策略组名、节点名、控制 API 地址改为环境变量可覆盖，默认值保留为示例
- 调整 `recovery/recover-now.sh` —— 保持原有恢复流程；文档中的路径改为按仓库位置推导
- 调整 `recovery/local-tools/` —— Windows 触发器不再硬编码本机绝对路径；`askpass.sh` 改为从环境变量 / 忽略文件读取口令，并随仓分发
- 调整 `system/rc.local` —— 自建 nft 表加载逻辑不变；注释中的设备专属值改为通用描述

### 文档

- 调整 根 README —— 面向使用者的门面：这是什么 / 环境要求 / 使用 / 目录 / 安全与隐私 / 反馈 / 免责声明 / 鸣谢 / 许可证
- 调整 `docs/OPERATIONS.md` —— 状态速查改为参考部署示例，移除机场状态、内部备份路径与历史勘误
- 调整 `docs/SECRETS.md` —— 重写为公开版：只写读取方式、位置与轮换顺序
- 调整 `docs/HARDWARE.md` —— 保留实测基线，设备标识改为占位符，移除内部审计链接
- 调整 `docs/DEPLOY.md` / `docs/MAINTENANCE.md` / `docs/BACKUP-VAULT.md` / `docs/PITFALLS.md` / `docs/TROUBLESHOOTING.md` / `docs/UPSTREAM.md` —— 移除内部台账与证据引用，统一「参考实现」口径
- 调整 `docs/DOC-RULES.md` / `docs/README.md` —— 索引与规则按公开树重建
- 调整 `NOTICE` / `third-party/README.md` —— 移除证据库与私有仓表述

### CI

- 调整 CI —— 保留 vault 守卫、Shell 语法与文档自检，新增密钥扫描
