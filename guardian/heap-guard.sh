#!/bin/sh
# /etc/ShellCrash/heap-guard.sh
# mihomo(CrashCore) 存活堆单调递增自愈：连续多次 MemAvailable 低于阈值且 PID 未变时,
# 受控 restart 把 heap 压回基线。由 guardian.sh 每 5 分钟调度,不自带 cron(避免被 start.sh 冲掉)。
#
# 安全护栏: 1)PID 变化(别处已重启)自动重置计数 2)连续 N 次才触发 3)冷却期 4)重启后验活
# 配置: /etc/ShellCrash/configs/heapguard.conf
# 环境变量(离线测试/覆盖用): HG_MEMINFO HG_PID HG_NOW HG_STATE HG_LOG HG_START HG_DRY

CRASHDIR=/etc/ShellCrash
CONF="$CRASHDIR/configs/heapguard.conf"
MEMINFO="${HG_MEMINFO:-/proc/meminfo}"
LOG="${HG_LOG:-$CRASHDIR/logs/heapguard.log}"
STATE="${HG_STATE:-/tmp/ShellCrash/.heapguard_state}"
START="${HG_START:-$CRASHDIR/start.sh}"
DRY="${HG_DRY:-0}"

read_conf() {
  _k="$1"; _d="$2"; _v=""
  [ -r "$CONF" ] && _v=$(sed -n "s/^[[:space:]]*$_k[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$CONF" 2>/dev/null | head -n 1)
  case "$_v" in ''|*[!0-9]*) _v=$_d ;; esac
  echo "$_v"
}
THRESHOLD=$(read_conf HG_THRESHOLD_MB 30)
STRIKES=$(read_conf HG_STRIKES 3)
COOLDOWN=$(read_conf HG_COOLDOWN 7200)

hg_log() {
  _m="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') $_m" >> "$LOG" 2>/dev/null
  logger -t heapguard "$_m" 2>/dev/null
  [ "$DRY" = "1" ] && printf 'HG[%s] %s\n' "$(date '+%H:%M:%S')" "$_m"
}

avail_mb() { awk '/^MemAvailable:/{print int($2/1024); exit}' "$MEMINFO" 2>/dev/null; }

PID="${HG_PID:-$(pidof CrashCore 2>/dev/null | awk '{print $1}')}"
# 进程不在 -> 交给 guardian 存活守卫处理,这里不插手,并清掉旧计数
if [ -z "$PID" ]; then rm -f "$STATE" 2>/dev/null; exit 0; fi

AVAIL=$(avail_mb)
[ -z "$AVAIL" ] && exit 0   # 读不到内存数据 -> fail-safe 不动作

NOW="${HG_NOW:-$(date +%s)}"
S=0; LPID=""; LTS=0
if [ -r "$STATE" ]; then
  S=$(sed -n 's/^strikes=\([0-9]*\).*/\1/p' "$STATE" 2>/dev/null)
  LPID=$(sed -n 's/^pid=\(.*\)/\1/p' "$STATE" 2>/dev/null)
  LTS=$(sed -n 's/^ts=\([0-9]*\).*/\1/p' "$STATE" 2>/dev/null)
fi
case "$S" in ''|*[!0-9]*) S=0 ;; esac
case "$LTS" in ''|*[!0-9]*) LTS=0 ;; esac

# PID 变了(别处已重启过) -> 重置计数,避免重复杀进程
if [ -n "$LPID" ] && [ "$LPID" != "$PID" ]; then S=0; fi

if [ "$AVAIL" -lt "$THRESHOLD" ]; then
  S=$((S + 1))
  hg_log "WARN: MemAvailable=${AVAIL}MB < ${THRESHOLD}MB, strike ${S}/${STRIKES} (pid=$PID)"
else
  [ "$S" -ne 0 ] && hg_log "INFO: 内存恢复到 ${AVAIL}MB, strike 清零"
  S=0
fi

printf 'strikes=%s\npid=%s\nts=%s\n' "$S" "$PID" "$LTS" > "$STATE" 2>/dev/null

if [ "$S" -ge "$STRIKES" ]; then
  if [ "$LTS" -gt 0 ]; then
    _age=$((NOW - LTS))
    if [ "$_age" -lt "$COOLDOWN" ]; then
      hg_log "INFO: strike 达标但在冷却期(距上次自愈 ${_age}s < ${COOLDOWN}s),跳过"
      exit 0
    fi
  fi
  if [ "$DRY" = "1" ]; then
    hg_log "WOULD-FIX: 应受控重启 CrashCore 释放 heap (pid=$PID, avail=${AVAIL}MB)"
    exit 0
  fi
  # 启动保护：进程刚起来(<900s)说明别处已重启过/堆还没累积，不重复杀
  # 用 /proc/<pid>/stat 第22字段(starttime,ticks) 与 /proc/uptime 计算;不依赖 stat/getconf(该机都没有)
  _st=$(awk '{print $22}' /proc/$PID/stat 2>/dev/null)
  _up=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
  _proc_age=999999
  case "$_st" in
    ''|*[!0-9]*) ;;
    *) case "$_up" in ''|*[!0-9]*) ;; *) _proc_age=$(( _up - (_st / 100) )) ;; esac ;;
  esac
  [ "$_proc_age" -lt 0 ] && _proc_age=999999
  if [ "$_proc_age" -lt 900 ]; then
    hg_log "INFO: CrashCore 启动仅 ${_proc_age}s(<900s)，跳过自愈避免重复重启"
    printf 'strikes=0\npid=%s\nts=%s\n' "$PID" "$LTS" > "$STATE" 2>/dev/null
    exit 0
  fi
  hg_log "ALERT: 连续 ${S} 次内存吃紧,受控重启 CrashCore 释放累积 heap (pid=$PID, avail=${AVAIL}MB)"
  /bin/ash "$START" restart >> "$LOG" 2>&1
  # 验活：轮询最多 90s，要求出现「新 PID 且稳定 5s」。
  # 2026-11-25 修：原来固定 sleep 12 就判活，而 mihomo 加载 4000+ 规则要 20-40s，
  # 19:00 那轮因此误报「未起来,需人工介入」（实际 14s 后正常起来）。
  _w=0; _newpid=""
  while [ "$_w" -lt 30 ]; do
    sleep 3
    _w=$((_w+1))
    _cand=$(pidof CrashCore 2>/dev/null | awk '{print $1}')
    [ -z "$_cand" ] && continue
    [ "$_cand" = "$PID" ] && continue
    sleep 5
    _re=$(pidof CrashCore 2>/dev/null | awk '{print $1}')
    if [ "$_re" = "$_cand" ]; then _newpid="$_cand"; break; fi
  done
  if [ -n "$_newpid" ]; then
    _avail2=$(avail_mb)
    hg_log "FIX: CrashCore 已重启 (old=$PID new=$_newpid, 等待约 $((_w*3))s), MemAvailable 回到 ${_avail2}MB"
    printf 'strikes=0\npid=%s\nts=%s\n' "$_newpid" "$(date +%s)" > "$STATE" 2>/dev/null
  else
    # 保持 strikes 但刷新 ts，进入 HG_COOLDOWN 冷却，避免 5 分钟后再次触发形成重启风暴
    hg_log "ERROR: CrashCore 重启后 90s 内未见稳定新进程,需人工介入（已进入冷却）"
    printf 'strikes=%s\npid=%s\nts=%s\n' "$S" "$PID" "$(date +%s)" > "$STATE" 2>/dev/null
  fi
fi
exit 0
