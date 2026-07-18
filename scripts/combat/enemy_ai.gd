extends RefCounted
## 敌方战斗决策服务；按优先级选择摸鱼、药品、绝招或普通攻击。

const ABILITY_RULES := preload("res://scripts/combat/combat_ability_rules.gd")
const ULT_USE_RATE := 0.35
const ITEM_USE_RATE := 0.55
const REST_USE_RATE := 0.20
const ITEM_HP_RATIO := 0.30
const REST_HP_RATIO := 0.35
const REST_MIN_MP := 8
const REST_HEAL_RATIO := 0.18
const REST_DEFAULT_CHARGES := 1
const CONSUMABLE_HEAL_RATIO := 0.25

var combat: Node

## 绑定战斗系统协调器。
func _init(combat_system: Node) -> void:
	combat = combat_system

## 执行一个敌方回合，并按资源与概率选择最高优先级行为。
func act(session: Dictionary) -> Dictionary:
	var turn_check: Dictionary = combat.start_turn(session, "enemy")
	if not turn_check.can_act:
		return {"hit": false, "damage": 0, "skipped": true, "message": turn_check.message}
	var hp := int(session.get("enemy_hp", 0))
	var hp_max := maxi(1, int(session.get("enemy_max_hp", hp)))
	var enemy_mp := int(session.get("enemy_mp", 0))
	var hp_ratio := float(hp) / float(hp_max)
	var ai: Dictionary = session.enemy.get("ai", {})
	var rest_result := _try_rest(session, ai, hp, hp_max, enemy_mp, hp_ratio)
	if not rest_result.is_empty():
		return rest_result
	var item_result := _try_item(session, ai, hp, hp_max, hp_ratio)
	if not item_result.is_empty():
		return item_result
	var affordable: Array = npc_ults(session.enemy).filter(func(ult): return enemy_mp >= int(ult.get("mp_cost", 0)))
	if not affordable.is_empty() and randf() < ULT_USE_RATE:
		affordable.sort_custom(func(left, right): return int(left.get("tier", 1)) > int(right.get("tier", 1)))
		return combat._enemy_use_ult(session, affordable[0], true)
	return combat.enemy_attack(session, true)

## 敌方濒危且精力足够时按配置概率摸鱼恢复体力；受次数上限约束，
## 单次封顶为最大体力的 18%（刻意低于玩家的 20%）。
func _try_rest(session: Dictionary, ai: Dictionary, hp: int, hp_max: int, enemy_mp: int, hp_ratio: float) -> Dictionary:
	var threshold := float(ai.get("restHpRatio", REST_HP_RATIO))
	var use_rate := float(ai.get("restUseRate", REST_USE_RATE))
	var charges := int(ai.get("restCharges", REST_DEFAULT_CHARGES))
	var used := int(session.get("enemy_rest_uses", 0))
	if hp_ratio >= threshold or enemy_mp < REST_MIN_MP or used >= charges or randf() >= use_rate:
		return {}
	var heal_cap := maxi(1, int(ceil(float(hp_max) * REST_HEAL_RATIO)))
	var healed := mini(enemy_mp, mini(hp_max - hp, heal_cap))
	if healed <= 0:
		return {}
	session.enemy_hp = hp + healed
	session.enemy_mp = enemy_mp - healed
	session.enemy_rest_uses = used + 1
	session.log.append("%s 摸鱼恢复 %d 体力" % [session.enemy.get("displayName", "敌人"), healed])
	return {"ok": true, "rest": true, "damage": 0, "message": "敌方摸鱼恢复 %d 体力" % healed}

## 敌方低体力且仍有虚拟药品次数时按配置概率服药。
func _try_item(session: Dictionary, ai: Dictionary, hp: int, hp_max: int, hp_ratio: float) -> Dictionary:
	var threshold := float(ai.get("itemHpRatio", ITEM_HP_RATIO))
	var use_rate := float(ai.get("itemUseRate", ITEM_USE_RATE))
	var charges := int(ai.get("consumableCharges", 0))
	if hp_ratio >= threshold or charges <= 0 or randf() >= use_rate:
		return {}
	var configured_heal := maxi(1, int(floor(float(hp_max) * CONSUMABLE_HEAL_RATIO)))
	var healed := int(ai.get("consumableHeal", configured_heal))
	session.enemy_hp = mini(hp_max, hp + healed)
	var updated_ai: Dictionary = ai.duplicate(true)
	updated_ai.consumableCharges = charges - 1
	session.enemy.ai = updated_ai
	session.log.append("%s 服下一颗丹药，体力 +%d" % [session.enemy.get("displayName", "敌人"), healed])
	return {"ok": true, "item": true, "damage": 0, "message": "敌方服药回复 %d 体力" % healed}

## 按 NPC 已装备架构功法等级构建两档绝招列表；构造逻辑与玩家侧共用。
func npc_ults(npc: Dictionary) -> Array:
	var result: Array = []
	var skill_levels: Dictionary = npc.get("skillLevels", {})
	for skill_id in npc.get("equippedSkillIds", []):
		var definition: Dictionary = DataRegistry.get_skill(str(skill_id))
		if str(definition.get("theme", "")) != "arch" or definition.get("ult", {}).is_empty():
			continue
		var level := int(skill_levels.get(str(skill_id), 0))
		var inner_power := int(skill_levels.get("dcebef7e-09b8-5a69-8e3d-159cb2b0c355", 0)) + level * 2
		var config: Dictionary = definition.get("ult", {})
		if level >= ABILITY_RULES.ULT_TIER1_ARCH_LEVEL:
			result.append(ABILITY_RULES.build_ult(config, 1, inner_power, level))
		if level >= ABILITY_RULES.ULT_TIER2_ARCH_LEVEL:
			result.append(ABILITY_RULES.build_ult(config, 2, inner_power, level))
	return result
