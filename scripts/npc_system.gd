extends Node

var defeated_until: Dictionary = {}
var runtime_npcs: Dictionary = {}
var sprite_regions: Dictionary = {}

func _ready() -> void:
	_load_sprite_regions()

func _load_sprite_regions() -> void:
	sprite_regions.clear()
	var file := FileAccess.open("res://assets/Texture/NPC.tpsheet", FileAccess.READ)
	if not file:
		return
	var sheet = JSON.parse_string(file.get_as_text())
	if not sheet is Dictionary:
		return
	var textures: Array = sheet.get("textures", [])
	if textures.is_empty():
		return
	for sprite_value in textures[0].get("sprites", []):
		var sprite: Dictionary = sprite_value
		var region: Dictionary = sprite.get("region", {})
		var key := str(sprite.get("filename", "")).get_file().get_basename()
		if not key.is_empty():
			sprite_regions[key] = Rect2(
				float(region.get("x", 0)), float(region.get("y", 0)),
				float(region.get("w", 0)), float(region.get("h", 0)),
			)

func sprite_region(npc_id: String) -> Rect2:
	var sprite := str(build_instance(npc_id).get("sprite", "npc-1"))
	return sprite_regions.get(sprite.get_file().get_basename(), sprite_regions.get("npc-1", Rect2(0, 0, 1, 1)))

func build_instance(npc_id: String, overrides: Dictionary = {}) -> Dictionary:
	var definition: Dictionary = runtime_npcs.get(npc_id, DataRegistry.get_npc(npc_id)).duplicate(true)
	if definition.is_empty():
		return {}
	for key in overrides:
		definition[key] = overrides[key]
	definition["npc_id"] = npc_id
	definition["display_name"] = definition.get("displayName", npc_id)
	return definition

func dialogue(npc_id: String) -> String:
	var npc: Dictionary = DataRegistry.get_npc(npc_id)
	return str(npc.get("defaultLine", "……"))

func can_interact(npc_id: String) -> bool:
	return (runtime_npcs.has(npc_id) or not DataRegistry.get_npc(npc_id).is_empty()) and not is_defeated(npc_id)

func register_runtime(npc_id: String, definition: Dictionary) -> void:
	runtime_npcs[npc_id] = definition.duplicate(true)

func unregister_runtime(npc_id: String) -> void:
	runtime_npcs.erase(npc_id)

func mark_defeated(npc_id: String, duration_sec: float = 300.0) -> void:
	defeated_until[npc_id] = GameState.game_time_sec + duration_sec

func is_defeated(npc_id: String) -> bool:
	if not defeated_until.has(npc_id):
		return false
	if GameState.game_time_sec >= float(defeated_until[npc_id]):
		defeated_until.erase(npc_id)
		return false
	return true

func sweep_defeated() -> void:
	for npc_id in defeated_until.keys():
		is_defeated(npc_id)

func get_drop_items(npc_id: String) -> Array:
	var result: Array = []
	for item_id in DataRegistry.items:
		if DataRegistry.items[item_id].get("dropNpcId", "") == npc_id:
			result.append(item_id)
	return result
