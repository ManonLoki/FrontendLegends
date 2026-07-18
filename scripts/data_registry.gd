## 加载物品、人物、任务和技能 JSON，并一次扫描全部 TMX 地图的名称、类型和人物摆放，
## 让其他系统通过注册表查询，不在运行中重复读取文件。
extends Node

var items: Dictionary = {}
var vendor_stock: Dictionary = {}
var npcs: Dictionary = {}
var quests: Dictionary = {}
var quest_generators: Dictionary = {}
var skills: Dictionary = {}
var teach_stock: Dictionary = {}
var world_event_archetypes: Dictionary = {}
var world_event_placements: Dictionary = {}
var map_files: Array[String] = []
var map_ids_by_path: Dictionary = {}
var map_display_names: Dictionary = {}
var map_parent_ids: Dictionary = {}
var map_types: Dictionary = {}
var placed_npc_targets: Array[Dictionary] = []
var _placed_npc_keys: Dictionary = {}

func _ready() -> void:
	var item_catalog := _load_document("items.json")
	items = item_catalog.get("items", {})
	vendor_stock = item_catalog.get("vendorStock", {})
	npcs = _load_table("npcs.json", "npcs")
	var quest_catalog := _load_document("quests.json")
	quests = quest_catalog.get("quests", {})
	quest_generators = quest_catalog.get("generators", {})
	var skill_catalog := _load_document("skills.json")
	skills = skill_catalog.get("skills", {})
	teach_stock = skill_catalog.get("teachStock", {})
	var world_event_catalog := _load_document("world_events.json")
	world_event_archetypes = world_event_catalog.get("archetypes", {})
	_index_world_event_placements(world_event_catalog.get("placements", []))
	_index_maps(_load_document("maps.json").get("maps", {}))

func _load_table(file_name: String, key: String) -> Dictionary:
	return _load_document(file_name).get(key, {})

func _load_document(file_name: String) -> Dictionary:
	var file := FileAccess.open("res://assets/Data/" + file_name, FileAccess.READ)
	if not file:
		push_error("Missing data table: " + file_name)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func get_item(item_id: String) -> Dictionary:
	return items.get(item_id, {})

func get_npc(npc_id: String) -> Dictionary:
	return npcs.get(npc_id, {})

func get_quest(quest_id: String) -> Dictionary:
	return quests.get(quest_id, {})

func get_skill(skill_id: String) -> Dictionary:
	return skills.get(skill_id, {})

## 教学表随其余数据在 _ready 缓存；旧字符串条目在此统一升格为字典格式。
func get_teach_entries(npc_id: String) -> Array:
	var result: Array = []
	for entry in teach_stock.get(npc_id, []):
		if entry is String:
			result.append({"skillId": entry})
		elif entry is Dictionary and not str(entry.get("skillId", "")).is_empty():
			result.append(entry.duplicate(true))
	return result

func is_independent_tutor(npc_id: String) -> bool:
	return not get_teach_entries(npc_id).is_empty() and get_npc(npc_id).get("joinSect", {}).is_empty()

func list_vendor_stock(npc_id: String) -> Array:
	return vendor_stock.get(npc_id, [])

