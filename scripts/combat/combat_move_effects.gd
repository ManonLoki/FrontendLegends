extends RefCounted
## 普通招式附加伤害/状态与命中后资源吸取服务。

var combat: Node

func _init(combat_system: Node) -> void:
	combat = combat_system

func merged(external: Dictionary, move: Dictionary) -> Dictionary:
	var result := external.duplicate(true)
	result.merge(move.get("combat_effects", {}), true)
	return result

func apply_move_bonus(session: Dictionary, side: String, move: Dictionary, result: Dictionary) -> String:
	if move.is_empty(): return ""
	var status: Dictionary = combat._roll_attack_move_status(move)
	var extra := int(floor(8.0 + maxi(0, int(move.get("level", 0)) - int(move.get("unlock", 0))) * 0.6))
	if not status.is_empty(): extra = int(floor(float(extra) * 0.5))
	result.damage += extra
	var tag := "（招式+%d）" % extra
	if not status.is_empty():
		var turns := randi_range(1, 3)
		var target := "enemy" if side == "player" else "player"
		combat.add_status(session, target, str(status.kind), turns)
		tag += "（施加%s%d回合）" % [combat._status_name(str(status.kind)), turns]
	return tag

func apply_drain(session: Dictionary, player_side: bool, actual_damage: int, effects: Dictionary) -> String:
	var tags := ""
	var hp_ratio := maxf(0.0, float(effects.get("drainHpRatio", 0.0)))
	if hp_ratio > 0.0 and actual_damage > 0:
		var wanted := int(floor(float(actual_damage) * hp_ratio))
		var healed := _heal_attacker(session, player_side, wanted)
		if healed > 0: tags += "（吸血+%d）" % healed
	var mp_ratio := maxf(0.0, float(effects.get("drainMpMaxRatio", 0.0)))
	if mp_ratio > 0.0:
		var drained := _transfer_mp(session, player_side, mp_ratio)
		if drained > 0: tags += "（吸精+%d）" % drained
	return tags

func _heal_attacker(session: Dictionary, player_side: bool, wanted: int) -> int:
	if wanted <= 0: return 0
	if player_side:
		var current := int(GameState.combat_state.hp)
		var maximum := maxi(1, int(session.get("player_max_hp", combat._player_hp_max())))
		var healed := mini(wanted, maxi(0, maximum - current))
		GameState.combat_state.hp = clampi(current + healed, 0, maximum)
		session.player_hp = GameState.combat_state.hp
		return healed
	var enemy_current := int(session.get("enemy_hp", 0))
	var enemy_maximum := maxi(1, int(session.get("enemy_max_hp", enemy_current)))
	var enemy_healed := mini(wanted, maxi(0, enemy_maximum - enemy_current))
	session.enemy_hp = clampi(enemy_current + enemy_healed, 0, enemy_maximum)
	return enemy_healed

func _transfer_mp(session: Dictionary, player_side: bool, ratio: float) -> int:
	if player_side:
		var target_max := maxi(0, int(session.get("enemy_mp_max", 0)))
		var target_current := maxi(0, int(session.get("enemy_mp", 0)))
		var attacker_max := maxi(0, GameState.player_mp_max())
		var attacker_current := maxi(0, int(GameState.combat_state.mp))
		var amount := mini(int(floor(float(target_max) * ratio)), mini(target_current, maxi(0, attacker_max - attacker_current)))
		session.enemy_mp = target_current - amount
		GameState.combat_state.mp = attacker_current + amount
		session.player_mp = GameState.combat_state.mp
		return amount
	var player_max := maxi(0, GameState.player_mp_max())
	var player_current := maxi(0, int(GameState.combat_state.mp))
	var enemy_max := maxi(0, int(session.get("enemy_mp_max", 0)))
	var enemy_current := maxi(0, int(session.get("enemy_mp", 0)))
	var enemy_amount := mini(int(floor(float(player_max) * ratio)), mini(player_current, maxi(0, enemy_max - enemy_current)))
	GameState.combat_state.mp = player_current - enemy_amount
	session.player_mp = GameState.combat_state.mp
	session.enemy_mp = enemy_current + enemy_amount
	return enemy_amount
