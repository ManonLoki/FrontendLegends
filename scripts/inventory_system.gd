extends Node

const SELL_PRICE_RATE := 0.25

func count(item_id: String) -> int:
	return int(GameState.inventory.get(item_id, 0))

func add_item(item_id: String, amount: int = 1) -> bool:
	var definition: Dictionary = DataRegistry.get_item(item_id)
	if definition.is_empty() or amount <= 0:
		return false
	var current := count(item_id)
	var limit := int(definition.get("stackLimit", 999))
	if current + amount > limit:
		return false
	GameState.inventory[item_id] = current + amount
	return true

func remove_item(item_id: String, amount: int = 1) -> bool:
	if amount <= 0 or count(item_id) < amount:
		return false
	GameState.inventory[item_id] = count(item_id) - amount
	if GameState.inventory[item_id] <= 0:
		GameState.inventory.erase(item_id)
	return true

func use_item(item_id: String) -> Dictionary:
	var definition: Dictionary = DataRegistry.get_item(item_id)
	if not _can_use(item_id, definition):
		return {"ok": false, "message": _use_failure(item_id, definition)}
	if not remove_item(item_id):
		return {"ok": false, "message": "%s 数量不足。" % definition.get("name", item_id)}
	var effects: Dictionary = definition.get("effects", {})
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	var capacity := 200 + int(attributes.get("strength", 25)) * 10
	var kind := str(definition.get("kind", ""))
	var result := {"ok": false, "message": "%s 不能直接使用。" % definition.get("name", item_id)}
	if kind in ["food", "water"]:
		var food_gain := maxi(0, int(effects.get("food", 0)))
		var water_gain := maxi(0, int(effects.get("water", 0)))
		if food_gain <= 0 and water_gain <= 0:
			result.message = "无效饮水。" if kind == "water" else "无效食物。"
		elif (food_gain <= 0 or int(vitals.get("food", 0)) >= capacity) and (water_gain <= 0 or int(vitals.get("water", 0)) >= capacity):
			result.message = "食物与饮水已满，无需使用。"
		else:
			if food_gain > 0:
				vitals.food = mini(capacity, int(vitals.get("food", 0)) + food_gain)
			if water_gain > 0:
				vitals.water = mini(capacity, int(vitals.get("water", 0)) + water_gain)
			var parts: Array[String] = []
			if food_gain > 0: parts.append("食物 +%d" % food_gain)
			if water_gain > 0: parts.append("饮水 +%d" % water_gain)
			result = {"ok": true, "message": "%s%s，%s。" % ["喝了" if kind == "water" else "吃了", definition.get("name", item_id), "，".join(parts)]}
	elif kind == "medicine":
		var hp_gain := maxi(0, int(effects.get("hp", 0)))
		var injury_heal := maxi(0, int(effects.get("injury", 0)))
		var appearance_gain := int(effects.get("appearance", 0))
		var effective_before := GameState.player_effective_hp_max()
		if hp_gain <= 0 and injury_heal <= 0 and appearance_gain == 0:
			result.message = "无效药品。"
		elif (hp_gain <= 0 or int(GameState.combat_state.hp) >= effective_before) and (injury_heal <= 0 or int(GameState.combat_state.injury) <= 0) and appearance_gain == 0:
			result.message = "体力已满，伤势已愈，无需用药。"
		else:
			GameState.combat_state.injury = maxi(0, int(GameState.combat_state.injury) - injury_heal)
			GameState.combat_state.hp = mini(GameState.player_effective_hp_max(), int(GameState.combat_state.hp) + hp_gain)
			vitals.appearance = clampi(int(vitals.get("appearance", 0)) + appearance_gain, 0, 100)
			var parts: Array[String] = []
			if hp_gain > 0: parts.append("体力 +%d" % hp_gain)
			if injury_heal > 0: parts.append("伤势 −%d" % injury_heal)
			if appearance_gain != 0: parts.append("容貌 %s%d" % ["+" if appearance_gain > 0 else "", appearance_gain])
			result = {"ok": true, "message": "服用了%s，%s。" % [definition.get("name", item_id), "，".join(parts)]}
	elif kind == "elixir":
		var appearance_gain := int(effects.get("appearance", 0))
		var potential_gain := int(effects.get("potential", 0))
		if appearance_gain == 0 and potential_gain == 0:
			result.message = "无效丹药。"
		else:
			vitals.appearance = clampi(int(vitals.get("appearance", 0)) + appearance_gain, 0, 100)
			vitals.potential = maxi(0, int(vitals.get("potential", 0)) + potential_gain)
			var parts: Array[String] = []
			if appearance_gain != 0: parts.append("容貌 %s%d" % ["+" if appearance_gain > 0 else "", appearance_gain])
			if potential_gain != 0: parts.append("潜能 %s%d" % ["+" if potential_gain > 0 else "", potential_gain])
			result = {"ok": true, "message": "服下%s，%s。" % [definition.get("name", item_id), "，".join(parts)]}
	elif kind == "book" and definition.get("skillId", "") != "":
		var learn_result: Dictionary = SkillSystem.learn_from_book(str(definition.skillId))
		result = learn_result
	if not bool(result.get("ok", false)):
		add_item(item_id)
		return result
	if definition.get("consumeOnUse", true) == false:
		add_item(item_id)
	var interval := float(definition.get("useIntervalSec", 0.0))
	if interval > 0.0:
		GameState.item_cooldowns[item_id] = GameState.game_time_sec + interval
	GameState.profile.vitals = vitals
	return result

