# 更新日志

> **一句话**：本仓的版本号、每个版本改了什么、为什么升这一位 —— 按对象拆行，不做流水账。

版本命名遵循三段式进位：**有功能更新进次版本（+0.1.0），没有就进补丁版本（+0.0.1）**。
规则正本见 [docs/VERSIONING.md](docs/VERSIONING.md) §1 与 §2。
本仓是脚本与配置仓库，**没有构建产物、没有 `versionCode`** —— 版本号只在本文档头部维护；
发版 tag 与 Release 说明文件名都用它（格式见 [docs/release-notes/README.md](docs/release-notes/README.md)）。

---

## [未发布]

### 设备内核升级到 mihomo v1.19.33（2026-11-10）

- 设备维护者在维护窗口用一份纯 LF 预置脚本（设备 `/tmp/` 留档；本仓 `.work/` 属 gitignore 的内部工作区，不随公开仓发布）执行：
  `curl` 拉作者 `update` 分支 `bin/meta/clash-linux-arm64.upx` → 15,007,192 B 与
  `-v` 双校验 → 备份 `/root/CrashCore.upx.bak-v1.19.28-20261110`（10,283,068 B）→
  同目录 `cp` + `sync` + `mv -f` 原子替换 `CrashCore.upx` → `sed` 同步 `core_v=v1.19.33`
  → `start.sh restart`（`stop` 里 `killall CrashCore`，`start` 重建 `/tmp/ShellCrash/CrashCore` 软链）。
- 为什么：ShellCrash 1.9.5beta3 的 upx 通道与三档菜单早已在位，`update/bin/version`
  的 `meta_v` 已是 `v1.19.33`，设备二进制却停在 10/20 装入的 `v1.19.28`；
  `custcorelink` 钉的就是该 `.upx` URL，升级后与 `core_v` 一致，自动更新不会再拉回旧版。
- 验证（11:09 设备只读复验）：`CrashCore.upx -v` = `Mihomo Meta v1.19.33 linux arm64
  with go1.27.3`、15,007,192 B；`core_v=v1.19.33`；运行态 `/version` =
  `{"meta":true,"version":"v1.19.33"}`；核心进程数 1、`/tmp` 下载临时件与 `.tmp` 均已清理；
  31 个分组 / `RULE-SET,cn` 未变、探针 cron 在、`stats/2026-11-10.tsv` 3,265 B 仍在写，
  `uptime` 未重启整机。
- 连带：预置脚本 7/7 验收段把 `sleep 3` 单次 `curl` 改为最多 20 秒轮询且判据必须含
  `v1.19.33`（`start.sh` 的 `start_l` 分支是 `afstart &` 后台拉起，controller 晚几秒才监听，
  首次执行时 `/version` 空响应被 `|| true` 吞掉留了一行空白）；
  [docs/OPERATIONS.md](docs/OPERATIONS.md) §3 当前值、[docs/HARDWARE.md](docs/HARDWARE.md) §3
  时点指引同步，本地与设备 `/tmp/` 留档脚本双端 md5 一致（`b099bef4d268cb564257207333a2a260`）。
- 版本判断：设备二进制与配置更新，非本仓脚本功能变更，不发版、不动版本号，按
  [docs/VERSIONING.md](docs/VERSIONING.md) §5 记在 `[未发布]` 段。

### 日志降噪：keepaudit 幂等告警与派生件排除（2026-11-10）

- `system/router-health/health-snapshot.sh` 的 keepaudit 段：巡检
  `/etc/ShellCrash` 顶层时先用 `case` 跳过派生件（`CrashCore.raw|gz|upx`、
  `meta-backup`、`GeoSite.dat` / `GeoIP.dat`、`ui`、隐藏 `.*`、`*.bak*`、
  `*.disabled` / `*.old` / `*.tmp` / `*.swp`），漏项集合存
  `/tmp/.keepaudit.state`，只在**集合相对上次发生变化**时才
  `logger -t keepaudit`；24 字段快照主体字节不变。
