extends Node

var items: Dictionary = {}
var vendor_stock: Dictionary = {}
var npcs: Dictionary = {}
var quests: Dictionary = {}
var quest_generators: Dictionary = {}
var skills: Dictionary = {}
var map_files: Array[String] = []
var map_display_names: Dictionary = {}
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
	skills = _load_table("skills.json", "skills")
	_scan_maps("res://assets/Map/maps")

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

func get_teach_entries(npc_id: String) -> Array:
	var catalog: Dictionary = _load_document("skills.json")
	var stock: Dictionary = catalog.get("teachStock", {})
	var result: Array = []
	for entry in stock.get(npc_id, []):
		if entry is String:
			result.append({"skillId": entry})
		elif entry is Dictionary and not str(entry.get("skillId", "")).is_empty():
			result.append(entry.duplicate(true))
	return result

func is_independent_tutor(npc_id: String) -> bool:
	return not get_teach_entries(npc_id).is_empty() and get_npc(npc_id).get("joinSect", {}).is_empty()

func list_vendor_stock(npc_id: String) -> Array:
	return vendor_stock.get(npc_id, [])

func _scan_maps(path: String) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue
		var child := path + "/" + name
		if dir.current_is_dir():
			_scan_maps(child)
		elif name.ends_with(".tmx"):
			map_files.append(child)
			var file := FileAccess.open(child, FileAccess.READ)
			var xml := file.get_as_text() if file else ""
			var matcher := RegEx.new()
			matcher.compile("<property\\s+name=\"mapName\"\\s+value=\"([^\"]*)\"")
			var matched := matcher.search(xml)
			var map_id := name.get_basename()
			var map_name := matched.get_string(1) if matched else map_id
			map_display_names[map_id] = map_name
			_collect_placed_npcs(xml, map_id, map_name)
	dir.list_dir_end()

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
