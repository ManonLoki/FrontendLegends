extends Node

const SKILL_MAPS := preload("res://scripts/skills/skill_maps.gd")
const EQUIPMENT_MATH := preload("res://scripts/equipment_math.gd")
## 售价统一按买价乘固定比例计算，不为每件物品单设字段，以保证所有商店差价一致。
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

## 使用物品时先暂扣数量，让后续类型分支只负责计算效果；若没有可生效内容
## （例如体力已满），再通过 add_item() 退回，避免为每种物品重复预判。
func use_item(item_id: String) -> Dictionary:
	var definition: Dictionary = DataRegistry.get_item(item_id)
	if not _can_use(item_id, definition):
		return {"ok": false, "message": _use_failure(item_id, definition)}
	if not remove_item(item_id):
		return {"ok": false, "message": "%s 数量不足。" % definition.get("name", item_id)}
	var effects: Dictionary = definition.get("effects", {})
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	var capacity := GameState.vitals_capacity(attributes)
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
		var learn_result: Dictionary = SkillSystem.learn_from_book(str(definition.skillId), int(definition.get("maxLearnLevel", DataRegistry.get_skill(str(definition.skillId)).get("maxLevel", 100))))
		result = learn_result
	if not bool(result.get("ok", false)):
		add_item(item_id)
		return result
	# 不消耗的可重复物品也走相同的“暂扣后退回”路径，使冷却和效果逻辑无需另设分支。
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
	for key in definition.get("requires", {}):
		if int(GameState.profile.get("attributes", {}).get(key, 0)) < int(definition.requires[key]):
			missing.append("%s ≥ %d" % [SKILL_MAPS.ATTRIBUTE_LABELS.get(str(key), str(key)), int(definition.requires[key])])
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
			# 两个饰品槽都占用时默认替换第二槽，优先保留最早装备的第一件饰品。
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
		return {"ok": false, "message": "该部位未曾穿戴。"}
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
		var definition: Dictionary = DataRegistry.get_item(item_id)
		return {"ok": false, "message": "%s 未曾穿戴。" % definition.get("name", item_id)}
	return unequip(slot)

func equipment_bonus() -> Dictionary:
	_normalize_equipment()
	return EQUIPMENT_MATH.sum_equipment_bonus(GameState.equipment.values())

func equipment_attribute_bonus() -> Dictionary:
	_normalize_equipment()
	return EQUIPMENT_MATH.sum_attribute_bonus(GameState.equipment.values())

## 清理已经不在背包中的装备引用，防止绕过卸下流程的出售或丢弃留下悬空状态。
func _normalize_equipment() -> void:
	for slot in GameState.equipment:
		var item_id := str(GameState.equipment[slot])
		if not item_id.is_empty() and count(item_id) <= 0:
			GameState.equipment[slot] = ""

func buy_item(npc_id: String, item_id: String) -> Dictionary:
	if item_id not in DataRegistry.list_vendor_stock(npc_id):
		return {"ok": false, "message": "此处不售此物。"}
	var definition: Dictionary = DataRegistry.get_item(item_id)
	if definition.is_empty():
		return {"ok": false, "message": "货单无效。"}
	var price := int(definition.get("price", 0))
	var vitals: Dictionary = GameState.profile.vitals
	if int(vitals.get("money", 0)) < price:
		return {"ok": false, "message": "Token 不足，%s 要价 %d。" % [definition.get("name", item_id), price]}
	if not add_item(item_id):
		return {"ok": false, "message": "背包已满"}
	vitals.money = int(vitals.get("money", 0)) - price
	GameState.profile.vitals = vitals
	return {"ok": true, "message": "买下%s，花费 %d Token。" % [definition.get("name", item_id), price]}

func sell_item(item_id: String) -> Dictionary:
	var definition: Dictionary = DataRegistry.get_item(item_id)
	if definition.is_empty():
		return {"ok": false, "message": "这不是我能收的东西。"}
	if definition.get("kind", "") == "quest" or definition.get("sellable", true) == false:
		return {"ok": false, "message": "%s 不能卖。" % definition.get("name", item_id)}
	if not remove_item(item_id):
		return {"ok": false, "message": "你没有%s。" % definition.get("name", item_id)}
	var gain := int(floor(float(definition.get("price", 0)) * SELL_PRICE_RATE))
	var vitals: Dictionary = GameState.profile.vitals
	vitals.money = int(vitals.get("money", 0)) + gain
	GameState.profile.vitals = vitals
	return {"ok": true, "message": "卖出%s，得 %d Token。" % [definition.get("name", item_id), gain]}

func discard_item(item_id: String) -> Dictionary:
	var definition: Dictionary = DataRegistry.get_item(item_id)
	if definition.is_empty() or str(definition.get("kind", "")) == "quest" or definition.get("discardable", true) == false:
		return {"ok": false, "message": "%s 不能丢弃。" % definition.get("name", item_id)}
	for slot in GameState.equipment:
		if str(GameState.equipment[slot]) == item_id:
			return {"ok": false, "message": "请先卸下装备再丢弃"}
	if not remove_item(item_id):
		return {"ok": false, "message": "你没有%s。" % definition.get("name", item_id)}
	return {"ok": true, "message": "丢弃了%s。" % definition.get("name", item_id)}

## 复用 use_item() 的效果白名单、冷却和性别检查，让菜单能在玩家确认前禁用无效物品。
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
	var item_ids: Array = GameState.inventory.keys()
	item_ids.sort()
	for item_id in item_ids:
		var definition: Dictionary = DataRegistry.get_item(item_id)
		if kind.is_empty() or definition.get("kind", "other") == kind:
			result.append({"id": item_id, "count": count(item_id), "definition": definition})
	return result
