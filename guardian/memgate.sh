#!/bin/sh
# /etc/ShellCrash/memgate.sh
# U13-guard : memory gate for the ShellCrash legacy watchdog (start_legacy_wd.sh).
#
# Why this exists
#   CrashCore was OOM-killed 3 times on 2026-10-20 (10:43:09 / 12:57:34 / 12:59:01).
#   Each kill was followed by the per-minute cron watchdog pulling CrashCore back
#   up.  "start.sh start" -> check_core.sh -> core_webget / core_unzip can push a
#   ~57 MB core payload into /tmp, which is a RAM-backed tmpfs (no size= option,
#   so the cap is RAM/2 = 119512 kB).  That re-fills the RAM, triggers the next
#   OOM, and after 31 s without a watchdog kick the whole router hard-resets.
#   This gate refuses to (re)launch CrashCore while the system has no memory
#   headroom, so the loop is broken: one WARNING is logged and the run exits 0.
#
# Usage
#   memgate.sh check     exit 0 = allowed to launch, exit 1 = BLOCKED by the gate
#   memgate.sh status    print the readings and the verdict
#
# Configuration : /etc/ShellCrash/configs/memgate.conf
#   MEM_GATE_KB=32768     block the launch when MemAvailable < this value (kB)
#
# Environment overrides (used by the offline dry-run harness):
#   MEMGATE_MEMINFO   meminfo-like file to read   (default /proc/meminfo)
#   MEMGATE_CONF      config file to read          (default .../configs/memgate.conf)
#   MEMGATE_LOG       log file to append to        (default .../logs/memgate.log)
#   MEMGATE_LOG_MAX   max size of the log file     (default 65536)
#   MEMGATE_TAG       syslog tag                   (default ShellCrashMemGate)

CRASHDIR="${MEMGATE_CRASHDIR:-/etc/ShellCrash}"
CONF="${MEMGATE_CONF:-$CRASHDIR/configs/memgate.conf}"
MEMINFO="${MEMGATE_MEMINFO:-/proc/meminfo}"
LOGFILE="${MEMGATE_LOG:-$CRASHDIR/logs/memgate.log}"
LOGMAX="${MEMGATE_LOG_MAX:-65536}"
TAG="${MEMGATE_TAG:-ShellCrashMemGate}"
DEFAULT_GATE_KB=32768
DEFAULT_FORCE_AFTER=5

# MemAvailable (kB): the kernel estimate of how much memory can still be
# allocated without swapping.  It already discounts reclaimable cache, so it
# is far more meaningful than MemFree.
mem_available_kb() {
    [ -r "$MEMINFO" ] || return 1
    awk '/^MemAvailable:/ { print $2; exit }' "$MEMINFO" 2>/dev/null
}

# Threshold from the config file, with a built-in fallback.
gate_threshold_kb() {
    _t=""
    if [ -r "$CONF" ]; then
        _t=$(sed -n 's/^[[:space:]]*MEM_GATE_KB[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$CONF" 2>/dev/null | head -n 1)
    fi
    case "$_t" in
        ''|*[!0-9]*) _t="$DEFAULT_GATE_KB" ;;
    esac
    echo "$_t"
}

# Consecutive-block counter: after MEMGATE_FORCE_AFTER blocked checks we
# allow the launch anyway.  A down proxy is a worse outcome than a proxy
# running with reduced headroom, and the original OOM->relaunch loop is
# already broken at the source (the core no longer lands in /tmp).
force_after() {
    _f=""
    if [ -r "$CONF" ]; then
        _f=$(sed -n 's/^[[:space:]]*MEMGATE_FORCE_AFTER[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$CONF" 2>/dev/null | head -n 1)
    fi
    case "$_f" in
        ''|*[!0-9]*) _f="$DEFAULT_FORCE_AFTER" ;;
    esac
    echo "$_f"
}