func equip_item(item_id: String) -> Dictionary:
	var definition: Dictionary = DataRegistry.get_item(item_id)
	var slot := str(definition.get("slot", ""))
	if definition.get("kind", "") != "equip" or slot.is_empty():
		return {"ok": false, "message": "这不是能穿戴的装备。"}
	if count(item_id) <= 0:
		return {"ok": false, "message": "你没有%s。" % definition.get("name", item_id)}
	var missing: Array[String] = []
	var labels := {"strength": "编码", "agility": "思维", "constitution": "架构", "wisdom": "灵感"}
	for key in definition.get("requires", {}):
		if int(GameState.profile.get("attributes", {}).get(key, 0)) < int(definition.requires[key]):
			missing.append("%s ≥ %d" % [labels.get(str(key), str(key)), int(definition.requires[key])])
	if not missing.is_empty():
		return {"ok": false, "message": "穿戴%s需：%s。你资质未足，先练练再来。" % [definition.get("name", item_id), "、".join(missing)]}
	_normalize_equipment()
	var actual_slot := slot
	var previous := ""
	if slot == "accessory":
		if str(GameState.equipment.get("accessory1", "")) == item_id or str(GameState.equipment.get("accessory2", "")) == item_id:
			return {"ok": true, "message": "%s已穿戴。" % definition.get("name", item_id)}
		if str(GameState.equipment.get("accessory1", "")).is_empty():
			actual_slot = "accessory1"
		elif str(GameState.equipment.get("accessory2", "")).is_empty():
			actual_slot = "accessory2"
		else:
			actual_slot = "accessory2"
		previous = str(GameState.equipment.get(actual_slot, ""))
	else:
		previous = str(GameState.equipment.get(actual_slot, ""))
	GameState.equipment[actual_slot] = item_id
	if not previous.is_empty() and previous != item_id:
		return {"ok": true, "message": "换下%s，穿上了%s。" % [DataRegistry.get_item(previous).get("name", previous), definition.get("name", item_id)], "previous": previous, "slot": actual_slot}
	return {"ok": true, "message": "穿上了%s。" % definition.get("name", item_id), "previous": previous, "slot": actual_slot}

func unequip(slot: String) -> Dictionary:
	var previous := str(GameState.equipment.get(slot, ""))
	if previous.is_empty():
		return {"ok": false, "message": "该部位没有装备"}
	GameState.equipment[slot] = ""
	return {"ok": true, "message": "卸下了%s。" % DataRegistry.get_item(previous).get("name", previous)}

func equipped_slot(item_id: String) -> String:
	_normalize_equipment()
	for slot in GameState.equipment:
		if str(GameState.equipment[slot]) == item_id:
			return str(slot)
	return ""

func unequip_item(item_id: String) -> Dictionary:
	var slot := equipped_slot(item_id)
	if slot.is_empty():
		return {"ok": false, "message": "该物品没有装备"}
	return unequip(slot)

