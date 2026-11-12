# 踩坑总汇

> **一句话**：这类设备的机制级坑与红线 —— 现象 → 步骤 → 解法的**排查流程**在 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)，本篇只写「为什么会这样」与「动手前的红线」。

**① `/tmp` 是 tmpfs，写满就是 OOM。**
`/tmp` 无 `size=` → 上限 ≈ RAM/2 = **119 MB**，且直接吃内存。
2026-10-20 12:45 实测：升级 mihomo 核心时 `gunzip` 把 **57 MB** 裸二进制灌进 `/tmp`，
占用冲到 99% → 核心被杀 → 触发 mtk-wdt 硬件看门狗整机复位。
守护每 5 分钟看水位，≥ 80% 就清掉已知的大临时文件。
**清理 `/tmp` 前先 `ls -ld /var`。**

**② `/var` 是指向 `/tmp` 的相对软链。**
`/var -> tmp` ⇒ `/var/etc` 就是 `/tmp/etc`，而那里正是 **dnsmasq 生成配置文件**的目录
（dnsmasq 以 `-C /var/etc/dnsmasq.conf.<cfg>` 启动）。
`rm -rf /tmp/etc` 之后 dnsmasq 靠内存里的旧配置继续跑，**看起来一切正常**，
但任何一次 dnsmasq 重启都会失败 → 全屋 DNS 断。
**只删具体文件名，绝不用通配符删目录**；`rc.local` 里已有 `VAR_RUNTIME_DIRS` 兜底重建。

**③ YAML 重复键 / 非法 `mixed-port` → mihomo 拒载 → ShellCrash 静默回退基础配置。**
ShellCrash 校验失败时**只打一行日志**（「自定义配置文件校验失败！将使用基础配置文件启动！」），
自定义策略组（🤖 AI网页 / 🤖 干净出口）与 E 段规则**全丢**，面板却看着正常。
`mixed-port` 被写成 `127.0.0.1:7890`（mihomo v1.19 只接受纯数字）是最典型的一种。
**检测**：`ls /tmp/ShellCrash/error.yaml`（存在 = 回退过）；
`grep -q "name: 🤖 AI网页" /tmp/ShellCrash/config.yaml`（缺失 = 自定义组没了）。
守护里有 30 分钟限频的自愈分支会自动重跑 `hotupdate`。

**④ overlay 余量比看上去紧。**
分区 **57.5 MB**。2026-10-20 早间实测 `23.1M / 57.5M`（40%），
同日 15:00 内存审计实测 **36,392 KB / 58,832 KB（65%）**，余 19 MB。
`du` 是逻辑值、**高估约 2.16×**（UBIFS 压缩），判断余量以 `df` 为准。
备份区是最大的消耗项 —— 策略见 [MAINTENANCE.md](MAINTENANCE.md)。