- 为什么：原口径把 42 个漏项里的 37 个派生件全算进去，每 30 分钟重报一条
  1,000+ B 超长清单，是 `cron.err` 降噪后剩余写入的大头；漏项集合稳定时
  反复告警属于「报当前值」而非「报变化」。
- 验证：稳态连跑两次零新增；造 `zz-tune-probe.sh` 立刻可见、删掉后集合恢复
  也可见；隔夜 9 小时真实 cron 零新增，`/tmp/.keepaudit.state` 存活且稳定。
- 版本判断：属缺陷修复 / 内部行为修正，不发版、不动版本号，按
  [docs/VERSIONING.md](docs/VERSIONING.md) §5 记在 `[未发布]` 段。

### 设备日志配置恢复：cronloglevel 漂移回正（2026-11-10）

- 设备 `/etc/config/system` 的 `cronloglevel` 实测漂到 `5`（记忆正本与基线均为
  `9`），`conloglevel` 也由 `8` 变 `5`；经 `uci set … cronloglevel=9 &&`
  `uci commit system` 与 `/etc/init.d/cron restart` 恢复，`crond -l 9` 实证。改前备份
  `/root/system.config.bak-router-log-tune-20261109`。`log_size=512` / `log_file=/overlay/log/messages` 未动。
- 为什么：level 5 让 crond 自身 stderr（`wakeup dt=10` 等）每 10 秒一条灌进
  syslog，占改前日志 97.55% 字节，把 512 KiB 环形缓冲压到只覆盖 3.8 小时；
  恢复 9 后**业务告警不受影响**（45 行有效日志全走显式 `logger -t`）。
- 验证：隔夜 9 小时 11-10 当天新增 `cron.err` = 0，`/overlay/log/messages`
  增速 891 B/h（改前 138,063 B/h，降幅 99.4%），当日 00:00–09:00 健康快照
  每半小时一条、24 字段完整。
- 版本判断：设备当前配置回正，非使用者可感知的新能力，不进位；
  [docs/OPERATIONS.md](docs/OPERATIONS.md) §3 同步当前值。

### 守护补回流量归因采样 cron 行（2026-11-06）

- `guardian/guardian.sh` 在原有 legacy 看门狗 cron 自愈块之后、`exit 0` 之前新增一段：
  `/etc/ShellCrash/traffic-stats.sh` 存在、而 `/etc/crontabs/root` 里没有它的条目时，追加
  `* * * * * /bin/ash /etc/ShellCrash/traffic-stats.sh #流量归因:按策略组+域名每分钟采样`，
  再 `crontab /etc/crontabs/root` 重载，日志写 `FIX: restored traffic-stats cron line`。
  脚本文件本身不存在时**不补**，避免每 5 分钟刷一条失败记录
- 为什么：**2026-11-02 10:14 起这一行丢失，流量归因采集中断 4 天**（stats 目录没有新文件，
  脚本手动跑正常），直到 2026-11-06 人工才发现。guardian 本来就承担 legacy 看门狗行的
  cron 自愈，这次把流量采集纳入同一套
- 验证：`grep traffic-stats /etc/crontabs/root` 应看到该行；删掉这一行后手动跑一次
  `sh /etc/ShellCrash/guardian.sh`，`/tmp/ShellCrash/guardian.log` 出现
  `FIX: restored traffic-stats cron line`，再 `grep` 确认 cron 行已回来
- 版本判断：新增一个守护项（使用者可感知的新能力）→ 属**功能更新**，发版时进次版本
  `0.6.0` → `0.7.0`；本次不发版、不动 tag，按 [docs/VERSIONING.md](docs/VERSIONING.md) §5 先记在
  `[未发布]` 段

## [0.6.0] — 2026-11-06

### 门禁脚本 GBK 控制台自毁修复（2026-11-04）

