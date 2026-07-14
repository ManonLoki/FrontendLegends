extends Node

func resolve_victory(session: Dictionary, lethal: bool = true) -> String:
	var enemy_id := str(session.get("enemy_id", ""))
	var enemy: Dictionary = session.get("enemy", {})
	if lethal:
		_apply_lethal_wounds(session)
	var lines: Array[String] = []
	if not lethal:
		return "切磋结束：你在交流中获益，双方均未受致命伤。"
	var quest_line := QuestSystem.on_enemy_defeated(enemy_id)
	if not quest_line.is_empty():
		lines.append(quest_line)
	else:
		var money := int(enemy.get("money", 0))
		if money <= 0:
			money = maxi(0, int(ceil(_rating(enemy) / 3.0)))
		var vitals: Dictionary = GameState.profile.get("vitals", {})
		vitals.money = int(vitals.get("money", 0)) + money
		GameState.profile.vitals = vitals
		lines.append("击败强敌，获得 %d Token" % money)
	var drops := NpcSystem.get_drop_items(enemy_id)
	var gained: Array[String] = []
	for item_id in drops:
		if InventorySystem.add_item(item_id):
			gained.append(str(DataRegistry.get_item(item_id).get("name", item_id)))
	if not gained.is_empty():
		lines.append("拾获：%s" % "、".join(gained))
	NpcSystem.mark_defeated(enemy_id)
	return "\n".join(lines)

func resolve_defeat(session: Dictionary) -> String:
	_apply_lethal_wounds(session)
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	var money_loss := int(floor(float(vitals.get("money", 0)) * randf_range(0.05, 0.15)))
	var potential_loss := int(floor(float(vitals.get("potential", 0)) * randf_range(0.05, 0.15)))
	var experience_loss := int(floor(float(vitals.get("experience", 0)) * randf_range(0.10, 0.20)))
	vitals.money = maxi(0, int(vitals.get("money", 0)) - money_loss)
	vitals.potential = maxi(0, int(vitals.get("potential", 0)) - potential_loss)
	vitals.experience = maxi(0, int(vitals.get("experience", 0)) - experience_loss)
	var skill_loss := 0
	var levels: Dictionary = GameState.profile.get("skills", {}).get("levels", {})
	for skill_id in levels.keys():
		var current := int(levels[skill_id])
		if randf() < 0.5:
			var floor_level := 1 if str(skill_id).begins_with("basic") or str(skill_id) == "literacy" else 0
			var next := maxi(floor_level, current - randi_range(0, 2))
			if next < current:
				levels[skill_id] = next
				skill_loss += 1
	GameState.profile.vitals = vitals
	GameState.profile.skills.levels = levels
	GameState.combat_state.hp = _effective_hp_max()
	var suffix := "，%d 门功法生疏" % skill_loss if skill_loss > 0 else ""
	return "你重伤昏迷，醒来损失 Token %d、潜能 %d、经验 %d%s" % [money_loss, potential_loss, experience_loss, suffix]

func resolve_flee(session: Dictionary, lethal: bool = true) -> String:
	if not lethal:
		return "你收招退了下来。"
	_apply_lethal_wounds(session)
	return "你脱身遁走。" + (" 你在这场恶战中破了相。" if session.get("disfigurement", false) else "")

func _apply_lethal_wounds(session: Dictionary) -> void:
	var damage_taken := maxi(0, int(session.get("initial_player_hp", GameState.combat_state.hp)) - int(GameState.combat_state.hp))
	GameState.combat_state.injury = maxi(0, int(GameState.combat_state.injury) + int(ceil(damage_taken * 0.2)))
	var appearance_drops := 0
	if bool(session.get("player_reached_zero", false)) and randf() < 0.30:
		appearance_drops += 1
	if bool(session.get("player_near_death", false)) and randf() < 0.15:
		appearance_drops += 1
	if appearance_drops > 0:
		var vitals: Dictionary = GameState.profile.get("vitals", {})
		vitals.appearance = maxi(0, int(vitals.get("appearance", 0)) - appearance_drops * 20)
		GameState.profile.vitals = vitals
		session.disfigurement = true
	GameState.combat_state.hp = mini(_effective_hp_max(), int(GameState.combat_state.hp))

func _effective_hp_max() -> int:
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	var maximum := int(floor(140.0 * (1.0 + float(attributes.get("constitution", 0)) * 0.025)))
	return maxi(1, maximum - int(GameState.combat_state.get("injury", 0)))

func _rating(enemy: Dictionary) -> int:
	var levels: Dictionary = enemy.get("skillLevels", {})
	var total := 0
	for value in levels.values(): total += int(value)
	return maxi(1, int(floor(float(total) / maxi(1, levels.size()))))
