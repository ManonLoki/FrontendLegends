extends SceneTree
## 数值重制回归：人物分层、四门派镜像回合、奖励、任务过滤与顶级装备定位。

const MIRROR_ROUND_BENCHMARK := preload("res://tests/combat/mirror_round_benchmark.gd")
const INVARIANT_CONTRACT := preload("res://tests/combat/invariant_contract.gd")
const TRIALS := 1000
const EXPECTED_NPC_COUNT := 66
## 合法阶位以 combat_rules 的生命缩放表为唯一来源，避免第二份清单漂移；
## 不能在此 preload combat_rules（-s 编译期自动加载单例未注册），在 _run 里取。
var valid_ranks: Array = []
const VALID_ROLES := [
	"noncombatant", "striker", "skirmisher", "tank",
	"counter", "controller", "balanced",
]

var failures: Array[String] = []

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state = root.get_node("GameState")
	var registry = root.get_node("DataRegistry")
	var npc_system = root.get_node("NpcSystem")
	var combat = root.get_node("CombatSystem")
	var resolver = root.get_node("BattleResolve")
	var quests = root.get_node("QuestSystem")
	valid_ranks = combat.rules.NPC_RANK_HP_SCALE.keys()
	state.use_test_save_path("combat_balance")
	state.delete_save()
	_assert_true(state.current_save_path().begins_with(OS.get_temp_dir()), "数值测试必须使用系统临时目录存档")

	INVARIANT_CONTRACT.run(root, _assert_true)
	_test_npc_schema(registry)
	_test_small_student_ttk(state, npc_system, combat)
	_test_equal_build_mirror_rounds()
	_test_role_formula_separation(state)
	_test_qc_reward(registry)
	_test_combat_reward_scaling(resolver)
	_test_victory_reward_exclusion(state, registry, npc_system, quests, resolver)
	_test_noncombatant_quest_filter(registry, quests)
	_test_generator_endpoint_filtering(registry, quests)
	_test_endgame_weapon_roles(state, registry)

	state.delete_save()
	if failures.is_empty():
		print("combat_balance_test: PASS")
		quit(0)
	else:
		print("combat_balance_test: FAIL (%d)" % failures.size())
		quit(1)

func _test_npc_schema(registry: Node) -> void:
	var npcs: Dictionary = registry.npcs
	_assert_true(npcs.size() == EXPECTED_NPC_COUNT, "数值基线应包含 %d 名 NPC" % EXPECTED_NPC_COUNT)
	var seen_attributes: Dictionary = {}
	var fractional_npcs := 0
	for npc_id in npcs:
		var npc: Dictionary = npcs[npc_id]
		var rank := str(npc.get("combatRank", ""))
		var role := str(npc.get("combatRole", ""))
		_assert_true(valid_ranks.has(rank), "%s 的 combatRank 非法：%s" % [npc_id, rank])
		_assert_true(VALID_ROLES.has(role), "%s 的 combatRole 非法：%s" % [npc_id, role])
		var attributes: Dictionary = npc.get("attributes", {})
		var values: Array[float] = []
		var has_fraction := false
		for key in ["strength", "agility", "constitution", "wisdom"]:
			var value = attributes.get(key, null)
			var is_numeric := value is int or value is float
			_assert_true(is_numeric and float(value) >= 0.0, "%s 的 %s 必须是非负数值" % [npc_id, key])
			var numeric_value := float(value) if is_numeric else -1.0
			values.append(numeric_value)
			has_fraction = has_fraction or not is_equal_approx(numeric_value, round(numeric_value))
		if has_fraction:
			fractional_npcs += 1
		var signature := "%.1f/%.1f/%.1f/%.1f" % values
		_assert_true(not seen_attributes.has(signature), "%s 与 %s 的四维配点重复：%s" % [npc_id, seen_attributes.get(signature, ""), signature])
		seen_attributes[signature] = str(npc_id)
	_assert_true(seen_attributes.size() == EXPECTED_NPC_COUNT, "%d 名 NPC 的四维配点必须全部唯一" % EXPECTED_NPC_COUNT)
	_assert_true(fractional_npcs == EXPECTED_NPC_COUNT, "全部 NPC 都应保留一位小数的个体微差")

