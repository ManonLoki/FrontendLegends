extends RefCounted
## 玩家与敌方共用的绝招执行器；统一连击、异常、削上限和巨伤规则。

const HIT_BONUS := {"multi": -0.05, "abnormal": 0.10, "reduceMax": 0.05, "hugeDamage": -0.15}
const MULTI_POWER := [0.55, 0.50]
const MULTI_HITS := [3, 5]
const ABNORMAL_POWER := [0.60, 0.70]
const ABNORMAL_CHANCE := [0.80, 0.95]
const REDUCE_MAX_POWER := [0.55, 0.65]
const REDUCE_MAX_RATIO := [0.08, 0.15]
const HUGE_DAMAGE_POWER := [2.5, 4.0]

var combat: Node

## 绑定战斗系统协调器。
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
	return _execute(session, ult, true)

## 把字典引用或数组索引解析为当前已解锁绝招。
func _resolve_player_ult(ult_ref: Variant) -> Dictionary:
	if ult_ref is Dictionary:
		return ult_ref
	var ults: Array = SkillSystem.unlocked_ults()
	var index := int(ult_ref)
	return ults[index] if index >= 0 and index < ults.size() else {}

## 按绝招类型选择连击或单次效果流程。
func _execute(session: Dictionary, ult: Dictionary, player_side: bool) -> Dictionary:
	var kind := str(ult.get("kind", "hugeDamage"))
	var tier_index := clampi(int(ult.get("tier", 1)) - 1, 0, 1)
	var label := "施展【%s】" % ult.get("name", "绝招" if player_side else "敌方绝招")
	var power_bonus := float(ult.get("inner_power", 0))
	if kind == "multi":
		return _execute_multi(session, ult, player_side, tier_index, label, power_bonus)
	return _execute_single(session, ult, player_side, kind, tier_index, label, power_bonus)

## 逐击独立判定连击绝招并汇总命中数与总伤害。
func _execute_multi(session: Dictionary, ult: Dictionary, player_side: bool, tier_index: int, label: String, power_bonus: float) -> Dictionary:
	var hit_count := int(MULTI_HITS[tier_index])
	var total_damage := 0
	var landed := 0
	for _index in hit_count:
		if _target_is_down(session, player_side):
			break
		var hit: Dictionary
		if player_side:
			hit = combat.player_attack(session, true, float(MULTI_POWER[tier_index]), float(HIT_BONUS.multi), power_bonus, label, true)
		else:
			hit = combat.enemy_attack(session, true, float(MULTI_POWER[tier_index]), float(HIT_BONUS.multi), power_bonus, label, true)
		if bool(hit.get("hit", false)):
			landed += 1
			total_damage += int(hit.damage)
	session.log.append("连击 %d 击（%d 中）：%s" % [hit_count, landed, "共伤 %d。" % total_damage if total_damage > 0 else "一击未中。"])
	return {"ok": true, "damage": total_damage, "landed": landed, "ult": ult}

## 执行单次绝招，并在命中后应用麻痹或削减体力上限。
func _execute_single(session: Dictionary, ult: Dictionary, player_side: bool, kind: String, tier_index: int, label: String, power_bonus: float) -> Dictionary:
	var scale := _power_scale(kind, tier_index)
	var hit: Dictionary
	if player_side:
		hit = combat.player_attack(session, true, scale, float(HIT_BONUS.get(kind, 0.0)), power_bonus, label, false)
	else:
		hit = combat.enemy_attack(session, true, scale, float(HIT_BONUS.get(kind, 0.0)), power_bonus, label, false)
	if not bool(hit.get("hit", false)):
		return {"ok": true, "damage": 0, "landed": 0, "ult": ult}
	if kind == "abnormal" and randf() < float(ABNORMAL_CHANCE[tier_index]):
		_apply_paralysis(session, player_side, tier_index)
	elif kind == "reduceMax":
		_reduce_target_max_hp(session, player_side, tier_index)
	return {"ok": true, "damage": int(hit.damage), "landed": 1, "ult": ult}

## 返回绝招类型和档位对应的伤害倍率。
func _power_scale(kind: String, tier_index: int) -> float:
	if kind == "abnormal":
		return float(ABNORMAL_POWER[tier_index])
	if kind == "reduceMax":
		return float(REDUCE_MAX_POWER[tier_index])
	return float(HUGE_DAMAGE_POWER[tier_index])

## 对目标施加一至两回合麻痹并写入战报。
func _apply_paralysis(session: Dictionary, player_side: bool, tier_index: int) -> void:
	var turns := 1 if tier_index == 0 else randi_range(1, 2)
	var target_side := "enemy" if player_side else "player"
	combat.add_status(session, target_side, "paralysis", turns)
	var target_name: String = str(session.enemy.get("displayName", "敌人")) if player_side else combat._player_name()
	session.log.append("%s麻痹，%d 回合无法出手。" % [target_name, turns])

## 按比例削减目标体力上限，并等比例同步当前体力。
func _reduce_target_max_hp(session: Dictionary, player_side: bool, tier_index: int) -> void:
	var ratio := float(REDUCE_MAX_RATIO[tier_index])
	if player_side:
		if int(session.enemy_hp) <= 0:
			return
		var old_max := maxi(1, int(session.enemy_max_hp))
		var reduced := maxi(1, int(floor(float(old_max) * ratio)))
		var new_max := maxi(1, old_max - reduced)
		session.enemy_hp = maxi(0 if bool(session.get("lethal", true)) else 1, mini(new_max, int(floor(float(session.enemy_hp) * float(new_max) / float(old_max)))))
		session.enemy_max_hp = new_max
		session.log.append("%s气机受创，体力上限 −%d。" % [session.enemy.get("displayName", "敌人"), reduced])
		return
	if int(GameState.combat_state.hp) <= 0:
		return
	var old_max := maxi(1, int(session.get("player_max_hp", combat._player_hp_max())))
	var reduced := maxi(1, int(floor(float(old_max) * ratio)))
	var new_max := maxi(1, old_max - reduced)
	GameState.combat_state.hp = maxi(0 if bool(session.get("lethal", true)) else 1, mini(new_max, int(floor(float(GameState.combat_state.hp) * float(new_max) / float(old_max)))))
	session.player_hp = GameState.combat_state.hp
	session.player_max_hp = new_max
	session.log.append("%s气机受创，体力上限 −%d。" % [combat._player_name(), reduced])

## 判断绝招目标是否已达到致命或切磋模式的最低体力。
func _target_is_down(session: Dictionary, player_side: bool) -> bool:
	var minimum := 0 if bool(session.get("lethal", true)) else 1
	return int(session.enemy_hp) <= minimum if player_side else int(GameState.combat_state.hp) <= minimum