func equipment_bonus() -> Dictionary:
	_normalize_equipment()
	var total := {"attack": 0, "defense": 0, "hit": 0, "dodge": 0, "crit": 0, "woundInflict": 0, "parry": 0}
	for item_id in GameState.equipment.values():
		var bonus: Dictionary = DataRegistry.get_item(str(item_id)).get("equipmentBonus", {})
		for key in total:
			total[key] = int(total[key]) + int(bonus.get(key, 0))
	return total

func _normalize_equipment() -> void:
	for slot in GameState.equipment:
		var item_id := str(GameState.equipment[slot])
		if not item_id.is_empty() and count(item_id) <= 0:
			GameState.equipment[slot] = ""

func buy_item(npc_id: String, item_id: String) -> Dictionary:
	if item_id not in DataRegistry.list_vendor_stock(npc_id):
		return {"ok": false, "message": "该商贩不出售此物品"}
	var definition: Dictionary = DataRegistry.get_item(item_id)
	var price := int(definition.get("price", 0))
	var vitals: Dictionary = GameState.profile.vitals
	if int(vitals.get("money", 0)) < price:
		return {"ok": false, "message": "Token 不足"}
	if not add_item(item_id):
		return {"ok": false, "message": "背包已满"}
	vitals.money = int(vitals.get("money", 0)) - price
	GameState.profile.vitals = vitals
	return {"ok": true, "message": "购买了 %s" % definition.get("name", item_id)}

func sell_item(item_id: String) -> Dictionary:
	var definition: Dictionary = DataRegistry.get_item(item_id)
	if definition.is_empty() or definition.get("kind", "") == "quest" or definition.get("sellable", true) == false:
		return {"ok": false, "message": "该物品不可出售"}
	if not remove_item(item_id):
		return {"ok": false, "message": "背包中没有该物品"}
	var gain := int(floor(float(definition.get("price", 0)) * SELL_PRICE_RATE))
	var vitals: Dictionary = GameState.profile.vitals
	vitals.money = int(vitals.get("money", 0)) + gain
	GameState.profile.vitals = vitals
	return {"ok": true, "message": "出售获得 %d Token" % gain}

func discard_item(item_id: String) -> Dictionary:
	var definition: Dictionary = DataRegistry.get_item(item_id)
	if definition.is_empty() or str(definition.get("kind", "")) == "quest" or definition.get("discardable", true) == false:
		return {"ok": false, "message": "该物品不可丢弃"}
	for slot in GameState.equipment:
		if str(GameState.equipment[slot]) == item_id:
			return {"ok": false, "message": "请先卸下装备再丢弃"}
	if not remove_item(item_id):
		return {"ok": false, "message": "背包中没有该物品"}
	return {"ok": true, "message": "已丢弃 %s" % definition.get("name", item_id)}

func _can_use(item_id: String, definition: Dictionary) -> bool:
	if count(item_id) <= 0 or definition.is_empty():
		return false
	var deadline := float(GameState.item_cooldowns.get(item_id, 0.0))
	if deadline > GameState.game_time_sec:
		return false
	if definition.get("kind", "") not in ["food", "water", "medicine", "elixir", "book"]:
		return false
	if definition.get("forbiddenGender", "") == GameState.profile.get("gender", ""):
		return false
	return true

func _use_failure(item_id: String, definition: Dictionary) -> String:
	if definition.is_empty(): return "未知物品。"
	if definition.get("forbiddenGender", "") == GameState.profile.get("gender", ""): return str(definition.get("blockedLine", "这件东西不适合你使用。"))
	var remaining := ceili(float(GameState.item_cooldowns.get(item_id, 0.0)) - GameState.game_time_sec)
	if remaining > 0: return "%s（还需 %d 秒）" % [definition.get("cooldownLine", "还没到可以再次使用的时候。"), remaining]
	if count(item_id) <= 0: return "%s 数量不足。" % definition.get("name", item_id)
	return "%s 不能直接使用。" % definition.get("name", item_id)

func list_entries(kind: String = "") -> Array:
	var result: Array = []
	for item_id in GameState.inventory:
		var definition: Dictionary = DataRegistry.get_item(item_id)
		if kind.is_empty() or definition.get("kind", "other") == kind:
			result.append({"id": item_id, "count": count(item_id), "definition": definition})
	return result
