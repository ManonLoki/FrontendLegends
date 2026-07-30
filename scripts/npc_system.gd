extends Node

## 静态人物的击败后果写入角色世界状态；动态任务人物只保留本局冷却，避免把临时 ID 写进存档。
const DEFAULT_RESPAWN_SECONDS := 300.0
var runtime_defeated_until: Dictionary = {}
## 本局人物覆盖数据叠加在静态注册表之上，用于任务生成或临时移动；构建实例时合并，
## 不修改静态注册表，确保新会话始终从干净数据开始。
var runtime_npcs: Dictionary = {}
var sprite_regions: Dictionary = {}

func _ready() -> void:
	_load_sprite_regions()

## 人物图集与玩家图集使用相同的 TexturePacker 表格式，但因源图片不同而独立解析。
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

## 每帧绘制的热路径：只读定义中的 sprite 字段，不经过 build_instance 的深复制。
func sprite_region(npc_id: String) -> Rect2:
	return sprite_region_for_instance(runtime_npcs.get(npc_id, DataRegistry.get_npc(npc_id)))

## 直接按人物快照解析形象，使动态任务人物和运行时覆盖不会退回临时 ID 的默认头像。
func sprite_region_for_instance(npc: Dictionary) -> Rect2:
	var sprite := str(npc.get("sprite", "npc-1"))
	return sprite_regions.get(sprite.get_file().get_basename(), sprite_regions.get("npc-1", Rect2(0, 0, 1, 1)))

## 本局覆盖数据优先于静态注册表，深复制结果防止调用方通过人物实例修改源字典。
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
	var npc: Dictionary = build_instance(npc_id)
	var line := str(npc.get("defaultLine", "……"))
	if defeat_count(npc_id) > 0:
		var rematch_line := str(npc.get("rematchLine", "上次是我大意了，这次可没那么容易。"))
		return "%s\n%s" % [rematch_line, line]
	return line

func can_interact(npc_id: String) -> bool:
	return (runtime_npcs.has(npc_id) or not DataRegistry.get_npc(npc_id).is_empty()) and not is_defeated(npc_id)

func register_runtime(npc_id: String, definition: Dictionary) -> void:
	runtime_npcs[npc_id] = definition.duplicate(true)

func unregister_runtime(npc_id: String) -> void:
	runtime_npcs.erase(npc_id)

func mark_defeated(npc_id: String, duration_sec: float = DEFAULT_RESPAWN_SECONDS) -> Dictionary:
	var until := GameState.game_time_sec + maxf(0.0, duration_sec)
	if DataRegistry.get_npc(npc_id).is_empty():
		runtime_defeated_until[npc_id] = until
		return {"until": until, "count": 1, "persistent": false}
	var world := _world_state()
	var defeated: Dictionary = world.get("defeated_until", {})
	var counts: Dictionary = world.get("defeat_counts", {})
	defeated[npc_id] = until
	counts[npc_id] = int(counts.get(npc_id, 0)) + 1
	world.defeated_until = defeated
	world.defeat_counts = counts
	world.last_defeated_npc_id = npc_id
	world.last_defeated_at = GameState.game_time_sec
	GameState.profile.world_state = world
	return {"until": until, "count": int(counts[npc_id]), "persistent": true}

func clear_defeated() -> void:
	clear_runtime_defeated()
	if GameState.profile.is_empty():
		return
	var world := _world_state()
	world.defeated_until = {}
	world.defeat_counts = {}
	world.erase("last_defeated_npc_id")
	world.erase("last_defeated_at")
	GameState.profile.world_state = world

## 场景或角色重置时只清除动态任务人物的本局状态，不触碰角色存档中的静态人物后果。
func clear_runtime_defeated() -> void:
	runtime_defeated_until.clear()

## 读取击败状态时惰性清理到期记录；逐帧清扫只负责移除长期未被查询的过期项。
func is_defeated(npc_id: String) -> bool:
	if runtime_defeated_until.has(npc_id):
		if GameState.game_time_sec < float(runtime_defeated_until[npc_id]):
			return true
		runtime_defeated_until.erase(npc_id)
	var world := _world_state(false)
	var defeated: Dictionary = world.get("defeated_until", {})
	if not defeated.has(npc_id):
		return false
	if GameState.game_time_sec < float(defeated[npc_id]):
		return true
	defeated.erase(npc_id)
	world.defeated_until = defeated
	GameState.profile.world_state = world
	return false

func sweep_defeated() -> void:
	for npc_id in runtime_defeated_until.keys():
		is_defeated(npc_id)
	var defeated: Dictionary = _world_state(false).get("defeated_until", {})
	for npc_id in defeated.keys():
		is_defeated(npc_id)

func defeat_count(npc_id: String) -> int:
	return maxi(0, int(_world_state(false).get("defeat_counts", {}).get(npc_id, 0)))

func consequence_summary(npc_id: String) -> String:
	var count := defeat_count(npc_id)
	return "与你的战绩：落败 %d 次" % count if count > 0 else ""

func _world_state(create := true) -> Dictionary:
	if GameState.profile.is_empty():
		return {}
	var raw = GameState.profile.get("world_state", {})
	var world: Dictionary = raw if raw is Dictionary else {}
	if create and not GameState.profile.has("world_state"):
		GameState.profile.world_state = world
	return world

## 掉落采用反向查询：物品通过 dropNpcId 声明来源人物，使掉落规则只保存在物品定义旁边。
func get_drop_items(npc_id: String) -> Array:
	var result: Array = []
	for item_id in DataRegistry.items:
		if DataRegistry.items[item_id].get("dropNpcId", "") == npc_id:
			result.append(item_id)
	return result
