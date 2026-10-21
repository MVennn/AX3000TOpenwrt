#!/bin/bash
# fix-router.sh — PC 端一键：切到路由器 WiFi → 推送恢复脚本执行 → 切回热点
# 用法： bash "<仓库>/recovery/local-tools/fix-router.sh"
set -u
# 本机网络名：默认写占位符，用环境变量覆盖（SSID_ROUTER / SSID_HOTSPOT / ROUTER_IP）
SSID_ROUTER="${SSID_ROUTER:-YOUR_ROUTER_SSID}"
SSID_HOTSPOT="${SSID_HOTSPOT:-YOUR_HOTSPOT_SSID}"
ROUTER_IP="${ROUTER_IP:-10.0.0.1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ASKPASS="${ASKPASS:-$HERE/askpass.sh}"
SCRIPT="${SCRIPT:-$HERE/../recover-now.sh}"
SSH="/usr/bin/ssh"
export SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force DISPLAY=:0

echo "=== [1/4] 切到路由器 WiFi ($SSID_ROUTER) ==="
netsh wlan connect name="$SSID_ROUTER" 2>&1 | tr -d '\r'
for i in $(seq 1 20); do
  sleep 2
  if ping -n 1 -w 800 "$ROUTER_IP" >/dev/null 2>&1; then
    echo "    路由器已可达"
    break
  fi
done
ping -n 1 -w 1000 "$ROUTER_IP" >/dev/null 2>&1 || { echo "!! 路由器仍不可达，放弃修复"; }

echo "=== [2/4] 推送并执行恢复脚本 ==="
"$SSH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=12 \
       -o ServerAliveInterval=10 root@"$ROUTER_IP" "sh -s" < "$SCRIPT"
RC=$?
echo "=== ssh 退出码: $RC ==="

echo "=== [3/4] 切回热点 ($SSID_HOTSPOT) ==="
netsh wlan connect name="$SSID_HOTSPOT" 2>&1 | tr -d '\r'
sleep 3
echo "=== [4/4] 结束 ==="
