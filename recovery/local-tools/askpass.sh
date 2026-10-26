#!/bin/sh
# askpass.sh —— 给 ssh 提供 root 口令。
#
# 口令不写在脚本里。取值顺序：
#   1) 环境变量 ROUTER_PASSWORD
#   2) 本目录下的 .router-password（单行，已被 .gitignore 排除）
#   3) $HOME/.router-password
# 都没有就退出并说明怎么办 —— 绝不给出一个错的空口令。
#
# 用法：export ROUTER_PASSWORD='...' 后，由 fix-router.sh / verify-gemini.sh 间接调用
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"

if [ -n "${ROUTER_PASSWORD:-}" ]; then
	printf '%s\n' "$ROUTER_PASSWORD"
	exit 0
fi

for f in "$HERE/.router-password" "$HOME/.router-password"; do
	if [ -s "$f" ]; then
		head -n 1 "$f"
		exit 0
	fi
done

echo "askpass: 没有 root 口令。请设置环境变量 ROUTER_PASSWORD，" >&2
echo "        或在 $HERE/.router-password 里写一行口令（该文件不入库）。" >&2
exit 1