- 修 `tools/check-docs.py`、`tools/check-secrets.py`、`tools/check-vault-not-staged.py`、`tools/make_social_preview.py` 的结论行 `✓` / `✗` / `⚠` → ASCII `[OK]` / `[FAIL]` / `[!]`：Windows 中文控制台
  （cp936）下这些字符不在 GBK 码表，`print` 抛 `UnicodeEncodeError`，脚本即便检查全过也以
  **退出码 1** 结束；`python -I` 会忽略 `PYTHONIOENCODING` / `PYTHONUTF8`，环境变量救不回来，
  只能改脚本本身。
- 入口补兜底 `if hasattr(sys.stdout, "reconfigure"): sys.stdout.reconfigure(errors="replace")`：
  以后任何非 GBK 字符降级成 `?`，不再让门禁误判失败。
- 验证：`python -I` 逐个跑上述脚本 → `[OK] …`、退出码 0、无 traceback；反证：把 `✓` 改回原样，
  同一命令退出码 1 并抛 `UnicodeEncodeError`。

### 自建 nft 表与生成器入库 + 刷机保留清单补齐（2026-11-04）

- 入库 `system/quicguard.nft`（设备生成快照）与 `system/quicguard-sync.sh`（生成器正本）、
  `system/googlecn.nft`、`system/googleroute.nft`。此前只有 `system/mixedport.nft` 在仓，
  刷机或误删后其余三表无法复原
- `baseline/sysupgrade.conf` 补保留项：四张自建 nft 表 + `quicguard-sync.sh`、
  `/etc/router-health/`、`/etc/crontabs/root`（ShellCrash `set_cron.sh` 会整表覆盖 crontab）
- 文档订正：README / DEPLOY / DOC-RULES 三处「`guardian.sh` shebang 在第 9 行」
  与实物不符（首行即 `#!/bin/sh`，git 与设备双端核对）；DEPLOY 部署映射表补四行；
  TROUBLESHOOTING「表缺失」行改为已入库，并补整表清空事故的排查与恢复

### P3 清理（2026-11-04 审查遗留项）

- `recovery/archive/verify-fix.sh`：补回 cron 的路径笔误（`/bin/ShellCrash/...` →
  `/etc/ShellCrash/task/task.sh 106`）
- `recovery/local-tools/askpass.sh` 注释澄清跨仓调用方（本仓 `fix-router.sh` +
  ClientTriage `tools/verify-gemini.sh`，后者不在本仓）
- `system/router-health/health-snapshot.sh` 正本入库（此前只在设备上），DEPLOY 映射表补行；
  TROUBLESHOOTING 的 cron 参考注明 health-snapshot（本仓）与 daily-ai-check（ShellcrashRules 仓）的出处

### 2026-11-04 事故记录：crontab 被整表清空

- 现象：重启后 `/etc/crontabs/root` 为 0 字节，守护/看门狗/全部定时任务停摆
- 根因指向：ShellCrash `libs/set_cron.sh` 的 `cronadd()` 用 `cat > /etc/crontabs/root`
  整表覆盖，无任务时即清空；guardian 的「cron lifeline」只补 `start_legacy_wd.sh` 一行，
  且 guardian 自身只能由 cron 拉起（死锁）。重启后 syslog 在 tmpfs，无法回看当时调用栈
- 处置：从 `/etc/crontabs/root.bak-destguard-20261023-*`（11 行、md5 `9185d8ab`）还原并 md5 复验
- 待定：`post-sc-update` 增加 ensure_cron（控制面变更，待正式拍板）

## [0.5.0] — 2026-11-01

### 守卫脚本 bug 奇偶同步（2026-11-01）

- `tools/check-secrets.py` 对齐 ClientTriage `c3a3952` 已修的三类漏报 ——
  混行豁免改逐命中段（只免注释/字符串内的命中段，不再整行放行）、
  `re.search` 改 `finditer`（同一行多个命中不再只报第一个）、`--all` 遵循
  `.gitignore`；分叉差异（SKIP_DIRS、文档前缀等）全部保留，加出处头注释
