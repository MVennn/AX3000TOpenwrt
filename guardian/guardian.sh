#!/bin/sh
# ============================================================================
# 网络守护 v3 —— 只做「检测 + 最小化修复」，绝不做破坏性操作
#
# 已知良好状态（2026-10-20 固化，依据实测）：
#   - 🤖 干净出口 / 🤖 AI网页 = CLEAN_CANDIDATES 里第一个可达的入口
#     （2026-10-22 起不再写死单个节点：HY2 池优先，整池挂掉时退到台湾-优化3；
#      入口之间共用同一干净出口 IP，切入口只换链路，所以会话不受影响）
#   - 🤖 人工智能 = 🤖 AI网页
#   - 所有 Google 家族域名规则指向 🤖 干净出口（一次性 Google 会话 = 一个出口 IP）
#   - 🚀 节点选择 = ♻️ 自动选择
#   - nft 表 inet quicguard / googleroute / googlecn 均已加载
#   - 运行配置未发生「静默回退」（ShellCrash 生成失败会静默改用基础配置）
#
# 原则：
#   1. 只在检测到偏离已知良好状态时才动手；每种修复都幂等、可回退
#   2. 绝不删改防火墙链、绝不重启路由器、绝不改订阅与规则文件
#   3. 关键动作失败必须显式报错
#   4. 维护前可先停守护：sed -i '/guardian/d' /etc/crontabs/root && /etc/init.d/cron restart
# ============================================================================
mkdir -p /tmp/ShellCrash 2>/dev/null
LOG=/tmp/ShellCrash/guardian.log
CURL=/usr/bin/curl
NFT=/usr/sbin/nft
CTRL="${MIHOMO_API:-http://127.0.0.1:9999}"
PROXY="${PROXY_URL:-http://127.0.0.1:7890}"
PIDFILE=/tmp/ShellCrash/shellcrash.pid
ALIVEF=/tmp/ShellCrash/.proxy_alive
AI_GROUP="${AI_GROUP:-🤖 人工智能}"
AI_WEB="${AI_WEB:-🤖 AI网页}"
CL="${CLEAN_GROUP:-🤖 干净出口}"
# 干净出口候选：按优先级排列，全部是实测 cc≠CN/HK 的入口。
# HY2 池优先（cc=SG）；HY2 整池挂掉时自动退到台湾-优化3（cc=TW）。
# 不再写死单个 CLEAN_NODE —— 2026-10-22 实测 HY2 四个节点全挂，写死目标会让
# 2.1「锁干净节点」把组切到死节点、2.3「存活守卫」再切走，每 5 分钟打一次。
# 不含韩国：2026-10-23 起 Google 按出口 IP 国家执行韩国成人内容强制年龄验证，
# 弹「19 岁验证」且只认韩国手机号 —— 落韩国 = Google 搜索废掉，永远不进候选。
# 不含「台湾-优化2-GPT」：不在干净出口组的 filter 内，put 必被控制 API 拒绝
# （2026-10-23 实测：解析成它之后每轮 ERROR）。印度-优化 实测 cc=IN 兜底。
CLEAN_CANDIDATES="${CLEAN_NODE:+$CLEAN_NODE|}${CLEAN_CANDIDATES:-🇸🇬 新加坡SG-HY2|🇯🇵 日本JP-HY2|🇹🇼 台湾-优化3|🇮🇳 印度-优化}"
CL_ALIVE_URL="${CL_ALIVE_URL:-https://www.google.com/generate_204}"
CLEAN_CACHE=/tmp/ShellCrash/.clean_node
CLEAN_VERDICT_FILE=/tmp/ShellCrash/.clean_verdict
CLEAN_RETRY="${CLEAN_RETRY:-600}"
POOL_GROUP="${POOL_GROUP:-🚀 节点选择}"
POOL_FALLBACK_GROUP="${POOL_FALLBACK_GROUP:-♻️ 自动选择}"

API_SECRET=$(sed -n "s/^secret=//p" /etc/ShellCrash/configs/ShellCrash.cfg 2>/dev/null | head -1)
SECRET="$API_SECRET"
AUTH="Authorization: Bearer $SECRET"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
# 每轮动作计数，供 --status 与 /tmp/ShellCrash/guardian.state 汇总
# （联动：health-snapshot.sh --json 把这一行并进结构化快照）
FIXES=0; ERRORS=0; WARNS=0; WOULDFIX=0
log() {
  _msg="$*"
  # dry-run 下把 FIX: 改写成 WOULD-FIX: —— put() 已返回 204 让调用方走成功分支，
  # 这里统一改写，预演输出里一眼能看出「本来会动哪一组」。
  if [ "$MODE" = "dry" ]; then
    case "$_msg" in FIX:*) _msg="WOULD-FIX:${_msg#FIX:}" ;; esac
  fi
  # 计数显式互斥（L2）：WOULD-FIX 含 FIX 子串，旧版两个模式虽靠 case 顺序隐含
  # 互斥，顺序一被调整就会 fixes/wouldfix 双计；这里用 else 分支硬隔离。
  case "$_msg" in
    *WOULD-FIX*) WOULDFIX=$((WOULDFIX + 1)) ;;
    *) case "$_msg" in *FIX*) FIXES=$((FIXES + 1)) ;; esac ;;
  esac
  case "$_msg" in *ERROR*) ERRORS=$((ERRORS + 1)) ;; esac
  case "$_msg" in *WARN*|*ALERT*) WARNS=$((WARNS + 1)) ;; esac
  # H1：dry-run 零副作用 —— 预演消息只回显到 stdout，不写 guardian.log、不 logger
  # 写 syslog；生产轮保持原样（落盘 + 高优先级日志）。
  if [ "$MODE" = "dry" ]; then
    printf 'WOULD[%s] %s\n' "$(ts)" "$_msg"
    return 0
  fi
  echo "$(ts) $_msg" >> "$LOG"
  case "$_msg" in
    *FIX*|*ALERT*|*ERROR*|*WARN*) logger -t guardian -p daemon.warn "$_msg" 2>/dev/null ;;
  esac
}
enc() { echo "$1" | sed 's/ /%20/g'; }