func _test_small_student_ttk(state: Node, npc_system: Node, combat: Node) -> void:
	_set_player_profile(state, {"strength": 5, "agility": 5, "constitution": 40, "wisdom": 50})
	var student: Dictionary = npc_system.build_instance("98138ebf-d4f4-515c-aea7-d95bf6155994")
	var student_hp := int(combat.rules.npc_hp_max(student))
	_assert_true(str(student.get("combatRank", "")) == "noncombatant", "小学生必须属于 noncombatant")
	_assert_true(student_hp == 100, "小学生 HP 应精确锁定为 100，当前为 %d" % student_hp)
	var attacks := _simulate_player_attacks(combat, "98138ebf-d4f4-515c-aea7-d95bf6155994", TRIALS, 20260716)
	var median := _percentile(attacks, 0.50)
	var p90 := _percentile(attacks, 0.90)
	_assert_true(median >= 6 and median <= 9, "低编码合法新手击败小学生的攻击次数中位数应为 6–9，当前为 %d" % median)
	_assert_true(p90 <= 12, "低编码合法新手击败小学生的攻击次数 P90 应不超过 12，当前为 %d" % p90)
	_set_player_profile(state, {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25})
	var balanced_student := _simulate_player_attacks(combat, "98138ebf-d4f4-515c-aea7-d95bf6155994", TRIALS, 20260717)
	_assert_true(_percentile(balanced_student, 0.50) >= 2, "均衡新手击败小学生的攻击次数中位数不得再为 1")
	_assert_true(_percentile(balanced_student, 0.50) <= 4, "均衡新手击败小学生的攻击次数中位数应不超过 4")
	_assert_true(_percentile(balanced_student, 0.90) <= 5, "均衡新手击败小学生的攻击次数 P90 应不超过 5")
	var training_target_attacks := _simulate_player_attacks(combat, "0b38ec96-d752-5083-a03c-aa0ac49a6dc1", TRIALS, 20260718)
	var training_target_median := _percentile(training_target_attacks, 0.50)
	var training_target_p90 := _percentile(training_target_attacks, 0.90)
	_assert_true(training_target_median >= 6 and training_target_median <= 8, "均衡新手击败 Qc. 的攻击次数中位数应为 6–8，当前为 %d" % training_target_median)
	_assert_true(training_target_p90 <= 10, "均衡新手击败 Qc. 的攻击次数 P90 应不超过 10，当前为 %d" % training_target_p90)

func _test_equal_build_mirror_rounds() -> void:
	var results: Dictionary = MIRROR_ROUND_BENCHMARK.run(root, [0, 20, 60, 100], TRIALS)
	for sect_key in results:
		var sect_results: Dictionary = results[sect_key]
		for level in sect_results:
			var sample: Dictionary = sect_results[level]
			var label := "%s Lv%d" % [sect_key, int(level)]
			_assert_true(int(sample.player_hp) == int(sample.enemy_hp), "%s 镜像双方体力必须完全一致" % label)
			_assert_true(int(sample.p10) >= 8 and int(sample.p10) <= 12, "%s 同属性同功法镜像战 P10 应为 8–12 回合，当前为 %d" % [label, sample.p10])
			_assert_true(int(sample.median) >= 8 and int(sample.median) <= 12, "%s 同属性同功法镜像战中位数应为 8–12 回合，当前为 %d" % [label, sample.median])
			_assert_true(int(sample.p90) >= 8 and int(sample.p90) <= 12, "%s 同属性同功法镜像战 P90 应为 8–12 回合，当前为 %d" % [label, sample.p90])

