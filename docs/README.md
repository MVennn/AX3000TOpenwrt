# docs/ 索引

> **一句话**：这里只有索引与定位，不放正文 —— 每篇文档一句话说明「它管什么」，
> 规则本身按 [DOC-RULES.md](DOC-RULES.md) 的单一正本原则只在对应文档里定义。

文档分四类。每篇开头都有一个「一句话」引言块，先看它再决定要不要往下读。

> 本仓是脱敏后的公开参考实现：原始设备证据、内部进度台账与审计报告不随公开仓发布。

---

## 一、架构与基线

| 文档 | 一句话定位 |
|---|---|
| [HARDWARE.md](HARDWARE.md) | 硬件与固件基线：型号 / SoC / 内核 / 内存 / 闪存 / 网络拓扑 / SQM / 拥塞控制 / 无线，每条标注来源与时点 |
| [OPERATIONS.md](OPERATIONS.md) | **路由器状态速查**：当前配置值、访问入口、路由器上需要的包、自检命令、已知残留风险（长期维护件，改动即需刷新） |

## 二、功能专项

| 文档 | 一句话定位 |
|---|---|
| [DEPLOY.md](DEPLOY.md) | 部署映射（**正本**）：本仓管哪几件事、本地路径 → 路由器目标路径 → 被谁调用 → 回退方式、启用与停用守护，外加目录职责；脚本自身的行为写在脚本头部注释，运行期状态写在 [OPERATIONS.md](OPERATIONS.md) |

## 三、流程与规范

| 文档 | 一句话定位 |
|---|---|
| [DOC-RULES.md](DOC-RULES.md) | **文档规则正本**：分类与定位、单一正本映射表、禁止重复清单、链接纪律、变更触发矩阵、体量预算、索引维护 |
| [MAINTENANCE.md](MAINTENANCE.md) | 保留策略与清理流程：备份区命名约定、修剪阈值、「改完即删」、不做什么清单 |
| [BACKUP-VAULT.md](BACKUP-VAULT.md) | 私有金库 `vault/`：不可再生的回退材料（私钥备份、整机快照、主题恢复包）放哪、怎么取回、为什么绝不入库 |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | 排障手册：八个高频现象，按「现象 → 排查步骤 → 原因 / 解法」组织，每节给可执行命令 |
| [PITFALLS.md](PITFALLS.md) | 踩坑总汇（**正本**）：这类设备的机制级坑与红线（tmpfs OOM / `/var` 软链 / 静默回退 / overlay 余量 / Windows 路径依赖） |
| [SECRETS.md](SECRETS.md) | 凭据的**存放位置**清单、读取方式与轮换建议（不写明文值） |
| [VERSIONING.md](VERSIONING.md) | **版本晋升规则正本**：三段式进位（有功能更新 +0.1.0 / 没有 +0.0.1）、版本号在哪维护、什么时候不动版本号；**发版与交付规则并入本篇**，不另立 `RELEASE.md` |
| [release-notes/README.md](release-notes/README.md) | **Release 说明格式正本**：四动词、一行一条、按对象拆行、覆盖率红线、固定尾巴 |

## 四、参考资料

| 位置 | 一句话定位 |
|---|---|
| [release-notes/v0.1.0.md](release-notes/v0.1.0.md) | 首版 Release 说明（面向使用者：你现在能拿到什么） |
| 仓库根 [CHANGELOG.md](../CHANGELOG.md) | 开发者记录：按对象拆行的变更清单（**版本号本身**在这里维护，规则见 [VERSIONING.md](VERSIONING.md)） |
| 仓库根 [NOTICE](../NOTICE) | 第三方声明：引用 / 派生的开源项目、来源、许可证、为何使用 |
| 仓库根 [LICENSE](../LICENSE) | 许可证全文（**MIT**）—— 与 [NOTICE](../NOTICE) 的第三方声明配套 |
| [UPSTREAM.md](UPSTREAM.md) | **上游来源与调研正本**：引用了哪些上游、为什么引用/不引用、随仓分发了哪些文件 |
| 仓库根 [third-party/](../third-party/README.md) | **随仓分发的上游文件**：每个子目录一份 `UPSTREAM.md`（来源 URL / 钉住的 commit / 许可 / 怎么用 / 怎么更新） |

---

## 版本 / 发版规则的正本归属（已收口）

本节记录原「待补」表的最终去向，避免后人再去找一篇不存在的 `RELEASE.md`。

| 文档 | 状态 | 说明 |
|---|---|---|
| `docs/VERSIONING.md` | **已建** —— 见上表 | 版本三段式进位规则 |
| `docs/RELEASE.md` | **不单独建** | 发版与交付规则**并入** [VERSIONING.md](VERSIONING.md)（版本号进位 / 版本号在哪维护 / 什么时候不动版本号 / 打 tag）+ [release-notes/README.md](release-notes/README.md)（Release 说明格式）—— 发版规则本就是版本晋升的一部分，另立一篇只会让两处口径分叉 |

---

> 新增 / 删除文档后**必须同步更新本索引**（规则见 [DOC-RULES.md](DOC-RULES.md)）；
> 新文档至少要被一处既有文档引用，不允许孤儿。
