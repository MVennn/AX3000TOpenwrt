# 更新日志

> **一句话**：本仓的版本号、每个版本改了什么、为什么升这一位 —— 按对象拆行，不做流水账。

版本命名遵循三段式进位：**有功能更新进次版本（+0.1.0），没有就进补丁版本（+0.0.1）**。
规则正本见 [docs/VERSIONING.md](docs/VERSIONING.md) §1 与 §2。
本仓是脚本与配置仓库，**没有构建产物、没有 `versionCode`** —— 版本号只在本文档头部维护；
发版 tag 与 Release 说明文件名都用它（格式见 [docs/release-notes/README.md](docs/release-notes/README.md)）。

---

## [未发布] — 2026-10-22 ~ 2026-10-23

### 仓库门面

- 新增 `.github/ISSUE_TEMPLATE/` —— 问题反馈（Bug）与功能建议两套表单，外加 `config.yml`：
  Bug 表单要求填设备与固件、脚本与调用方式、guardian / recover 日志；功能建议要求先写场景并确认范围
- 新增 `CONTRIBUTING.md` —— 提 Issue / PR 的入口、提交前自检命令与硬规矩索引
- 新增 `SECURITY.md` —— 私密报告渠道、支持版本、脚本会改的设备状态与安全边界

### 新增

- 新增 `guardian/dest-guard.sh` —— 按「站点 → 策略组」探测真实可达性（X / GitHub / B站 / YouTube / 通用），默认 dry-run 只写日志；启用后只在 B站候选白名单内切换、30 分钟冷却，不碰全局选择器
- 新增 `system/mixedport.nft` —— 把设备上已生效的 7890 收口 nft 表纳入版本库：
  `input priority -200` 拦 LAN → 7890（IPv4 按网段、IPv6 按 `br-lan` 入接口），
  路由器自身与透明代理不受影响；`system/rc.local` 开机会 `nft -f /etc/mixedport.nft`

### 调整

- 调整 `docs/DEPLOY.md` / `docs/TROUBLESHOOTING.md` —— 部署映射表补 `/etc/mixedport.nft`；
  悬空引用从两条减为一条（只剩 `/etc/router-health/reboot-verify.sh`）；
- 调整 `docs/DEPLOY.md` —— 仓库根文件数从「四个」更新为「六个」，补 `CONTRIBUTING.md` / `SECURITY.md`

### 文档规范对齐（2026-10-22，对齐兄弟仓 GoldSunEnhance 的文档骨架）

- 调整 `docs/release-notes/` —— 四份说明文件名去掉 `v` 前缀（`v0.1.0.md` → `0.1.0.md` 等，全部 `git mv`）；文件名 = `versionName`，`v` 前缀只属于发版 tag（tag 不动）
- 调整 `docs/release-notes/README.md` —— 头部补「一句话」引言块；文件名规则改为 `versionName` 并加一句「不带 `v`」
- 调整 `docs/README.md` —— 索引引言块与结尾提醒对齐基准仓；一句话定位压到一行读完；参考资料区补 `release-notes/` 目录行
- 调整 `docs/VERSIONING.md` —— §2 判断口诀改为「翻能力清单找答案」+ 补边界情况行；§3 标注说明文件名不带 `v`；§5 改为「不发版的时候：不要动版本号」并补「提前进位会吃掉下一个版本号」
- 调整 `docs/DOC-RULES.md` —— §1 补「文件命名：全大写 + 连字符」小节（含 release-notes 例外）；§4 补「点验有脚本兜底」

### 清理（2026-10-22 大扫除）

- 清理 `tools/__pycache__/` —— 4 个 `.pyc`（约 60 KB），纯再生缓存，`.gitignore` 已排除
- 清理 `.work/gh-refresh.log` —— 一次性 GitHub 设备授权日志（157 B），非证据、非游标
- 调整 `docs/VERSIONING.md` §4 —— 当前版本从 0.2.0 对齐到 0.4.0；注明 v0.4.0 的 Release 说明与 tag 尚未创建
- 调整 `docs/README.md` —— release-notes 索引把 v0.3.1 标为「最近一份」，注明 v0.4.0 尚未单独撰写
- 调整 `docs/release-notes/README.md` —— 补「反馈入口」规则：第一行加粗总结，第二行绝对地址 `issues/new/choose`，然后才是 `## 本版内容`
- 修复 `docs/PITFALLS.md` §⑤ —— `recover-gitbash.cmd` 实际已按 `%~dp0..\..` 推导仓库根，删掉「仍硬编码绝对路径」的过期说法
- 仓库体积 29M → 29M（`tools/__pycache__` 61 KB + `.work/gh-refresh.log` 157 B 已删；`.work/` 19M 与 `vault/` 8.8M 按红线保留）