func _simulate_player_attacks(combat: Node, enemy_id: String, trials: int, random_seed: int) -> Array[int]:
	seed(random_seed)
	var counts: Array[int] = []
	for _trial in range(trials):
		var session: Dictionary = combat.create_session(enemy_id, true)
		var attack_count := 0
		while int(session.get("enemy_hp", 0)) > 0 and attack_count < 100:
			combat.player_attack(session, true, 1.0, 0.0, 0.0, "出手", false)
			attack_count += 1
		_assert_true(attack_count < 100, "%s 的模拟战斗未能在 100 次攻击内结束" % enemy_id)
		counts.append(attack_count)
	counts.sort()
	return counts

func _percentile(sorted_values: Array[int], ratio: float) -> int:
	if sorted_values.is_empty():
		return 0
	var index := clampi(int(ceil(float(sorted_values.size()) * ratio)) - 1, 0, sorted_values.size() - 1)
	return sorted_values[index]

func _set_player_profile(state: Node, attributes: Dictionary) -> void:
	state.delete_save()
	state.create_profile("数值测试", attributes)
	state.profile.vitals.cultivation = 0
	state.combat_state.injury = 0
	state.combat_state.mp = 0
	state.combat_state.hp = state.player_effective_hp_max()

func _test_role_formula_separation(state: Node) -> void:
	var striker := {"strength": 40, "agility": 25, "constitution": 20, "wisdom": 15}
	var skirmisher := {"strength": 25, "agility": 40, "constitution": 20, "wisdom": 15}
	var tank := {"strength": 20, "agility": 20, "constitution": 45, "wisdom": 15}
	var controller := {"strength": 15, "agility": 25, "constitution": 20, "wisdom": 40}
	_assert_true(state.attack_base(striker.strength) > state.attack_base(controller.strength), "striker 必须以更高基础攻击区别于 controller")
	_assert_true(state.base_hp_max(tank.constitution) > state.base_hp_max(striker.constitution), "tank 必须以更高体力区别于 striker")
	_assert_true(state.defense_base(tank.constitution) > state.defense_base(striker.constitution), "tank 必须以更高防御区别于 striker")
	_assert_true(state.combat_hit_rate(skirmisher, tank) > state.combat_hit_rate(striker, tank), "skirmisher 必须以更高命中区别于 striker")
	_assert_true(state.combat_crit_rate(controller) > state.combat_crit_rate(tank), "controller 的灵感应转化为高于 tank 的暴击率")

func _test_qc_reward(registry: Node) -> void:
	var training_target: Dictionary = registry.get_npc("0b38ec96-d752-5083-a03c-aa0ac49a6dc1")
	var reward: Dictionary = training_target.get("combatReward", {})
	_assert_true(str(training_target.get("combatRank", "")) == "novice" and str(training_target.get("combatRole", "")) == "balanced", "Qc 应是 novice/balanced 训练目标")
	_assert_true(int(reward.get("experience", -1)) == 60, "Qc 应奖励 60 经验")
	_assert_true(int(reward.get("potential", -1)) == 24, "Qc 应奖励 24 潜能")
	_assert_true(int(reward.get("money", -1)) == 5, "Qc 应只奖励 5 Token")

func _test_combat_reward_scaling(resolver: Node) -> void:
	var expected := {
		"noncombatant": {"experience": 2, "potential": 1, "money": 2},
		"novice": {"experience": 5, "potential": 2, "money": 4},
		"trained": {"experience": 7, "potential": 3, "money": 6},
		"veteran": {"experience": 9, "potential": 3, "money": 8},
		"elite": {"experience": 11, "potential": 4, "money": 9},
		"master": {"experience": 14, "potential": 5, "money": 11},
		"legendary": {"experience": 18, "potential": 6, "money": 15},
	}
	for rank in expected:
		var reward: Dictionary = resolver._combat_reward({"combatRank": rank, "skillLevels": {"2224675d-63f2-50e8-a2c6-064acd5c5623": 20}})
		_assert_true(reward == expected[rank], "%s 的普通战斗奖励必须锁定 %s/%s/%s 系数公式与阶位系数" % [rank, resolver.COMBAT_RULES.COMBAT_REWARD_EXP_COEF, resolver.COMBAT_RULES.COMBAT_REWARD_POT_COEF, resolver.COMBAT_RULES.COMBAT_REWARD_MONEY_COEF])
	var configured := {"combatRank": "legendary", "skillLevels": {"2224675d-63f2-50e8-a2c6-064acd5c5623": 200}, "combatReward": {"experience": 7, "potential": 3, "money": 2}}
	var configured_reward: Dictionary = resolver._combat_reward(configured)
	_assert_true(configured_reward == {"experience": 7, "potential": 3, "money": 2}, "显式 combatReward 必须精确覆盖评级与阶位公式")

