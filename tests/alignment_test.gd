extends "res://tests/alignment/settings_teleport_suite.gd"
## 综合回归入口；具体断言按领域职责拆分到 tests/alignment/。

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_run_domain_suite()
	var game: Node = await _run_hud_suite()
	await _run_menu_suite(game)
	await _run_settings_teleport_suite(game)
	root.get_node("GameState").delete_save()
	if failures.is_empty():
		print("alignment_test: PASS")
		quit(0)
	else:
		print("alignment_test: FAIL (%d)" % failures.size())
		quit(1)
