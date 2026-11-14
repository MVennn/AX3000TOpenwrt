#!/bin/sh
# 路由器健康快照 —— 定时把关键指标记到持久日志，便于事后回溯
# 用法: sh /etc/router-health/health-snapshot.sh [标签] [--json]
# 日志: /etc/router-health/health-YYYYMMDD.log（overlay 持久，重启不丢；保留 7 天）
# --json: 额外产出一行结构化 JSON（stdout + /tmp/router-health/health.json，tmpfs），
#         供面板 / 脚本直接消费；不改变默认行为（默认仍只追加一行 KV 到 flash 日志）。
#         联动：把 guardian.state 与 dest-guard.state 并进 guardian / dest_guard 两个子对象。

TAG=auto
JSON=0
for a in "$@"; do
  case "$a" in
    --json) JSON=1 ;;
    -h|--help)
      printf 'usage: %s [标签] [--json]\n' "$0"
      exit 0 ;;
    *) TAG="$a" ;;
  esac
done
DIR=/etc/router-health
SECRET=$(grep -m1 "^secret=" /etc/ShellCrash/configs/ShellCrash.cfg 2>/dev/null | cut -d= -f2- | tr -d "'\"")
CTRL=http://127.0.0.1:9999
API="Authorization: Bearer $SECRET"

mkdir -p "$DIR" 2>/dev/null
# 自愈: /var -> /tmp 的软链, 运行时目录被误删会让 dnsmasq 等服务起不来
# 只在真的建成功时才打日志 —— 原来无条件 echo, 只读根或 PC 上试跑会刷一屏「已重建」假日志
for d in etc lib run lock state spool shm tmp overlay sysinfo odhcpd-piodir resolv.conf.d log; do
  [ -d "/var/$d" ] && continue
  mkdir -p "/var/$d" 2>/dev/null && echo "[HEAL] recreated /var/$d"
done
LOG="$DIR/health-$(date +%Y%m%d).log"

# --- 保留清单覆盖巡检: /etc/ShellCrash 是逐项枚举的, 新增顶层文件不会自动进清单 ---
# 漏一条 = 刷机后该文件真丢。只盯「现役脚本/配置」这一层: 回滚副本(.bak*)、
# 隐藏临时(.*)、禁用件、大二进制缓存都不该进刷机保留清单, 一律排除; 否则每轮
# WARN 里几十个 .bak 会把真漏项淹掉, 等于每 30 分钟往 syslog 刷一屏无效告警。
# 去重降频: 集合存 /tmp(tmpfs, 不写闪存); 只在集合「变化」时 logger —— 长期稳定
# 的漏项不再重复刷同一条, 新出现/消失的漏项立刻可见, 审计价值不丢。
KEEPMISS=""
for e in $(ls -A /etc/ShellCrash 2>/dev/null); do
  case "$e" in CrashCore.raw|CrashCore.gz|CrashCore.upx|meta-backup|GeoSite.dat|GeoIP.dat|ui|.*|*.bak*|*.disabled|*.old|*.tmp|*.swp) continue ;; esac
  grep -q "^/etc/ShellCrash/$e$" /etc/sysupgrade.conf 2>/dev/null || KEEPMISS="$KEEPMISS $e"
done
KEEPSTATE=/tmp/.keepaudit.state
KEEPPREV=$(cat "$KEEPSTATE" 2>/dev/null)
if [ -n "$KEEPMISS" ] && [ "$KEEPMISS" != "$KEEPPREV" ]; then
  logger -t keepaudit "WARN not-in-keep-list:$KEEPMISS" 2>/dev/null
  echo "[WARN] 未进保留清单的 ShellCrash 顶层文件:$KEEPMISS" >&2
fi
printf '%s' "$KEEPMISS" > "$KEEPSTATE" 2>/dev/null

# --- 保留 7 天 ---
find "$DIR" -maxdepth 1 -name "health-*.log" -mtime +7 -delete 2>/dev/null

# 单行快照，便于 grep/awk
one() { echo -n "$1=$2 "; }