**⑤ Windows 侧工具的路径依赖。**
`recovery/local-tools/fix-router.sh`、`recover-run.ps1` 与 `recover-gitbash.cmd`
都已改成**按脚本自身位置推导**
（`$(dirname "$0")` / `Split-Path $PSScriptRoot -Parent` / `%~dp0..\..`），仓搬到哪里都能跑。
但 `recover-gitbash.cmd` 仍假定 Git 装在 `C:\Program Files\Git\`；
它还依赖**仓外**的 `%TEMP%\owrt\rsh.sh`（SSH 辅助脚本，不在本仓）。
另外 `fix-router.sh` 里的 SSID 默认值是占位符 `YOUR_ROUTER_SSID`，速查表用的是 `<YOUR-SSID>` ——
两者都是占位符，运行时必须用环境变量指定真实值。

**⑥ 守护的耗时判据：`awk` 取 max 后又除 2，阈值被静默减半。**
3.5 / 3.6 的意图是「两次探测取较慢那次」，写法却是
`awk '{t+=($1>$2?$1:$2)} END{printf "%.1f", t/2}'` —— `$1` / `$2` 是**同一行的两个字段**，
取到 max 之后又除了 2。实测 3.2 / 2.8 得 1.6，而意图是 3.2：`EXIT_MAX_SEC=3` 实际要真实
6 秒才触发，节点劣化守卫长期失灵。另外用 `case "$MS" in 3.*|4.*…)` 判数值时，
`10.0` / `12.5` 这类带小数点的两位数**不会命中**任何分支。
**判据用数值比较**（`awk -v a=… 'BEGIN{exit !(a+0 >= b+0)}'`），不要用 case glob。
**下次怎么避**：任何「阈值 × 探测」的改动，先用两组样本手算一遍再上机。

**⑦ 守护没有实例锁：`*/5` 的 cron 与最坏 300 秒的一轮必然叠轮。**
3.6 每个候选 `sleep 3` + 两次 15 秒超时，4 个候选就 132 秒；叠轮时两轮同时 `put`
策略组、同时写 `.clean_node` / `.clean_verdict`，日志记录与实际生效节点对不上。
锁用 `mkdir` 原子建 + `pid` / `ts` + 600 秒过期回收 + `trap` 清理（`bulk-guard.sh` 同款）。
**下次怎么避**：凡是 cron 周期可能小于最坏耗时的脚本，第一版就要有实例锁。

**⑧ `check` 模式必须在动手之前分流。**
`recover-now.sh check` 声称「只诊断、不改任何东西」，但第 1 节在 `MODE` 判断之前
就备份并重写了 `fake_ip_filter`。**下次怎么避**：只读模式的分支要放在所有写操作之前，
不能靠「后面再 exit」。

**⑨ 两个仓的同名脚本落点相同，部署前先确认设备跑的是哪一版。**
`AX3000TOpenwrt/guardian/guardian.sh` 与 `OpenwrtOpsToolkit/openwrt/guardian.sh`
都部署到 `/etc/ShellCrash/guardian.sh`，但**不是同一份实现**（配置读取、变量名不同）。
2026-10-24 维护时先推了 Ops 版、又推 AX 版，中间几分钟设备上跑的是错误的变体。
**下次怎么避**：部署前先 `md5sum` 对比设备文件与两个仓的候选，确认血缘；部署后再核对。

**⑩ 「盯着 `/tmp`」不等于「回收 `/tmp`」：只告警的监控会连续报警到没人看。**
`tmp-watch.sh` 第一版只写日志 + `logger`，没有任何 `rm`；阈值 WARN 30 MB / CRIT 40 MB
又贴着 48 MiB 的硬顶。2026-10-23 实测 `/tmp` 长期停在 **34.4 MB**，20:45–21:20
每 5 分钟一条 `[WARN]`，连续 8 条无人处理；而 28.7 MB 那一段甚至低于 30 MB 阈值，
**完全静默**。根因是内存盘没有自动过期机制（OpenWrt 上没有 tmpwatch / systemd-tmpfiles），
且本机无 swap，tmpfs 页不可回收 —— 只有删文件或重启才会降。
**下次怎么避**：内存盘的监控第一版就要带「安全回收」，阈值留出缓冲
（WARN 放在上限的 50%，不是 62%）；回收范围按**正向白名单 + 只动根目录**写，
子目录（`/tmp/ShellCrash`）永远不递归 —— 边界见 [MAINTENANCE.md](MAINTENANCE.md) §6.2。

**⑪ 落在韩国的干净出口 = Google 搜索弹「19 岁验证」且只认韩国手机号。**
2026-10-23 用户报告「Google 搜成人内容要求绑定韩国手机号」。实况：全部
Google 域名走 `🤖 干净出口`，该组当前 `🇰🇷 韩国KR-HY2`。根因是韩国法律对
成人内容强制年龄验证，Google 按出口 IP 国家执行 —— 这不是风控误判，换账号、
清 cookie 都无效，唯一的出路是出口不落韩国。而 guardian 的 `is_bad_node`
豁免全部 `-HY2` 节点（对 AI 干净），2.1 段永远不会扳它；候选清单里韩国排第 3，
HY2 池前两个（新加坡/日本）一抖它就上位，上位后 resolve「在候选里且可达就保持」
让它稳坐。**下次怎么避**：地区性限制（年龄验证 / 服务封锁）按「目标站 × 出口国家」
单独拦，别混进通用的坏节点清单；候选清单宁缺毋滥，`CLEAN_CANDIDATES` 已剔除
韩国并新增 `is_kr_node` 扳走判定。顺带实测（`support.google.com` 页面
`var cc=` 判定）：新加坡-优化系全部 cc=CN、印度-优化 cc=IN 兜底 ——
**节点名里的国家与实际 cc 无关，每次都要实测**。

**⑫ 守卫的候选清单必须做「组内成员」校验：delay API 测得到组外节点，PUT 必拒。**
2026-10-24 guardian 连续两轮 `ERROR: 切到 台湾-优化2-GPT 失败`，组却留在韩国。
根因：mihomo 的 `/proxies/<名>/delay` 对**任意已知代理**都能测（哪怕不在目标组里），
而 `PUT /proxies/<组>` 只接受组内成员 —— 候选清单（硬编码在 guardian）与组 filter
`(印度|India|IN|台湾-优化3|新加坡|HY2)` 脱节时，「可达候选」切不进去，
2.1 每轮 ERROR，劣化治理空转。**下次怎么避**：任何「守卫自动切节点」的候选
都必须先 `grep -Fxq` 组的 `all` 成员列表再探测（`resolve_clean_node` 已加）；
改组 filter 时必须同步过一遍守卫的候选清单 —— 节点名是环境的一部分，
订阅一变就脱节。

**⑬ 锁目录里只要还有文件，`rmdir` 永远回收不掉：一次强杀就能让守护永久静默。**
`dest-guard.sh` 的锁是「目录 + `ts` 文件」，进程被 `kill -9` / OOM / 掉电时 `trap` 不执行；
陈旧锁回收分支只做 `rmdir "$LOCK"`，对非空目录必然失败，还被 `2>/dev/null` 吞掉。
之后每轮 `mkdir` 失败即 `exit 0`，日志一行都没有 —— 站点探活与切换全停，直到人工清锁。
**下次怎么避**：锁回收必须「先删文件再删目录」（`guardian.sh` 本来就是这么写的），
失败要留 `ALERT`；新建锁的地方照抄已验证的形状，别手写简化版。

**⑭ 健康探测只看耗时，会把「快速失败」当成健康。**
两个 guardian 的 3.5 / 3.6 原来只取 `%{time_total}`。节点被封或目标站直接拒绝时，
代理会**很快**返回 502 / 连接被拒，耗时只有零点几秒 —— 判定为健康，永远不触发复位。
**下次怎么避**：探测同时取 `%{http_code}`，非 2xx/3xx 一律按劣化处理，再比较耗时；
`000`（curl 连不上）同样算劣化。

**⑮ 「节点 alive + 组延迟正常」不等于 AI API 能用：探数据面，但别用 `put` 重选。**
2026-10-27 机器人侧 `opencode.ai` 间歇 502。实况：`opencode.ai` 走 `🤖 AI接口`
（url-test，健康检查就是 `https://opencode.ai/`），当轮选中的 `🇺🇸 美国LA-优化-GPT`
面板 alive、组延迟 1068ms，但 `/zen/go/v1/models` 与根路径同时超时 —— 守卫此前只覆盖
`🤖 人工智能` / `🤖 AI网页` / `🤖 干净出口`，这个组根本没人看。
**下次怎么避**：任何承载关键 API 的 url-test 组都要有「数据面」探测，探的要是**真实
业务端点**而不是根页面；修复不要用 `put` —— 对 url-test 组 `put` 会写 `fixed`，
自动选路永久失效（重演 2026-10-23 台湾-优化2-GPT 那类事故），重选交给 `interval`。
2.4 段按这个口径写成「只告警」，节点切换仍由 url-test 每分钟复测完成。

