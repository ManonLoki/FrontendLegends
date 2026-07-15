extends Node

## Keyed by npc_id → the GameState.game_time_sec value at which the NPC respawns;
## expressed in game-clock seconds (not wall-clock) so defeat cooldowns pause with
## the rest of the simulation whenever the game clock itself is paused.
var defeated_until: Dictionary = {}
## Per-session overrides layered on top of DataRegistry's static NPC definitions
## (e.g. quest-spawned or relocated NPCs); build_instance() merges the two rather
## than mutating DataRegistry so a fresh session always starts from clean data.
var runtime_npcs: Dictionary = {}
var sprite_regions: Dictionary = {}

func _ready() -> void:
	_load_sprite_regions()

## Same TexturePacker-sheet format as player.tpsheet (scripts/game.gd); NPC and
## player atlases are parsed independently since they're separate source images.
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

## runtime_npcs takes priority over the static registry so per-session state (relocation,
## quest overrides) always wins; duplicate(true) protects the source dictionaries from
## mutation via the returned instance.
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

## Lazily expires entries on read rather than on a timer, so is_defeated() alone is
## enough to both check and self-clean the map; sweep_defeated() below just forces
## that cleanup once per frame so stale entries don't accumulate between checks.
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

## Reverse lookup: items declare their source NPC via dropNpcId rather than NPCs
## listing their own drops, so a single item's loot rule lives next to its own
## definition in items.json instead of being duplicated across NPC entries.
func get_drop_items(npc_id: String) -> Array:
	var result: Array = []
	for item_id in DataRegistry.items:
		if DataRegistry.items[item_id].get("dropNpcId", "") == npc_id:
			result.append(item_id)
	return result
