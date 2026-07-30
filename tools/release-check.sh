#!/bin/sh
# 发布前唯一闸门：数据、预设、源码规模和 Godot 行为必须全部通过。

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

npm run data:check
node tools/validate-release.mjs
./tools/check_file_size.sh
./tools/run-godot-tests.sh

printf '%s\n' 'Release check: PASS'
