#!/bin/sh
# 路由器健康快照 —— 定时把关键指标记到持久日志，便于事后回溯
# 用法: sh /etc/router-health/health-snapshot.sh [标签]
# 日志: /etc/router-health/health-YYYYMMDD.log（overlay 持久，重启不丢；保留 7 天）

TAG="${1:-auto}"
DIR=/etc/router-health
SECRET=$(grep -m1 "^secret=" /etc/ShellCrash/configs/ShellCrash.cfg 2>/dev/null | cut -d= -f2- | tr -d "'\"")
CTRL=http://127.0.0.1:9999
API="Authorization: Bearer $SECRET"

mkdir -p "$DIR"
# 自愈: /var -> /tmp 的软链, 运行时目录被误删会让 dnsmasq 等服务起不来
for d in etc lib run lock state spool shm tmp overlay sysinfo odhcpd-piodir resolv.conf.d log; do
  [ -d "/var/$d" ] || { mkdir -p "/var/$d" 2>/dev/null; echo "[HEAL] recreated /var/$d"; }
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
case "$TMPU" in */*) : ;; esac
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
NODENOW=$(curl -s -m 5 -H "$API" "$CTRL/proxies/%F0%9F%9A%80%20%E8%8A%82%E7%82%B9%E9%80%89%E6%8B%A9" 2>/dev/null | grep -o '"now":"[^"]*"' | head -1 | cut -d'"' -f4)
AINOW=$(curl -s -m 5 -H "$API" "$CTRL/proxies/%F0%9F%A4%96%20AI%E7%BD%91%E9%A1%B5" 2>/dev/null | grep -o '"now":"[^"]*"' | head -1 | cut -d'"' -f4)
NFT=$(nft list tables 2>/dev/null | wc -l)
CH24=$(iw dev phy0-ap0 info 2>/dev/null | grep -o 'channel [0-9]*' | head -1 | cut -d' ' -f2)
CH5=$(iw dev phy1-ap0 info 2>/dev/null | grep -o 'channel [0-9]*' | head -1 | cut -d' ' -f2)
STA24=$(iw dev phy0-ap0 station dump 2>/dev/null | grep -c Station)
STA5=$(iw dev phy1-ap0 station dump 2>/dev/null | grep -c Station)
LASTFAIL=$(cat /etc/ShellCrash/logs/LAST_FAILURE 2>/dev/null | tr -d '\n')

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

# 日志体积上限 512KB，超了截尾
SZ=$(wc -c < "$LOG" 2>/dev/null || echo 0)
[ "$SZ" -gt 524288 ] && { tail -2000 "$LOG" > "$LOG.tmp" && mv -f "$LOG.tmp" "$LOG"; }

exit 0