- `tools/check-docs.py` 对齐 ClientTriage `c3a3952` / WindowsRemoteOps
  `156562c` 已修的四处功能性 bug —— BOM 首锚点、跨盘符 relpath 崩溃、
  冻结锚点误报、引言块只认头部；分叉差异（检查项、忽略目录）保留，加出处头注释
- 文档脱敏 —— 守卫文档示例中的本机用户名改占位（`d4003c0`）

### 闪存磨损审查：tmp-watch 状态文件迁 /tmp（2026-11-01）

- 三仓（本仓 / OpenwrtOpsToolkit / ShellcrashRules）路由器侧脚本做了一次
  **闪存写入磨损专项审查**（逐脚本列「写哪里、多频繁、写多大」）。本仓结论：
  guardian.sh / dest-guard.sh / memgate.sh / backup-prune.sh 的常驻写入全部
  已在 tmpfs 或低频带轮转（tmp-usage.log、backup-prune.log、memgate.log 都有
  64KB/16KB 上限），唯一的高频闪存写入点是 `tmp-watch.sh` 的增速状态文件
  `.tmp-watch.state` —— 每 5 分钟整写一次（288 次/天），纯属磨损
- 优化 `system/router-health/tmp-watch.sh` —— 状态文件迁到
  `/tmp/router-health/.tmp-watch.state`（tmpfs，路径可用 `TMPWATCH_STATE` 覆盖）。
  **告警路径 / 阈值 / 日志格式 / 回收边界一行未动**：状态只存「上轮 /tmp 用量」
  供 GROW 增速告警用，重启丢失等同开机首轮（PREV=0，/tmp 开机本来就近空，
  不会误报 GROW）；写状态前 `mkdir -p` 父目录
- 沙箱验证 —— 路由器实测 9 项断言：`TMPWATCH_STATE` 指到沙箱时状态写沙箱、
  默认路径自动建目录、闪存旧状态 mtime 全程不动、无日志残留、rc=0
- 部署 —— `/etc/router-health/tmp-watch.sh` md5 `e0e65b07…` 与仓库一致；
  真机幂等复跑一轮正常；旧的 `/etc/router-health/.tmp-watch.state` 已清理
  （一次性，避免闪存上留孤儿文件）

### backup-prune.sh 独立审查修复（2026-11-01）

- 对 11-01 入库的 `system/router-health/backup-prune.sh`（当时只经作者代理自测）做
  独立增量审查，路由器 /tmp 沙箱 74 项断言 + 生产幂等复跑，修三处真问题：
  1. **size-cap 删反了方向** —— 注释与 MAINTENANCE §5 均为「总量超限先删**最旧**
     非锚点散文件」，实现 `sort -rn` 实为最新先删（沙箱实测证实：超限时删的是
     新文件、留的是最旧垃圾）；改为 `sort -n` 最旧先删，删到阈值内即停
     （根因与规避见 [docs/PITFALLS.md](docs/PITFALLS.md) ⑱）；
  2. **scratch 建不出来时整个脚本静默猝死** —— phase 1 用 `: >`（POSIX special
     builtin）初始化临时文件，重定向失败（如 /tmp 写满）会当场退出整个脚本：
     零日志、phase 2 不执行、退出码 1（沙箱故障注入复现）；改为 `true >`（普通
     builtin，失败仅该命令失败）+ `mkdir` 显式判失败 log 后跳过 phase 1，phase 2
     照常执行（根因与规避见 [docs/PITFALLS.md](docs/PITFALLS.md) ⑰）；
  3. **INT/TERM 陷阱不退出** —— trap 收到信号只清锁不 `exit`，脚本会继续跑完
     phase 2；trap 动作补 `exit`（busybox ash 实测 EXIT trap 内 `exit` 只跑一次）。
- 加固两处（行为语义不变）：`b_is_keep` 的 `.keep` 匹配 `grep -q "^…$"` 改
  `-qxF`（文件名含正则元字符时不再扩大保护面）；头部退出码注释对齐实现
  （0 正常/无事可做、1 phase-2 根目录缺失、2 锁占用）。
