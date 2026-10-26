#!/bin/ash
# bootfix.sh - 修复冷启动后 ShellCrash 无法自愈的三个隐患
#   1. /tmp/ShellCrash 在 tmpfs 上，重启后不存在；rc.local 在 S99 之前补建
#   2. guardian.sh 没有 mkdir，冷启动后它调 start.sh 必然失败
#   3. legacy 看门狗 cron 被 start.sh stop 删掉后不会自己回来 -> 加自愈
# 保留 init.d/shellcrash 处于 disabled：start_old=ON 时走 procd 会产生僵尸实例

TS=$(date +%Y%m%d-%H%M%S)
BK=/root/backup/pre-bootfix-$TS
mkdir -p "$BK"
cp -f /etc/rc.local "$BK"/rc.local
cp -f /etc/ShellCrash/guardian.sh "$BK"/guardian.sh
cp -f /etc/crontabs/root "$BK"/root.crontab
echo "backup -> $BK"

# 1) rc.local
if grep -q 'mkdir -p /tmp/ShellCrash' /etc/rc.local; then
    echo "rc.local: already patched"
else
    awk 'NR==1{print; print ""; print "# ShellCrash: /tmp is tmpfs, create runtime dir before S99shellcrash"; print "mkdir -p /tmp/ShellCrash"; next} {print}' \
        /etc/rc.local > /tmp/rc.local.new
    cat /tmp/rc.local.new > /etc/rc.local
    rm -f /tmp/rc.local.new
    echo "rc.local: patched"
fi

# 2) guardian.sh
if grep -q 'mkdir -p /tmp/ShellCrash' /etc/ShellCrash/guardian.sh; then
    echo "guardian.sh: already patched"
else
    awk '/^LOG=\/tmp\/ShellCrash\/guardian.log/{print "mkdir -p /tmp/ShellCrash 2>/dev/null"; print; next} {print}' \
        /etc/ShellCrash/guardian.sh > /tmp/guardian.new
    cat /tmp/guardian.new > /etc/ShellCrash/guardian.sh
    chmod 755 /etc/ShellCrash/guardian.sh
    rm -f /tmp/guardian.new
    echo "guardian.sh: patched"
fi

# 2b) guardian 自愈 legacy 看门狗 cron（插在末尾 exit 0 之前）
if grep -q 'cron lifeline' /etc/ShellCrash/guardian.sh; then
    echo "guardian cron self-heal: already present"
else
    cat > /tmp/lifeline.txt <<'EOF'

# cron lifeline: start.sh stop 会重写 crontab 并删掉 legacy 看门狗行,
# 这里每 5 分钟检查一次, 缺失就补回 (2026-10-20 事故)
if ! grep -q 'start_legacy_wd.sh' /etc/crontabs/root 2>/dev/null; then
    echo '* * * * * /bin/ash /etc/ShellCrash/starts/start_legacy_wd.sh shellcrash #ShellCrash保守模式守护进程' >> /etc/crontabs/root
    crontab /etc/crontabs/root 2>/dev/null
    log "FIX: restored legacy watchdog cron line"
fi
EOF
    awk 'NR==FNR{blk=blk $0 "\n"; next} {lines[FNR]=$0} END{for(i=1;i<FNR;i++)print lines[i]; printf "%s", blk; print lines[FNR]}' \
        /tmp/lifeline.txt /etc/ShellCrash/guardian.sh > /tmp/guardian.new
    cat /tmp/guardian.new > /etc/ShellCrash/guardian.sh
    chmod 755 /etc/ShellCrash/guardian.sh
    head -1 /etc/ShellCrash/guardian.sh | grep -q '^#!' || echo "WARN: guardian.sh 首行不是 shebang（检查插入位置）"
    rm -f /tmp/guardian.new /tmp/lifeline.txt
    echo "guardian cron self-heal: inserted before final exit"
fi

# 3) 补齐当前 crontab（去重）
grep -v 'start_legacy_wd.sh\|task/task.sh 106' /etc/crontabs/root > /tmp/cron.new
cat >> /tmp/cron.new <<'EOF'
* * * * * /bin/ash /etc/ShellCrash/starts/start_legacy_wd.sh shellcrash #ShellCrash保守模式守护进程
*/10 * * * * /etc/ShellCrash/task/task.sh 106 #运行时每10分钟自动保存面板配置
EOF
crontab /tmp/cron.new
rm -f /tmp/cron.new
/etc/init.d/cron restart 2>/dev/null
echo "crontab: updated"

echo "=== verify ==="
echo "-- rc.local head --"
head -6 /etc/rc.local
echo "-- guardian mkdir --"
grep -n 'mkdir -p /tmp/ShellCrash' /etc/ShellCrash/guardian.sh | head -2
echo "-- crontab --"
crontab -l
echo "-- init enabled (expected rc=1, legacy mode) --"
/etc/init.d/shellcrash enabled; echo "rc=$?"
echo "-- watchdog dry run (proxy already up, should exit fast) --"
/bin/ash /etc/ShellCrash/starts/start_legacy_wd.sh shellcrash; echo "wd_rc=$?"
echo "=== done ==="
