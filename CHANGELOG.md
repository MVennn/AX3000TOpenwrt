# 更新日志

> **一句话**：本仓的版本号、每个版本改了什么、为什么升这一位 —— 按对象拆行，不做流水账。

版本命名遵循三段式进位：**有功能更新进次版本（+0.1.0），没有就进补丁版本（+0.0.1）**。
规则正本见 [docs/VERSIONING.md](docs/VERSIONING.md) §1 与 §2。
本仓是脚本与配置仓库，**没有构建产物、没有 `versionCode`** —— 版本号只在本文档头部维护；
发版 tag 与 Release 说明文件名都用它（格式见 [docs/release-notes/README.md](docs/release-notes/README.md)）。

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
