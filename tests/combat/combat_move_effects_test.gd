extends SceneTree

const TEST_ENEMY_ID := "ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1"
const TEST_SKILL_ID := "__ordinary_effect_skill__"
const BASIC_ARCH_ID := "dcebef7e-09b8-5a69-8e3d-159cb2b0c355"

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
	state.use_test_save_path("combat_move_effects")
	state.delete_save()
	state.create_profile("能力测试", {"strength": 25, "agility": 1, "constitution": 25, "wisdom": 25})

	for index in 100:
		var result: Dictionary = state.resolve_attack(100.0, {"agility": 1, "wisdom": 1}, {"agility": 1000}, 0.0, 0.0, 100.0, 0.0, 0.0, true)
		_assert_true(bool(result.hit), "必中攻击不得被基础命中判定避开，第%d次失败" % index)

	var parried := false
	for index in 100:
		var result: Dictionary = state.resolve_attack(100.0, {"agility": 1, "wisdom": 1}, {"strength": 1000}, 0.0, 0.0, 0.0, 1.0, 0.0, true)
		parried = parried or bool(result.parried)
	_assert_true(parried, "必中不得绕过招架阶段")

	var merged: Dictionary = combat.move_effects.merged({"guaranteedHit": true}, {"combat_effects": {"damageScale": 1.5, "drainHpRatio": 0.2}})
	_assert_true(bool(merged.guaranteedHit) and float(merged.damageScale) == 1.5 and float(merged.drainHpRatio) == 0.2, "绝招与普通招式效果必须合并")

	var registry = root.get_node("DataRegistry")
	var skill_system = root.get_node("SkillSystem")
	registry.skills[TEST_SKILL_ID] = {
		"name": "测试普通功法", "category": "sect", "sect": "测试门派", "theme": "code",
		"moves": [{
			"unlockLevel": 10, "name": "测试复合招式",
			"combatEffects": {"guaranteedHit": true, "damageScale": 1.5, "drainHpRatio": 0.2, "drainMpMaxRatio": 0.08},
		}],
	}
	state.profile.sect = "测试门派"
	state.profile.vitals.cultivation = 100
	var skill_state: Dictionary = skill_system.ensure_skills()
	skill_state.levels[BASIC_ARCH_ID] = 80
	skill_state.equipped_basic.arch = BASIC_ARCH_ID
	skill_state.levels[TEST_SKILL_ID] = 100
	skill_state.equipped_special.code = TEST_SKILL_ID
	var session: Dictionary = combat.create_session(TEST_ENEMY_ID, true)
	session.enemy.attributes.agility = 100000
	session.enemy_hp = 100000
	session.enemy_max_hp = 100000
	session.enemy_mp = session.enemy_mp_max
	state.combat_state.hp = maxi(1, int(session.player_max_hp) - 100)
	state.combat_state.mp = 0
	seed(37)
	var triggered := false
	for index in 200:
		var hp_before := int(state.combat_state.hp)
		var mp_before := int(state.combat_state.mp)
		var result: Dictionary = combat.player_attack(session, true)
		if str(session.log[-1]).contains("测试复合招式"):
			triggered = true
			_assert_true(bool(result.hit), "带必中效果的普通招式不得落空")
			_assert_true(int(state.combat_state.hp) > hp_before and int(state.combat_state.mp) > mp_before, "普通招式必须执行吸血和吸精效果")
			break
	_assert_true(triggered, "固定随机种子下必须触发测试普通招式")
	registry.skills.erase(TEST_SKILL_ID)

	state.delete_save()
	print("combat_move_effects_test: PASS" if failures.is_empty() else "combat_move_effects_test: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
