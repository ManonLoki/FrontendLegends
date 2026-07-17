extends SceneTree

const STATE_REGRESSION := preload("res://tests/combat/state_regression.gd")

var failures: Array[String] = []

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state = root.get_node("GameState")
	var combat = root.get_node("CombatSystem")
	var npc_system = root.get_node("NpcSystem")
	state.use_test_save_path("combat_alignment")
	# 进攻、闪避、招架采用独立触发曲线；防守侧封顶更低，避免命中后连续二次完全落空。
	_assert_true(combat.rules.MOVE_TRIGGER_RULES == {
		"attack": {"base": 0.22, "per_move": 0.025, "cap": 0.45},
		"dodge": {"base": 0.12, "per_move": 0.015, "cap": 0.27},
		"parry": {"base": 0.18, "per_move": 0.020, "cap": 0.35},
	}, "三类招式应使用 v4 的独立触发曲线")
	_assert_true(
		is_equal_approx(combat.rules.move_trigger_rate("attack", 1), 0.245)
			and is_equal_approx(combat.rules.move_trigger_rate("attack", 20), 0.45)
			and is_equal_approx(combat.rules.move_trigger_rate("dodge", 20), 0.27)
			and is_equal_approx(combat.rules.move_trigger_rate("parry", 20), 0.35),
		"招式触发率应按各自增量成长，并分别封顶 45%/27%/35%"
	)
	_assert_true(combat.rules.ATTACK_MOVE_STATUS_TABLE == {20: "paralysis", 40: "weakness", 50: "poison", 70: "paralysis", 80: "weakness", 90: "poison"}, "攻击招式应仅在六个明确档位附加异常")
	var jiu_ri: Dictionary = npc_system.build_instance("jiu_ri")
	var jiu_ri_mp_bonus: int = int(combat.rules.npc_combat_bonus(jiu_ri).get("mp_max", 0))
	_assert_true(combat.rules.npc_inner_power(jiu_ri) == 150 and jiu_ri_mp_bonus == 150 and combat.rules.npc_mp_max(jiu_ri) == 3300, "九日精力应由 150 内功、根骨修正和 150 点已装备功法上限加成共同构成")
	var jiu_ri_veteran := jiu_ri.duplicate(true)
	jiu_ri_veteran.combatRank = "veteran"
	_assert_true(combat.rules.npc_hp_max(jiu_ri_veteran) == 460 and combat.rules.npc_hp_max(jiu_ri) == 506, "同一套属性的精英 NPC 应在 460 基础体力上按 1.10 位阶缩放到 506")
	var student: Dictionary = npc_system.build_instance("xiao_xue_sheng")
	_assert_true(combat.rules.npc_mp_max(student) == 0 and combat.rules.npc_hp_max(student) == 48, "小学生作为 noncombatant 应只有 48 体力且没有精力，不得形成同级战斗耐久")
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

	# 摸鱼是每场一次的即时辅助动作，单次最多恢复本场体力上限的 20%，且不执行敌方行动。
	state.combat_state.hp = 1
	state.combat_state.mp = int(session.player_max_hp)
	var enemy_before: int = int(session.enemy_hp)
	var rest_cap: int = int(ceil(float(session.player_max_hp) * combat.player_recovery.REST_HEAL_RATIO))
	var rest_result: Dictionary = combat.rest(session)
	_assert_true(bool(rest_result.ok) and int(rest_result.amount) == rest_cap and state.combat_state.hp == 1 + rest_cap and state.combat_state.mp == int(session.player_max_hp) - rest_cap, "摸鱼应按 1:1 消耗精力，且单次恢复封顶为体力上限的 20%")
	_assert_true(int(session.enemy_hp) == enemy_before, "摸鱼本身不得推进敌方回合")
	var hp_before_second_rest: int = state.combat_state.hp
	var mp_before_second_rest: int = state.combat_state.mp
	session.player_status.weakness = 2
	var second_rest: Dictionary = combat.rest(session)
	_assert_true(not bool(second_rest.get("ok", true)) and state.combat_state.hp == hp_before_second_rest and state.combat_state.mp == mp_before_second_rest and int(session.player_status.weakness) == 2 and str(second_rest.get("message", "")).contains("已经摸过一次"), "同一场战斗第二次摸鱼应被拒绝，且不得改变资源或消耗异常状态")
	session.player_status.erase("weakness")
	session.player_rest_used = false
	state.combat_state.hp -= 1
	state.combat_state.mp = 1
	session.player_status.paralysis = 1
	var hp_before_skip: int = state.combat_state.hp
	var mp_before_skip: int = state.combat_state.mp
	var skipped_rest: Dictionary = combat.rest(session)
	_assert_true(bool(skipped_rest.get("skipped", false)) and state.combat_state.hp == hp_before_skip and state.combat_state.mp == mp_before_skip, "麻痹应在摸鱼前结算并跳过该回合")

	# 战斗药品每场最多使用两次；拒绝第三次时不得消耗物品、触发冷却或推进敌方行动。
	var registry = root.get_node("DataRegistry")
	registry.items.test_battle_medicine = {"name": "测试伤药", "kind": "medicine", "stackLimit": 9, "effects": {"hp": 9}}
	state.inventory.test_battle_medicine = 3
	state.combat_state.hp = int(session.player_max_hp) - 30
	var enemy_before_item: int = int(session.enemy_hp)
	var first_item_result: Dictionary = combat.use_item(session, "test_battle_medicine")
	var second_item_result: Dictionary = combat.use_item(session, "test_battle_medicine")
	var hp_before_third_item: int = state.combat_state.hp
	session.player_status.weakness = 2
	var third_item_result: Dictionary = combat.use_item(session, "test_battle_medicine")
	_assert_true(bool(first_item_result.ok) and bool(second_item_result.ok) and int(session.get("player_medicine_uses", 0)) == 2 and state.inventory.get("test_battle_medicine", 0) == 1 and state.combat_state.hp == int(session.player_max_hp) - 12, "前两次战斗用药应各消耗一件并按配置恢复体力")
	_assert_true(not bool(third_item_result.get("ok", true)) and state.combat_state.hp == hp_before_third_item and state.inventory.get("test_battle_medicine", 0) == 1 and int(session.player_status.weakness) == 2 and str(third_item_result.get("message", "")).contains("两次"), "第三次战斗用药应被次数上限拒绝，且不得消耗库存或异常状态")
	_assert_true(int(session.enemy_hp) == enemy_before_item and not state.item_cooldowns.has("test_battle_medicine"), "战斗用药不得推进敌方回合或写入脱战冷却")
	session.player_medicine_uses = 0
	session.player_max_hp = 100
	session.player_status = {"poison": 1}
	state.combat_state.hp = 95
	var poison_item_result: Dictionary = combat.use_item(session, "test_battle_medicine")
	_assert_true(bool(poison_item_result.get("skipped", false)) and state.combat_state.hp == 90 and state.inventory.get("test_battle_medicine", 0) == 1 and int(session.player_medicine_uses) == 0, "毒发把当前体力钳到新上限时不得消耗药品或本场用药次数")
	registry.items.erase("test_battle_medicine")
	state.inventory.erase("test_battle_medicine")

	# NPC 摸鱼同样受单次次数与 18% 体力上限约束。
	var npc_rest_session: Dictionary = combat.create_session("jiu_ri", true)
	var npc_rest_ai: Dictionary = npc_rest_session.enemy.get("ai", {}).duplicate(true)
	npc_rest_ai.restUseRate = 1.0
	npc_rest_ai.restHpRatio = 1.0
	npc_rest_ai.restCharges = 1
	npc_rest_session.enemy.ai = npc_rest_ai
	npc_rest_session.enemy_hp = 1
	npc_rest_session.enemy_mp = int(npc_rest_session.enemy_mp_max)
	var npc_rest_cap: int = int(ceil(float(npc_rest_session.enemy_max_hp) * combat.enemy_ai.REST_HEAL_RATIO))
	var npc_rest_result: Dictionary = combat.enemy_ai._try_rest(npc_rest_session, npc_rest_ai, int(npc_rest_session.enemy_hp), int(npc_rest_session.enemy_max_hp), int(npc_rest_session.enemy_mp), float(npc_rest_session.enemy_hp) / float(npc_rest_session.enemy_max_hp))
	var npc_hp_after_rest: int = int(npc_rest_session.enemy_hp)
	var npc_mp_after_rest: int = int(npc_rest_session.enemy_mp)
	var npc_second_rest: Dictionary = combat.enemy_ai._try_rest(npc_rest_session, npc_rest_ai, npc_hp_after_rest, int(npc_rest_session.enemy_max_hp), npc_mp_after_rest, float(npc_hp_after_rest) / float(npc_rest_session.enemy_max_hp))
	_assert_true(bool(npc_rest_result.get("ok", false)) and npc_hp_after_rest == 1 + npc_rest_cap and int(npc_rest_session.get("enemy_rest_uses", 0)) == 1, "NPC 摸鱼单次恢复应封顶为最大体力的 18%")
	_assert_true(npc_second_rest.is_empty() and int(npc_rest_session.enemy_hp) == npc_hp_after_rest and int(npc_rest_session.enemy_mp) == npc_mp_after_rest, "NPC 摸鱼次数耗尽后不得再次恢复")

	# NPC 加力每次只动用四分之一内功；连续两击也不得按完整内功逐击扣除。
	var force_session: Dictionary = combat.create_session("jiu_ri", true)
	var force_ai: Dictionary = force_session.enemy.get("ai", {}).duplicate(true)
	force_ai.forceUseRate = 1.0
	force_ai.forceRatio = combat.NPC_FORCE_INNER_POWER_RATIO
	force_session.enemy.ai = force_ai
	force_session.enemy_mp = 1000
	var npc_inner_power: int = combat.rules.npc_inner_power(force_session.enemy)
	var npc_force_per_hit: int = int(ceil(float(npc_inner_power) * combat.NPC_FORCE_INNER_POWER_RATIO))
	seed(29)
	var force_hit_one := {"damage": 100}
	var force_hit_two := {"damage": 100}
	var force_extra_one: int = combat._apply_enemy_force_power(force_session, force_hit_one)
	var force_extra_two: int = combat._apply_enemy_force_power(force_session, force_hit_two)
	_assert_true(npc_inner_power == 150 and npc_force_per_hit == 38 and int(force_session.enemy_mp) == 1000 - npc_force_per_hit * 2, "NPC 连续两击加力应每击只消耗 ceil(150×25%)=38 精力")
	_assert_true(force_extra_one >= 24 and force_extra_one <= 30 and force_extra_two >= 24 and force_extra_two <= 30, "四分之一内功加力应按递减收益为 100 基础伤害追加约 24~30 点")

	# 高烈度单击必定触发当场重伤，并立即削减本场上限。
	var old_max: int = int(session.player_max_hp)
	var heavy_hit := {"damage": old_max}
	var injury_tag: String = combat._maybe_apply_in_battle_injury(session, heavy_hit)
	_assert_true(not injury_tag.is_empty() and int(session.player_max_hp) < old_max, "高烈度攻击应立即触发重伤并削减上限")
	_assert_true(int(session.player_in_battle_injury) > 0 and int(heavy_hit.damage) == int(floor(old_max * 0.85)), "当场重伤应累计伤势并把该击伤害折减为 85%")

	# 逃跑率必须同时保留成功与失败（封顶 90%，保底 10%），失败写入权威战报。
	seed(17)
	var escaped := 0
	var stopped := 0
	for _index in 100:
		if combat.flee(session): escaped += 1
		else: stopped += 1
	_assert_true(escaped > 0 and stopped > 0, "逃跑不得必成或必败")
	_assert_true(session.log.has("逃跑不及，被拦了下来！"), "逃跑失败应写入明确战报")

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
	var battle_clock_before: float = state.game_time_sec
	game.game_runtime_controller._process(1.0)
	_assert_true(is_equal_approx(state.game_time_sec, battle_clock_before), "战斗 HUD 激活时不得推进生存时钟或触发等待回血")
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
	_assert_true(game.battle_ui.submenu.is_empty() and game.battle_ui.session.log.size() == log_before_item + 1 and game.battle_ui.session.log[-1] == "身上没有伤药。", "没有回血药时用药入口应写入明确战报且不推进回合")
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
	_assert_true(bool(ult_result.ok) and state.combat_state.mp == mp_before_ult - int(ults[0].mp_cost), "未设置加力时，玩家连击绝招应只扣除固定绝招精力")
	var ult_named_in_log := false
	for line in ult_session.log:
		if str(line).contains(str(ults[0].name)): ult_named_in_log = true
	_assert_true(ult_named_in_log and str(ult_session.log[-1]).begins_with("连击"), "连击绝招应逐击写入名称并汇总命中战报")
	_assert_true(int(ult_session.enemy_hp) <= enemy_before_ult, "绝招不得恢复敌方体力")

	# NPC 使用同一套绝招执行器；连击加力逐击结算，但每击只动用四分之一内功。
	state.profile.attributes.constitution = 500
	state.combat_state.injury = 0
	state.combat_state.hp = state.player_effective_hp_max()
	var npc_ult_session: Dictionary = combat.create_session("xiao_bu_er", true)
	var npc_ult_ai: Dictionary = npc_ult_session.enemy.get("ai", {}).duplicate(true)
	npc_ult_ai.forceUseRate = 1.0
	npc_ult_ai.forceRatio = combat.NPC_FORCE_INNER_POWER_RATIO
	npc_ult_session.enemy.ai = npc_ult_ai
	var npc_ults: Array = combat._npc_ults(npc_ult_session.enemy)
	_assert_true(npc_ults.size() == 2, "高阶 NPC 应解锁两档门派绝招")
	var npc_mp_before: int = int(npc_ult_session.enemy_mp)
	var npc_ult_force_per_hit: int = int(ceil(float(combat.rules.npc_inner_power(npc_ult_session.enemy)) * combat.NPC_FORCE_INNER_POWER_RATIO))
	seed(47)
	var npc_ult_result: Dictionary = combat._enemy_use_ult(npc_ult_session, npc_ults[0], true)
	var npc_ult_named := false
	for line in npc_ult_session.log:
		if str(line).contains(str(npc_ults[0].name)): npc_ult_named = true
	var expected_npc_ult_spend: int = int(npc_ults[0].mp_cost) + int(npc_ult_result.get("landed", 0)) * npc_ult_force_per_hit
	_assert_true(bool(npc_ult_result.ok) and npc_mp_before - int(npc_ult_session.enemy_mp) == expected_npc_ult_spend, "NPC 连击绝招应扣固定消耗，并仅对实际命中的每击追加四分之一内功消耗")
	_assert_true(npc_ult_named and npc_ult_session.log.size() > 1, "NPC 连击绝招应逐击生成战报")
	state.profile.attributes.constitution = 25

	# 战败惩罚必须真实扣除三类资源、满血复活并立即写入隔离测试存档。
	state.combat_state.injury = 0
	state.combat_state.hp = 0
	session.player_reached_zero = true
	seed(23)
	var defeat_text: String = root.get_node("BattleResolve").resolve_defeat(session, true)
	_assert_true(int(state.profile.vitals.money) < 1000 and int(state.profile.vitals.potential) < 1000 and int(state.profile.vitals.experience) < 1000, "死亡应扣除 Token、潜能和经验")
	_assert_true(state.combat_state.hp == state.player_effective_hp_max(), "死亡惩罚后应按伤势后的有效上限满血复活")
	_assert_true(defeat_text.contains("Token") and FileAccess.file_exists(state.current_save_path()), "死亡惩罚应生成结算文案并立即保存")
	var post_start_recovery: Dictionary = STATE_REGRESSION.post_start_recovery_result(root)
	_assert_true(post_start_recovery.skipped and post_start_recovery.status_empty and post_start_recovery.mp == 50, "毒发令摸鱼失去恢复空间时应标记为已消耗行动，避免清除状态却免掉敌方回合")
	var downgrade: Dictionary = STATE_REGRESSION.defeat_downgrade_result(root)
	_assert_true(downgrade.level == 9 and downgrade.constitution == 25 and downgrade.mp == downgrade.mp_max and downgrade.mp_max == 9 and downgrade.hp == downgrade.hp_max, "战败令基础架构 10→9 后，应在保存前重算派生架构并把当前体力/精力钳到新上限")

	state.delete_save()
	if failures.is_empty():
		print("combat_alignment_test: PASS")
		quit(0)
	else:
		print("combat_alignment_test: FAIL (%d)" % failures.size())
		quit(1)
