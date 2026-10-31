#!/usr/bin/env bash
# 运行 test/ 下的每个 Lua 测试（每个用独立的 XDG 目录，避免残留数据互相污染）
#
#   ./scripts/test.sh              # 全部
#   ./scripts/test.sh backend      # 只跑名字含 backend 的
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT=$PWD

filter="${1:-}"
passed=0
failed=0
failed_names=()

for file in test/*.lua; do
	[ -e "$file" ] || continue
	name=$(basename "$file" .lua)
	if [ -n "$filter" ] && [[ "$name" != *"$filter"* ]]; then
		continue
	fi

	home=$(mktemp -d)
	XDG_DATA_HOME=$home/data \
		XDG_STATE_HOME=$home/state \
		XDG_CACHE_HOME=$home/cache \
		nvim --headless -u NONE -l "$file" >"$home/out" 2>&1
	code=$?

	if [ $code -eq 0 ]; then
		passed=$((passed + 1))
		printf '  ok   %s\n' "$name"
	else
		failed=$((failed + 1))
		failed_names+=("$name")
		printf '  FAIL %s (exit %d)\n' "$name" "$code"
		sed 's/^/       /' "$home/out" | tail -20
	fi
	rm -rf "$home"
done

echo
printf '%d passed, %d failed\n' "$passed" "$failed"
if [ $failed -ne 0 ]; then
	printf 'failed: %s\n' "${failed_names[*]}"
	exit 1
fi
