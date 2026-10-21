#!/bin/sh
# ============================================================================
# 网络守护 v3 —— 只做「检测 + 最小化修复」，绝不做破坏性操作
#
# 已知良好状态（2026-10-20 固化，依据实测）：
#   - 🤖 干净出口 / 🤖 AI网页 = 🇮🇳 印度-备用m2（与订阅的 印度-优化 / 印度-备用ct2
#     三选一，三者共用同一干净出口 IP <CLEAN-EXIT-IP>，Google 侧 cc 恒为 IN；
#     切入口不换 IP、只换链路，所以会话不受影响）
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
CLEAN_NODE="${CLEAN_NODE:-🇮🇳 印度-优化}"
POOL_GROUP="${POOL_GROUP:-🚀 节点选择}"
POOL_FALLBACK_GROUP="${POOL_FALLBACK_GROUP:-♻️ 自动选择}"

API_SECRET=$(sed -n "s/^secret=//p" /etc/ShellCrash/configs/ShellCrash.cfg 2>/dev/null | head -1)
SECRET="$API_SECRET"
AUTH="Authorization: Bearer $SECRET"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() {
  echo "$(ts) $*" >> "$LOG"
  case "$*" in
    *FIX*|*ALERT*|*ERROR*|*WARN*) logger -t guardian -p daemon.warn "$*" 2>/dev/null ;;
  esac
}
enc() { echo "$1" | sed 's/ /%20/g'; }
grp() { $CURL -s -m 5 -H "$AUTH" "$CTRL/proxies/$(enc "$1")" 2>/dev/null | grep -oE '"now":"[^"]*"' | head -1 | sed 's/"now":"//;s/"$//'; }
put() { $CURL -s -m 8 -o /dev/null -w "%{http_code}" -H "$AUTH" -X PUT "$CTRL/proxies/$(enc "$1")" -H 'Content-Type: application/json' -d "{\"name\":\"$2\"}" 2>/dev/null; }

# 被 Google 判为 CN 的节点（实测清单；台湾/美国是轮换 IP 池，判定会跳变，同样不可靠）
is_bad_node() {
  case "$1" in
    *日本-优化*|*台湾-优化*|*美国LA-优化*|*新加坡-优化*|*香港-优化*|*香港WAP-优化*|*德国-优化*|*加拿大-优化*|*英国-优化*|*过滤掉14条线路*) return 0 ;;
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

eff_node() {
  n=$(grp "$1")
  [ -z "$n" ] && return 0
  case "$n" in
    "🚀 手动切换") grp "🚀 手动切换" ;;
    *) echo "$n" ;;
  esac
}

if [ -f "$LOG" ]; then
  SZ=$(wc -c < "$LOG" 2>/dev/null || echo 0)
  [ "$SZ" -gt 204800 ] && { tail -60 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; }
fi

# ---------- 1) mihomo 存活（OOM 会被内核杀掉；服务关闭会清 pid 文件，故用"最近活着"状态文件兜底） ----------
if $CURL -s -m 5 -H "$AUTH" "$CTRL/version" >/dev/null 2>&1; then
  date +%s > "$ALIVEF" 2>/dev/null
else
  if pidof CrashCore >/dev/null 2>&1; then
    log "WARN: CrashCore 进程在但 API 无响应（可能正在热重载），本次不动作"
  else
    LAST=$(cat "$ALIVEF" 2>/dev/null || echo 0)
    NOWT=$(date +%s)
    if [ -f "$PIDFILE" ] || [ $((NOWT - LAST)) -lt 1800 ]; then
      log "ALERT: CrashCore 进程不存在（可能是 OOM 被杀），用 start.sh 拉起"
      /bin/ash /etc/ShellCrash/start.sh start >> "$LOG" 2>&1
      sleep 12
      if $CURL -s -m 5 -H "$AUTH" "$CTRL/version" >/dev/null 2>&1; then
        log "FIX: CrashCore 已恢复"
      else
        log "ERROR: CrashCore 拉起后仍无响应，需人工介入"
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

# ---------- 2.1) AI网页 / 干净出口 锁到唯一干净节点 ----------
for g in "$AI_WEB" "$CL"; do
  NOW=$(grp "$g")
  if [ -n "$NOW" ] && [ "$NOW" != "$CLEAN_NODE" ] && is_bad_node "$NOW"; then
    if [ "$(put "$g" "$CLEAN_NODE")" = "204" ]; then
      log "FIX: $g 从「$NOW」切到干净出口「$CLEAN_NODE」"
    else
      log "ERROR: $g 切到 $CLEAN_NODE 失败"
    fi
  fi
