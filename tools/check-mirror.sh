#!/bin/sh
# ============================================================================
# 跨仓镜像一致性门禁
#   AX3000TOpenwrt/system/*  ←→  ShellcrashRules/firewall/*
#
# 用法：
#   sh tools/check-mirror.sh
#   SHELLCRASH_RULES_DIR=/path/to/ShellcrashRules sh tools/check-mirror.sh
#
# 退出码：0 全部一致 / 1 有漂移 / 2 找不到兄弟仓（跳过，不算失败）
#
# 为什么需要这道门禁：
#   这三张 nft 表与生成器在两仓各存一份 —— ShellcrashRules 是正本，
#   AX3000TOpenwrt/system 是「路由器上实际跑的那份」的镜像。靠人记得
#   「改完同步」的结果就是 2026-11-14 实测到的状态：googleroute.nft 与
#   googlecn.nft 一致，而 quicguard-sync.sh 落后 7 项改进（并发诊断互相覆盖、
#   校验失败打印硬编码行号、每次生成都往 /etc 留一份备份、grep 缺 -F、
#   元素数被当成行数报）。这种漂移不报错，只会让路由器跑着旧逻辑。
#
# 判定分两类：
#   同一份文件（字节必须相等）：googleroute.nft / googlecn.nft / quicguard-sync.sh
#   生成物 vs 模板（字节必然不同）：quicguard.nft —— A 侧是 GENERATED（含填满的
#     cn_ip_mirror 集合，约 170KB），S 侧是 TEMPLATE（空集合，约 3KB）。这里
#     只校验「角色没搞反」：A 必须标 GENERATED 且明显更大，S 必须标 TEMPLATE。
# ============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
A=$(cd "$HERE/.." && pwd)
S=${SHELLCRASH_RULES_DIR:-}
if [ -z "$S" ]; then
  S=$(cd "$A/../ShellcrashRules" 2>/dev/null && pwd) || S=""
fi
if [ -z "$S" ] || [ ! -d "$S" ]; then
  echo "[SKIP] 找不到 ShellcrashRules 兄弟仓（用 SHELLCRASH_RULES_DIR 指定路径）"
  exit 2
fi

PASS=0
FAIL=0
md5of() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }

same() {
  _ap="$A/$1"; _sp="$S/$2"
  if [ ! -f "$_ap" ]; then
    echo "[FAIL] missing file: $1"; FAIL=$((FAIL + 1)); return
  fi
  if [ ! -f "$_sp" ]; then
    echo "[FAIL] missing file: $2 (ShellcrashRules)"; FAIL=$((FAIL + 1)); return
  fi
  _ha=$(md5of "$_ap"); _hs=$(md5of "$_sp")
  if [ "$_ha" = "$_hs" ]; then
    echo "[ OK ] $1 == $2  ($_ha)"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $1 != $2"
    echo "       A: $_ha  $(wc -c < "$_ap")B"
    echo "       S: $_hs  $(wc -c < "$_sp")B"
    echo "       fix: cp \"$_sp\" \"$_ap\"   (ShellcrashRules is the source of truth)"
    FAIL=$((FAIL + 1))
  fi
}

generated_from() {
  _ap="$A/$1"; _sp="$S/$2"
  if [ ! -f "$_ap" ] || [ ! -f "$_sp" ]; then
    echo "[FAIL] missing file: $1 or $2"; FAIL=$((FAIL + 1)); return
  fi
  _bad=""
  head -8 "$_ap" | grep -q 'GENERATED' || _bad="$_bad A-side not marked GENERATED"
  head -10 "$_sp" | grep -q 'TEMPLATE' || _bad="$_bad S-side not marked TEMPLATE"
  _ba=$(wc -c < "$_ap"); _bs=$(wc -c < "$_sp")
  # 模板被直接部署时集合为空 -> 每条 QUIC 都被 reject，CN 豁免失效（安卓缩略图卡顿）
  [ "$_ba" -gt "$_bs" ] || _bad="$_bad generated not larger than template (${_ba}B/${_bs}B)"
  if [ -z "$_bad" ]; then
    echo "[ OK ] $1 generated from $2  (${_ba}B generated / ${_bs}B template)"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $1 / $2 wrong role:$_bad"
    FAIL=$((FAIL + 1))
  fi
}

echo "A = $A"
echo "S = $S"
echo "---"
same system/googleroute.nft firewall/tables/googleroute.nft
same system/googlecn.nft   firewall/tables/googlecn.nft
same system/quicguard-sync.sh firewall/quicguard-sync.sh
generated_from system/quicguard.nft firewall/tables/quicguard.nft
echo "---"
if [ "$FAIL" -eq 0 ]; then
  echo "[OK] $PASS item(s) identical"
  exit 0
fi
echo "[FAIL] $FAIL item(s) drifted, $PASS identical"
exit 1