# ---- 组状态缓存（同一轮内同一组只问一次控制 API）----------------------------
# 为什么：一轮里「🤖 干净出口」被 resolve_clean_node / 2.2 / 2.3 / 3.6 各取一次，
# 「🚀 节点选择」被第 3 节与 3.5 各取一次；每次都是一个 curl 进程 + 一份整组
# JSON（含全部成员与 history，2-4 KB）。缓存后每轮少 4-6 个 curl 与对应解析
# 进程，并让同一轮的判断基于同一份快照（不会前后结论打架）。
#
# 为什么落文件而不是变量：调用点全是 X=$(grp "组名") 的命令替换形式，每次
# 替换都开一个子 shell —— 在 grp 里改的变量回到父 shell 就丢了，变量缓存
# 等于没做（2026-11-14 单测实测：两次调用仍是两次请求）。文件放 tmpfs，
# 每轮独立文件名、收尾删除，不写闪存、不跨轮污染。
# 空值也缓存 —— 组不存在时不能每轮重复发请求。
GRP_CACHE_FILE=${GUARDIAN_CACHE_FILE:-/tmp/ShellCrash/.grp-cache.$$}

# 命中判定用 awk 的 index() 做字面前缀匹配（"组名<TAB>"），
# 组名里带 . * [ ] 都不会误命中别的组。
grp_cached() {
  _res=$(awk -v k="$1" 'index($0, k "\t")==1 { print "1" substr($0, length(k)+2); f=1; exit } END{ if(!f) print "0" }' "$GRP_CACHE_FILE" 2>/dev/null)
  case "$_res" in
    1*) printf '%s' "${_res#1}"; return 0 ;;
  esac
  return 1
}
grp_invalidate() {
  _f="$GRP_CACHE_FILE.new"
  if awk -v k="$1" 'index($0, k "\t")!=1' "$GRP_CACHE_FILE" > "$_f" 2>/dev/null; then
    mv -f "$_f" "$GRP_CACHE_FILE" 2>/dev/null
  fi
  rm -f "$_f" 2>/dev/null
}
grp_uncached() {
  $CURL -s -m 5 -H "$AUTH" "$CTRL/proxies/$(enc "$1")" 2>/dev/null \
    | grep -oE '"now":"[^"]*"' | head -1 | sed 's/"now":"//;s/"$//'
}
grp() {
  if grp_cached "$1"; then return 0; fi
  _v=$(grp_uncached "$1")
  printf '%s\t%s\n' "$1" "$_v" >> "$GRP_CACHE_FILE" 2>/dev/null
  printf '%s' "$_v"
}
put() {
  # dry-run：不落任何切换，但让调用方走「成功」分支，由 log() 统一把 FIX:
  # 改写成 WOULD-FIX: —— 单点处理，调用处不必各写一份判断。
  if [ "$MODE" = "dry" ]; then printf '%s' "204"; return 0; fi
  _code=$($CURL -s -m 8 -o /dev/null -w "%{http_code}" -H "$AUTH" -X PUT "$CTRL/proxies/$(enc "$1")" -H 'Content-Type: application/json' -d "{\"name\":\"$2\"}" 2>/dev/null)
  [ "$_code" = "204" ] && grp_invalidate "$1"
  printf '%s' "$_code"
}

# ---- 运行模式 ---------------------------------------------------------------
# run（默认）: 检测 + 最小化修复
# dry        : 只记录 WOULD-FIX，不调用任何 put（改策略组前先试跑）
# status     : 只读体检，打印各组出口 / 内存 / tmpfs / nft，不取锁、不写日志
MODE=run
case "${1:-}" in
  --dry-run) MODE=dry ;;
  --status)  MODE=status ;;
  -h|--help)
    printf 'usage: %s [--dry-run|--status]\n' "$0"
    printf '  --dry-run  只记录 WOULD-FIX，不切换任何策略组\n'
    printf '  --status   只读打印当前状态（不取锁、不写日志）\n'
    exit 0 ;;
  '') ;;
  *) printf 'usage: %s [--dry-run|--status]\n' "$0" >&2; exit 2 ;;
esac
# 环境变量只在默认模式下生效：--status 是只读体检，被降级成 dry 会去取锁、
# 改策略组，与 usage 承诺相反。
[ "$MODE" = "run" ] && [ "${GUARDIAN_DRY_RUN:-0}" = "1" ] && MODE=dry

# ---- H1/M1: dry-run 状态隔离（预演绝不覆盖生产状态文件）------------------------
# --status 与 health-snapshot.sh --json 把 guardian.state / .clean_verdict /
# .clean_node 当「现状」读；dry 轮若写这些文件，预演假设就被当成真实现状。
# 这里让 dry 轮只读写 .dry 副本（verdict/cache 干脆不写，见下方守卫），生产
# 路径一个字节都不碰。STATE_FILE 统一收口收尾写入。
STATE_FILE=/tmp/ShellCrash/guardian.state
if [ "$MODE" = "dry" ]; then
  CLEAN_VERDICT_FILE=/tmp/ShellCrash/.clean_verdict.dry
  CLEAN_CACHE=/tmp/ShellCrash/.clean_node.dry
  STATE_FILE=/tmp/ShellCrash/guardian.dry.state
fi

# 缓存文件在参数解析之后才建：--help / 非法参数提前 exit，不该在 tmpfs 留空文件。
: > "$GRP_CACHE_FILE" 2>/dev/null

# 同一时间只允许一个实例：3.6 逐个候选探测最坏要跑两分多钟，加上 3.5 与第 1 节
# 的等待，整轮可能超过 cron 的 5 分钟；叠轮会让两轮同时切策略组、同时写
# .clean_node / .clean_verdict，日志记录与实际生效节点对不上。
# 锁形状照抄 bulk-guard.sh：mkdir 原子建锁 + pid/ts + 过期回收 + trap 清理。
GUARDIAN_LOCK=/tmp/ShellCrash/guardian.lock
acquire_lock() {
  _now=$(date +%s)
  if [ -d "$GUARDIAN_LOCK" ]; then
    _lp=$(cat "$GUARDIAN_LOCK/pid" 2>/dev/null)
    _lt=$(cat "$GUARDIAN_LOCK/ts" 2>/dev/null)
    case "$_lt" in ''|*[!0-9]*) _lt=0 ;; esac
    if [ -n "$_lp" ] && kill -0 "$_lp" 2>/dev/null && [ $((_now - _lt)) -lt 600 ]; then
      log "另一实例在跑（pid=$_lp），跳过本轮"
      exit 0
    fi
    rm -f "$GUARDIAN_LOCK/pid" "$GUARDIAN_LOCK/ts" 2>/dev/null
    rmdir "$GUARDIAN_LOCK" 2>/dev/null
  fi
  mkdir "$GUARDIAN_LOCK" 2>/dev/null || { log "无法取得实例锁，跳过本轮"; exit 0; }
  echo $$ > "$GUARDIAN_LOCK/pid"
  echo "$_now" > "$GUARDIAN_LOCK/ts"
  trap 'rm -f "$GUARDIAN_LOCK/pid" "$GUARDIAN_LOCK/ts" 2>/dev/null; rmdir "$GUARDIAN_LOCK" 2>/dev/null; rm -f "$GRP_CACHE_FILE" "$GRP_CACHE_FILE.new" 2>/dev/null' EXIT INT TERM HUP
}
[ "$MODE" = "status" ] || acquire_lock