done

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
T1=$(/usr/bin/curl -s -m 12 -o /dev/null -w "%{time_total}" -x "$PROXY" "https://api.ipify.org" 2>/dev/null)
T2=$(/usr/bin/curl -s -m 12 -o /dev/null -w "%{time_total}" -x "$PROXY" "https://api.ipify.org" 2>/dev/null)
if [ -n "$T1" ] && [ -n "$T2" ]; then
  MS=$(echo "$T1 $T2" | awk '{t+=($1>$2?$1:$2)} END{printf "%.1f", t/2}')
  case "$MS" in
    3.*|4.*|5.*|6.*|7.*|8.*|9.*|[1-9][0-9]*)
      if [ "$(put "$POOL_GROUP" "$POOL_FALLBACK_GROUP")" = "204" ]; then
        log "FIX: 通用出口耗时 ${MS}s（>3s，疑似节点劣化），复位为「♻️ 自动选择」"
      else
        log "ERROR: 通用出口复位失败（控制 API 拒绝）"
      fi
      ;;
  esac
fi

# ---------- 3.6) 干净出口健康守卫（CLEAN_EXIT_HEALTH）----------
# 干净出口（印度）会间歇性劣化。实测（2026-10-20）：
#   - 机场订阅给的印度入口（<YOUR-NODE-SERVER>）到 gemini.google.com（784KB）
#     偶发吞吐塌陷，耗时 22s / 25s 超时；但小响应的 API 端点始终 0.9s ——
#     所以健康探测必须用真实页面，用 API 端点抓不到这个长尾。
#   - 自建的 m2 / ct2 两个入口（与订阅同端口同 Host）实测稳定在 1.5-1.8s。
#   - 三条入口共用同一干净出口 IP <CLEAN-EXIT-IP>（Google 恒判 cc=IN），
#     切入口不换 IP、只换链路，对已登录的 Google 会话无感。
# 候选顺序按实测稳定性排：自建入口优先，订阅入口兜底。
# 绝不降级到非印度节点：实测机场 27 个节点里其余全部 cc=CN（美/日/新/台/英/加/德/港），
# Google 会直接拒绝服务并提示「不支持此国家」。
CL_CANDIDATES="${CL_CANDIDATES:-🇮🇳 印度-备用m2|🇮🇳 印度-备用ct2|🇮🇳 印度-优化}"
CL_PROBE_URL="https://gemini.google.com/"

clean_exit_ms() {
  C1=$(/usr/bin/curl -s -m 15 -o /dev/null --max-filesize 131072 -w "%{time_total}" -x "$PROXY" "$CL_PROBE_URL" 2>/dev/null)
  C2=$(/usr/bin/curl -s -m 15 -o /dev/null --max-filesize 131072 -w "%{time_total}" -x "$PROXY" "$CL_PROBE_URL" 2>/dev/null)
  [ -z "$C1" ] && [ -z "$C2" ] && { echo "99"; return; }
  echo "$C1 $C2" | awk '{t+=($1>$2?$1:$2)} END{printf "%.1f", t/2}'
}
clean_exit_bad() {
  MS=$(clean_exit_ms)
  case "$MS" in
    4.*|5.*|6.*|7.*|8.*|9.*|[1-9][0-9]*) return 0 ;;
    *) return 1 ;;
  esac
}
CUR_CL=$(grp "$CL")
if [ -n "$CUR_CL" ] && clean_exit_bad; then
  FIXED=""
  OLDIFS="$IFS"; IFS="|"
  for cand in $CL_CANDIDATES; do
    [ "$cand" = "$CUR_CL" ] && continue
    [ "$(put "$CL" "$cand")" = "204" ] || continue
    sleep 3
    if ! clean_exit_bad; then
      FIXED="$cand"; break
    fi
  done
  IFS="$OLDIFS"
  if [ -n "$FIXED" ]; then
    put "$AI_WEB" "$FIXED" >/dev/null 2>&1
    log "FIX: 干净出口劣化（当前入口「$CUR_CL」），已换到「$FIXED」（同一出口 IP <CLEAN-EXIT-IP>，不影响会话）；AI网页组同步"
  else
    [ "$CUR_CL" != "$(grp "$CL")" ] && put "$CL" "$CUR_CL" >/dev/null 2>&1
    log "ALERT: 干净出口三个入口全部劣化（已保持「$CUR_CL」），Gemini 可能打不开；不降级到非印度节点（Google 会判为 CN 并拒绝服务）"
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
if ! grep -q "name: $AI_WEB" /tmp/ShellCrash/config.yaml 2>/dev/null; then
  LASTF=/tmp/ShellCrash/.last_fallback_heal
  NOWT=$(date +%s)
  PREV=$(cat $LASTF 2>/dev/null || echo 0)
  if [ $((NOWT - PREV)) -gt 1800 ]; then
    echo $NOWT > $LASTF
    log "FIX: 运行配置缺 $AI_WEB 组（疑为回退基础配置），重跑 hotupdate 重新生成"
    /bin/ash /etc/ShellCrash/task/task.sh hotupdate >> "$LOG" 2>&1
  else
    log "WARN: 运行配置缺 $AI_WEB 组（疑为回退基础配置），30 分钟限频内不重复重生成"
  fi
