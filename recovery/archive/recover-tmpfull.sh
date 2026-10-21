#!/bin/ash
# 恢复：/tmp (tmpfs 116MB) 被内核测试文件写满 -> ShellCrash 生成配置 ENOSPC -> 退基础配置 -> 代理/DNS 全断
# 用法（在路由器上）：sh /tmp/recover-tmpfull.sh
# 或从 PC：cat recover-tmpfull.sh | ssh root@10.0.0.1 "cat > /tmp/recover-tmpfull.sh && sh /tmp/recover-tmpfull.sh"

echo "== 1. 清理测试文件 =="
rm -f /tmp/m132 /tmp/m132.gz /tmp/scmeta.tar.gz /tmp/sc-meta.tar.gz \
      /tmp/mihomo-new /tmp/mihomo-arm64.gz /tmp/core_test_out.txt /tmp/_core_test.sh
rm -rf /tmp/sctest /tmp/sctest2 /tmp/sct2 /tmp/core_tmp
df -h /tmp
echo

echo "== 2. 检查持久化源是否完好（应为 700KB~1MB，非 0） =="
ls -la /etc/ShellCrash/yamls/config.yaml /etc/ShellCrash/yamls/rules.yaml \
       /etc/ShellCrash/yamls/proxy-groups.yaml /etc/ShellCrash/yamls/user.yaml 2>&1
echo

echo "== 3. 删除坏掉的运行时配置并重启（start.sh 会重跑 clash_modify.sh 重新生成） =="
sh /etc/ShellCrash/start.sh stop
killall -9 CrashCore 2>/dev/null
rm -f /tmp/ShellCrash/config.yaml /tmp/ShellCrash/error.yaml /etc/ShellCrash/.start_error
sh /etc/ShellCrash/start.sh start
sleep 5

echo
echo "== 4. 校验 =="
/etc/ShellCrash/CrashCore.raw -t -d /etc/ShellCrash -f /tmp/ShellCrash/config.yaml 2>&1 | tail -3
echo "-- listeners --"
netstat -lntp 2>/dev/null | grep -E ':7892|:1053|:9999'
echo "-- crashcore pid --"
pidof CrashCore
echo "-- config key counts --"
grep -c '^  - name:' /tmp/ShellCrash/config.yaml
grep -c '^rules:' /tmp/ShellCrash/config.yaml
echo

echo "== 5. 出口验证 =="
grep -n 'DOMAIN-SUFFIX,opencode.ai\|RULE-SET,cn' /tmp/ShellCrash/config.yaml | head -3
curl -s --max-time 8 -o /dev/null -w 'baidu=%{http_code} %{time_total}s\n' http://www.baidu.com
curl -s --max-time 12 -x http://127.0.0.1:7890 -o /dev/null -w 'google-via-proxy=%{http_code} %{time_total}s\n' https://www.google.com
echo "== done =="
