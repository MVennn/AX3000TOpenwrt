#!/bin/ash
# recover-now.sh v2 — ShellCrash / DNS 离线恢复（AX3000T / OpenWrt 25.12）
#
# 触发场景：fake-ip 过滤文件里出现空行 → ShellCrash 把它原样塞进 fake-ip-filter
#           → mihomo DNS 异常/不自愈 → 内网所有域名解析失败
#           → 客户端表现为「WiFi 连上了但没网」
#
# 用法：  ash /tmp/recover-now.sh         完整修复
#         ash /tmp/recover-now.sh check   只诊断，不改任何东西
# 日志：  /root/recover-last.log（overlay 持久化，重启不丢）

MODE="${1:-fix}"
LOG=/root/recover-last.log
: > "$LOG"
log() { printf '%s\n' "$*" | tee -a "$LOG"; }
section() { log ""; log "=============================="; log "$*"; log "=============================="; }
run() { log "\$ $*"; "$@" 2>&1 | tee -a "$LOG"; }

core_up() {
    pidof CrashCore >/dev/null 2>&1 && netstat -lntp 2>/dev/null | grep -q ':7892'
}
dns_up() {
    netstat -lntp 2>/dev/null | grep -q ':1053'
}

section "0. 环境 $(date)"
log "mode=$MODE"
run uptime
run df -h /tmp /overlay

section "1. 修复 fake-ip 过滤文件（去掉空行/注释/重复项）"
FIP=/etc/ShellCrash/configs/fake_ip_filter
if [ "$MODE" = "check" ]; then
    if [ -f "$FIP" ]; then
        log "当前行数=$(wc -l < "$FIP")  空行数=$(grep -c '^[[:space:]]*$' "$FIP")"
        log "-- 过滤清单 --"
        cat "$FIP" | tee -a "$LOG"
    else
        log "!! $FIP 不存在"
    fi
else
    if [ -f "$FIP" ]; then
        cp -f "$FIP" "/root/fake_ip_filter.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null
        log "改前行数=$(wc -l < "$FIP")  空行数=$(grep -c '^[[:space:]]*$' "$FIP")"
        grep -v '^[[:space:]]*$' "$FIP" | grep -v '^[[:space:]]*#' | sed 's/[[:space:]]*$//' | awk '!a[$0]++' > "$FIP.tmp"
        mv -f "$FIP.tmp" "$FIP"
        log "改后行数=$(wc -l < "$FIP")"
        log "-- 过滤清单 --"
        cat "$FIP" | tee -a "$LOG"
    else
        log "!! $FIP 不存在"
    fi
fi

if [ "$MODE" = "check" ]; then
    section "2. 当前状态（check 模式，不做任何修改）"
    run pidof CrashCore
    log "7892 端口: $(netstat -lntp 2>/dev/null | grep -c ':7892')"
    log "1053 DNS 端口: $(netstat -lntp 2>/dev/null | grep -c ':1053')"
    run nft list tables
    log "-- 内网解析测试 --"
    run nslookup www.baidu.com 127.0.0.1
    log "日志：$LOG"
    exit 0
fi

section "2. 先摘掉 DNS 劫持，让内网直连立刻恢复（此时外网不走代理）"
for t in "inet googleroute" "inet shellcrash" "ip shellcrash" "ip6 shellcrash"; do
    if nft list table $t >/dev/null 2>&1; then
        nft delete table $t 2>/dev/null && log "已删除 nft 表：$t"
    fi
done
/etc/init.d/dnsmasq restart >/dev/null 2>&1 && log "dnsmasq 已重启（内网 DNS 回到直连解析）"
sleep 2
log "-- 直连测试 --"
run nslookup www.baidu.com 127.0.0.1

section "3. 停核心、清理运行态配置，重新生成"
[ -f /etc/crontabs/root ] && cp -f /etc/crontabs/root /tmp/cron.recover.bak
sh /etc/ShellCrash/start.sh stop >/dev/null 2>&1
killall -9 CrashCore 2>/dev/null
sleep 1
mkdir -p /tmp/ShellCrash
rm -f /tmp/ShellCrash/config.yaml /tmp/ShellCrash/error.yaml /tmp/ShellCrash/shellcrash.pid
log "运行态配置已清空，交给 start.sh 重新生成"
sh /etc/ShellCrash/start.sh start 2>&1 | tail -30 | tee -a "$LOG"
i=0
while [ $i -lt 30 ]; do
    core_up && break
    sleep 1
    i=$((i+1))
done
core_up && log "CrashCore 已就绪" || log "!! 30 秒内核心未就绪"

