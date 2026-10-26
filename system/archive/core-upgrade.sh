#!/bin/ash
# core-upgrade.sh - mihomo v1.19.28 -> v1.19.32
# 原则：/tmp 只放一个 gz + 一个解压副本；旧 raw 删除后流式写入；失败自动回滚 v1.19.28

NEW=v1.19.32
OLD=v1.19.28
URL="https://github.com/MetaCubeX/mihomo/releases/download/$NEW/mihomo-linux-arm64-$NEW.gz"
OLDURL="https://github.com/MetaCubeX/mihomo/releases/download/$OLD/mihomo-linux-arm64-$OLD.gz"
GZ=/tmp/mihomo-$NEW.gz
BIN=/tmp/mihomo-$NEW
OLDGZ=/tmp/mihomo-$OLD.gz
RAW=/etc/ShellCrash/CrashCore.raw
CFG=/etc/ShellCrash/configs/ShellCrash.cfg
LOG=/root/core-upgrade.log
: > "$LOG"

log(){ printf '%s\n' "$*" | tee -a "$LOG"; }
run(){ log "\$ $*"; "$@" 2>&1 | tee -a "$LOG"; }
restore_cron(){ [ -f /tmp/cron.upgrade.bak ] && crontab /tmp/cron.upgrade.bak 2>/dev/null; }
wait_core(){ i=0; while [ "$i" -lt 30 ]; do pidof CrashCore >/dev/null 2>&1 && netstat -lntp 2>/dev/null | grep -q ':7892' && return 0; sleep 1; i=$((i+1)); done; return 1; }

# 升级前记下原值：回滚要回到「原状」，不能把用户自定义的核心链接清空。
ORIG_CORE_V=$(sed -n 's/^core_v=//p' "$CFG" 2>/dev/null | head -1)
ORIG_CUSTLINK=$(sed -n 's/^custcorelink=//p' "$CFG" 2>/dev/null | head -1)

rollback(){
    log "!!! 进入回滚：重新下载 $OLD"
    rm -f "$RAW"
    curl -L --max-time 300 -o "$OLDGZ" "$OLDURL"
    if [ "$?" = "0" ]; then
        gunzip -c "$OLDGZ" > "$RAW" && chmod +x "$RAW"
        log "回滚核心版本：$(/etc/ShellCrash/CrashCore.raw -v 2>&1 | head -1)"
    else
        log "!!! 回滚下载失败，核心文件缺失，ShellCrash 下次启动会尝试从镜像重下"
    fi
    sed -i "s/^core_v=.*/core_v=$OLD/" "$CFG"
    if [ -n "$ORIG_CUSTLINK" ]; then
        sed -i "s|^custcorelink=.*|custcorelink=$ORIG_CUSTLINK|" "$CFG"
    else
        sed -i 's|^custcorelink=.*|custcorelink=|' "$CFG"
    fi
    rm -f "$OLDGZ"
    mkdir -p /tmp/ShellCrash
    ln -sf "$RAW" /tmp/ShellCrash/CrashCore
    sh /etc/ShellCrash/start.sh start 2>&1 | tail -20 | tee -a "$LOG"
    wait_core || log "!!! 回滚后仍未在 30 秒内就绪"
    restore_cron
    log "=== 回滚结束，日志 $LOG ==="
    exit 1
}

log "================ $(date) ================"
log "upgrade: $OLD -> $NEW"

log ""; log "---- 0. 预检 ----"
run df -h / /tmp
run /etc/ShellCrash/CrashCore.raw -v
run pidof CrashCore

log ""; log "---- 1. 下载（仅一个 gz 到 /tmp）----"
rm -f "$GZ" "$BIN"
run curl -L --max-time 300 -o "$GZ" "$URL"
[ -s "$GZ" ] || { log "!!! 下载失败或文件为空"; exit 1; }
run ls -la "$GZ"
run df -h /tmp