func _test_victory_reward_exclusion(state: Node, registry: Node, npc_system: Node, quests: Node, resolver: Node) -> void:
	const ENEMY_ID := "__reward_exclusion_enemy"
	const GENERATOR_ID := "__reward_exclusion_bounty"
	npc_system.register_runtime(ENEMY_ID, {"displayName": "任务奖励互斥目标", "combatRank": "legendary", "combatRole": "balanced", "attributes": {"strength": 20, "agility": 20, "constitution": 20, "wisdom": 20}, "skillLevels": {"2224675d-63f2-50e8-a2c6-064acd5c5623": 100}, "combatReward": {"experience": 999, "potential": 999, "money": 999}})
	registry.quest_generators[GENERATOR_ID] = {"type": "bounty", "lines": {"ready": ""}}
	quests.reset_runtime()
	quests.active["generator:" + GENERATOR_ID] = {"generator_id": GENERATOR_ID, "kind": "bounty", "target": {"target_id": ENEMY_ID, "target_name": "任务奖励互斥目标"}, "ready": false}
	state.profile.vitals.experience = 0
	state.profile.vitals.potential = 0
	state.profile.vitals.money = 0
	var session := {"enemy_id": ENEMY_ID, "enemy": npc_system.build_instance(ENEMY_ID), "initial_player_hp": int(state.combat_state.hp), "player_in_battle_injury": 0}
	resolver.resolve_victory(session, true)
	_assert_true(bool(quests.active["generator:" + GENERATOR_ID].ready), "普通悬赏胜利必须进入待交付状态")
	_assert_true(int(state.profile.vitals.experience) == 0 and int(state.profile.vitals.potential) == 0 and int(state.profile.vitals.money) == 0, "任务文案即使为空，目标胜利也不得叠加显式或普通野战奖励")
	quests.reset_runtime()
	registry.quest_generators.erase(GENERATOR_ID)
	npc_system.unregister_runtime(ENEMY_ID)

func _test_noncombatant_quest_filter(registry: Node, quests: Node) -> void:
	var original_targets: Array[Dictionary] = registry.placed_npc_targets.duplicate(true)
	var combat_filter_fixture: Array[Dictionary] = [
		{"npc_id": "98138ebf-d4f4-515c-aea7-d95bf6155994", "map_id": "test", "map_name": "测试"},
		{"npc_id": "fface007-32fe-52f4-8e8c-19b497f364e8", "map_id": "test", "map_name": "测试"},
		{"npc_id": "0b38ec96-d752-5083-a03c-aa0ac49a6dc1", "map_id": "test", "map_name": "测试"},
	]
	registry.placed_npc_targets = combat_filter_fixture
	seed(20260718)
	var selected: Dictionary = quests._placed_npc_target([], true)
	_assert_true(str(selected.get("npc_id", "")) == "0b38ec96-d752-5083-a03c-aa0ac49a6dc1", "combat_only 目标池必须排除全部 noncombatant")
	registry.placed_npc_targets = original_targets

