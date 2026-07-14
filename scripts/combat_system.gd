extends Node

const CRIT_BASE := 0.03
const CRIT_PER_CONSTITUTION := 0.0035
const FLEE_BASE := 0.40
const FLEE_PER_AGILITY := 0.03

func create_session(enemy_id: String) -> Dictionary:
	var enemy: Dictionary = NpcSystem.build_instance(enemy_id)
	var player_attributes: Dictionary = GameState.profile.get("attributes", {})
	var enemy_attributes: Dictionary = enemy.get("attributes", {})
	return {
		"enemy_id": enemy_id,
		"enemy": enemy,
		"player_hp": int(GameState.combat_state.get("hp", 1)),
		"player_max_hp": _hp_max(player_attributes),
		"initial_player_hp": int(GameState.combat_state.get("hp", 1)),
		"player_mp": int(GameState.combat_state.get("mp", 0)),
		"enemy_hp": _hp_max(enemy_attributes),
		"enemy_max_hp": _hp_max(enemy_attributes),
		"enemy_mp": int(enemy.get("mp", 0)),
		"enemy_mp_max": int(enemy.get("mp", 0)),
		"player_status": {},
		"enemy_status": {},
		"player_reached_zero": false,
		"player_near_death": false,
		"turn": "player" if _initiative(player_attributes, enemy_attributes) else "enemy",
		"log": []
	}

func player_attack(session: Dictionary) -> Dictionary:
	var turn_check := start_turn(session, "player")
	if not turn_check.can_act:
		return {"hit": false, "parried": false, "crit": false, "damage": 0, "skipped": true, "message": turn_check.message}
	var enemy_attributes: Dictionary = session.enemy.get("attributes", {})
	var bonuses: Dictionary = SkillSystem.combat_bonus()
	var attack_moves: Array = SkillSystem.unlocked_moves().filter(func(move): return move.get("kind", "") == "attack")
	var attack_move: Dictionary = attack_moves[randi() % attack_moves.size()] if not attack_moves.is_empty() and randf() < minf(0.55, 0.25 + attack_moves.size() * 0.04) else {}
	var move_hit_bonus := 0.12 if not attack_move.is_empty() else 0.0
	var enemy_equipment := _npc_equipment_bonus(session.enemy)
	var result: Dictionary = GameState.resolve_attack(_player_attack_power(), GameState.profile.get("attributes", {}), enemy_attributes, float(enemy_attributes.get("constitution", 0)) * 2.0 + float(enemy_equipment.get("defense", 0)), (float(bonuses.get("hit", 0.0)) + float(InventorySystem.equipment_bonus().get("hit", 0))) * 0.01 + move_hit_bonus, float(enemy_equipment.get("dodge", 0)) * 0.01, 0.0, float(InventorySystem.equipment_bonus().get("crit", 0)) * 0.01)
	if result.hit:
		var enemy_parry := _npc_move(session.enemy, "parry")
		if not enemy_parry.is_empty():
			result.damage = int(floor(float(result.damage) * (1.0 - minf(0.35, 0.15 + maxi(0, int(enemy_parry.get("level", 0)) - int(enemy_parry.get("unlock", 0))) * 0.01))))
		if int(session.get("enemy_status", {}).get("weakness", 0)) > 0:
			result.damage = int(ceil(float(result.damage) * 1.30))
		var force := mini(SkillSystem.force_power(), int(GameState.combat_state.mp))
		if force > 0:
			GameState.combat_state.mp -= force
			result.damage += int(round(float(force) * randf_range(0.75, 1.25)))
		if not attack_move.is_empty():
			var extra := int(floor(8.0 + maxi(0, int(attack_move.get("level", 0)) - int(attack_move.get("unlock", 0))) * 0.6))
			result.damage += extra
			if int(attack_move.get("unlock", 0)) in [20, 70] and randf() < 0.10 + float(int(attack_move.get("unlock", 0)) - 10) / 90.0 * 0.20:
				add_status(session, "enemy", "paralysis", randi_range(1, 3))
			elif int(attack_move.get("unlock", 0)) in [40, 80] and randf() < 0.10 + float(int(attack_move.get("unlock", 0)) - 10) / 90.0 * 0.20:
				add_status(session, "enemy", "weakness", randi_range(1, 3))
			elif int(attack_move.get("unlock", 0)) in [50, 90] and randf() < 0.10 + float(int(attack_move.get("unlock", 0)) - 10) / 90.0 * 0.20:
				add_status(session, "enemy", "poison", randi_range(1, 3))
		var wound := int(InventorySystem.equipment_bonus().get("woundInflict", 0))
		if wound > 0 and int(session.enemy_hp) > 0:
			session.enemy_max_hp = maxi(1, int(session.enemy_max_hp) - wound)
			session.enemy_hp = mini(int(session.enemy_hp), int(session.enemy_max_hp))
		session.enemy_hp = maxi(0, int(session.enemy_hp) - int(result.damage))
		session.log.append("你造成 %d 点%s伤害" % [result.damage, "暴击" if result.crit else ""])
	else:
		session.log.append("你的攻击未命中")
	return result

