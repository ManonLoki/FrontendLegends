extends RefCounted
## 敌方战斗决策服务；combatRole 只改变可追溯的行动偏好，不直接修改攻防数值。

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

## 六类原型通过行动概率形成差异：输出型更常加力，控制型优先绝招，坦克更重恢复。
## 字段仍可由人物 ai 配置的同名驼峰字段覆盖。
const ROLE_BEHAVIORS := {
	"striker": {"ult_rate": 0.32, "force_rate": 0.80, "rest_rate": 0.08, "item_rate": 0.35},
	"skirmisher": {"ult_rate": 0.48, "force_rate": 0.35, "rest_rate": 0.12, "item_rate": 0.45},
	"tank": {"ult_rate": 0.22, "force_rate": 0.25, "rest_rate": 0.65, "item_rate": 0.60},
	"counter": {"ult_rate": 0.28, "force_rate": 0.55, "rest_rate": 0.30, "item_rate": 0.50},
	"controller": {"ult_rate": 0.72, "force_rate": 0.20, "rest_rate": 0.22, "item_rate": 0.55},
	"balanced": {"ult_rate": 0.38, "force_rate": 0.45, "rest_rate": 0.25, "item_rate": 0.55},
	"noncombatant": {"ult_rate": 0.0, "force_rate": 0.05, "rest_rate": 0.35, "item_rate": 0.70},
}

var combat: Node
var decision_rng := RandomNumberGenerator.new()

func _init(combat_system: Node) -> void:
	combat = combat_system
	decision_rng.randomize()

## 预先生成下一回合意图并写入战报，让玩家能用现有攻击、绝招、恢复和逃跑作出判断。
func prepare_intent(session: Dictionary, decision_roll := -1.0) -> Dictionary:
	var intent := choose_intent(session, decision_roll)
	session.enemy_intent = intent
	if not intent.is_empty():
		session.log.append("【预判】%s" % str(intent.get("label", "敌方正在观察局势。")))
	return intent

## 纯决策入口；测试可传固定 roll，实战使用随机数。所有数值偏好均来自角色或 ai 显式配置。
func choose_intent(session: Dictionary, decision_roll := -1.0) -> Dictionary:
	var enemy: Dictionary = session.get("enemy", {})
	var enemy_name := str(enemy.get("displayName", "对手"))
	var role := str(enemy.get("combatRole", "balanced"))
	var behavior: Dictionary = ROLE_BEHAVIORS.get(role, ROLE_BEHAVIORS.balanced).duplicate(true)
	var ai: Dictionary = enemy.get("ai", {})
	behavior.ult_rate = clampf(float(ai.get("ultUseRate", behavior.ult_rate)), 0.0, 1.0)
	behavior.force_rate = clampf(float(ai.get("forceUseRate", behavior.force_rate)), 0.0, 1.0)
	behavior.rest_rate = clampf(float(ai.get("restUseRate", behavior.rest_rate)), 0.0, 1.0)
	behavior.item_rate = clampf(float(ai.get("itemUseRate", behavior.item_rate)), 0.0, 1.0)
	var roll := decision_rng.randf() if decision_roll < 0.0 else clampf(decision_roll, 0.0, 0.999999)
	var secondary_roll := fmod(roll * 1.61803398875 + 0.173, 1.0)
	if role == "tank":
		if _can_rest(session, ai) and roll < float(behavior.rest_rate):
			return _intent("rest", role, false, {}, enemy_name)
		if _can_item(session, ai) and secondary_roll < float(behavior.item_rate):
			return _intent("item", role, false, {}, enemy_name)
	else:
		if _can_item(session, ai) and roll < float(behavior.item_rate):
			return _intent("item", role, false, {}, enemy_name)
		if _can_rest(session, ai) and secondary_roll < float(behavior.rest_rate):
			return _intent("rest", role, false, {}, enemy_name)
	var affordable: Array = npc_ults(enemy).filter(func(ult): return int(session.get("enemy_mp", 0)) >= int(ult.get("mp_cost", 0)))
	if not affordable.is_empty() and roll < float(behavior.ult_rate):
		var chosen := _select_ult(affordable, role)
		return _intent("ultimate", role, false, chosen, enemy_name)
	return _intent("attack", role, secondary_roll < float(behavior.force_rate), {}, enemy_name)

## 消费之前公开的意图；行动完成后再公布下一意图，形成一回合可反应窗口。
func act(session: Dictionary) -> Dictionary:
	var turn_check: Dictionary = combat.start_turn(session, "enemy")
	if not turn_check.can_act:
		return _finish_action(session, {"hit": false, "damage": 0, "skipped": true, "message": turn_check.message})
	var intent: Dictionary = session.get("enemy_intent", {})
	if intent.is_empty():
		intent = choose_intent(session)
	session.enemy_current_intent = intent
	var result: Dictionary
	match str(intent.get("action", "attack")):
		"rest":
			result = _perform_rest(session) if _can_rest(session, session.enemy.get("ai", {})) else combat.enemy_attack(session, true)
		"item":
			result = _perform_item(session) if _can_item(session, session.enemy.get("ai", {})) else combat.enemy_attack(session, true)
		"ultimate":
			var ult: Dictionary = intent.get("ult", {})
			result = combat._enemy_use_ult(session, ult, true) if int(session.get("enemy_mp", 0)) >= int(ult.get("mp_cost", 0)) else combat.enemy_attack(session, true)
		_:
			result = combat.enemy_attack(session, true)
	return _finish_action(session, result)