# 节点到 Google 的实链路探测：有 delay 字段就算可达。
# 干净出口只服务 Google 家族；GitHub 由 🔗 GitHub 出口 组自行 url-test（2026-10-22 拆组）。
node_alive() {
  $CURL -s -m 8 -H "$AUTH" "$CTRL/proxies/$(enc "$1")/delay?timeout=5000&url=$(echo "$CL_ALIVE_URL" | sed "s|:|%3A|g;s|/|%2F|g")" 2>/dev/null | grep -q '"delay"'
}

in_clean_list() {
  _oldifs="$IFS"; IFS="|"
  for _c in $CLEAN_CANDIDATES; do
    if [ "$_c" = "$1" ]; then IFS="$_oldifs"; return 0; fi
  done
  IFS="$_oldifs"
  return 1
}

# 解析本轮唯一的干净出口，全脚本只认这一个结果（2.1 / 2.3 / 3.6 共用），
# 避免各段各自挑节点导致每 5 分钟互相切换。优先级：
#   1) 当前入口在候选里、在组内且 Google 可达 → 保持不动（稳定优先，HY2 恢复也不主动切回）；
#   2) 上次扫描已判定「全挂」且未到重试时间 → 不再重复扫，直接保持当前；
#   3) 按候选顺序找第一个「在组内且可达」的；
#   4) 全挂 → 返回当前入口，并把 verdict=0 写盘，由 2.3 告警。
# 「在组内」校验必须有：delay API 对任意已知节点都能测（哪怕不在组里），
# 但 put 只接受组内成员 —— 2026-10-23 台湾-优化2-GPT 可达却在组外，解析成它
# 之后 2.1 每轮 put 必失败，韩国就这样多留了一小时。
# 探测结论写到 CLEAN_VERDICT_FILE：1=有可达入口，0=全部不可达。2.3 直接复用，
# 不再二次探测 —— 节点到 Google 是间歇性抖动的，连探两次会得出相反结论。
resolve_clean_node() {
  _cur=$(grp "$CL")
  _members=$($CURL -s -m 5 -H "$AUTH" "$CTRL/proxies/$(enc "$CL")" 2>/dev/null \
    | sed -n 's/.*"all":\[\([^]]*\)\].*/\1/p' | tr ',' '\n' | sed 's/^"//;s/"$//')
  if [ -n "$_cur" ] && in_clean_list "$_cur" && echo "$_members" | grep -Fxq "$_cur" && node_alive "$_cur"; then
    [ "$MODE" != "dry" ] && echo 1 > "$CLEAN_VERDICT_FILE" 2>/dev/null
    [ "$MODE" != "dry" ] && echo "$(date +%s) $_cur" > "$CLEAN_CACHE" 2>/dev/null
    echo "$_cur"
    return
  fi
  if [ -f "$CLEAN_CACHE" ] && [ "$(cat "$CLEAN_VERDICT_FILE" 2>/dev/null)" = "0" ]; then
    _ts=0; _node=""
    read -r _ts _node < "$CLEAN_CACHE" 2>/dev/null
    case "$_ts" in ''|*[!0-9]*) _ts=0 ;; esac
    if [ $(( $(date +%s) - _ts )) -lt "$CLEAN_RETRY" ]; then
      echo "$_cur"
      return
    fi
  fi
  _oldifs="$IFS"; IFS="|"
  for _cand in $CLEAN_CANDIDATES; do
    if echo "$_members" | grep -Fxq "$_cand" && node_alive "$_cand"; then
      IFS="$_oldifs"
      [ "$MODE" != "dry" ] && echo 1 > "$CLEAN_VERDICT_FILE" 2>/dev/null
      [ "$MODE" != "dry" ] && echo "$(date +%s) $_cand" > "$CLEAN_CACHE" 2>/dev/null
      echo "$_cand"
      return
    fi
  done
  IFS="$_oldifs"
  [ "$MODE" != "dry" ] && echo 0 > "$CLEAN_VERDICT_FILE" 2>/dev/null
  [ "$MODE" != "dry" ] && echo "$(date +%s) $_cur" > "$CLEAN_CACHE" 2>/dev/null
  echo "$_cur"
}

# 被 Google 判为 CN 的节点（实测清单）。台湾-优化3 / 台湾-优化2-GPT 例外，见顶部 CLEAN_CANDIDATES。
# 2026-10-22：机场的 vmess 池（xiaoyan/mobgslb 三条入口，含全部印度节点）全部判 cc=CN，
#   新出现的 Hysteria2 池（*.mjhy2.com）实测 4 个节点全部 cc=SG —— 它们是干净出口。
is_bad_node() {
  case "$1" in
    *-HY2*) return 1 ;;
    *台湾-优化3*|*台湾-优化2-GPT*) return 1 ;;
    # 印度已从坏节点清单移除：2026-10-23 实测「印度-优化」cc=IN，且是
    # CLEAN_CANDIDATES 的兜底项；继续判坏会让 2.1 与候选解析互相扳动。
    *日本-优化*|*台湾-优化*|*美国LA-优化*|*新加坡-优化*|*香港-优化*|*香港WAP-优化*|*德国-优化*|*加拿大-优化*|*英国-优化*|*过滤掉14条线路*|*过滤掉10条线路*) return 0 ;;
  esac
  return 1
}
# 通用池只拦香港：OpenAI 对香港WAP×3 直接 403 unsupported_country_region_territory，
# 其余地区对通用流量无害（各家自报真实国家），且 Google 流量已全部隔离到干净出口。
is_hk_only() {
  case "$1" in
    *香港*|*HK*|*Hong*Kong*) return 0 ;;
  esac
  return 1
}
# 韩国出口对 Google 生态不可用：韩国对成人内容强制年龄验证，Google 按出口 IP
# 国家执行，搜索即弹「19 岁验证」且只认韩国手机号。is_bad_node 豁免全部 HY2
# （对 AI 干净），韩国 HY2 要在这里单独拦 —— 2.1 据此把落在韩国的组扳走。
is_kr_node() {
  case "$1" in
    *韩国*|*🇰🇷*) return 0 ;;
  esac
  return 1
}