## [0.4.0] — 2026-10-22

干净出口不再写死单个节点：HY2 池整池挂掉时自动退到台湾入口，消除 2.1 与 2.3
每 5 分钟互切的抖动。

### 新增

- 新增 `guardian/guardian.sh` 的 `resolve_clean_node` —— 每轮只解析一次干净出口：
  当前入口在 `CLEAN_CANDIDATES` 里且可达就保持不动，否则按
  `HY2 ×3 → 台湾-优化3 → 台湾-优化2-GPT` 取第一个可达的。2.1 / 2.3 / 3.6 共用这一个结果
- 新增 `guardian/guardian.sh` —— 全部候选不可达时 10 分钟内不再重复扫描（`CLEAN_RETRY`），
  避免整池挂掉时每 5 分钟空转 40 秒
- 调整 `guardian/guardian.sh` —— `CL_ALIVE_URL` 从 `https://github.com/` 改为
  `https://www.google.com/generate_204`：2026-10-22 起 GitHub 全族已拆到独立的
  `🔗 GitHub 出口` 组（`ShellcrashRules` 侧，url-test 按 GitHub 可达性选路），
  干净出口只服务 Google。探针口径必须跟着改 —— 否则守卫会按 GitHub 可达性
  把「Gemini 用着好、GitHub 不通」的节点踢掉，而那个节点对 Google 恰恰是对的

### 修复

- 修复 `guardian/guardian.sh` —— 2.1 的切换条件从「判 CN」扩到「判 CN **或** GitHub 不可达」，
  死节点在同一处换掉，不再依赖 2.3 事后补救
- 修复 `guardian/guardian.sh` —— 探测结论写 `/tmp/ShellCrash/.clean_verdict`，2.3 直接复用、
  不再二次探测：节点到 GitHub 是间歇性抖动的，连探两次会得出相反结论并误报 ALERT
  （2026-10-22 14:50 实测：同一节点 1 秒内一次可达一次不可达）
- 修复 `guardian/guardian.sh` —— 3.6 换节点前先做 GitHub 可达性检查，跳过死节点，
  不再把组切到死节点再回滚
- 调整 `guardian/guardian.sh` —— `CLEAN_NODE` 从写死的单节点改为候选列表；
  显式设置 `CLEAN_NODE` 环境变量仍可把它钉在候选首位

### 部署

- `scp guardian/guardian.sh root@10.0.0.1:/etc/ShellCrash/guardian.sh`，备份
  `guardian.sh.bak-cleandyn-20261022`

### 部署验证（2026-10-22）

- HY2 四个节点全部超时（连 `gstatic/generate_204` 都失败）时，干净出口稳定停在
  `🇹🇼 台湾-优化3`，guardian 连续多轮无 FIX / 无 ALERT
- 手动把组切到 `🇮🇳 印度-优化` 后，下一轮自动切回台湾入口；不再出现
  2.1→SG-HY2→2.3→台湾 的来回跳

---

## [0.3.2] — 2026-10-22

公共备用不再只当故障兜底：新增「大流量」通道，已知的大文件下载走公共池，
实测跑不满时自动切回机场。

### 部署

- 部署 `OpenwrtOpsToolkit/openwrt/bulk-guard.sh` → `/etc/ShellCrash/bulk-guard.sh`，cron `*/10 * * * *`
- 新建 `/etc/openwrt-ops/device.conf` —— `BULK_GROUP="📺 大流量"` / `BULK_PUBLIC="🆓 公共备用"` / `BULK_AIRPORT="♻️ 自动选择"`（文件不入库）
- 策略组与规则由 `ShellcrashRules` 侧下发；本仓只记录设备侧部署

### 文档

- 调整 `docs/DEPLOY.md` —— 部署映射表加入 `bulk-guard.sh` 与 `device.conf`；「启用与停用守护」补守卫的停用命令

### 部署验证（2026-10-22）

- `sh bulk-guard.sh --status` 能读到三个组名；`proof.ovh.net` 的 `/connections` 链路为
  `📺 大流量 → 🆓 公共备用 → 🆓 公共-01`
- 强制阈值触发：切到 `♻️ 自动选择` 并写入 1 小时冷却；冷却清零后自动切回公共池并首测 1356 KB/s

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
