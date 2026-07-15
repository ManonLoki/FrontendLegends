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
	var combat_system = root.get_node("CombatSystem")
	var npc_system = root.get_node("NpcSystem")
	game_state.delete_save()
	game_state.create_profile("alignment-test", {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25})
	_assert_true(skill_system.ensure_skills().levels.is_empty(), "新角色不应自带任何基础技能")
	_assert_true(skill_system.ensure_skills().equipped_basic.is_empty() and skill_system.ensure_skills().equipped_special.is_empty(), "新角色不应预装备任何功法")
	_assert_true(int(game_state.profile.vitals.money) == 0 and int(game_state.profile.vitals.potential) == 0, "新角色的 Token 和潜能应从 0 开始")
	game_state.profile.vitals.potential = 100000
	game_state.profile.vitals.money = 100000
	_assert_true(int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 640 and int(ProjectSettings.get_setting("display/window/size/viewport_height")) == 480, "设计分辨率应为 640×480")
	_assert_true(str(ProjectSettings.get_setting("display/window/stretch/aspect")) == "keep", "运行窗口放大时应保持宽高比等量缩放")

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

	# 小不二动态悬赏：严格使用四段姓名、父地图播报、五项基础技能和安全落点。
	quest_system.reset_runtime()
	var bounty_definition: Dictionary = data_registry.quest_generators.bountyring_xiaobuer.duplicate(true)
	bounty_definition.spawnMaps = ["DarkXue"]
	data_registry.quest_generators.bountyring_xiaobuer = bounty_definition
	seed(7)
	var bounty_offer: Dictionary = quest_system.offer_bounty()
	_assert_true(bool(bounty_offer.get("ok", false)), "小不二悬赏应能生成动态目标")
	var bounty: Dictionary = quest_system.get_bounty_target()
	var bounty_name_pattern := RegEx.new()
	bounty_name_pattern.compile("^(傻X|脑残|白痴|霸道|凶狠)(老板|客户|领导|同事|朋友)(赵|钱|孙|李|周|吴|郑|王)(一|二|三|四|五|六|七|八|九|十)$")
	_assert_true(bounty_name_pattern.search(str(bounty.get("target_name", ""))) != null, "悬赏目标姓名应按原项目四段词库生成")
	_assert_true(str(bounty.get("map_name", "")) == "开源镇", "室内悬赏地点应播报父级大地图名称")
	var runtime_bounty: Dictionary = root.get_node("NpcSystem").build_instance(str(bounty.get("target_id", "")))
	_assert_true(runtime_bounty.get("skillLevels", {}).keys().size() == 5 and runtime_bounty.get("equippedSkillIds", []).size() == 5, "悬赏目标应缩放并装备五项基础技能")
	var darkxue_map := TiledMapLoader.new()
	_assert_true(darkxue_map.load_file("res://assets/Map/maps/LoreWorld/KaiyuanTown/DarkXue.tmx"), "应能加载 DARK学室内地图")
	_assert_true(data_registry.map_type("DarkXue") == "inDoor" and data_registry.map_type("KaiyuanTown") == "outDoor", "地图注册阶段应缓存室内/室外类型，传送菜单不得临时重读 TMX")
	_assert_true(not darkxue_map.npc_object_at_tile(7, 6).is_empty(), "NPC point 对象应命中脚下单格")
	_assert_true(darkxue_map.npc_object_at_tile(8, 6).is_empty(), "NPC point 对象不得扩张命中相邻格")
	var bounty_tile: Vector2i = darkxue_map.pick_dynamic_npc_tile()
	_assert_true(bounty_tile.x >= 0 and darkxue_map.is_walkable(bounty_tile.x, bounty_tile.y) and darkxue_map.is_walkable(bounty_tile.x, bounty_tile.y - 1), "室内悬赏 NPC 应落在身前无墙的可行走格")
	_assert_true(darkxue_map.npc_object_at_tile(bounty_tile.x, bounty_tile.y).is_empty(), "动态悬赏 NPC 不应与固定 NPC 重叠")
	quest_system.reset_runtime()

	# 学艺逻辑本身不离散快进；时间由 Game 场景的逐帧统一时钟推进。
	game_state.profile.sect = "NG神教"
	game_state.profile.master = "xue_lang"
	var before_time: float = game_state.game_time_sec
	var learn_result: Dictionary = skill_system.learn_tick("xue_lang", "basicStrength")
	_assert_true(not learn_result.has("reason"), "学习 tick 应实际推进")
	_assert_true(is_equal_approx(game_state.game_time_sec, before_time), "学习 tick 不应重复推进全局时钟")

	# 当前设定：学习/冥想 30 Hz、练功每秒 5 tick。
	_assert_true(is_equal_approx(skill_system.LEARNING_TICK_SECONDS, 1.0 / 30.0), "学习应每秒推进 30 次")
	_assert_true(is_equal_approx(skill_system.MEDITATION_TICK_SECONDS, 1.0 / 30.0), "冥想应每秒推进 30 次")
	_assert_true(is_equal_approx(skill_system.PRACTICE_TICK_SECONDS, 1.0 / 5.0), "练功应每秒推进 5 次")
	game_state.profile.attributes.constitution = 29
	game_state.profile.vitals.cultivation = 130
	_assert_true(game_state.player_mp_max() == 260 and game_state.player_hp_max() == 293, "内功修为 130 的当前精力上限应为 260，并按该上限反哺体力至 293")
	game_state.profile.attributes.constitution = 25

	# 练功：有效 tick 推进 1/5 秒，并消耗精力。
	var skills: Dictionary = skill_system.ensure_skills()
	skills.levels.basicStrength = 5
	skills.levels.ng_code_decorator = 1
	game_state.profile.vitals.cultivation = 5
	game_state.combat_state.hp = game_state.player_effective_hp_max()
	game_state.combat_state.mp = 5
	before_time = game_state.game_time_sec
	var practice_result: Dictionary = skill_system.practice_tick("ng_code_decorator")
	_assert_true(bool(practice_result.get("ok", false)), "练功 tick 应成功")
	_assert_true(is_equal_approx(game_state.game_time_sec - before_time, 1.0 / 5.0), "练功 tick 应推进 1/5 秒")

	# 冥想：装备基础/高级架构后，有效 tick 推进 1/30 秒。
	skills.levels.basicConstitution = 2
	skills.levels.ng_arch_zone = 1
	skills.equipped_special.arch = "ng_arch_zone"
	game_state.profile.vitals.cultivation = 1
	game_state.combat_state.mp = 0
	before_time = game_state.game_time_sec
	var meditation_result: Dictionary = skill_system.meditate_tick()
	_assert_true(bool(meditation_result.get("ok", false)), "冥想 tick 应成功")
	_assert_true(is_equal_approx(game_state.game_time_sec - before_time, 1.0 / 30.0), "冥想 tick 未推进 1/30 秒")

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

	# 三个主场景统一直接使用 640×480 设计坐标，窗口缩放只交给 Godot stretch。
	var splash = load("res://scenes/splash.tscn").instantiate()
	root.add_child(splash)
	await process_frame
	_assert_true(splash.stage.size == Vector2(640.0, 480.0) and splash.stage.scale == Vector2.ONE and splash.stage.position == Vector2.ZERO, "Splash 应与 Game 共用 640×480 原点设计画布")
	_assert_true(splash.prompt.size.x == 640.0 and is_equal_approx(splash.prompt.position.x, 0.0), "Splash 提示文字应在完整设计画布上居中，不得缩在左上角")
	splash.queue_free()
	await process_frame
	var character_creation = load("res://scenes/character_creation.tscn").instantiate()
	root.add_child(character_creation)
	await process_frame
	_assert_true(character_creation.stage.size == Vector2(640.0, 480.0) and character_creation.stage.scale == Vector2.ONE and character_creation.stage.position == Vector2.ZERO, "CharacterCreation 应与 Game 共用 640×480 原点设计画布")
	_assert_true(character_creation.intro_root.scale == Vector2.ONE and character_creation.intro_root.position == Vector2(0.0, 40.0), "CharacterCreation 开场内容应以原始尺寸在设计画布中居中")
	_assert_true(character_creation.form.scale == Vector2.ONE and character_creation.form.position == Vector2(0.0, 40.0), "CharacterCreation 表单应以原始尺寸在设计画布中居中")
	character_creation.queue_free()
	await process_frame

	# 对话分页与顶部进度条几何：一行一页；相机视口顶部 16px、水平居中。
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	# 新 TexturePacker 图集必须直接按 tpsheet 载入，不能继续使用旧横排图集坐标。
	_assert_true(game.player_sprite_regions.size() == 64 and game.player_sprite_layouts.size() == 64, "Player 图集应载入男女、四方向、idle/run 各四帧，共 64 帧")
	_assert_true(npc_system.sprite_regions.size() == 70, "NPC 图集应从 NPC.tpsheet 载入全部 70 个角色区域")
	for gender in ["male", "female"]:
		for direction in ["down", "left", "right", "up"]:
			for motion in ["idle", "run"]:
				for frame in 4:
					var expected_player_frame := "player_%s_%s_%s_%d" % [gender, direction, motion, frame]
					_assert_true(game.player_sprite_regions.has(expected_player_frame), "Player 图集缺少帧：%s" % expected_player_frame)
	for npc_id in data_registry.npcs:
		var npc_sprite := str(data_registry.npcs[npc_id].get("sprite", "npc-1")).get_file().get_basename()
		_assert_true(npc_system.sprite_regions.has(npc_sprite), "NPC %s 引用了图集中不存在的角色 %s" % [npc_id, npc_sprite])
	for player_region_value in game.player_sprite_regions.values():
		var player_region: Rect2 = player_region_value
		_assert_true(Rect2(Vector2.ZERO, game.player_texture.get_size()).encloses(player_region), "Player 帧区域不得越出新 320×116 图集")
	for npc_region_value in npc_system.sprite_regions.values():
		var npc_region: Rect2 = npc_region_value
		_assert_true(Rect2(Vector2.ZERO, game.npc_texture.get_size()).encloses(npc_region), "NPC 帧区域不得越出新 128×244 图集")
	game_state.profile.gender = "male"
	game.facing = Vector2i.DOWN
	game.player_moving = false
	game.animation_frame = 2
	_assert_true(game._player_frame_key() == "player_male_down_idle_2", "男性静止动画应选择 male/down/idle 对应帧")
	game_state.profile.gender = "female"
	game.facing = Vector2i.LEFT
	game.player_moving = true
	game.animation_frame = 3
	_assert_true(game._player_frame_key() == "player_female_left_run_3", "女性移动动画应选择 female/left/run 对应帧")
	var female_run_layout: Dictionary = game.player_sprite_layouts[game._player_frame_key()]
	_assert_true(female_run_layout.canvas_size == Vector2(40.0, 34.0), "Player 裁切帧应归一化到稳定的 40×34 最大逻辑画布，避免动画抖动")
	for player_layout_value in game.player_sprite_layouts.values():
		_assert_true(player_layout_value.canvas_size == Vector2(40.0, 34.0), "所有 Player 性别、方向和动作帧必须共用同一逻辑画布锚点")
	game_state.profile.gender = "male"
	game.facing = Vector2i.DOWN
	game.player_moving = false
	game.animation_frame = 0
	# UI 统一使用 640×480 逻辑坐标；窗口缩放只交给 Godot stretch，避免二次放大。
	_assert_true(is_equal_approx(game._display_scale(), 1.0), "游戏 UI 不应再按物理窗口执行第二次缩放")
	_assert_true(game._game_view_rect() == Rect2(0.0, 0.0, 640.0, 480.0), "地图相机应覆盖完整 640×480 设计画布")
	game.map_context = darkxue_map
	var covered_map_size: Vector2 = Vector2(darkxue_map.width * darkxue_map.tile_width, darkxue_map.height * darkxue_map.tile_height) * game._map_zoom()
	_assert_true(covered_map_size.x >= 640.0 and covered_map_size.y >= 480.0, "小地图应等比 cover 相机，不得产生黑边")
	game._layout_game_view()
	game._toggle_menu()
	var stable_menu_widgets: Array = game.menu_widgets.duplicate()
	for frame in 3:
		game._process(1.0 / 60.0)
	_assert_true(game.menu_widgets.size() == stable_menu_widgets.size(), "菜单连续帧不应重复创建控件")
	for index in stable_menu_widgets.size():
		_assert_true(game.menu_widgets[index] == stable_menu_widgets[index], "菜单连续帧应复用同一批控件，避免闪烁")
	game._toggle_menu()
	var design_rect := Rect2(Vector2.ZERO, Vector2(640.0, 480.0))
	for panel in [game.map_badge_panel, game.menu_panel, game.dialogue_panel, game.details_panel, game.tree_confirm_panel, game.battle_panel]:
		_assert_true(design_rect.encloses(Rect2(panel.position, panel.size)), "%s 必须完整位于设计画布内" % panel.name)
	game._show_inventory()
	var inventory_has_title := false
	var first_inventory_category_y := INF
	for widget in game.details_widgets:
		if widget is Label and str(widget.text).begins_with("背包"):
			inventory_has_title = true
		if widget is Label and str(widget.text) == "食物":
			first_inventory_category_y = widget.position.y
	_assert_true(not inventory_has_title, "背包详情面板不应再创建顶部 Title")
	_assert_true(first_inventory_category_y < 30.0, "移除 Title 后背包内容应上移并回收顶部空间")
	var inventory_hud: PanelContainer = game.detail_huds.inventory.panel
	var inventory_child_count: int = (game.detail_huds.inventory.content as Label).get_child_count()
	game._render_skill_book_widgets()
	_assert_true(game.detail_huds.skill_book.panel != inventory_hud, "背包与功法必须使用不同 HUD 面板")
	_assert_true(not inventory_hud.visible and game.detail_huds.skill_book.panel.visible, "切换详情 HUD 时只应显示目标面板")
	_assert_true(game.detail_huds.inventory.content.get_child_count() == inventory_child_count, "渲染功法 HUD 不得清理或重建背包 HUD 的控件")
	var unique_detail_panel_ids: Dictionary = {}
	for detail_entry in game.detail_huds.values():
		unique_detail_panel_ids[(detail_entry.panel as PanelContainer).get_instance_id()] = true
	_assert_true(unique_detail_panel_ids.size() == game.detail_huds.size(), "每类详情 HUD 必须拥有独立 PanelContainer，不得复用")
	game.nearby_npc_id = "nai_cha_mei_mei"
	game.trade_mode = game.TRADE_MODE_BUY
	game.trade_all_items = data_registry.list_vendor_stock("nai_cha_mei_mei")
	game.trade_open = true
	game._rebuild_trade_categories()
	_assert_true(game.active_detail_hud == "buy" and game.details_panel == game.detail_huds.buy.panel, "购买应使用独立 BuyHUD，不得复用 NPC 菜单")
	_assert_true(game.details_panel != game.npc_menu_panel, "购买 HUD 与 NPC 交互 HUD 必须是不同节点")
	_assert_true(game.detail_huds.buy.panel != game.detail_huds.sell.panel, "购买与典当必须使用不同 HUD 面板")
	var trade_has_title := false
	var trade_has_money := false
	var trade_has_divider := false
	for widget in game.details_widgets:
		if widget is Label and str(widget.text) == "— 购买 —":
			trade_has_title = true
		elif widget is Label and str(widget.text).begins_with("持有 "):
			trade_has_money = true
		elif widget is ColorRect and widget.size.x <= 1.0 and widget.position.y >= 60.0:
			trade_has_divider = true
	_assert_true(trade_has_title and trade_has_money and trade_has_divider, "购买 HUD 应包含标题、余额和左右栏分隔线")
	game._handle_trade_key(KEY_SPACE)
	var repeatedly_traded_item := str(game.trade_items[game.trade_index])
	var count_before_repeated_buy: int = inventory_system.count(repeatedly_traded_item)
	game._handle_trade_key(KEY_SPACE)
	_assert_true(not game.trade_focus_category and str(game.trade_items[game.trade_index]) == repeatedly_traded_item, "购买一次后应停留在当前右栏物品")
	game._handle_trade_key(KEY_SPACE)
	_assert_true(inventory_system.count(repeatedly_traded_item) == count_before_repeated_buy + 2, "右栏按两次空格应连续购买同一物品两次")
	game._handle_trade_key(KEY_ESCAPE)
	_assert_true(game.trade_open and game.trade_focus_category and game.details_panel.visible, "购买右栏按 ESC 应先退回分类层，不得直接关闭")
	_assert_true(not game.npc_menu_open and not game.npc_menu_panel.visible, "购买回退过程中不得重新叠加 NPC 菜单")
	game._handle_trade_key(KEY_ESCAPE)
	_assert_true(not game.trade_open and not game.details_panel.visible, "购买在分类层按 ESC 应关闭整个交易面板")
	_assert_true(not game.npc_menu_open and not game.npc_menu_panel.visible, "关闭购买面板后不得弹回 NPC 菜单")
	game.trade_mode = game.TRADE_MODE_SELL
	game.trade_open = true
	game.trade_all_items.clear()
	for inventory_entry in inventory_system.list_entries():
		game.trade_all_items.append(inventory_entry.get("id", ""))
	game.trade_category_index = 0
	game._rebuild_trade_categories()
	var sold_category: String = game._item_category(repeatedly_traded_item)
	game.trade_category_index = game.trade_categories.find(sold_category)
	game._refresh_trade_items()
	game._handle_trade_key(KEY_SPACE)
	game.trade_index = game.trade_items.find(repeatedly_traded_item)
	var count_before_repeated_sell: int = inventory_system.count(repeatedly_traded_item)
	var sell_quantity_visible := false
	for sell_widget in game.details_widgets:
		if sell_widget is Label and str(sell_widget.text) == "× %d" % count_before_repeated_sell:
			sell_quantity_visible = true
	_assert_true(count_before_repeated_sell > 1 and sell_quantity_visible, "典当物品存在多个时应显示当前剩余数量")
	game._handle_trade_key(KEY_SPACE)
	_assert_true(not game.trade_focus_category, "典当一次后应停留在右栏，不得跳回分类")
	var single_quantity_hidden := true
	for sell_widget in game.details_widgets:
		if sell_widget is Label and str(sell_widget.text) == "× 1":
			single_quantity_hidden = false
	_assert_true(inventory_system.count(repeatedly_traded_item) == 1 and single_quantity_hidden, "典当后只剩一个时数量应实时更新并隐藏单件标记")
	game._handle_trade_key(KEY_SPACE)
	_assert_true(inventory_system.count(repeatedly_traded_item) == count_before_repeated_sell - 2, "右栏按两次空格应连续典当物品两次")
	game._handle_trade_key(KEY_ESCAPE)
	_assert_true(game.trade_open and game.trade_focus_category, "典当右栏按 ESC 应先退回分类层")
	game._handle_trade_key(KEY_ESCAPE)
	_assert_true(not game.trade_open and not game.details_panel.visible and not game.npc_menu_open, "典当分类层按 ESC 应直接关闭且不重开 NPC 菜单")
	game.trade_open = false
	game.details_panel.visible = false
	game.inventory_open = false
	game.nearby_npc_id = "jiu_ri"
	game.battle_ui.start()
	await process_frame
	for widget in game.battle_ui.widgets:
		_assert_true(Rect2(Vector2.ZERO, game.battle_panel.size).encloses(Rect2(widget.position, widget.size)), "战斗 UI 元素不得互相挤出面板边界")
	game.battle_ui.active = false
	game.battle_panel.visible = false
	game.battle_ui._clear_widgets()
	_assert_true(game._prop_display_name({"name": "电脑", "properties": {"questGiver": "darkxue_computer"}}) == "电脑", "Props 对话标题应使用 Tiled 对象名")
	# 歪脖树使用独立 HUD，不得修改或复用 NPC 菜单的正文状态。
	game.npc_menu_content.visible = false
	game._show_delete_confirm()
	_assert_true(game.tree_confirm_panel.visible and not game.tree_confirm_content.text.is_empty(), "歪脖树独立确认 HUD 不应显示为空白面板")
	_assert_true(not game.npc_menu_content.visible and not game.npc_menu_panel.visible, "歪脖树 HUD 不应复用或改变 NPC 菜单")
	game._close_delete_confirm()
	game.map_context = darkxue_map
	_assert_true(game._npc_occupies_tile(Vector2i(7, 6)), "室内固定 NPC 所在格应阻挡玩家移动")
	_assert_true(not game._npc_occupies_tile(Vector2i(8, 6)), "NPC 碰撞只应占脚下格，不应误挡相邻格")
	game.player_tile = Vector2i(7, 7)
	game.facing = Vector2i.UP
	game._refresh_nearby_npc()
	_assert_true(game.nearby_npc_id == "dao_shi", "玩家正面紧邻 NPC 时应允许交互")
	game.facing = Vector2i.RIGHT
	game._refresh_nearby_npc()
	_assert_true(game.nearby_npc_id.is_empty(), "NPC 位于玩家侧面时不得触发交互")
	game.nearby_npc_id = "dao_shi"
	game._interact()
	_assert_true(not game.npc_menu_open, "交互触发前必须重验当前朝向，不得使用旧 NPC 缓存")
	game.move_cooldown = 1.0
	game._apply_facing_input(Vector2.UP)
	_assert_true(game.facing == Vector2i.UP and game.nearby_npc_id == "dao_shi", "移动冷却期间方向输入也必须立即更新交互朝向")
	game.player_tile = Vector2i(12, 7)
	game.facing = Vector2i.UP
	_assert_true(game._has_front_interactable(), "玩家正面紧邻 Props 时应允许交互")
	game.facing = Vector2i.LEFT
	_assert_true(not game._has_front_interactable(), "Props 位于玩家侧面时不得触发交互")
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
	_assert_true(not Rect2(game.map_badge_panel.position, game.map_badge_panel.size).intersects(Rect2(meter.position, meter.size)), "房间名 HUD 不得与学习进度条重叠")
	var meditation_meter := Control.new()
	game.hud.add_child(meditation_meter)
	game._layout_top_progress_meter(meditation_meter)
	_assert_true(is_equal_approx(meditation_meter.position.y, view_rect.position.y + 16.0 * scale), "冥想进度条顶部 margin 应为 16px")
	_assert_true(is_equal_approx(meditation_meter.position.x + meditation_meter.size.x * 0.5, view_rect.position.x + view_rect.size.x * 0.5), "冥想进度条应相对摄像机视口水平居中")
	_assert_true(not Rect2(game.map_badge_panel.position, game.map_badge_panel.size).intersects(Rect2(meditation_meter.position, meditation_meter.size)), "房间名 HUD 不得与冥想进度条重叠")

	# 练功必须先选左栏分类，再进入右栏选择具体功法。
	game_state.profile.sect = "NG神教"
	game_state.profile.attributes.wisdom = 25
	game_state.profile.vitals.cultivation = 80
	game_state.combat_state.mp = 10
	game_state.combat_state.hp = 100
	skill_system.ensure_skills().levels["basicStrength"] = 80
	skill_system.ensure_skills().levels["ng_code_decorator"] = 40
	skill_system.ensure_skills().levels["ng_tune_rx_step"] = 40
	skill_system.ensure_skills().levels["ng_parry_interceptor"] = 40
	skill_system.ensure_skills().practiceProgress["ng_code_decorator"] = 365
	skill_system.ensure_skills().learnProgress["ng_code_decorator"] = 365
	var ng_definition: Dictionary = data_registry.get_skill("ng_code_decorator")
	_assert_true(skill_system._learn_required(ng_definition, 41, 1.0) == 492 and skill_system.skill_exp_required("ng_code_decorator", 41) == 492, "40→41 级经验应严格采用参考项目 skillExpRequiredOf 曲线，不得使用指数成本")
	_assert_true(skill_system.practice_progress("ng_code_decorator").total == 492 and skill_system.learning_progress("ng_code_decorator").total == 492, "学艺与练功必须共用同一经验需求")
	var practice_hp_before: int = game_state.combat_state.hp
	var practice_mp_before: int = game_state.combat_state.mp
	var aligned_practice_tick: Dictionary = skill_system.practice_tick("ng_code_decorator")
	_assert_true(bool(aligned_practice_tick.get("ok", false)) and int(skill_system.ensure_skills().practiceProgress["ng_code_decorator"]) == 370, "灵感 25 时练功每秒应推进 floor(25/5)=5 点经验")
	_assert_true(game_state.combat_state.mp == practice_mp_before - 2 and game_state.combat_state.hp == practice_hp_before - 4, "练功每 tick 应固定消耗 2 精力，并按经验增量分摊 80% 体力成本")
	game._open_practice()
	_assert_true(game.practice_focus_category and game.practice_categories.size() == 3, "练功打开后应先聚焦编码、思维、招架分类栏")
	_assert_true(game.practice_items == ["ng_code_decorator"], "编码分类右栏应只显示对应的已学门派功法")
	var first_category_x := -INF
	var first_skill_x := -INF
	for first_practice_widget in game.details_widgets:
		if first_practice_widget is Label and str(first_practice_widget.text) == "编码":
			first_category_x = first_practice_widget.position.x
		elif first_practice_widget is Label and str(first_practice_widget.text) == "模版语法":
			first_skill_x = first_practice_widget.position.x
	_assert_true(first_category_x > 0.0 and first_skill_x > game.details_panel.size.x * 0.34, "练功 HUD 首次打开必须按面板实际尺寸完成左右栏布局，不得缩在左上角")
	game._handle_practice_key(KEY_SPACE)
	_assert_true(not game.practice_focus_category and game.practicing_skill_id.is_empty(), "分类栏按空格应只进入功法栏，不得立即开始练功")
	game._handle_practice_key(KEY_SPACE)
	_assert_true(game.practicing_skill_id == "ng_code_decorator" and game.practice_progress_widgets.size() == 1, "功法栏选中具体功法后按空格才应开始修炼")
	game._handle_practice_key(KEY_ESCAPE)
	_assert_true(game.practice_open and not game.practice_focus_category and game.practicing_skill_id.is_empty(), "修炼中按 ESC 应先停止并留在功法栏")
	game._handle_practice_key(KEY_ESCAPE)
	_assert_true(game.practice_open and game.practice_focus_category, "功法栏按 ESC 应先退回分类栏")
	game._handle_practice_key(KEY_DOWN)
	_assert_true(game.practice_category_index == 1 and game.practice_items == ["ng_tune_rx_step"], "切换练功分类时右栏功法必须同步更新")
	game._handle_practice_key(KEY_ESCAPE)
	_assert_true(not game.practice_open and not game.details_panel.visible, "练功分类栏按 ESC 才关闭整个独立 HUD")

	# 练功进度条：开始时显示当前等级内进度，停止后立即清理。
	game.practice_open = true
	game.practice_focus_category = false
	game.practice_items.assign(["ng_code_decorator"])
	game.practice_index = 0
	game.practicing_skill_id = "ng_code_decorator"
	skill_system.ensure_skills().practiceProgress["ng_code_decorator"] = 3
	game._refresh_practice()
	_assert_true(game.practice_progress_widgets.size() == 1, "开始练功后应显示独立进度条")
	var practice_meter = game.practice_progress_widgets[0]
	var expected_practice_progress: Dictionary = skill_system.practice_progress("ng_code_decorator")
	_assert_true(practice_meter.current == int(expected_practice_progress.current) and practice_meter.total == int(expected_practice_progress.total), "练功进度条应显示当前等级内的真实进度")
	_assert_true(not Rect2(game.map_badge_panel.position, game.map_badge_panel.size).intersects(Rect2(practice_meter.position, practice_meter.size)), "房间名 HUD 不得与练功进度条重叠")
	skill_system.ensure_skills().practiceProgress["ng_code_decorator"] = 4
	game._refresh_practice()
	_assert_true(game.practice_progress_widgets[0] == practice_meter and practice_meter.current == 4, "练功 tick 刷新时应复用并更新同一进度条，避免闪烁")
	game.practicing_skill_id = ""
	game._refresh_practice()
	_assert_true(game.practice_progress_widgets.is_empty(), "停止练功后应立即清理进度条")
	# 练功失败应按参考项目文案停止，并在底部对话框明确提示原因。
	skill_system.ensure_skills().levels["basicStrength"] = 10
	skill_system.ensure_skills().levels["ng_code_decorator"] = 1
	game_state.profile.vitals.cultivation = 3
	game._refresh_practice()
	var practice_level_cap_visible := false
	for practice_widget in game.details_widgets:
		if practice_widget is Label and str(practice_widget.text) == "1/6":
			practice_level_cap_visible = true
	_assert_true(skill_system.practice_cap("ng_code_decorator") == 6 and practice_level_cap_visible, "练功 n/m 应显示当前等级与当前最大可练等级")
	game_state.profile.vitals.cultivation = 10
	game_state.combat_state.mp = 0
	game_state.combat_state.hp = 100
	skill_system.ensure_skills().practiceProgress["ng_code_decorator"] = 0
	game.practicing_skill_id = "ng_code_decorator"
	game.practice_tick_accumulator = 0.0
	game._update_continuous_skill_actions(skill_system.PRACTICE_TICK_SECONDS)
	_assert_true(game.practicing_skill_id.is_empty() and game.practice_progress_widgets.is_empty(), "练功失败后应停止并清理进度条")
	_assert_true(game.dialogue_open and game.dialogue_panel.visible and game.dialogue_content.text.contains("精力不足，练不动功。"), "精力不足时应在底部练功对话框显示参考文案")
	game._close_dialogue()
	skill_system.ensure_skills().levels["ng_code_decorator"] = 5
	game_state.profile.vitals.cultivation = 2
	var practice_cap_failure: Dictionary = skill_system.practice_tick("ng_code_decorator")
	_assert_true(str(practice_cap_failure.get("reason", "")) == "cap" and str(practice_cap_failure.get("message", "")).contains("精力修为不足，须多冥想积累内力。"), "练功达到精力上限时应使用参考项目的原因文案")
	game.practice_open = true
	game.menu_open = false
	game.menu_panel.visible = false
	game.practicing_skill_id = "ng_code_decorator"
	game._refresh_practice()
	game._handle_practice_key(KEY_ESCAPE)
	_assert_true(game.practice_open and game.practicing_skill_id.is_empty() and game.details_panel.visible, "练功中第一次 ESC 应只停止练功并保留面板")
	_assert_true(not game.menu_open and not game.menu_panel.visible, "停止练功时不得弹出顶部菜单")
	game._handle_practice_key(KEY_ESCAPE)
	_assert_true(game.practice_open and game.practice_focus_category and game.details_panel.visible, "停止状态再次按 ESC 应从功法栏退回分类栏")
	game._handle_practice_key(KEY_ESCAPE)
	_assert_true(not game.practice_open and not game.details_panel.visible, "回到分类栏后再次按 ESC 应真正关闭练功面板")
	_assert_true(not game.menu_open and not game.menu_panel.visible, "关闭练功面板后不得打开顶部菜单")

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
	game._update_continuous_skill_actions(skill_system.LEARNING_TICK_SECONDS)
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
	game._update_continuous_skill_actions(skill_system.LEARNING_TICK_SECONDS)
	_assert_true(skill_system.level(selected_skill) == selected_level + 1, "最后 1 点潜能应在同一 tick 完成升级")
	_assert_true(int(game_state.profile.vitals.potential) == 0, "每个有效学习 tick 应只消耗 1 点潜能")
	_assert_true(int(game_state.profile.vitals.money) == money_before - ceili(float(selected_required) * 0.8), "升级 Token 学费应为本级经验需求的 80% 向上取整")
	_assert_true(str(game.learning_skill_id).is_empty() and game.learning_progress_widgets.is_empty(), "学习完成后进度条应立即消失")
	game.npc_menu_open = false
	game.npc_menu_panel.visible = false
	game.learn_focus_category = false
	game._handle_learn_key(KEY_ESCAPE)
	_assert_true(game.learn_open and game.learn_focus_category and game.details_panel.visible and not game.npc_menu_panel.visible, "学习功法栏按 ESC 应只退回分类，不得叠加 NPC 菜单")
	game._handle_learn_key(KEY_ESCAPE)
	_assert_true(not game.learn_open and not game.details_panel.visible and not game.npc_menu_open and not game.npc_menu_panel.visible, "学习分类层按 ESC 应关闭独立 HUD 并直接回到地图")

	# 顶栏与两个二级菜单必须由独立 HUD 面板承载，切换时互斥显示。
	game.menu_open = true
	game.menu_panel.visible = true
	game.menu_index = 2
	game.skill_open = true
	game.system_open = false
	game._refresh_menu()
	_assert_true(game.menu_panel.visible and game.skill_menu_panel.visible and not game.system_menu_panel.visible, "技能二级菜单应保留一级菜单，并只显示独立的 SkillMenu 面板")
	_assert_true(game.skill_menu_items.get_child_count() == game.SKILL_ITEMS.size(), "技能二级菜单条目应挂在自己的 HUD 面板中")
	# 加力在技能菜单内进入独立调整态，上下调档、空格确认；上限取基础架构+高级架构×2。
	game_state.profile.sect = "NG神教"
	skill_system.ensure_skills().levels["basicConstitution"] = 40
	skill_system.ensure_skills().levels["ng_arch_zone"] = 40
	skill_system.ensure_skills().equipped_basic["arch"] = "basicConstitution"
	skill_system.ensure_skills().equipped_special["arch"] = "ng_arch_zone"
	skill_system.ensure_skills().forcePower = 0
	game.skill_index = 2
	game._select_skill_menu()
	_assert_true(game.force_power_open and game.force_power_limit == 120 and game.dialogue_content.text.contains("加力 0 / 120"), "选择加力后应按图示进入菜单内调整态，并显示当前值与内功上限")
	game._handle_menu_key(KEY_UP)
	_assert_true(game.force_power_value == 1 and game.dialogue_content.text.contains("命中耗 1 精力"), "加力调整态按上应增加一档并实时刷新说明")
	game._handle_menu_key(KEY_SPACE)
	_assert_true(not game.force_power_open and skill_system.force_power() == 1 and game.skill_open and game.skill_menu_panel.visible, "加力按空格应提交选定值并返回技能二级菜单")
	# 精力不足时不得按剩余精力部分加力；足额时整档扣除并附加 0~2 倍伤害。
	skill_system.set_force_power(10)
	game_state.combat_state.mp = 5
	var no_force_result := {"damage": 100}
	_assert_true(combat_system._apply_player_force_power(no_force_result) == 0 and game_state.combat_state.mp == 5 and no_force_result.damage == 100, "精力不足完整档位时加力必须完全不生效")
	game_state.combat_state.mp = 10
	seed(13)
	var force_result := {"damage": 100}
	var force_extra: int = combat_system._apply_player_force_power(force_result)
	_assert_true(game_state.combat_state.mp == 0 and force_extra >= 0 and force_extra <= 20 and force_result.damage == 100 + force_extra, "足额加力应整档扣精力并按图示 0~2 倍公式追加伤害")
	game.menu_index = 3
	game.skill_open = false
	game.system_open = true
	game._refresh_menu()
	_assert_true(game.menu_panel.visible and game.system_menu_panel.visible and not game.skill_menu_panel.visible, "系统二级菜单应保留一级菜单，并只显示独立的 SystemMenu 面板")
	_assert_true(game.system_menu_items.get_child_count() == game.SYSTEM_ITEMS.size(), "系统二级菜单条目应挂在自己的 HUD 面板中")
	game.system_index = 3
	game._select_system_menu()
	_assert_true(game.menu_open and game.menu_panel.visible and game.system_menu_panel.visible, "保存等无弹窗的二级操作不得收起父子菜单")
	# 赛博传送使用自己的下拉 HUD：保留一级菜单、替换系统操作列表，ESC 回系统菜单。
	game_state.profile.sect = "NG神教"
	skill_system.ensure_skills().levels["basicAgility"] = 40
	skill_system.ensure_skills().levels["ng_tune_rx_step"] = 40
	skill_system.ensure_skills().equipped_basic["tune"] = "basicAgility"
	skill_system.ensure_skills().equipped_special["tune"] = "ng_tune_rx_step"
	# 基础架构 40 + NG 架构 40×2，根骨 25 时理论修为终点为 3000，
	# 对应最大当前精力 6000；即使当前修为很低，传送仍须支付 6000 的 1/5 = 1200。
	skill_system.ensure_skills().levels["basicConstitution"] = 40
	skill_system.ensure_skills().levels["ng_arch_zone"] = 40
	skill_system.ensure_skills().equipped_basic["arch"] = "basicConstitution"
	skill_system.ensure_skills().equipped_special["arch"] = "ng_arch_zone"
	game_state.profile.attributes.constitution = 25
	game_state.profile.vitals.cultivation = 30
	game_state.combat_state.mp = 30
	game.system_index = 0
	game._select_system_menu()
	_assert_true(skill_system.meditation_cap() == 3000 and skill_system.meditation_max_mp_cap() == 6000 and game._cyber_teleport_cost() == 1200, "理论修为终点与对应最大当前精力应保持 1:2，传送取后者的 1/5")
	# 3000 必须是公式结果而非特判：综合内功 40+40×2=120，每级贡献25，
	# 初始根骨25修正为1.0，因此 floor(120×25×1.0)=3000。
	_assert_true(is_equal_approx(game_state.meditation_modifier(25), 1.0), "初始根骨25的冥想修正应处于中性值1.0")
	_assert_true(skill_system.MEDITATION_INNER_POWER_UNIT == 25.0, "每级综合内功应按公式贡献25点冥想修为上限")
	_assert_true(skill_system.meditation_cap_from_values(25, 40, 40) == int(floor(float(40 + 40 * 2) * 25.0 * game_state.meditation_modifier(25))), "40级基础+40级高级、根骨25的冥想上限必须由通用公式推得")
	_assert_true(skill_system.meditation_cap_from_values(25, 39, 40) == 2975 and skill_system.meditation_cap_from_values(25, 40, 39) == 2950, "基础或高级内功等级变化时上限必须随公式变化，不得写死3000")
	_assert_true(skill_system.meditation_cap_from_values(30, 40, 40) == 3300, "根骨变化时冥想上限必须应用根骨修正动态变化")
	# 验证真实 tick 的终点行为：最后一层可以从2999升至3000，不越界；达到
	# 修为上限后仍可把“当前精力”充满至修为的2倍6000，之后才彻底停止。
	game_state.profile.vitals.cultivation = 2999
	game_state.combat_state.mp = game_state.player_mp_max() - 1
	var final_layer_result: Dictionary = skill_system.meditate_tick()
	_assert_true(bool(final_layer_result.get("ok", false)) and game_state.profile.vitals.cultivation == 3000 and game_state.combat_state.mp == 0, "真实冥想 tick 应能从2999升至公式上限3000并清空当前精力")
	game_state.combat_state.mp = game_state.player_mp_max() - 1
	var fill_final_mp_result: Dictionary = skill_system.meditate_tick()
	_assert_true(not bool(fill_final_mp_result.get("ok", true)) and game_state.profile.vitals.cultivation == 3000 and game_state.combat_state.mp == 6000, "修为到3000后应继续允许当前精力充至6000，并在充满时停止")
	var capped_cultivation_before := int(game_state.profile.vitals.cultivation)
	var capped_mp_before := int(game_state.combat_state.mp)
	var capped_result: Dictionary = skill_system.meditate_tick()
	_assert_true(not bool(capped_result.get("ok", true)) and game_state.profile.vitals.cultivation == capped_cultivation_before and game_state.combat_state.mp == capped_mp_before, "冥想到顶后继续 tick 不得突破公式上限或6000当前精力")
	game_state.profile.vitals.cultivation = 30
	game_state.combat_state.mp = 30
	_assert_true(game_state.player_mp_max() == 60 and not game.cyber_open and game.dialogue_open and game.dialogue_content.text.contains("需要 1200 精力"), "当前已冥想精力上限较低时也不得降低传送要求")
	game._close_dialogue()
	game_state.profile.vitals.cultivation = 600
	game_state.combat_state.mp = 1200
	game.menu_open = true
	game.menu_panel.visible = true
	game.menu_index = 3
	game.system_open = true
	game.system_index = 0
	game._refresh_menu()
	game._select_system_menu()
	_assert_true(game.cyber_open and game.active_detail_hud == "cyber" and game.details_panel == game.detail_huds.cyber.panel, "赛博传送应打开独立 CyberHUD")
	_assert_true(game.menu_open and game.menu_panel.visible and not game.system_menu_panel.visible, "传送目的地 HUD 应保留一级菜单并替换系统二级菜单")
	_assert_true(game.details_panel.size.x < 300.0 and is_equal_approx(game.details_panel.position.y, game.menu_panel.position.y + game.menu_panel.size.y), "CyberHUD 应作为系统菜单下方的窄下拉列表，不得使用全屏详情面板")
	var cyber_labels_before: Array = game.cyber_labels.duplicate()
	var cyber_selection_before = game.cyber_selection_widget
	game._handle_cyber_key(KEY_DOWN)
	_assert_true(game.cyber_selection_widget == cyber_selection_before and game.cyber_labels == cyber_labels_before, "传送光标移动应复用标签和选中框，不得销毁重建整套 HUD")
	_assert_true(is_equal_approx(game.cyber_selection_widget.position.y, 24.0 * game._display_scale()), "传送光标移动只应更新同一选中框的位置")
	game._handle_cyber_key(KEY_ESCAPE)
	_assert_true(not game.cyber_open and not game.details_panel.visible and game.system_open and game.system_menu_panel.visible, "传送 HUD 按 ESC 应退回系统二级菜单")
	game._close_menu()
	_assert_true(not game.skill_menu_panel.visible and not game.system_menu_panel.visible, "关闭菜单时应分别隐藏两个二级 HUD 面板")

	# “退出”只返回 Splash，不得隐式保存、删除或重建存档。
	game_state.profile.vitals.potential = 2468
	game_state.save_game()
	var save_before_exit := FileAccess.get_file_as_string(game_state.SAVE_PATH)
	game_state.profile.vitals.potential = 1357
	game.system_index = 4
	game._select_system_menu()
	await process_frame
	await process_frame
	_assert_true(current_scene != null and current_scene.scene_file_path == "res://scenes/splash.tscn", "系统菜单退出应返回 Splash 页面")
	_assert_true(FileAccess.get_file_as_string(game_state.SAVE_PATH) == save_before_exit, "退出不得写入或删除存档文件")
	_assert_true(int(game_state.profile.vitals.potential) == 1357, "退出不得重新加载或重建内存中的存档状态")
	game.queue_free()

	game_state.delete_save()
	if failures.is_empty():
		print("alignment_test: PASS")
		quit(0)
	else:
		print("alignment_test: FAIL (%d)" % failures.size())
		quit(1)