section "4. 加载自建 nft 表（DNS 劫持 / QUIC 拦截 / Google 直连）"
for t in quicguard googlecn googleroute; do
    if [ -f "/etc/$t.nft" ]; then
        nft -f "/etc/$t.nft" >/dev/null 2>&1 && log "已加载 inet $t" || log "!! inet $t 加载失败"
    else
        log "!! /etc/$t.nft 不存在"
    fi
done
grep -q 'googleroute' /etc/rc.local 2>/dev/null || log "提醒：rc.local 里没有 googleroute 的开机加载"

section "4.1 重载 fw4 防火墙（start.sh 可能把它留在半加载状态，表现为连上却没网）"
/etc/init.d/firewall restart 2>&1 | tail -5 | tee -a "$LOG"
sleep 3
log "-- WAN 口地址与默认路由 --"
ip -brief addr show 2>/dev/null | grep -E 'wan|br-lan' | tee -a "$LOG"
ip route show default 2>/dev/null | tee -a "$LOG"
if ! ip -brief addr show 2>/dev/null | grep -q 'wan'; then
    log "!! WAN 口没有地址，尝试 ifup wan"
    ifup wan 2>&1 | tail -5 | tee -a "$LOG"
    sleep 5
    ip -brief addr show 2>/dev/null | grep -E 'wan|br-lan' | tee -a "$LOG"
fi
if ! ip route show default 2>/dev/null | grep -q .; then
    log "!! 没有默认路由，尝试 ifup wan"
    ifup wan >/dev/null 2>&1
    sleep 5
    ip route show default 2>/dev/null | tee -a "$LOG"
fi

section "5. 恢复看门狗 crontab"
if [ -f /tmp/cron.recover.bak ]; then
    crontab /tmp/cron.recover.bak 2>/dev/null && log "crontab 已恢复"
    grep -q 'guardian.sh' /etc/crontabs/root 2>/dev/null || {
        echo '*/5 * * * * /bin/ash /etc/ShellCrash/guardian.sh #网络守护:出口组复原+nft表补载+探活' >> /etc/crontabs/root
        crontab /etc/crontabs/root 2>/dev/null && log "已补回 guardian 守护行"
    }
    grep -q 'start_legacy_wd.sh' /etc/crontabs/root 2>/dev/null || {
        echo '* * * * * /bin/ash /etc/ShellCrash/starts/start_legacy_wd.sh shellcrash #ShellCrash保守模式守护进程' >> /etc/crontabs/root
        crontab /etc/crontabs/root 2>/dev/null && log "已补回 legacy 看门狗行"
    }
    run crontab -l
fi

section "6. 校验"
run pidof CrashCore
log "7892=$(netstat -lntp 2>/dev/null | grep -c ':7892')  1053=$(netstat -lntp 2>/dev/null | grep -c ':1053')  9999=$(netstat -lntp 2>/dev/null | grep -c ':9999')"
run nft list tables
if [ -s /tmp/ShellCrash/config.yaml ]; then
    log "运行态 config.yaml = $(wc -c < /tmp/ShellCrash/config.yaml) bytes"
    grep -q '🤖 干净出口' /tmp/ShellCrash/config.yaml && log "自定义组（干净出口）已加载" || log "!! 自定义组缺失（可能回退基础配置）"
else
    log "!! 运行态 config.yaml 不存在"
fi
ls -la /tmp/ShellCrash/error.yaml 2>/dev/null && log "!! 存在 error.yaml = 配置校验失败过（已回退基础配置）" || log "无 error.yaml（未回退）"

section "7. 连通性"
run nslookup www.baidu.com 127.0.0.1
curl -s --max-time 10 -o /dev/null -w '  baidu_direct=%{http_code} %{time_total}s\n' http://www.baidu.com 2>&1 | tee -a "$LOG"
if core_up; then
    curl -s --max-time 15 -x http://127.0.0.1:7890 -o /dev/null -w '  google_via_proxy=%{http_code} %{time_total}s\n' https://www.google.com 2>&1 | tee -a "$LOG"
    curl -s --max-time 15 -x http://127.0.0.1:7890 -o /dev/null -w '  gemini_via_proxy=%{http_code} %{time_total}s\n' https://gemini.google.com/ 2>&1 | tee -a "$LOG"
    curl -s --max-time 10 -x http://127.0.0.1:7890 "https://support.google.com/gemini/answer/13575153" 2>/dev/null | grep -oE "var cc=.[A-Z]{2}" | head -1 | sed 's/^/  google_cc=/' | tee -a "$LOG"
fi

section "完成"
log "日志：$LOG"
log "把上面输出发回给我即可继续排查"