log ""; log "---- 2. 解压并校验 ----"
gunzip -c "$GZ" > "$BIN" || { log "!!! 解压失败"; exit 1; }
chmod +x "$BIN"
run "$BIN" -v
"$BIN" -v 2>&1 | grep -q "$NEW" || { log "!!! 版本号不是 $NEW"; exit 1; }
run "$BIN" -t -d /etc/ShellCrash -f /tmp/ShellCrash/config.yaml
"$BIN" -t -d /etc/ShellCrash -f /tmp/ShellCrash/config.yaml >/dev/null 2>&1 || { log "!!! 新核心配置校验失败"; exit 1; }
log "新核心版本与配置校验通过"

log ""; log "---- 3. 暂停看门狗 ----"
cp -f /etc/crontabs/root /tmp/cron.upgrade.bak
sed -i '/guardian.sh/d;/start_legacy_wd.sh/d' /etc/crontabs/root
crontab /etc/crontabs/root 2>/dev/null
log "已临时移除 guardian / legacy 看门狗"

log ""; log "---- 4. 停止 mihomo ----"
run sh /etc/ShellCrash/start.sh stop
killall -9 CrashCore 2>/dev/null
sleep 1
mkdir -p /tmp/ShellCrash
log "CrashCore=$([ -n "$(pidof CrashCore)" ] && echo 仍在运行 || echo 已停止)"

log ""; log "---- 5. 替换核心（删旧后流式写入）----"
log "-- 删除前 --"; df -h /
rm -f "$RAW"
log "-- 删除后 --"; df -h /
gunzip -c "$GZ" > "$RAW" || { log "!!! 写入失败"; rollback; }
chmod +x "$RAW"
run ls -la "$RAW"
run "$RAW" -v
"$RAW" -v 2>&1 | grep -q "$NEW" || { log "!!! 写入后的核心版本不对"; rollback; }

log ""; log "---- 6. 更新 ShellCrash 记录 ----"
sed -i "s/^core_v=.*/core_v=$NEW/" "$CFG"
sed -i "s|^custcorelink=.*|custcorelink=$URL|" "$CFG"
grep -E '^(core_v|custcorelink)=' "$CFG" | tee -a "$LOG"

log ""; log "---- 7. 启动 ----"
ln -sf "$RAW" /tmp/ShellCrash/CrashCore
run sh /etc/ShellCrash/start.sh start
wait_core && log "CrashCore 已监听 7892" || log "!!! 30 秒内未监听 7892"

log ""; log "---- 8. 运行态校验 ----"
run pidof CrashCore
run netstat -lntp
nft list table inet shellcrash >/dev/null 2>&1 && log "nft 表 inet shellcrash: OK" || log "!!! nft 表缺失"
RCFG=/tmp/ShellCrash/config.yaml
if [ -s "$RCFG" ]; then
    run /etc/ShellCrash/CrashCore.raw -t -d /etc/ShellCrash -f "$RCFG"
    log "分组数：$(grep -c '^  - name:' "$RCFG")"
    grep -Fq '🤖 AI接口' "$RCFG" && log "自定义组 🤖 AI接口: OK" || log "!!! 自定义组缺失"
fi
log "-- 连通性 --"
curl -s --max-time 8 -o /dev/null -w 'baidu_direct=%{http_code} %{time_total}s\n' http://www.baidu.com | tee -a "$LOG"
curl -s --max-time 12 -x http://127.0.0.1:7890 -o /dev/null -w 'google_proxy=%{http_code} %{time_total}s\n' https://www.google.com | tee -a "$LOG"
curl -s --max-time 12 -x http://127.0.0.1:7890 -o /dev/null -w 'opencode_proxy=%{http_code} %{time_total}s\n' https://opencode.ai | tee -a "$LOG"

log ""; log "---- 9. 恢复看门狗并清理 /tmp ----"
restore_cron
crontab -l 2>&1 | tee -a "$LOG"
rm -f "$GZ" "$BIN" "$OLDGZ"
df -h /tmp | tee -a "$LOG"

log ""
if pidof CrashCore >/dev/null 2>&1 && netstat -lntp 2>/dev/null | grep -q ':7892'; then
    log "结果：PASS  $(/etc/ShellCrash/CrashCore.raw -v 2>&1 | head -1)"
else
    log "结果：FAIL  代理未运行，请把 $LOG 发回"
fi
log "日志：$LOG"