eff_node() {
  n=$(grp "$1")
  [ -z "$n" ] && return 0
  case "$n" in
    "🚀 手动切换") grp "🚀 手动切换" ;;
    *) echo "$n" ;;
  esac
}

# ---- --status：只读体检（不取锁、不写日志、不切换）--------------------------
# 给「动手之前先看一眼」用：一次拿到全部关键组出口 + 内存 + tmpfs + nft 表，
# 不必再 tail 三个日志文件拼状态。组状态走 grp() 的缓存，每组只问一次。
if [ "$MODE" = "status" ]; then
  _NFT=${NFT:-nft}
  printf 'mode=status ts=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf 'api=%s secret=%s\n' "$CTRL" "$([ -n "$SECRET" ] && echo set || echo MISSING)"
  for _g in "$AI_GROUP" "$AI_WEB" "$CL" "$POOL_GROUP" "${AI_API_GROUP:-🤖 AI接口}"; do
    printf 'group[%s] now=%s eff=%s\n' "$_g" "$(grp "$_g")" "$(eff_node "$_g")"
  done
  printf 'clean_verdict=%s clean_cache=%s\n' \
    "$(cat "$CLEAN_VERDICT_FILE" 2>/dev/null || echo '?')" \
    "$(cat "$CLEAN_CACHE" 2>/dev/null || echo '?')"
  printf 'mem_avail_mb=%s\n' "$(awk '/^MemAvailable/{print int($2/1024)}' /proc/meminfo 2>/dev/null)"
  printf 'tmp=%s\n' "$(df -k /tmp 2>/dev/null | tail -1 | awk '{printf "%sK/%sK (%d%%)", $3, $2, ($2>0?$3*100/$2:0)}')"
  for _t in quicguard googleroute googlecn mixedport; do
    if $_NFT list table inet "$_t" >/dev/null 2>&1; then printf 'nft[%s]=loaded\n' "$_t"
    else printf 'nft[%s]=MISSING\n' "$_t"; fi
  done
  printf 'state=%s\n' "$(cat /tmp/ShellCrash/guardian.state 2>/dev/null || echo '<none>')"
  # status 不取锁（没有 trap），缓存文件自己收
  rm -f "$GRP_CACHE_FILE" "$GRP_CACHE_FILE.new" 2>/dev/null
  exit 0
fi

# 秒数比较用数值，不用 case glob —— "10.0" / "12.5" 这类带小数点的
# 两位数以上耗时不会命中 "3.*|4.*|…" 那套模式，判据会被静默跳过。
ge_sec() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0 >= b+0)}'; }

if [ "$MODE" != "dry" ] && [ -f "$LOG" ]; then
  SZ=$(wc -c < "$LOG" 2>/dev/null || echo 0)
  [ "$SZ" -gt 204800 ] && { tail -60 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; }
fi

# ---------- 1) mihomo 存活（OOM 会被内核杀掉；服务关闭会清 pid 文件，故用"最近活着"状态文件兜底） ----------
if $CURL -s -m 5 -H "$AUTH" "$CTRL/version" >/dev/null 2>&1; then
  [ "$MODE" != "dry" ] && date +%s > "$ALIVEF" 2>/dev/null
else
  if pidof CrashCore >/dev/null 2>&1; then
    log "WARN: CrashCore 进程在但 API 无响应（可能正在热重载），本次不动作"
  else
    LAST=$(cat "$ALIVEF" 2>/dev/null || echo 0)
    NOWT=$(date +%s)
    if [ -f "$PIDFILE" ] || [ $((NOWT - LAST)) -lt 1800 ]; then
      # ---- U15 memory gate (helper: /etc/ShellCrash/memgate.sh) ----
      # OOM-kill -> relaunch -> re-fill /tmp (RAM tmpfs) -> OOM -> hard reset.
      # memgate.sh check: exit 0 = allow, exit 1 = blocked (it writes the WARNING
      # itself to syslog and to .../logs/memgate.log, size capped).
      _memgate_rc=0
      if [ -f /etc/ShellCrash/memgate.sh ]; then
        # dry-run 不能真跑 check：它会往闪存 memgate.log 追加、并累加
        # /tmp/ShellCrash/.memgate_block_count，把生产计数器推向 FORCE_AFTER。
        if [ "$MODE" = "dry" ]; then
          log "FIX: 内存闸门本应执行 /etc/ShellCrash/memgate.sh check（dry-run 跳过：不写 memgate.log、不动拦截计数）"
        else
          /etc/ShellCrash/memgate.sh check
          _memgate_rc=$?
        fi
      else
        # memgate.sh missing -> fail open (pre-U15 behaviour), warn once per boot
        if [ ! -f /tmp/ShellCrash/.memgate_missing_warned_guardian ]; then
          log "WARN: /etc/ShellCrash/memgate.sh 不存在，本轮无内存闸门保护地拉起 CrashCore"
          [ "$MODE" != "dry" ] && touch /tmp/ShellCrash/.memgate_missing_warned_guardian 2>/dev/null
        fi
      fi
      if [ "$_memgate_rc" -eq 1 ]; then
        log "WARN: 可用内存不足，memgate 拦截本轮拉起（详见 /etc/ShellCrash/logs/memgate.log）；内存恢复后由下一轮 cron 重试"
      else
        if [ "$MODE" = "dry" ]; then
          log "FIX: CrashCore 进程不存在，本应执行 /etc/ShellCrash/start.sh start 拉起（dry-run 跳过：不重启、不 sleep 12s）"
        else
          log "ALERT: CrashCore 进程不存在（可能是 OOM 被杀），用 start.sh 拉起"
          /bin/ash /etc/ShellCrash/start.sh start >> "$LOG" 2>&1
          sleep 12
          if $CURL -s -m 5 -H "$AUTH" "$CTRL/version" >/dev/null 2>&1; then
            log "FIX: CrashCore 已恢复"
          else
            log "ERROR: CrashCore 拉起后仍无响应，需人工介入"
          fi
        fi
      fi
    else
      log "INFO: CrashCore 已停止且近 30 分钟无存活记录（判定为人为停止），守护不做拉起，不妨碍维护"
    fi
  fi
fi

# ---------- 2) AI 组出口必须干净 ----------
AI_NOW=$(grp "$AI_GROUP")
if [ -n "$AI_NOW" ]; then
  AI_EFF=$(eff_node "$AI_GROUP")
  if is_bad_node "$AI_EFF"; then
    if [ "$(put "$AI_GROUP" "$AI_WEB")" = "204" ]; then
      log "FIX: $AI_GROUP 从「$AI_NOW」(实际出口「$AI_EFF」) 复原为「$AI_WEB」（该出口被 Google 判为 CN）"
    else
      log "ERROR: 切回 $AI_WEB 失败（控制 API 拒绝）"
    fi
  fi
