#!/bin/sh
# FrontendLegends 的 Godot 唯一命令行入口。
# Godot 4.7 在 macOS 受限环境中无法创建默认 user://logs 时可能直接崩溃，
# 因此每次运行都把日志显式写入可写的 /tmp，并保留日志用于失败诊断。

set -eu

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$tool_dir/.." && pwd)
default_macos_godot="/Applications/Godot.app/Contents/MacOS/Godot"

if [ -n "${GODOT_BIN:-}" ]; then
	godot_bin=$GODOT_BIN
elif [ -x "$default_macos_godot" ]; then
	godot_bin=$default_macos_godot
else
	godot_bin=godot
fi

godot_log_file=${FRONTEND_LEGENDS_GODOT_LOG:-/tmp/frontend-legends-godot-$$.log}
echo "Godot log: $godot_log_file" >&2

exec "$godot_bin" --path "$project_root" --log-file "$godot_log_file" "$@"
