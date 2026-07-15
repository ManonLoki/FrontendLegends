extends SceneTree

var failures: Array[String] = []

# 断言验证true相关逻辑，并保持调用方状态一致。
func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

# 处理initialize相关逻辑，并保持调用方状态一致。
func _initialize() -> void:
	call_deferred("_run")

# 执行run相关逻辑，并保持调用方状态一致。
func _run() -> void:
	var state = root.get_node("GameState")
	var combat = root.get_node("CombatSystem")
	state.use_test_save_path("combat_alignment")
	# 玩家与 NPC 必须共用参照项目的被动招式触发曲线和异常档位。
	_assert_true(is_equal_approx(combat.rules.MOVE_TRIGGER_BASE, 0.25) and is_equal_approx(combat.rules.MOVE_TRIGGER_PER_MOVE, 0.04) and is_equal_approx(combat.rules.MOVE_TRIGGER_CAP, 0.55), "NPC 招式触发率应为 25% + 每招 4%，封顶 55%")
	_assert_true(combat.rules.ATTACK_MOVE_STATUS_TABLE == {20: "paralysis", 40: "weakness", 50: "poison", 70: "paralysis", 80: "weakness", 90: "poison"}, "NPC 攻击招式的六个异常档位应与参照项目一致")
	_assert_true(combat.rules.npc_mp_max(root.get_node("NpcSystem").build_instance("jiu_ri")) == 3750, "九日精力上限应按装备内功等级、25 点单位和架构修正计算")
	state.delete_save()
	state.create_profile("战斗测试", {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25})
	state.profile.vitals.money = 1000
	state.profile.vitals.potential = 1000
	state.profile.vitals.experience = 1000

	# 伤势必须压低有效上限，百分比以真实上限为分母。
	var true_max: int = state.player_hp_max()
	state.combat_state.injury = 20
	state.combat_state.hp = state.player_effective_hp_max()
	_assert_true(state.player_effective_hp_max() == true_max - 20, "伤势应逐点压低有效体力上限")
	_assert_true(state.player_effective_hp_percent() == int(round(float(true_max - 20) / true_max * 100.0)), "受伤百分比应按有效上限/真实上限计算")

	var session: Dictionary = combat.create_session("jiu_ri", true)
	_assert_true(int(session.player_max_hp) == state.player_effective_hp_max(), "开战应使用受伤后的有效体力上限")
	_assert_true(int(session.player_true_max_hp) == true_max, "战斗会话应保留真实体力上限供百分比展示")

	# 摸鱼是即时辅助动作：只换算己方 HP/MP，不执行敌方行动。
	state.combat_state.hp -= 10
	state.combat_state.mp = 6
	var enemy_before: int = int(session.enemy_hp)
	var rest_result: Dictionary = combat.rest(session)
	_assert_true(bool(rest_result.ok) and state.combat_state.hp == int(session.player_max_hp) - 4 and state.combat_state.mp == 0, "摸鱼应按 1:1 消耗精力恢复体力")
	_assert_true(int(session.enemy_hp) == enemy_before, "摸鱼本身不得推进敌方回合")
	state.combat_state.hp -= 1
	state.combat_state.mp = 1
	session.player_status.paralysis = 1
	var hp_before_skip: int = state.combat_state.hp
	var mp_before_skip: int = state.combat_state.mp
	var skipped_rest: Dictionary = combat.rest(session)
	_assert_true(bool(skipped_rest.get("skipped", false)) and state.combat_state.hp == hp_before_skip and state.combat_state.mp == mp_before_skip, "麻痹应在摸鱼前结算并跳过该回合")

	# 战斗药品直接消耗一件并回血，不触发物品冷却或敌方行动。
	var registry = root.get_node("DataRegistry")
	registry.items.test_battle_medicine = {"name": "测试伤药", "kind": "medicine", "stackLimit": 9, "effects": {"hp": 9}}
	state.inventory.test_battle_medicine = 1
	state.combat_state.hp = int(session.player_max_hp) - 10
	var enemy_before_item: int = int(session.enemy_hp)
	var item_result: Dictionary = combat.use_item(session, "test_battle_medicine")
	_assert_true(bool(item_result.ok) and state.inventory.get("test_battle_medicine", 0) == 0 and state.combat_state.hp == int(session.player_max_hp) - 1, "战斗药品应消耗一件并按配置恢复体力")
	_assert_true(int(session.enemy_hp) == enemy_before_item and not state.item_cooldowns.has("test_battle_medicine"), "战斗用药不得推进敌方回合或写入脱战冷却")
	registry.items.erase("test_battle_medicine")

	# 高烈度单击必定触发当场重伤，并立即削减本场上限。
	var old_max: int = int(session.player_max_hp)
	var heavy_hit := {"damage": old_max}
	var injury_tag: String = combat._maybe_apply_in_battle_injury(session, heavy_hit)
	_assert_true(not injury_tag.is_empty() and int(session.player_max_hp) < old_max, "高烈度攻击应立即触发重伤并削减上限")
	_assert_true(int(session.player_in_battle_injury) > 0 and int(heavy_hit.damage) == int(floor(old_max * 0.85)), "当场重伤应累计伤势并按参照项目折减该击伤害")

	# 逃跑率必须同时保留成功与失败（封顶 90%，保底 10%），失败写入权威战报。
	seed(17)
	var escaped := 0
	var stopped := 0
	for _index in 100:
		if combat.flee(session): escaped += 1
		else: stopped += 1
	_assert_true(escaped > 0 and stopped > 0, "逃跑不得必成或必败")
	_assert_true(session.log.has("逃跑不及，被拦了下来！"), "逃跑失败应写入参照项目战报")

	# HUD 协调层：体力必须显示有效上限百分比，摸鱼不能暗中触发反击。
	state.combat_state.injury = 20
	state.combat_state.hp = state.player_effective_hp_max() - 5
	state.combat_state.mp = 5
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.nearby_npc_id = "jiu_ri"
	game.battle_ui.lethal = true
	seed(1)
	game.battle_ui.start()
	state.combat_state.injury = 20
	state.combat_state.hp = state.player_effective_hp_max() - 5
	state.combat_state.mp = 5
	game.battle_ui.session.player_max_hp = state.player_effective_hp_max()
	game.battle_ui.session.player_true_max_hp = state.player_hp_max()
	game.battle_ui.session.player_hp = state.combat_state.hp
	game.battle_ui.refresh()
	var expected_suffix := "（%d%%）" % state.player_effective_hp_percent()
	var found_percent := false
	var report_label: Label
	for widget in game.battle_ui.widgets:
		if widget is Label and str(widget.text) == expected_suffix:
			found_percent = true
		if widget is Label and widget.has_meta("battle_report"):
			report_label = widget
	_assert_true(found_percent, "战斗 HUD 应显示有效体力上限占真实上限的百分比")
	_assert_true(report_label != null, "战斗 HUD 应创建独立战报区域")
	if report_label != null:
		_assert_true(report_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT and report_label.vertical_alignment == VERTICAL_ALIGNMENT_TOP, "战报应左对齐并从区域顶部开始显示")
		_assert_true(report_label.position.y >= 190.0 and report_label.position.y + report_label.size.y <= game.battle_panel.size.y, "战报应位于战斗信息区下方且不超出战斗面板")
	var report_history: Array[String] = []
	for index in range(10):
		report_history.append("战报%d" % index)
	game.battle_ui.session.log = report_history
	game.battle_ui.refresh()
	var expected_report: Array[String] = []
	for index in range(2, 10):
		expected_report.append("战报%d" % index)
	_assert_true(game.battle_ui._report_text() == "\n".join(expected_report), "战报应保留最近八条记录")
	game.battle_ui.submenu = "ult"
	game.battle_ui.submenu_items = [{"name": "测试绝招", "mp_cost": 1}]
	var submenu_report_rect: Rect2 = game.battle_ui._report_rect(game.battle_panel.size, game._display_scale())
	var submenu_height: float = (44.0 + game.battle_ui.submenu_items.size() * 26.0) * game._display_scale()
	var submenu_top: float = game.battle_panel.size.y - submenu_height - 76.0 * game._display_scale()
	_assert_true(submenu_report_rect.end.y <= submenu_top or submenu_report_rect.position.y >= submenu_top + submenu_height, "子菜单打开时战报不得与菜单重叠")
	game.battle_ui.submenu = ""
	game.battle_ui.submenu_items = []
	# 隔离摸鱼本身的行为；开战先手可能随机附带麻痹，不应污染此断言。
	game.battle_ui.session.player_status = {}
	var enemy_hp_before_rest: int = int(game.battle_ui.session.enemy_hp)
	var log_before_rest: int = game.battle_ui.session.log.size()
	game.battle_ui._rest()
	_assert_true(int(game.battle_ui.session.enemy_hp) == enemy_hp_before_rest, "战斗中摸鱼不得触发敌方行动")
	_assert_true(game.battle_ui.session.log.size() == log_before_rest + 1, "摸鱼只应追加自身一条战报")
	state.combat_state.hp -= 1
	game.battle_ui.session.player_hp = state.combat_state.hp
	var log_before_item: int = game.battle_ui.session.log.size()
	game.battle_ui._open_submenu("item")
	_assert_true(game.battle_ui.submenu.is_empty() and game.battle_ui.session.log.size() == log_before_item + 1 and game.battle_ui.session.log[-1] == "身上没有伤药。", "没有回血药时用药入口应按参照项目写入战报且不推进回合")
	game.battle_ui.end("")
	_assert_true(game.battle_ui.active and game.battle_ui.ended and game.battle_panel.visible, "战斗结束后应保留最终战报，等待确认键收尾")
	game.battle_ui._finish_end()
	game.battle_ui.active = true
	game.battle_panel.visible = true
	game.battle_ui.end("死亡结算测试", true)
	game.battle_ui._finish_end()
	_assert_true(game.dialogue_open and game.dialogue_after_last.is_valid(), "生死战死亡应显示惩罚对话，并在确认后返回 Splash")
	game._close_dialogue()
	game.queue_free()
	await process_frame

	# 绝招：菜单只列精力可支付项；施展时扣精力并生成权威战报，本函数本身不代跑敌方回合。
	state.profile.sect = "NG神教"
	var skills: Dictionary = root.get_node("SkillSystem").ensure_skills()
	skills.levels.basicConstitution = 80
	skills.levels.ng_arch_zone = 80
	skills.equipped_basic.arch = "basicConstitution"
	skills.equipped_special.arch = "ng_arch_zone"
	state.profile.vitals.cultivation = 100
	state.combat_state.mp = state.player_mp_max()
	state.combat_state.injury = 0
	state.combat_state.hp = state.player_effective_hp_max()
	var ult_session: Dictionary = combat.create_session("jiu_ri", true)
	var ults: Array = root.get_node("SkillSystem").unlocked_ults()
	_assert_true(ults.size() == 2, "架构功法 80 级应解锁两档门派绝招")
	var mp_before_ult: int = state.combat_state.mp
	var enemy_before_ult: int = int(ult_session.enemy_hp)
	seed(31)
	var ult_result: Dictionary = combat.use_ult(ult_session, ults[0])
	_assert_true(bool(ult_result.ok) and state.combat_state.mp <= mp_before_ult - int(ults[0].mp_cost), "绝招应扣除固定精力，连击加力可逐击继续扣除")
	var ult_named_in_log := false
	for line in ult_session.log:
		if str(line).contains(str(ults[0].name)): ult_named_in_log = true
	_assert_true(ult_named_in_log and str(ult_session.log[-1]).begins_with("连击"), "连击绝招应逐击写入名称并按参照项目汇总命中战报")
	_assert_true(int(ult_session.enemy_hp) <= enemy_before_ult, "绝招不得恢复敌方体力")

	# NPC 使用同一套绝招执行器、逐击加力与战报，不得退回另一套简化公式。
	state.profile.attributes.constitution = 500
	state.combat_state.injury = 0
	state.combat_state.hp = state.player_effective_hp_max()
	var npc_ult_session: Dictionary = combat.create_session("xiao_bu_er", true)
	var npc_ults: Array = combat._npc_ults(npc_ult_session.enemy)
	_assert_true(npc_ults.size() == 2, "高阶 NPC 应解锁两档门派绝招")
	var npc_mp_before: int = int(npc_ult_session.enemy_mp)
	seed(47)
	var npc_ult_result: Dictionary = combat._enemy_use_ult(npc_ult_session, npc_ults[0], true)
	var npc_ult_named := false
	for line in npc_ult_session.log:
		if str(line).contains(str(npc_ults[0].name)): npc_ult_named = true
	_assert_true(bool(npc_ult_result.ok) and int(npc_ult_session.enemy_mp) < npc_mp_before, "NPC 绝招应扣除绝招与逐击加力精力")
	_assert_true(npc_ult_named and npc_ult_session.log.size() > 1, "NPC 连击绝招应逐击生成参照项目战报")
	state.profile.attributes.constitution = 25

	# 战败惩罚必须真实扣除三类资源、满血复活并立即写入隔离测试存档。
	state.combat_state.injury = 0
	state.combat_state.hp = 0
	session.player_damage_taken = 80
	session.player_reached_zero = true
	seed(23)
	var defeat_text: String = root.get_node("BattleResolve").resolve_defeat(session, true)
	_assert_true(int(state.profile.vitals.money) < 1000 and int(state.profile.vitals.potential) < 1000 and int(state.profile.vitals.experience) < 1000, "死亡应扣除 Token、潜能和经验")
	_assert_true(state.combat_state.hp == state.player_effective_hp_max(), "死亡惩罚后应按伤势后的有效上限满血复活")
	_assert_true(defeat_text.contains("Token") and FileAccess.file_exists(state.current_save_path()), "死亡惩罚应生成结算文案并立即保存")

	state.delete_save()
	if failures.is_empty():
		print("combat_alignment_test: PASS")
		quit(0)
	else:
		print("combat_alignment_test: FAIL (%d)" % failures.size())
		quit(1)