fi

# ---------- 2.4) AI API 数据面探活（🤖 AI接口）----------
# url-test 的健康检查打的是 https://opencode.ai/ 根路径；根路径通了不代表 API
# 路径能用。2026-10-27 实测该组选中的「🇺🇸 美国LA-优化-GPT」面板 alive、探活
# 也过，但 /zen/go/v1/models 与根路径同时死 —— zgate 侧表现为 TLS 握手超时
# （15s）后 502，回落 WorkBuddy 免费池再撞 429，一次回复拖到 22–32s。
# 这里只「检测 + 告警」，不切组：🤖 AI接口 是 url-test，put 会写 fixed 把自动
# 选路永久钉死；重选交给 interval（已从默认 300s 调到 60s，最多 1 分钟）。
AI_API_GROUP="${AI_API_GROUP:-🤖 AI接口}"
AI_API_PROBE="${AI_API_PROBE:-https://opencode.ai/zen/go/v1/models}"
AI_API_NOW=$(grp "$AI_API_GROUP")
if [ -n "$AI_API_NOW" ]; then
  # 不带 key：401/403 也证明 TLS 与 HTTP 链路通，只有 000（超时/握不上）才算坏
  AI_API_R=$($CURL -s -m 10 -o /dev/null -w "%{http_code} %{time_total}" -x "$PROXY" "$AI_API_PROBE" 2>/dev/null)
  case "${AI_API_R%% *}" in
    000|'') log "WARN: $AI_API_GROUP 数据面不可达（当前节点「$AI_API_NOW」，$AI_API_PROBE 无响应）；url-test 下一轮复测应自动换节点" ;;
  esac
fi

# ---------- 2.1) AI网页 / 干净出口 锁到同一个干净节点 ----------
# 目标节点每轮只解析一次（resolve_clean_node）：当前入口在候选里且可达就不动，
# 否则按候选顺序找第一个可达的。判定条件是「判 CN 的坏节点 或 Google 不可达
# 或落在韩国（成人内容强制年龄验证）」，死节点也在这里被换掉，不再依赖 2.3 事后补救。
CLEAN_NODE=$(resolve_clean_node)
if [ -z "$CLEAN_NODE" ]; then
  log "WARN: 无法解析干净出口（控制 API 无响应或候选全挂），本轮跳过 2.1/2.2"
else
  for g in "$AI_WEB" "$CL"; do
    NOW=$(grp "$g")
    if [ -n "$NOW" ] && [ "$NOW" != "$CLEAN_NODE" ] && { is_bad_node "$NOW" || ! node_alive "$NOW" || is_kr_node "$NOW"; }; then
      if [ "$(put "$g" "$CLEAN_NODE")" = "204" ]; then
        log "FIX: $g 从「$NOW」切到干净出口「$CLEAN_NODE」"
      else
        log "ERROR: $g 切到 $CLEAN_NODE 失败"
      fi
    fi
  done
fi

# ---------- 2.2) AI网页组与干净出口必须用同一个入口 ----------
# 两者是同一批印度节点，但组成员会各自漂移。三条入口共用同一出口 IP，
# 所以对齐入口不会改变会话 IP，只是让链路保持一致（p6 入口对大页面会吞吐塌陷）。
CL_NOW=$(grp "$CL")
AW_NOW=$(grp "$AI_WEB")
if [ -n "$CL_NOW" ] && [ -n "$AW_NOW" ] && [ "$CL_NOW" != "$AW_NOW" ]; then
  if [ "$(put "$AI_WEB" "$CL_NOW")" = "204" ]; then
    log "FIX: AI网页组入口「$AW_NOW」与干净出口「$CL_NOW」不一致，已对齐（同一出口 IP）"
  else
    log "ERROR: AI网页组对齐失败（控制 API 拒绝）"
  fi
fi

# ---------- 2.3) 干净出口结果校验（CLEAN_EXIT_ALIVE）----------
# 切换已在 2.1 完成（目标节点就是解析出的可达节点），这里只校验结果：
# 如果最终入口仍不可达，说明候选全挂，必须显式告警。
# 历史：入口域名被 GSLB 轮到死后端时，Google 全族会在 TLS 握手阶段 5 秒超时，
# 而 Gemini 可能仍然打得开 —— 3.6 的吞吐探测抓不到这种情况，所以单独校验。
CL_NOW=$(grp "$CL")
CLEAN_OK=$(cat "$CLEAN_VERDICT_FILE" 2>/dev/null || echo 1)
if [ -n "$CL_NOW" ] && [ "$CLEAN_OK" != "1" ]; then
  log "ALERT: 干净出口候选入口全部不可达（当前入口「$CL_NOW」），Gemini/Google 可能打不开"
fi

# ---------- 3) 通用池：只有落在坏节点清单里才复位 ----------
NODE_NOW=$(grp "$POOL_GROUP")
if [ -n "$NODE_NOW" ]; then
  NODE_EFF=$(eff_node "$POOL_GROUP")
  if is_hk_only "$NODE_EFF"; then
    if [ "$(put "$POOL_GROUP" "$POOL_FALLBACK_GROUP")" = "204" ]; then
      log "FIX: 🚀 节点选择 从「$NODE_NOW」(实际出口「$NODE_EFF」) 复原为「♻️ 自动选择」"
    else
      log "ERROR: 切回 ♻️ 自动选择 失败"
    fi
  fi
fi

# ---------- 3.5) 通用出口健康守卫（EXIT_HEALTH）----------
# 通用池的节点会劣化（实测德国节点从 5s 恶化到 15s，表现为全站超时）。
# 这里按真实出口耗时判定：超过 3 秒就复位到「♻️ 自动选择」（url-test 会挑最快的节点）。
# 幂等前置：3.5 唯一的动作是把池复位到「♻️ 自动选择」。池已经是它时，探测与
# 复位都不产生任何状态变化 —— 直接跳过两次出口探测（最坏省 24s 与 2 个 curl）。
POOL_EFF=$(eff_node "$POOL_GROUP")
if [ "$POOL_EFF" = "$POOL_FALLBACK_GROUP" ]; then
  :
