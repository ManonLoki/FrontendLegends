extends RefCounted
## 装备加成聚合的唯一口径；玩家侧（InventorySystem）与 NPC 侧（combat_rules）共用，
## 新增装备加成字段只需改这里。

static func sum_equipment_bonus(item_ids: Array) -> Dictionary:
	var total := {"attack": 0, "defense": 0, "hit": 0, "dodge": 0, "crit": 0, "woundInflict": 0, "parry": 0}
	for item_id in item_ids:
		var bonus: Dictionary = DataRegistry.get_item(str(item_id)).get("equipmentBonus", {})
		for key in total:
			total[key] = int(total[key]) + int(bonus.get(key, 0))
	return total

static func sum_attribute_bonus(item_ids: Array) -> Dictionary:
	var total := {"strength": 0, "agility": 0, "constitution": 0, "wisdom": 0}
	for item_id in item_ids:
		var bonus: Dictionary = DataRegistry.get_item(str(item_id)).get("attributes", {})
		for key in total:
			total[key] = int(total[key]) + maxi(0, int(bonus.get(key, 0)))
	return total
