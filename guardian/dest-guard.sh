#!/bin/sh
# ============================================================================
# 站点健康守卫 v1 —— 按「站点 → 策略组」检查真实可达性
#
# 与 guardian.sh 的分工：
#   guardian.sh 管进程存活、干净出口、通用池整体劣化、nft 表；
#   本脚本只管「某个站点族的出口是否还能用」，不碰全局选择器。
#
# 默认 DRY-RUN：只写日志，不切换任何组。跑一周确认判断与体感一致后，
#   在 cron 行里加 DEST_GUARD_DRY_RUN=0 再启用切换。
#
# 探测方式：
#   GET /proxies/<组>/delay?url=<站点真实 URL> —— 让组当前出口真的去取一次；
#   每项探两次取较小值，避免单次抖动误判。
#
# 动作：
#   observe —— 只记录（url-test 组会自愈，不需要脚本切；干净出口/通用池由
#              guardian.sh 管，避免两个脚本互相打）
#   switch  —— 当前出口不可达或超阈值时，在候选白名单里选第一个健康的切过去；
#              同一组 30 分钟冷却，避免每轮来回打。切换只发生在启用了
#              DEST_GUARD_DRY_RUN=0 之后。
#
# 表格式（| 分隔）：
#   名称|组|动作|探测 URL|阈值 ms|候选（逗号分隔，仅 switch 用）
# ============================================================================
mkdir -p /tmp/ShellCrash 2>/dev/null

CTRL="${MIHOMO_API:-http://127.0.0.1:9999}"
CURL=/usr/bin/curl
LOG=/tmp/ShellCrash/dest-guard.log
RUNTIME=/tmp/ShellCrash
STATE_DIR=$RUNTIME/.dest-guard
LOCK=$RUNTIME/.dest-guard.lock
DRY_RUN="${DEST_GUARD_DRY_RUN:-1}"
COOLDOWN="${DEST_GUARD_COOLDOWN:-1800}"
TIMEOUT_MS="${DEST_GUARD_TIMEOUT:-5000}"

TARGETS=$(cat <<'EOF'
twimg|𝕏 媒体|observe|https://pbs.twimg.com/robots.txt|2500|
github|🔗 GitHub 出口|observe|https://github.com/robots.txt|2500|
bili|🎬 B站解锁|switch|https://api.bilibili.com/x/web-interface/zone|4000|🇭🇰 香港WAP-优化,🇹🇼 台湾-优化3,🇯🇵 日本-优化,🇸🇬 新加坡-优化3
youtube|🤖 干净出口|observe|https://www.youtube.com/|4000|
general|🚀 节点选择|observe|https://www.cloudflare.com/cdn-cgi/trace|3000|
EOF
)

API_SECRET=$(sed -n 's/^secret=//p' /etc/ShellCrash/configs/ShellCrash.cfg 2>/dev/null | head -1)
AUTH="Authorization: Bearer $API_SECRET"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() {
  echo "$(ts) $*" >> "$LOG"
  case "$*" in
    *ALERT*|*FIX*|*WOULD-FIX*|*ERROR*) logger -t dest-guard -p daemon.warn "$*" 2>/dev/null ;;
  esac
}

# 组名只需转义空格；UTF-8 原样交给 curl（与 guardian.sh 一致）
enc() { printf '%s' "$1" | sed 's/ /%20/g'; }
# 探测 URL 里的保留字符；表里的 URL 没有查询串，这里仍兜底转义
urlenc() { printf '%s' "$1" | sed 's/%/%25/g; s/:/%3A/g; s|/|%2F|g; s/?/%3F/g; s/&/%26/g'; }

api_get() {
  $CURL -s -m 8 -H "$AUTH" "$CTRL$1" 2>/dev/null
}

delay_of() {
  _g=$(enc "$1")
  _u=$(urlenc "$2")
  api_get "/proxies/$_g/delay?timeout=$TIMEOUT_MS&url=$_u" |
    sed -n 's/.*"delay":\([0-9][0-9]*\).*/\1/p' | head -1
}

# 两次取较小值：单次抖动（尤其 VMess+WS）不能直接判死
best_delay() {
  _a=$(delay_of "$1" "$2")
  _b=$(delay_of "$1" "$2")
  if [ -n "$_a" ] && [ -n "$_b" ]; then
    if [ "$_a" -le "$_b" ]; then echo "$_a"; else echo "$_b"; fi
  elif [ -n "$_a" ]; then
    echo "$_a"
  else
    echo "$_b"
  fi
}

now_of() {
  api_get "/proxies/$(enc "$1")" |
    sed -n 's/.*"now":"\([^"]*\)".*/\1/p' | head -1
}

