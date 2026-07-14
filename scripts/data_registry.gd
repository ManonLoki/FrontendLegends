extends Node

var items: Dictionary = {}
var vendor_stock: Dictionary = {}
var npcs: Dictionary = {}
var quests: Dictionary = {}
var quest_generators: Dictionary = {}
var skills: Dictionary = {}
var map_files: Array[String] = []

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
	dir.list_dir_end()