func enemy_attack(session: Dictionary) -> Dictionary:
	var turn_check := start_turn(session, "enemy")
	if not turn_check.can_act:
		return {"hit": false, "parried": false, "crit": false, "damage": 0, "skipped": true, "message": turn_check.message}
	var enemy_attributes: Dictionary = session.enemy.get("attributes", {})
	var player_attributes: Dictionary = GameState.profile.get("attributes", {})
	var enemy_dodge := _npc_move(session.enemy, "dodge")
	if not enemy_dodge.is_empty():
		session.log.append("%s 身形一晃避开了攻击" % session.enemy.get("displayName", "敌人"))
		return {"hit": false, "parried": false, "crit": false, "damage": 0, "dodged": true, "message": "敌方闪避"}
	var equipment := InventorySystem.equipment_bonus()
	var enemy_equipment := _npc_equipment_bonus(session.enemy)
	var result: Dictionary = GameState.resolve_attack(_enemy_attack_power(session.enemy), enemy_attributes, player_attributes, _player_defense(), (float(enemy_equipment.get("hit", 0))) * 0.01, (float(SkillSystem.combat_bonus().get("dodge", 0.0)) + float(equipment.get("dodge", 0))) * 0.01, float(equipment.get("parry", 0)) * 0.01, float(enemy_equipment.get("crit", 0)) * 0.01)
	if result.hit:
		var player_parry := SkillSystem.unlocked_moves().filter(func(move): return move.get("kind", "") == "parry")
		if not player_parry.is_empty() and randf() < minf(0.55, 0.25 + player_parry.size() * 0.04):
			var parry_move: Dictionary = player_parry[randi() % player_parry.size()]
			result.damage = int(floor(float(result.damage) * (1.0 - minf(0.35, 0.15 + maxi(0, int(parry_move.get("level", 0)) - int(parry_move.get("unlock", 0))) * 0.01))))
		if int(session.get("player_status", {}).get("weakness", 0)) > 0:
			result.damage = int(ceil(float(result.damage) * 1.30))
		GameState.combat_state.hp = maxi(0, int(GameState.combat_state.hp) - int(result.damage))
		session.player_hp = GameState.combat_state.hp
		_track_player_state(session)
		session.log.append("%s 造成 %d 点伤害" % [session.enemy.get("displayName", "敌人"), result.damage])
	return result

func _npc_move(npc: Dictionary, kind: String) -> Dictionary:
	var moves: Array = []
	var skill_levels: Dictionary = npc.get("skillLevels", {})
	for skill_id in npc.get("equippedSkillIds", []):
		var definition: Dictionary = DataRegistry.get_skill(str(skill_id))
		var theme_kind: String = str({"code": "attack", "tune": "dodge", "parry": "parry"}.get(str(definition.get("theme", "")), ""))
		if theme_kind != kind:
			continue
		var current := int(skill_levels.get(str(skill_id), 0))
		for move in definition.get("moves", []):
			if current >= int(move.get("unlockLevel", 0)):
				moves.append({"name": move.get("name", "招式"), "level": current, "unlock": int(move.get("unlockLevel", 0))})
	if moves.is_empty() or randf() >= minf(0.55, 0.25 + moves.size() * 0.04):
		return {}
	return moves[randi() % moves.size()]

