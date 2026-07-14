extends SceneTree

var failures: Array[String] = []

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game_state = root.get_node("GameState")
	var skill_system = root.get_node("SkillSystem")
	var quest_system = root.get_node("QuestSystem")
	var inventory_system = root.get_node("InventorySystem")
	var data_registry = root.get_node("DataRegistry")
	game_state.delete_save()
	game_state.create_profile("alignment-test", {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25})
	game_state.profile.vitals.potential = 100000
	game_state.profile.vitals.money = 100000

	# 全地图 NPC 目标注册：读取 TMX property npcId，并保留地图显示名。
	var placed_targets: Array[Dictionary] = data_registry.list_placed_npc_targets()
	_assert_true(not placed_targets.is_empty(), "全地图 NPC 任务目标池不应为空")
	var found_darkxue_tutor := false
	for placed_target in placed_targets:
		_assert_true(not data_registry.get_npc(str(placed_target.get("npc_id", ""))).is_empty(), "任务目标池不应包含未注册 NPC")
		if str(placed_target.get("npc_id", "")) == "dao_shi" and str(placed_target.get("map_id", "")) == "DarkXue":
			found_darkxue_tutor = str(placed_target.get("map_name", "")) == "DARK学"
	_assert_true(found_darkxue_tutor, "应从 DarkXue.tmx 收集导师及 DARK学地图名")
	for excluded_target in data_registry.list_placed_npc_targets(["jiu_ri"]):
		_assert_true(str(excluded_target.get("npc_id", "")) != "jiu_ri", "任务发布者应能从目标池排除")
	quest_system.reset_runtime()
	seed(1)
	var generated_ring: Dictionary = quest_system.offer_generator("ring_cunzhang")
	_assert_true(bool(generated_ring.get("ok", false)), "九日环应能从真实地图生成 NPC 目标")
	_assert_true(not str(generated_ring.get("message", "")).contains("【】"), "九日环文案不应缺失地图或 NPC")
	var generated_target: Dictionary = quest_system.active.get("generator:ring_cunzhang", {}).get("target", {})
	_assert_true(not str(generated_target.get("target_id", "")).is_empty() and not str(generated_target.get("map_name", "")).is_empty(), "九日环运行时应保存 NPC 与地图显示名")

	# 学艺逻辑本身不离散快进；时间由 Game 场景的逐帧统一时钟推进。
	game_state.profile.sect = "NG神教"
	game_state.profile.master = "xue_lang"
	var before_time: float = game_state.game_time_sec
	var learn_result: Dictionary = skill_system.learn_tick("xue_lang", "basicStrength")
	_assert_true(not learn_result.has("reason"), "学习 tick 应实际推进")
	_assert_true(is_equal_approx(game_state.game_time_sec, before_time), "学习 tick 不应重复推进全局时钟")

	# 练功：有效 tick 推进 1 秒，并消耗精力。
	var skills: Dictionary = skill_system.ensure_skills()
	skills.levels.basicStrength = 5
	skills.levels.ng_code_decorator = 1
	game_state.profile.vitals.neigong = 5
	game_state.combat_state.hp = game_state.player_effective_hp_max()
	game_state.combat_state.mp = 5
	before_time = game_state.game_time_sec
	var practice_result: Dictionary = skill_system.practice_tick("ng_code_decorator")
	_assert_true(bool(practice_result.get("ok", false)), "练功 tick 应成功")
	_assert_true(is_equal_approx(game_state.game_time_sec - before_time, 1.0), "练功 tick 未推进 1 秒")

	# 冥想：装备基础/高级架构后，有效标准帧推进 1/60 秒。
	skills.levels.basicConstitution = 2
	skills.levels.ng_arch_zone = 1
	skills.equipped_special.arch = "ng_arch_zone"
	game_state.profile.vitals.neigong = 1
	game_state.combat_state.mp = 0
	before_time = game_state.game_time_sec
	var meditation_result: Dictionary = skill_system.meditate_tick()
	_assert_true(bool(meditation_result.get("ok", false)), "冥想 tick 应成功")
	_assert_true(is_equal_approx(game_state.game_time_sec - before_time, 1.0 / 60.0), "冥想 tick 未推进 1/60 秒")

	# 学习经验曲线：覆盖基础/门派、低/中/满级与悟性倍率，锁定原项目取整顺序。
	var basic_def: Dictionary = data_registry.get_skill("basicStrength")
	var sect_def: Dictionary = data_registry.get_skill("ng_code_decorator")
	var curve_cases := [
		[basic_def, 6, 0.65, 6], [basic_def, 40, 0.65, 204], [basic_def, 100, 0.65, 1300],
		[basic_def, 6, 1.0, 8], [basic_def, 60, 1.0, 712], [basic_def, 100, 1.0, 2000],
		[basic_def, 2, 1.25, 4], [basic_def, 80, 1.25, 1594],
		[sect_def, 6, 0.8, 8], [sect_def, 40, 0.8, 374], [sect_def, 100, 0.8, 2400],
		[sect_def, 6, 1.0, 10], [sect_def, 80, 1.0, 1912], [sect_def, 100, 1.25, 3750],
	]
	for test_case in curve_cases:
		var actual: int = skill_system._learn_required(test_case[0], test_case[1], test_case[2])
		_assert_true(actual == test_case[3], "学习曲线不符：Lv.%d rate %.2f，应为 %d，实际 %d" % [test_case[1], test_case[2], test_case[3], actual])

	# 九日送物：缺物品不结算，装备中不结算，卸下后扣物并发奖。
	quest_system.reset_runtime()
	quest_system.active["generator:ring_cunzhang"] = {
		"generator_id": "ring_cunzhang", "kind": "ring", "giverNpcId": "jiu_ri",
		"target": {"target_id": "brendan_eich", "target_name": "Brendan Eich", "map_id": "Angular"},
		"item_id": "fagun", "item_name": "法棍",
		"reward": {"experience": 75, "potential": 50, "money": 60},
	}
	var missing_message: String = quest_system.interact_npc("brendan_eich")
	_assert_true(missing_message.contains("不在你身上"), "九日送物缺少道具时不应结算")
	inventory_system.add_item("fagun", 1)
	# 运行时按装备表判定；这里直接构造旧档/配置可能出现的已装备状态。
	game_state.equipment.weapon = "fagun"
	var equipped_message: String = quest_system.interact_npc("brendan_eich")
	_assert_true(equipped_message.contains("卸下来"), "九日送物装备中时不应结算")
	game_state.equipment.weapon = ""
	var exp_before := int(game_state.profile.vitals.experience)
	quest_system.interact_npc("brendan_eich")
	_assert_true(inventory_system.count("fagun") == 0, "九日送物成功后应扣除道具")
	_assert_true(int(game_state.profile.vitals.experience) > exp_before, "九日送物成功后应发放奖励")

	# 杀人环：逐单即时结算，满 ringSize 后计数归零并进入冷却。
	quest_system.reset_runtime()
	exp_before = int(game_state.profile.vitals.experience)
	for index in 10:
		quest_system.active["generator:killring_huoyanwang"] = {
			"generator_id": "killring_huoyanwang",
			"target": {"target_id": "kill_target_%d" % index, "target_name": "目标", "map_id": "KaiyuanTown"},
			"reward": {"experience": 50, "potential": 50, "money": 40},
		}
		quest_system.on_enemy_defeated("kill_target_%d" % index)
	_assert_true(int(game_state.profile.vitals.experience) == exp_before + 500, "杀人环每单应按快照即时发奖")
	_assert_true(int(quest_system.ring_progress.get("killring_huoyanwang", -1)) == 0, "杀人环满环后计数应归零")
	_assert_true(float(quest_system.cooldown_until.get("killring_huoyanwang", 0.0)) > game_state.game_time_sec, "杀人环结算后应进入冷却")

	# DARK 学项目：5 秒锁定对话结束前不扣体力、不发奖，结束后才结算。
	quest_system.reset_runtime()
	quest_system.active.novice_darkxue_project = {
		"completion_giver_id": "darkxue_computer", "target": "测试项目", "hp_cost": 10,
		"reward": {"experience": 7, "potential": 6, "money": 5},
	}
	game_state.combat_state.hp = 100
	exp_before = int(game_state.profile.vitals.experience)
	var hp_before := int(game_state.combat_state.hp)
	var project_intro: Dictionary = quest_system.begin_novice_completion("darkxue_computer")
	_assert_true(float(project_intro.get("lock_seconds", 0.0)) == 5.0, "项目交付应锁定对话 5 秒")
	_assert_true(int(game_state.combat_state.hp) == hp_before and int(game_state.profile.vitals.experience) == exp_before, "锁定对话结束前不应结算项目")
	quest_system.finish_novice_completion("darkxue_computer")
	_assert_true(int(game_state.combat_state.hp) == hp_before - 10, "项目完成后应扣除体力")
	_assert_true(int(game_state.profile.vitals.experience) == exp_before + 7, "项目完成后应发放奖励")

	# 通用寻物差事：回发布者时验物、扣物、发奖并开始冷却。
	quest_system.reset_runtime()
	data_registry.quest_generators.test_errand = {
		"type": "errand", "giverNpcId": "test_giver", "cooldownSec": 10,
		"pool": {"items": ["fagun"]}, "reward": {"experience": 3, "potential": 2, "money": 1},
	}
	quest_system.offer_generator("test_errand")
	exp_before = int(game_state.profile.vitals.experience)
	quest_system.interact_npc("test_giver")
	_assert_true(int(game_state.profile.vitals.experience) == exp_before, "寻物差事缺物品时不应发奖")
	inventory_system.add_item("fagun", 1)
	quest_system.interact_npc("test_giver")
	_assert_true(inventory_system.count("fagun") == 0, "寻物差事交付后应扣除目标物品")
	_assert_true(int(game_state.profile.vitals.experience) == exp_before + 3, "寻物差事交付后应发奖")

	# 通用送信差事：目标 NPC 保留普通对话，只标记见面，回发布者交差。
	quest_system.reset_runtime()
	data_registry.quest_generators.test_talk_errand = {
		"type": "errand", "giverNpcId": "test_talk_giver", "cooldownSec": 10,
		"pool": {"npcs": ["brendan_eich"]}, "reward": {"experience": 4, "potential": 0, "money": 0},
	}
	quest_system.offer_generator("test_talk_errand")
	_assert_true(quest_system.interact_npc("brendan_eich").is_empty(), "送信目标不应覆盖普通 NPC 对话")
	exp_before = int(game_state.profile.vitals.experience)
	quest_system.interact_npc("test_talk_giver")
	_assert_true(int(game_state.profile.vitals.experience) == exp_before + 4, "见过送信目标后应可回发布者交差")

	# 通用悬赏：击杀只标 ready，必须回发布者才结算。
	quest_system.reset_runtime()
	data_registry.quest_generators.test_bounty = {
		"type": "bounty", "giverNpcId": "test_bounty_giver", "cooldownSec": 10,
		"enemyPool": ["brendan_eich"], "spawnMaps": ["KaiyuanTown"],
		"reward": {"experience": 5, "potential": 0, "money": 0},
	}
	quest_system.offer_generator("test_bounty")
	exp_before = int(game_state.profile.vitals.experience)
	quest_system.on_enemy_defeated("brendan_eich")
	_assert_true(int(game_state.profile.vitals.experience) == exp_before, "普通悬赏击杀时不应即时发奖")
	quest_system.interact_npc("test_bounty_giver")
	_assert_true(int(game_state.profile.vitals.experience) == exp_before + 5, "普通悬赏应回发布者领赏")
	data_registry.quest_generators.erase("test_errand")
	data_registry.quest_generators.erase("test_talk_errand")
	data_registry.quest_generators.erase("test_bounty")

	# 道具：满状态不消耗；有效使用展示原设定效果文案；冷却提示含剩余秒数。
	game_state.inventory.clear()
	inventory_system.add_item("linxing_kafei", 2)
	var capacity := 200 + int(game_state.profile.attributes.strength) * 10
	game_state.profile.vitals.food = capacity
	game_state.profile.vitals.water = capacity
	var item_result: Dictionary = inventory_system.use_item("linxing_kafei")
	_assert_true(not bool(item_result.get("ok", false)) and inventory_system.count("linxing_kafei") == 2, "食物饮水已满时不应消耗道具")
	game_state.profile.vitals.water = capacity - 20
	item_result = inventory_system.use_item("linxing_kafei")
	_assert_true(bool(item_result.get("ok", false)) and str(item_result.message).contains("饮水 +50"), "道具信息应展示配置效果")
	_assert_true(inventory_system.count("linxing_kafei") == 1, "有效使用应消耗一个道具")
	item_result = inventory_system.use_item("linxing_kafei")
	_assert_true(not bool(item_result.get("ok", false)) and str(item_result.message).contains("还需"), "冷却提示应展示剩余游戏秒数")
	game_state.equipment.weapon = "hhkb"
	game_state.save_game()
	game_state.equipment.weapon = "mbp"
	game_state.load_game()
	_assert_true(str(game_state.equipment.weapon).is_empty(), "穿戴状态不应写入或恢复自存档")

	# 对话分页与顶部进度条几何：一行一页；相机视口顶部 16px、水平居中。
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	_assert_true(game._prop_display_name({"name": "电脑", "properties": {"questGiver": "darkxue_computer"}}) == "电脑", "Props 对话标题应使用 Tiled 对象名")
	var pages: Array[String] = game._paginate_dialogue("第一行\n第二行")
	_assert_true(pages.size() == 2 and pages[0] == "第一行" and pages[1] == "第二行", "对话正文每个逻辑行应独占一页")
	game._show_dialogue("测试", "单页")
	_assert_true(game.dialogue_auto_close_at_msec > 0, "普通单页对话应启用 5 秒自动关闭")
	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	escape_event.pressed = true
	game._input(escape_event)
	_assert_true(game.dialogue_open, "ESC 不应关闭原设定中的对话框")
	game.dialogue_auto_close_at_msec = 1
	game._update_dialogue_auto_close()
	_assert_true(not game.dialogue_open, "单页对话到期后应自动关闭")
	game.learning_skill_id = "basicStrength"
	game._render_learning_progress()
	var meter: Control = game.learning_progress_widgets[0]
	var view_rect: Rect2 = game._game_view_rect()
	var scale: float = game._display_scale()
	_assert_true(is_equal_approx(meter.position.y, view_rect.position.y + 16.0 * scale), "学习进度条顶部 margin 应为 16px")
	_assert_true(is_equal_approx(meter.position.x + meter.size.x * 0.5, view_rect.position.x + view_rect.size.x * 0.5), "学习进度条应相对摄像机视口水平居中")
	var meditation_meter := Control.new()
	game.hud.add_child(meditation_meter)
	game._layout_top_progress_meter(meditation_meter)
	_assert_true(is_equal_approx(meditation_meter.position.y, view_rect.position.y + 16.0 * scale), "冥想进度条顶部 margin 应为 16px")
	_assert_true(is_equal_approx(meditation_meter.position.x + meditation_meter.size.x * 0.5, view_rect.position.x + view_rect.size.x * 0.5), "冥想进度条应相对摄像机视口水平居中")

	# 学习进度条生命周期：进入右栏不显示；空格启动才显示；资源阻断后立即消失。
	game._clear_learning_progress_widgets()
	game.learning_skill_id = ""
	game.learn_open = true
	game.nearby_npc_id = "xue_lang"
	game_state.profile.sect = "NG神教"
	game_state.profile.master = "xue_lang"
	game.learn_all_items = skill_system.learn_options_for_npc("xue_lang")
	game.learn_category_index = 0
	game._rebuild_learn_categories()
	game._handle_learn_key(KEY_SPACE)
	_assert_true(not game.learn_focus_category and game.learning_progress_widgets.is_empty(), "仅进入功法右栏时不应显示学习进度条")
	game._handle_learn_key(KEY_SPACE)
	_assert_true(not str(game.learning_skill_id).is_empty() and game.learning_progress_widgets.size() == 1, "选中功法按空格后才应显示并启动进度条")
	game_state.profile.vitals.potential = 0
	game._update_continuous_skill_actions(0.02)
	_assert_true(str(game.learning_skill_id).is_empty() and game.learning_progress_widgets.is_empty(), "潜能不足无法继续学习后进度条应消失")
	var selected_skill: String = game.learn_items[game.learn_index]
	var selected_definition: Dictionary = data_registry.get_skill(selected_skill)
	var selected_level: int = skill_system.level(selected_skill)
	var selected_rate: float = clampf(1.0 - (float(game_state.profile.attributes.wisdom) - 25.0) * 0.02, 0.65, 1.25)
	var selected_required: int = skill_system._learn_required(selected_definition, selected_level + 1, selected_rate)
	skill_system.ensure_skills().learnProgress[selected_skill] = selected_required - 1
	game_state.profile.vitals.potential = 1
	game_state.profile.vitals.money = 100000
	var money_before := int(game_state.profile.vitals.money)
	game._handle_learn_key(KEY_SPACE)
	game._update_continuous_skill_actions(0.02)
	_assert_true(skill_system.level(selected_skill) == selected_level + 1, "最后 1 点潜能应在同一 tick 完成升级")
	_assert_true(int(game_state.profile.vitals.potential) == 0, "每个有效学习 tick 应只消耗 1 点潜能")
	_assert_true(int(game_state.profile.vitals.money) == money_before - ceili(float(selected_required) * 0.8), "升级 Token 学费应为本级经验需求的 80% 向上取整")
	_assert_true(str(game.learning_skill_id).is_empty() and game.learning_progress_widgets.is_empty(), "学习完成后进度条应立即消失")
	game.queue_free()

	game_state.delete_save()
	if failures.is_empty():
		print("alignment_test: PASS")
		quit(0)
	else:
		print("alignment_test: FAIL (%d)" % failures.size())
		quit(1)
