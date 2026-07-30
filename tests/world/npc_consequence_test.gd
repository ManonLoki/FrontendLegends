extends SceneTree
## 静态 NPC 的击败冷却、累计战绩与重逢反馈必须随角色存档保持。

const NPC_ID := "ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state: Node = root.get_node("GameState")
	var npcs: Node = root.get_node("NpcSystem")
	state.use_test_save_path("npc-consequences")
	state.delete_save()
	state.create_profile("后果测试", {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25})
	var marked: Dictionary = npcs.mark_defeated(NPC_ID)
	_assert_true(bool(marked.persistent) and npcs.is_defeated(NPC_ID) and npcs.defeat_count(NPC_ID) == 1, "静态 NPC 击败冷却与次数应进入世界状态")
	_assert_true(npcs.consequence_summary(NPC_ID).contains("落败 1 次"), "NPC 表现层应能读取累计后果摘要")
	state.save_game()
	state.profile = {}
	_assert_true(state.load_game() and npcs.is_defeated(NPC_ID) and npcs.defeat_count(NPC_ID) == 1, "重新读档后 NPC 仍应处于击败冷却")
	state.advance_time(npcs.DEFAULT_RESPAWN_SECONDS + 1.0)
	_assert_true(not npcs.is_defeated(NPC_ID) and npcs.defeat_count(NPC_ID) == 1, "冷却结束只恢复人物，不应抹去累计战绩")
	_assert_true(npcs.dialogue(NPC_ID).contains("上次是我大意了"), "NPC 重返世界后对白应反馈此前的交手后果")
	npcs.clear_defeated()
	state.delete_save()
	print("npc_consequence_test: PASS" if failures.is_empty() else "npc_consequence_test: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