func enemy_action(session: Dictionary) -> Dictionary:
	var hp := int(session.get("enemy_hp", 0))
	var hp_max := maxi(1, int(session.get("enemy_max_hp", hp)))
	var enemy_mp := int(session.get("enemy_mp", 0))
	var enemy_ults := _npc_ults(session.enemy)
	if not enemy_ults.is_empty() and enemy_mp >= int(enemy_ults[-1].get("mp_cost", 999)) and randf() < 0.35:
		return _enemy_use_ult(session, enemy_ults[-1])
	# NPCs use a conservative AI: recover when badly wounded and holding
	# enough inner power, otherwise perform the normal attack. This preserves
	# the old BattleController's non-player turn as a real decision point.
	if hp < int(floor(float(hp_max) * 0.30)) and enemy_mp >= 8 and hp < hp_max:
		var heal := mini(enemy_mp, hp_max - hp)
		session.enemy_hp = hp + heal
		session.enemy_mp = enemy_mp - heal
		session.log.append("%s 摸鱼恢复 %d 体力" % [session.enemy.get("displayName", "敌人"), heal])
		return {"ok": true, "rest": true, "damage": 0, "message": "敌方摸鱼恢复 %d 体力" % heal}
	return enemy_attack(session)

func _npc_ults(npc: Dictionary) -> Array:
	var result: Array = []
	var skill_levels: Dictionary = npc.get("skillLevels", {})
	for skill_id in npc.get("equippedSkillIds", []):
		var definition: Dictionary = DataRegistry.get_skill(str(skill_id))
		if str(definition.get("theme", "")) != "arch" or definition.get("ult", {}).is_empty():
			continue
		var level_value := int(skill_levels.get(str(skill_id), 0))
		var inner_power := int(skill_levels.get("basicConstitution", 0)) + level_value * 2
		var config: Dictionary = definition.get("ult", {})
		var kind := str(config.get("kind", "hugeDamage"))
		var costs: Dictionary = {"multi": [25, 45], "abnormal": [30, 50], "reduceMax": [35, 60], "hugeDamage": [40, 70]}
		var names: Array = config.get("names", ["绝招", "绝招"])
		if level_value >= 30:
			result.append({"name": names[0], "kind": kind, "tier": 1, "inner_power": inner_power, "mp_cost": costs.get(kind, [40, 70])[0]})
		if level_value >= 80:
			result.append({"name": names[1], "kind": kind, "tier": 2, "inner_power": inner_power, "mp_cost": costs.get(kind, [40, 70])[1]})
	return result

func _enemy_use_ult(session: Dictionary, ult: Dictionary) -> Dictionary:
	var turn_check := start_turn(session, "enemy")
	if not turn_check.can_act:
		return {"ok": false, "skipped": true, "damage": 0, "message": turn_check.message}
	var enemy_attributes: Dictionary = session.enemy.get("attributes", {})
	var player_attributes: Dictionary = GameState.profile.get("attributes", {})
	var cost := int(ult.get("mp_cost", 0))
	if int(session.enemy_mp) < cost:
		return enemy_attack(session)
	session.enemy_mp = int(session.enemy_mp) - cost
	var base_power := _enemy_attack_power(session.enemy)
	var kind := str(ult.get("kind", "hugeDamage"))
	var tier := int(ult.get("tier", 1))
	var total_damage := 0
	var landed := 0
	var defense := _player_defense()
	if kind == "multi":
		var hits := 3 if tier == 1 else 5
		for _index in hits:
			var hit := GameState.resolve_attack(base_power * (0.55 if tier == 1 else 0.50), enemy_attributes, player_attributes, defense)
			if hit.hit:
				landed += 1
				total_damage += int(hit.damage)
	elif kind == "abnormal":
		var abnormal := GameState.resolve_attack(base_power * (0.60 if tier == 1 else 0.70), enemy_attributes, player_attributes, defense)
		if abnormal.hit:
			landed = 1
			total_damage = int(abnormal.damage)
			if randf() < (0.80 if tier == 1 else 0.95):
				add_status(session, "player", "paralysis", 1 if tier == 1 else randi_range(1, 2))
	elif kind == "reduceMax":
		var reduced := GameState.resolve_attack(base_power * (0.55 if tier == 1 else 0.65), enemy_attributes, player_attributes, defense)
		if reduced.hit:
			landed = 1
			total_damage = int(reduced.damage)
			var ratio := 0.08 if tier == 1 else 0.15
			session.player_max_hp = maxi(1, int(floor(float(session.get("player_max_hp", _player_hp_max())) * (1.0 - ratio))))
			session.player_hp = mini(int(session.player_hp), int(session.player_max_hp))
	else:
		var huge := GameState.resolve_attack(base_power * (2.5 if tier == 1 else 4.0), enemy_attributes, player_attributes, defense)
		if huge.hit:
			landed = 1
			total_damage = int(huge.damage)
	GameState.combat_state.hp = maxi(0, int(GameState.combat_state.hp) - total_damage)
	session.player_hp = GameState.combat_state.hp
	_track_player_state(session)
	session.log.append("%s：%d 伤害" % [ult.get("name", "敌方绝招"), total_damage])
	return {"ok": true, "damage": total_damage, "landed": landed, "ult": ult}

