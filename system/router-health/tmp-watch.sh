#!/bin/sh
# tmp-watch.sh —— 盯住 + 自动回收 RAM 型 /tmp 的占用
#
# 为什么盯: /tmp 是 RAM 型 tmpfs，已被 /etc/init.d/tmpfs-cap 封顶 48 MiB。
# /tmp 写满 → ENOSPC → ShellCrash 配置生成失败 → 退回基础配置 → 用户自定义规则全丢
# （2026-10-20 真的发生过）。所以要在它涨起来之前就看见，并且把垃圾收掉。
#
# 每次检查:
#   - 读 /tmp 已用量
#   - 自动回收（PURGE=1，默认开）:
#       * 只动 /tmp **根目录**的普通文件（find -maxdepth 1，永不进入子目录）；
#       * 只删匹配白名单且 6 小时未修改的文件；
#       * 额外精确回收 /tmp/ShellCrash/config.yaml.rules-*.{del,ana}
#         （rules-cnip.sh / rules-porn.sh 带 PID 的中间产物，trap 未执行时残留，
#          文件名含 PID 永不复用；config.yaml / .bak / -test.yaml 一律不碰）；
#       * 删除前跳过仍被进程打开的 fd；
#       * 每轮最多 64 个 / 8 MB，避免异常情况下的 I/O 峰值。
#   - 超阈值(24MB/40MB) → 写持久日志 + syslog，并附上占用最大的几个目录
#   - 已有一定占用且较上次增长很快 → 同样告警（早期发现泄漏）
#   - 状态文件只留上次用量（回收后），方便算增速
#
# 日志: /etc/router-health/tmp-usage.log（只记告警/回收，上限 64KB）
# 用法: sh /etc/router-health/tmp-watch.sh
# 只观察不回收: TMPWATCH_PURGE=0 sh /etc/router-health/tmp-watch.sh

DIR=/etc/router-health
CONF="${TMPWATCH_CONF:-$DIR/tmp-watch.conf}"
LOG="$DIR/tmp-usage.log"
STATE="$DIR/.tmp-watch.state"
LOGMAX=65536

[ -r "$CONF" ] || CONF=/etc/router-health/tmp-watch.conf

# 默认值；tmp-watch.conf 存在时逐项覆盖
WARN_KB=24576
CRIT_KB=40960
GROW_KB=4096
NOTICE_KB=20480
PURGE=1
PURGE_AGE_MIN=360
PURGE_MAX_FILES=64
PURGE_MAX_KB=8192
if [ -r "$CONF" ]; then
	_v=$(sed -n 's/^[[:space:]]*TMP_WARN_KB[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$CONF" | head -1)
	_c=$(sed -n 's/^[[:space:]]*TMP_CRIT_KB[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$CONF" | head -1)
	_g=$(sed -n 's/^[[:space:]]*TMP_GROWTH_KB[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$CONF" | head -1)
	_n=$(sed -n 's/^[[:space:]]*TMP_NOTICE_KB[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$CONF" | head -1)
	_p=$(sed -n 's/^[[:space:]]*TMP_PURGE[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$CONF" | head -1)
	_a=$(sed -n 's/^[[:space:]]*TMP_PURGE_AGE_MIN[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$CONF" | head -1)
	[ -n "$_v" ] && WARN_KB=$_v
	[ -n "$_c" ] && CRIT_KB=$_c
	[ -n "$_g" ] && GROW_KB=$_g
	[ -n "$_n" ] && NOTICE_KB=$_n
	[ -n "$_p" ] && PURGE=$_p
	[ -n "$_a" ] && PURGE_AGE_MIN=$_a
fi

# 白名单：正向匹配，没匹配上的一律不碰
purge_match() {
	case "$1" in
		*.html|*.json|*.txt|*.log|*.out|*.sh) return 0 ;;
		test*.yaml|*.nft.new.*|cdnbody*) return 0 ;;
	esac
	return 1
}

# 保护名单：即使匹配白名单也不删（系统运行必需 / 运维备份）
purge_keep() {
	case "$1" in
		TZ|resolv.conf|dhcp.leases|cron_tmp|.ujailnoafile) return 0 ;;
		luci-indexcache.*.json) return 0 ;;
	esac
	return 1
}

# 回收。结果写回全局 PF / PKB / PNAMES。
purge_tmp() {
	PF=0; PKB=0; PNAMES=""
	[ "$PURGE" = "1" ] || return 0

	# 候选 1: /tmp 根目录的老文件（maxdepth 1，不进子目录）
	raw=$(find /tmp -maxdepth 1 -type f -mmin +"$PURGE_AGE_MIN" 2>/dev/null)
	# 候选 2: ShellCrash 带 PID 的中间产物（精确模式）
	sc=$(find /tmp/ShellCrash -maxdepth 1 -type f \
		\( -name 'config.yaml.rules-*.del' -o -name 'config.yaml.rules-*.ana' \) \
		-mmin +"$PURGE_AGE_MIN" 2>/dev/null)

	all=""
	oldifs=$IFS; IFS='
'
	for f in $raw; do
		[ -n "$f" ] || continue
		b=${f##*/}
		purge_keep "$b" && continue
		purge_match "$b" || continue
		all="$all$f
"
	done
	for f in $sc; do
		[ -n "$f" ] || continue
		all="$all$f
"
	done
	IFS=$oldifs
	[ -n "$all" ] || return 0

	# 一次性取"被进程打开"的路径集合，避免每个文件都遍历 /proc
	busy=$(ls -l /proc/[0-9]*/fd 2>/dev/null | sed -n 's/.* -> //p' | tr '\n' ' ')

	oldifs=$IFS; IFS='
'
	for f in $all; do
		[ -n "$f" ] || continue
		[ -f "$f" ] || continue
		case " $busy " in *" $f "*) continue ;; esac
		[ "$PF" -ge "$PURGE_MAX_FILES" ] && break
		sz=$(wc -c < "$f" 2>/dev/null)
		case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
		szkb=$(( (sz + 1023) / 1024 ))
		[ $((PKB + szkb)) -gt "$PURGE_MAX_KB" ] && break
		rm -f -- "$f" 2>/dev/null || continue
		PF=$((PF + 1)); PKB=$((PKB + szkb)); PNAMES="$PNAMES ${f##*/}"
	done
	IFS=$oldifs
	return 0
}

USED=$(df -k /tmp 2>/dev/null | tail -1 | awk '{print $3}')
TOTAL=$(df -k /tmp 2>/dev/null | tail -1 | awk '{print $2}')
case "$USED" in ''|*[!0-9]*) exit 0 ;; esac
case "$TOTAL" in ''|*[!0-9]*) TOTAL=0 ;; esac

