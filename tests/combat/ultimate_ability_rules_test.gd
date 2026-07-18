extends SceneTree

const RULES := preload("res://scripts/combat/combat_ability_rules.gd")
const LOADOUT := preload("res://scripts/skills/skill_loadout.gd")

var failures: Array[String] = []

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_assert_true([RULES.multi_hits(30), RULES.multi_hits(50), RULES.multi_hits(75), RULES.multi_hits(100)] == [3, 4, 5, 6], "连击次数必须按30/50/75/100级成长为3/4/5/6")
	_assert_true([RULES.multi_power(30), RULES.multi_power(50), RULES.multi_power(75), RULES.multi_power(100)] == [0.65, 0.60, 0.55, 0.50], "连击逐击倍率必须随次数调整")
	_assert_true(RULES.abnormal_count(30) == 1 and RULES.abnormal_count(79) == 1 and RULES.abnormal_count(80) == 2 and RULES.abnormal_count(100) == 2, "异常数量必须在80级从1种增长到2种")
	_assert_true(is_equal_approx(RULES.guaranteed_damage_scale(30), 1.5) and is_equal_approx(RULES.guaranteed_damage_scale(100), 2.0), "必中伤害必须从1.5倍成长到2倍")
	_assert_true(is_equal_approx(RULES.drain_hp_ratio(30), 0.20) and is_equal_approx(RULES.drain_hp_ratio(100), 0.35), "吸血比例必须从20%成长到35%")
	_assert_true(is_equal_approx(RULES.drain_mp_ratio(30), 0.08) and is_equal_approx(RULES.drain_mp_ratio(100), 0.15), "吸精比例必须从8%成长到15%")
	var guaranteed := RULES.attack_effects({"abilities": ["guaranteed_hit"], "inner_level": 65})
	_assert_true(bool(guaranteed.guaranteedHit) and is_equal_approx(float(guaranteed.damageScale), 1.75), "必中绝招必须生成标准攻击效果")
	var drains := RULES.attack_effects({"abilities": ["drain_hp", "drain_mp"], "inner_level": 100})
	_assert_true(is_equal_approx(float(drains.drainHpRatio), 0.35) and is_equal_approx(float(drains.drainMpMaxRatio), 0.15), "吸取能力必须生成标准攻击效果")
	var config := {
		"key": "test", "names": ["一档", "二档"],
		"abilitySets": [["drain_hp"], ["drain_mp"]], "mpCosts": [35, 60],
	}
	var tier_one := LOADOUT.build_ult(config, 1, 190, 80)
	var tier_two := LOADOUT.build_ult(config, 2, 190, 80)
	_assert_true(tier_one.abilities == ["drain_hp"] and tier_two.abilities == ["drain_mp"], "两档绝招必须携带各自能力")
	_assert_true(int(tier_one.inner_level) == 80 and int(tier_one.inner_power) == 190, "标准绝招必须区分特性等级与攻击内功")
	_assert_true(int(tier_one.mp_cost) == 35 and int(tier_two.mp_cost) == 60, "精力消耗必须由绝招数据提供")
	_assert_true(tier_one.kind == "reduceMax" and tier_two.kind == "reduceMax", "能力数据必须临时映射到旧执行器类型")
	print("ultimate_ability_rules_test: PASS" if failures.is_empty() else "ultimate_ability_rules_test: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