func use_item(session: Dictionary, item_id: String) -> Dictionary:
	var result: Dictionary = InventorySystem.use_item(item_id)
	if result.ok:
		session.player_hp = GameState.combat_state.hp
		session.log.append(result.message)
	return result

func rest(session: Dictionary) -> Dictionary:
	var amount := mini(int(GameState.combat_state.mp), maxi(0, _player_hp_max() - int(GameState.combat_state.hp)))
	if amount <= 0:
		return {"ok": false, "message": "没有可用于摸鱼的精力"}
	GameState.combat_state.mp -= amount
	GameState.combat_state.hp += amount
	session.player_hp = GameState.combat_state.hp
	session.log.append("你偷偷摸了会鱼，消耗 %d 精力，恢复 %d 体力。" % [amount, amount])
	return {"ok": true, "message": "你偷偷摸了会鱼，消耗 %d 精力，恢复 %d 体力。" % [amount, amount], "amount": amount}

func start_turn(session: Dictionary, side: String) -> Dictionary:
	var status_key := "player_status" if side == "player" else "enemy_status"
	var statuses: Dictionary = session.get(status_key, {})
	var message := ""
	if int(statuses.get("poison", 0)) > 0:
		if side == "player":
			var poison_damage := maxi(1, int(floor(float(GameState.combat_state.hp) * 0.10)))
			GameState.combat_state.injury += poison_damage
			GameState.combat_state.hp = mini(int(GameState.combat_state.hp), maxi(1, int(GameState.combat_state.hp) - poison_damage))
			session.player_hp = GameState.combat_state.hp
		else:
			session.enemy_hp = maxi(1, int(session.enemy_hp) - maxi(1, int(floor(float(session.enemy_hp) * 0.10))))
		message = "中毒发作"
	var skipped := int(statuses.get("paralysis", 0)) > 0
	for status in statuses.keys():
		statuses[status] = int(statuses[status]) - 1
		if int(statuses[status]) <= 0:
			statuses.erase(status)
	session[status_key] = statuses
	if skipped:
		return {"can_act": false, "message": message + "，麻痹无法行动"}
	return {"can_act": true, "message": message}

func add_status(session: Dictionary, side: String, status: String, turns: int) -> void:
	var key := "player_status" if side == "player" else "enemy_status"
	var statuses: Dictionary = session.get(key, {})
	statuses[status] = maxi(int(statuses.get(status, 0)), turns)
	session[key] = statuses

func _track_player_state(session: Dictionary) -> void:
	var hp := int(GameState.combat_state.hp)
	var maximum := maxi(1, int(session.get("player_max_hp", _player_hp_max())))
	if hp <= 0:
		session.player_reached_zero = true
	elif hp <= int(floor(float(maximum) * 0.15)):
		session.player_near_death = true