else
P1=$($CURL -s -m 12 -o /dev/null -w "%{http_code} %{time_total}" -x "$PROXY" "https://api.ipify.org" 2>/dev/null)
P2=$($CURL -s -m 12 -o /dev/null -w "%{http_code} %{time_total}" -x "$PROXY" "https://api.ipify.org" 2>/dev/null)
if [ -n "$P1" ] && [ -n "$P2" ]; then
  # 两次探测取较慢那次；取 max 后不能再除 2（除 2 会把阈值整体压低一半）。
  MS=$(echo "$P1 $P2" | awk '{t=($2>$4?$2:$4)} END{printf "%.1f", t}')
  BAD=0
  # 节点被封/被拒时常表现为"快速失败"（502/连接被拒），只看耗时会把
  # 它误判为健康；非 2xx/3xx 一律按劣化处理。
  case "${P1%% *}" in 2*|3*) ;; *) BAD=1 ;; esac
  case "${P2%% *}" in 2*|3*) ;; *) BAD=1 ;; esac
  if [ "$BAD" = "1" ] || ge_sec "$MS" 3; then
    if [ "$(put "$POOL_GROUP" "$POOL_FALLBACK_GROUP")" = "204" ]; then
      log "FIX: 通用出口劣化（HTTP ${P1%% *}/${P2%% *}，耗时 ${MS}s，阈值 3s），复位为「♻️ 自动选择」"
    else
      log "ERROR: 通用出口复位失败（控制 API 拒绝）"
    fi
  fi
fi
fi

# ---------- 3.6) 干净出口健康守卫（CLEAN_EXIT_HEALTH）----------
# 干净出口（印度）会间歇性劣化。实测（2026-10-20）：
#   - 机场订阅给的印度入口（<YOUR-NODE-SERVER>）到 gemini.google.com（784KB）
#     偶发吞吐塌陷，耗时 22s / 25s 超时；但小响应的 API 端点始终 0.9s ——
#     所以健康探测必须用真实页面，用 API 端点抓不到这个长尾。
#   - 自建的 m2 / ct2 两个入口（与订阅同端口同 Host）实测稳定在 1.5-1.8s。
#   - 2026-10-21：该出口已变成轮换池（TW/CN 跳变），见下方候选说明。
#     切入口不换 IP、只换链路，对已登录的 Google 会话无感。
# 2026-10-21 复测：机场的 Google 落地不再是恒定印度 IP，而是在 TW/CN 间轮换；
# 30 个节点里只有台湾-优化3 / 台湾-优化2-GPT 能出 cc=TW；候选改为台湾优先、印度兜底。
# 2026-10-22：上述 vmess 池 5 个候选全部判 cc=CN（含手机同款「新加坡-优化3」）；
# 机场新给的 Hysteria2 池 4 个节点全部 cc=SG，故候选改为 HY2 优先。
# 候选统一用顶部的 CLEAN_CANDIDATES，和 2.1 共用同一份优先级，不再各自维护。
CL_PROBE_URL="https://gemini.google.com/"

clean_exit_ms() {
  C1=$($CURL -s -m 15 -o /dev/null --max-filesize 131072 -w "%{http_code} %{time_total}" -x "$PROXY" "$CL_PROBE_URL" 2>/dev/null)
  C2=$($CURL -s -m 15 -o /dev/null --max-filesize 131072 -w "%{http_code} %{time_total}" -x "$PROXY" "$CL_PROBE_URL" 2>/dev/null)
  [ -z "$C1" ] && [ -z "$C2" ] && { echo "99"; return; }
  # 同上：非 2xx/3xx 直接按劣化处理，避免"快速失败"被当成健康。
  case "${C1%% *}" in 2*|3*) ;; *) echo "99"; return ;; esac
  case "${C2%% *}" in 2*|3*) ;; *) echo "99"; return ;; esac
  echo "$C1 $C2" | awk '{t=($2>$4?$2:$4)} END{printf "%.1f", t}'
}
clean_exit_bad() {
  MS=$(clean_exit_ms)
  ge_sec "$MS" 4
}
CUR_CL=$(grp "$CL")
if [ -n "$CUR_CL" ] && clean_exit_bad; then
  FIXED=""
  OLDIFS="$IFS"; IFS="|"
  for cand in $CLEAN_CANDIDATES; do
    [ "$cand" = "$CUR_CL" ] && continue
    node_alive "$cand" || continue
    [ "$(put "$CL" "$cand")" = "204" ] || continue
    [ "$MODE" != "dry" ] && sleep 3
    if ! clean_exit_bad; then
      FIXED="$cand"; break
    fi
  done
  IFS="$OLDIFS"
  if [ -n "$FIXED" ]; then
    put "$AI_WEB" "$FIXED" >/dev/null 2>&1
    [ "$MODE" != "dry" ] && echo 1 > "$CLEAN_VERDICT_FILE" 2>/dev/null
    [ "$MODE" != "dry" ] && echo "$(date +%s) $FIXED" > "$CLEAN_CACHE" 2>/dev/null
    log "FIX: 干净出口劣化（当前入口「$CUR_CL」），已换到「$FIXED」（同一出口 IP，不影响会话）；AI网页组同步"
  else
    [ "$CUR_CL" != "$(grp "$CL")" ] && put "$CL" "$CUR_CL" >/dev/null 2>&1
    log "ALERT: 干净出口候选入口全部劣化（已保持「$CUR_CL」），Gemini 可能打不开"
  fi
fi

# ---------- 4) nft 表补载 ----------
for t in quicguard googleroute googlecn; do
  if ! $NFT list table inet $t >/dev/null 2>&1; then
    if [ -f "/etc/$t.nft" ] && $NFT -f "/etc/$t.nft" >/dev/null 2>&1; then
      log "FIX: nft 表 inet $t 缺失，已从 /etc/$t.nft 重载"
    else
      log "ERROR: nft 表 inet $t 缺失且重载失败"
    fi
  fi
done

# ---------- 5) 静默回退自愈 ----------
# -F：组名里有 emoji 与空格，一旦将来带上 . * [ 之类字符，正则匹配会误判
# 「配置里没有这个组」→ 误触发一次 hotupdate 重生成（闪存写 + 组序被打乱）。
if ! grep -qF "name: $AI_WEB" /tmp/ShellCrash/config.yaml 2>/dev/null; then
  LASTF=/tmp/ShellCrash/.last_fallback_heal
  NOWT=$(date +%s)
  PREV=$(cat $LASTF 2>/dev/null || echo 0)
  if [ $((NOWT - PREV)) -gt 1800 ]; then
    if [ "$MODE" = "dry" ]; then
      log "FIX: 运行配置缺 $AI_WEB 组，本应重跑 task.sh hotupdate 重新生成（dry-run 跳过：不写 LASTF、不 hotupdate）"
    else
      echo $NOWT > $LASTF
      log "FIX: 运行配置缺 $AI_WEB 组（疑为回退基础配置），重跑 hotupdate 重新生成"
      /bin/ash /etc/ShellCrash/task/task.sh hotupdate >> "$LOG" 2>&1
    fi
  else
    log "WARN: 运行配置缺 $AI_WEB 组（疑为回退基础配置），30 分钟限频内不重复重生成"
  fi
