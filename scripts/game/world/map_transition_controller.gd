extends RefCounted
## 地图发现、加载、出生点选择与 Transaction 跳转。

const BGM_CONTROLLER := preload("res://scripts/game/audio/bgm_controller.gd")

var game: Node
var bgm_controller: RefCounted

func _init(owner: Node) -> void:
	game = owner
	bgm_controller = BGM_CONTROLLER.new(owner)

func load_initial_map() -> void:
	if DataRegistry.map_files.is_empty():
		return
	for index in DataRegistry.map_files.size():
		var candidate := TiledMapLoader.new()
		if candidate.load_file(DataRegistry.map_files[index]) and not candidate.spawn_point().is_empty():
			load_map(index)
			return
	load_map(0)

func load_map(index: int, arrival_from := "", cyber := false) -> void:
	if DataRegistry.map_files.is_empty() or game.map_transitioning:
		return
	game.map_transitioning = true
	var target_index := clampi(index, 0, DataRegistry.map_files.size() - 1)
	if OS.has_feature("web"):
		var pack_manager := game.get_node_or_null("/root/ContentPackManager")
		var target_map_id := DataRegistry.map_id_at(target_index)
		if not pack_manager or not await pack_manager.ensure_map_pack(target_map_id):
			push_warning("地图分包不可用：%s" % target_map_id)
			game.transition_overlay.color.a = 0.0
			game.message = "地图资源加载失败，请检查网络并重新进入游戏"
			game.queue_redraw()
			game.map_transitioning = false
			return
	if game.has_loaded_map:
		var fade_in := game.create_tween()
		fade_in.tween_property(game.transition_overlay, "color:a", 1.0, 0.12)
		await fade_in.finished
	game.map_index = target_index
	var next_context := TiledMapLoader.new()
	if not next_context.load_file(DataRegistry.map_files[game.map_index]):
		game.map_transitioning = false
		return
	next_context.inject_objects(DataRegistry.world_event_objects(next_context.map_id, next_context.tile_width, next_context.tile_height))
	game._close_dialogue()
	game.map_context = next_context
	game.map_renderer.set_context(game.map_context)
	bgm_controller.sync_for_map(game.map_context)
	var display_name := str(game.map_context.properties.get("mapName", game.map_context.map_id))
	game.map_badge.text = display_name.replace("{playerName}", str(GameState.profile.get("name", "")))
	game.transition_overlay.color.a = 1.0
	game.player_tile = Vector2i(8, 5)
	if not arrival_from.is_empty():
		var arrival: Dictionary = game.map_context.transaction_for_arrival(arrival_from, game.map_context.map_id, cyber)
		if not arrival.is_empty():
			game.player_tile = game.map_context.object_tile(arrival)
		elif cyber:
			var fallback_spawn: Dictionary = game.map_context.spawn_point()
			if not fallback_spawn.is_empty():
				game.player_tile = game.map_context.object_tile(fallback_spawn)
	else:
		var spawn: Dictionary = game.map_context.spawn_point()
		if not spawn.is_empty():
			game.player_tile = game.map_context.object_tile(spawn)
			_apply_spawn_facing(spawn)
	game.player_visual_tile = Vector2(game.player_tile)
	game.player_step_start = game.player_visual_tile
	game.player_step_elapsed = game.MOVE_STEP_SECONDS
	game.nearby_npc_id = ""
	game._refresh_nearby_npc()
	game.message = "已加载地图：%s（%dx%d）" % [game.map_context.properties.get("mapName", game.map_context.map_id), game.map_context.width, game.map_context.height]
	game._update_camera()
	game.queue_redraw()
	game.has_loaded_map = true
	var fade_out := game.create_tween()
	fade_out.tween_property(game.transition_overlay, "color:a", 0.0, 0.18)
	await fade_out.finished
	game.map_transitioning = false

func _apply_spawn_facing(spawn: Dictionary) -> void:
	match str(spawn.get("properties", {}).get("faceDir", "")).to_lower():
		"up": game.facing = Vector2i.UP
		"down": game.facing = Vector2i.DOWN
		"left": game.facing = Vector2i.LEFT
		"right": game.facing = Vector2i.RIGHT

func try_map_transition() -> void:
	if not game.map_context:
		return
	var object: Dictionary = game.map_context.object_at_tile(game.player_tile.x, game.player_tile.y)
	if object.is_empty() or object.get("type", "") != "Transaction":
		return
	var properties: Dictionary = object.get("properties", {})
	if str(properties.get("from", "")).to_lower() != game.map_context.map_id.to_lower():
		return
	var target := str(properties.get("to", ""))
	if target.is_empty():
		return
	var target_index := map_index_by_id(target)
	if target_index >= 0:
		load_map(target_index, game.map_context.map_id, false)

func map_index_by_id(target: String) -> int:
	var normalized_target := target.strip_edges().to_lower()
	for index in DataRegistry.map_files.size():
		var map_id := DataRegistry.map_id_at(index).to_lower()
		if map_id == normalized_target:
			return index
	return -1