**⑯ 修剪脚本只管一个目录，「清完还会再堆」的斜率就没变。**
2026-11-01 大扫除把 `/root/backup` 从 1004KB 修到 692KB，但现役 `backup-prune.sh`
（cron 04:40）硬编码只管 `/root/final-backup`，注释里还写着「/root/backup is NEVER
touched」—— 只要「改前 cp 一份到 /root/backup」的习惯还在，副本只进不出，
垃圾必然重新堆积；而且该脚本此前不入库，仓库里连它管什么都不知情。
**下次怎么避**：新增备份区（或新增「改前留副本」的落点）时，必须同步扩大 cron
修剪的管辖面（现脚本 phase 1 = `/root/backup` 用 MAINTENANCE §3 同套阈值 + 锚点
必保留清单，phase 2 = `/root/final-backup` 原配额）；把某个目录划出自动化管辖的
注释是**行为描述**，管辖面变了要跟着改，否则它就是撒谎的文档；设备侧现役脚本
一律入库为正本（`system/router-health/`），回退走 git 历史。

**⑰ busybox ash 里 `: > 临时文件` 遇到重定向失败会**当场退出整个脚本** —— 前面跑了一半、后面全部不跑、日志一行不留。**
2026-11-01 对 `backup-prune.sh` 做 /tmp 沙箱实测时发现：把 phase 1 的 scratch 路径
`/tmp/.backup-prune-b.$$` 预先占用成一个文件后，脚本在 `: > "$TMPD_B"/cand` 这一行
直接终止（rc=1），audit log 零字节，phase 2（`/root/final-backup` 的原配额修剪）
**一次都没执行**。根因：POSIX 把 `:` 归为 **special builtin**，special builtin 遇到
重定向失败时非交互 shell 必须**整体退出**（`mkdir -p` 失败它不拦，拦不住下一行的
`: >`）；而 cron 把 stderr 丢掉，这次「死在半路」在日志上完全不可见。`true` 是
普通 builtin，重定向失败只让那一条命令失败，脚本继续走。
**下次怎么避**：busybox ash 脚本里**所有**临时文件截断/创建用 `true > file`（或先
`mkdir` 判失败再跳过本段），别用 `: >`；依赖 scratch 的段落必须在创建失败时
显式 log + 跳过，并保证同脚本后续段落照常执行（phase 1 挂了 phase 2 还得跑）；
「写一半就死」这类故障只在沙箱里构造故障注入才能暴露，正常路径自测测不到。

