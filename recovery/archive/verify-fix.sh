#!/bin/ash
# verify-fix.sh — 复测 + 修补（AX3000T）
# 1) 补回 crontab 缺失行（task.sh 106：每 10 分钟保存面板选择）
# 2) 确认 fake-ip 过滤已生效（gstatic/googleapis 必须给真实 IP，不能是 198.18/15）
# 3) 组状态 + Google 侧 cc 实测
# 4) 查上次重启的原因（OOM / 看门狗）
LOG=/root/verify-last.log
: > "$LOG"
log() { printf '%s\n' "$*" | tee -a "$LOG"; }
section() { log ""; log "========== $* =========="; }

section "1. crontab 补行"
if ! grep -q 'task.sh 106' /etc/crontabs/root 2>/dev/null; then
    echo '*/10 * * * * /bin/ShellCrash/task/task.sh 106 #运行时每10分钟自动保存面板配置' >> /etc/crontabs/root
    crontab /etc/crontabs/root 2>/dev/null && log "已补回 task.sh 106"
else
    log "task.sh 106 已在"
fi
log "-- 当前 crontab --"
crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$' | tee -a "$LOG"

section "2. fake-ip 是否已按新过滤表生效（客户端拿到的必须是真实 IP）"
for d in www.gstatic.com gemini.gstatic.com fonts.gstatic.com gemini.google.com www.google.com fonts.googleapis.com; do
    ip=$(nslookup $d 127.0.0.1 2>/dev/null | awk '/^Address: /{print $2}' | grep -v '^127.0.0.1$' | head -1)
    case "$ip" in
        198.18.*|198.19.*) log "  $d -> $ip  【假 IP】Chrome LNA 会判为本地地址并拦截！" ;;
        "") log "  $d -> 无解析" ;;
        *) log "  $d -> $ip  【真实 IP】" ;;
    esac
done

section "3. 策略组与 Google 侧 cc"
SECRET=$(sed -n "s/^secret=//p" /etc/ShellCrash/configs/ShellCrash.cfg 2>/dev/null | head -1)
for g in "%F0%9F%A4%96%20%E5%B9%B2%E5%87%80%E5%87%BA%E5%8F%A3" "%F0%9F%A4%96%20AI%E7%BD%91%E9%A1%B5" "%F0%9F%9A%80%20%E8%8A%82%E7%82%B9%E9%80%89%E6%8B%A9"; do
    now=$(curl -s -m 8 -H "Authorization: Bearer $SECRET" "http://127.0.0.1:9999/proxies/$g" | grep -oE '"now":"[^"]*"' | head -1)
    log "  $(echo "$g" | sed 's/%20/ /g; s/%F0%9F%A4%96/机器人/; s/%F0%9F%9A%80/火箭/') : $now"
done
cc=$(curl -s -m 25 -x http://127.0.0.1:7890 "https://support.google.com/gemini/answer/13575153" 2>/dev/null | grep -oE "var cc=.[A-Z]{2}" | head -1)
log "  Google 侧出口判定: $cc"

section "4. 上次重启原因排查"
log "-- uptime --"; uptime | tee -a "$LOG"
log "-- 内核里的 OOM / 看门狗 记录 --"
dmesg 2>/dev/null | grep -iE "out of memory|oom-kill|watchdog|panic|Killed process" | tail -10 | tee -a "$LOG"
log "-- 持久化健康快照的最后几行 --"
for f in /etc/router-health/health-*.log; do
    [ -f "$f" ] && { log "  == $f =="; tail -12 "$f" | tee -a "$LOG"; }
done
log "-- 当前内存 --"
grep -E "^MemAvailable|^MemFree" /proc/meminfo | tee -a "$LOG"
log "-- overlay --"; df -h /overlay | tail -1 | tee -a "$LOG"

section "5. 连通性复测"
for u in "http://www.baidu.com" "https://www.google.com" "https://gemini.google.com/" "https://chatgpt.com/" "https://github.com/"; do
    printf "  %-34s " "$u"
    curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -m 20 -x http://127.0.0.1:7890 "$u" 2>/dev/null || echo "FAIL"
done
log "日志：$LOG"
