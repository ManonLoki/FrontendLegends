#!/bin/sh
# 从空导入缓存也能启动的隔离测试入口；每个用例都有独立日志、测试存档前缀和超时。

set -eu

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test_timeout=${FRONTEND_LEGENDS_TEST_TIMEOUT:-90}

run_case() {
	case_name=$1
	shift
	case_log="/tmp/frontend-legends-${case_name}-$$.log"
	echo "==> ${case_name}" >&2
	FRONTEND_LEGENDS_TEST_SUITE="${case_name}-$$" \
	FRONTEND_LEGENDS_GODOT_LOG="$case_log" \
		"$tool_dir/godot-safe.sh" "$@" &
	case_pid=$!
	(
		sleep "$test_timeout"
		if kill -0 "$case_pid" 2>/dev/null; then
			echo "TIMEOUT: ${case_name} exceeded ${test_timeout}s (log: ${case_log})" >&2
			kill -TERM "$case_pid" 2>/dev/null || true
			sleep 2
			kill -KILL "$case_pid" 2>/dev/null || true
		fi
	) &
	watchdog_pid=$!
	set +e
	wait "$case_pid"
	status=$?
	set -e
	kill "$watchdog_pid" 2>/dev/null || true
	wait "$watchdog_pid" 2>/dev/null || true
	if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script|ERROR: Failed to instantiate an autoload' "$case_log"; then
		echo "FAILED: ${case_name} reported a script load error (log: ${case_log})" >&2
		return 1
	fi
	if [ "$status" -ne 0 ]; then
		echo "FAILED: ${case_name} (exit ${status}, log: ${case_log})" >&2
		return "$status"
	fi
}

# --script 不会主动扫描 class_name；--import 会等待资源与全局类缓存全部生成后再退出。
run_case import-scan --headless --import
run_case alignment --headless --script res://tests/alignment_test.gd
run_case bgm --headless --script res://tests/audio/bgm_controller_test.gd
run_case exported-audio --headless --script res://tests/audio/exported_audio_test.gd
run_case combat-alignment --headless --script res://tests/combat_alignment_test.gd
run_case ultimate-rules --headless --script res://tests/combat/ultimate_ability_rules_test.gd
run_case combat-move-effects --headless --script res://tests/combat/combat_move_effects_test.gd
run_case ultimate-integration --headless --script res://tests/combat/ultimate_abilities_integration_test.gd
run_case enemy-ai --headless --script res://tests/combat/enemy_ai_decision_test.gd
run_case combat-balance --headless --script res://tests/combat_balance_test.gd
run_case world-events --headless --script res://tests/world_event_test.gd
run_case npc-consequences --headless --script res://tests/world/npc_consequence_test.gd

echo "Godot test suite: PASS" >&2
