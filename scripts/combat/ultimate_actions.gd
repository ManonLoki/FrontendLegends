extends RefCounted
## 玩家与敌方共用的组合式绝招执行器。

const ABILITY_RULES := preload("res://scripts/combat/combat_ability_rules.gd")

var combat: Node

func _init(combat_system: Node) -> void:
	combat = combat_system

## 执行敌方绝招；精力不足时退回普通攻击。
func enemy_use(session: Dictionary, ult: Dictionary, turn_started := false) -> Dictionary:
	var turn_check: Dictionary = {"can_act": true, "message": ""} if turn_started else combat.start_turn(session, "enemy")
	if not turn_check.can_act:
		return {"ok": false, "skipped": true, "damage": 0, "message": turn_check.message}
	var cost := int(ult.get("mp_cost", 0))
	if int(session.enemy_mp) < cost:
		return combat.enemy_attack(session, true)
	session.enemy_mp = int(session.enemy_mp) - cost
	return _execute(session, ult, false)

## 选择并执行玩家绝招；先完成回合状态和精力校验。
func player_use(session: Dictionary, ult_ref: Variant = 0) -> Dictionary:
	var turn_check: Dictionary = combat.start_turn(session, "player")
	if not turn_check.can_act:
		return {"ok": false, "skipped": true, "message": turn_check.message}
	var ult := _resolve_player_ult(ult_ref)
	if ult.is_empty():
		return {"ok": false, "message": "你没有这门绝招。"}
	var cost := int(ult.get("mp_cost", 0))
	if int(GameState.combat_state.get("mp", 0)) < cost:
		return {"ok": false, "message": "精力不足，施展不出【%s】。" % ult.get("name", "绝招")}
	GameState.combat_state.mp = int(GameState.combat_state.mp) - cost
	session.player_mp = GameState.combat_state.mp
	return _execute(session, ult, true)

func _resolve_player_ult(ult_ref: Variant) -> Dictionary:
	if ult_ref is Dictionary:
		return ult_ref
	var ults: Array = SkillSystem.unlocked_ults()
	var index := int(ult_ref)
	return ults[index] if index >= 0 and index < ults.size() else {}

## 能力数组可组合；连击只改变攻击次数与逐击倍率，其余能力经标准攻击效果
## 进入权威结算管线，攻击无关的异常能力在攻击循环后统一施加。
func _execute(session: Dictionary, ult: Dictionary, player_side: bool) -> Dictionary:
	var abilities: Array = ult.get("abilities", [])
	var level := int(ult.get("inner_level", ABILITY_RULES.MIN_INNER_LEVEL))
	var label := "施展【%s】" % ult.get("name", "绝招" if player_side else "敌方绝招")
	var power_bonus: float = float(combat.rules.inner_power_attack_bonus(int(ult.get("inner_power", 0))))
	var is_multi := "multi" in abilities
	var hit_count := ABILITY_RULES.multi_hits(level) if is_multi else 1
	var hit_power := ABILITY_RULES.multi_power(level) if is_multi else 1.0
	var attack_effects := ABILITY_RULES.attack_effects(ult)
	var total_damage := 0
	var landed := 0
	var attempted := 0
	for _index in hit_count:
		if _target_is_down(session, player_side):
			break
		attempted += 1
		var hit: Dictionary
		if player_side:
			hit = combat.player_attack(session, true, hit_power, 0.0, power_bonus, label, is_multi, attack_effects)
		else:
			hit = combat.enemy_attack(session, true, hit_power, 0.0, power_bonus, label, is_multi, attack_effects)
		if bool(hit.get("hit", false)):
			landed += 1
			total_damage += int(hit.get("damage", 0))
	if "abnormal" in abilities:
		_apply_abnormal(session, player_side, level)
	if is_multi:
		session.log.append("连击 %d 击（%d 中）：%s" % [attempted, landed, "共伤 %d。" % total_damage if total_damage > 0 else "一击未中。"])
	return {"ok": true, "damage": total_damage, "landed": landed, "attempted": attempted, "ult": ult}

## 从三种异常中无重复抽取，并无视附带攻击是否命中而必定施加两回合。
func _apply_abnormal(session: Dictionary, player_side: bool, inner_level: int) -> void:
	var pool: Array[String] = ["paralysis", "weakness", "poison"]
	pool.shuffle()
	var target_side := "enemy" if player_side else "player"
	var names: Array[String] = []
	for index in ABILITY_RULES.abnormal_count(inner_level):
		combat.add_status(session, target_side, pool[index], 2)
		names.append(combat._status_name(pool[index]))
	var target_name: String = str(session.enemy.get("displayName", "敌人")) if player_side else combat._player_name()
	session.log.append("%s陷入%s，各持续2回合。" % [target_name, "、".join(names)])

func _target_is_down(session: Dictionary, player_side: bool) -> bool:
	var minimum := 0 if bool(session.get("lethal", true)) else 1
	return int(session.enemy_hp) <= minimum if player_side else int(GameState.combat_state.hp) <= minimum