func _finish_action(session: Dictionary, result: Dictionary) -> Dictionary:
	session.erase("enemy_current_intent")
	session.erase("enemy_intent")
	var minimum := 0 if bool(session.get("lethal", true)) else 1
	if int(GameState.combat_state.get("hp", 0)) > minimum and int(session.get("enemy_hp", 0)) > minimum:
		prepare_intent(session)
	return result

func _intent(action: String, role: String, use_force: bool, ult: Dictionary = {}, enemy_name := "对手") -> Dictionary:
	var label := "%s准备稳健进招。" % enemy_name
	match action:
		"rest": label = "%s气息转缓，准备抽身摸鱼恢复体力。" % enemy_name
		"item": label = "%s伸手探向行囊，准备服药。" % enemy_name
		"ultimate": label = "%s开始聚气，准备施展【%s】。" % [enemy_name, ult.get("name", "绝招")]
		"attack":
			label = "%s压低重心，准备加力猛攻。" % enemy_name if use_force else "%s盯住破绽，准备普通进招。" % enemy_name
	return {"action": action, "role": role, "use_force": use_force, "ult": ult, "label": label}

func _select_ult(affordable: Array, role: String) -> Dictionary:
	affordable.sort_custom(func(left, right): return int(left.get("tier", 1)) > int(right.get("tier", 1)))
	if role in ["tank", "counter", "balanced"]:
		return affordable[affordable.size() - 1]
	return affordable[0]

func _hp_ratio(session: Dictionary) -> float:
	return float(session.get("enemy_hp", 0)) / float(maxi(1, int(session.get("enemy_max_hp", 1))))

func _can_rest(session: Dictionary, ai: Dictionary) -> bool:
	var charges := int(ai.get("restCharges", REST_DEFAULT_CHARGES))
	return _hp_ratio(session) < float(ai.get("restHpRatio", REST_HP_RATIO)) and int(session.get("enemy_mp", 0)) >= REST_MIN_MP and int(session.get("enemy_rest_uses", 0)) < charges

func _can_item(session: Dictionary, ai: Dictionary) -> bool:
	return _hp_ratio(session) < float(ai.get("itemHpRatio", ITEM_HP_RATIO)) and int(ai.get("consumableCharges", 0)) > 0

## 保留概率包装入口供规则测试；实际意图消费不再二次掷骰。
func _try_rest(session: Dictionary, ai: Dictionary, _hp: int, _hp_max: int, _enemy_mp: int, _hp_ratio_value: float) -> Dictionary:
	if not _can_rest(session, ai) or decision_rng.randf() >= clampf(float(ai.get("restUseRate", REST_USE_RATE)), 0.0, 1.0):
		return {}
	return _perform_rest(session)

func _perform_rest(session: Dictionary) -> Dictionary:
	var hp := int(session.get("enemy_hp", 0))
	var hp_max := maxi(1, int(session.get("enemy_max_hp", hp)))
	var enemy_mp := int(session.get("enemy_mp", 0))
	var healed := mini(enemy_mp, mini(hp_max - hp, maxi(1, int(ceil(float(hp_max) * REST_HEAL_RATIO)))))
	if healed <= 0:
		return {}
	session.enemy_hp = hp + healed
	session.enemy_mp = enemy_mp - healed
	session.enemy_rest_uses = int(session.get("enemy_rest_uses", 0)) + 1
	session.log.append("%s 摸鱼恢复 %d 体力" % [session.enemy.get("displayName", "敌人"), healed])
	return {"ok": true, "rest": true, "damage": 0, "message": "敌方摸鱼恢复 %d 体力" % healed}

func _try_item(session: Dictionary, ai: Dictionary, _hp: int, _hp_max: int, _hp_ratio_value: float) -> Dictionary:
	if not _can_item(session, ai) or decision_rng.randf() >= clampf(float(ai.get("itemUseRate", ITEM_USE_RATE)), 0.0, 1.0):
		return {}
	return _perform_item(session)

func _perform_item(session: Dictionary) -> Dictionary:
	var ai: Dictionary = session.enemy.get("ai", {})
	var hp := int(session.get("enemy_hp", 0))
	var hp_max := maxi(1, int(session.get("enemy_max_hp", hp)))
	var healed := int(ai.get("consumableHeal", maxi(1, int(floor(float(hp_max) * CONSUMABLE_HEAL_RATIO)))))
	session.enemy_hp = mini(hp_max, hp + healed)
	var updated_ai := ai.duplicate(true)
	updated_ai.consumableCharges = int(ai.get("consumableCharges", 0)) - 1
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
		var inner_power: int = int(combat.rules.npc_inner_power(npc))
		var config: Dictionary = definition.get("ult", {})
		if level >= ABILITY_RULES.ULT_TIER1_ARCH_LEVEL:
			result.append(ABILITY_RULES.build_ult(config, 1, inner_power, level))
		if level >= ABILITY_RULES.ULT_TIER2_ARCH_LEVEL:
			result.append(ABILITY_RULES.build_ult(config, 2, inner_power, level))
	return result