block_count_file() {
    echo "${MEMGATE_COUNT_FILE:-/tmp/ShellCrash/.memgate_block_count}"
}

# Log to syslog (RAM only) and to the on-flash log file (size capped).
memgate_log() {
    _msg="$1"
    logger -t "$TAG" "$_msg" 2>/dev/null
    _dir=$(dirname "$LOGFILE" 2>/dev/null)
    [ -n "$_dir" ] && [ ! -d "$_dir" ] && mkdir -p "$_dir" 2>/dev/null
    _sz=0
    if [ -f "$LOGFILE" ]; then
        _sz=$(wc -c < "$LOGFILE" 2>/dev/null)
        case "$_sz" in ''|*[!0-9]*) _sz=0 ;; esac
    fi
    if [ "$_sz" -ge "$LOGMAX" ]; then
        tail -c $((LOGMAX / 2)) "$LOGFILE" > "$LOGFILE.trim" 2>/dev/null &&
            mv -f "$LOGFILE.trim" "$LOGFILE" 2>/dev/null
        rm -f "$LOGFILE.trim" 2>/dev/null
        printf '%s [memgate] log truncated, limit %s bytes\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$LOGMAX" >> "$LOGFILE" 2>/dev/null
    fi
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$_msg" >> "$LOGFILE" 2>/dev/null
}

case "${1:-check}" in
check)
    _avail=$(mem_available_kb)
    if [ -z "$_avail" ]; then
        # Cannot decide -> fail open, never keep the proxy down because of us.
        logger -t "$TAG" "memgate: cannot read MemAvailable from $MEMINFO; allowing launch (fail-open)" 2>/dev/null
        exit 0
    fi
    _thr=$(gate_threshold_kb)
    if [ "$_avail" -lt "$_thr" ]; then
        _cntf=$(block_count_file)
        _cnt=0
        [ -f "$_cntf" ] && _cnt=$(cat "$_cntf" 2>/dev/null)
        case "$_cnt" in ''|*[!0-9]*) _cnt=0 ;; esac
        _cnt=$((_cnt + 1))
        _cdir=$(dirname "$_cntf" 2>/dev/null)
        [ -n "$_cdir" ] && [ ! -d "$_cdir" ] && mkdir -p "$_cdir" 2>/dev/null
        echo "$_cnt" > "$_cntf" 2>/dev/null
        _force=$(force_after)
        if [ "$_cnt" -ge "$_force" ]; then
            rm -f "$_cntf" 2>/dev/null
            memgate_log "ALLOW-BY-ESCALATION memgate: MemAvailable=${_avail}kB < MEM_GATE_KB=${_thr}kB for ${_cnt} consecutive checks (>= MEMGATE_FORCE_AFTER=${_force}); allowing launch to avoid a permanent proxy outage"
            exit 0
        fi
        memgate_log "WARNING memgate BLOCKED (#${_cnt}/${_force}): MemAvailable=${_avail}kB < MEM_GATE_KB=${_thr}kB; CrashCore launch skipped to avoid the OOM->relaunch loop"
        exit 1
    fi
    rm -f "$(block_count_file)" 2>/dev/null
    exit 0
    ;;
status)
    _avail=$(mem_available_kb)
    _thr=$(gate_threshold_kb)
    echo "meminfo      : $MEMINFO"
    echo "conf         : $CONF"
    echo "log file     : $LOGFILE (max ${LOGMAX} bytes)"
    echo "MemAvailable : ${_avail:-unknown} kB"
    echo "MEM_GATE_KB  : $_thr kB"
    if [ -z "$_avail" ]; then
        echo "verdict      : UNKNOWN (fail-open)"
        exit 0
    fi
    if [ "$_avail" -lt "$_thr" ]; then
        echo "verdict      : BLOCK"
        exit 1
    fi
    echo "verdict      : ALLOW"
    exit 0
    ;;
*)
    echo "usage: memgate.sh check|status" >&2
    exit 2
    ;;
esac