TS=$(date '+%Y-%m-%d %H:%M:%S')
LOAD=$(cut -d' ' -f1-3 /proc/loadavg | tr ' ' ',')
UPT=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)
MEMAV=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
MEMTOT=$(awk '/MemTotal/{print $2}' /proc/meminfo)
OVL=$(df -k /overlay | tail -1 | awk '{print $3"/"$2}')
TEMP=$(awk '{print int($1/1000)}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
TMPU=$(df -k /tmp | tail -1 | awk '{print $3"/"$2}')
TMPW=0
TMPA=${TMPU%%/*}
case "$TMPA" in ""|*[!0-9]*) TMPA=0 ;; esac
TMPT=${TMPU##*/}
case "$TMPT" in ""|*[!0-9]*) TMPT=0 ;; esac
if [ "$TMPA" -ge 40960 ]; then TMPW=CRIT; elif [ "$TMPA" -ge 30720 ]; then TMPW=WARN; fi
CT=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)
CTMAX=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)
WANIP=$(ip -4 addr show wan 2>/dev/null | grep -o 'inet [0-9.]*' | cut -d' ' -f2)
WANMTU=$(ip link show wan 2>/dev/null | grep -o 'mtu [0-9]*' | cut -d' ' -f2)
WANUP=$(ip link show wan 2>/dev/null | grep -c 'state UP')
MIMO=$(pidof CrashCore 2>/dev/null | head -1)
DNSPID=$(pidof dnsmasq 2>/dev/null | head -1)
MIVER=$(curl -s -m 5 -H "$API" "$CTRL/version" 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
CONN=$(curl -s -m 5 -H "$API" "$CTRL/connections" 2>/dev/null | grep -o '"downloadTotal":[0-9]*' | head -1 | cut -d: -f2)
# 组名不再硬编码 URL 编码：原来是 %F0%9F%9A%80%20%E8%8A%82... 这种死值，
# 组名一改（重排 / 改名）快照就静默变成空字段，而看的人还以为「没有数据」。
# 与 guardian.sh 的 enc() 同一口径：只转空格，mihomo 接受 UTF-8 原样路径。
POOL_GROUP="${POOL_GROUP:-🚀 节点选择}"
AI_WEB="${AI_WEB:-🤖 AI网页}"
urlenc() { printf '%s' "$1" | sed 's/ /%20/g'; }
NODENOW=$(curl -s -m 5 -H "$API" "$CTRL/proxies/$(urlenc "$POOL_GROUP")" 2>/dev/null | grep -o '"now":"[^"]*"' | head -1 | cut -d'"' -f4)
AINOW=$(curl -s -m 5 -H "$API" "$CTRL/proxies/$(urlenc "$AI_WEB")" 2>/dev/null | grep -o '"now":"[^"]*"' | head -1 | cut -d'"' -f4)
NFT=$(nft list tables 2>/dev/null | wc -l)
CH24=$(iw dev phy0-ap0 info 2>/dev/null | grep -o 'channel [0-9]*' | head -1 | cut -d' ' -f2)
CH5=$(iw dev phy1-ap0 info 2>/dev/null | grep -o 'channel [0-9]*' | head -1 | cut -d' ' -f2)
STA24=$(iw dev phy0-ap0 station dump 2>/dev/null | grep -c Station)
STA5=$(iw dev phy1-ap0 station dump 2>/dev/null | grep -c Station)
LASTFAIL=$(cat /etc/ShellCrash/logs/LAST_FAILURE 2>/dev/null | tr -d '\n')

# --- 内存趋势：连续多少次低于 30MB（与 guardian 的 WARN 阈值同口径）---
# 单次低是噪声（一次 hotupdate 解压就能压到 20MB），连续 3 次（=90 分钟）才算趋势。
# 状态放 tmpfs，不写闪存。
MEMLOW_F=/tmp/router-health/.memlow.state
MEMLOW=$(cat "$MEMLOW_F" 2>/dev/null)
case "$MEMLOW" in ''|*[!0-9]*) MEMLOW=0 ;; esac
case "$MEMAV" in ''|*[!0-9]*) MEMAV=0 ;; esac
if [ "$MEMAV" -lt 30720 ]; then
  MEMLOW=$((MEMLOW + 1))
  [ "$MEMLOW" -ge 3 ] && logger -t health "WARN mem_avail_kb=${MEMAV} 连续 ${MEMLOW} 次低于 30MB" 2>/dev/null
else
  MEMLOW=0
fi
mkdir -p /tmp/router-health 2>/dev/null
printf '%s\n' "$MEMLOW" > "$MEMLOW_F" 2>/dev/null

# --- JSON 辅助（只在 --json 时用到；纯 shell，不依赖 jq）---
jesc() {
  printf '%s' "$1" | tr '\n\r\t' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
jnum() { case "$2" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$2" ;; esac; }
# 跨仓联动：设备上若装了 ShellcrashRules 仓的契约快照（/etc/ShellCrash/health-snapshot.sh，
# schema shellcrash.health/1），把它的整份 JSON 内嵌成 shellcrash 子对象 —— 消费方只读这一份
# 文件，不必再各自 ssh 上去采一遍。用 --no-api 采：api 结论以本文件顶层的 ai_exit / node 为准，
# 每 30 分钟不再多打一次控制 API。SHELLCRASH_SNAP 置空即关闭；路径不存在时输出 null。
SHELLCRASH_SNAP=${SHELLCRASH_SNAP-/etc/ShellCrash/health-snapshot.sh}
sc_json() {
  [ -n "$SHELLCRASH_SNAP" ] && [ -r "$SHELLCRASH_SNAP" ] || { printf 'null'; return 0; }
  _s=$(sh "$SHELLCRASH_SNAP" --no-api 2>/dev/null | tr -d '\n\r')
  # 半截 JSON 会把整份快照搞坏：只接受首尾配对的单层对象，否则报 null
  case "$_s" in
    '{'*'}') printf '%s' "$_s" ;;
    *) printf 'null' ;;
  esac
}
# 把一个多行 KV 状态文件（guardian.state / dest-guard.state）转成 JSON 子对象。
# 值可含空格，所以按第一个 "=" 切分；键为空的行跳过。
sub_json() {
  _f="$1"; _o=""
  [ -r "$_f" ] || { printf 'null'; return 0; }
  while IFS='=' read -r _k _v; do
    [ -n "$_k" ] || continue
    _o="$_o$(printf '"%s": "%s", ' "$(jesc "$_k")" "$(jesc "$_v")")"
  done < "$_f"
  printf '{%s}' "${_o%, }"
}