- 验证与部署 —— `sh -n` + busybox `ash -n` ✓；路由器 /tmp 沙箱 74 断言全绿
  （stem/锚点/pre-* 前 3/.keep/.inprogress/180min/symlink/空格/换行文件名/锁自愈/
  退出码/故障注入/幂等复跑，生产目录前后指纹一致）；覆盖前现役脚本已备份路由器
  /tmp（`bak-20261101-155013`），部署后 md5 复验一致；生产幂等复跑 `/root/backup`
  10 项 0 删除（692KB）、`/root/final-backup` master rank-1 保护 0 删除，rc=0；
  cron 未动（仍 `40 4 * * *` 仅一条）。

### /root/backup 纳入 cron 修剪（2026-11-01）

- 修复备份区修剪的管辖面缺口 —— 现役 `backup-prune.sh`（cron `40 4 * * *`）硬编码只管
  `/root/final-backup`，`/root/backup` 不在管辖内：当天上午刚把 `/root/backup` 从
  1004KB 修到 692KB，但「改前 cp 一份」的副本只进不出，垃圾会重新堆积（根因与规避
  见 [docs/PITFALLS.md](docs/PITFALLS.md) ⑯）。现役脚本拉回仓库入库为正本
  `system/router-health/backup-prune.sh`，扩为两段：phase 2（`/root/final-backup`）
  原逻辑逐字节未动；phase 1（`/root/backup`）沿用 MAINTENANCE §3 同套阈值 ——
  `.bak-*` 同 stem 只留最新 1、`pre-*` 目录按 mtime 只留最近 3（不硬编码名单）、
  `*.apk-new` 全删、总量 >1 MiB 先删最旧非锚点散文件；锚点（sysupgrade.conf、
  argon 主题包、final-25.12.6-config.tar.gz、uhttpd 证书对、wireless.keep11k、
  `.keep` 名单、`.inprogress`、180min 内新写入）一律不删
- 部署与验证 —— 覆盖前现役脚本与 crontab 各备份到路由器 /tmp（`bak-20261101-142957`）；
  `sh -n` + busybox `ash -n` ✓；/tmp 沙箱自测（同 stem 旧副本、第 4 个及以后 `pre-*`、
  `*.apk-new` 被清，锚点全保，复跑 0 删除，锁不残留）✓；生产手动跑一轮：
  `/root/backup` 10 项 0 删除（692KB，上午已清干净、本就合规），`/root/final-backup`
  行为与改前一致（master rank-1 保护，0 删除）；cron 仍 `40 4 * * *` 且仅一条，
  其余行未动
- 文档同步 —— [MAINTENANCE.md](docs/MAINTENANCE.md) §5 止血点标注 cron 扩面（2026-11-01）；
  [DEPLOY.md](docs/DEPLOY.md) 部署映射表补 `backup-prune.sh` 行，并把 tmp-watch /
  guardian / memgate / rc.local 四行仍指向 `/root/backup` 同名副本与
  `tmp-watch.sh.bak-<时间戳>` 的过期回退写法改为「回退源 = git 历史」（当天清理后
  这些副本已不存在，属登记在案的文档滞后）

### 设备备份区修剪（2026-11-01）

- 修剪路由器 `/root/backup` —— 1004 KB → 692 KB：按 MAINTENANCE §3/§4 删同 basename
  旧副本与第 4 个及以后的 `pre-*`（共 26 项），按 §5「改完即删」清掉已验证改动的
  散落副本（guardian.sh / proxy-groups.yaml / ai-api-check.sh 等，判据：部署版与
  仓库 md5 一致、health 日志 10-27 起 0 ERROR）；必保留清单（sysupgrade.conf、
  argon 主题包）与最近 3 个 `pre-*` 原样保留
- 清掉 `/etc/router-health/` 的 tmp-watch `.bak-20261023` 一对 —— 改动已入库
  （b63407a）并运行 9 天，回退走 git 历史，不再留副本
- 仓库侧清掉 `tools/__pycache__/` 构建残留（本就不入库）

