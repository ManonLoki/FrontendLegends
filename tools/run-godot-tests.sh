#!/bin/sh
# 使用安全日志入口依次运行全部 Godot 无界面回归。

set -eu

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

"$tool_dir/godot-safe.sh" --headless --script res://tests/alignment_test.gd
"$tool_dir/godot-safe.sh" --headless --script res://tests/audio/bgm_controller_test.gd
"$tool_dir/godot-safe.sh" --headless --script res://tests/combat_alignment_test.gd
"$tool_dir/godot-safe.sh" --headless --script res://tests/combat/ultimate_ability_rules_test.gd
"$tool_dir/godot-safe.sh" --headless --script res://tests/combat/combat_move_effects_test.gd
"$tool_dir/godot-safe.sh" --headless --script res://tests/combat/ultimate_abilities_integration_test.gd
"$tool_dir/godot-safe.sh" --headless --script res://tests/combat_balance_test.gd
