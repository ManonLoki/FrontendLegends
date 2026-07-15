extends Node

## 记录人物 ID 到复活游戏时刻的映射；使用全局游戏秒数而非现实时间，暂停模拟时冷却也暂停。
var defeated_until: Dictionary = {}
## 本局人物覆盖数据叠加在静态注册表之上，用于任务生成或临时移动；构建实例时合并，
## 不修改静态注册表，确保新会话始终从干净数据开始。
var runtime_npcs: Dictionary = {}
var sprite_regions: Dictionary = {}

# 初始化ready相关逻辑，并保持调用方状态一致。
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

# 处理region相关逻辑，并保持调用方状态一致。
func sprite_region(npc_id: String) -> Rect2:
	var sprite := str(build_instance(npc_id).get("sprite", "npc-1"))
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

# 处理dialogue相关逻辑，并保持调用方状态一致。
func dialogue(npc_id: String) -> String:
	var npc: Dictionary = build_instance(npc_id)
	return str(npc.get("defaultLine", "……"))

# 判断是否允许interact相关逻辑，并保持调用方状态一致。
func can_interact(npc_id: String) -> bool:
	return (runtime_npcs.has(npc_id) or not DataRegistry.get_npc(npc_id).is_empty()) and not is_defeated(npc_id)

# 注册runtime相关逻辑，并保持调用方状态一致。
func register_runtime(npc_id: String, definition: Dictionary) -> void:
	runtime_npcs[npc_id] = definition.duplicate(true)

# 处理runtime相关逻辑，并保持调用方状态一致。
func unregister_runtime(npc_id: String) -> void:
	runtime_npcs.erase(npc_id)

# 处理defeated相关逻辑，并保持调用方状态一致。
func mark_defeated(npc_id: String, duration_sec: float = 300.0) -> void:
	defeated_until[npc_id] = GameState.game_time_sec + duration_sec

# 清理defeated相关逻辑，并保持调用方状态一致。
func clear_defeated() -> void:
	defeated_until.clear()

## 读取击败状态时惰性清理到期记录；逐帧清扫只负责移除长期未被查询的过期项。
func is_defeated(npc_id: String) -> bool:
	if not defeated_until.has(npc_id):
		return false
	if GameState.game_time_sec >= float(defeated_until[npc_id]):
		defeated_until.erase(npc_id)
		return false
	return true

# 处理defeated相关逻辑，并保持调用方状态一致。
func sweep_defeated() -> void:
	for npc_id in defeated_until.keys():
		is_defeated(npc_id)

## 掉落采用反向查询：物品通过 dropNpcId 声明来源人物，使掉落规则只保存在物品定义旁边。
func get_drop_items(npc_id: String) -> Array:
	var result: Array = []
	for item_id in DataRegistry.items:
		if DataRegistry.items[item_id].get("dropNpcId", "") == npc_id:
			result.append(item_id)
	return result