### guardian 增加 AI API 数据面探活（2026-10-27）

- 新增 `guardian/guardian.sh` 2.4 段 —— 每轮对 `🤖 AI接口` 的当前节点打一次
  `https://opencode.ai/zen/go/v1/models`（经 `127.0.0.1:7890`；不带 key，
  401/403 也证明链路通，只有 `000` 算坏），坏则写 `WARN`
- **只告警、不 `put`** —— `🤖 AI接口` 是 url-test，`put` 会写 `fixed` 把自动选路
  永久钉死；重选交给该组的 `interval`（已从默认 300s 调到 60s，见 ShellcrashRules 仓）
- 起因：2026-10-27 该组选中的 LA 节点「面板 alive、健康检查也过」但数据面已死，
  zgate 侧表现为 15s TLS 握手超时后 502。见 `docs/PITFALLS.md` ⑮

## [0.4.1] — 2026-10-26

### 全仓审查修复（2026-10-26）

- 修复 `guardian/dest-guard.sh` —— 陈旧锁回收只 `rmdir` 非空目录，必然失败且被
  `2>/dev/null` 吞掉；一次 `kill -9` / OOM / 掉电后每轮静默退出，站点守卫永久失效。
  改为先 `rm -f "$LOCK/ts"` 再 `rmdir`，仍失败则写 `ALERT`（PITFALLS ⑬）
- 修复 `guardian/guardian.sh` 健康探测 —— 3.5 / 3.6 只看 `%{time_total}`，节点被封时
  「快速失败」（502 / 连接被拒）耗时只有零点几秒，被判健康。改为同时取 `%{http_code}`，
  非 2xx/3xx 一律按劣化处理（PITFALLS ⑭）
- 修复 `guardian/guardian.sh` 的印度矛盾 —— `CLEAN_CANDIDATES` 含「印度-优化」
  （10-23 实测 cc=IN），`is_bad_node` 却仍按 10-22 结论把 `*印度*` 判坏，
  2.1 会与候选解析互相扳动；以新实测为准移出坏清单
- 修复 `guardian/guardian.sh` 一处裸 `curl` —— `resolve_clean_node` 取组成员改用
  `$CURL`，与全脚本约定一致
- 修复 `recovery/recover-now.sh` —— 核心 30 秒未就绪仍无条件重载含 DNS 劫持的
  `googleroute`，会自演「连上 WiFi 没网」；第 4 节加载前加 `:1053` 就绪门控
  （与 rc.local 同口径）
- 修复 `system/archive/bootfix.sh` —— awk 双文件插入用全局 `NR` 当数组下标，
  会给 guardian.sh 头部插 N 行空行、shebang 不再首行；改用 `FNR` 并在插入后自检首行
- 修复 `recovery/local-tools/recover-run.ps1` —— Windows PowerShell 5.1 下
  `2>&1` + `ErrorActionPreference=Stop` 会让 ssh 首条 stderr（known-hosts 警告）
  终止整个恢复；加 `LogLevel=ERROR` 并局部放宽为 `Continue`
- 修复 `tools/check-vault-not-staged.py` —— `--all` 在 CI 浅克隆下只能看到 1 个提交，
  且 git 失败时打假绿；CI 检出加 `fetch-depth: 0`，git 返回码非零直接报错
- 修复 `tools/check-secrets.py` —— `git ls-files` 失败时按 0 文件「通过」；改为报错退出
- 修复 `recovery/local-tools/askpass.sh` —— 空的 `.router-password` 会吐出空口令；
  改为 `-s` 判非空
- 修复 `system/archive/core-upgrade.sh` —— 回滚无条件清空 `custcorelink`，用户自定义
  链接丢失；升级前备份原值、回滚按原值恢复
- 验证 —— 全量 `sh -n` ✓、`python -m py_compile` ✓、`tools/check-secrets.py` ✓
  （58 文件）；guardian / dest-guard 部署后 `ash -n` ✓、md5 与仓库一致，
  实跑一轮 rc=0、日志无 ERROR