fi

# ---------- 6) 探活与内存水位（内存不足是 OOM 根因，必须盯） ----------
# Google 侧地区判定探测：support.google.com 的 cc 变量在页面 1MB 之后，整页 1.6MB，
# 所以每 60 分钟探一次（全天约 23MB），不要每 5 分钟拉一次。
# cc 一旦不再是 IN，说明机场把印度出口 IP 换成了被判为 CN 的地址，
# Gemini 会直接报「不支持此国家」，只能换机场节点。
CCF=/tmp/ShellCrash/.cc_probe_ts
NOWT2=$(date +%s)
LASTF2=$(cat "$CCF" 2>/dev/null || echo 0)
if [ $((NOWT2 - LASTF2)) -ge 3600 ]; then
  echo $NOWT2 > "$CCF"
  CC=$($CURL -s -m 20 -x "$PROXY" "https://support.google.com/gemini/answer/13575153" 2>/dev/null | grep -oE "var cc=.[A-Z]{2}" | head -1 | sed "s/var cc=.//")
  if [ -n "$CC" ]; then
    log "INFO: Google 侧出口判定 cc=$CC（干净出口，期望 IN）"
    [ "$CC" != "IN" ] && log "ALERT: Google 把干净出口判为 cc=$CC（不再是印度），Gemini 会报「不支持此国家」，需更换机场节点"
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
TMPK=$(df -k /tmp 2>/dev/null | tail -1 | awk '{print $3}')
TMPT=$(df -k /tmp 2>/dev/null | tail -1 | awk '{print $2}')
if [ -n "$TMPK" ] && [ -n "$TMPT" ] && [ "$TMPT" -gt 0 ]; then
  TMPP=$((TMPK * 100 / TMPT))
  if [ "$TMPP" -ge 80 ]; then
    log "WARN: /tmp 内存盘已用 ${TMPP}%（${TMPK}K/${TMPT}K），接近撑爆会 OOM 并触发看门狗重启"
    for f in /tmp/pre-reboot-config.tar.gz /tmp/m132 /tmp/m132.gz /tmp/scmeta.tar.gz \
             /tmp/sc-meta.tar.gz /tmp/mihomo-new /tmp/mihomo-arm64.gz /tmp/core_test_out.txt \
             /tmp/_core_test.sh /tmp/gpage.html /tmp/g2.html /tmp/g4.html /tmp/g5.html /tmp/pt.html \
             /tmp/sub.raw /tmp/sub.txt /tmp/sub2.txt; do
      [ -e "$f" ] && { rm -rf "$f" 2>/dev/null; log "FIX: 已清理 /tmp 临时大文件 $f"; }
    done
    TMPK2=$(df -k /tmp 2>/dev/null | tail -1 | awk '{print $3}')
    log "INFO: /tmp 清理后占用 ${TMPK2}K/${TMPT}K"
  fi
fi

# cron lifeline: start.sh stop 会重写 crontab 并删掉 legacy 看门狗行,
# 这里每 5 分钟检查一次, 缺失就补回 (2026-10-20 事故)
if ! grep -q 'start_legacy_wd.sh' /etc/crontabs/root 2>/dev/null; then
    echo '* * * * * /bin/ash /etc/ShellCrash/starts/start_legacy_wd.sh shellcrash #ShellCrash保守模式守护进程' >> /etc/crontabs/root
    crontab /etc/crontabs/root 2>/dev/null
    log "FIX: restored legacy watchdog cron line"
fi
exit 0