fi

# ---------- 6) 探活与内存水位（内存不足是 OOM 根因，必须盯） ----------
# Google 侧地区判定探测：support.google.com 的 cc 变量在页面 1MB 之后，整页 1.6MB，
# 所以每 60 分钟探一次（全天约 23MB），不要每 5 分钟拉一次。
# cc 只有 CN / HK 会让 Gemini 直接报「不支持此国家」；2026-10-22 起干净出口
# 走 Hysteria2 池（实测 cc=SG），所以不再要求必须是 IN。
CCF=/tmp/ShellCrash/.cc_probe_ts
NOWT2=$(date +%s)
LASTF2=$(cat "$CCF" 2>/dev/null || echo 0)
if [ $((NOWT2 - LASTF2)) -ge 3600 ]; then
  [ "$MODE" != "dry" ] && echo $NOWT2 > "$CCF"
  CC=$($CURL -s -m 20 -x "$PROXY" "https://support.google.com/gemini/answer/13575153" 2>/dev/null | grep -oE "var cc=.[A-Z]{2}" | head -1 | sed "s/var cc=.//")
  if [ -n "$CC" ]; then
    case "$CC" in
      CN|HK) log "ALERT: Google 把干净出口判为 cc=$CC（Gemini 不支持该地区），需切到 HY2 节点" ;;
      *) log "INFO: Google 侧出口判定 cc=$CC（干净出口可用）" ;;
    esac
  else
    log "WARN: Google 侧 cc 探测未取到结果（页面 1.6MB 未下完或节点超时）"
  fi
fi
AVAIL=$(awk '/^MemAvailable/{print int($2/1024)}' /proc/meminfo 2>/dev/null)
[ -n "$AVAIL" ] && [ "$AVAIL" -lt 30 ] && log "WARN: 可用内存仅 ${AVAIL}MB（低于 30MB 阈值，注意 OOM 风险）"

# /tmp 是内存盘（116MB），一旦被写满会连锁 OOM：先杀 CrashCore，再触发 mtk-wdt 看门狗整机重启。
# 实测（2026-10-20 12:45）：升级内核时 gunzip 57MB 核心进 /tmp，tmpfs 占用冲到 99%，
# 核心被杀、路由器重启，重启后 DNS 劫持指向没起来的核心 → 全家「连上 WiFi 但没网」。
# 所以这里每 5 分钟看一眼水位，超 80% 就把已知的临时大文件清掉。
# 一次 df 取两个数：原来是两条 df|tail|awk（6 个进程），现在一条（3 个进程）。
# 不用 set --：那会把脚本自己的位置参数（$1）覆盖成 df 的列，后续任何
# 用到 $1 的地方都会读到容量数字。
_df=$(df -k /tmp 2>/dev/null | tail -1 | awk '{print $2" "$3}')
case "$_df" in
  *" "*) TMPT=${_df%% *}; TMPK=${_df##* } ;;
  *) TMPT=; TMPK= ;;
esac
if [ -n "$TMPK" ] && [ -n "$TMPT" ] && [ "$TMPT" -gt 0 ]; then
  TMPP=$((TMPK * 100 / TMPT))
  if [ "$TMPP" -ge 80 ]; then
    log "WARN: /tmp 内存盘已用 ${TMPP}%（${TMPK}K/${TMPT}K），接近撑爆会 OOM 并触发看门狗重启"
    # 清理逻辑优先委托 tmp-watch.sh（单点实现）：它有白名单 / 保护名单 /
    # 被打开 fd 检查 / 每轮 64 文件 8MB 配额，比这里的固定列表更懂哪些能删。
    # 委托后仍超线，才退回固定列表兜底（大文件不在白名单里时它不会碰）。
    if [ "$MODE" != "dry" ] && [ -x /etc/router-health/tmp-watch.sh ]; then
      TMPWATCH_PURGE=1 /bin/ash /etc/router-health/tmp-watch.sh >/dev/null 2>&1 \
        && log "FIX: 已委托 tmp-watch.sh 清理 /tmp（触发水位 ${TMPP}%）"
    fi
    TMPK2=$(df -k /tmp 2>/dev/null | tail -1 | awk '{print $3}')
    TMPP2=$(( ${TMPK2:-0} * 100 / TMPT ))
    if [ "$TMPP2" -ge 80 ]; then
      for f in /tmp/pre-reboot-config.tar.gz /tmp/m132 /tmp/m132.gz /tmp/scmeta.tar.gz \
               /tmp/sc-meta.tar.gz /tmp/mihomo-new /tmp/mihomo-arm64.gz /tmp/core_test_out.txt \
               /tmp/_core_test.sh /tmp/gpage.html /tmp/g2.html /tmp/g4.html /tmp/g5.html /tmp/pt.html \
               /tmp/sub.raw /tmp/sub.txt /tmp/sub2.txt; do
        [ -e "$f" ] && { [ "$MODE" != "dry" ] && rm -rf "$f" 2>/dev/null; log "FIX: 已清理 /tmp 临时大文件 $f"; }
      done
      TMPK2=$(df -k /tmp 2>/dev/null | tail -1 | awk '{print $3}')
    fi
    log "INFO: /tmp 清理后占用 ${TMPK2}K/${TMPT}K"
  fi
fi

