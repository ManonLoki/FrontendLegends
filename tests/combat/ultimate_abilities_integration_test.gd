extends SceneTree

const RULES := preload("res://scripts/combat/combat_ability_rules.gd")
const TEST_ENEMY_ID := "ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1"

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
	state.use_test_save_path("ultimate_abilities")
	state.delete_save()
	state.create_profile("绝招测试", {"strength": 25, "agility": 25, "constitution": 100, "wisdom": 25})
	state.profile.vitals.cultivation = 1000
	state.combat_state.mp = state.player_mp_max()
	state.combat_state.hp = state.player_effective_hp_max()
	_assert_true(RULES.multi_hits(30) == 3 and RULES.multi_hits(100) == 6, "连击成长边界必须为3至6击")

	var abnormal_session: Dictionary = combat.create_session(TEST_ENEMY_ID, true)
	var abnormal := {"name": "测试异常", "abilities": ["abnormal"], "inner_level": 80, "inner_power": 0, "mp_cost": 0, "tier": 2}
	abnormal_session.enemy.attributes.agility = 100000
	seed(101)
	combat.use_ult(abnormal_session, abnormal)
	_assert_true(abnormal_session.enemy_status.size() == 2, "80级异常绝招必须附加两种不同状态，即使攻击落空")
	for turns in abnormal_session.enemy_status.values():
		_assert_true(int(turns) == 2, "必定异常必须持续两回合")

	var hp_drain_session: Dictionary = combat.create_session(TEST_ENEMY_ID, true)
	state.combat_state.hp = maxi(1, int(hp_drain_session.player_max_hp) - 100)
	var hp_before := int(state.combat_state.hp)
	var hp_drain := {"name": "测试吸血", "abilities": ["guaranteed_hit", "drain_hp"], "inner_level": 100, "inner_power": 0, "mp_cost": 0, "tier": 1}
	seed(7)
	var hp_result: Dictionary = combat.use_ult(hp_drain_session, hp_drain)
	var healed := int(state.combat_state.hp) - hp_before
	_assert_true(healed >= 0 and healed <= int(floor(float(hp_result.damage) * 0.35)), "吸血必须以实际伤害为基数且不得超过35%")

	var mp_drain_session: Dictionary = combat.create_session(TEST_ENEMY_ID, true)
	mp_drain_session.enemy_mp = mp_drain_session.enemy_mp_max
	state.combat_state.mp = 0
	mp_drain_session.player_mp = 0
	var mp_drain := {"name": "测试吸精", "abilities": ["guaranteed_hit", "drain_mp"], "inner_level": 100, "inner_power": 0, "mp_cost": 0, "tier": 2}
	seed(9)
	var enemy_mp_before := int(mp_drain_session.enemy_mp)
	combat.use_ult(mp_drain_session, mp_drain)
	var transferred := enemy_mp_before - int(mp_drain_session.enemy_mp)
	_assert_true(transferred <= int(floor(float(mp_drain_session.enemy_mp_max) * 0.15)) and transferred == int(state.combat_state.mp) and transferred == int(mp_drain_session.player_mp), "吸精必须按目标最大精力转移、守恒并同步会话")

	var guaranteed := {"name": "测试必中", "abilities": ["guaranteed_hit"], "inner_level": 100, "inner_power": 0, "mp_cost": 0, "tier": 2}
	for index in 50:
		var guaranteed_session: Dictionary = combat.create_session(TEST_ENEMY_ID, true)
		guaranteed_session.enemy.attributes.agility = 100000
		var result: Dictionary = combat.use_ult(guaranteed_session, guaranteed)
		_assert_true(int(result.landed) == 1, "必中绝招第%d次不应落空" % index)

	var multi_session: Dictionary = combat.create_session(TEST_ENEMY_ID, true)
	multi_session.enemy_hp = 100000
	multi_session.enemy_max_hp = 100000
	var multi := {"name": "测试连击", "abilities": ["multi", "guaranteed_hit"], "inner_level": 100, "inner_power": 0, "mp_cost": 0, "tier": 2}
	seed(19)
	var multi_result: Dictionary = combat.use_ult(multi_session, multi)
	_assert_true(int(multi_result.attempted) == 6, "100级连击必须尝试6击")
	multi_session.enemy_hp = 1
	multi_session.enemy_max_hp = 1
	seed(23)
	var stopped_result: Dictionary = combat.use_ult(multi_session, multi)
	_assert_true(int(stopped_result.attempted) == 1, "目标倒下后必须停止后续连击")

	state.delete_save()
	print("ultimate_abilities_integration_test: PASS" if failures.is_empty() else "ultimate_abilities_integration_test: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