func use_ult(session: Dictionary, ult_index: int = 0) -> Dictionary:
	var ults: Array = SkillSystem.unlocked_ults()
	if ult_index < 0 or ult_index >= ults.size():
		return {"ok": false, "message": "没有可用绝招"}
	var ult: Dictionary = ults[ult_index]
	var cost := int(ult.get("mp_cost", 0))
	if int(GameState.combat_state.get("mp", 0)) < cost:
		return {"ok": false, "message": "精力不足"}
	GameState.combat_state.mp = int(GameState.combat_state.mp) - cost
	var enemy_attributes: Dictionary = session.enemy.get("attributes", {})
	var base_power := _player_attack_power()
	var kind := str(ult.get("kind", "hugeDamage"))
	var total_damage := 0
	var landed := 0
	if kind == "multi":
		var hits := 3 if int(ult.tier) == 1 else 5
		for _index in hits:
			var hit: Dictionary = GameState.resolve_attack(base_power * (0.55 if int(ult.tier) == 1 else 0.50), GameState.profile.get("attributes", {}), enemy_attributes, float(enemy_attributes.get("constitution", 0)) * 2.0)
			if hit.hit:
				landed += 1
				total_damage += int(hit.damage)
	elif kind == "abnormal":
		var abnormal: Dictionary = GameState.resolve_attack(base_power * (0.60 if int(ult.tier) == 1 else 0.70), GameState.profile.get("attributes", {}), enemy_attributes, float(enemy_attributes.get("constitution", 0)) * 2.0)
		if abnormal.hit:
			landed = 1
			total_damage = int(abnormal.damage)
			if randf() < (0.80 if int(ult.tier) == 1 else 0.95): session.enemy_status.paralysis = 1 if int(ult.tier) == 1 else randi_range(1, 2)
	elif kind == "reduceMax":
		var reduced: Dictionary = GameState.resolve_attack(base_power * (0.55 if int(ult.tier) == 1 else 0.65), GameState.profile.get("attributes", {}), enemy_attributes, float(enemy_attributes.get("constitution", 0)) * 2.0)
		if reduced.hit:
			landed = 1
			total_damage = int(reduced.damage)
			var ratio := 0.08 if int(ult.tier) == 1 else 0.15
			session.enemy_max_hp = maxi(1, int(floor(float(session.enemy_max_hp) * (1.0 - ratio))))
			session.enemy_hp = mini(session.enemy_hp, session.enemy_max_hp)
	else:
		var huge: Dictionary = GameState.resolve_attack(base_power * (2.5 if int(ult.tier) == 1 else 4.0), GameState.profile.get("attributes", {}), enemy_attributes, float(enemy_attributes.get("constitution", 0)) * 2.0)
		if huge.hit:
			landed = 1
			total_damage = int(huge.damage)
	session.enemy_hp = maxi(0, int(session.enemy_hp) - total_damage)
	var log_line := "%s：%d 伤害" % [ult.get("name", "绝招"), total_damage]
	if kind == "multi": log_line += "（%d 击命中）" % landed
	session.log.append(log_line)
	return {"ok": true, "damage": total_damage, "landed": landed, "ult": ult}

func flee(session: Dictionary) -> bool:
	var self_attributes: Dictionary = GameState.profile.get("attributes", {})
	var enemy_attributes: Dictionary = session.enemy.get("attributes", {})
	var rate := clampf(FLEE_BASE + (float(self_attributes.get("agility", 0)) - float(enemy_attributes.get("agility", 0))) * FLEE_PER_AGILITY, 0.10, 0.90)
	return randf() < rate

func tick_status(session: Dictionary) -> void:
	for side in ["player_status", "enemy_status"]:
		var statuses: Dictionary = session.get(side, {})
		for status in statuses.keys():
			statuses[status] = int(statuses[status]) - 1
			if statuses[status] <= 0:
				statuses.erase(status)
		session[side] = statuses

func _initiative(player: Dictionary, enemy: Dictionary) -> bool:
	if int(player.get("agility", 0)) != int(enemy.get("agility", 0)):
		return int(player.get("agility", 0)) > int(enemy.get("agility", 0))
	return randf() >= 0.5

func _hp_max(attributes: Dictionary) -> int:
	return maxi(1, int(floor(140.0 * (1.0 + float(attributes.get("constitution", 0)) * 0.025))))

func _player_hp_max() -> int:
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	return maxi(1, int(floor(140.0 * (1.0 + float(attributes.get("constitution", 0)) * 0.025))) - int(GameState.combat_state.get("injury", 0)))

func _player_attack_power() -> float:
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	var bonus: Dictionary = SkillSystem.combat_bonus()
	return maxf(1.0, float(attributes.get("strength", 0)) + float(bonus.get("attack", 0.0)) + float(InventorySystem.equipment_bonus().get("attack", 0)))

func _player_defense() -> float:
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	return float(attributes.get("constitution", 0)) * 2.0 + float(SkillSystem.combat_bonus().get("defense", 0.0)) + float(InventorySystem.equipment_bonus().get("defense", 0))

func _enemy_attack_power(enemy: Dictionary) -> float:
	return maxf(1.0, float(enemy.get("attributes", {}).get("strength", 1)) + float(_npc_equipment_bonus(enemy).get("attack", 0)))

func _npc_equipment_bonus(npc: Dictionary) -> Dictionary:
	var total := {"attack": 0, "defense": 0, "hit": 0, "dodge": 0, "crit": 0, "woundInflict": 0, "parry": 0}
	for item_id in npc.get("equipment", []):
		var bonus: Dictionary = DataRegistry.get_item(str(item_id)).get("equipmentBonus", {})
		for key in total:
			total[key] = int(total[key]) + int(bonus.get(key, 0))
	return total