{
  printf "%s " "$TS"
  one tag "$TAG"
  one load "$LOAD"
  one uptime_s "$UPT"
  one mem_avail_kb "$MEMAV"
  one mem_total_kb "$MEMTOT"
  one temp_c "$TEMP"
  one overlay_kb "$OVL"
  one tmp_kb "$TMPU"
  one tmp_warn "$TMPW"
  one conntrack "$CT/$CTMAX"
  one wan_ip "$WANIP"
  one wan_mtu "$WANMTU"
  one wan_up "$WANUP"
  one mihomo_pid "$MIMO"
  one mihomo_ver "$MIVER"
  one dnsmasq_pid "$DNSPID"
  one conns "$CONN"
  one node "$NODENOW"
  one ai_exit "$AINOW"
  one nft_tables "$NFT"
  one ch24 "$CH24/$STA24"
  one ch5 "$CH5/$STA5"
  one last_fail "$LASTFAIL"
  echo
} >> "$LOG"

# --- 结构化输出（--json）：写 tmpfs 并回显，供面板 / 脚本直接消费 ---
# 默认行为不变（上面那一行 KV 照旧进 flash 日志，保持时间线连续）。
if [ "$JSON" = "1" ]; then
  J=/tmp/router-health/health.json
  {
    printf '{"ts": "%s", "epoch": %s, "tag": "%s", ' "$TS" "$(date +%s)" "$(jesc "$TAG")"
    printf '"load": "%s", "uptime_s": %s, ' "$(jesc "$LOAD")" "$(jnum "$UPT")"
    printf '"mem_avail_kb": %s, "mem_total_kb": %s, "mem_low_streak": %s, ' \
      "$(jnum "$MEMAV")" "$(jnum "$MEMTOT")" "$(jnum "$MEMLOW")"
    printf '"temp_c": %s, ' "$(jnum "$TEMP")"
    printf '"overlay_kb": "%s", "tmp_kb": "%s", "tmp_warn": "%s", ' \
      "$(jesc "$OVL")" "$(jesc "$TMPU")" "$TMPW"
    printf '"conntrack": "%s", ' "$(jesc "$CT/$CTMAX")"
    printf '"wan_ip": "%s", "wan_mtu": "%s", "wan_up": %s, ' \
      "$(jesc "$WANIP")" "$(jesc "$WANMTU")" "$(jnum "$WANUP")"
    printf '"mihomo_pid": "%s", "mihomo_ver": "%s", "dnsmasq_pid": "%s", ' \
      "$(jesc "$MIMO")" "$(jesc "$MIVER")" "$(jesc "$DNSPID")"
    printf '"conns": "%s", ' "$(jesc "$CONN")"
    printf '"node": "%s", "ai_exit": "%s", ' "$(jesc "$NODENOW")" "$(jesc "$AINOW")"
    printf '"nft_tables": %s, ' "$(jnum "$NFT")"
    printf '"ch24": "%s", "ch5": "%s", ' "$(jesc "$CH24/$STA24")" "$(jesc "$CH5/$STA5")"
    printf '"last_fail": "%s", ' "$(jesc "$LASTFAIL")"
    printf '"guardian": %s, ' "$(sub_json /tmp/ShellCrash/guardian.state)"
    printf '"dest_guard": %s, ' "$(sub_json /tmp/ShellCrash/dest-guard.state)"
    printf '"shellcrash": %s' "$(sc_json)"
    printf '}\n'
  } > "$J.tmp" 2>/dev/null && mv -f "$J.tmp" "$J"
  cat "$J" 2>/dev/null
fi

# 日志体积上限 512KB，超了截尾
SZ=$(wc -c < "$LOG" 2>/dev/null || echo 0)
[ "$SZ" -gt 524288 ] && { tail -2000 "$LOG" > "$LOG.tmp" && mv -f "$LOG.tmp" "$LOG"; }

exit 0