### 干净出口韩国节点治理（2026-10-24）

- 修复 `guardian/guardian.sh` —— `CLEAN_CANDIDATES` 剔除 `🇰🇷 韩国KR-HY2`：
  韩国法律对成人内容强制年龄验证，Google 按出口 IP 国家执行，落在韩国 =
  搜成人词弹「19 岁验证」且只认韩国手机号，无解（2026-10-23 用户报告）
- 新增 `is_kr_node()` 并加进 2.1 段扳走条件 —— `is_bad_node` 豁免全部
  `-HY2` 节点，韩国 HY2 要单独拦，否则已落韩国的组永远不会被扳走
- `resolve_clean_node()` 增加**组内成员校验**（候选 `grep -Fxq` 组的 `all`
  列表）—— delay API 对组外节点也能测通，但 PUT 只接受组内成员；此前
  「台湾-优化2-GPT」可达却在组外，解析成它后每轮 `ERROR` 切换失败
  （根因与规避见 [docs/PITFALLS.md](docs/PITFALLS.md) ⑪⑫）
- 候选兜底调整为 `印度-优化`（实测 cc=IN）；剔除同样组外的
  `台湾-优化2-GPT`；同晚实测新加坡-优化系（-GPT / 2-GPT / 优化3）全部
  cc=CN 不可用，HY2 池（新加坡/日本）对 Google 间歇超时 —— 恢复后
  仍按候选顺序优先切回
- 验证 —— `sh -n` ✓（本机与路由器）；实跑一轮 `🤖 干净出口` / `🤖 AI网页`
  / `🤖 人工智能` 全部落 `印度-优化`，`support.google.com` 实测 cc=IN，
  Google 搜索成人词 HTTP 200、无 ageverify 跳转；后续 cron 轮安静（verdict=1）
- 部署 —— 已同步 `/etc/ShellCrash/guardian.sh`

### `/tmp` 自动回收（2026-10-23）

- 新增 `system/router-health/tmp-watch.sh` + `tmp-watch.conf` 入库 —— 原先只存在于设备上。
  脚本在原有「水位告警」之外增加**安全回收**：只删 `/tmp` 根目录、白名单内、6 小时未修改
  且未被进程打开的文件；每轮最多 64 个 / 8 MB；额外精确回收
  `/tmp/ShellCrash/config.yaml.rules-*.{del,ana}`（带 PID 的中间产物）。
  **子目录永不递归**，`config.yaml` / `.bak-*` / `-test.yaml` 不在回收范围
- 调整阈值 —— `TMP_WARN_KB` 30 MB → **24 MB**（上限 48 MiB 的 50%），
  避免「28.7 MB 静默、34.4 MB 才报警」的盲区
- 修复 —— 原脚本注释写「≥80% 会自动清」，实际只写日志 + `logger`，没有任何 `rm`。
  2026-10-23 实测 `/tmp` 停在 34.4 MB 时连续 8 条 WARN 无人处理
  （根因与规避见 [docs/PITFALLS.md](docs/PITFALLS.md) ⑩）
- 实测（2026-10-23 22:00）—— `/tmp` 29,412 KB → 4.2 MB，`MemAvailable`
  30,396 KB → 52,416 KB，`Shmem` 42,976 KB → 17,836 KB；清掉 87 个根目录调试文件 +
  9 个中间产物，`config.yaml` md5 全程未变；`sh -n` ✓、dry-run（`TMPWATCH_PURGE=0`）✓、
  无候选时静默 ✓
- 文档同步 —— [docs/DEPLOY.md](docs/DEPLOY.md) 部署映射表与目录职责、
  [docs/MAINTENANCE.md](docs/MAINTENANCE.md) 新增 §6「RAM 型 `/tmp` 的自动回收」、
  [docs/OPERATIONS.md](docs/OPERATIONS.md) 定时任务与日志入口、
  [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) 修正「`/tmp` 无 `size=`、上限 119 MB」
  与「守护 ≥80% 会自动清」两处过时描述，`GOMEMLIMIT` 状态从「待执行」改为「已生效」