put() {
  $CURL -s -m 8 -o /dev/null -w "%{http_code}" -H "$AUTH" -X PUT \
    "$CTRL/proxies/$(enc "$1")" -H 'Content-Type: application/json' \
    -d "{\"name\":\"$2\"}" 2>/dev/null
}

cooldown_file() {
  printf '%s/cooldown_%s' "$STATE_DIR" "$(printf '%s' "$1" | md5sum | cut -c1-8)"
}
cooldown_active() {
  _f=$(cooldown_file "$1")
  [ -f "$_f" ] || return 1
  _t=$(cat "$_f" 2>/dev/null || echo 0)
  case "$_t" in ''|*[!0-9]*) return 1 ;; esac
  [ $(( $(date +%s) - _t )) -lt "$COOLDOWN" ]
}
cooldown_set() { date +%s > "$(cooldown_file "$1")" 2>/dev/null; }

# ---- 单实例锁：重叠运行直接退出；超过 15 分钟的陈旧锁自动清掉 ----
mkdir -p "$RUNTIME" "$STATE_DIR" 2>/dev/null
if ! mkdir "$LOCK" 2>/dev/null; then
  _T=$(cat "$LOCK/ts" 2>/dev/null || echo 0)
  case "$_T" in ''|*[!0-9]*) _T=0 ;; esac
  if [ $(( $(date +%s) - _T )) -gt 900 ]; then
    # 锁目录每轮都会写入 ts，永远非空；必须连文件一起删，rmdir 才能成功。
    rm -f "$LOCK/ts" 2>/dev/null
    rmdir "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null || { log "ALERT: 清除陈旧锁失败（$LOCK），本轮退出"; exit 0; }
  else
    exit 0
  fi
fi
date +%s > "$LOCK/ts" 2>/dev/null
trap 'rm -f "$LOCK/ts"; rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

if [ -z "$API_SECRET" ]; then
  log "ERROR: 读不到 mihomo API secret（/etc/ShellCrash/configs/ShellCrash.cfg），本轮跳过"
  exit 0
fi

if [ -f "$LOG" ]; then
  SZ=$(wc -c < "$LOG" 2>/dev/null || echo 0)
  [ "$SZ" -gt 204800 ] && { tail -100 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; }
fi

SUMMARY=""
OLDIFS=$IFS
while IFS='|' read -r NAME GROUP MODE PROBE MAX_MS CANDIDATES; do
  [ -z "$NAME" ] && continue
  CUR=$(now_of "$GROUP")
  if [ -z "$CUR" ]; then
    log "ALERT: $NAME 组「$GROUP」不存在或没有选中节点"
    SUMMARY="$SUMMARY $NAME=NOGROUP"
    continue
  fi

  D=$(best_delay "$GROUP" "$PROBE")
  if [ -z "$D" ]; then
    log "ALERT: $NAME 探测失败 group=$GROUP now=$CUR url=$PROBE"
    SUMMARY="$SUMMARY $NAME=FAIL"
  elif [ "$D" -gt "$MAX_MS" ] 2>/dev/null; then
    log "ALERT: $NAME 延迟 ${D}ms > ${MAX_MS}ms group=$GROUP now=$CUR"
    SUMMARY="$SUMMARY $NAME=SLOW(${D}ms)"
  else
    SUMMARY="$SUMMARY $NAME=OK(${D}ms)"
    continue
  fi

  # 只有 switch 类型且已启用才动手；observe 只记录
  [ "$MODE" = "switch" ] || continue
  if cooldown_active "$GROUP"; then
    log "INFO: $NAME 冷却中（${COOLDOWN}s），本轮不重复切换"
    continue
  fi

  PICK=""
  PICK_D=""
  IFS=','
  for CAND in $CANDIDATES; do
    [ "$CAND" = "$CUR" ] && continue
    CD=$(best_delay "$CAND" "$PROBE")
    [ -z "$CD" ] && continue
    [ "$CD" -gt "$MAX_MS" ] 2>/dev/null && continue
    PICK="$CAND"
    PICK_D="$CD"
    break
  done
  IFS=$OLDIFS

  if [ -z "$PICK" ]; then
    log "ALERT: $NAME 无可用候选（当前「$CUR」探测 ${D:-超时}ms）"
    continue
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log "WOULD-FIX: $NAME 「$CUR」 -> 「$PICK」(probe ${PICK_D}ms) [dry-run]"
  else
    CODE=$(put "$GROUP" "$PICK")
    if [ "$CODE" = "204" ]; then
      cooldown_set "$GROUP"
      log "FIX: $NAME 「$CUR」 -> 「$PICK」(probe ${PICK_D}ms)"
    else
      log "ERROR: $NAME 切换到「$PICK」失败（HTTP $CODE），保持「$CUR」"
    fi
  fi
done <<EOF
$TARGETS
EOF

log "INFO:$SUMMARY"
exit 0
