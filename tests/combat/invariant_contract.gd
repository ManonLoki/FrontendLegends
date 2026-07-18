extends RefCounted
## 战斗基础逻辑契约：调参可以改变幅度，但不能让四属性、已装备功法、装备或阶位职责失效。

const TEST_SKILL_ID := "__combat_invariant_skill__"
const TEST_ITEM_ID := "__combat_invariant_item__"

static func run(root: Node, assert_true: Callable) -> void:
	var state = root.get_node("GameState")
	var registry = root.get_node("DataRegistry")
	var combat = root.get_node("CombatSystem")
	_test_four_attributes(state, assert_true)
	_test_equipped_skill(registry, combat, assert_true)
	_test_equipment(registry, combat, assert_true)
	_test_rank_and_role_scope(combat, assert_true)

static func _test_four_attributes(state: Node, assert_true: Callable) -> void:
	var low := {"strength": 10.0, "agility": 10.0, "constitution": 10.0, "wisdom": 10.0}
	var high := {"strength": 40.0, "agility": 40.0, "constitution": 40.0, "wisdom": 40.0}
	assert_true.call(state.attack_base(high.strength) > state.attack_base(low.strength), "编码必须提高基础攻击")
	assert_true.call(state.combat_parry_rate(high) > state.combat_parry_rate(low), "编码必须提高基础招架")
	assert_true.call(state.combat_hit_rate(high, low) > state.combat_hit_rate(low, high), "思维必须影响命中与回避关系")
	assert_true.call(state.defense_base(high.constitution) > state.defense_base(low.constitution), "架构必须提高基础防御")
	assert_true.call(state.base_hp_max(high.constitution) > state.base_hp_max(low.constitution), "架构必须提高基础体力")
	assert_true.call(state.combat_crit_rate(high) > state.combat_crit_rate(low), "灵感必须提高暴击率")

static func _test_equipped_skill(registry: Node, combat: Node, assert_true: Callable) -> void:
	registry.skills[TEST_SKILL_ID] = {
		"combat": {
			"atkPerLv": 1.0, "defPerLv": 2.0, "hitPerLv": 0.01,
			"dodgePerLv": 0.02, "parryPerLv": 0.03, "mpMaxPerLv": 4,
		},
	}
	var unequipped := {"skillLevels": {TEST_SKILL_ID: 3}, "equippedSkillIds": []}
	var equipped := {"skillLevels": {TEST_SKILL_ID: 3}, "equippedSkillIds": [TEST_SKILL_ID]}
	var none: Dictionary = combat.rules.npc_combat_bonus(unequipped)
	var bonus: Dictionary = combat.rules.npc_combat_bonus(equipped)
	assert_true.call(float(none.attack) == 0.0, "未装备功法不得进入常规战斗聚合")
	assert_true.call(float(bonus.attack) == 3.0 and float(bonus.defense) == 6.0, "已装备功法的攻防必须按等级生效")
	assert_true.call(is_equal_approx(float(bonus.hit), 0.03) and is_equal_approx(float(bonus.dodge), 0.06) and is_equal_approx(float(bonus.parry), 0.09), "已装备功法的命中、闪避与招架必须生效")
	assert_true.call(int(bonus.mp_max) == 12, "已装备功法的精力上限加成必须生效")
	registry.skills.erase(TEST_SKILL_ID)

static func _test_equipment(registry: Node, combat: Node, assert_true: Callable) -> void:
	registry.items[TEST_ITEM_ID] = {
		"attributes": {"strength": 1, "agility": 2, "constitution": 3, "wisdom": 4},
		"equipmentBonus": {"attack": 5, "defense": 6, "hit": 7, "dodge": 8, "crit": 9, "parry": 10, "woundInflict": 11},
	}
	var npc := {"attributes": {"strength": 10, "agility": 10, "constitution": 10, "wisdom": 10}, "equipment": [TEST_ITEM_ID]}
	var attributes: Dictionary = combat.rules.npc_combat_attributes(npc)
	var bonus: Dictionary = combat.rules.npc_equipment_bonus(npc)
	assert_true.call(attributes == {"strength": 11.0, "agility": 12.0, "constitution": 13.0, "wisdom": 14.0}, "装备四属性必须进入战斗快照")
	for key in ["attack", "defense", "hit", "dodge", "crit", "parry", "woundInflict"]:
		assert_true.call(int(bonus.get(key, 0)) > 0, "装备显式修正 %s 必须进入战斗聚合" % key)
	registry.items.erase(TEST_ITEM_ID)

static func _test_rank_and_role_scope(combat: Node, assert_true: Callable) -> void:
	var base := {"attributes": {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25}, "skillLevels": {}, "equippedSkillIds": [], "equipment": []}
	var novice: Dictionary = base.duplicate(true)
	var elite: Dictionary = base.duplicate(true)
	novice.combatRank = "novice"
	novice.combatRole = "tank"
	elite.combatRank = "elite"
	elite.combatRole = "striker"
	assert_true.call(is_equal_approx(combat.rules.enemy_attack_power(novice), combat.rules.enemy_attack_power(elite)), "combatRank 与 combatRole 不得暗中修改攻击")
	assert_true.call(combat.rules.npc_hp_max(elite, elite.attributes, 0) > combat.rules.npc_hp_max(novice, novice.attributes, 0), "combatRank 必须只按显式职责缩放 NPC 体力")
