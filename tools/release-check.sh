#!/bin/sh
# 发布前唯一闸门：数据、预设、源码规模和 Godot 行为必须全部通过。

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

npm run data:check
node tools/validate-release.mjs
./tools/check_file_size.sh
./tools/run-godot-tests.sh

web_export_dir=$(mktemp -d /tmp/frontend-legends-web-export.XXXXXX)
cleanup_web_export() {
	case "$web_export_dir" in
		/tmp/frontend-legends-web-export.*) rm -rf -- "$web_export_dir" ;;
	esac
}
trap cleanup_web_export EXIT
trap 'exit 1' HUP INT TERM
web_export_console="$web_export_dir/export-console.log"
if ! FRONTEND_LEGENDS_TEST_SUITE=release-web-export \
	FRONTEND_LEGENDS_GODOT_LOG="$web_export_dir/godot.log" \
	./tools/godot-safe.sh --headless --export-release Web "$web_export_dir/index.html" >"$web_export_console" 2>&1; then
	tail -100 "$web_export_console" >&2
	exit 1
fi
node tools/validate-web-export.mjs "$web_export_dir/index.html"

printf '%s\n' 'Release check: PASS'
