extends Node

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
		return {"ok": false, "message": "你没有这个物品"}
	var effects: Dictionary = definition.get("effects", {})
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	var changed := false
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	var capacity := 200 + int(attributes.get("strength", 25)) * 10
	for key in ["food", "water", "potential", "experience", "neigong"]:
		if not effects.has(key):
			continue
		var before := int(vitals.get(key, 0))
		var maximum := capacity if key in ["food", "water"] else 2147483647
		var after := clampi(before + int(effects[key]), 0, maximum)
		vitals[key] = after
		changed = changed or after != before
	if effects.has("hp"):
		var before_hp := int(GameState.combat_state.hp)
		GameState.combat_state.hp = mini(_hp_max(), before_hp + int(effects.hp))
		changed = changed or GameState.combat_state.hp != before_hp
	if effects.has("injury"):
		var before_injury := int(GameState.combat_state.injury)
		GameState.combat_state.injury = maxi(0, before_injury - int(effects.injury))
		changed = changed or GameState.combat_state.injury != before_injury
	if effects.has("appearance"):
		var before_appearance := int(vitals.get("appearance", 0))
		vitals.appearance = clampi(before_appearance + int(effects.appearance), 0, 100)
		changed = changed or vitals.appearance != before_appearance
	if definition.get("skillId", "") != "":
		var learn_result: Dictionary = SkillSystem.learn_from_book(str(definition.skillId))
		if not learn_result.ok:
			add_item(item_id)
			return learn_result
		changed = true
	if not changed:
		add_item(item_id)
		return {"ok": false, "message": "当前状态不需要使用%s" % definition.get("name", item_id)}
	var interval := float(definition.get("useIntervalSec", 0.0))
	if interval > 0.0:
		GameState.item_cooldowns[item_id] = GameState.game_time_sec + interval
	GameState.profile.vitals = vitals
	return {"ok": true, "message": "使用了 %s" % definition.get("name", item_id)}

func equip_item(item_id: String) -> Dictionary:
	var definition: Dictionary = DataRegistry.get_item(item_id)
	var slot := str(definition.get("slot", ""))
	if definition.get("kind", "") != "equip" or slot.is_empty():
		return {"ok": false, "message": "这不是可装备物品"}
	if count(item_id) <= 0:
		return {"ok": false, "message": "背包中没有该物品"}
	var actual_slot := slot
	var previous := ""
	if slot == "accessory":
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
	return {"ok": true, "message": "已装备 %s" % definition.get("name", item_id), "previous": previous, "slot": actual_slot}

func unequip(slot: String) -> Dictionary:
	var previous := str(GameState.equipment.get(slot, ""))
	if previous.is_empty():
		return {"ok": false, "message": "该部位没有装备"}
	GameState.equipment[slot] = ""
	return {"ok": true, "message": "已卸下 %s" % DataRegistry.get_item(previous).get("name", previous)}

func equipped_slot(item_id: String) -> String:
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
	var total := {"attack": 0, "defense": 0, "hit": 0, "dodge": 0, "crit": 0, "woundInflict": 0, "parry": 0}
	for item_id in GameState.equipment.values():
		var bonus: Dictionary = DataRegistry.get_item(str(item_id)).get("equipmentBonus", {})
		for key in total:
			total[key] = int(total[key]) + int(bonus.get(key, 0))
	return total

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
	var gain := int(floor(float(definition.get("price", 0)) * 0.25))
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
	if count(item_id) <= 0: return "你没有这个物品"
	if float(GameState.item_cooldowns.get(item_id, 0.0)) > GameState.game_time_sec: return str(definition.get("cooldownLine", "暂时还不能使用"))
	if definition.get("forbiddenGender", "") == GameState.profile.get("gender", ""): return str(definition.get("blockedLine", "你无法使用这个物品"))
	return "这个物品不能使用"

func list_entries(kind: String = "") -> Array:
	var result: Array = []
	for item_id in GameState.inventory:
		var definition: Dictionary = DataRegistry.get_item(item_id)
		if kind.is_empty() or definition.get("kind", "other") == kind:
			result.append({"id": item_id, "count": count(item_id), "definition": definition})
	return result

func _hp_max() -> int:
	return GameState.player_effective_hp_max()