**⑱ 修剪「超总量先删最旧」的口径，实现排成了「先删最新」——注释与文档都在说谎。**
`backup-prune.sh` phase 1 的 size-cap 分支，脚本头注释与 MAINTENANCE §5 都写
「总量 >1 MiB 先删**最旧**非锚点散文件」，实现却是 `sort -rn`（mtime 降序 = 最新
在前）逐个标记删除 —— 方向反了，真触发了会先删刚生成的备份、留下最陈旧的垃圾。
10-31 的自测没暴露：当时 `/root/backup` 只有 692KB，没构造**超过总量上限**的用例，
整条分支一次都没跑到。**下次怎么避**：凡「排序 + 取前 N / 删到阈值」的逻辑，必须
有一个**实际触发该分支**的沙箱用例（构造 mtime 一老一新两个文件，断言删老留新）；
注释里的方向词（最旧/最新、升序/降序）要和 `sort` 参数逐字对照一遍——`-rn` 是
降序，`-n` 才是升序。

**⑲ 门禁脚本用 `✓` / `✗` 打结论，GBK 控制台下把自己判成失败。**
Windows 中文控制台（cp936）跑 `python -I tools/check-docs.py`，最后一行
`print(f"✓ …")` 抛 `UnicodeEncodeError: 'gbk' codec can't encode character '\u2713'`，
脚本以**退出码 1** 结束 —— 检查其实全过，门禁却报红；CI 是 UTF-8 所以一直没暴露。
`✓` U+2713 / `✗` U+2717 / `⚠` U+26A0 都不在 cp936 码表，而 `python -I` 会忽略
`PYTHONIOENCODING` / `PYTHONUTF8`，「设个别名带环境变量」也不是解法。
**怎么避**：结论行只用 ASCII（`[OK]` / `[FAIL]` / `[!]`），入口再加
`if hasattr(sys.stdout, "reconfigure"): sys.stdout.reconfigure(errors="replace")` 兜底；
以后凡是往 stdout 写花字（✓、⚠、→、emoji），先在 `python -I` + 系统默认代码页下跑一遍。
同一问题首次记录见 ModelBus 仓「踩坑总汇」第 36 节（跨仓引用，非本仓路径）。