# cron lifeline: start.sh stop 会重写 crontab 并删掉 legacy 看门狗行,
# 这里每 5 分钟检查一次, 缺失就补回 (2026-10-20 事故)
# 追加 cron 行并去重：grep -q 之后直接 >> 不是原子操作，start.sh 重写 crontab 与
# 本脚本追加交错时会出现重复行 —— 每分钟跑两份 legacy 看门狗 = 双 CrashCore =
# OOM 与断网（AGENTS 硬红线）。这里写临时文件去重后 mv 覆盖，再 crontab 重载。
#
# 2026-11-25 加固（审查 P1-A），四条一起改，缺一条都不安全：
#   1) 临时文件放 /etc/crontabs 同盘：跨 tmpfs(/tmp) → overlay(/etc) 的 mv 是
#      copy+unlink，断电/写满会留下截断的 crontab（2026-11-04 整表清空事故）。
#   2) 旧内容先读进变量并检查 cat 的退出码。写成 { cat; printf; } | awk 时管道
#      状态取的是 awk 的，cat 失败会被掩码，结果「只剩新加那一行」被当成完整表装回去。
#   3) 合并结果要校验：非空、行数不少于旧表的去重行数；不满足就放弃覆盖并记 ERROR。
#   4) 覆盖后归一 600 root:root，并检查 crontab 重载的返回码（原实现都没做）。
cron_ensure() {
  # H1: dry-run 零副作用 —— 不写 /etc/crontabs/root、不重载 crontab。
  # 返回 0 让调用方照常记一条 WOULD-FIX（log() 负责 FIX→WOULD-FIX 改写）。
  [ "$MODE" = "dry" ] && return 0
  _pat="$1"; _line="$2"; _f=/etc/crontabs/root
  grep -qF "$_pat" "$_f" 2>/dev/null && return 0
  # 同盘临时文件：mv 才是 rename（原子）。点开头不会被当作用户名加载。
  _tmp=/etc/crontabs/.root.new.$$
  _oldtxt=""
  if [ -f "$_f" ]; then
    _oldtxt=$(cat "$_f" 2>/dev/null) || { log "ERROR: 读 $_f 失败，放弃补 cron 行（$_pat）"; return 1; }
  fi
  # 旧表的去重行数：合并后至少要保住这么多行（旧表里的重复行允许被合并掉）
  _need=0
  if [ -n "$_oldtxt" ]; then
    _need=$(printf '%s\n' "$_oldtxt" | awk '!seen[$0]++' | wc -l)
    case "$_need" in ''|*[!0-9]*) _need=0 ;; esac
  fi
  {
    [ -n "$_oldtxt" ] && printf '%s\n' "$_oldtxt"
    printf '%s\n' "$_line"
  } | awk '!seen[$0]++' > "$_tmp" 2>/dev/null
  _arc=$?
  if [ "$_arc" -ne 0 ]; then
    rm -f "$_tmp"
    log "ERROR: 合并 crontab 失败（awk rc=$_arc），未覆盖 $_f"
    return 1
  fi
  _new=$(wc -l < "$_tmp" 2>/dev/null)
  case "$_new" in ''|*[!0-9]*) _new=0 ;; esac
  if [ ! -s "$_tmp" ] || [ "$_new" -lt 1 ] || [ "$_new" -lt "$_need" ]; then
    rm -f "$_tmp"
    log "ERROR: crontab 合并结果异常（新 $_new 行 / 旧需 $_need 行），放弃覆盖并保留原表"
    return 1
  fi
  # 覆盖前留一份旧表到 tmpfs：/etc/crontabs 下的多余文件会被 crond 当未知用户清掉
  cp -f "$_f" /tmp/ShellCrash/crontab.bak 2>/dev/null
  mv -f "$_tmp" "$_f" 2>/dev/null || { rm -f "$_tmp"; log "ERROR: 替换 $_f 失败"; return 1; }
  chmod 600 "$_f" 2>/dev/null
  chown root:root "$_f" 2>/dev/null
  crontab "$_f" 2>/dev/null \
    || { log "ERROR: crontab 重载失败（内容已写入 $_f，下轮重试；旧表副本 /tmp/ShellCrash/crontab.bak）"; return 1; }
  return 0
}
if ! grep -qF 'start_legacy_wd.sh' /etc/crontabs/root 2>/dev/null; then
    if cron_ensure 'start_legacy_wd.sh' '* * * * * /bin/ash /etc/ShellCrash/starts/start_legacy_wd.sh shellcrash #ShellCrash保守模式守护进程'; then
        log "FIX: restored legacy watchdog cron line"
    else
        log "ERROR: 补回 legacy watchdog cron 行失败（/etc/crontabs/root 不可写？）"
    fi
fi

# 流量归因采样（OpenwrtOpsToolkit/traffic-stats.sh）：这一行同样会被 start.sh
# stop / 订阅重写 crontab 冲掉 —— 2026-11-02 10:14 起停了 4 天到 11-06 才发现，
# 期间「机场流量被谁吃了」是空白。脚本不在就不补，免得每 5 分钟刷一条失败记录。
if [ -f /etc/ShellCrash/traffic-stats.sh ] && ! grep -qF 'traffic-stats.sh' /etc/crontabs/root 2>/dev/null; then
    if cron_ensure 'traffic-stats.sh' '* * * * * /bin/ash /etc/ShellCrash/traffic-stats.sh #流量归因:按策略组+域名每分钟采样'; then
        log "FIX: restored traffic-stats cron line"
    else
        log "ERROR: 补回 traffic-stats cron 行失败（/etc/crontabs/root 不可写？）"
    fi
fi

# 守护自己那一行：crontab 一旦被清空/截断，guardian 再也不会被 cron 拉起，
# 也就没有任何东西能把它补回来（2026-11-04 事故的终局形态：整表只剩一行）。
# 这里同样自愈，让「cron 全丢」至少能靠自身下一次运行救回来。
if ! grep -qF '/etc/ShellCrash/guardian.sh' /etc/crontabs/root 2>/dev/null; then
    if cron_ensure '/etc/ShellCrash/guardian.sh' '*/5 * * * * /bin/ash /etc/ShellCrash/guardian.sh #网络守护'; then
        log "FIX: restored guardian cron line"
    else
        log "ERROR: 补回 guardian 自身 cron 行失败（/etc/crontabs/root 不可写？）"
    fi
fi

# ---------- 收尾：写机器可读状态（tmpfs，不占闪存）----------
# 联动搭桥：health-snapshot.sh --json 会把这行并进结构化快照，
# 排查时不用再 tail 日志拼「这轮修了什么」。
# 多行 KV（一行一个键，值可含空格）：health-snapshot.sh --json 逐行读成 JSON 对象，
# 用单行空格分隔时含空格的节点名没法稳定切分。
{
  printf 'ts=%s\n' "$(date +%s)"
  printf 'mode=%s\n' "$MODE"
  printf 'fixes=%s\n' "$FIXES"
  printf 'errors=%s\n' "$ERRORS"
  printf 'warns=%s\n' "$WARNS"
  printf 'wouldfix=%s\n' "$WOULDFIX"
  printf 'mem_avail_mb=%s\n' "${AVAIL:-0}"
  printf 'tmp_pct=%s\n' "${TMPP:-0}"
  printf 'pool=%s\n' "$(eff_node "$POOL_GROUP")"
  printf 'ai_exit=%s\n' "$(grp "$AI_WEB")"
  printf 'clean_node=%s\n' "$(grp "$CL")"
} > "$STATE_FILE" 2>/dev/null
exit 0
