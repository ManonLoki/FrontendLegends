extends SceneTree
## 数据、任务、技能与物品规则回归。
const LEARNING_SUITE := preload("res://tests/alignment/learning_suite.gd")
var failures: Array[String] = []
const NOVICE_PROJECT_ID := "b7ce37d7-b841-5a71-ac4b-24c8a491967b"
const DELIVERY_RING_ID := "55578b74-31b5-5ef9-87d1-350ffb56e109"
const BOUNTY_RING_ID := "c7666a34-f17b-5427-875a-74f227071fa2"
const KILL_RING_ID := "2bbbd0f5-280f-5141-a4ad-79fcb3478579"
const BASIC_STRENGTH_SKILL_ID := "2224675d-63f2-50e8-a2c6-064acd5c5623"
const BASIC_CONSTITUTION_SKILL_ID := "dcebef7e-09b8-5a69-8e3d-159cb2b0c355"
const SECT_CODE_SKILL_ID := "bcb538e2-4d6a-52ae-990d-20377e27ab64"
const SECT_CONSTITUTION_SKILL_ID := "9287473e-59a9-5dc8-a914-324ec57ffc14"
func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run_domain_suite() -> void:
	var game_state = root.get_node("GameState")
	var skill_system = root.get_node("SkillSystem")
	var quest_system = root.get_node("QuestSystem")
	var inventory_system = root.get_node("InventorySystem")
	var data_registry = root.get_node("DataRegistry")
	var combat_system = root.get_node("CombatSystem")
	var npc_system = root.get_node("NpcSystem")
	var system_settings = root.get_node("SystemSettings")
	_assert_true(data_registry.get_index() < skill_system.get_index() and skill_system.get_index() < game_state.get_index(), "DataRegistry 与 SkillSystem 必须先于 GameState 就绪，冷启动读档才能计算完整资源上限")
	game_state.use_test_save_path("alignment")
	system_settings.use_test_settings_path("alignment")
	system_settings.delete_settings()
	npc_system.register_runtime("__dialogue_target", {"displayName": "动态目标", "defaultLine": "你……找我有事？"})
	_assert_true(npc_system.dialogue("__dialogue_target") == "你……找我有事？", "动态 NPC 应读取运行时 defaultLine")
	npc_system.unregister_runtime("__dialogue_target")
	npc_system.mark_defeated("ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1")
	_assert_true(npc_system.is_defeated("ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1"), "击杀隐藏记录应能登记")
	npc_system.clear_defeated()
	_assert_true(not npc_system.is_defeated("ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1"), "重新进入 Game 时应清空 NPC 击杀隐藏记录")
	game_state.delete_save()
	game_state.create_profile("alignment-test", {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25})
	_assert_true(skill_system.ensure_skills().levels.is_empty(), "新角色不应自带任何基础技能")
	_assert_true(skill_system.ensure_skills().equipped_basic.is_empty() and skill_system.ensure_skills().equipped_special.is_empty(), "新角色不应预装备任何功法")
	_assert_true(int(game_state.profile.vitals.money) == 50 and int(game_state.profile.vitals.potential) == 0, "新角色应有 50 Token，潜能从 0 开始")
	game_state.save_game()
	var saved_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game_state.current_save_path()))
	_assert_true(not saved_document.get("profile", {}).has("attributes") and saved_document.get("profile", {}).has("base_attributes"), "存档只应持久化基础四维，派生 attributes 必须在读档时重算")
	# 主存档损坏时必须从上一次完整备份恢复，且测试路径不得指向正式存档。
	_assert_true(game_state.current_save_path().begins_with(OS.get_temp_dir()), "回归测试必须使用系统临时目录，不得读写正式 user:// 存档")
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
	_assert_true(rating_rules.title(1) == "不堪一击" and rating_rules.title(60) == "略有小成" and rating_rules.title(300) == "返璞归真", "武学称号应保留完整分段表")
	var rating_levels := {"2224675d-63f2-50e8-a2c6-064acd5c5623": 60, "1011d493-be02-53e2-86a2-a6a439328f84": 100}
	_assert_true(rating_rules.title(rating_rules.equipped_average(rating_levels, ["2224675d-63f2-50e8-a2c6-064acd5c5623", "1011d493-be02-53e2-86a2-a6a439328f84"])) == "略有小成", "武学称号平均值应只统计已装备武学并排除灵感")
	game_state.profile.skills.levels = {"2224675d-63f2-50e8-a2c6-064acd5c5623": 20, "74903f7d-7f7f-52c2-a6da-b3f4b12b97f2": 30}
	skill_system.refresh_derived_attributes()
	_assert_true(int(game_state.profile.attributes.strength) == 27, "基础编码应独立反哺编码（25+2），基础招架不得重复叠加臂力")
	game_state.profile.skills.levels = {}
	skill_system.refresh_derived_attributes()
	# 当前版本读档仍执行边界归一化；更早版本则必须直接拒绝，且不运行任何迁移。
	var normalized_profile: Dictionary = game_state.profile.duplicate(true)
	normalized_profile.name = "12345678901"
	var normalized_vitals: Dictionary = normalized_profile.vitals
	normalized_vitals["food"] = 99999
	normalized_vitals["money"] = -7
	normalized_vitals["potential"] = -3
	normalized_profile["vitals"] = normalized_vitals
	var normalized_file := FileAccess.open(game_state.current_save_path(), FileAccess.WRITE)
	normalized_file.store_string(JSON.stringify({"version": 5, "profile": normalized_profile, "game_time_sec": 0, "combat_state": {"hp": 1, "mp": 0, "injury": 0}, "inventory": {"1bb38a9b-68ca-55e1-88ff-933102dbcb64": 2, "removed_item": 9}, "item_cooldowns": {"1bb38a9b-68ca-55e1-88ff-933102dbcb64": 12.0, "removed_item": 99.0}}))
	normalized_file = null
	_assert_true(game_state.load_game(), "当前版本归一化测试存档应可读取")
	_assert_true(str(game_state.profile.name) == "1234567890" and int(game_state.profile.vitals.food) == 350, "读档应裁剪姓名并按派生编码钳制食物上限（实际 %s / %d）" % [game_state.profile.name, game_state.profile.vitals.food])
	_assert_true(int(game_state.profile.vitals.money) == 0 and int(game_state.profile.vitals.potential) == 0, "读档应将资源钳为非负整数")
	_assert_true(game_state.inventory == {"1bb38a9b-68ca-55e1-88ff-933102dbcb64": 2} and game_state.item_cooldowns == {"1bb38a9b-68ca-55e1-88ff-933102dbcb64": 12.0}, "读档应清除未知物品和冷却记录")
	game_state.use_test_save_path("obsolete-save-version")
	game_state.delete_save()
	var obsolete_file := FileAccess.open(game_state.current_save_path(), FileAccess.WRITE)
	obsolete_file.store_string(JSON.stringify({"version": 4, "profile": normalized_profile}))
	obsolete_file = null
	_assert_true(not game_state.load_game() and game_state._read_save_document(game_state.current_save_path()).is_empty(), "v4 及更早存档必须直接拒绝，不得隐式迁移")
	game_state.create_profile("alignment-test", {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25})
	game_state.profile.vitals.potential = 100000
	game_state.profile.vitals.money = 100000
	var bought: Dictionary = inventory_system.buy_item("fface007-32fe-52f4-8e8c-19b497f364e8", "6ef0a50a-9443-58dc-ab43-fd31c942b998")
	_assert_true(str(bought.get("message", "")) == "买下临幸咖啡，花费 99 Token。", "购买成功文案应准确展示物品与花费")
	var sold: Dictionary = inventory_system.sell_item("6ef0a50a-9443-58dc-ab43-fd31c942b998")
	_assert_true(str(sold.get("message", "")) == "卖出临幸咖啡，得 24 Token。", "出售成功文案应准确展示物品与所得")
	inventory_system.add_item("6ef0a50a-9443-58dc-ab43-fd31c942b998")
	var discarded: Dictionary = inventory_system.discard_item("6ef0a50a-9443-58dc-ab43-fd31c942b998")
	_assert_true(str(discarded.get("message", "")) == "丢弃了临幸咖啡。", "丢弃成功文案应准确展示物品")
	# 师父高低严格取教学表显式 maxTeachLevel；鱿鱼须的字符串旧格式上限为 0。
	game_state.profile.sect = "鱿鱼山庄"
	game_state.profile.master = "c3e0a935-ec47-584f-9a90-648ead8dc206"
	_assert_true(not skill_system.can_join("1f8eac82-dee2-5f0f-a499-d133299a1171") and str(skill_system.join_npc("1f8eac82-dee2-5f0f-a499-d133299a1171").message).contains("造诣不及"), "不得用拜师门槛推断师父造诣；鱿鱼须教学上限 0 不高于维特 60")
	# 技能书须使用道具自身 maxLearnLevel，而非只看技能总上限。
	data_registry.items["__alignment_book"] = {"name": "测试秘籍", "kind": "book", "skillId": "2224675d-63f2-50e8-a2c6-064acd5c5623", "maxLearnLevel": 1, "stackLimit": 2}
	inventory_system.add_item("__alignment_book", 2)
	var first_book: Dictionary = inventory_system.use_item("__alignment_book")
	var capped_book: Dictionary = inventory_system.use_item("__alignment_book")
	_assert_true(bool(first_book.get("ok", false)) and skill_system.level("2224675d-63f2-50e8-a2c6-064acd5c5623") == 1 and not bool(capped_book.get("ok", true)) and str(capped_book.get("message", "")).contains("读到 1 级"), "技能书应在道具 maxLearnLevel 处停止并退还未生效的书")
	game_state.inventory.erase("__alignment_book")
	data_registry.items.erase("__alignment_book")
	# 异门功法即使被直接写入技能状态也不得装备；本门成功文案同时对齐标点。
	skill_system.ensure_skills().levels["bcb538e2-4d6a-52ae-990d-20377e27ab64"] = 1
	game_state.profile.sect = "香草派"
	_assert_true(skill_system.equip("bcb538e2-4d6a-52ae-990d-20377e27ab64").message == "非本门功法，不能装备。", "异门功法必须拒绝装备")
	game_state.profile.sect = "NG神教"
	_assert_true(skill_system.equip("bcb538e2-4d6a-52ae-990d-20377e27ab64").message == "已装备【模版语法】。", "本门功法装备成功文案应稳定展示功法名")
	game_state.profile.sect = ""
	game_state.profile.master = ""
	_assert_true(int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 480 and int(ProjectSettings.get_setting("display/window/size/viewport_height")) == 320, "逻辑视口应为 480×320")
	_assert_true(int(ProjectSettings.get_setting("display/window/size/window_width_override")) == 1280 and int(ProjectSettings.get_setting("display/window/size/window_height_override")) == 960, "Windows 与 macOS 默认窗口应为 1280×960")
	_assert_true(str(ProjectSettings.get_setting("display/window/stretch/aspect")) == "keep", "窗口应保持 480×320 设计比例，不得扩展逻辑坐标系")

	# 全地图 NPC 目标注册：读取 TMX property npcId，并保留地图显示名。
	var placed_targets: Array[Dictionary] = data_registry.list_placed_npc_targets()
	_assert_true(not placed_targets.is_empty(), "全地图 NPC 任务目标池不应为空")
	var found_training_tutor := false
	for placed_target in placed_targets:
		_assert_true(not data_registry.get_npc(str(placed_target.get("npc_id", ""))).is_empty(), "任务目标池不应包含未注册 NPC")
		if str(placed_target.get("npc_id", "")) == "831434cb-2471-5f24-9fdf-0259fe149eae" and str(placed_target.get("map_id", "")) == "8f8add5e-93f8-5afe-b3e6-ba96dfc273c8":
			found_training_tutor = str(placed_target.get("map_name", "")) == "DARK学"
	_assert_true(found_training_tutor, "应从 DarkXue.tmx 收集导师及 DARK学地图名")
	for excluded_target in data_registry.list_placed_npc_targets(["ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1"]):
		_assert_true(str(excluded_target.get("npc_id", "")) != "ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1", "任务发布者应能从目标池排除")
	var original_endpoint_targets: Array[Dictionary] = data_registry.placed_npc_targets.duplicate(true)
	data_registry.placed_npc_targets.assign([
		{"npc_id": "831434cb-2471-5f24-9fdf-0259fe149eae", "map_id": "test", "map_name": "测试地图"},
		{"npc_id": "c6592971-0e60-5f47-969c-2db122c7c011", "map_id": "test", "map_name": "测试地图"},
		{"npc_id": "95621051-c06f-58a7-b004-b4eee0d7f472", "map_id": "test", "map_name": "测试地图"},
		{"npc_id": "0b38ec96-d752-5083-a03c-aa0ac49a6dc1", "map_id": "test", "map_name": "测试地图"},
	])
	quest_system.reset_runtime()
	var endpoint_safe_offer: Dictionary = quest_system.offer_generator("55578b74-31b5-5ef9-87d1-350ffb56e109")
	var endpoint_safe_target := str(quest_system.active.get("generator:" + DELIVERY_RING_ID, {}).get("target", {}).get("target_id", ""))
	_assert_true(bool(endpoint_safe_offer.get("ok", false)) and endpoint_safe_target in ["831434cb-2471-5f24-9fdf-0259fe149eae", "0b38ec96-d752-5083-a03c-aa0ac49a6dc1"], "非击杀任务只排除其他任务的交付端点，不应全局禁用所有发布者")
	quest_system.reset_runtime()
	data_registry.placed_npc_targets.assign(original_endpoint_targets)
	quest_system.reset_runtime()
	seed(1)
	var generated_ring: Dictionary = quest_system.offer_generator("55578b74-31b5-5ef9-87d1-350ffb56e109")
	_assert_true(bool(generated_ring.get("ok", false)), "九日环应能从真实地图生成 NPC 目标")
	_assert_true(not str(generated_ring.get("message", "")).contains("【】"), "九日环文案不应缺失地图或 NPC")
	var generated_target: Dictionary = quest_system.active.get("generator:" + DELIVERY_RING_ID, {}).get("target", {})
	_assert_true(not str(generated_target.get("target_id", "")).is_empty() and not str(generated_target.get("map_name", "")).is_empty(), "九日环运行时应保存 NPC 与地图显示名")
	var parallel_bounty: Dictionary = quest_system.offer_bounty()
	var parallel_novice: String = quest_system.interact_npc("831434cb-2471-5f24-9fdf-0259fe149eae")
	_assert_true(bool(parallel_bounty.get("ok", false)) and parallel_novice.contains("【"), "普通环进行中仍应能跨类型接取悬赏环和新手任务")
	_assert_true(quest_system.active.has("generator:" + DELIVERY_RING_ID) and quest_system.active.has("generator:" + BOUNTY_RING_ID) and quest_system.active.has(NOVICE_PROJECT_ID), "普通环、悬赏环和新手任务应能同时保持 active")
	_assert_true(int(quest_system.active.get(NOVICE_PROJECT_ID, {}).get("reward", {}).get("potential", -1)) == 50, "从导师实际接取的任意项目都必须把 50 潜能写入运行时奖励快照")
	var duplicate_ring: Dictionary = quest_system.offer_generator("55578b74-31b5-5ef9-87d1-350ffb56e109")
	var duplicate_bounty: Dictionary = quest_system.offer_bounty()
	var active_count_before_novice_repeat: int = quest_system.active.size()
	var repeated_novice: String = quest_system.interact_npc("831434cb-2471-5f24-9fdf-0259fe149eae")
	_assert_true(not bool(duplicate_ring.get("ok", true)) and not bool(duplicate_bounty.get("ok", true)), "同一 generator runtime_id 不得重复接取")
	_assert_true(repeated_novice.contains("咋还没做完") and quest_system.active.size() == active_count_before_novice_repeat, "同一固定任务 ID 不得重复接取")
	_assert_true(quest_system._base_reward({"rewardBase": 10}) == {"experience": 20, "potential": 30, "money": 24}, "通用 rewardBase 必须按 2:3:2.4 拆分")
	var novice_definition: Dictionary = data_registry.get_quest(NOVICE_PROJECT_ID)
	var novice_reward: Dictionary = quest_system.rewards.base_reward(novice_definition)
	_assert_true(int(novice_reward.get("experience", -1)) == 50 and int(novice_reward.get("potential", -1)) == 50 and int(novice_reward.get("money", -1)) == 40, "导师项目必须固定奖励 50 经验、50 潜能、40 Token，当前为 %s" % [novice_reward])
	for variant in novice_definition.get("variants", []):
		_assert_true(not variant.has("rewardScale"), "导师项目难度只允许改变体力成本，%s 不得携带奖励缩放字段" % variant.get("title", "项目"))
	_assert_true(quest_system._scaled_reward({"ringGrowth": 0.5, "fluctuation": 0.0}, {"experience": 1}, 2).experience == 1, "九日环增长后的小数奖励应向下取整而非四舍五入")
	_assert_true(quest_system._scaled_reward({"ringGrowth": 1.0, "growthCap": 2.5, "fluctuation": 0.0}, {"experience": 10}, 10).experience == 25, "九日环线性增长必须受 growthCap 封顶")
	data_registry.items["__refund_item"] = {"name": "退款测试物", "kind": "food", "price": 100, "stackLimit": 2}
	var refund_definition := {"type": "ring", "reward": {"experience": 0, "potential": 0, "money": 10}, "ringSize": 1, "ringGrowth": 1.0, "fluctuation": 0.0, "itemRefundRate": 1.0, "itemExtraMoney": 20}
	data_registry.quest_generators["__refund_ring"] = refund_definition
	var refund_runtime := {"generator_id": "__refund_ring", "kind": "ring", "item_id": "__refund_item", "item_name": "退款测试物", "reward": {}}
	quest_system.generator._assign_reward(refund_runtime, refund_definition, "ring")
	quest_system.active["generator:__refund_ring"] = refund_runtime
	quest_system.ring_progress["__refund_ring"] = 1
	game_state.inventory["__refund_item"] = 1
	var money_before_refund := int(game_state.profile.vitals.money)
	var refunded_ring: Dictionary = quest_system.advance_generator("__refund_ring")
	_assert_true(bool(refunded_ring.get("ok", false)) and int(refunded_ring.reward.money) == 160 and int(game_state.profile.vitals.money) == money_before_refund + 160, "物品原价 100 应固定退款；只有 10+20 的任务报酬参与第二环×2，合计应为 160")
	data_registry.items.erase("__refund_item")
	data_registry.quest_generators.erase("__refund_ring")
	quest_system.reset_runtime()

	# 小不二动态悬赏：严格使用四段姓名、父地图播报、五项基础技能和安全落点。
	quest_system.reset_runtime()
	var bounty_definition: Dictionary = data_registry.quest_generators[BOUNTY_RING_ID].duplicate(true)
	bounty_definition.spawnMaps = ["8f8add5e-93f8-5afe-b3e6-ba96dfc273c8"]
	data_registry.quest_generators[BOUNTY_RING_ID] = bounty_definition
	seed(7)
	var bounty_offer: Dictionary = quest_system.offer_bounty()
	_assert_true(bool(bounty_offer.get("ok", false)), "小不二悬赏应能生成动态目标")
	var bounty: Dictionary = quest_system.get_bounty_target()
	_assert_true(quest_system.bounty_board_text() == str(bounty_offer.get("message", "")), "暗网悬赏榜应复用接取文案，而非进行中文案")
	var bounty_name_pattern := RegEx.new()
	bounty_name_pattern.compile("^(傻X|脑残|白痴|霸道|凶狠)(老板|客户|领导|同事|朋友)(赵|钱|孙|李|周|吴|郑|王)(一|二|三|四|五|六|七|八|九|十)$")
	_assert_true(bounty_name_pattern.search(str(bounty.get("target_name", ""))) != null, "悬赏目标姓名应按原项目四段词库生成")
	_assert_true(str(bounty.get("map_name", "")) == "开源镇", "室内悬赏地点应播报父级大地图名称")
	var runtime_bounty: Dictionary = root.get_node("NpcSystem").build_instance(str(bounty.get("target_id", "")))
	_assert_true(runtime_bounty.get("skillLevels", {}).keys().size() == 5 and runtime_bounty.get("equippedSkillIds", []).size() == 5, "悬赏目标应缩放并装备五项基础技能")
	var dark_study_map := TiledMapLoader.new()
	_assert_true(dark_study_map.load_file("res://assets/Map/maps/LoreWorld/KaiyuanTown/DarkXue.tmx"), "应能加载 DARK学室内地图")
	_assert_true(data_registry.map_type("8f8add5e-93f8-5afe-b3e6-ba96dfc273c8") == "inDoor" and data_registry.map_type("25f3952d-ec39-53af-a8c1-d523c43b80b0") == "outDoor", "地图注册阶段应缓存室内/室外类型，传送菜单不得临时重读 TMX")
	_assert_true(not dark_study_map.npc_object_at_tile(7, 6).is_empty(), "NPC point 对象应命中脚下单格")
	_assert_true(dark_study_map.npc_object_at_tile(8, 6).is_empty(), "NPC point 对象不得扩张命中相邻格")
	var bounty_tile: Vector2i = dark_study_map.pick_dynamic_npc_tile()
	_assert_true(bounty_tile.x >= 0 and dark_study_map.is_walkable(bounty_tile.x, bounty_tile.y) and dark_study_map.is_walkable(bounty_tile.x, bounty_tile.y - 1), "室内悬赏 NPC 应落在身前无墙的可行走格")
	_assert_true(dark_study_map.npc_object_at_tile(bounty_tile.x, bounty_tile.y).is_empty(), "动态悬赏 NPC 不应与固定 NPC 重叠")
	var fixed_reward_definition := bounty_definition.duplicate(true)
	fixed_reward_definition.fluctuationMin = 0.0
	fixed_reward_definition.fluctuationMax = 0.0
	var bounty_runtime_id := "generator:" + BOUNTY_RING_ID
	var settled_bounty: Dictionary = quest_system._settle_bounty_ring(bounty_runtime_id, quest_system.active[bounty_runtime_id], fixed_reward_definition)
	_assert_true(settled_bounty.reward == {"experience": 90, "potential": 90, "money": 72}, "小不二悬赏基础奖励应按经验×3、潜能×3、Token×2.4 计算")
	quest_system.reset_runtime()
	var linear_bounty := {"rewardBase": 100, "ringSize": 3, "rewardGrowthMin": 0.10, "rewardGrowthMax": 0.10, "statGrowthMin": 0.20, "statGrowthMax": 0.20, "fluctuationMin": 0.0, "fluctuationMax": 0.0}
	quest_system.bounty_money_base["__linear_bounty"] = 100.0
	quest_system.bounty_stat_base["__linear_bounty"] = 100.0
	var linear_first: Dictionary = quest_system._settle_bounty_ring("generator:__linear_bounty", {"generator_id": "__linear_bounty"}, linear_bounty)
	var linear_second: Dictionary = quest_system._settle_bounty_ring("generator:__linear_bounty", {"generator_id": "__linear_bounty"}, linear_bounty)
	var linear_third: Dictionary = quest_system._settle_bounty_ring("generator:__linear_bounty", {"generator_id": "__linear_bounty"}, linear_bounty)
	_assert_true(linear_first.reward == {"experience": 300, "potential": 300, "money": 240} and linear_second.reward == {"experience": 360, "potential": 360, "money": 264}, "悬赏第二轮奖励必须从初始基数线性增长，不得复利")
	_assert_true(bool(linear_third.complete) and linear_third.reward == {"experience": 420, "potential": 420, "money": 288} and int(quest_system.ring_progress.get("__linear_bounty", -1)) == 0, "悬赏满环必须结算第三轮线性奖励并重置进度")
	_assert_true(float(quest_system.bounty_money_base.get("__linear_bounty", -1.0)) == 100.0 and float(quest_system.bounty_stat_base.get("__linear_bounty", -1.0)) == 100.0, "悬赏满环后两类奖励基数必须恢复初始值")
	quest_system.reset_runtime()
	data_registry.quest_generators["__standard_bounty"] = {"type": "bounty", "reward": {"experience": 10, "potential": 10, "money": 10}}
	quest_system.active["generator:__standard_bounty"] = {"generator_id": "__standard_bounty", "kind": "bounty", "target": {"target_id": "0b38ec96-d752-5083-a03c-aa0ac49a6dc1", "target_name": "Qc."}, "ready": false}
	var bounty_progress_line: String = quest_system.on_enemy_defeated("0b38ec96-d752-5083-a03c-aa0ac49a6dc1")
	_assert_true(not bounty_progress_line.is_empty() and bool(quest_system.active["generator:__standard_bounty"].ready), "普通悬赏击杀必须返回非空进度文案，以阻止战斗结算重复发放野战奖励")
	data_registry.quest_generators.erase("__standard_bounty")
	quest_system.reset_runtime()
	data_registry.quest_generators["__talk_ring"] = {"type": "ring", "reward": {"experience": 10, "potential": 10, "money": 10}}
	quest_system.active["generator:__talk_ring"] = {"generator_id": "__talk_ring", "kind": "ring", "target": {"target_id": "0b38ec96-d752-5083-a03c-aa0ac49a6dc1", "target_name": "Qc."}, "reward": {"experience": 10, "potential": 10, "money": 10}}
	var talk_ring_defeat: Dictionary = quest_system.handle_enemy_defeated("0b38ec96-d752-5083-a03c-aa0ac49a6dc1")
	_assert_true(not bool(talk_ring_defeat.get("handled", true)) and quest_system.active.has("generator:__talk_ring"), "击败跑腿/谈话目标不得推进或结算非击杀任务")
	data_registry.quest_generators.erase("__talk_ring")
	quest_system.reset_runtime()

	# 生死簿只允许抽取成年、可战斗且没有任务保护的普通人物。
	var original_targets: Array[Dictionary] = data_registry.placed_npc_targets.duplicate(true)
	var synthetic_kill_npcs := {
		"__kill_minor": {"displayName": "未成年战斗员", "age": 15, "roles": ["civilian"], "combatRank": "trained", "attributes": {"strength": 10, "agility": 10, "constitution": 10, "wisdom": 10}, "skillLevels": {}},
		"__kill_seventeen": {"displayName": "十七岁战斗员", "age": 17, "roles": ["civilian"], "combatRank": "trained", "attributes": {"strength": 10, "agility": 10, "constitution": 10, "wisdom": 10}, "skillLevels": {}},
		"__kill_noncombatant": {"displayName": "成年非战斗员", "age": 30, "roles": ["civilian"], "combatRank": "noncombatant", "attributes": {"strength": 10, "agility": 10, "constitution": 10, "wisdom": 10}, "skillLevels": {}},
		"__kill_vendor": {"displayName": "成年商贩", "age": 30, "roles": ["vendor"], "combatRank": "trained", "attributes": {"strength": 10, "agility": 10, "constitution": 10, "wisdom": 10}, "skillLevels": {}},
		"__kill_master": {"displayName": "成年师父", "age": 30, "roles": ["master"], "combatRank": "trained", "attributes": {"strength": 10, "agility": 10, "constitution": 10, "wisdom": 10}, "skillLevels": {}},
		"__kill_optout": {"displayName": "剧情保护人物", "age": 30, "roles": ["civilian"], "combatRank": "trained", "targetableByKillQuest": false, "attributes": {"strength": 10, "agility": 10, "constitution": 10, "wisdom": 10}, "skillLevels": {}},
		"__kill_eligible": {"displayName": "合法目标", "age": 30, "roles": ["civilian"], "combatRank": "trained", "attributes": {"strength": 10, "agility": 10, "constitution": 10, "wisdom": 10}, "skillLevels": {"2224675d-63f2-50e8-a2c6-064acd5c5623": 10}},
	}
	for synthetic_id in synthetic_kill_npcs:
		data_registry.npcs[synthetic_id] = synthetic_kill_npcs[synthetic_id]
	var rank_reward_definition := {"rewardPotentialScale": 1.0, "rewardPotentialMin": 0, "rewardPotentialMax": 999999}
	var novice_reward_npc: Dictionary = synthetic_kill_npcs["__kill_eligible"].duplicate(true)
	novice_reward_npc.combatRank = "novice"
	var legendary_reward_npc: Dictionary = synthetic_kill_npcs["__kill_eligible"].duplicate(true)
	legendary_reward_npc.combatRank = "legendary"
	data_registry.npcs["__rank_reward_novice"] = novice_reward_npc
	data_registry.npcs["__rank_reward_legendary"] = legendary_reward_npc
	var novice_kill_reward: Dictionary = quest_system._kill_ring_reward(rank_reward_definition, "__rank_reward_novice")
	var legendary_kill_reward: Dictionary = quest_system._kill_ring_reward(rank_reward_definition, "__rank_reward_legendary")
	_assert_true(int(legendary_kill_reward.potential) > int(novice_kill_reward.potential), "生死簿奖励必须计入战斗阶位，传奇目标应高于同数值新手目标")
	data_registry.npcs.erase("__rank_reward_novice")
	data_registry.npcs.erase("__rank_reward_legendary")
	# 除合法目标外的全部合成人物摆放；两次目标池检查共用同一份列表。
	var ineligible_placements: Array = []
	for synthetic_id in synthetic_kill_npcs:
		if synthetic_id != "__kill_eligible":
			ineligible_placements.append({"npc_id": synthetic_id, "map_id": "test", "map_name": "测试地图"})
	data_registry.placed_npc_targets.assign([
		{"npc_id": "95621051-c06f-58a7-b004-b4eee0d7f472", "map_id": "test", "map_name": "测试地图"},
		{"npc_id": "ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1", "map_id": "test", "map_name": "测试地图"},
		{"npc_id": "c6592971-0e60-5f47-969c-2db122c7c011", "map_id": "test", "map_name": "测试地图"},
		{"npc_id": "831434cb-2471-5f24-9fdf-0259fe149eae", "map_id": "test", "map_name": "测试地图"},
	] + ineligible_placements)
	var allowed_endpoint_target: Dictionary = quest_system._placed_npc_target([], true)
	_assert_true(str(allowed_endpoint_target.get("npc_id", "")) in ["95621051-c06f-58a7-b004-b4eee0d7f472", "ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1", "c6592971-0e60-5f47-969c-2db122c7c011", "831434cb-2471-5f24-9fdf-0259fe149eae"], "生死簿应允许其他任务的发布或交付人物成为击杀目标，同时继续过滤未成年与受保护人物")
	data_registry.placed_npc_targets.assign(ineligible_placements + [{"npc_id": "__kill_eligible", "map_id": "test", "map_name": "测试地图"}])
	quest_system.reset_runtime()
	var filtered_kill_offer: Dictionary = quest_system.offer_generator("2bbbd0f5-280f-5141-a4ad-79fcb3478579")
	_assert_true(bool(filtered_kill_offer.get("ok", false)) and str(quest_system.active.get("generator:" + KILL_RING_ID, {}).get("target", {}).get("target_id", "")) == "__kill_eligible", "生死簿仍应只从过滤后的成年普通战斗人物中生成目标")
	data_registry.placed_npc_targets.assign(original_targets)
	for synthetic_id in synthetic_kill_npcs:
		data_registry.npcs.erase(synthetic_id)
	quest_system.reset_runtime()
	# 学艺逻辑本身不离散快进；时间由 Game 场景的逐帧统一时钟推进。
	game_state.profile.sect = "NG神教"
	game_state.profile.master = "21e05288-a075-5137-85e8-a6c4c115be87"
	var before_time: float = game_state.game_time_sec
	var learn_result: Dictionary = skill_system.learn_tick("21e05288-a075-5137-85e8-a6c4c115be87", "2224675d-63f2-50e8-a2c6-064acd5c5623")
	_assert_true(not learn_result.has("reason"), "学习 tick 应实际推进")
	_assert_true(is_equal_approx(game_state.game_time_sec, before_time), "学习 tick 不应重复推进全局时钟")

	# 当前设定：学习/冥想 10 Hz、练功每秒 5 tick。
	_assert_true(is_equal_approx(skill_system.LEARNING_TICK_SECONDS, 1.0 / 10.0), "学习应每秒推进 10 次")
	_assert_true(is_equal_approx(skill_system.MEDITATION_TICK_SECONDS, 1.0 / 10.0), "冥想应每秒推进 10 次")
	_assert_true(is_equal_approx(skill_system.PRACTICE_TICK_SECONDS, 1.0 / 5.0), "练功应每秒推进 5 次")
	game_state.profile.attributes.constitution = 29
	game_state.profile.vitals.cultivation = 130
	_assert_true(game_state.player_mp_max() == 130 and game_state.player_hp_max() == 374, "29 根骨、130 修为且未装备架构功法时，应有 130 精力和 374 体力")
	var vitality_skill_state: Dictionary = skill_system.ensure_skills()
	vitality_skill_state.levels[BASIC_CONSTITUTION_SKILL_ID] = 10
	vitality_skill_state.levels[SECT_CONSTITUTION_SKILL_ID] = 5
	vitality_skill_state.equipped_basic.arch = "dcebef7e-09b8-5a69-8e3d-159cb2b0c355"
	vitality_skill_state.equipped_special.arch = "9287473e-59a9-5dc8-a914-324ec57ffc14"
	_assert_true(int(skill_system.combat_bonus().get("mp_max", 0)) == 25 and game_state.player_mp_max() == 155 and game_state.player_hp_max() == 377, "已装备架构功法的 10+5×3 上限加成应进入总精力，并通过平方根公式反哺体力")
	game_state.combat_state.mp = 155
	_assert_true(bool(skill_system.unequip("9287473e-59a9-5dc8-a914-324ec57ffc14").get("ok", false)) and game_state.player_mp_max() == 140 and int(game_state.combat_state.mp) == 140, "卸下高级架构功法后应立即把当前精力钳到新上限")
	_assert_true(bool(skill_system.unequip("dcebef7e-09b8-5a69-8e3d-159cb2b0c355").get("ok", false)) and game_state.player_mp_max() == 130 and int(game_state.combat_state.mp) == 130, "卸下基础架构功法后也应立即归一化资源")
	vitality_skill_state.levels.erase("dcebef7e-09b8-5a69-8e3d-159cb2b0c355")
	vitality_skill_state.levels.erase("9287473e-59a9-5dc8-a914-324ec57ffc14")
	game_state.profile.attributes.constitution = 25
	# 练功：有效 tick 推进 1/5 秒，并消耗精力。
	var skills: Dictionary = skill_system.ensure_skills()
	skills.levels[BASIC_STRENGTH_SKILL_ID] = 5
	skills.levels[SECT_CODE_SKILL_ID] = 1
	game_state.profile.vitals.cultivation = 5
	game_state.combat_state.hp = game_state.player_effective_hp_max()
	game_state.combat_state.mp = 5
	before_time = game_state.game_time_sec
	var practice_result: Dictionary = skill_system.practice_tick("bcb538e2-4d6a-52ae-990d-20377e27ab64")
	_assert_true(bool(practice_result.get("ok", false)), "练功 tick 应成功")
	_assert_true(str(practice_result.get("message", "")).begins_with("你苦练【模版语法】") and str(practice_result.get("message", "")).contains("，进度 "), "练功普通推进文案应同时展示功法名与当前进度")
	_assert_true(is_equal_approx(game_state.game_time_sec - before_time, 1.0 / 5.0), "练功 tick 应推进 1/5 秒")

	# 冥想：装备基础/高级架构后，有效 tick 推进 1/10 秒。
	skills.levels[BASIC_CONSTITUTION_SKILL_ID] = 2
	skills.levels[SECT_CONSTITUTION_SKILL_ID] = 1
	skills.equipped_special.arch = "9287473e-59a9-5dc8-a914-324ec57ffc14"
	_assert_true(not skill_system.can_meditate(), "只学会但未装备基础架构时不得冥想")
	skills.equipped_basic.arch = "dcebef7e-09b8-5a69-8e3d-159cb2b0c355"
	game_state.profile.vitals.cultivation = 1
	game_state.combat_state.mp = 0
	before_time = game_state.game_time_sec
	var meditation_result: Dictionary = skill_system.meditate_tick()
	_assert_true(bool(meditation_result.get("ok", false)), "冥想 tick 应成功")
	_assert_true(is_equal_approx(game_state.game_time_sec - before_time, 1.0 / 10.0), "冥想 tick 未推进 1/10 秒")

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

	LEARNING_SUITE.run(self, _assert_true)
	var basic_skill_id := "2224675d-63f2-50e8-a2c6-064acd5c5623"
	var previous_basic_level: int = skill_system.level(basic_skill_id)
	skill_system.ensure_skills().levels[basic_skill_id] = 4
	_assert_true(int(skill_system.learning_progress(basic_skill_id).total) == 22, "基础功法 4→5 级应固定需要 22 学习经验")
	skill_system.ensure_skills().levels[basic_skill_id] = previous_basic_level

	# 九日送物：缺物品不结算，装备中不结算，卸下后扣物并发奖。
	quest_system.reset_runtime()
	quest_system.active["generator:" + DELIVERY_RING_ID] = {
		"generator_id": "55578b74-31b5-5ef9-87d1-350ffb56e109", "kind": "ring", "giverNpcId": "ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1",
		"target": {"target_id": "de6328e3-32c7-5560-b6c7-298a7fa02a03", "target_name": "Brendan Eich", "map_id": "44ebb310-6990-5d82-bc23-623343b9acca"},
		"item_id": "1bb38a9b-68ca-55e1-88ff-933102dbcb64", "item_name": "法棍",
		"reward": {"experience": 75, "potential": 50, "money": 60},
	}
	var missing_message: String = quest_system.interact_npc("de6328e3-32c7-5560-b6c7-298a7fa02a03")
	_assert_true(missing_message.contains("不在你身上"), "九日送物缺少道具时不应结算")
	inventory_system.add_item("1bb38a9b-68ca-55e1-88ff-933102dbcb64", 1)
	# 运行时按装备表判定；这里直接构造配置可能出现的已装备状态。
	game_state.equipment.weapon = "1bb38a9b-68ca-55e1-88ff-933102dbcb64"
	var equipped_message: String = quest_system.interact_npc("de6328e3-32c7-5560-b6c7-298a7fa02a03")
	_assert_true(equipped_message.contains("卸下来"), "九日送物装备中时不应结算")
	game_state.equipment.weapon = ""
	var exp_before := int(game_state.profile.vitals.experience)
	quest_system.interact_npc("de6328e3-32c7-5560-b6c7-298a7fa02a03")
	_assert_true(inventory_system.count("1bb38a9b-68ca-55e1-88ff-933102dbcb64") == 0, "九日送物成功后应扣除道具")
	_assert_true(int(game_state.profile.vitals.experience) > exp_before, "九日送物成功后应发放奖励")

	# 杀人环：逐单即时结算，满 ringSize 后计数归零并进入冷却。
	quest_system.reset_runtime()
	exp_before = int(game_state.profile.vitals.experience)
	for index in 10:
		quest_system.active["generator:" + KILL_RING_ID] = {
			"generator_id": "2bbbd0f5-280f-5141-a4ad-79fcb3478579",
			"target": {"target_id": "kill_target_%d" % index, "target_name": "目标", "map_id": "25f3952d-ec39-53af-a8c1-d523c43b80b0"},
			"reward": {"experience": 50, "potential": 50, "money": 40},
		}
		quest_system.on_enemy_defeated("kill_target_%d" % index)
	_assert_true(int(game_state.profile.vitals.experience) == exp_before + 500, "杀人环每单应按快照即时发奖")
	_assert_true(int(quest_system.ring_progress.get("2bbbd0f5-280f-5141-a4ad-79fcb3478579", -1)) == 0, "杀人环满环后计数应归零")
	_assert_true(float(quest_system.cooldown_until.get("2bbbd0f5-280f-5141-a4ad-79fcb3478579", 0.0)) > game_state.game_time_sec, "杀人环结算后应进入冷却")

	# DARK 学项目：5 秒锁定对话结束前不扣体力、不发奖，结束后才结算。
	quest_system.reset_runtime()
	quest_system.active[NOVICE_PROJECT_ID] = {
		"completion_giver_id": "d07dc3ae-a94f-5bf5-a352-b2c487682d31", "target": "测试项目", "hp_cost": 10,
		"reward": {"experience": 7, "potential": 6, "money": 5},
	}
	game_state.combat_state.hp = 100
	exp_before = int(game_state.profile.vitals.experience)
	var hp_before := int(game_state.combat_state.hp)
	var project_intro: Dictionary = quest_system.begin_novice_completion("d07dc3ae-a94f-5bf5-a352-b2c487682d31")
	_assert_true(float(project_intro.get("lock_seconds", 0.0)) == 5.0, "项目交付应锁定对话 5 秒")
	_assert_true(int(game_state.combat_state.hp) == hp_before and int(game_state.profile.vitals.experience) == exp_before, "锁定对话结束前不应结算项目")
	quest_system.finish_novice_completion("d07dc3ae-a94f-5bf5-a352-b2c487682d31")
	_assert_true(int(game_state.combat_state.hp) == hp_before - 10, "项目完成后应扣除体力")
	_assert_true(int(game_state.profile.vitals.experience) == exp_before + 7, "项目完成后应发放奖励")

	# 通用寻物差事：回发布者时验物、扣物、发奖并开始冷却。
	quest_system.reset_runtime()
	data_registry.quest_generators.test_errand = {
		"type": "errand", "giverNpcId": "test_giver", "cooldownSec": 10,
		"pool": {"items": ["1bb38a9b-68ca-55e1-88ff-933102dbcb64"]}, "reward": {"experience": 3, "potential": 2, "money": 1},
	}
	quest_system.offer_generator("test_errand")
	exp_before = int(game_state.profile.vitals.experience)
	quest_system.interact_npc("test_giver")
	_assert_true(int(game_state.profile.vitals.experience) == exp_before, "寻物差事缺物品时不应发奖")
	inventory_system.add_item("1bb38a9b-68ca-55e1-88ff-933102dbcb64", 1)
	quest_system.interact_npc("test_giver")
	_assert_true(inventory_system.count("1bb38a9b-68ca-55e1-88ff-933102dbcb64") == 0, "寻物差事交付后应扣除目标物品")
	_assert_true(int(game_state.profile.vitals.experience) == exp_before + 3, "寻物差事交付后应发奖")

	# 通用送信差事：目标 NPC 保留普通对话，只标记见面，回发布者交差。
	quest_system.reset_runtime()
	data_registry.quest_generators.test_talk_errand = {
		"type": "errand", "giverNpcId": "test_talk_giver", "cooldownSec": 10,
		"pool": {"npcs": ["de6328e3-32c7-5560-b6c7-298a7fa02a03"]}, "reward": {"experience": 4, "potential": 0, "money": 0},
	}
	quest_system.offer_generator("test_talk_errand")
	_assert_true(quest_system.interact_npc("de6328e3-32c7-5560-b6c7-298a7fa02a03").is_empty(), "送信目标不应覆盖普通 NPC 对话")
	exp_before = int(game_state.profile.vitals.experience)
	quest_system.interact_npc("test_talk_giver")
	_assert_true(int(game_state.profile.vitals.experience) == exp_before + 4, "见过送信目标后应可回发布者交差")

	# 通用悬赏：击杀只标 ready，必须回发布者才结算。
	quest_system.reset_runtime()
	data_registry.quest_generators.test_bounty = {
		"type": "bounty", "giverNpcId": "test_bounty_giver", "cooldownSec": 10,
		"enemyPool": ["0b38ec96-d752-5083-a03c-aa0ac49a6dc1"], "spawnMaps": ["25f3952d-ec39-53af-a8c1-d523c43b80b0"],
		"reward": {"experience": 5, "potential": 0, "money": 0},
	}
	quest_system.offer_generator("test_bounty")
	exp_before = int(game_state.profile.vitals.experience)
	quest_system.on_enemy_defeated("0b38ec96-d752-5083-a03c-aa0ac49a6dc1")
	_assert_true(int(game_state.profile.vitals.experience) == exp_before, "普通悬赏击杀时不应即时发奖")
	quest_system.interact_npc("test_bounty_giver")
	_assert_true(int(game_state.profile.vitals.experience) == exp_before + 5, "普通悬赏应回发布者领赏")
	data_registry.quest_generators.erase("test_errand")
	data_registry.quest_generators.erase("test_talk_errand")
	data_registry.quest_generators.erase("test_bounty")
	# 道具：满状态不消耗；有效使用展示原设定效果文案；冷却提示含剩余秒数。
	game_state.inventory.clear()
	inventory_system.add_item("6ef0a50a-9443-58dc-ab43-fd31c942b998", 2)
	var capacity: int = game_state.vitals_capacity()
	game_state.profile.vitals.food = capacity
	game_state.profile.vitals.water = capacity
	var item_result: Dictionary = inventory_system.use_item("6ef0a50a-9443-58dc-ab43-fd31c942b998")
	_assert_true(not bool(item_result.get("ok", false)) and inventory_system.count("6ef0a50a-9443-58dc-ab43-fd31c942b998") == 2, "食物饮水已满时不应消耗道具")
	game_state.profile.vitals.water = capacity - 20
	item_result = inventory_system.use_item("6ef0a50a-9443-58dc-ab43-fd31c942b998")
	_assert_true(bool(item_result.get("ok", false)) and str(item_result.message).contains("饮水 +50"), "道具信息应展示配置效果")
	_assert_true(inventory_system.count("6ef0a50a-9443-58dc-ab43-fd31c942b998") == 1, "有效使用应消耗一个道具")
	item_result = inventory_system.use_item("6ef0a50a-9443-58dc-ab43-fd31c942b998")
	_assert_true(not bool(item_result.get("ok", false)) and str(item_result.message).contains("还需"), "冷却提示应展示剩余游戏秒数")
	game_state.equipment.weapon = "85021013-908c-5a02-a78a-35e5a6e85001"
	game_state.save_game()
	game_state.equipment.weapon = "7e19e6c8-cec3-51b4-afd1-14a438cce8d3"
	game_state.load_game()
	_assert_true(str(game_state.equipment.weapon).is_empty(), "穿戴状态不应写入或恢复自存档")