PREV=0
[ -r "$STATE" ] && { v=$(cat "$STATE" 2>/dev/null); case "$v" in ''|*[!0-9]*) v=0 ;; esac; PREV=$v; }

USED_BEFORE=$USED
GROW=$((USED_BEFORE - PREV))
LEVEL=""
if [ "$USED_BEFORE" -ge "$CRIT_KB" ]; then
	LEVEL="CRIT"
elif [ "$USED_BEFORE" -ge "$WARN_KB" ]; then
	LEVEL="WARN"
elif [ "$USED_BEFORE" -ge "$NOTICE_KB" ] && [ "$GROW" -ge "$GROW_KB" ]; then
	LEVEL="GROW"
fi

# 自动回收
PURGE_NOTE=""
PF=0; PKB=0; PNAMES=""
if [ "$PURGE" = "1" ]; then
	purge_tmp
	if [ "$PF" -gt 0 ]; then
		USED_AFTER=$(df -k /tmp 2>/dev/null | tail -1 | awk '{print $3}')
		case "$USED_AFTER" in ''|*[!0-9]*) USED_AFTER=$USED_BEFORE ;; esac
		PURGE_NOTE="purged=${PF} freed=${PKB}KB used=${USED_BEFORE}->${USED_AFTER}KB:${PNAMES}"
		USED=$USED_AFTER
	else
		USED=$USED_BEFORE
	fi
fi

echo "$USED" > "$STATE" 2>/dev/null

[ -z "$LEVEL" ] && [ -z "$PURGE_NOTE" ] && exit 0

# 谁在吃 /tmp：最大的几个目录
TOP=$(du -k -d 1 /tmp 2>/dev/null | sort -n | tail -4 | tr '\n' ';' | tr -s ' ')

mkdir -p "$DIR"
SZ=0
[ -f "$LOG" ] && { SZ=$(wc -c < "$LOG" 2>/dev/null || echo 0); case "$SZ" in ''|*[!0-9]*) SZ=0 ;; esac; }
if [ "$SZ" -ge "$LOGMAX" ]; then
	tail -c $((LOGMAX / 2)) "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
	rm -f "$LOG.tmp" 2>/dev/null
fi

if [ -n "$LEVEL" ]; then
	printf '%s [%s] /tmp used=%sKB total=%sKB prev=%sKB growth=%sKB | %s%s\n' \
		"$(date '+%Y-%m-%d %H:%M:%S')" "$LEVEL" "$USED_BEFORE" "$TOTAL" "$PREV" "$GROW" "$TOP" "$PURGE_NOTE" >> "$LOG"
	logger -t tmp-watch "[$LEVEL] /tmp used=${USED_BEFORE}KB/${TOTAL}KB (prev ${PREV}KB, +${GROW}KB) - $TOP $PURGE_NOTE" 2>/dev/null
else
	printf '%s [PURGE] %s | %s\n' \
		"$(date '+%Y-%m-%d %H:%M:%S')" "$PURGE_NOTE" "$TOP" >> "$LOG"
	logger -t tmp-watch "[PURGE] $PURGE_NOTE" 2>/dev/null
fi
exit 0