**⑳ 日志告警「每轮都报当前状态」把 512 KiB 环形缓冲冲成只覆盖 3.8 小时。**
两层噪音叠在一起：① `cronloglevel` 漂到 5，crond 自身 stderr（`wakeup dt=10`、
子进程退出）每 10 秒一条 `cron.err`，占改前日志 **97.55% 字节**；② keepaudit 巡检把
`/etc/ShellCrash` 顶层的 `.bak-*` 回滚副本、`.disabled` 禁用件、隐藏临时文件全算成
「未在保留清单」，42 个漏项里 37 个是派生件，且每 30 分钟**无条件重报**同一条
1,000+ B 超长清单。**根因**：两处都是「把状态当事件报」—— crond 把每轮 wakeup
当日志，keepaudit 把稳定不变的漏项集合当新告警，都没做幂等。
**怎么避**：状态类告警必须幂等 —— crond loglevel 保持 9（业务告警一律显式
`logger -t`，不靠 crond stderr）；巡检先按后缀 `case` 排除派生件，再把漏项集合
存 `/tmp/.keepaudit.state`，仅当**集合相对上次变化**时才 `logger -t keepaudit`。
判据写「变化才报」而不是「每轮算一遍就报」；也别用加大 `log_size` 掩盖刷屏 ——
缓冲是 tmpfs，加大直接吃内存、增加闪存写入；降噪后实测 138,063 B/h → 891 B/h，
覆盖时长从 3.8 小时拉到约 6 天。
**㉑ 升完内核 `start.sh restart` 后立刻查 `/version`，空响应被 `|| true` 吞掉，验收假绿。**
2026-11-10 11:06 执行 `upgrade-core-to-v1.19.33.sh`：7 步都打印了、二进制 `-v` 也报
`v1.19.33`，唯独 7/7 的运行态 `curl /version` 留了一行空白（脚本里 `curl … || true`
把失败吞了），随后几秒 SSH 提示符才冒出 `rules-porn:` / `rules-cnip:` /
`[reorder-groups]` 回显。**根因**：`start.sh` 的 `start_l` 分支是 `bfstart && … && afstart &`
**后台拉起**，核心进程写完 pid 时外部控制 API（`:9999`）还没监听；`clash_modify.sh`
/ `sub-sync.sh` / `reorder-groups.sh` 这些启动钩子也是异步跑完才把规则回显吐到终端。
单次 `sleep 3` 不够，且「有 `-v` 就算成功」只验了文件、没验运行态。
**怎么避**：升级脚本的运行态验收改成「最多 20 秒轮询 `curl /version`，响应必须含
目标版本号」，超时显式 `!! 未就绪` 告警，不再 `|| true` 静默；二进制 `-v` 与运行态
`{"version":"…"}` 两个判据都要有。看到晚到的 `rules-*` 回显不是升级失败，是启动钩子
按 Design 补完规则，复验 `grep -c "^  - name:"` = 31 / `RULE-SET,cn` 命中即可。