## 将数据表中的格子摆放升格为地图对象；TMX 因此不再保存事件文案和行为参数。
func world_event_objects(map_id: String, tile_width: int, tile_height: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for placement_value in world_event_placements.get(map_id, []):
		var placement: Dictionary = placement_value
		var archetype_id := str(placement.get("archetype", ""))
		var properties: Dictionary = world_event_archetypes.get(archetype_id, {}).duplicate(true)
		properties.merge(placement.get("data", {}), true)
		properties["worldEventId"] = str(placement.get("id", ""))
		var tile: Array = placement.get("tile", [0, 0])
		var size: Array = placement.get("size", [1, 1])
		result.append({
			"name": str(properties.get("displayName", "")),
			"type": "WorldEvent",
			"x": int(tile[0]) * tile_width,
			"y": int(tile[1]) * tile_height,
			"width": maxi(1, int(size[0])) * tile_width,
			"height": maxi(1, int(size[1])) * tile_height,
			"properties": properties,
		})
	return result

func _index_world_event_placements(placements: Array) -> void:
	var known_ids: Dictionary = {}
	for placement_value in placements:
		if not placement_value is Dictionary:
			continue
		var placement: Dictionary = placement_value
		var event_id := str(placement.get("id", ""))
		var map_id := str(placement.get("map", ""))
		var archetype_id := str(placement.get("archetype", ""))
		if event_id.is_empty() or map_id.is_empty() or not world_event_archetypes.has(archetype_id):
			push_error("Invalid world event placement: " + str(placement))
			continue
		if known_ids.has(event_id):
			push_error("Duplicate world event id: " + event_id)
			continue
		known_ids[event_id] = true
		if not world_event_placements.has(map_id):
			world_event_placements[map_id] = []
		world_event_placements[map_id].append(placement)

## maps.json 是 UUID 到 TMX 路径的维护索引；TMX 自身仍声明相同 mapId，启动时交叉校验。
func _index_maps(map_catalog: Dictionary) -> void:
	for map_id_value in map_catalog:
		var map_id := str(map_id_value)
		var definition: Dictionary = map_catalog[map_id_value]
		var map_path := str(definition.get("path", ""))
		var file := FileAccess.open(map_path, FileAccess.READ)
		var xml := file.get_as_text() if file else ""
		if map_id.is_empty() or map_path.is_empty() or xml.is_empty():
			push_error("Invalid map registry entry: " + map_id)
			continue
		var id_matcher := RegEx.new()
		id_matcher.compile("<property\\s+name=\"mapId\"\\s+value=\"([^\"]+)\"")
		var id_match := id_matcher.search(xml)
		if not id_match or id_match.get_string(1) != map_id:
			push_error("TMX mapId mismatch: " + map_path)
			continue
		map_files.append(map_path)
		map_ids_by_path[map_path] = map_id
		var map_name := str(definition.get("displayName", map_id))
		map_display_names[map_id] = map_name
		map_types[map_id] = str(definition.get("mapType", "outDoor"))
		var parent_map_id := str(definition.get("parentMapId", ""))
		if not parent_map_id.is_empty():
			map_parent_ids[map_id] = parent_map_id
		_collect_placed_npcs(xml, map_id, map_name)

## 把地图上的每个人物对象注册为任务目标；以人物 ID 与地图 ID 组合去重，
## 同一人物模板出现在不同地图时仍视为不同目标位置。
func _collect_placed_npcs(xml: String, map_id: String, map_name: String) -> void:
	var object_matcher := RegEx.new()
	object_matcher.compile("<object\\b([^>]*?)>([\\s\\S]*?)</object>")
	var attribute_matcher := RegEx.new()
	attribute_matcher.compile("\\b([A-Za-z_][A-Za-z0-9_-]*)=\"([^\"]*)\"")
	var npc_property_matcher := RegEx.new()
	npc_property_matcher.compile("<property\\b[^>]*\\bname=\"npcId\"[^>]*\\bvalue=\"([^\"]+)\"")
	for object_match in object_matcher.search_all(xml):
		var attributes: Dictionary = {}
		for attribute_match in attribute_matcher.search_all(object_match.get_string(1)):
			attributes[attribute_match.get_string(1)] = attribute_match.get_string(2)
		# 与原项目一致：带 gid 的对象是地图道具，不参与 NPC 任务目标池。
		if attributes.has("gid"):
			continue
		var property_match := npc_property_matcher.search(object_match.get_string(2))
		var npc_id := property_match.get_string(1) if property_match else str(attributes.get("name", ""))
		if npc_id.is_empty() or not npcs.has(npc_id):
			continue
		var key := npc_id + "@" + map_id
		if _placed_npc_keys.has(key):
			continue
		_placed_npc_keys[key] = true
		placed_npc_targets.append({"npc_id": npc_id, "map_id": map_id, "map_name": map_name})

func list_placed_npc_targets(exclude_ids: Array = []) -> Array[Dictionary]:
	var excluded: Dictionary = {}
	for npc_id in exclude_ids:
		excluded[str(npc_id)] = true
	var result: Array[Dictionary] = []
	for target in placed_npc_targets:
		if not excluded.has(str(target.get("npc_id", ""))):
			var copy := target.duplicate(true)
			copy["map_name"] = map_display_name(str(copy.get("map_id", "")))
			result.append(copy)
	return result

func map_display_name(map_id: String) -> String:
	var value := str(map_display_names.get(map_id, map_id))
	return value.replace("{playerName}", str(GameState.profile.get("name", "玩家")))

func map_id_at(index: int) -> String:
	if index < 0 or index >= map_files.size():
		return ""
	return str(map_ids_by_path.get(map_files[index], ""))

func map_type(map_id: String) -> String:
	return str(map_types.get(map_id, "outDoor"))

## 建筑内部等子区域通过 parentMap 指向所属大地图，使 HUD 与任务显示外部区域名称。
func region_display_name(map_id: String) -> String:
	var parent_id := str(map_parent_ids.get(map_id, ""))
	return map_display_name(parent_id if not parent_id.is_empty() else map_id)