### 文档正本与守卫规则（2026-10-24）

- 新增 `docs/DOC-RULES.md` 变更触发矩阵一条 —— **修一个缺陷必须给对应正本补一条**
  （只改代码不改正本，下次还会踩同一个坑）
- 新增 `docs/PITFALLS.md` ⑥–⑨ 四条 —— 阈值减半（耗时取 max 后又除 2）、`mkdir` 实例锁、
  `check` 模式必须先判 mode 再动作、两个仓的脚本落到设备同一路径的同落点变体（后者会互相覆盖）
- 新增 `docs/SECRETS.md`「推送前脱敏规则」通用章节 —— 凭据 / 本机用户目录 / 真实邮箱
  三类拦截面与三条放行口径；`tools/check-secrets.py` 相应加占位用户名放行
- 调整 `tools/check-secrets.py` —— 新增本机用户目录（`C:\Users\<名字>`，正反斜杠都拦）
  与真实邮箱域名两类规则

### 守护实例锁（2026-10-24）

- 新增 `guardian/guardian.sh` 实例锁 —— 3.6 逐个候选探测最坏要跑两分多钟，加上 3.5 与
  第 1 节的等待，整轮可能超过 `*/5` cron 的 5 分钟；叠轮会让两轮同时切策略组、同时写
  `.clean_node` / `.clean_verdict`，日志记录与实际生效节点对不上。锁形状照抄
  `bulk-guard.sh`：`mkdir` 原子建锁 + pid/ts + 600 秒过期回收 + `trap` 清理；
  拿不到锁时记一行日志并跳过本轮
- 验证 —— `sh -n` ✓；本地用两个并发实例验证「第二个跳过、trap 删锁、死 PID 过期回收」；
  部署到路由器后 `ash -n` ✓、md5 与仓库一致

## [0.4.0] — 2026-10-23

### 守卫与恢复脚本（2026-10-23）

- 修复 `guardian/guardian.sh` —— 3.5 / 3.6 的耗时计算把「取较慢那次」写成了
  「取 max 后再除 2」，算出的值只有真实值的一半（实测 3.2/2.8 得 1.6）。
  后果是劣化阈值被系统性抬高约一倍：`EXIT_MAX_SEC=3` 实际要真实 6 秒才触发，
  节点劣化守卫长期失灵。改为取 max 不除；同时新增 `ge_sec` 用数值比较替代
  case glob（`10.0` / `12.5` 这类两位数带小数的耗时不会命中旧模式，判据被跳过）
- 修复 `recovery/recover-now.sh` —— `check` 模式声明「只诊断、不改任何东西」，
  但第 1 节在 mode 判断之前就备份并重写 `fake_ip_filter`；现在 check 分支只打印现状
- 修复 `recovery/local-tools/fix-router.sh` —— 路由器不可达 / SSH 失败只打印一行
  就继续切回热点，用户看到「跑完 4 步」而实际一步都没做成。现在不可达直接
  `exit 1` 并保持连在路由器 WiFi，SSH 退出码透传成脚本退出码
- 调整 `.gitignore` —— 忽略 `recovery/local-tools/recover-output.txt`
  （恢复脚本会把内网拓扑、nft 表、出口 IP 写到这个文件，此前 `git add -A` 会带进仓）
- 验证 —— 三个脚本 `sh -n` / `bash -n` ✓；耗时计算用 3.2/2.8、5.9/6.1、12.5/3.0
  三组样本核对（分别得 3.2 / 6.1 / 12.5）；`check-vault-not-staged --all` ✓、
  `check-secrets.py` ✓（55 个文件）、`check-docs.py` ✓（21 篇）


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

### 干净出口运行时解析（2026-10-22）

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

- `scp guardian/guardian.sh root@<REPLACE-ROUTER-LAN-IP>:/etc/ShellCrash/guardian.sh`（历史原文用参考设备 LAN 地址，现按设备值外置口径改为占位符），备份
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