func _test_generator_endpoint_filtering(registry: Node, quests: Node) -> void:
	registry.quests["__reserved_endpoint"] = {"giverNpcId": "de6328e3-32c7-5560-b6c7-298a7fa02a03", "completionGiverId": "ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1"}
	registry.quest_generators["__endpoint_errand"] = {
		"type": "errand", "giverNpcId": "__errand_giver",
		"pool": {"npcs": ["ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1", "0b38ec96-d752-5083-a03c-aa0ac49a6dc1"]},
	}
	registry.quest_generators["__endpoint_bounty"] = {
		"type": "bounty", "giverNpcId": "__bounty_giver",
		"enemyPool": ["ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1"],
	}
	quests.reset_runtime()
	var errand: Dictionary = quests.offer_generator("__endpoint_errand")
	_assert_true(bool(errand.get("ok", false)) and str(quests.active.get("generator:__endpoint_errand", {}).get("target", {}).get("target_id", "")) == "0b38ec96-d752-5083-a03c-aa0ac49a6dc1", "普通送信任务必须排除其他任务的交付端点")
	quests.reset_runtime()
	var bounty: Dictionary = quests.offer_generator("__endpoint_bounty")
	_assert_true(bool(bounty.get("ok", false)) and str(quests.active.get("generator:__endpoint_bounty", {}).get("target", {}).get("target_id", "")) == "ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1", "普通悬赏允许把另一任务的交付人物选为击杀目标")
	quests.reset_runtime()
	registry.quests.erase("__reserved_endpoint")
	registry.quest_generators.erase("__endpoint_errand")
	registry.quest_generators.erase("__endpoint_bounty")

func _test_endgame_weapon_roles(state: Node, registry: Node) -> void:
	var bandage_effects: Dictionary = registry.get_item("173f2c35-09a0-58cd-9598-7477c0e698cd").get("effects", {})
	var antibiotic_effects: Dictionary = registry.get_item("21d76e51-0bb7-57e3-a924-02d50fe182d0").get("effects", {})
	_assert_true(int(bandage_effects.get("hp", 0)) == 35 and int(bandage_effects.get("injury", 0)) == 20, "创可贴应是低价、小恢复的战斗伤药")
	_assert_true(int(antibiotic_effects.get("hp", 0)) == 80 and int(antibiotic_effects.get("injury", 0)) == 100, "阿莫西林应以更高价格提供更强体力与伤势恢复")
	var mbp_bonus: Dictionary = registry.get_item("7e19e6c8-cec3-51b4-afd1-14a438cce8d3").get("equipmentBonus", {})
	var gpu_bonus: Dictionary = registry.get_item("28d397e9-d601-5cef-af26-35f8cc5eb4a2").get("equipmentBonus", {})
	_assert_true(int(mbp_bonus.get("attack", 0)) > int(gpu_bonus.get("attack", 0)) and int(mbp_bonus.get("defense", 0)) > 0, "MBP 应定位为高攻击、带防御的稳健综合武器")
	_assert_true(int(gpu_bonus.get("hit", 0)) > int(mbp_bonus.get("hit", 0)) and int(gpu_bonus.get("woundInflict", 0)) > 0, "5090D 应定位为高命中、持续致伤武器")
	_assert_true(int(gpu_bonus.get("crit", 0)) > int(mbp_bonus.get("crit", 0)), "5090D 的暴击定位应强于 MBP")
	var minimum_crit: float = float(state.combat_crit_rate({"agility": 0, "wisdom": 0}, 0.0))
	var maximum_crit: float = float(state.combat_crit_rate({"agility": 0, "wisdom": 0}, 1.0))
	var usable_crit_cap := int(floor((maximum_crit - minimum_crit) * 100.0))
	_assert_true(int(mbp_bonus.get("crit", 0)) <= usable_crit_cap, "MBP 暴击词条不得超过 %d%% 的系统上限" % usable_crit_cap)
	_assert_true(int(gpu_bonus.get("crit", 0)) <= usable_crit_cap, "5090D 暴击词条不得超过 %d%% 的系统上限" % usable_crit_cap)
