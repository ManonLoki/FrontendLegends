extends SceneTree
## 数据、任务、技能与物品规则回归。

var failures: Array[String] = []

# 断言验证true相关逻辑，并保持调用方状态一致。
func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

# 执行domain、suite相关逻辑，并保持调用方状态一致。
func _run_domain_suite() -> void:
	var game_state = root.get_node("GameState")
	var skill_system = root.get_node("SkillSystem")
	var quest_system = root.get_node("QuestSystem")
	var inventory_system = root.get_node("InventorySystem")
	var data_registry = root.get_node("DataRegistry")
	var combat_system = root.get_node("CombatSystem")
	var npc_system = root.get_node("NpcSystem")
	game_state.use_test_save_path("alignment")
	npc_system.register_runtime("__dialogue_target", {"displayName": "动态目标", "defaultLine": "你……找我有事？"})
	_assert_true(npc_system.dialogue("__dialogue_target") == "你……找我有事？", "动态 NPC 应读取运行时 defaultLine")
	npc_system.unregister_runtime("__dialogue_target")
	npc_system.mark_defeated("jiu_ri")
	_assert_true(npc_system.is_defeated("jiu_ri"), "击杀隐藏记录应能登记")
	npc_system.clear_defeated()
	_assert_true(not npc_system.is_defeated("jiu_ri"), "重新进入 Game 时应清空 NPC 击杀隐藏记录")
	game_state.delete_save()
	game_state.create_profile("alignment-test", {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25})
	_assert_true(skill_system.ensure_skills().levels.is_empty(), "新角色不应自带任何基础技能")
	_assert_true(skill_system.ensure_skills().equipped_basic.is_empty() and skill_system.ensure_skills().equipped_special.is_empty(), "新角色不应预装备任何功法")
	_assert_true(int(game_state.profile.vitals.money) == 50 and int(game_state.profile.vitals.potential) == 0, "新角色应有 50 Token，潜能从 0 开始")
	game_state.save_game()
	var saved_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game_state.current_save_path()))
	_assert_true(not saved_document.get("profile", {}).has("attributes") and saved_document.get("profile", {}).has("base_attributes"), "存档只应持久化基础四维，派生 attributes 必须在读档时重算")
	# 主存档损坏时必须从上一次完整备份恢复，且测试路径不得指向正式存档。
	_assert_true(game_state.current_save_path().begins_with("user://test_saves/"), "回归测试必须使用隔离存档路径，不得读写正式 user:// 存档")
	_assert_true(not game_state._read_save_document(game_state.current_save_path() + ".bak").is_empty(), "第二次安全保存后应保留上一份完整 .bak 存档")
	var corrupt_file := FileAccess.open(game_state.current_save_path(), FileAccess.WRITE)
	corrupt_file.store_string("{损坏的存档")
	corrupt_file = null
	var recovered_from_backup: bool = game_state.load_game()
	_assert_true(recovered_from_backup, "主存档损坏后应自动从 .bak 读取最近一次完整存档")
	var expected_recovered_name := str(saved_document.get("profile", {}).get("name", "")).substr(0, 10)
	_assert_true(str(game_state.profile.get("name", "")) == expected_recovered_name, "备份恢复后应按正常读档规则保留原角色资料")
	var restored_document = JSON.parse_string(FileAccess.get_file_as_string(game_state.current_save_path()))
	_assert_true(restored_document is Dictionary and str(restored_document.get("profile", {}).get("name", "")) == "alignment-test", "备份恢复后主存档文件本身也应重新变为有效 JSON")
	var rating_rules = load("res://scripts/skills/skill_rating.gd")
	_assert_true(rating_rules.title(1) == "不堪一击" and rating_rules.title(60) == "略有小成" and rating_rules.title(300) == "返璞归真", "武学称号应使用参照项目的完整分段表")
	var rating_levels := {"basicStrength": 60, "literacy": 100}
	_assert_true(rating_rules.title(rating_rules.equipped_average(rating_levels, ["basicStrength", "literacy"])) == "略有小成", "武学称号平均值应只统计已装备武学并排除灵感")
	game_state.profile.skills.levels = {"basicStrength": 20, "basicParry": 30}
	skill_system.refresh_derived_attributes()
	_assert_true(int(game_state.profile.attributes.strength) == 30, "基础编码与基础招架对编码的反哺应累加（25+2+3）")
	game_state.profile.skills.levels = {}
	skill_system.refresh_derived_attributes()
	# 读档归一化：裁剪姓名、钳制资源、清理未知物品并迁移旧档师父。
	var legacy_profile: Dictionary = game_state.profile.duplicate(true)
	legacy_profile.name = "12345678901"
	legacy_profile.sect = "NG神教"
	legacy_profile.master = ""
	legacy_profile.erase("base_attributes")
	var legacy_skills: Dictionary = legacy_profile.skills
	legacy_skills["levels"] = {"basicAgility": 20}
	legacy_skills["learnProgress"] = {"basicAgility": 12}
	legacy_skills["practiceProgress"] = {"basicAgility": 34}
	legacy_skills["forcePower"] = 7
	legacy_skills.erase("learn_progress")
	legacy_skills.erase("practice_progress")
	legacy_skills.erase("force_power")
	legacy_profile["skills"] = legacy_skills
	var legacy_attributes: Dictionary = legacy_profile.attributes
	legacy_attributes["agility"] = 27
	legacy_profile["attributes"] = legacy_attributes
	var legacy_vitals: Dictionary = legacy_profile.vitals
	legacy_vitals["food"] = 99999
	legacy_vitals["money"] = -7
	legacy_vitals["potential"] = -3
	legacy_profile["vitals"] = legacy_vitals
	var legacy_file := FileAccess.open(game_state.current_save_path(), FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({"version": 2, "profile": legacy_profile, "game_time_sec": 0, "combat_state": {"hp": 1, "mp": 0, "injury": 0}, "inventory": {"fagun": 2, "removed_item": 9}, "item_cooldowns": {"fagun": 12.0, "removed_item": 99.0}}))
	legacy_file = null
	_assert_true(game_state.load_game(), "归一化测试存档应可读取")
	_assert_true(str(game_state.profile.name) == "1234567890" and int(game_state.profile.vitals.food) == 450, "读档应裁剪姓名并按派生编码钳制食物上限（实际 %s / %d）" % [game_state.profile.name, game_state.profile.vitals.food])
	_assert_true(int(game_state.profile.vitals.money) == 0 and int(game_state.profile.vitals.potential) == 0, "读档应将资源钳为非负整数")
	_assert_true(str(game_state.profile.master) == "da_mo_qiong_qiu", "旧档缺师父时应迁移到本门入门师父")
	_assert_true(int(game_state.profile.base_attributes.agility) == 25 and int(game_state.profile.attributes.agility) == 27, "旧档缺基础四维时应扣除技能反哺后重建并重算派生值（实际 %d / %d）" % [game_state.profile.base_attributes.agility, game_state.profile.attributes.agility])
	_assert_true(int(game_state.profile.skills.learn_progress.basicAgility) == 12 and int(game_state.profile.skills.practice_progress.basicAgility) == 34 and int(game_state.profile.skills.force_power) == 7, "第二版技能存档的驼峰字段应迁移为蛇形字段")
	_assert_true(not game_state.profile.skills.has("learnProgress") and not game_state.profile.skills.has("practiceProgress") and not game_state.profile.skills.has("forcePower"), "迁移后应删除旧技能字段，避免双数据源")
	_assert_true(game_state.inventory == {"fagun": 2} and game_state.item_cooldowns == {"fagun": 12.0}, "读档应清除未知物品和冷却记录")
	game_state.create_profile("alignment-test", {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25})
	game_state.profile.vitals.potential = 100000
	game_state.profile.vitals.money = 100000
	var bought: Dictionary = inventory_system.buy_item("nai_cha_mei_mei", "linxing_kafei")
	_assert_true(str(bought.get("message", "")) == "买下临幸咖啡，花费 99 Token。", "购买成功文案应与参照项目一致")
	var sold: Dictionary = inventory_system.sell_item("linxing_kafei")
	_assert_true(str(sold.get("message", "")) == "卖出临幸咖啡，得 24 Token。", "出售成功文案应与参照项目一致")
	inventory_system.add_item("linxing_kafei")
	var discarded: Dictionary = inventory_system.discard_item("linxing_kafei")
	_assert_true(str(discarded.get("message", "")) == "丢弃了临幸咖啡。", "丢弃成功文案应与参照项目一致")
	# 师父高低严格取教学表显式 maxTeachLevel；鱿鱼须的字符串旧格式上限为 0。
	game_state.profile.sect = "鱿鱼山庄"
	game_state.profile.master = "wei_te_er"
	_assert_true(not skill_system.can_join("youyu_xu") and str(skill_system.join_npc("youyu_xu").message).contains("造诣不及"), "不得用拜师门槛推断师父造诣；鱿鱼须教学上限 0 不高于维特 60")
	# 技能书须使用道具自身 maxLearnLevel，而非只看技能总上限。
	data_registry.items["__alignment_book"] = {"name": "测试秘籍", "kind": "book", "skillId": "basicStrength", "maxLearnLevel": 1, "stackLimit": 2}
	inventory_system.add_item("__alignment_book", 2)
	var first_book: Dictionary = inventory_system.use_item("__alignment_book")
	var capped_book: Dictionary = inventory_system.use_item("__alignment_book")
	_assert_true(bool(first_book.get("ok", false)) and skill_system.level("basicStrength") == 1 and not bool(capped_book.get("ok", true)) and str(capped_book.get("message", "")).contains("读到 1 级"), "技能书应在道具 maxLearnLevel 处停止并退还未生效的书")
	game_state.inventory.erase("__alignment_book")
	data_registry.items.erase("__alignment_book")
	# 异门功法即使存在于旧档技能状态中也不得装备；本门成功文案同时对齐标点。
	skill_system.ensure_skills().levels["ng_code_decorator"] = 1
	game_state.profile.sect = "香草派"
	_assert_true(skill_system.equip("ng_code_decorator").message == "非本门功法，不能装备。", "异门功法必须拒绝装备")
	game_state.profile.sect = "NG神教"
	_assert_true(skill_system.equip("ng_code_decorator").message == "已装备【模版语法】。", "本门功法装备成功文案应与参照项目一致")
	game_state.profile.sect = ""
	game_state.profile.master = ""
	_assert_true(int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 640 and int(ProjectSettings.get_setting("display/window/size/viewport_height")) == 480, "设计分辨率应为 640×480")
	_assert_true(str(ProjectSettings.get_setting("display/window/stretch/aspect")) == "expand", "横屏窗口应保持设计高度并扩展横向设计区域")

	# 全地图 NPC 目标注册：读取 TMX property npcId，并保留地图显示名。
	var placed_targets: Array[Dictionary] = data_registry.list_placed_npc_targets()
	_assert_true(not placed_targets.is_empty(), "全地图 NPC 任务目标池不应为空")
	var found_training_tutor := false
	for placed_target in placed_targets:
		_assert_true(not data_registry.get_npc(str(placed_target.get("npc_id", ""))).is_empty(), "任务目标池不应包含未注册 NPC")
		if str(placed_target.get("npc_id", "")) == "dao_shi" and str(placed_target.get("map_id", "")) == "DarkXue":
			found_training_tutor = str(placed_target.get("map_name", "")) == "DARK学"
	_assert_true(found_training_tutor, "应从 DarkXue.tmx 收集导师及 DARK学地图名")
	for excluded_target in data_registry.list_placed_npc_targets(["jiu_ri"]):
		_assert_true(str(excluded_target.get("npc_id", "")) != "jiu_ri", "任务发布者应能从目标池排除")
	quest_system.reset_runtime()
	seed(1)
	var generated_ring: Dictionary = quest_system.offer_generator("ring_cunzhang")
	_assert_true(bool(generated_ring.get("ok", false)), "九日环应能从真实地图生成 NPC 目标")
	_assert_true(not str(generated_ring.get("message", "")).contains("【】"), "九日环文案不应缺失地图或 NPC")
	var generated_target: Dictionary = quest_system.active.get("generator:ring_cunzhang", {}).get("target", {})
	_assert_true(not str(generated_target.get("target_id", "")).is_empty() and not str(generated_target.get("map_name", "")).is_empty(), "九日环运行时应保存 NPC 与地图显示名")
	_assert_true(quest_system._scaled_reward({"ringGrowth": 0.5, "fluctuation": 0.0}, {"experience": 1}, 2).experience == 1, "九日环增长后的小数奖励应向下取整而非四舍五入")

	# 小不二动态悬赏：严格使用四段姓名、父地图播报、五项基础技能和安全落点。
	quest_system.reset_runtime()
	var bounty_definition: Dictionary = data_registry.quest_generators.bountyring_xiaobuer.duplicate(true)
	bounty_definition.spawnMaps = ["DarkXue"]
	data_registry.quest_generators.bountyring_xiaobuer = bounty_definition
	seed(7)
	var bounty_offer: Dictionary = quest_system.offer_bounty()
	_assert_true(bool(bounty_offer.get("ok", false)), "小不二悬赏应能生成动态目标")
	var bounty: Dictionary = quest_system.get_bounty_target()
	_assert_true(quest_system.bounty_board_text() == str(bounty_offer.get("message", "")), "暗网悬赏榜应复用参照项目的接取文案，而非进行中文案")
	var bounty_name_pattern := RegEx.new()
	bounty_name_pattern.compile("^(傻X|脑残|白痴|霸道|凶狠)(老板|客户|领导|同事|朋友)(赵|钱|孙|李|周|吴|郑|王)(一|二|三|四|五|六|七|八|九|十)$")
	_assert_true(bounty_name_pattern.search(str(bounty.get("target_name", ""))) != null, "悬赏目标姓名应按原项目四段词库生成")
	_assert_true(str(bounty.get("map_name", "")) == "开源镇", "室内悬赏地点应播报父级大地图名称")
	var runtime_bounty: Dictionary = root.get_node("NpcSystem").build_instance(str(bounty.get("target_id", "")))
	_assert_true(runtime_bounty.get("skillLevels", {}).keys().size() == 5 and runtime_bounty.get("equippedSkillIds", []).size() == 5, "悬赏目标应缩放并装备五项基础技能")
	var dark_study_map := TiledMapLoader.new()
	_assert_true(dark_study_map.load_file("res://assets/Map/maps/LoreWorld/KaiyuanTown/DarkXue.tmx"), "应能加载 DARK学室内地图")
	_assert_true(data_registry.map_type("DarkXue") == "inDoor" and data_registry.map_type("KaiyuanTown") == "outDoor", "地图注册阶段应缓存室内/室外类型，传送菜单不得临时重读 TMX")
	_assert_true(not dark_study_map.npc_object_at_tile(7, 6).is_empty(), "NPC point 对象应命中脚下单格")
	_assert_true(dark_study_map.npc_object_at_tile(8, 6).is_empty(), "NPC point 对象不得扩张命中相邻格")
	var bounty_tile: Vector2i = dark_study_map.pick_dynamic_npc_tile()
	_assert_true(bounty_tile.x >= 0 and dark_study_map.is_walkable(bounty_tile.x, bounty_tile.y) and dark_study_map.is_walkable(bounty_tile.x, bounty_tile.y - 1), "室内悬赏 NPC 应落在身前无墙的可行走格")
	_assert_true(dark_study_map.npc_object_at_tile(bounty_tile.x, bounty_tile.y).is_empty(), "动态悬赏 NPC 不应与固定 NPC 重叠")
	var fixed_reward_definition := bounty_definition.duplicate(true)
	fixed_reward_definition.fluctuationMin = 0.0
	fixed_reward_definition.fluctuationMax = 0.0
	var settled_bounty: Dictionary = quest_system._settle_bounty_ring("generator:bountyring_xiaobuer", quest_system.active["generator:bountyring_xiaobuer"], fixed_reward_definition)
	_assert_true(settled_bounty.reward == {"experience": 90, "potential": 90, "money": 72}, "小不二悬赏基础奖励应按经验×3、潜能×3、Token×2.4 计算")
	quest_system.reset_runtime()

	# 生死簿目标池包含发布者本人；参照项目允许抽到活阎王。
	var original_targets: Array[Dictionary] = data_registry.placed_npc_targets.duplicate(true)
	data_registry.placed_npc_targets.assign([{"npc_id": "huo_yan_wang", "map_id": "test", "map_name": "测试地图"}])
	var self_kill_offer: Dictionary = quest_system.offer_generator("killring_huoyanwang")
	_assert_true(bool(self_kill_offer.get("ok", false)) and str(quest_system.active.get("generator:killring_huoyanwang", {}).get("target", {}).get("target_id", "")) == "huo_yan_wang", "生死簿目标池不得排除发布者活阎王")
	data_registry.placed_npc_targets.assign(original_targets)
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
	_assert_true(game_state.player_mp_max() == 130 and game_state.player_hp_max() == 267, "内功修为 130 的当前精力上限应为 130，并按该上限反哺体力至 267")
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
	_assert_true(str(practice_result.get("message", "")).begins_with("你苦练【模版语法】") and str(practice_result.get("message", "")).contains("，进度 "), "练功普通推进文案应与参照项目一致")
	_assert_true(is_equal_approx(game_state.game_time_sec - before_time, 1.0 / 5.0), "练功 tick 应推进 1/5 秒")

	# 冥想：装备基础/高级架构后，有效 tick 推进 1/30 秒。
	skills.levels.basicConstitution = 2
	skills.levels.ng_arch_zone = 1
	skills.equipped_special.arch = "ng_arch_zone"
	_assert_true(not skill_system.can_meditate(), "只学会但未装备基础架构时不得冥想")
	skills.equipped_basic.arch = "basicConstitution"
	game_state.profile.vitals.cultivation = 1
	game_state.combat_state.mp = 0
	before_time = game_state.game_time_sec
	var meditation_result: Dictionary = skill_system.meditate_tick()
	_assert_true(bool(meditation_result.get("ok", false)), "冥想 tick 应成功")
	_assert_true(is_equal_approx(game_state.game_time_sec - before_time, 1.0 / 30.0), "冥想 tick 未推进 1/30 秒")

	# 装备四维只进入战斗快照，并同时作用于玩家与 NPC。
	data_registry.items["__alignment_attr_equip"] = {"name": "属性测试装备", "kind": "equip", "slot": "weapon", "attributes": {"strength": 3, "constitution": 5}}
	game_state.inventory["__alignment_attr_equip"] = 1
	game_state.equipment.weapon = "__alignment_attr_equip"
	var player_combat_attrs: Dictionary = combat_system.rules.player_combat_attributes()
	var npc_combat_attrs: Dictionary = combat_system.rules.npc_combat_attributes({"attributes": {"strength": 10, "agility": 10, "constitution": 10, "wisdom": 10}, "equipment": ["__alignment_attr_equip"]})
	_assert_true(int(player_combat_attrs.strength) == int(game_state.profile.attributes.strength) + 3 and int(player_combat_attrs.constitution) == int(game_state.profile.attributes.constitution) + 5 and int(game_state.profile.attributes.constitution) == 25, "玩家装备四维应进入战斗快照但不得改写永久四维")
	_assert_true(int(npc_combat_attrs.strength) == 13 and int(npc_combat_attrs.constitution) == 15, "NPC 随身装备四维应进入战斗快照")
	game_state.equipment.weapon = ""
	game_state.inventory.erase("__alignment_attr_equip")
	data_registry.items.erase("__alignment_attr_equip")
	# 背包条目按 id 稳定排序，与获得先后无关。
	data_registry.items["__sort_z"] = {"name": "Z", "kind": "material"}
	data_registry.items["__sort_a"] = {"name": "A", "kind": "material"}
	game_state.inventory["__sort_z"] = 1
	game_state.inventory["__sort_a"] = 1
	var sorted_ids: Array = inventory_system.list_entries().map(func(entry): return entry.id)
	_assert_true(sorted_ids.find("__sort_a") < sorted_ids.find("__sort_z"), "背包与出售条目应按道具 id 稳定排序")
	game_state.inventory.erase("__sort_z")
	game_state.inventory.erase("__sort_a")
	data_registry.items.erase("__sort_z")
	data_registry.items.erase("__sort_a")

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
